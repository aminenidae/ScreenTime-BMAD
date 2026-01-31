import Foundation
import SQLite3

// SQLITE_TRANSIENT constant for Swift - tells SQLite to copy the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Validates usage data integrity between UserDefaults (cache) and SQLite audit log (source of truth).
/// Used by the main app to detect and repair data corruption on launch.
@MainActor
final class UsageIntegrityValidator {
    static let shared = UsageIntegrityValidator()

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private var db: OpaquePointer?

    // MARK: - Validation Result

    struct ValidationResult {
        let discrepancies: [Discrepancy]
        let wasRepaired: Bool
        let totalEventsInDB: Int
        let validationTimestamp: Date

        var hasDiscrepancies: Bool { !discrepancies.isEmpty }
    }

    struct Discrepancy {
        let appID: String
        let date: String
        let userDefaultsValue: Int
        let databaseValue: Int
        var difference: Int { abs(userDefaultsValue - databaseValue) }
        var isInflated: Bool { userDefaultsValue > databaseValue }
    }

    // MARK: - Initialization

    private init() {
        openDatabase()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    /// Validate usage data integrity on app launch/foreground
    /// Returns validation result with any discrepancies found and repair status
    func validateUsageDataIntegrity(autoRepair: Bool = true) -> ValidationResult {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return ValidationResult(
                discrepancies: [],
                wasRepaired: false,
                totalEventsInDB: 0,
                validationTimestamp: Date()
            )
        }

        let discrepancies = findDiscrepancies(defaults: defaults)
        var wasRepaired = false

        if !discrepancies.isEmpty {
            logDiscrepancies(discrepancies)

            if autoRepair {
                repairFromDatabase(discrepancies: discrepancies, defaults: defaults)
                wasRepaired = true
            }
        }

        let eventCount = getEventCount()

        // Record validation checkpoint
        defaults.set(Date().timeIntervalSince1970, forKey: "usage_integrity_last_validated")
        defaults.set(discrepancies.count, forKey: "usage_integrity_discrepancy_count")
        defaults.set(wasRepaired, forKey: "usage_integrity_was_repaired")

        return ValidationResult(
            discrepancies: discrepancies,
            wasRepaired: wasRepaired,
            totalEventsInDB: eventCount,
            validationTimestamp: Date()
        )
    }

    /// Check if database is available and has data
    var isDatabaseAvailable: Bool {
        return db != nil
    }

    /// Get summary statistics for diagnostics
    func getDatabaseStats() -> (totalEvents: Int, uniqueApps: Int, oldestDate: String?, newestDate: String?) {
        guard let db = db else { return (0, 0, nil, nil) }

        var totalEvents = 0
        var uniqueApps = 0
        var oldestDate: String?
        var newestDate: String?

        // Total events
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM usage_events", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalEvents = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        // Unique apps
        if sqlite3_prepare_v2(db, "SELECT COUNT(DISTINCT app_logical_id) FROM usage_events", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                uniqueApps = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        // Date range
        if sqlite3_prepare_v2(db, "SELECT MIN(event_date), MAX(event_date) FROM usage_events", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let minPtr = sqlite3_column_text(stmt, 0) {
                    oldestDate = String(cString: minPtr)
                }
                if let maxPtr = sqlite3_column_text(stmt, 1) {
                    newestDate = String(cString: maxPtr)
                }
            }
            sqlite3_finalize(stmt)
        }

        return (totalEvents, uniqueApps, oldestDate, newestDate)
    }

    /// Get all events for a specific app on a date (for debugging)
    func getEventsForApp(appID: String, date: String) -> [(minute: Int, timestamp: Date, sessionID: String)] {
        guard let db = db else { return [] }

        var events: [(Int, Date, String)] = []

        let sql = """
        SELECT threshold_minute, event_timestamp, session_id
        FROM usage_events
        WHERE app_logical_id = ? AND event_date = ?
        ORDER BY event_timestamp
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, appID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, date, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let minute = Int(sqlite3_column_int(stmt, 0))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                let sessionID = String(cString: sqlite3_column_text(stmt, 2))
                events.append((minute, timestamp, sessionID))
            }
            sqlite3_finalize(stmt)
        }

        return events
    }

    /// Get recent events across all apps (for diagnostic view)
    func getRecentEvents(limit: Int = 10) -> [(appID: String, date: String, minute: Int, timestamp: Date, secondsAdded: Int)] {
        guard let db = db else { return [] }

        var events: [(String, String, Int, Date, Int)] = []

        let sql = """
        SELECT app_logical_id, event_date, threshold_minute, event_timestamp, seconds_added
        FROM usage_events
        ORDER BY event_timestamp DESC
        LIMIT ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let appIDPtr = sqlite3_column_text(stmt, 0),
                   let datePtr = sqlite3_column_text(stmt, 1) {
                    let appID = String(cString: appIDPtr)
                    let date = String(cString: datePtr)
                    let minute = Int(sqlite3_column_int(stmt, 2))
                    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                    let seconds = Int(sqlite3_column_int(stmt, 4))
                    events.append((appID, date, minute, timestamp, seconds))
                }
            }
            sqlite3_finalize(stmt)
        }

        return events
    }

    /// Get events since a specific timestamp (for polling new events)
    func getEventsSince(timestamp: TimeInterval) -> [(appID: String, date: String, minute: Int, timestamp: Date, secondsAdded: Int)] {
        guard let db = db else { return [] }

        var events: [(String, String, Int, Date, Int)] = []

        let sql = """
        SELECT app_logical_id, event_date, threshold_minute, event_timestamp, seconds_added
        FROM usage_events
        WHERE event_timestamp > ?
        ORDER BY event_timestamp ASC
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, timestamp)

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let appIDPtr = sqlite3_column_text(stmt, 0),
                   let datePtr = sqlite3_column_text(stmt, 1) {
                    let appID = String(cString: appIDPtr)
                    let date = String(cString: datePtr)
                    let minute = Int(sqlite3_column_int(stmt, 2))
                    let eventTimestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                    let seconds = Int(sqlite3_column_int(stmt, 4))
                    events.append((appID, date, minute, eventTimestamp, seconds))
                }
            }
            sqlite3_finalize(stmt)
        }

        return events
    }

    /// Get today's event count
    func getTodayEventCount() -> Int {
        guard let db = db else { return 0 }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        var count = 0
        let sql = "SELECT COUNT(*) FROM usage_events WHERE event_date = ?"

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, today, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        return count
    }

    /// Get database file path for display
    func getDatabasePath() -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }

        return containerURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("usage_audit.sqlite")
            .path
    }

    /// Get last validation/repair timestamps from UserDefaults
    func getValidationTimestamps() -> (lastValidation: Date?, lastRepair: Date?, repairCount: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return (nil, nil, 0)
        }

        let lastValidation = defaults.double(forKey: "usage_integrity_last_validated")
        let lastRepair = defaults.double(forKey: "usage_integrity_last_repair")
        let repairCount = defaults.integer(forKey: "usage_integrity_repair_count")

        return (
            lastValidation > 0 ? Date(timeIntervalSince1970: lastValidation) : nil,
            lastRepair > 0 ? Date(timeIntervalSince1970: lastRepair) : nil,
            repairCount
        )
    }

    /// Force repair UserDefaults from database (public method for manual trigger)
    func forceRepair() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }

        let discrepancies = findDiscrepancies(defaults: defaults)
        if !discrepancies.isEmpty {
            repairFromDatabase(discrepancies: discrepancies, defaults: defaults)
        }
        return discrepancies.count
    }

    // MARK: - Private Methods

    private func openDatabase() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            print("[IntegrityValidator] Failed to get App Group container URL")
            return
        }

        let dbPath = containerURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("usage_audit.sqlite")
            .path

        // Check if database exists before opening
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("[IntegrityValidator] Audit database does not exist yet at \(dbPath)")
            return
        }

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("[IntegrityValidator] Failed to open database: \(errorMsg)")
            db = nil
        } else {
            print("[IntegrityValidator] Opened audit database for validation")
        }
    }

    private func findDiscrepancies(defaults: UserDefaults) -> [Discrepancy] {
        guard let db = db else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        var discrepancies: [Discrepancy] = []

        // Get all apps with database records for today
        let sql = """
        SELECT app_logical_id, SUM(seconds_added) as total
        FROM usage_events
        WHERE event_date = ?
        GROUP BY app_logical_id
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, today, -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let appIDPtr = sqlite3_column_text(stmt, 0) {
                    let appID = String(cString: appIDPtr)
                    let dbSeconds = Int(sqlite3_column_int(stmt, 1))

                    let udKey = "ext_usage_\(appID)_today"
                    let udSeconds = defaults.integer(forKey: udKey)
                    let udDate = defaults.string(forKey: "ext_usage_\(appID)_date")

                    // Only compare if UserDefaults is for today
                    if udDate == today && udSeconds != dbSeconds {
                        discrepancies.append(Discrepancy(
                            appID: appID,
                            date: today,
                            userDefaultsValue: udSeconds,
                            databaseValue: dbSeconds
                        ))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return discrepancies
    }

    private func repairFromDatabase(discrepancies: [Discrepancy], defaults: UserDefaults) {
        for d in discrepancies {
            let key = "ext_usage_\(d.appID)_today"
            let oldValue = defaults.integer(forKey: key)
            defaults.set(d.databaseValue, forKey: key)
            print("[IntegrityValidator] REPAIRED \(d.appID.prefix(12))... \(oldValue) -> \(d.databaseValue)")
        }

        // Record repair event
        defaults.set(Date().timeIntervalSince1970, forKey: "usage_integrity_last_repair")
        defaults.set(discrepancies.count, forKey: "usage_integrity_repair_count")

        // Log to extension debug log for visibility
        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)][REPAIR] Fixed \(discrepancies.count) discrepancies from audit DB"
        let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
        let trimmedLines = Array(lines.suffix(499))
        log = (trimmedLines + [entry]).joined(separator: "\n")
        defaults.set(log, forKey: "extension_debug_log")
    }

    private func logDiscrepancies(_ discrepancies: [Discrepancy]) {
        print("[IntegrityValidator] Found \(discrepancies.count) discrepancies:")
        for d in discrepancies {
            let direction = d.isInflated ? "INFLATED" : "DEFLATED"
            print("  - \(d.appID.prefix(12))...: UD=\(d.userDefaultsValue)s, DB=\(d.databaseValue)s (\(direction) by \(d.difference)s)")
        }
    }

    private func getEventCount() -> Int {
        guard let db = db else { return 0 }

        var count = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM usage_events", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        return count
    }
}
