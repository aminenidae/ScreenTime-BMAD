import DeviceActivity
import Foundation
import Darwin // For mach_task_self_ and task_info

/// Memory-optimized DeviceActivityMonitor extension with continuous tracking support
/// Target: <6MB memory usage
/// Strategy: Primitive key-value storage + re-arm signaling for minute-by-minute tracking
final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {

    // MARK: - Constants
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    // NOTE: cooldownSeconds removed - SET semantics prevent double-counting naturally

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
    /// KEY FIX: Uses SET semantics based on threshold minute, not INCREMENT
    /// This prevents phantom usage from accumulating
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

        // 2. Extract the minute number from event name (e.g., "usage.app.0.min.15" → 15)
        // This is the CUMULATIVE minutes reached, not an increment
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        writeDebugLog("Found mapping: appID=\(appID), thresholdMinutes=\(thresholdMinutes)")

        // 3. SET usage to threshold value (not INCREMENT)
        // NOTE: Cooldown removed because SET semantics already prevent double-counting
        // The setUsageToThreshold function only updates if threshold > current usage
        // This allows rapid catch-up events to fire correctly (e.g., thresholds 4,5,6,7 after accumulated usage)
        let now = Date().timeIntervalSince1970
        // This prevents phantom usage from accumulating
        let didUpdate = setUsageToThreshold(appID: appID, thresholdSeconds: thresholdSeconds, defaults: defaults)

        if !didUpdate {
            writeDebugLog("SKIPPED: Current usage already >= threshold (\(thresholdSeconds)s)")
            return false
        }

        // 4. Signal re-arm request for continuous tracking
        defaults.set(true, forKey: "rearm_\(appID)_requested")
        defaults.set(now, forKey: "rearm_\(appID)_time")

        defaults.synchronize()

        // Log memory usage after recording
        let memoryMB = getMemoryUsageMB()
        writeDebugLog("SUCCESS: Set usage to \(thresholdSeconds)s (\(thresholdMinutes)min) for \(appID) - Memory: \(String(format: "%.1f", memoryMB))MB")

        // Check for high memory usage
        if memoryMB > 5.0 {
            writeDebugLog("⚠️ HIGH MEMORY: \(String(format: "%.1f", memoryMB))MB / 6MB limit")
        }

        return true
    }

    /// Extract minute number from event name like "usage.app.0.min.15" → 15
    private nonisolated func extractMinuteFromEventName(_ eventName: String) -> Int {
        let components = eventName.split(separator: ".")
        // Look for "min" followed by number
        for i in 0..<components.count - 1 {
            if components[i] == "min", let minute = Int(components[i + 1]) {
                return minute
            }
        }
        // Fallback: check if last component is a number
        if let lastNum = Int(components.last ?? "") {
            return lastNum
        }
        return 1 // Default to 1 minute if can't parse
    }

    /// Simple +60s per event when threshold exceeds lastThreshold
    /// No session tracking needed - just track highest threshold seen today
    /// Returns true if 60s was added, false if skipped (catch-up or duplicate)
    private nonisolated func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults) -> Bool {
        let todayKey = "usage_\(appID)_today"
        let todayResetKey = "usage_\(appID)_reset"
        let totalKey = "usage_\(appID)_total"
        let lastThresholdKey = "usage_\(appID)_lastThreshold"
        let now = Date()
        let nowTimestamp = now.timeIntervalSince1970
        let startOfToday = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let lastReset = defaults.double(forKey: todayResetKey)

        // Day rollover check
        if lastReset < startOfToday {
            writeDebugLog("🌅 New day detected - performing global reset")

            // Check if we've already done a global reset today
            let globalResetKey = "global_daily_reset_timestamp"
            let lastGlobalReset = defaults.double(forKey: globalResetKey)

            if lastGlobalReset < startOfToday {
                resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
                defaults.set(startOfToday, forKey: globalResetKey)
                writeDebugLog("✅ Global reset completed")
                notifyMainApp()
            }

            // First event of new day = 60s
            defaults.set(60, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            defaults.set(60, forKey: totalKey)
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
            defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")
            writeDebugLog("🌅 New day: \(appID) today=60s (first event, threshold=\(thresholdSeconds)s)")
            return true
        }

        // Same day - simple logic: add 60s if threshold > lastThreshold
        let currentToday = defaults.integer(forKey: todayKey)
        let lastThreshold = defaults.integer(forKey: lastThresholdKey)

        // Only add 60s if this threshold is higher than last recorded
        if thresholdSeconds <= lastThreshold {
            writeDebugLog("⏭️ SKIP: threshold=\(thresholdSeconds)s <= last=\(lastThreshold)s")
            return false
        }

        // Add exactly 60s
        let newToday = currentToday + 60
        defaults.set(newToday, forKey: todayKey)
        defaults.set(thresholdSeconds, forKey: lastThresholdKey)

        // Update total
        let currentTotal = defaults.integer(forKey: totalKey)
        defaults.set(currentTotal + 60, forKey: totalKey)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

        writeDebugLog("📊 +60s: threshold=\(thresholdSeconds)s > last=\(lastThreshold)s → today=\(newToday)s")
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
    /// KEY FIX: Uses SET semantics based on threshold minute, not INCREMENT
    private nonisolated func recordUsageWithMapping(_ mapping: (appID: String, increment: Int, displayName: String, category: String, rewardPoints: Int), eventName: String, defaults: UserDefaults) -> Bool {
        let now = Date().timeIntervalSince1970

        // NOTE: Cooldown removed - SET semantics prevent double-counting naturally

        // Extract threshold minutes from event name and SET (not increment)
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        let didUpdate = setUsageToThreshold(appID: mapping.appID, thresholdSeconds: thresholdSeconds, defaults: defaults)

        if !didUpdate {
            writeDebugLog("SKIPPED (JSON path): Current usage already >= threshold")
            return false
        }

        // Update JSON persistence for compatibility
        // Delta is 60 seconds (1 threshold = 1 minute)
        updateJSONPersistence(appID: mapping.appID, increment: 60, rewardPoints: mapping.rewardPoints, defaults: defaults)

        // Signal re-arm request
        defaults.set(true, forKey: "rearm_\(mapping.appID)_requested")
        defaults.set(now, forKey: "rearm_\(mapping.appID)_time")
        defaults.synchronize()

        // Log memory usage after recording
        let memoryMB = getMemoryUsageMB()
        writeDebugLog("SUCCESS (JSON path): Set usage to \(thresholdSeconds)s (\(thresholdMinutes)min) for \(mapping.displayName) - Memory: \(String(format: "%.1f", memoryMB))MB")

        // Check for high memory usage
        if memoryMB > 5.0 {
            writeDebugLog("⚠️ HIGH MEMORY: \(String(format: "%.1f", memoryMB))MB / 6MB limit")
        }

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

    /// Get current memory usage in MB using task_vm_info for accuracy
    private nonisolated func getMemoryUsageMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_,
                         task_flavor_t(TASK_VM_INFO),
                         intPtr,
                         &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            writeDebugLog("Failed to get memory usage")
            return 0.0
        }

        // Convert bytes to MB (phys_footprint is more accurate than resident_size)
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    /// Update heartbeat for diagnostics
    private nonisolated func updateHeartbeat() {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_heartbeat")

            // Add memory tracking
            let memoryMB = getMemoryUsageMB()
            defaults.set(memoryMB, forKey: "extension_memory_mb")

            defaults.synchronize()

            // Log memory for debugging
            writeDebugLog("Heartbeat updated - Memory: \(String(format: "%.1f", memoryMB))MB")
        }
    }

    /// Reset daily counters for all tracked apps
    private nonisolated func resetAllDailyCounters(defaults: UserDefaults, startOfToday: Double) {
        // Get all keys that match our usage pattern
        let allKeys = defaults.dictionaryRepresentation().keys

        // Find all app IDs by looking for usage keys
        var appIDs = Set<String>()
        for key in allKeys {
            if key.hasPrefix("usage_") && key.hasSuffix("_today") {
                // Extract app ID from "usage_<appID>_today"
                let startIndex = key.index(key.startIndex, offsetBy: 6) // Skip "usage_"
                let endIndex = key.index(key.endIndex, offsetBy: -6) // Remove "_today"
                if startIndex < endIndex {
                    let appID = String(key[startIndex..<endIndex])
                    appIDs.insert(appID)
                }
            }
        }

        // Reset each app's daily counters
        for appID in appIDs {
            let todayKey = "usage_\(appID)_today"
            let resetKey = "usage_\(appID)_reset"
            let totalKey = "usage_\(appID)_total"
            let lastThresholdKey = "usage_\(appID)_lastThreshold"
            let modifiedKey = "usage_\(appID)_modified"

            // Only reset if this app hasn't been reset today
            let lastReset = defaults.double(forKey: resetKey)
            if lastReset < startOfToday {
                defaults.set(0, forKey: todayKey)
                defaults.set(startOfToday, forKey: resetKey)
                defaults.set(0, forKey: totalKey)
                defaults.set(0, forKey: lastThresholdKey) // Reset lastThreshold for new day
                defaults.set(Date().timeIntervalSince1970, forKey: modifiedKey)
                writeDebugLog("Reset \(appID): today=0s, lastThreshold=0s")
            }
        }

        writeDebugLog("Global reset completed for \(appIDs.count) apps")
    }

    /// Send Darwin notification to main app with sequence tracking for diagnostics
    private nonisolated func notifyMainApp() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            writeDebugLog("ERROR: Cannot access app group for notification")
            return
        }

        // Increment and store sequence number for tracking delivery
        let currentSeq = defaults.integer(forKey: "darwin_notification_seq_sent")
        let nextSeq = currentSeq + 1
        defaults.set(nextSeq, forKey: "darwin_notification_seq_sent")
        defaults.set(Date().timeIntervalSince1970, forKey: "darwin_notification_last_sent")
        defaults.synchronize()

        // Post the Darwin notification
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.screentimerewards.usageRecorded" as CFString),
            nil,
            nil,
            true
        )

        writeDebugLog("📤 SENT Darwin notification #\(nextSeq)")
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
