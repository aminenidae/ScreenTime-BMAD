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
    /// Ensures lifecycle log only fires once per process (init() is called per event)
    private static var hasLoggedSession = false

    // MARK: - Constants
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    // NOTE: cooldownSeconds removed - SET semantics prevent double-counting naturally

    // MARK: - Shield Control
    /// ManagedSettingsStore for direct shield manipulation
    /// The extension can use this to unblock reward apps when learning goals are met
    private let managedSettingsStore = ManagedSettingsStore()

    // MARK: - Debug Logging
    /// Cached DateFormatters — Apple warns against creating these repeatedly
    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static let dayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let lifecycleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Cached Expensive Objects
    /// Decoders/encoders are expensive to create (~50-100KB each). Cache as static lets.
    private static let propertyListDecoder = PropertyListDecoder()
    private static let jsonDecoder = JSONDecoder()
    private static let jsonEncoder = JSONEncoder()
    /// Calendar.current triggers locale/timezone resolution each call
    private static let calendar = Calendar.current

    /// Max log size in bytes before trimming (~50KB)
    private static let maxLogBytes = 50_000
    /// Lines to keep after trim
    private static let trimToLines = 200

    /// Lifecycle log limits (larger — events are rare, ~5-20/day)
    private static let maxLifecycleLogBytes = 100_000
    private static let lifecycleTrimToLines = 400

    /// Midnight diagnostic log limits (small — only midnight→scheduleActivity window)
    private static let maxMidnightLogBytes = 15_000
    private static let midnightTrimToLines = 75

    /// O(1) append-only debug log — avoids catastrophic read-parse-rewrite cycle
    /// Only trims when buffer exceeds size threshold
    private nonisolated func debugLog(_ message: String, defaults: UserDefaults) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        let entry = "[\(timestamp)][\(Self.sessionID)] \(message)\n"

        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        log.append(entry)

        // Size-based trim: only when exceeding threshold (rare, amortized O(1))
        if log.utf8.count > Self.maxLogBytes {
            let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            let kept = lines.suffix(Self.trimToLines)
            log = kept.joined(separator: "\n") + "\n"
        }

        defaults.set(log, forKey: "extension_debug_log")
    }

    /// Dedicated lifecycle log — ONLY start/stop/kill events for monitoring diagnostics
    private nonisolated func lifecycleLog(_ message: String, defaults: UserDefaults) {
        let timestamp = Self.lifecycleDateFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"

        var log = defaults.string(forKey: "monitoring_lifecycle_log") ?? ""
        log.append(entry)

        if log.utf8.count > Self.maxLifecycleLogBytes {
            let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            let kept = lines.suffix(Self.lifecycleTrimToLines)
            log = kept.joined(separator: "\n") + "\n"
        }

        defaults.set(log, forKey: "monitoring_lifecycle_log")
    }

    /// Midnight diagnostic log — captures EVERYTHING between midnight and first scheduleActivity()
    /// Immune to regular debug log trimming. Only active when midnight_diagnostic_active is true.
    private nonisolated func midnightDiagnosticLog(_ message: String, defaults: UserDefaults) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        let entry = "[\(timestamp)][\(Self.sessionID)] \(message)\n"

        var log = defaults.string(forKey: "midnight_diagnostic_log") ?? ""
        log.append(entry)

        if log.utf8.count > Self.maxMidnightLogBytes {
            let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            let kept = lines.suffix(Self.midnightTrimToLines)
            log = kept.joined(separator: "\n") + "\n"
        }

        defaults.set(log, forKey: "midnight_diagnostic_log")
    }

    // MARK: - Lifecycle
    override nonisolated init() {
        super.init()
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(true, forKey: "extension_initialized_flag")
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")

            // Only log session lifecycle once per process (init() is called per event)
            if !Self.hasLoggedSession {
                Self.hasLoggedSession = true
                let lastSessionID = defaults.string(forKey: "ext_last_session_id")
                if let lastSessionID = lastSessionID, lastSessionID != Self.sessionID {
                    lifecycleLog("EXTENSION_KILLED — new session detected (was: \(lastSessionID), now: \(Self.sessionID))", defaults: defaults)
                }
                defaults.set(Self.sessionID, forKey: "ext_last_session_id")
                lifecycleLog("EXTENSION_INIT session=\(Self.sessionID)", defaults: defaults)
            }
        }
    }

    // MARK: - Interval Events
    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            // Set restart timestamp for 60s safety window
            defaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")

            // === MIDNIGHT DIAGNOSTIC: Only activate on genuine midnight (day changed) ===
            let lastDiagDate = defaults.string(forKey: "midnight_diagnostic_date")
            let todayStr = Self.dayDateFormatter.string(from: Date())
            if lastDiagDate != todayStr {
                // Genuine midnight — day changed. Activate and clear.
                defaults.set(true, forKey: "midnight_diagnostic_active")
                defaults.removeObject(forKey: "midnight_diagnostic_log")
                defaults.set(todayStr, forKey: "midnight_diagnostic_date")
                let diagTrackedIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
                midnightDiagnosticLog("MIDNIGHT_START activity=\(activity.rawValue) trackedApps=\(diagTrackedIDs.count)", defaults: defaults)
                for diagAppID in diagTrackedIDs {
                    let extToday = defaults.integer(forKey: "ext_usage_\(diagAppID)_today")
                    let extDate = defaults.string(forKey: "ext_usage_\(diagAppID)_date") ?? "nil"
                    let lastThresh = defaults.integer(forKey: "usage_\(diagAppID)_lastThreshold")
                    let usageToday = defaults.integer(forKey: "usage_\(diagAppID)_today")
                    midnightDiagnosticLog("  APP_STATE \(diagAppID.prefix(8))... ext_today=\(extToday)s ext_date=\(extDate) lastThresh=\(lastThresh)s usage_today=\(usageToday)s", defaults: defaults)
                }

                // SKIP_MIDNIGHT: Block all events until scheduleActivity() registers fresh thresholds.
                // At midnight, old thresholds remain registered. iOS fires catch-ups for yesterday's
                // residual that would record as phantom today usage. Block until fresh thresholds arrive.
                defaults.set(true, forKey: "midnight_pending_refresh")
                defaults.set(Date().timeIntervalSince1970, forKey: "midnight_pending_timestamp")

                // Clear stale catchup_max — yesterday's values would corrupt new day
                for diagAppID in diagTrackedIDs {
                    defaults.removeObject(forKey: "catchup_max_\(diagAppID)")
                }
                midnightDiagnosticLog("MIDNIGHT_PENDING_SET — blocking events until scheduleActivity, cleared catchup_max for \(diagTrackedIDs.count) apps", defaults: defaults)
            } else if defaults.bool(forKey: "midnight_diagnostic_active") {
                // Non-midnight intervalDidStart (restart-triggered) — log it, don't clear
                midnightDiagnosticLog("RESTART_INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
            }

            debugLog("INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
            lifecycleLog("INTERVAL_START — iOS daily restart (activity=\(activity.rawValue))", defaults: defaults)

            // Load shield configs early — needed for both catchup_max correction and shield evaluation
            let shieldConfigs: ExtensionShieldConfigsMinimal? = {
                guard let data = defaults.data(forKey: "extensionShieldConfigs") else { return nil }
                return try? Self.jsonDecoder.decode(ExtensionShieldConfigsMinimal.self, from: data)
            }()

            // Apply pending catchup_max corrections ONLY for same-day restarts.
            // At midnight, stale catchup_max was cleared above — nothing to apply.
            // This handles the case where extension was killed mid-day and catchup_max
            // was captured from legitimate SKIP_RESTART events.
            let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
            if lastDiagDate == todayStr {
                for trackedAppID in trackedAppIDs {
                    let catchupMaxKey = "catchup_max_\(trackedAppID)"
                    let catchupMax = defaults.integer(forKey: catchupMaxKey)
                    if catchupMax > 0 {
                        // Skip correction for shielded reward apps — phantom catch-ups
                        if isShieldedRewardApp(trackedAppID, defaults: defaults, shieldConfigs: shieldConfigs) {
                            lifecycleLog("CATCHUP_SKIP_SHIELDED \(trackedAppID.prefix(8))... clearing phantom catchup_max=\(catchupMax)s", defaults: defaults)
                            defaults.removeObject(forKey: catchupMaxKey)
                            continue
                        }
                        let currentToday = defaults.integer(forKey: "usage_\(trackedAppID)_today")
                        if catchupMax > currentToday {
                            let correction = catchupMax - currentToday
                            defaults.set(catchupMax, forKey: "usage_\(trackedAppID)_today")
                            defaults.set(catchupMax, forKey: "ext_usage_\(trackedAppID)_today")
                            let currentTotal = defaults.integer(forKey: "ext_usage_\(trackedAppID)_total")
                            defaults.set(max(0, currentTotal + correction), forKey: "ext_usage_\(trackedAppID)_total")
                            defaults.set(max(0, currentTotal + correction), forKey: "usage_\(trackedAppID)_total")
                            lifecycleLog("CATCHUP_CORRECTION \(trackedAppID.prefix(8))... \(currentToday)s → \(catchupMax)s (+\(correction)s)", defaults: defaults)
                        }
                        let dateString = Self.dayDateFormatter.string(from: Date())
                        defaults.set(dateString, forKey: "ext_usage_\(trackedAppID)_date")
                        defaults.set(Date().timeIntervalSince1970, forKey: "ext_usage_\(trackedAppID)_timestamp")
                        defaults.removeObject(forKey: catchupMaxKey)
                    }
                }
            }

            // Reset lastThreshold for all apps — iOS resets its counter on daily restart
            for trackedAppID in trackedAppIDs {
                defaults.set(0, forKey: "usage_\(trackedAppID)_lastThreshold")
            }

            if defaults.bool(forKey: "midnight_diagnostic_active") {
                midnightDiagnosticLog("MIDNIGHT_RESET_COMPLETE — lastThreshold reset for \(trackedAppIDs.count) apps", defaults: defaults)
            }

            // Evaluate shields on monitoring start — usage data is already correct
            // from previous session. Don't wait for events (absorb window blocks first 60s).
            checkAndUpdateShields(configs: shieldConfigs, defaults: defaults)
            checkAndBlockIfRewardTimeExhausted(configs: shieldConfigs, defaults: defaults)
            debugLog("INTERVAL_START_SHIELD_CHECK completed", defaults: defaults)

            // Notify main app to sync shields (covers case where main app is running)
            notifyMainApp()
        }
        updateHeartbeat()
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            debugLog("INTERVAL_END activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
            lifecycleLog("INTERVAL_END — iOS daily cycle (activity=\(activity.rawValue))", defaults: defaults)
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

        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            debugLog("THRESHOLD_RESULT event=\(event.rawValue.suffix(20)) recorded=\(didRecord)", defaults: defaults)

            if !didRecord {
                // Shield check on first rejected event per restart — covers absorb window gap
                // where events are dropped but usage data already satisfies goals
                let restartTs = defaults.double(forKey: "monitoring_restart_timestamp")
                let lastCheck = defaults.double(forKey: "ext_shield_check_after_restart")
                if restartTs > lastCheck {
                    defaults.set(restartTs, forKey: "ext_shield_check_after_restart")
                    let shieldConfigs: ExtensionShieldConfigsMinimal? = {
                        guard let data = defaults.data(forKey: "extensionShieldConfigs") else { return nil }
                        return try? Self.jsonDecoder.decode(ExtensionShieldConfigsMinimal.self, from: data)
                    }()
                    checkAndUpdateShields(configs: shieldConfigs, defaults: defaults)
                    checkAndBlockIfRewardTimeExhausted(configs: shieldConfigs, defaults: defaults)
                    debugLog("ABSORB_SHIELD_CHECK completed (first rejected event after restart)", defaults: defaults)
                }
            }
        }

        if didRecord {
            // Send notification to main app for re-arm and UI update
            notifyMainApp()
        }
    }

    // MARK: - Memory-Efficient Usage Recording

    /// Record usage using only primitive values - no JSON, no structs
    /// Uses +60s INCREMENT per valid event with basic catch-up protection
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

        // Console visibility for development
        print("📝 [EXTENSION] Recording: app=\(appID.prefix(8))... minute=\(thresholdMinutes) currentToday=\(currentToday)s")

        // Decode shield configs ONCE — used by filter chain (shielded app check) and post-recording shield updates
        let shieldConfigs: ExtensionShieldConfigsMinimal? = {
            guard let data = defaults.data(forKey: "extensionShieldConfigs") else { return nil }
            return try? Self.jsonDecoder.decode(ExtensionShieldConfigsMinimal.self, from: data)
        }()

        // 3. Record usage with filter chain (restart window, per-app cooldown, min threshold, shielded app, progression)
        let now = Date().timeIntervalSince1970
        let didUpdate = setUsageToThreshold(appID: appID, thresholdSeconds: thresholdSeconds, defaults: defaults, shieldConfigs: shieldConfigs)

        if !didUpdate {
            debugLog("FILTER_REJECTED appID=\(appID.prefix(8))... min=\(thresholdMinutes) (check SKIP_* entries above)", defaults: defaults)
            return false
        }

        // Confirm recording success in console
        let newToday = defaults.integer(forKey: "usage_\(appID)_today")
        print("✅ [EXTENSION] Recorded +60s - total today: \(newToday)s")

        // 4. Signal re-arm request for continuous tracking
        defaults.set(true, forKey: "rearm_\(appID)_requested")
        defaults.set(now, forKey: "rearm_\(appID)_time")

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(configs: shieldConfigs, defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        checkAndBlockIfRewardTimeExhausted(configs: shieldConfigs, defaults: defaults)

        // EXTENSION CLOUDKIT SYNC: Only if explicitly enabled (disabled by default to save ~1-2MB)
        // Main app handles CloudKit sync on foreground activation
        if defaults.bool(forKey: "ext_cloudkit_sync_enabled") {
            ExtensionCloudKitSync.shared.syncUsageToParent(defaults: defaults)
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

    /// Check if an app is a shielded reward app (user can't use it, so any events are phantom)
    /// Used to prevent catchup_max capture and correction for blocked reward apps.
    private nonisolated func isShieldedRewardApp(_ appID: String, defaults: UserDefaults, shieldConfigs: ExtensionShieldConfigsMinimal?) -> Bool {
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
        guard category == "Reward", let configs = shieldConfigs else { return false }
        for goalConfig in configs.goalConfigs where goalConfig.rewardAppLogicalID == appID {
            if let token = try? Self.propertyListDecoder.decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) {
                let currentShields = managedSettingsStore.shield.applications ?? Set()
                return currentShields.contains(token)
            }
            break
        }
        return false
    }

    /// Record +60s per valid event with robust filter chain
    /// Filter order: restart window → per-app cooldown → min threshold → shielded app → threshold progression
    /// All filters applied BEFORE any recording (including day rollover)
    private nonisolated func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults, shieldConfigs: ExtensionShieldConfigsMinimal?) -> Bool {
        let now = Date()
        let nowTimestamp = now.timeIntervalSince1970
        let midnightDiagActive = defaults.bool(forKey: "midnight_diagnostic_active")

        // ═══════════ FILTER CHAIN — applied to ALL events before any recording ═══════════
        // Compute calendar values once for use in both filters and recording
        let calendar = Self.calendar
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970

        // Filter 0: SKIP_MIDNIGHT — block ALL events between midnight and first scheduleActivity()
        // At midnight, intervalDidStart() fires but scheduleActivity() does NOT. Yesterday's
        // stale thresholds remain; iOS fires catch-ups with cumulative that includes yesterday's
        // residual. These must be blocked to prevent phantom overcounting.
        let midnightPending = defaults.bool(forKey: "midnight_pending_refresh")
        if midnightPending {
            let midnightTimestamp = defaults.double(forKey: "midnight_pending_timestamp")
            let timeSinceMidnight = nowTimestamp - midnightTimestamp
            if timeSinceMidnight < 7200.0 {  // 2-hour safety timeout
                debugLog("SKIP_MIDNIGHT appID=\(appID.prefix(8))... timeSince=\(Int(timeSinceMidnight))s thresh=\(thresholdSeconds)s", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_MIDNIGHT appID=\(appID.prefix(8))... timeSince=\(Int(timeSinceMidnight))s thresh=\(thresholdSeconds)s", defaults: defaults) }
                return false
            } else {
                // Safety timeout expired — clear flag and resume recording
                defaults.set(false, forKey: "midnight_pending_refresh")
                debugLog("MIDNIGHT_TIMEOUT — 2hr expired, clearing midnight_pending_refresh", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_MIDNIGHT_TIMEOUT clearing flag after \(Int(timeSinceMidnight))s", defaults: defaults) }
            }
        }

        // Filter 1: 60s restart window with catchup_max capture
        // After scheduleActivity() registers fresh thresholds, iOS fires catch-ups for real
        // today usage. Capture the max threshold per app — safe because SKIP_MIDNIGHT blocks
        // stale cross-midnight catch-ups upstream. Only legitimate post-scheduleActivity
        // catch-ups reach here.
        let restartTimestamp = defaults.double(forKey: "monitoring_restart_timestamp")
        let timeSinceRestart = nowTimestamp - restartTimestamp
        if timeSinceRestart < 60.0 && restartTimestamp > 0 {
            // Skip catchup_max capture for shielded reward apps — user can't use a blocked app,
            // so any catch-up events are phantom. Prevents phantom inflation of reward app usage.
            if isShieldedRewardApp(appID, defaults: defaults, shieldConfigs: shieldConfigs) {
                debugLog("SKIP_RESTART_SHIELDED appID=\(appID.prefix(8))... shielded reward app, skipping catchup_max capture thresh=\(thresholdSeconds)s", defaults: defaults)
            } else {
                let catchupMaxKey = "catchup_max_\(appID)"
                let currentMax = defaults.integer(forKey: catchupMaxKey)
                if thresholdSeconds > currentMax {
                    defaults.set(thresholdSeconds, forKey: catchupMaxKey)
                }
                debugLog("SKIP_RESTART appID=\(appID.prefix(8))... catchup_max=\(max(thresholdSeconds, currentMax))s timeSinceRestart=\(Int(timeSinceRestart))s", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_RESTART_CAPTURE appID=\(appID.prefix(8))... catchup_max=\(max(thresholdSeconds, currentMax))s timeSinceRestart=\(Int(timeSinceRestart))s", defaults: defaults) }
            }
            return false
        }

        // Post-restart: reset lastThreshold for all apps so threshold progression
        // filter doesn't block genuine events (post-restart thresholds may be lower
        // than pre-restart lastThreshold)
        // Post-restart: reset lastThreshold for all apps so threshold progression
        // filter doesn't block genuine events (post-restart thresholds may be lower
        // than pre-restart lastThreshold). catchup_max is NOT consumed here — it's
        // applied in the recording section (before-recording for same-day, NEW_DAY for new day).
        let lastHandledRestart = defaults.double(forKey: "ext_lastHandledRestartTimestamp")
        if restartTimestamp > lastHandledRestart && restartTimestamp > 0 {
            let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
            debugLog("RESTART_RESET_BEGIN tracked_app_ids=[\(trackedAppIDs.map { String($0.prefix(8)) + "..." }.joined(separator: ","))] count=\(trackedAppIDs.count)", defaults: defaults)
            for trackedAppID in trackedAppIDs {
                let oldThresh = defaults.integer(forKey: "usage_\(trackedAppID)_lastThreshold")
                debugLog("RESTART_RESET \(trackedAppID.prefix(8))... lastThresh=\(oldThresh) → 0", defaults: defaults)
                defaults.set(0, forKey: "usage_\(trackedAppID)_lastThreshold")
            }
            defaults.set(restartTimestamp, forKey: "ext_lastHandledRestartTimestamp")
            debugLog("RESTART_THRESHOLD_RESET: Reset lastThreshold for \(trackedAppIDs.count) apps", defaults: defaults)
            if midnightDiagActive { midnightDiagnosticLog("DIAG_RESTART_RESET resetApps=\(trackedAppIDs.count)", defaults: defaults) }
        }

        // Filter 2: 55s per-app cooldown
        // Same app can't legitimately fire twice in <55s (thresholds are 60s apart)
        // Different apps CAN fire close together when user switches between apps
        // EXCEPTION: iOS deferred batch events where threshold > lastThreshold represent
        // real usage that was queued while extension was killed — let these through.
        // Filter 5 (threshold progression) handles ordering; delta calculation handles amounts.
        let perAppCooldownKey = "last_recorded_\(appID)"
        let lastRecordedForApp = defaults.double(forKey: perAppCooldownKey)
        let timeSinceLastForApp = nowTimestamp - lastRecordedForApp
        let lastThresholdForCooldown = defaults.integer(forKey: "usage_\(appID)_lastThreshold")
        if timeSinceLastForApp < 55.0 && lastRecordedForApp > 0 && thresholdSeconds <= lastThresholdForCooldown {
            debugLog("SKIP_COOLDOWN appID=\(appID.prefix(8))... timeSinceLastForApp=\(Int(timeSinceLastForApp))s < 55s, threshold=\(thresholdSeconds)s <= lastThresh=\(lastThresholdForCooldown)s (dropped)", defaults: defaults)
            if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_COOLDOWN appID=\(appID.prefix(8))... timeSinceLastForApp=\(Int(timeSinceLastForApp))s thresh=\(thresholdSeconds)s", defaults: defaults) }
            return false
        }

        // Filter 3: Minimum threshold validation
        // All configured thresholds are >= 60s (1 minute minimum)
        // Values below 60 indicate OS regression (0-minute phantom fires)
        if thresholdSeconds < 60 {
            debugLog("SKIP_INVALID appID=\(appID.prefix(8))... thresholdSeconds=\(thresholdSeconds) < 60", defaults: defaults)
            return false
        }

        // Filter 4: Shielded reward app — user can't use a blocked app, so events are phantom
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
        if category == "Reward", let configs = shieldConfigs {
            for goalConfig in configs.goalConfigs where goalConfig.rewardAppLogicalID == appID {
                if let token = try? Self.propertyListDecoder.decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) {
                    let currentShields = managedSettingsStore.shield.applications ?? Set()
                    if currentShields.contains(token) {
                        debugLog("SKIP_SHIELDED appID=\(appID.prefix(8))... reward app is currently blocked", defaults: defaults)
                        return false
                    }
                }
                break
            }
        }

        // Filter 5: Threshold progression
        // Same day: cumulative usage only grows, so thresholds must strictly increase
        // Cross-day: thresholds restart from min.1, just block exact duplicates
        let lastThresholdKey = "usage_\(appID)_lastThreshold"
        var lastThreshold = defaults.integer(forKey: lastThresholdKey)
        let todayResetKey = "usage_\(appID)_reset"
        let lastResetTimestamp = defaults.double(forKey: todayResetKey)

        if lastResetTimestamp >= startOfToday {
            // Same day: threshold must strictly increase (usage is monotonic within a day)
            if thresholdSeconds <= lastThreshold {
                debugLog("SKIP_REGRESSION appID=\(appID.prefix(8))... threshold=\(thresholdSeconds) <= lastThreshold=\(lastThreshold) (same day)", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_REGRESSION appID=\(appID.prefix(8))... thresh=\(thresholdSeconds) lastThresh=\(lastThreshold) sameDay=true", defaults: defaults) }
                return false
            }
        } else {
            // Cross-day: thresholds restart from min.1, just block exact duplicates
            if thresholdSeconds == lastThreshold {
                debugLog("SKIP_DUP appID=\(appID.prefix(8))... threshold=\(thresholdSeconds) == lastThreshold (cross-day)", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_DUP appID=\(appID.prefix(8))... thresh=\(thresholdSeconds) lastThresh=\(lastThreshold) crossDay=true", defaults: defaults) }
                return false
            }
        }

        // ═══════════ CATCHUP CORRECTION — apply before recording (SAME-DAY ONLY) ═══════════
        // For new-day events, catchup_max is handled by the NEW_DAY branch below
        // (must be read BEFORE resetAllDailyCounters clears it).
        // For same-day events, adjust usage upward to match iOS ground truth.
        let catchupMaxKey = "catchup_max_\(appID)"
        let catchupMax = defaults.integer(forKey: catchupMaxKey)
        if catchupMax > 0 && lastResetTimestamp >= startOfToday {
            let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
            if catchupMax > currentToday {
                let correction = catchupMax - currentToday
                defaults.set(catchupMax, forKey: "usage_\(appID)_today")
                defaults.set(catchupMax, forKey: "ext_usage_\(appID)_today")
                let currentTotal = defaults.integer(forKey: "ext_usage_\(appID)_total")
                defaults.set(max(0, currentTotal + correction), forKey: "ext_usage_\(appID)_total")
                defaults.set(max(0, currentTotal + correction), forKey: "usage_\(appID)_total")
                debugLog("CATCHUP_CORRECTION appID=\(appID.prefix(8))... \(currentToday)s → \(catchupMax)s (+\(correction)s)", defaults: defaults)
                defaults.set(catchupMax, forKey: lastThresholdKey)
                lastThreshold = catchupMax  // Update local var so delta calculation uses corrected base
            }
            // ALWAYS set date when catchup_max exists — value may already match but date could be missing
            let corrDateStr = Self.dayDateFormatter.string(from: now)
            defaults.set(corrDateStr, forKey: "ext_usage_\(appID)_date")
            defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")
            defaults.removeObject(forKey: catchupMaxKey)
        }

        // ═══════════ PASSED ALL FILTERS — proceed to record ═══════════

        let todayKey = "usage_\(appID)_today"
        let totalKey = "usage_\(appID)_total"
        let dateString = Self.dayDateFormatter.string(from: now)
        let hour = calendar.component(.hour, from: now)

        // Day rollover check
        if lastResetTimestamp < startOfToday {
            // Read catchup_max BEFORE resetAllDailyCounters clears it.
            // catchup_max represents real today usage captured during SKIP_RESTART
            // (post-scheduleActivity catch-ups that exactly match iOS cumulative).
            let appCatchupMax = defaults.integer(forKey: "catchup_max_\(appID)")

            let globalResetKey = "global_daily_reset_timestamp"
            let lastGlobalReset = defaults.double(forKey: globalResetKey)

            if lastGlobalReset < startOfToday {
                debugLog("DAY_ROLLOVER appID=\(appID.prefix(8))... globalReset triggered", defaults: defaults)
                resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
                defaults.set(startOfToday, forKey: globalResetKey)
                notifyMainApp()
            }

            // Initialize: catchup_max (real usage before restart) + 60s (this event)
            // Example: YouTube had 25 min of real usage → catch-ups captured max=1500s
            // initialUsage = 1500 + 60 = 1560s (26 min: 25 min catch-up + 1 min current)
            let initialUsage = (appCatchupMax > 0 ? appCatchupMax : 0) + 60
            debugLog("NEW_DAY appID=\(appID.prefix(8))... catchupMax=\(appCatchupMax)s initialUsage=\(initialUsage)s thresh=\(thresholdSeconds)s", defaults: defaults)
            if midnightDiagActive { midnightDiagnosticLog("DIAG_NEW_DAY appID=\(appID.prefix(8))... catchupMax=\(appCatchupMax)s initial=\(initialUsage)s thresh=\(thresholdSeconds)s", defaults: defaults) }
            defaults.set(initialUsage, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            defaults.set(initialUsage, forKey: totalKey)
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
            defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

            // ext_ keys
            debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... NEW_DAY today=\(initialUsage) total=\(initialUsage) date=\(dateString) hour=\(hour)", defaults: defaults)
            defaults.set(initialUsage, forKey: "ext_usage_\(appID)_today")
            defaults.set(initialUsage, forKey: "ext_usage_\(appID)_total")
            defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
            defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
            defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")

            // Hourly buckets
            for h in 0..<24 {
                defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
            }
            defaults.set(initialUsage, forKey: "ext_usage_\(appID)_hourly_\(hour)")
            defaults.set(dateString, forKey: "ext_usage_\(appID)_hourly_date")

            // Clear catchup_max after consumption (may already be cleared by resetAllDailyCounters)
            defaults.removeObject(forKey: "catchup_max_\(appID)")

            trackAppID(appID, defaults: defaults)
            defaults.set(nowTimestamp, forKey: "last_recorded_\(appID)")
            defaults.set(nowTimestamp, forKey: "last_recorded_timestamp") // diagnostics
            return true
        }

        // Same day — use threshold delta when we have a reliable lastThreshold (>0),
        // otherwise fall back to safe +60 to prevent phantom threshold amplification.
        // lastThreshold > 0 means it was set by a previous recording in this session.
        // lastThreshold = 0 means daily reset or post-restart — can't trust delta.
        let currentToday = defaults.integer(forKey: todayKey)
        let delta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60
        let newToday = currentToday + delta
        debugLog("RECORDED appID=\(appID.prefix(8))... oldToday=\(currentToday)s +\(delta) = newToday=\(newToday)s, thresh=\(thresholdSeconds)s", defaults: defaults)
        if midnightDiagActive { midnightDiagnosticLog("DIAG_INCREMENT appID=\(appID.prefix(8))... old=\(currentToday)s +\(delta)s = \(newToday)s thresh=\(thresholdSeconds)s lastThresh=\(lastThreshold)s", defaults: defaults) }
        defaults.set(newToday, forKey: todayKey)
        defaults.set(thresholdSeconds, forKey: lastThresholdKey)

        // Update total
        let currentTotal = defaults.integer(forKey: totalKey)
        defaults.set(currentTotal + delta, forKey: totalKey)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

        // ext_ keys (source of truth)
        let currentExtToday = defaults.integer(forKey: "ext_usage_\(appID)_today")
        let currentExtTotal = defaults.integer(forKey: "ext_usage_\(appID)_total")
        let currentExtDate = defaults.string(forKey: "ext_usage_\(appID)_date")

        let newExtToday = (currentExtDate == dateString) ? currentExtToday + delta : delta

        debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... INCREMENT today=\(newExtToday) total=\(currentExtTotal + delta) hour=\(hour)", defaults: defaults)
        defaults.set(newExtToday, forKey: "ext_usage_\(appID)_today")
        defaults.set(currentExtTotal + delta, forKey: "ext_usage_\(appID)_total")
        defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
        defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
        defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")

        // Hourly buckets
        let storedHourlyDate = defaults.string(forKey: "ext_usage_\(appID)_hourly_date")
        if storedHourlyDate != dateString {
            debugLog("HOURLY_RESET appID=\(appID.prefix(8))... date changed from \(storedHourlyDate ?? "nil") to \(dateString)", defaults: defaults)
            for h in 0..<24 {
                defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
            }
            defaults.set(dateString, forKey: "ext_usage_\(appID)_hourly_date")
        }
        let currentHourlySeconds = defaults.integer(forKey: "ext_usage_\(appID)_hourly_\(hour)")
        defaults.set(currentHourlySeconds + delta, forKey: "ext_usage_\(appID)_hourly_\(hour)")

        trackAppID(appID, defaults: defaults)
        defaults.set(nowTimestamp, forKey: "last_recorded_\(appID)")
        defaults.set(nowTimestamp, forKey: "last_recorded_timestamp") // diagnostics
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
    private nonisolated func recordUsageWithMapping(_ mapping: (appID: String, increment: Int, displayName: String, category: String, rewardPoints: Int), eventName: String, defaults: UserDefaults) -> Bool {
        let now = Date().timeIntervalSince1970

        // Extract threshold minutes from event name
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        // Decode shield configs ONCE — used by filter chain and post-recording shield updates
        let shieldConfigs: ExtensionShieldConfigsMinimal? = {
            guard let data = defaults.data(forKey: "extensionShieldConfigs") else { return nil }
            return try? Self.jsonDecoder.decode(ExtensionShieldConfigsMinimal.self, from: data)
        }()

        let didUpdate = setUsageToThreshold(appID: mapping.appID, thresholdSeconds: thresholdSeconds, defaults: defaults, shieldConfigs: shieldConfigs)

        if !didUpdate {
            return false
        }

        // Update JSON persistence for compatibility
        updateJSONPersistence(appID: mapping.appID, increment: 60, rewardPoints: mapping.rewardPoints, defaults: defaults)

        // Signal re-arm request
        defaults.set(true, forKey: "rearm_\(mapping.appID)_requested")
        defaults.set(now, forKey: "rearm_\(mapping.appID)_time")

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(configs: shieldConfigs, defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        checkAndBlockIfRewardTimeExhausted(configs: shieldConfigs, defaults: defaults)

        // EXTENSION CLOUDKIT SYNC: Only if explicitly enabled (disabled by default to save ~1-2MB)
        if defaults.bool(forKey: "ext_cloudkit_sync_enabled") {
            ExtensionCloudKitSync.shared.syncUsageToParent(defaults: defaults)
        }

        return true
    }

    /// Update JSON persistence for backward compatibility with main app
    private nonisolated func updateJSONPersistence(appID: String, increment: Int, rewardPoints: Int, defaults: UserDefaults) {
        guard let data = defaults.data(forKey: "persistedApps_v3"),
              var apps = try? Self.jsonDecoder.decode([String: PersistedAppMinimal].self, from: data),
              var app = apps[appID] else {
            return
        }

        // Check for day rollover
        let now = Date()
        let calendar = Self.calendar
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

        if let encoded = try? Self.jsonEncoder.encode(apps) {
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
        let startOfToday = Self.calendar.startOfDay(for: now).timeIntervalSince1970

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

    /// Ensure appID is in the tracked app list (for efficient enumeration without dictionaryRepresentation)
    private nonisolated func trackAppID(_ appID: String, defaults: UserDefaults) {
        var ids = defaults.stringArray(forKey: "tracked_app_ids") ?? []
        if !ids.contains(appID) {
            ids.append(appID)
            defaults.set(ids, forKey: "tracked_app_ids")
        }
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
        // Use tracked app list instead of materializing all UserDefaults keys
        let appIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []

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

                // Clear stale catchup_max to prevent yesterday's correction from polluting today
                defaults.removeObject(forKey: "catchup_max_\(appID)")

                // Reset ext_usage daily counters (must stay in sync with usage_ counters)
                defaults.set(0, forKey: "ext_usage_\(appID)_today")
                defaults.removeObject(forKey: "ext_usage_\(appID)_date")
                defaults.removeObject(forKey: "ext_usage_\(appID)_timestamp")

                // Reset hourly buckets
                for h in 0..<24 {
                    defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
                }
                defaults.removeObject(forKey: "ext_usage_\(appID)_hourly_date")
            }
        }

        // Clear shield check flag so it re-evaluates after next restart
        defaults.removeObject(forKey: "ext_shield_check_after_restart")
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
    private nonisolated func checkAndUpdateShields(configs: ExtensionShieldConfigsMinimal?, defaults: UserDefaults) {
        debugLog("SHIELD_CHECK: Starting shield update check", defaults: defaults)

        guard let configs = configs else {
            debugLog("SHIELD_CHECK: ❌ NO extensionShieldConfigs - ensure main app synced configs", defaults: defaults)
            return
        }

        debugLog("SHIELD_CHECK: Found \(configs.goalConfigs.count) goal configs to evaluate", defaults: defaults)

        for goalConfig in configs.goalConfigs {
            let isGoalMet = checkGoalMet(goalConfig: goalConfig, defaults: defaults)
            let shortID = String(goalConfig.rewardAppLogicalID.prefix(12))
            debugLog("SHIELD_CHECK: \(shortID)... goalMet=\(isGoalMet)", defaults: defaults)

            if isGoalMet {
                // Don't unlock if today's daily limit is 0 (app blocked for entire day)
                let todayLimit = goalConfig.todayDailyLimit()
                if todayLimit == 0 {
                    debugLog("SHIELD_CHECK: \(shortID) goal met but dailyLimit=0 today — keeping shield", defaults: defaults)
                    continue
                }

                guard let token = try? Self.propertyListDecoder.decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) else {
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
        let todayKey = Self.dayDateFormatter.string(from: Date())
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
        // Use dynamic per-day time window (falls back to snapshot if per-day not available)
        let window = goalConfig.todayTimeWindow()

        // Full day access = always allowed
        if window.isFullDay { return true }

        let now = Date()
        let calendar = Self.calendar
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTotalMinutes = currentHour * 60 + currentMinute

        let startTotal = window.startHour * 60 + window.startMinute
        let endTotal = window.endHour * 60 + window.endMinute

        // Check if current time is within allowed window
        return currentTotalMinutes >= startTotal && currentTotalMinutes < endTotal
    }

    /// Check if any reward app should be blocked due to downtime, daily limit, or exhausted earned time
    /// Priority: Downtime (highest) > Daily limit > Reward time expired (lowest)
    /// This uses the same data source (extensionShieldConfigs) as the unlock logic
    private nonisolated func checkAndBlockIfRewardTimeExhausted(configs: ExtensionShieldConfigsMinimal?, defaults: UserDefaults) {
        guard let configs = configs else {
            return
        }

        for goalConfig in configs.goalConfigs {
            // Get reward app usage (today)
            let usageKey = "usage_\(goalConfig.rewardAppLogicalID)_today"
            let usageSeconds = defaults.integer(forKey: usageKey)
            let usageMinutes = usageSeconds / 60

            // Check -1 (Absolute Highest Priority): App completely blocked for today (dailyLimit == 0)
            // dailyLimit=0 means "no access today regardless of goal state or time window."
            // Handled separately from Check 1 (daily limit exceeded) — a 0 limit is an
            // unconditional daily block, not a "you've used up your quota" condition.
            // This prevents the edge case where stale config data causes Check 1 (usageMinutes >= limit)
            // to fail to fire (e.g., fallback dailyLimitMinutes=60 returns instead of correct 0).
            let zeroLimitCheck = goalConfig.todayDailyLimit()
            if zeroLimitCheck == 0 {
                guard let token = try? PropertyListDecoder().decode(
                    ApplicationToken.self,
                    from: goalConfig.rewardAppTokenData
                ) else { continue }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                if !currentShields.contains(token) {
                    currentShields.insert(token)
                    managedSettingsStore.shield.applications = currentShields

                    recordBlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)

                    persistBlockingReason(
                        tokenHash: goalConfig.rewardAppLogicalID,
                        reasonType: "dailyLimitReached",
                        usedMinutes: usageMinutes,
                        defaults: defaults
                    )

                    debugLog("DAILY_ZERO_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... dailyLimit=0 — app blocked entire day", defaults: defaults)
                }
                continue  // Skip all other checks — entire day is blocked
            }

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
            let dailyLimit = goalConfig.todayDailyLimit()
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

            // Check 2: Learning goal not yet met — re-block at start of new day
            // Covers the case where yesterday's shield was lifted (goal was met) but today's
            // goal hasn't been started yet. earnedMinutes would be 0, so Check 3 never fires.
            let isGoalMet = checkGoalMet(goalConfig: goalConfig, defaults: defaults)
            if !isGoalMet {
                guard let token = try? PropertyListDecoder().decode(
                    ApplicationToken.self,
                    from: goalConfig.rewardAppTokenData
                ) else { continue }

                var currentShields = managedSettingsStore.shield.applications ?? Set()
                if !currentShields.contains(token) {
                    currentShields.insert(token)
                    managedSettingsStore.shield.applications = currentShields

                    recordBlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)

                    persistBlockingReason(
                        tokenHash: goalConfig.rewardAppLogicalID,
                        reasonType: "learningGoal",
                        usedMinutes: usageMinutes,
                        defaults: defaults
                    )

                    debugLog("LEARNING_GOAL_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... goal not met — re-applying shield", defaults: defaults)
                }
                continue  // Skip reward time check — only relevant once goal is met
            }

            // Check 3: Reward time exhausted (lower priority)
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
    let dailyLimitMinutes: Int  // Snapshot fallback (1440 = unlimited)

    // Time window fields — snapshot fallback
    let allowedStartHour: Int      // 0-23
    let allowedStartMinute: Int    // 0-59
    let allowedEndHour: Int        // 0-23
    let allowedEndMinute: Int      // 0-59
    let isFullDayAllowed: Bool     // true = no time restriction

    // Per-day daily limits: index 0=Sunday, 1=Monday, ..., 6=Saturday
    // Optional for backward compatibility with configs synced before this update
    let dailyLimitsPerDay: [Int]?

    // Per-day time windows (same indexing)
    let timeWindowsPerDay: [DayTimeWindowMinimal]?

    struct LinkedGoalMinimal: Codable {
        let learningAppLogicalID: String
        let minutesRequired: Int
        let ratioLearningMinutes: Int  // Ratio input: every X minutes of learning...
        let rewardMinutesEarned: Int   // Ratio output: ...grants Y minutes of reward
    }

    struct DayTimeWindowMinimal: Codable {
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
        let isFullDay: Bool
    }

    /// Dynamic daily limit for today (falls back to snapshotted value)
    func todayDailyLimit() -> Int {
        if let perDay = dailyLimitsPerDay, perDay.count == 7 {
            let weekday = Calendar.current.component(.weekday, from: Date())
            return perDay[weekday - 1]
        }
        return dailyLimitMinutes
    }

    /// Dynamic time window for today (falls back to snapshotted values)
    func todayTimeWindow() -> (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, isFullDay: Bool) {
        if let perDay = timeWindowsPerDay, perDay.count == 7 {
            let weekday = Calendar.current.component(.weekday, from: Date())
            let w = perDay[weekday - 1]
            return (w.startHour, w.startMinute, w.endHour, w.endMinute, w.isFullDay)
        }
        return (allowedStartHour, allowedStartMinute, allowedEndHour, allowedEndMinute, isFullDayAllowed)
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
