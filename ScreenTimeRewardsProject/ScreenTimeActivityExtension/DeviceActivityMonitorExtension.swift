import DeviceActivity
import Foundation
import Darwin // For mach_task_self_ and task_info
import ManagedSettings

/// Memory-optimized DeviceActivityMonitor extension with continuous tracking support
/// Target: <6MB memory usage
/// Strategy: Primitive key-value storage + re-arm signaling for minute-by-minute tracking
final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {

    // MARK: - Constants
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    // NOTE: cooldownSeconds removed - SET semantics prevent double-counting naturally

    // MARK: - Shield Control
    /// ManagedSettingsStore for direct shield manipulation
    /// The extension can use this to unblock reward apps when learning goals are met
    private let managedSettingsStore = ManagedSettingsStore()

    // MARK: - Debug Logging
    /// Write debug log entry to shared UserDefaults buffer (last 100 entries)
    private nonisolated func debugLog(_ message: String, defaults: UserDefaults) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"

        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
        let trimmedLines = Array(lines.suffix(99)) // Keep last 99 to add 1 more
        log = (trimmedLines + [entry]).joined(separator: "\n")
        defaults.set(log, forKey: "extension_debug_log")
        defaults.synchronize() // Ensure log is persisted before extension terminates
    }

    // MARK: - Lifecycle
    override nonisolated init() {
        super.init()
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(true, forKey: "extension_initialized_flag")
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")
            defaults.synchronize()
        }
    }

    // MARK: - Interval Events
    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        updateHeartbeat()
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        // No-op
    }

    // MARK: - Threshold Event Handler
    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
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
        guard let appID = defaults.string(forKey: mapIdKey) else {
            // Try to read from JSON eventMappings as fallback
            if let mapping = readEventMappingFromJSON(eventName: eventName, defaults: defaults) {
                return recordUsageWithMapping(mapping, eventName: eventName, defaults: defaults)
            }
            debugLog("NO_MAPPING event=\(eventName)", defaults: defaults)
            return false
        }

        // 2. Extract the minute number from event name (e.g., "usage.app.0.min.15" → 15)
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        // DEBUG: Log event received with current state
        let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
        let currentThreshold = defaults.integer(forKey: "usage_\(appID)_lastThreshold")
        debugLog("EVENT appID=\(appID.prefix(8))... min=\(thresholdMinutes) currentToday=\(currentToday)s lastThresh=\(currentThreshold)s", defaults: defaults)

        // 3. SET usage to threshold value (not INCREMENT)
        let now = Date().timeIntervalSince1970
        let didUpdate = setUsageToThreshold(appID: appID, thresholdSeconds: thresholdSeconds, defaults: defaults)

        if !didUpdate {
            return false
        }

        // 4. Signal re-arm request for continuous tracking
        defaults.set(true, forKey: "rearm_\(appID)_requested")
        defaults.set(now, forKey: "rearm_\(appID)_time")
        defaults.synchronize()

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        // Called after EVERY usage event (learning or reward) because:
        // - Reward app usage might exceed earned time -> block
        // - Learning app usage might increase earned time (but we still check for exhaustion)
        checkAndBlockIfRewardTimeExhausted(defaults: defaults)

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
            defaults.set(60, forKey: "ext_usage_\(appID)_today")
            defaults.set(60, forKey: "ext_usage_\(appID)_total")
            defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
            defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
            defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")
            debugLog("EXT_INC appID=\(appID.prefix(8))... NEW_DAY ext_today=60s", defaults: defaults)

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

            // Check 1: Within 120s of monitoring restart → ALWAYS skip (catch-up from app list change)
            if timeSinceRestart < 120.0 && restartTimestamp > 0 {
                debugLog("SKIP_RESTART appID=\(appID.prefix(8))... timeSinceRestart=\(Int(timeSinceRestart))s < 120s", defaults: defaults)
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
        defaults.set(newExtToday, forKey: "ext_usage_\(appID)_today")
        defaults.set(currentExtTotal + 60, forKey: "ext_usage_\(appID)_total")
        defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
        defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
        defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")
        debugLog("EXT_INC appID=\(appID.prefix(8))... ext_today=\(newExtToday)s (was \(currentExtToday)s, +60s)", defaults: defaults)

        // === HOURLY BUCKET TRACKING ===
        let storedHourlyDate = defaults.string(forKey: "ext_usage_\(appID)_hourly_date")
        if storedHourlyDate != dateString {
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
        defaults.synchronize()

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        checkAndBlockIfRewardTimeExhausted(defaults: defaults)

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
            defaults.synchronize()
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
        defaults.synchronize()

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
        guard let data = defaults.data(forKey: "extensionShieldConfigs"),
              let configs = try? JSONDecoder().decode(ExtensionShieldConfigsMinimal.self, from: data) else {
            return
        }

        for goalConfig in configs.goalConfigs {
            let isGoalMet = checkGoalMet(goalConfig: goalConfig, defaults: defaults)

            if isGoalMet {
                guard let token = try? PropertyListDecoder().decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) else {
                    continue
                }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                if currentShields.contains(token) {
                    currentShields.remove(token)
                    managedSettingsStore.shield.applications = currentShields.isEmpty ? nil : currentShields
                    recordUnlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)
                }
            }
        }
    }

    /// Check if a reward app's learning goal is met
    private nonisolated func checkGoalMet(goalConfig: ExtensionGoalConfigMinimal, defaults: UserDefaults) -> Bool {
        switch goalConfig.unlockMode {
        case "any":
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                if usageMinutes >= linked.minutesRequired {
                    return true
                }
            }
            return false

        case "all":
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                if usageMinutes < linked.minutesRequired {
                    return false
                }
            }
            return !goalConfig.linkedLearningApps.isEmpty

        default:
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

        defaults.synchronize()
    }

    // MARK: - Unified Shield Blocking (when reward time expires)
    // Uses the same extensionShieldConfigs data as unlocking for consistency

    /// Check if any reward app has exhausted its earned time and block it
    /// Formula: rewardAppUsageMinutes >= earnedRewardMinutes → Re-apply shield
    /// This uses the same data source (extensionShieldConfigs) as the unlock logic
    private nonisolated func checkAndBlockIfRewardTimeExhausted(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: "extensionShieldConfigs"),
              let configs = try? JSONDecoder().decode(ExtensionShieldConfigsMinimal.self, from: data) else {
            return
        }

        for goalConfig in configs.goalConfigs {
            // 1. Calculate total earned minutes from met learning goals
            let earnedMinutes = calculateEarnedMinutes(goalConfig: goalConfig, defaults: defaults)

            // 2. Get reward app usage (today)
            let usageKey = "usage_\(goalConfig.rewardAppLogicalID)_today"
            let usageSeconds = defaults.integer(forKey: usageKey)
            let usageMinutes = usageSeconds / 60

            // 3. If usage >= earned AND earned > 0, re-apply shield
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
                        tokenHash: goalConfig.rewardAppLogicalID,  // Use logicalID as key
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
            // First met goal earns reward minutes (for each completed round)
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                if usageMinutes >= linked.minutesRequired {
                    // Calculate completed rounds and earn reward for each round
                    let completedRounds = usageMinutes / linked.minutesRequired
                    return completedRounds * linked.rewardMinutesEarned
                }
            }
            return 0

        case "all":
            // All goals must be met (at least 1 round each), then sum all earned rewards
            var totalEarned = 0
            for linked in goalConfig.linkedLearningApps {
                let usageKey = "usage_\(linked.learningAppLogicalID)_today"
                let usageSeconds = defaults.integer(forKey: usageKey)
                let usageMinutes = usageSeconds / 60
                if usageMinutes < linked.minutesRequired {
                    return 0  // Not all goals met (at least 1 round required)
                }
                // Calculate completed rounds and earn reward for each round
                let completedRounds = usageMinutes / linked.minutesRequired
                totalEarned += completedRounds * linked.rewardMinutesEarned
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

        defaults.synchronize()
    }
}

// MARK: - Minimal Structs for Shield Config (avoid importing main app's models)
// These mirror the structures in ExtensionShieldConfig.swift but are self-contained

private struct ExtensionGoalConfigMinimal: Codable {
    let rewardAppLogicalID: String
    let rewardAppTokenData: Data
    let linkedLearningApps: [LinkedGoalMinimal]
    let unlockMode: String

    struct LinkedGoalMinimal: Codable {
        let learningAppLogicalID: String
        let minutesRequired: Int
        let rewardMinutesEarned: Int
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
