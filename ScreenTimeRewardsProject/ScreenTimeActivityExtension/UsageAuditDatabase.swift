import Foundation
import SQLite3

// SQLITE_TRANSIENT constant for Swift - tells SQLite to copy the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe, lightweight SQLite wrapper for extension usage audit log.
/// This is the SOURCE OF TRUTH for usage data - append-only, never corrupted.
/// UserDefaults can be repaired from this database if corruption is detected.
final class UsageAuditDatabase {
    static let shared = UsageAuditDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.screentimerewards.usageaudit", qos: .utility)
    private let appGroupIdentifier = "group.com.screentimerewards.shared"

    // MARK: - Initialization

    private init() {
        openDatabase()
        createTablesIfNeeded()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            debugLog("AUDIT_DB: Failed to get App Group container URL")
            return
        }

        let supportDir = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)

        // Create directory if needed
        do {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        } catch {
            debugLog("AUDIT_DB: Failed to create support directory: \(error)")
            return
        }

        let dbPath = supportDir.appendingPathComponent("usage_audit.sqlite").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            debugLog("AUDIT_DB: Failed to open database: \(errorMsg)")
            db = nil
        } else {
            debugLog("AUDIT_DB: Opened database at \(dbPath)")

            // Enable WAL mode for better performance and reliability
            executeSQL("PRAGMA journal_mode=WAL")
            executeSQL("PRAGMA synchronous=NORMAL")
        }
    }

    private func createTablesIfNeeded() {
        guard db != nil else { return }

        // Main audit log - append-only, never modified
        let createUsageEvents = """
        CREATE TABLE IF NOT EXISTS usage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_logical_id TEXT NOT NULL,
            seconds_added INTEGER NOT NULL,
            threshold_minute INTEGER NOT NULL,
            event_date TEXT NOT NULL,
            event_timestamp REAL NOT NULL,
            session_id TEXT NOT NULL,
            created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
        )
        """

        // Cached aggregates - can be rebuilt from usage_events
        let createDailyTotals = """
        CREATE TABLE IF NOT EXISTS daily_totals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_logical_id TEXT NOT NULL,
            event_date TEXT NOT NULL,
            total_seconds INTEGER NOT NULL,
            last_threshold_minute INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(app_logical_id, event_date)
        )
        """

        // Validation checkpoints
        let createSyncCheckpoints = """
        CREATE TABLE IF NOT EXISTS sync_checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            checkpoint_type TEXT NOT NULL,
            checkpoint_timestamp REAL NOT NULL,
            data_hash TEXT,
            created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
        )
        """

        // Indexes for fast lookups
        let createIndexAppDate = """
        CREATE INDEX IF NOT EXISTS idx_usage_events_app_date
        ON usage_events(app_logical_id, event_date)
        """

        let createIndexDate = """
        CREATE INDEX IF NOT EXISTS idx_usage_events_date
        ON usage_events(event_date)
        """

        let createIndexDailyDate = """
        CREATE INDEX IF NOT EXISTS idx_daily_totals_date
        ON daily_totals(event_date)
        """

        executeSQL(createUsageEvents)
        executeSQL(createDailyTotals)
        executeSQL(createSyncCheckpoints)
        executeSQL(createIndexAppDate)
        executeSQL(createIndexDate)
        executeSQL(createIndexDailyDate)
    }

    // MARK: - Core Operations

    /// Record a usage event (append-only, never fails silently)
    /// Returns true if recorded successfully, false otherwise
    func recordUsageEvent(
        appLogicalID: String,
        secondsAdded: Int,
        thresholdMinute: Int,
        date: String,
        sessionID: String
    ) -> Bool {
        guard let db = db else {
            debugLog("AUDIT_DB: Cannot record - database not open")
            return false
        }

        var success = false
        queue.sync {
            let timestamp = Date().timeIntervalSince1970

            // 1. Check if this exact threshold minute was already recorded today
            //    (deduplication at database level)
            let checkSQL = """
            SELECT COUNT(*) FROM usage_events
            WHERE app_logical_id = ? AND event_date = ? AND threshold_minute = ?
            """

            var checkStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStmt, 1, appLogicalID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(checkStmt, 2, date, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(checkStmt, 3, Int32(thresholdMinute))

                if sqlite3_step(checkStmt) == SQLITE_ROW {
                    let count = sqlite3_column_int(checkStmt, 0)
                    if count > 0 {
                        debugLog("AUDIT_DB: DUPLICATE threshold_minute=\(thresholdMinute) for \(appLogicalID.prefix(8))... on \(date) - skipping")
                        sqlite3_finalize(checkStmt)
                        return
                    }
                }
                sqlite3_finalize(checkStmt)
            }

            // 2. Insert the event
            let insertSQL = """
            INSERT INTO usage_events
            (app_logical_id, seconds_added, threshold_minute, event_date, event_timestamp, session_id)
            VALUES (?, ?, ?, ?, ?, ?)
            """

            var insertStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStmt, 1, appLogicalID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(insertStmt, 2, Int32(secondsAdded))
                sqlite3_bind_int(insertStmt, 3, Int32(thresholdMinute))
                sqlite3_bind_text(insertStmt, 4, date, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(insertStmt, 5, timestamp)
                sqlite3_bind_text(insertStmt, 6, sessionID, -1, SQLITE_TRANSIENT)

                if sqlite3_step(insertStmt) == SQLITE_DONE {
                    debugLog("AUDIT_DB: RECORDED \(appLogicalID.prefix(8))... +\(secondsAdded)s min=\(thresholdMinute) date=\(date)")
                    success = true
                } else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    debugLog("AUDIT_DB: INSERT FAILED: \(errorMsg)")
                }
                sqlite3_finalize(insertStmt)
            }

            // 3. Update daily_totals cache (upsert)
            if success {
                updateDailyTotal(appLogicalID: appLogicalID, date: date, thresholdMinute: thresholdMinute)
            }
        }

        return success
    }

    /// Get total seconds for an app on a specific date (from audit log, not cache)
    func getTotalSeconds(appLogicalID: String, date: String) -> Int {
        guard let db = db else { return 0 }

        var total = 0
        queue.sync {
            let sql = """
            SELECT SUM(seconds_added) FROM usage_events
            WHERE app_logical_id = ? AND event_date = ?
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, appLogicalID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, date, -1, SQLITE_TRANSIENT)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
        }
        return total
    }

    /// Get the highest threshold minute recorded for an app on a date
    func getLastThresholdMinute(appLogicalID: String, date: String) -> Int {
        guard let db = db else { return 0 }

        var lastMinute = 0
        queue.sync {
            let sql = """
            SELECT MAX(threshold_minute) FROM usage_events
            WHERE app_logical_id = ? AND event_date = ?
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, appLogicalID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, date, -1, SQLITE_TRANSIENT)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    lastMinute = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
        }
        return lastMinute
    }

    /// Get all app IDs with usage on a specific date
    func getAppsWithUsage(date: String) -> [String] {
        guard let db = db else { return [] }

        var appIDs: [String] = []
        queue.sync {
            let sql = """
            SELECT DISTINCT app_logical_id FROM usage_events
            WHERE event_date = ?
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, date, -1, SQLITE_TRANSIENT)

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let appIDPtr = sqlite3_column_text(stmt, 0) {
                        appIDs.append(String(cString: appIDPtr))
                    }
                }
                sqlite3_finalize(stmt)
            }
        }
        return appIDs
    }

    /// Get daily totals for all apps on a date (from cache table for efficiency)
    func getDailyTotals(date: String) -> [(appLogicalID: String, totalSeconds: Int, lastThreshold: Int)] {
        guard let db = db else { return [] }

        var totals: [(String, Int, Int)] = []
        queue.sync {
            let sql = """
            SELECT app_logical_id, total_seconds, last_threshold_minute
            FROM daily_totals WHERE event_date = ?
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, date, -1, SQLITE_TRANSIENT)

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let appIDPtr = sqlite3_column_text(stmt, 0) {
                        let appID = String(cString: appIDPtr)
                        let seconds = Int(sqlite3_column_int(stmt, 1))
                        let threshold = Int(sqlite3_column_int(stmt, 2))
                        totals.append((appID, seconds, threshold))
                    }
                }
                sqlite3_finalize(stmt)
            }
        }
        return totals
    }

    // MARK: - Validation

    /// Validation discrepancy between UserDefaults and database
    struct ValidationDiscrepancy {
        let appID: String
        let date: String
        let userDefaultsValue: Int
        let databaseValue: Int
        var difference: Int { abs(userDefaultsValue - databaseValue) }
    }

    /// Validate UserDefaults against database
    func validateAgainstUserDefaults(defaults: UserDefaults) -> [ValidationDiscrepancy] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        var discrepancies: [ValidationDiscrepancy] = []

        // Get all apps with database records for today
        let dbApps = getAppsWithUsage(date: today)

        for appID in dbApps {
            let dbSeconds = getTotalSeconds(appLogicalID: appID, date: today)
            let udKey = "ext_usage_\(appID)_today"
            let udSeconds = defaults.integer(forKey: udKey)
            let udDate = defaults.string(forKey: "ext_usage_\(appID)_date")

            // Only compare if UserDefaults is for today
            if udDate == today && udSeconds != dbSeconds {
                discrepancies.append(ValidationDiscrepancy(
                    appID: appID,
                    date: today,
                    userDefaultsValue: udSeconds,
                    databaseValue: dbSeconds
                ))
            }
        }

        return discrepancies
    }

    /// Repair UserDefaults from database (source of truth)
    func repairUserDefaults(defaults: UserDefaults) {
        let discrepancies = validateAgainstUserDefaults(defaults: defaults)

        for d in discrepancies {
            let key = "ext_usage_\(d.appID)_today"
            defaults.set(d.databaseValue, forKey: key)
            debugLog("AUDIT_DB: REPAIRED \(d.appID.prefix(8))... \(d.userDefaultsValue) -> \(d.databaseValue)")
        }

        if !discrepancies.isEmpty {
            defaults.set(Date().timeIntervalSince1970, forKey: "audit_db_last_repair")
            defaults.set(discrepancies.count, forKey: "audit_db_repair_count")
        }
    }

    /// Record a validation checkpoint
    func recordCheckpoint(type: String, dataHash: String? = nil) {
        guard let db = db else { return }

        queue.sync {
            let sql = """
            INSERT INTO sync_checkpoints (checkpoint_type, checkpoint_timestamp, data_hash)
            VALUES (?, ?, ?)
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, type, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                if let hash = dataHash {
                    sqlite3_bind_text(stmt, 3, hash, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Maintenance

    /// Rebuild daily_totals cache from usage_events (use if cache is corrupted)
    func rebuildDailyTotals() {
        guard let db = db else { return }

        queue.sync {
            // Clear existing cache
            executeSQL("DELETE FROM daily_totals")

            // Rebuild from audit log
            let sql = """
            INSERT INTO daily_totals (app_logical_id, event_date, total_seconds, last_threshold_minute, updated_at)
            SELECT
                app_logical_id,
                event_date,
                SUM(seconds_added),
                MAX(threshold_minute),
                strftime('%s', 'now')
            FROM usage_events
            GROUP BY app_logical_id, event_date
            """
            executeSQL(sql)
            debugLog("AUDIT_DB: Rebuilt daily_totals from audit log")
        }
    }

    /// Delete old events (cleanup, keep last N days)
    func pruneOldEvents(keepDays: Int = 90) {
        guard let db = db else { return }

        queue.sync {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let cutoff = dateFormatter.string(from: cutoffDate)

            let sql = "DELETE FROM usage_events WHERE event_date < ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            // Also clean daily_totals
            let sql2 = "DELETE FROM daily_totals WHERE event_date < ?"
            if sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            debugLog("AUDIT_DB: Pruned events older than \(cutoff)")
        }
    }

    /// Check if database is available and healthy
    var isAvailable: Bool {
        return db != nil
    }

    /// Get event count for diagnostics
    func getEventCount(date: String? = nil) -> Int {
        guard let db = db else { return 0 }

        var count = 0
        queue.sync {
            let sql: String
            if let date = date {
                sql = "SELECT COUNT(*) FROM usage_events WHERE event_date = '\(date)'"
            } else {
                sql = "SELECT COUNT(*) FROM usage_events"
            }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
        }
        return count
    }

    // MARK: - Private Helpers

    private func updateDailyTotal(appLogicalID: String, date: String, thresholdMinute: Int) {
        guard let db = db else { return }

        // Get current total from audit log
        let total = getTotalSeconds(appLogicalID: appLogicalID, date: date)

        // Upsert into daily_totals
        let sql = """
        INSERT INTO daily_totals (app_logical_id, event_date, total_seconds, last_threshold_minute, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(app_logical_id, event_date)
        DO UPDATE SET total_seconds = ?, last_threshold_minute = MAX(last_threshold_minute, ?), updated_at = ?
        """

        let now = Date().timeIntervalSince1970
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, appLogicalID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, date, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(total))
            sqlite3_bind_int(stmt, 4, Int32(thresholdMinute))
            sqlite3_bind_double(stmt, 5, now)
            sqlite3_bind_int(stmt, 6, Int32(total))
            sqlite3_bind_int(stmt, 7, Int32(thresholdMinute))
            sqlite3_bind_double(stmt, 8, now)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    private func executeSQL(_ sql: String) {
        guard let db = db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                debugLog("AUDIT_DB: SQL error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    private func debugLog(_ message: String) {
        // Write to shared UserDefaults for visibility
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = formatter.string(from: Date())
            let entry = "[\(timestamp)][SQLITE] \(message)"

            var log = defaults.string(forKey: "extension_debug_log") ?? ""
            let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
            let trimmedLines = Array(lines.suffix(499))
            log = (trimmedLines + [entry]).joined(separator: "\n")
            defaults.set(log, forKey: "extension_debug_log")
        }
    }
}
