import DeviceActivity
import Foundation

/// Memory-optimized DeviceActivityMonitor extension with continuous tracking support
/// Target: <6MB memory usage
/// Strategy: Primitive key-value storage + re-arm signaling for minute-by-minute tracking
final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {

    // MARK: - Constants
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let cooldownSeconds: TimeInterval = 55  // Phantom event protection

    // MARK: - Lifecycle
    override nonisolated init() {
        super.init()
        writeDebugLog("Extension init() called")

        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(true, forKey: "extension_initialized_flag")
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")
            defaults.synchronize()
            writeDebugLog("Extension initialized successfully")
        } else {
            writeDebugLog("ERROR: Failed to access app group in init")
        }
    }

    // MARK: - Interval Events
    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        writeDebugLog("intervalDidStart: \(activity.rawValue)")
        updateHeartbeat()
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        writeDebugLog("intervalDidEnd: \(activity.rawValue)")
    }

    // MARK: - Threshold Event Handler
    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        writeDebugLog("eventDidReachThreshold: \(event.rawValue)")
        updateHeartbeat()

        // Record usage and signal re-arm
        let didRecord = recordUsageEfficiently(for: event.rawValue)

        if didRecord {
            // Send notification to main app for re-arm and UI update
            notifyMainApp()
        }
    }

    // MARK: - Memory-Efficient Usage Recording

    /// Record usage using only primitive values - no JSON, no structs
    private nonisolated func recordUsageEfficiently(for eventName: String) -> Bool {
        writeDebugLog("recordUsageEfficiently: \(eventName)")

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            writeDebugLog("ERROR: Cannot access app group")
            return false
        }

        // 1. Read event mapping (primitives only)
        let mapIdKey = "map_\(eventName)_id"
        guard let appID = defaults.string(forKey: mapIdKey) else {
            writeDebugLog("ERROR: No mapping found for '\(mapIdKey)'")
            // Try to read from JSON eventMappings as fallback
            if let mapping = readEventMappingFromJSON(eventName: eventName, defaults: defaults) {
                return recordUsageWithMapping(mapping, eventName: eventName, defaults: defaults)
            }
            return false
        }

        // Read increment (default 60s = 1 minute)
        let mapIncKey = "map_\(eventName)_inc"
        let mapSecKey = "map_\(eventName)_sec"
        let increment = defaults.integer(forKey: mapIncKey) > 0
            ? defaults.integer(forKey: mapIncKey)
            : (defaults.integer(forKey: mapSecKey) > 0 ? defaults.integer(forKey: mapSecKey) : 60)

        writeDebugLog("Found mapping: appID=\(appID), increment=\(increment)s")

        // 2. Check cooldown (phantom event protection)
        let now = Date().timeIntervalSince1970
        let lastRecordKey = "lastRecorded_\(appID)"
        let lastRecord = defaults.double(forKey: lastRecordKey)

        if lastRecord > 0 && (now - lastRecord) < cooldownSeconds {
            writeDebugLog("SKIPPED: Cooldown active (\(Int(now - lastRecord))s < \(Int(cooldownSeconds))s)")
            return false
        }

        // 3. Update usage counters (primitives only)
        incrementUsage(appID: appID, seconds: increment, defaults: defaults)

        // 4. Update last recorded timestamp
        defaults.set(now, forKey: lastRecordKey)

        // 5. Signal re-arm request for continuous tracking
        defaults.set(true, forKey: "rearm_\(appID)_requested")
        defaults.set(now, forKey: "rearm_\(appID)_time")

        defaults.synchronize()

        writeDebugLog("SUCCESS: Recorded \(increment)s for \(appID), re-arm requested")
        return true
    }

    /// Fallback: Read mapping from JSON eventMappings (for compatibility)
    private nonisolated func readEventMappingFromJSON(eventName: String, defaults: UserDefaults) -> (appID: String, increment: Int, displayName: String, category: String, rewardPoints: Int)? {
        guard let data = defaults.data(forKey: "eventMappings"),
              let mappings = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let eventInfo = mappings[eventName],
              let logicalID = eventInfo["logicalID"] as? String else {
            return nil
        }

        let displayName = eventInfo["displayName"] as? String ?? "Unknown"
        let category = eventInfo["category"] as? String ?? "Learning"
        let rewardPoints = eventInfo["rewardPoints"] as? Int ?? 10
        let thresholdSeconds = eventInfo["thresholdSeconds"] as? Int ?? 60
        let incrementSeconds = eventInfo["incrementSeconds"] as? Int ?? thresholdSeconds

        writeDebugLog("Fallback JSON mapping: \(displayName) (\(logicalID))")
        return (logicalID, incrementSeconds, displayName, category, rewardPoints)
    }

    /// Record usage using JSON fallback mapping
    private nonisolated func recordUsageWithMapping(_ mapping: (appID: String, increment: Int, displayName: String, category: String, rewardPoints: Int), eventName: String, defaults: UserDefaults) -> Bool {
        let now = Date().timeIntervalSince1970
        let lastRecordKey = "lastRecorded_\(mapping.appID)"
        let lastRecord = defaults.double(forKey: lastRecordKey)

        if lastRecord > 0 && (now - lastRecord) < cooldownSeconds {
            writeDebugLog("SKIPPED (JSON path): Cooldown active")
            return false
        }

        // Update usage counters
        incrementUsage(appID: mapping.appID, seconds: mapping.increment, defaults: defaults)

        // Update JSON persistence for compatibility
        updateJSONPersistence(appID: mapping.appID, increment: mapping.increment, rewardPoints: mapping.rewardPoints, defaults: defaults)

        // Update timestamp and request re-arm
        defaults.set(now, forKey: lastRecordKey)
        defaults.set(true, forKey: "rearm_\(mapping.appID)_requested")
        defaults.set(now, forKey: "rearm_\(mapping.appID)_time")
        defaults.synchronize()

        writeDebugLog("SUCCESS (JSON path): Recorded \(mapping.increment)s for \(mapping.displayName)")
        return true
    }

    /// Update JSON persistence for backward compatibility with main app
    private nonisolated func updateJSONPersistence(appID: String, increment: Int, rewardPoints: Int, defaults: UserDefaults) {
        guard let data = defaults.data(forKey: "persistedApps_v3"),
              var apps = try? JSONDecoder().decode([String: PersistedAppMinimal].self, from: data),
              var app = apps[appID] else {
            return
        }

        // Check for day rollover
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if !calendar.isDate(app.lastResetDate, inSameDayAs: today) {
            app.todaySeconds = 0
            app.todayPoints = 0
            app.lastResetDate = today
        }

        // Update counters
        let earnedPoints = (increment / 60) * rewardPoints
        app.totalSeconds += increment
        app.earnedPoints += earnedPoints
        app.todaySeconds += increment
        app.todayPoints += earnedPoints
        app.lastUpdated = now

        apps[appID] = app

        if let encoded = try? JSONEncoder().encode(apps) {
            defaults.set(encoded, forKey: "persistedApps_v3")
        }
    }

    /// Increment usage counters using primitive keys only (memory efficient)
    private nonisolated func incrementUsage(appID: String, seconds: Int, defaults: UserDefaults) {
        // Update total seconds
        let totalKey = "usage_\(appID)_total"
        let currentTotal = defaults.integer(forKey: totalKey)
        defaults.set(currentTotal + seconds, forKey: totalKey)

        // Update today's seconds with day rollover check
        let todayKey = "usage_\(appID)_today"
        let todayResetKey = "usage_\(appID)_reset"
        let lastReset = defaults.double(forKey: todayResetKey)
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now).timeIntervalSince1970

        if lastReset < startOfToday {
            // New day - reset today counter
            defaults.set(seconds, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            writeDebugLog("New day detected - reset today counter")
        } else {
            let currentToday = defaults.integer(forKey: todayKey)
            defaults.set(currentToday + seconds, forKey: todayKey)
        }

        // Update last modified timestamp
        defaults.set(now.timeIntervalSince1970, forKey: "usage_\(appID)_modified")

        writeDebugLog("Updated counters: total=\(currentTotal + seconds)s")
    }

    // MARK: - Utilities

    /// Update heartbeat for diagnostics
    private nonisolated func updateHeartbeat() {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_heartbeat")
            defaults.synchronize()
        }
    }

    /// Send Darwin notification to main app
    private nonisolated func notifyMainApp() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.screentimerewards.usageRecorded" as CFString),
            nil,
            nil,
            true
        )
        writeDebugLog("Sent notification to main app")
    }

    /// Write debug log (memory-efficient circular buffer)
    private nonisolated func writeDebugLog(_ message: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        let timestamp = Date().timeIntervalSince1970
        let entry = "[\(String(format: "%.0f", timestamp))] \(message)\n"

        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        log += entry

        // Keep only last 50 lines
        let lines = log.components(separatedBy: "\n")
        if lines.count > 50 {
            log = lines.suffix(50).joined(separator: "\n")
        }

        defaults.set(log, forKey: "extension_debug_log")
        // Don't synchronize here to reduce I/O - let it batch
    }
}

// MARK: - Minimal Codable Struct for JSON Compatibility
// This is only used for updating existing JSON persistence, not for reading
private struct PersistedAppMinimal: Codable {
    let logicalID: String
    let displayName: String
    var category: String
    var rewardPoints: Int
    var totalSeconds: Int
    var earnedPoints: Int
    let createdAt: Date
    var lastUpdated: Date
    var todaySeconds: Int
    var todayPoints: Int
    var lastResetDate: Date
}
