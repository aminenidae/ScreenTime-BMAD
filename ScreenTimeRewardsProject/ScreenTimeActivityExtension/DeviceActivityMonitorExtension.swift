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

    /// ADD session usage to day total using DELTA-BASED calculation
    /// iOS thresholds are SESSION-based (reset each monitoring restart)
    /// We calculate delta = threshold - sessionPeak, then add delta to current day total
    /// This avoids relying on persisted sessionStart which can get stale
    /// Returns true if update was applied, false if skipped
    private nonisolated func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults) -> Bool {
        // Read current today value
        let todayKey = "usage_\(appID)_today"
        let todayResetKey = "usage_\(appID)_reset"
        let totalKey = "usage_\(appID)_total"
        let sessionLastThresholdKey = "usage_\(appID)_sessionLastThreshold"
        let sessionPeakKey = "usage_\(appID)_sessionPeak"
        let now = Date()
        let nowTimestamp = now.timeIntervalSince1970
        let startOfToday = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let lastReset = defaults.double(forKey: todayResetKey)

        // Check for day rollover
        if lastReset < startOfToday {
            // PHASE 3 FIX: New day detected - reset ALL apps, not just current one
            writeDebugLog("🌅 New day detected - performing global reset for all apps")

            // Check if we've already done a global reset today
            let globalResetKey = "global_daily_reset_timestamp"
            let lastGlobalReset = defaults.double(forKey: globalResetKey)

            if lastGlobalReset < startOfToday {
                // Perform global reset for all tracked apps
                resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
                defaults.set(startOfToday, forKey: globalResetKey)
                writeDebugLog("✅ Global reset completed for all apps")

                // Notify main app about the global reset
                notifyMainApp()
            }

            // Set current app's usage to threshold (first event of new day)
            defaults.set(thresholdSeconds, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            defaults.set(thresholdSeconds, forKey: totalKey) // Reset total for new day
            // Initialize session tracking
            defaults.set(thresholdSeconds, forKey: sessionPeakKey) // Peak for this session
            defaults.set(nowTimestamp, forKey: sessionLastThresholdKey)
            defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")
            writeDebugLog("🌅 New day: set \(appID) today=\(thresholdSeconds)s (first session)")
            return true
        }

        // Same day - use DELTA-BASED SESSION-AWARE logic
        let currentToday = defaults.integer(forKey: todayKey)
        let lastThresholdTime = defaults.double(forKey: sessionLastThresholdKey)
        let timeSinceLastThreshold = nowTimestamp - lastThresholdTime

        // SESSION DETECTION:
        // iOS catch-up fires thresholds within milliseconds of each other
        // Real usage has gaps (user actually using the app for minutes)
        // If >30 seconds since last threshold, this is a NEW SESSION
        let isNewSession = timeSinceLastThreshold > 30.0 || lastThresholdTime == 0

        // Read sessionPeak, but reset it if this is a new session
        var sessionPeak = defaults.integer(forKey: sessionPeakKey)

        if isNewSession {
            // NEW SESSION: Reset session peak only (no sessionStart needed!)
            sessionPeak = 0
            defaults.set(0, forKey: sessionPeakKey)
            writeDebugLog("🆕 New session for \(appID) (gap=\(Int(timeSinceLastThreshold))s, currentToday=\(currentToday)s)")
        }

        // DELTA-BASED THRESHOLD LOGIC:
        // delta = how much NEW session time (threshold - peak)
        // newDayTotal = currentToday + delta
        //
        // Example: User had 1080s today, new session, threshold 60s fires
        // - sessionPeak = 0 (reset for new session)
        // - delta = 60 - 0 = 60s
        // - newDayTotal = 1080 + 60 = 1140s ✓

        // Check if this threshold is new for this SESSION (prevents duplicate events)
        if thresholdSeconds <= sessionPeak {
            // This threshold already fired in this session - SKIP
            writeDebugLog("⏭️ SKIP: threshold=\(thresholdSeconds)s <= sessionPeak=\(sessionPeak)s (already counted)")
            // Still update the timestamp to track activity
            defaults.set(nowTimestamp, forKey: sessionLastThresholdKey)
            return false
        }

        // Calculate delta (new session time to add)
        let delta = thresholdSeconds - sessionPeak

        // Sanity check: delta should always be positive at this point
        if delta <= 0 {
            writeDebugLog("⚠️ SKIP: delta=\(delta)s is not positive")
            defaults.set(nowTimestamp, forKey: sessionLastThresholdKey)
            return false
        }

        // Calculate new day total by ADDING delta to current
        let newDayTotal = currentToday + delta

        // Update usage
        defaults.set(newDayTotal, forKey: todayKey)
        defaults.set(thresholdSeconds, forKey: sessionPeakKey) // Update session peak
        defaults.set(nowTimestamp, forKey: sessionLastThresholdKey)

        // Update total
        let currentTotal = defaults.integer(forKey: totalKey)
        defaults.set(currentTotal + delta, forKey: totalKey)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

        writeDebugLog("📊 RECORDED: +\(delta)s (threshold=\(thresholdSeconds)s - peak=\(sessionPeak)s) → today=\(newDayTotal)s")
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

    /// Reset daily counters for all tracked apps (PHASE 3 FIX)
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
            let sessionPeakKey = "usage_\(appID)_sessionPeak"
            let sessionLastThresholdKey = "usage_\(appID)_sessionLastThreshold"
            let modifiedKey = "usage_\(appID)_modified"

            // Only reset if this app hasn't been reset today
            let lastReset = defaults.double(forKey: resetKey)
            if lastReset < startOfToday {
                defaults.set(0, forKey: todayKey)
                defaults.set(startOfToday, forKey: resetKey)
                defaults.set(0, forKey: totalKey) // Reset total for new day
                // Reset session tracking for new day
                defaults.set(0, forKey: sessionPeakKey)
                defaults.set(0.0, forKey: sessionLastThresholdKey)
                defaults.set(Date().timeIntervalSince1970, forKey: modifiedKey)
                writeDebugLog("Reset \(appID): today=0s, sessionPeak=0s")
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
