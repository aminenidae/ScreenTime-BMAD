import DeviceActivity
import Foundation
import Darwin // For mach_task_self_ and task_info
import ManagedSettings
import UserNotifications

/// Memory-optimized DeviceActivityMonitor extension with continuous tracking support
/// Target: <6MB memory usage
/// Strategy: Primitive key-value storage + re-arm signaling for minute-by-minute tracking
final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {

    // MARK: - Session Tracking
    /// Unique session ID for this extension instance (persists until extension terminates)
    private static let sessionID: String = {
        let id = UUID().uuidString.prefix(8)
        return String(id)
    }()

    // MARK: - Constants
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    // NOTE: cooldownSeconds removed - SET semantics prevent double-counting naturally

    // MARK: - Shield Control
    /// ManagedSettingsStore for direct shield manipulation
    /// The extension can use this to unblock reward apps when learning goals are met
    private let managedSettingsStore = ManagedSettingsStore()

    // MARK: - Debug Logging
    /// Write debug log entry to shared UserDefaults buffer (last 500 entries)
    private nonisolated func debugLog(_ message: String, defaults: UserDefaults) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)][\(Self.sessionID)] \(message)"

        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
        let trimmedLines = Array(lines.suffix(499)) // Keep last 499 to add 1 more (500 total)
        log = (trimmedLines + [entry]).joined(separator: "\n")
        defaults.set(log, forKey: "extension_debug_log")
    }

    // MARK: - Lifecycle
    override nonisolated init() {
        super.init()
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(true, forKey: "extension_initialized_flag")
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")
        }
    }

    // MARK: - Interval Events
    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            debugLog("INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
        }
        updateHeartbeat()
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            debugLog("INTERVAL_END activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
        }
    }

    // MARK: - Threshold Event Handler
    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        // Console visibility for development
        print("🔔 [EXTENSION] THRESHOLD EVENT: \(event.rawValue)")

        // Log FIRST - before any processing that could fail
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            debugLog("THRESHOLD_CALL event=\(event.rawValue)", defaults: defaults)
            // Increment persistent counter to track total events received
            let eventCount = defaults.integer(forKey: "ext_total_events_received") + 1
            defaults.set(eventCount, forKey: "ext_total_events_received")

            // Show event count in console
            print("🔔 [EXTENSION] Total events: \(eventCount)")
        }

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
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return false
        }

        // 1. Read event mapping (primitives only)
        let mapIdKey = "map_\(eventName)_id"

        // DIAGNOSTIC: Count total map keys for visibility
        let allMapKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("map_") && $0.hasSuffix("_id") }
        debugLog("EVENT_TRACE: eventName=\(eventName)", defaults: defaults)
        debugLog("EVENT_TRACE: mapIdKey=\(mapIdKey) totalMapKeys=\(allMapKeys.count)", defaults: defaults)

        guard let appID = defaults.string(forKey: mapIdKey) else {
            // Try to read from JSON eventMappings as fallback
            if let mapping = readEventMappingFromJSON(eventName: eventName, defaults: defaults) {
                return recordUsageWithMapping(mapping, eventName: eventName, defaults: defaults)
            }
            debugLog("NO_MAPPING event=\(eventName)", defaults: defaults)
            debugLog("EVENT_TRACE: ❌ No mapping found for key=\(mapIdKey)", defaults: defaults)
            return false
        }

        // DIAGNOSTIC: Log the resolved appID and category
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Unknown"
        let displayName = defaults.string(forKey: "map_\(appID)_name") ?? "Unknown"
        debugLog("EVENT_TRACE: ✅ Resolved appID=\(appID.prefix(12))... name=\(displayName) cat=\(category)", defaults: defaults)

        // 2. Extract the minute number from event name (e.g., "usage.app.0.min.15" → 15)
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        // DEBUG: Log event received with current state
        let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
        let currentThreshold = defaults.integer(forKey: "usage_\(appID)_lastThreshold")
        debugLog("EVENT appID=\(appID.prefix(8))... min=\(thresholdMinutes) currentToday=\(currentToday)s lastThresh=\(currentThreshold)s", defaults: defaults)

        // Console visibility for development
        print("📝 [EXTENSION] Recording: app=\(appID.prefix(8))... minute=\(thresholdMinutes) currentToday=\(currentToday)s")

        // 3. SET usage to threshold value (not INCREMENT)
        let now = Date().timeIntervalSince1970
        let didUpdate = setUsageToThreshold(appID: appID, thresholdSeconds: thresholdSeconds, defaults: defaults)

        if !didUpdate {
            return false
        }

        // Confirm recording success in console
        let newToday = defaults.integer(forKey: "usage_\(appID)_today")
        print("✅ [EXTENSION] Recorded +60s - total today: \(newToday)s")

        // 4. Signal re-arm request for continuous tracking
        defaults.set(true, forKey: "rearm_\(appID)_requested")
        defaults.set(now, forKey: "rearm_\(appID)_time")

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        // Called after EVERY usage event (learning or reward) because:
        // - Reward app usage might exceed earned time -> block
        // - Learning app usage might increase earned time (but we still check for exhaustion)
        checkAndBlockIfRewardTimeExhausted(defaults: defaults)

        // EXTENSION CLOUDKIT SYNC: Sync usage directly to parent's CloudKit zone
        // This enables real-time updates without requiring the main app to be opened
        debugLog("TRIGGERING_CLOUDKIT_SYNC from recordUsageEfficiently", defaults: defaults)
        ExtensionCloudKitSync.shared.syncUsageToParent(defaults: defaults)

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
    /// Writes to ext_ keys using INCREMENT semantics (source of truth for main app sync)
    private nonisolated func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults) -> Bool {
        let todayKey = "usage_\(appID)_today"
        let todayResetKey = "usage_\(appID)_reset"
        let totalKey = "usage_\(appID)_total"
        let lastThresholdKey = "usage_\(appID)_lastThreshold"
        let now = Date()
        let nowTimestamp = now.timeIntervalSince1970
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let lastReset = defaults.double(forKey: todayResetKey)

        // Date string for ext_ keys
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)
        let hour = calendar.component(.hour, from: now)

        // Day rollover check
        if lastReset < startOfToday {
            // Check if we've already done a global reset today
            let globalResetKey = "global_daily_reset_timestamp"
            let lastGlobalReset = defaults.double(forKey: globalResetKey)

            if lastGlobalReset < startOfToday {
                debugLog("DAY_ROLLOVER appID=\(appID.prefix(8))... globalReset triggered", defaults: defaults)
                resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
                defaults.set(startOfToday, forKey: globalResetKey)
                notifyMainApp()
            }

            // First event of new day = 60s
            debugLog("NEW_DAY appID=\(appID.prefix(8))... setting today=60s (was lastReset=\(lastReset) < startOfToday=\(startOfToday))", defaults: defaults)
            defaults.set(60, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            defaults.set(60, forKey: totalKey)
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
            defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

            // === PROTECTED ext_ KEYS (TRUE Source of Truth) ===
            // Uses INCREMENT semantics: first event of new day = 60s
            debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... NEW_DAY today=60 total=60 date=\(dateString) hour=\(hour)", defaults: defaults)
            defaults.set(60, forKey: "ext_usage_\(appID)_today")
            defaults.set(60, forKey: "ext_usage_\(appID)_total")
            defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
            defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
            defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")

            // === HOURLY BUCKET TRACKING ===
            for h in 0..<24 {
                defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
            }
            defaults.set(60, forKey: "ext_usage_\(appID)_hourly_\(hour)")
            defaults.set(dateString, forKey: "ext_usage_\(appID)_hourly_date")

            return true
        }

        // Same day - check for catch-up vs new session
        let currentToday = defaults.integer(forKey: todayKey)
        var lastThreshold = defaults.integer(forKey: lastThresholdKey)
        let lastEventTime = defaults.double(forKey: "usage_\(appID)_lastEventTime")
        let timeSinceLastEvent = nowTimestamp - lastEventTime

        // Global restart check - main app sets this when monitoring starts/restarts
        let restartTimestamp = defaults.double(forKey: "monitoring_restart_timestamp")
        let timeSinceRestart = nowTimestamp - restartTimestamp

        // Case 1: Duplicate threshold
        if thresholdSeconds == lastThreshold {
            debugLog("SKIP_DUP appID=\(appID.prefix(8))... threshold=\(thresholdSeconds) == lastThreshold", defaults: defaults)
            return false
        }

        // Case 2: Threshold decreased (could be catch-up OR new session)
        if thresholdSeconds < lastThreshold {
            debugLog("THRESH_DECREASE appID=\(appID.prefix(8))... new=\(thresholdSeconds)s < last=\(lastThreshold)s, checking catch-up...", defaults: defaults)

            // Check 1: Within 50s of monitoring restart → ALWAYS skip (catch-up from app list change)
            if timeSinceRestart < 50.0 && restartTimestamp > 0 {
                debugLog("SKIP_RESTART appID=\(appID.prefix(8))... timeSinceRestart=\(Int(timeSinceRestart))s < 50s", defaults: defaults)
                defaults.set(nowTimestamp, forKey: "usage_\(appID)_lastEventTime")
                return false
            }

            // Check 2: Rapid fire (< 30s since last event for this app) → catch-up, skip
            if timeSinceLastEvent < 30.0 && lastEventTime > 0 {
                debugLog("SKIP_RAPID appID=\(appID.prefix(8))... timeSinceLastEvent=\(Int(timeSinceLastEvent))s < 30s", defaults: defaults)
                defaults.set(nowTimestamp, forKey: "usage_\(appID)_lastEventTime")
                return false
            }

            // Both checks passed: likely a genuine new session → reset lastThreshold
            debugLog("⚠️ THRESH_RESET appID=\(appID.prefix(8))... from=\(lastThreshold)s to=0 (new session detected, currentToday=\(currentToday)s)", defaults: defaults)
            defaults.set(0, forKey: lastThresholdKey)
            lastThreshold = 0
        }

        // Case 3: Normal progression (threshold > lastThreshold, or after reset)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_lastEventTime")
        let newToday = currentToday + 60
        debugLog("RECORDED appID=\(appID.prefix(8))... oldToday=\(currentToday)s +60 = newToday=\(newToday)s, thresh=\(thresholdSeconds)s", defaults: defaults)
        defaults.set(newToday, forKey: todayKey)
        defaults.set(thresholdSeconds, forKey: lastThresholdKey)

        // Update total
        let currentTotal = defaults.integer(forKey: totalKey)
        let newTotal = currentTotal + 60
        defaults.set(newTotal, forKey: totalKey)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

        // === PROTECTED ext_ KEYS (TRUE Source of Truth) ===
        // Uses INCREMENT semantics: always add 60s for each valid event
        // Phantom events are already filtered by SKIP_RESTART and SKIP_RAPID above
        let currentExtToday = defaults.integer(forKey: "ext_usage_\(appID)_today")
        let currentExtTotal = defaults.integer(forKey: "ext_usage_\(appID)_total")
        let currentExtDate = defaults.string(forKey: "ext_usage_\(appID)_date")

        let newExtToday: Int
        if currentExtDate == dateString {
            // Same day: INCREMENT by 60s (phantom detection already passed)
            newExtToday = currentExtToday + 60
        } else {
            // New day: start fresh with 60s
            newExtToday = 60
        }

        // Always update ext_ keys - phantom events were filtered above
        debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... INCREMENT today=\(newExtToday) total=\(currentExtTotal + 60) hour=\(hour) (was today=\(currentExtToday))", defaults: defaults)
        defaults.set(newExtToday, forKey: "ext_usage_\(appID)_today")
        defaults.set(currentExtTotal + 60, forKey: "ext_usage_\(appID)_total")
        defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
        defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
        defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")

        // === HOURLY BUCKET TRACKING ===
        let storedHourlyDate = defaults.string(forKey: "ext_usage_\(appID)_hourly_date")
        if storedHourlyDate != dateString {
            debugLog("HOURLY_RESET appID=\(appID.prefix(8))... date changed from \(storedHourlyDate ?? "nil") to \(dateString)", defaults: defaults)
            for h in 0..<24 {
                defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
            }
            defaults.set(dateString, forKey: "ext_usage_\(appID)_hourly_date")
        }
        let currentHourlySeconds = defaults.integer(forKey: "ext_usage_\(appID)_hourly_\(hour)")
        defaults.set(currentHourlySeconds + 60, forKey: "ext_usage_\(appID)_hourly_\(hour)")

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

        return (logicalID, incrementSeconds, displayName, category, rewardPoints)
    }

    /// Record usage using JSON fallback mapping
    /// KEY FIX: Uses SET semantics based on threshold minute, not INCREMENT
    private nonisolated func recordUsageWithMapping(_ mapping: (appID: String, increment: Int, displayName: String, category: String, rewardPoints: Int), eventName: String, defaults: UserDefaults) -> Bool {
        let now = Date().timeIntervalSince1970

        // Extract threshold minutes from event name and SET (not increment)
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        let didUpdate = setUsageToThreshold(appID: mapping.appID, thresholdSeconds: thresholdSeconds, defaults: defaults)

        if !didUpdate {
            return false
        }

        // Update JSON persistence for compatibility
        updateJSONPersistence(appID: mapping.appID, increment: 60, rewardPoints: mapping.rewardPoints, defaults: defaults)

        // Signal re-arm request
        defaults.set(true, forKey: "rearm_\(mapping.appID)_requested")
        defaults.set(now, forKey: "rearm_\(mapping.appID)_time")

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        checkAndBlockIfRewardTimeExhausted(defaults: defaults)

        // EXTENSION CLOUDKIT SYNC: Sync usage directly to parent's CloudKit zone
        debugLog("TRIGGERING_CLOUDKIT_SYNC from recordUsageWithMapping", defaults: defaults)
        ExtensionCloudKitSync.shared.syncUsageToParent(defaults: defaults)

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
        } else {
            let currentToday = defaults.integer(forKey: todayKey)
            defaults.set(currentToday + seconds, forKey: todayKey)
        }

        // Update last modified timestamp
        defaults.set(now.timeIntervalSince1970, forKey: "usage_\(appID)_modified")
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
            return 0.0
        }

        // Convert bytes to MB (phys_footprint is more accurate than resident_size)
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    /// Update heartbeat for diagnostics
    private nonisolated func updateHeartbeat() {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_heartbeat")
            let memoryMB = getMemoryUsageMB()
            defaults.set(memoryMB, forKey: "extension_memory_mb")
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
                debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... DAILY_RESET clearing usage and hourly buckets", defaults: defaults)
                defaults.set(0, forKey: todayKey)
                defaults.set(startOfToday, forKey: resetKey)
                defaults.set(0, forKey: totalKey)
                defaults.set(0, forKey: lastThresholdKey)
                defaults.set(Date().timeIntervalSince1970, forKey: modifiedKey)

                // Reset hourly buckets
                for h in 0..<24 {
                    defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
                }
                defaults.removeObject(forKey: "ext_usage_\(appID)_hourly_date")
            }
        }
    }

    /// Send Darwin notification to main app with sequence tracking for diagnostics
    private nonisolated func notifyMainApp() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        // Increment and store sequence number for tracking delivery
        let currentSeq = defaults.integer(forKey: "darwin_notification_seq_sent")
        let nextSeq = currentSeq + 1
        defaults.set(nextSeq, forKey: "darwin_notification_seq_sent")
        defaults.set(Date().timeIntervalSince1970, forKey: "darwin_notification_last_sent")

        // Post the Darwin notification
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.screentimerewards.usageRecorded" as CFString),
            nil,
            nil,
            true
        )
    }

    // MARK: - Extension Shield Control
    // These methods allow the extension to directly control shields when learning goals are met,
    // without requiring the main app to be running

    /// Check all reward app goals and update shields accordingly
    /// Called after each usage recording to immediately unblock reward apps when goals are met
    private nonisolated func checkAndUpdateShields(defaults: UserDefaults) {
        debugLog("SHIELD_CHECK: Starting shield update check", defaults: defaults)

        guard let data = defaults.data(forKey: "extensionShieldConfigs") else {
            debugLog("SHIELD_CHECK: ❌ NO extensionShieldConfigs data found - ensure main app synced configs", defaults: defaults)
            return
        }

        guard let configs = try? JSONDecoder().decode(ExtensionShieldConfigsMinimal.self, from: data) else {
            debugLog("SHIELD_CHECK: ❌ DECODE FAILED for extensionShieldConfigs - data may be corrupted", defaults: defaults)
            return
        }

        debugLog("SHIELD_CHECK: Found \(configs.goalConfigs.count) goal configs to evaluate", defaults: defaults)

        for goalConfig in configs.goalConfigs {
            let isGoalMet = checkGoalMet(goalConfig: goalConfig, defaults: defaults)
            let shortID = String(goalConfig.rewardAppLogicalID.prefix(12))
            debugLog("SHIELD_CHECK: \(shortID)... goalMet=\(isGoalMet)", defaults: defaults)

            if isGoalMet {
                guard let token = try? PropertyListDecoder().decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) else {
                    debugLog("SHIELD_CHECK: ❌ TOKEN DECODE FAILED for \(shortID) - tokenData may be invalid", defaults: defaults)
                    continue
                }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                let shieldCount = currentShields.count
                let containsToken = currentShields.contains(token)
                debugLog("SHIELD_CHECK: \(shortID) currentShields=\(shieldCount), containsToken=\(containsToken)", defaults: defaults)

                if containsToken {
                    currentShields.remove(token)
                    managedSettingsStore.shield.applications = currentShields.isEmpty ? nil : currentShields
                    recordUnlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)
                    debugLog("SHIELD_CHECK: ✅ REMOVED shield for \(shortID)", defaults: defaults)

                    // Calculate earned minutes for notification
                    let earnedMinutes = calculateEarnedMinutes(goalConfig: goalConfig, defaults: defaults)
                    scheduleGoalCompletedNotification(rewardMinutes: earnedMinutes, rewardAppID: goalConfig.rewardAppLogicalID, defaults: defaults)
                } else {
                    debugLog("SHIELD_CHECK: ℹ️ \(shortID) goal met but not currently shielded", defaults: defaults)
                }
            }
        }
        debugLog("SHIELD_CHECK: Completed shield update check", defaults: defaults)
    }

    /// Check if a reward app's learning goal is met
    private nonisolated func checkGoalMet(goalConfig: ExtensionGoalConfigMinimal, defaults: UserDefaults) -> Bool {
        let shortID = String(goalConfig.rewardAppLogicalID.prefix(12))
        debugLog("GOAL_CHECK: \(shortID) mode=\(goalConfig.unlockMode) linkedApps=\(goalConfig.linkedLearningApps.count)", defaults: defaults)

        if goalConfig.linkedLearningApps.isEmpty {
            debugLog("GOAL_CHECK: ⚠️ \(shortID) has NO linked learning apps - goal cannot be met", defaults: defaults)
            return false
        }

        switch goalConfig.unlockMode {
        case "any":
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                let linkedShortID = String(linked.learningAppLogicalID.prefix(12))
                debugLog("GOAL_CHECK: \(linkedShortID) usage=\(usageMinutes)min required=\(linked.minutesRequired)min", defaults: defaults)
                if usageMinutes >= linked.minutesRequired {
                    debugLog("GOAL_CHECK: ✅ \(shortID) goal MET via \(linkedShortID)", defaults: defaults)
                    return true
                }
            }
            debugLog("GOAL_CHECK: ❌ \(shortID) goal NOT met (any mode) - no linked app reached target", defaults: defaults)
            return false

        case "all":
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                let linkedShortID = String(linked.learningAppLogicalID.prefix(12))
                debugLog("GOAL_CHECK: \(linkedShortID) usage=\(usageMinutes)min required=\(linked.minutesRequired)min", defaults: defaults)
                if usageMinutes < linked.minutesRequired {
                    debugLog("GOAL_CHECK: ❌ \(shortID) goal NOT met (all mode) - \(linkedShortID) below target", defaults: defaults)
                    return false
                }
            }
            debugLog("GOAL_CHECK: ✅ \(shortID) goal MET (all mode) - all linked apps reached target", defaults: defaults)
            return true

        default:
            debugLog("GOAL_CHECK: ⚠️ \(shortID) unknown unlockMode: \(goalConfig.unlockMode)", defaults: defaults)
            return false
        }
    }

    /// Record unlock state for main app to read
    private nonisolated func recordUnlockState(rewardAppLogicalID: String, defaults: UserDefaults) {
        let now = Date()
        let stateKey = "ext_unlock_\(rewardAppLogicalID)"
        let timestampKey = "ext_unlock_\(rewardAppLogicalID)_timestamp"

        defaults.set(true, forKey: stateKey)
        defaults.set(now.timeIntervalSince1970, forKey: timestampKey)

        // Also update a global "last unlock" timestamp so main app knows something changed
        defaults.set(now.timeIntervalSince1970, forKey: "ext_last_unlock_timestamp")
    }

    /// Schedule a local notification when learning goal is completed and shield is lifted
    /// Extensions CAN schedule local notifications - they share notification permissions with the main app
    private nonisolated func scheduleGoalCompletedNotification(rewardMinutes: Int, rewardAppID: String, defaults: UserDefaults) {
        // Check if we already sent this notification today to avoid duplicates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayKey = dateFormatter.string(from: Date())
        let notificationSentKey = "ext_goal_notification_\(rewardAppID)_\(todayKey)"

        if defaults.bool(forKey: notificationSentKey) {
            debugLog("NOTIFICATION: Already sent goal notification for \(String(rewardAppID.prefix(12))) today", defaults: defaults)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Goal Complete!"
        content.body = "You've earned \(rewardMinutes) minutes of reward time. Enjoy your games!"
        content.sound = .default
        content.categoryIdentifier = "learningGoal"

        let identifier = "ext_goal_completed_\(rewardAppID)_\(todayKey)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Immediate delivery
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.debugLog("NOTIFICATION: ❌ Failed to schedule - \(error.localizedDescription)", defaults: defaults)
            } else {
                // Mark as sent to prevent duplicates
                defaults.set(true, forKey: notificationSentKey)
                self?.debugLog("NOTIFICATION: ✅ Scheduled goal completed notification for \(String(rewardAppID.prefix(12)))", defaults: defaults)
            }
        }
    }

    // MARK: - Unified Shield Blocking (downtime, daily limit, or reward time expired)
    // Uses the same extensionShieldConfigs data as unlocking for consistency

    /// Check if current time is within the allowed time window
    /// Returns true if within allowed window (app CAN be used), false if in downtime (app should be blocked)
    private nonisolated func isCurrentTimeInAllowedWindow(_ goalConfig: ExtensionGoalConfigMinimal) -> Bool {
        // Full day access = always allowed
        if goalConfig.isFullDayAllowed { return true }

        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTotalMinutes = currentHour * 60 + currentMinute

        let startTotal = goalConfig.allowedStartHour * 60 + goalConfig.allowedStartMinute
        let endTotal = goalConfig.allowedEndHour * 60 + goalConfig.allowedEndMinute

        // Check if current time is within allowed window
        return currentTotalMinutes >= startTotal && currentTotalMinutes < endTotal
    }

    /// Check if any reward app should be blocked due to downtime, daily limit, or exhausted earned time
    /// Priority: Downtime (highest) > Daily limit > Reward time expired (lowest)
    /// This uses the same data source (extensionShieldConfigs) as the unlock logic
    private nonisolated func checkAndBlockIfRewardTimeExhausted(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: "extensionShieldConfigs"),
              let configs = try? JSONDecoder().decode(ExtensionShieldConfigsMinimal.self, from: data) else {
            return
        }

        for goalConfig in configs.goalConfigs {
            // Get reward app usage (today)
            let usageKey = "usage_\(goalConfig.rewardAppLogicalID)_today"
            let usageSeconds = defaults.integer(forKey: usageKey)
            let usageMinutes = usageSeconds / 60

            // Check 0: Downtime (HIGHEST priority)
            // Block if current time is outside allowed window
            if !isCurrentTimeInAllowedWindow(goalConfig) {
                guard let token = try? PropertyListDecoder().decode(
                    ApplicationToken.self,
                    from: goalConfig.rewardAppTokenData
                ) else { continue }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                if !currentShields.contains(token) {
                    currentShields.insert(token)
                    managedSettingsStore.shield.applications = currentShields

                    // Record block state for main app to sync
                    recordBlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)

                    // Persist blocking reason for ShieldConfigurationExtension
                    persistBlockingReason(
                        tokenHash: goalConfig.rewardAppLogicalID,
                        reasonType: "downtime",
                        usedMinutes: usageMinutes,
                        defaults: defaults
                    )

                    debugLog("DOWNTIME_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... outside allowed window \(goalConfig.allowedStartHour):\(goalConfig.allowedStartMinute)-\(goalConfig.allowedEndHour):\(goalConfig.allowedEndMinute)", defaults: defaults)
                }
                continue  // Skip other checks - downtime takes priority
            }

            // Check 1: Daily limit exceeded (higher priority)
            // 1440 minutes = 24 hours = unlimited
            let dailyLimit = goalConfig.dailyLimitMinutes
            if dailyLimit < 1440 && usageMinutes >= dailyLimit {
                guard let token = try? PropertyListDecoder().decode(
                    ApplicationToken.self,
                    from: goalConfig.rewardAppTokenData
                ) else { continue }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                if !currentShields.contains(token) {
                    currentShields.insert(token)
                    managedSettingsStore.shield.applications = currentShields

                    // Record block state for main app to sync
                    recordBlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)

                    // Persist blocking reason for ShieldConfigurationExtension
                    persistBlockingReason(
                        tokenHash: goalConfig.rewardAppLogicalID,
                        reasonType: "dailyLimitReached",
                        usedMinutes: usageMinutes,
                        defaults: defaults
                    )

                    debugLog("DAILY_LIMIT_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... used=\(usageMinutes)min >= limit=\(dailyLimit)min", defaults: defaults)
                }
                continue  // Skip reward time check - daily limit takes priority
            }

            // Check 2: Reward time exhausted (lower priority)
            // Calculate total earned minutes from met learning goals
            let earnedMinutes = calculateEarnedMinutes(goalConfig: goalConfig, defaults: defaults)

            // If usage >= earned AND earned > 0, re-apply shield
            // (earned > 0 means goals were met at some point today)
            if earnedMinutes > 0 && usageMinutes >= earnedMinutes {
                guard let token = try? PropertyListDecoder().decode(
                    ApplicationToken.self,
                    from: goalConfig.rewardAppTokenData
                ) else { continue }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                if !currentShields.contains(token) {
                    currentShields.insert(token)
                    managedSettingsStore.shield.applications = currentShields

                    // Record block state for main app to sync
                    recordBlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)

                    // Persist blocking reason for ShieldConfigurationExtension
                    persistBlockingReason(
                        tokenHash: goalConfig.rewardAppLogicalID,
                        reasonType: "rewardTimeExpired",
                        usedMinutes: usageMinutes,
                        defaults: defaults
                    )
                }
            }
        }
    }

    /// Calculate total earned reward minutes for a reward app based on met learning goals
    /// Uses the same logic as checkGoalMet() but returns the reward minutes instead of bool
    private nonisolated func calculateEarnedMinutes(
        goalConfig: ExtensionGoalConfigMinimal,
        defaults: UserDefaults
    ) -> Int {
        switch goalConfig.unlockMode {
        case "any":
            // First met goal earns reward minutes (proportional)
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                if usageMinutes >= linked.minutesRequired {
                    // Calculate proportional reward using ratio (rewardMinutesEarned per ratioLearningMinutes)
                    // E.g., 1:1 ratio = 1 reward per 1 learning minute
                    let ratio = Double(linked.rewardMinutesEarned) / Double(max(1, linked.ratioLearningMinutes))
                    let earned = Double(usageMinutes) * ratio
                    return Int(earned)
                }
            }
            return 0

        case "all":
            // All goals must be met (at least threshold reached), then sum all earned rewards
            var totalEarned = 0
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                if usageMinutes < linked.minutesRequired {
                    return 0  // Not all goals met (threshold not reached)
                }
                // Calculate proportional reward using ratio (rewardMinutesEarned per ratioLearningMinutes)
                // E.g., 1:1 ratio = 1 reward per 1 learning minute
                let ratio = Double(linked.rewardMinutesEarned) / Double(max(1, linked.ratioLearningMinutes))
                let earned = Double(usageMinutes) * ratio
                totalEarned += Int(earned)
            }
            return totalEarned

        default:
            return 0
        }
    }

    /// Persist blocking reason for ShieldConfigurationExtension to display correct message
    private nonisolated func persistBlockingReason(
        tokenHash: String,
        reasonType: String,
        usedMinutes: Int,
        defaults: UserDefaults
    ) {
        let key = "appBlocking_\(tokenHash)"
        let blockingInfo: [String: Any] = [
            "tokenHash": tokenHash,
            "reasonType": reasonType,
            "updatedAt": Date().timeIntervalSince1970,
            "rewardUsedMinutes": usedMinutes
        ]
        defaults.set(blockingInfo, forKey: key)
    }

    /// Record block state for main app to sync
    private nonisolated func recordBlockState(rewardAppLogicalID: String, defaults: UserDefaults) {
        let now = Date()
        let stateKey = "ext_block_\(rewardAppLogicalID)"
        let timestampKey = "ext_block_\(rewardAppLogicalID)_timestamp"

        defaults.set(true, forKey: stateKey)
        defaults.set(now.timeIntervalSince1970, forKey: timestampKey)

        // Update global "last block" timestamp so main app knows something changed
        defaults.set(now.timeIntervalSince1970, forKey: "ext_last_block_timestamp")
    }
}

// MARK: - Minimal Structs for Shield Config (avoid importing main app's models)
// These mirror the structures in ExtensionShieldConfig.swift but are self-contained

private struct ExtensionGoalConfigMinimal: Codable {
    let rewardAppLogicalID: String
    let rewardAppTokenData: Data
    let linkedLearningApps: [LinkedGoalMinimal]
    let unlockMode: String
    let dailyLimitMinutes: Int  // Daily limit in minutes (1440 = unlimited)

    // Time window fields (for today's allowed window)
    let allowedStartHour: Int      // 0-23
    let allowedStartMinute: Int    // 0-59
    let allowedEndHour: Int        // 0-23
    let allowedEndMinute: Int      // 0-59
    let isFullDayAllowed: Bool     // true = no time restriction

    struct LinkedGoalMinimal: Codable {
        let learningAppLogicalID: String
        let minutesRequired: Int
        let ratioLearningMinutes: Int  // Ratio input: every X minutes of learning...
        let rewardMinutesEarned: Int   // Ratio output: ...grants Y minutes of reward
    }
}

private struct ExtensionShieldConfigsMinimal: Codable {
    var goalConfigs: [ExtensionGoalConfigMinimal]
    var lastUpdated: Date
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
