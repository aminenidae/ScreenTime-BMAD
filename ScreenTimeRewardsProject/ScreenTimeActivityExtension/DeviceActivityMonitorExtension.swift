import DeviceActivity
import Foundation
import Darwin // For mach_task_self_ and task_info
import ManagedSettings
import UserNotifications
import os.log

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

    /// os_log logger for Console.app visibility (extension print() is invisible in Console)
    private static let logger = Logger(subsystem: "i6dev.ScreenTimeRewards.extension", category: "monitor")

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
    /// Format the most recently persisted battery snapshot from the App Group as a
    /// short context string like "bat=charging:42% age=12s". The main app writes these
    /// values via AppDelegate.persistBatterySnapshot() because UIDevice.batteryState
    /// returns .unknown from the extension's sandbox. Returns "bat=unavailable" if no
    /// snapshot has ever been written.
    private nonisolated func batteryContextString(defaults: UserDefaults) -> String {
        let ts = defaults.double(forKey: "battery_state_timestamp")
        guard ts > 0 else { return "bat=unavailable" }
        let stateInt = defaults.integer(forKey: "last_known_battery_state")
        let level = defaults.double(forKey: "last_known_battery_level")  // 0.0–1.0, or -1.0 if unknown
        let stateStr: String
        switch stateInt {
        case 1: stateStr = "unplugged"
        case 2: stateStr = "charging"
        case 3: stateStr = "full"
        default: stateStr = "unknown"
        }
        let pct = (level >= 0) ? "\(Int(level * 100))%" : "?"
        let ageSec = max(0, Int(Date().timeIntervalSince1970 - ts))
        return "bat=\(stateStr):\(pct) age=\(ageSec)s"
    }

    private nonisolated func debugLog(_ message: String, defaults: UserDefaults) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        let entry = "[\(timestamp)][\(Self.sessionID)] \(message)\n"

        // Rotating file logger captures the FULL day with no size cap, so
        // post-incident debugging has the complete record (the legacy
        // UserDefaults log below truncates to ~50 KB / 200 lines).
        ExtensionFileLogger.shared.appendLine(entry)

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

        // Mirror to rotating file so the full lifecycle history (across sessions
        // and days) is preserved beyond the 100 KB / 400-line size-trim below.
        ExtensionFileLogger.shared.appendLine("[LIFECYCLE] " + entry)

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

        // Mirror to rotating file (tagged) so the daily file shows midnight events
        // in their proper chronological place alongside everything else.
        ExtensionFileLogger.shared.appendLine("[MIDNIGHT] " + entry)

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
                let batCtx = batteryContextString(defaults: defaults)
                if let lastSessionID = lastSessionID, lastSessionID != Self.sessionID {
                    lifecycleLog("EXTENSION_KILLED — new session detected (was: \(lastSessionID), now: \(Self.sessionID)) \(batCtx)", defaults: defaults)
                }
                defaults.set(Self.sessionID, forKey: "ext_last_session_id")
                lifecycleLog("EXTENSION_INIT session=\(Self.sessionID) \(batCtx)", defaults: defaults)
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
                Self.logger.notice("MIDNIGHT_START trackedApps=\(diagTrackedIDs.count)")
                for diagAppID in diagTrackedIDs {
                    let extToday = defaults.integer(forKey: "ext_usage_\(diagAppID)_today")
                    let extDate = defaults.string(forKey: "ext_usage_\(diagAppID)_date") ?? "nil"
                    let lastThresh = defaults.integer(forKey: "usage_\(diagAppID)_lastThreshold")
                    let usageToday = defaults.integer(forKey: "usage_\(diagAppID)_today")
                    midnightDiagnosticLog("  APP_STATE \(diagAppID.prefix(8))... ext_today=\(extToday)s ext_date=\(extDate) lastThresh=\(lastThresh)s usage_today=\(usageToday)s", defaults: defaults)
                }

                // Midnight PENDING_SET is deferred — set below only if extension rebuild fails
            } else if defaults.bool(forKey: "midnight_diagnostic_active") {
                // Non-midnight intervalDidStart (restart-triggered) — log it, don't clear
                midnightDiagnosticLog("RESTART_INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
            }

            debugLog("INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID) \(batteryContextString(defaults: defaults))", defaults: defaults)
            lifecycleLog("INTERVAL_START — iOS daily restart (activity=\(activity.rawValue)) \(batteryContextString(defaults: defaults))", defaults: defaults)
            Self.logger.notice("INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID)")

            let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []

            // Reset lastThreshold ONLY at genuine midnight — iOS resets its threshold counter at day rollover.
            // Same-day intraday restarts must NOT reset lastThreshold: Filter 5 (SKIP_REGRESSION) relies on
            // lastThreshold persisting across same-day restarts to block the spurious second INTERVAL_START
            // burst where iOS fires ALL registered thresholds regardless of real cumulative usage.
            if lastDiagDate != todayStr {
                for trackedAppID in trackedAppIDs {
                    defaults.set(0, forKey: "usage_\(trackedAppID)_lastThreshold")
                }
                if defaults.bool(forKey: "midnight_diagnostic_active") {
                    midnightDiagnosticLog("MIDNIGHT_RESET_COMPLETE — lastThreshold reset for \(trackedAppIDs.count) apps", defaults: defaults)
                }
                Self.logger.notice("MIDNIGHT_RESET_COMPLETE lastThreshold reset for \(trackedAppIDs.count) apps")

                // Reset daily counters so rebuild sees fresh ext_usage=0 → window 1-60
                let calendar = Calendar.current
                let startOfToday = calendar.startOfDay(for: Date()).timeIntervalSince1970
                let globalResetKey = "global_daily_reset_timestamp"
                let lastGlobalReset = defaults.double(forKey: globalResetKey)
                if lastGlobalReset < startOfToday {
                    resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
                    defaults.set(startOfToday, forKey: globalResetKey)
                }

                // Attempt extension-side rebuild: register fresh 1-60 thresholds at midnight.
                // iOS cumulative is 0 at midnight, so no catch-ups fire — safe to startMonitoring().
                let rebuildSuccess = extensionRebuildSlidingWindow(defaults: defaults)
                if rebuildSuccess {
                    midnightDiagnosticLog("MIDNIGHT_EXT_REBUILD_OK — fresh 1-60 thresholds registered, no MIDNIGHT_PENDING needed", defaults: defaults)
                    lifecycleLog("MIDNIGHT_EXT_REBUILD — extension registered fresh thresholds at midnight", defaults: defaults)
                    Self.logger.notice("MIDNIGHT_EXT_REBUILD_OK — fresh thresholds registered autonomously")
                } else {
                    // Fallback: block events until main app runs scheduleActivity()
                    defaults.set(true, forKey: "midnight_pending_refresh")
                    defaults.set(Date().timeIntervalSince1970, forKey: "midnight_pending_timestamp")
                    midnightDiagnosticLog("MIDNIGHT_PENDING_SET — ext rebuild failed, blocking events until scheduleActivity", defaults: defaults)
                    lifecycleLog("MIDNIGHT_PENDING_SET — ext rebuild failed, waiting for main app", defaults: defaults)
                    Self.logger.error("MIDNIGHT_PENDING_SET — ext rebuild FAILED, waiting for main app")
                }
            }

            // Evaluate shields on monitoring start — usage data is already correct
            // from previous session. Don't wait for events.
            let shieldConfigs: ExtensionShieldConfigsMinimal? = {
                guard let data = defaults.data(forKey: "extensionShieldConfigs") else { return nil }
                return try? Self.jsonDecoder.decode(ExtensionShieldConfigsMinimal.self, from: data)
            }()
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
            debugLog("INTERVAL_END activity=\(activity.rawValue) session=\(Self.sessionID) \(batteryContextString(defaults: defaults))", defaults: defaults)
            lifecycleLog("INTERVAL_END — iOS daily cycle (activity=\(activity.rawValue)) \(batteryContextString(defaults: defaults))", defaults: defaults)
        }
    }

    // MARK: - Threshold Event Handler
    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        Self.logger.notice("THRESHOLD event=\(event.rawValue)")

        // Log FIRST - before any processing that could fail
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            debugLog("THRESHOLD_CALL event=\(event.rawValue)", defaults: defaults)
            // Increment persistent counter to track total events received
            let eventCount = defaults.integer(forKey: "ext_total_events_received") + 1
            defaults.set(eventCount, forKey: "ext_total_events_received")

            Self.logger.notice("THRESHOLD totalEvents=\(eventCount)")
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
        let appID: String
        if let mapped = defaults.string(forKey: mapIdKey) {
            appID = mapped
        } else if let mapping = readEventMappingFromJSON(eventName: eventName, defaults: defaults) {
            // JSON eventMappings fallback
            return recordUsageWithMapping(mapping, eventName: eventName, defaults: defaults)
        } else if let recovered = recoverLogicalIDFromEventName(eventName, defaults: defaults) {
            // May 2 fix — stable-hash recovery for thresholds above the registered window.
            // Symptom: log shows `NO_MAPPING event=usage.app.<hash>.min.<N>` for thresholds
            // that fired after the sliding window was exhausted but before the window-rebuild
            // wrote map keys for the next 60 minutes (or after the rebuild silently failed).
            // 26 thresholds (118–143) lost between 17:24–17:49 in ext-log-2026-05-02.log.
            // Defense: parse `<hash>` from the event name, look it up against
            // `app_stable_hash_<logicalID>` for each tracked app, recover the logicalID,
            // backfill the missing map keys so subsequent events from the same hash hit the
            // primitive-key fast path, and force a window rebuild — by definition the window
            // was exhausted if iOS is firing thresholds we don't have mappings for.
            appID = recovered
            let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
            defaults.set(appID, forKey: mapIdKey)
            defaults.set(category, forKey: "map_\(eventName)_category")
            debugLog("MAPPING_RECOVERED event=\(eventName) appID=\(appID.prefix(8))... — backfilled via stable-hash, forcing window rebuild", defaults: defaults)
            extensionRebuildSlidingWindow(defaults: defaults)
        } else {
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

        Self.logger.notice("EVENT app=\(appID.prefix(8))... min=\(thresholdMinutes) today=\(currentToday)s lastThresh=\(currentThreshold)s")

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

        let newToday = defaults.integer(forKey: "usage_\(appID)_today")
        Self.logger.notice("RECORDED app=\(appID.prefix(8))... total=\(newToday)s")

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
                Self.logger.notice("SKIP_MIDNIGHT app=\(appID.prefix(8))... timeSince=\(Int(timeSinceMidnight))s thresh=\(thresholdSeconds)s")
                return false
            } else {
                // Safety timeout expired — clear flag and resume recording
                defaults.set(false, forKey: "midnight_pending_refresh")
                debugLog("MIDNIGHT_TIMEOUT — 2hr expired, clearing midnight_pending_refresh", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_MIDNIGHT_TIMEOUT clearing flag after \(Int(timeSinceMidnight))s", defaults: defaults) }
            }
        }

        // Filter 1: Minimum threshold validation
        // All configured thresholds are >= 60s (1 minute minimum)
        // Values below 60 indicate OS regression (0-minute phantom fires)
        if thresholdSeconds < 60 {
            debugLog("SKIP_INVALID appID=\(appID.prefix(8))... thresholdSeconds=\(thresholdSeconds) < 60", defaults: defaults)
            return false
        }

        // Filter 2: Shielded reward app — user can't use a blocked app, so events are phantom
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
        Self.logger.notice("FILTER2_ENTRY app=\(appID.prefix(8))... category=\(category) thresh=\(thresholdSeconds)s")
        if category == "Reward" {
            guard let configs = shieldConfigs else {
                // shieldConfigs unavailable — can't verify shield state. Block reward app events as a
                // safe default: false negatives (missing earned-time events) are safer than false
                // positives (recording usage for a blocked app).
                debugLog("SKIP_SHIELDED_FALLBACK appID=\(appID.prefix(8))... shieldConfigs nil, blocking reward app event", defaults: defaults)
                Self.logger.error("SKIP_SHIELDED_FALLBACK app=\(appID.prefix(8))... configs=nil")
                return false
            }
            for goalConfig in configs.goalConfigs where goalConfig.rewardAppLogicalID == appID {
                if let token = try? Self.propertyListDecoder.decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) {
                    let currentShields = managedSettingsStore.shield.applications ?? Set()
                    let shieldHasToken = currentShields.contains(token)
                    Self.logger.notice("SHIELD_STATE app=\(appID.prefix(8))... shieldHasToken=\(shieldHasToken) shieldCount=\(currentShields.count)")
                    if shieldHasToken {
                        debugLog("SKIP_SHIELDED appID=\(appID.prefix(8))... reward app is currently blocked", defaults: defaults)
                        Self.logger.notice("SKIP_SHIELDED app=\(appID.prefix(8))... shield up, blocking")
                        return false
                    }
                    // SAFETY NET (Apr 24): the live `managedSettingsStore.shield.applications`
                    // can briefly NOT contain a reward app's token while a SHIELD_CHECK
                    // is mid-rebuild (LEARNING_GOAL_BLOCK was observed re-applying the
                    // shield ~220ms after the threshold event slipped past, allowing one
                    // false +60s credit on shielded reward app 51E884C1). Cross-check
                    // against goal-met status: if the goal is NOT met, the shield SHOULD
                    // be up regardless of what the live store says — block anyway.
                    // 2026-05-06 revert: removed the May 2 `pool > 0 → SHIELDED_RACE_BYPASS`
                    // branch. Pool-only carry-forward no longer unshields, so the original
                    // strict !goalMet → block rule is correct.
                    let rewardAppIDs = Set(configs.goalConfigs.map { $0.rewardAppLogicalID })
                    let goalMet = checkGoalMet(goalConfig: goalConfig, rewardAppIDs: rewardAppIDs, defaults: defaults)
                    if !goalMet {
                        debugLog("SKIP_SHIELDED_RACE appID=\(appID.prefix(8))... goal NOT met — blocking (race-window backstop)", defaults: defaults)
                        Self.logger.error("SKIP_SHIELDED_RACE app=\(appID.prefix(8))... goalMet=false — BLOCKING")
                        return false
                    }
                    Self.logger.notice("SHIELD_RACE_GATE app=\(appID.prefix(8))... goalMet=true — RECORDING")
                }
                break
            }
        }

        // Filter 2.5: SKIP_PIN_REPLAY — wall-clock anchor for newly-added apps.
        // Apr 25 evidence (E54C1C9E, ext-log-2026-04-25.log): iOS fires backed-up threshold
        // events for cumulative usage that occurred BEFORE registration, even when the app
        // was registered with `includesPastActivity:false`. The Apple flag only suppresses
        // cross-INTERVAL boundaries (midnight), not within-interval pre-registration usage.
        // Defense: anchor each newly-pinned app at its first-seen timestamp; reject any
        // threshold event claiming more cumulative seconds than (now - firstSeen + 60s buffer).
        // The +60s buffer lets the first legitimate min.1 event after pinning slip through.
        let firstSeenAt = defaults.double(forKey: "app_first_seen_today_\(appID)")
        if firstSeenAt >= startOfToday {
            let wallClockSincePin = nowTimestamp - firstSeenAt
            let allowedCeiling = wallClockSincePin + 60
            if Double(thresholdSeconds) > allowedCeiling {
                debugLog("SKIP_PIN_REPLAY appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s wallClock=\(Int(wallClockSincePin))s allowed=\(Int(allowedCeiling))s — historical replay since pin", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_PIN_REPLAY appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s wallClock=\(Int(wallClockSincePin))s", defaults: defaults) }
                Self.logger.notice("SKIP_PIN_REPLAY app=\(appID.prefix(8))... thresh=\(thresholdSeconds)s wallClock=\(Int(wallClockSincePin))s")
                return false
            }
        }

        // Filter 3: Threshold progression
        // Same day: cumulative usage only grows, so thresholds must strictly increase
        // Cross-day: thresholds restart from min.1, just block exact duplicates
        let lastThresholdKey = "usage_\(appID)_lastThreshold"
        let lastThreshold = defaults.integer(forKey: lastThresholdKey)
        let todayResetKey = "usage_\(appID)_reset"
        let lastResetTimestamp = defaults.double(forKey: todayResetKey)

        if lastResetTimestamp >= startOfToday {
            // Same day: threshold must strictly increase (usage is monotonic within a day)
            if thresholdSeconds <= lastThreshold {
                debugLog("SKIP_REGRESSION appID=\(appID.prefix(8))... threshold=\(thresholdSeconds) <= lastThreshold=\(lastThreshold) (same day)", defaults: defaults)
                if midnightDiagActive { midnightDiagnosticLog("DIAG_SKIP_REGRESSION appID=\(appID.prefix(8))... thresh=\(thresholdSeconds) lastThresh=\(lastThreshold) sameDay=true", defaults: defaults) }
                Self.logger.notice("SKIP_REGRESSION app=\(appID.prefix(8))... thresh=\(thresholdSeconds) <= lastThresh=\(lastThreshold)")
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

        // ═══════════ PASSED ALL FILTERS — proceed to record ═══════════

        // 2026-05-07 — iOS-claimed cumulative floor for shield decisions.
        // `usage_<id>_today` reflects only what we've credited, which can fall arbitrarily
        // far behind iOS' true cumulative when LASTTHRESH_HOLD engages during a stale
        // catch-up storm (May 6 device repro: extension stuck at usage_today=128min while
        // iOS fired thresholds at min.178+, all held at +0). Pool stuck above 0, shield
        // never re-applied. Track the highest threshold iOS has ever fired today as a
        // separate signal — used by `checkAndBlockIfRewardTimeExhausted` and
        // `computeEffectivePoolBalance` as a floor for `todayUsed`. Crediting math is
        // unchanged; only shield decisions use this floor. See
        // `docs/SMART_THRESHOLD_FILTERING.md` "May 7, 2026 — iOS-Claimed Cumulative Floor".
        let iosClaimedKey = "ios_claimed_today_\(appID)"
        let priorClaimed = defaults.integer(forKey: iosClaimedKey)
        if thresholdSeconds > priorClaimed {
            defaults.set(thresholdSeconds, forKey: iosClaimedKey)
        }

        let todayKey = "usage_\(appID)_today"
        let totalKey = "usage_\(appID)_total"
        let dateString = Self.dayDateFormatter.string(from: now)
        let hour = calendar.component(.hour, from: now)

        // Day rollover check
        if lastResetTimestamp < startOfToday {
            let globalResetKey = "global_daily_reset_timestamp"
            let lastGlobalReset = defaults.double(forKey: globalResetKey)

            if lastGlobalReset < startOfToday {
                debugLog("DAY_ROLLOVER appID=\(appID.prefix(8))... globalReset triggered", defaults: defaults)
                resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
                defaults.set(startOfToday, forKey: globalResetKey)
                notifyMainApp()
            }

            // First event of the day records 60s (1 minute). Subsequent burst events
            // use delta math (thresholdSeconds - lastThreshold) to accumulate correctly.
            let initialUsage = 60
            debugLog("NEW_DAY appID=\(appID.prefix(8))... initialUsage=\(initialUsage)s thresh=\(thresholdSeconds)s", defaults: defaults)
            if midnightDiagActive { midnightDiagnosticLog("DIAG_NEW_DAY appID=\(appID.prefix(8))... initial=\(initialUsage)s thresh=\(thresholdSeconds)s", defaults: defaults) }
            Self.logger.notice("NEW_DAY app=\(appID.prefix(8))... initial=\(initialUsage)s thresh=\(thresholdSeconds)s")
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

            trackAppID(appID, defaults: defaults)
            defaults.set(nowTimestamp, forKey: "last_recorded_timestamp") // diagnostics

            // Check if this threshold approached the top of the registered window → rebuild.
            // Trigger 5 minutes early so the main app has time to re-register fresh
            // thresholds before iOS exhausts the current window and goes silent.
            let thresholdMinNd = thresholdSeconds / 60
            let windowTopMinNd = defaults.integer(forKey: "window_top_min_\(appID)")
            if windowTopMinNd > 0 && thresholdMinNd >= windowTopMinNd - 5 {
                debugLog("WINDOW_TOP_HIT appID=\(appID.prefix(8))... min=\(thresholdMinNd) top=\(windowTopMinNd) → request main-app rebuild + ext fast-path (NEW_DAY)", defaults: defaults)
                requestMainAppWindowRebuild(reason: "window-top-newday-\(appID.prefix(8))", defaults: defaults)
                extensionRebuildSlidingWindow(defaults: defaults)
            }
            return true
        }

        // Same day — use threshold delta when we have a reliable lastThreshold (>0),
        // otherwise fall back to safe +60 to prevent phantom threshold amplification.
        // lastThreshold > 0 means it was set by a previous recording in this session.
        // lastThreshold = 0 means daily reset or post-restart — can't trust delta.
        //
        // Two-layer cap: a credited minute requires a real minute of elapsed time.
        //
        // Layer 1 — wall-clock cap.
        // Anchor: ext_usage_<appID>_timestamp (written below on every recording;
        // cleared at midnight by resetAllDailyCounters). On day-1 (timestamp absent)
        // fall back to startOfToday so a flush burst at 00:00:01 still gets capped
        // against ~1s of elapsed wall-clock instead of crediting the full threshold.
        // Catches in-burst events: once the first event for an app records,
        // ext_usage_*_timestamp updates to nowTimestamp and subsequent events in the
        // same burst see wallClockElapsed ≈ 0.
        //
        // Layer 2 — per-event hard cap (60 s).
        // Each threshold event represents the cumulative crossing exactly one minute
        // mark, so by definition at most 60 s of real progression has occurred since
        // the previous threshold for this app. Without this layer, the FIRST event of
        // a burst (when the timestamp anchor is hours stale) would credit the full
        // raw delta — exactly the failure mode observed Apr 23 23:38:22 where four
        // first-events of an iOS catch-up storm credited +3420 / +2280 / +540 / +420
        // seconds (111 min total fake credit) before the in-burst cap could kick in.
        // Trade-off: if iOS skips intermediate thresholds (rare — we register all 60
        // 1-min thresholds in the sliding window), we under-credit by ≤60 s per
        // skipped threshold. Asymmetric vs. unbounded over-credit; ship.
        let currentToday = defaults.integer(forKey: todayKey)
        let lastEventTime = defaults.double(forKey: "ext_usage_\(appID)_timestamp")
        // Anchor cap on the latest of: last event for this app, last unlock for this app
        // (Apr 26–27 fix), or start-of-today (midnight fallback). Using max() means a
        // legitimate post-unlock catch-up burst can credit up to elapsed-since-unlock
        // on its FIRST event — subsequent in-burst events naturally fall back to 60s
        // because lastEventTime advances. Without this, the per-event 60s cap discards
        // multi-minute legitimate use that accumulated between unshield and first event.
        let unlockTime = defaults.double(forKey: "ext_unlock_\(appID)_timestamp")
        let wallClockBaseline: TimeInterval = max(lastEventTime, unlockTime, startOfToday)
        let wallClockElapsed = max(0, Int(nowTimestamp - wallClockBaseline))
        let rawDelta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60

        // First event after an unlock relaxes the per-event cap to elapsed-since-unlock
        // (bounded by rawDelta and wallClockElapsed). Subsequent events have
        // lastEventTime > unlockTime, so isFirstEventAfterUnlock=false and cap=60s.
        let isFirstEventAfterUnlock = (unlockTime > lastEventTime) && (unlockTime > 0)
        let perEventCap = isFirstEventAfterUnlock
            ? max(60, Int(nowTimestamp - unlockTime))
            : 60
        let delta = max(0, min(rawDelta, wallClockElapsed, perEventCap))
        if delta < rawDelta {
            let unlockAge = unlockTime > 0 ? Int(nowTimestamp - unlockTime) : -1
            debugLog("WALL_CLOCK_CAP appID=\(appID.prefix(8))... raw=\(rawDelta)s capped=\(delta)s wallClock=\(wallClockElapsed)s perEvent=\(perEventCap)s unlockAge=\(unlockAge)s sinceLastEvent=\(lastEventTime > 0 ? "yes" : "no(midnight-baseline)") \(batteryContextString(defaults: defaults))", defaults: defaults)
        }
        let newToday = currentToday + delta
        debugLog("RECORDED appID=\(appID.prefix(8))... oldToday=\(currentToday)s +\(delta) = newToday=\(newToday)s, thresh=\(thresholdSeconds)s", defaults: defaults)
        if midnightDiagActive { midnightDiagnosticLog("DIAG_INCREMENT appID=\(appID.prefix(8))... old=\(currentToday)s +\(delta)s = \(newToday)s thresh=\(thresholdSeconds)s lastThresh=\(lastThreshold)s", defaults: defaults) }
        Self.logger.notice("INCREMENT app=\(appID.prefix(8))... +\(delta)s = \(newToday)s thresh=\(thresholdSeconds)s lastThresh=\(lastThreshold)s")
        defaults.set(newToday, forKey: todayKey)
        // Apr 30 fix — out-of-order stale catch-up `lastThreshold` poisoning.
        // When iOS delivers a stale catch-up event, `thresholdSeconds` reflects iOS's
        // backlogged cumulative — not real progression. Advancing `lastThreshold` to
        // that stale value pegs it at the high end of the sliding window and
        // `SKIP_REGRESSION` blocks every subsequent legitimate threshold for the rest
        // of the day. The Apr 29 incident (`ext-log-2026-04-29.log`) recorded a
        // 9.4-hour blackout across all 8 apps after one 14:35:14 flood walked
        // `lastThreshold` to 3600s in <14 seconds.
        //
        // Stale-catch-up signature: `rawDelta > perEventCap`. `rawDelta` is the gap
        // between the incoming threshold and the prior `lastThreshold`; `perEventCap`
        // is the maximum real time that one event can legitimately represent (60 s by
        // default, relaxed to elapsed-since-unlock for the first event after unlock).
        // When `rawDelta > perEventCap` the threshold has jumped further than real
        // time could justify — by definition a catch-up. Apr 29 examples: rawDelta=
        // 2160 (E54C1C9E min.55 with prior lastThresh=1140), 600 (FAE1D45B min.35
        // with prior lastThresh=1500). All ≫ 60s.
        //
        // Critical: do NOT use `delta < rawDelta` as the trigger. iOS does not fire
        // on exact 60 s boundaries — natural jitter (~1 s) makes the wall-clock cap
        // clamp every normal event by a second, and that would hold `lastThreshold`
        // on every healthy minute (Apr 30 v1 test: 123 false positives in one day,
        // `lastThreshold` pegged at 60 s all day, SKIP_REGRESSION effectively
        // disabled).
        //
        // On stale catch-up: hold `lastThreshold` at its prior value. The credited
        // delta is already bounded by `perEventCap`, so SKIP_REGRESSION remains
        // sound: subsequent real-time thresholds will pass against the unchanged
        // prior `lastThreshold`. Post-unlock catch-ups have inflated `perEventCap`,
        // so legitimate ones naturally fall under the gate without a special case.
        // v3 (May 1) — on stale catch-up, advance `lastThreshold` to the actual
        // credited high-water mark (`max(prior, newToday)`) rather than holding it
        // indefinitely at the pre-flood value. The v2 "hold" worked operationally
        // (no rest-of-day blackouts) but pegged `lastThreshold` permanently after
        // the first held event of the day for an app, classifying every subsequent
        // legitimate real-time event as "stale catch-up" because their `rawDelta`
        // grew unboundedly against the frozen baseline. Counting still came out
        // right (wall-clock cap independently bounded delta), but `SKIP_REGRESSION`
        // was effectively disabled for that app for the rest of the day, and the
        // log misleadingly tagged real-time events as "stale". Anchoring to
        // `newToday` keeps `lastThreshold` truthful as "highest credited progression"
        // and re-arms `SKIP_REGRESSION` against any *new* stale flood.
        let wasStaleCatchup = rawDelta > perEventCap
        if wasStaleCatchup {
            let newLastThreshold = max(lastThreshold, newToday)
            debugLog("LASTTHRESH_HOLD appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s held lastThresh=\(newLastThreshold)s (was \(lastThreshold)s) — stale catch-up (raw=\(rawDelta)s > perEventCap=\(perEventCap)s, credited=\(delta)s)", defaults: defaults)
            defaults.set(newLastThreshold, forKey: lastThresholdKey)
        } else {
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
        }

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
        defaults.set(nowTimestamp, forKey: "last_recorded_timestamp") // diagnostics

        // Check if this threshold approached the top of the registered window → rebuild.
        // Trigger 5 minutes early so the main app has time to re-register fresh
        // thresholds before iOS exhausts the current window and goes silent.
        let thresholdMin = thresholdSeconds / 60
        let windowTopMin = defaults.integer(forKey: "window_top_min_\(appID)")
        if windowTopMin > 0 && thresholdMin >= windowTopMin - 5 {
            debugLog("WINDOW_TOP_HIT appID=\(appID.prefix(8))... min=\(thresholdMin) top=\(windowTopMin) → request main-app rebuild + ext fast-path", defaults: defaults)
            requestMainAppWindowRebuild(reason: "window-top-\(appID.prefix(8))", defaults: defaults)
            extensionRebuildSlidingWindow(defaults: defaults)
        }
        return true
    }

    /// Request the main app to rebuild the sliding window. Called when a threshold
    /// approaches/exceeds the registered window top. May 3 incident
    /// (`ext-log-2026-05-03.log` Imane + Iness): the in-callback rebuild is
    /// structurally unreliable — it never produced an `EXT_REBUILD_SUCCESS` after
    /// midnight on either device. iOS kills the extension process mid-rebuild
    /// because registering 16 apps × 60 events exceeds the callback's memory/time
    /// budget. Iness was rescued ~4 h later when her main-app BGTask
    /// `usage-upload intraday refresh` ran `restartMonitoring()`; Imane's BGTask
    /// never fired and recording stayed dead from `min.60` onward.
    ///
    /// Defense: write a `pending_window_rebuild` flag and post a Darwin notification.
    /// If the main app is running, it handles the flag immediately and calls
    /// `scheduleActivity()` (full memory headroom — succeeds reliably). If the main
    /// app is not running, the flag persists until the next BGTask wake or app
    /// foreground entry checks it. The in-callback `extensionRebuildSlidingWindow`
    /// stays as the best-effort fast path; if it succeeds the main-app handler
    /// observes a clean state and is a no-op.
    private nonisolated func requestMainAppWindowRebuild(reason: String, defaults: UserDefaults) {
        defaults.set(true, forKey: "pending_window_rebuild")
        defaults.set(Date().timeIntervalSince1970, forKey: "pending_window_rebuild_timestamp")
        defaults.set(reason, forKey: "pending_window_rebuild_reason")
        debugLog("WINDOW_REBUILD_REQUESTED reason=\(reason) — flagged for main app + Darwin notification posted", defaults: defaults)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.screentimerewards.windowRebuildNeeded" as CFString),
            nil,
            nil,
            true
        )
    }

    /// Recover the logical app ID for an event name when no `map_<eventName>_id`
    /// primitive key exists. Event names follow `usage.app.<stable_hash>.min.<N>`;
    /// `app_stable_hash_<logicalID>` is written by `scheduleActivity()` for every
    /// monitored app, so a reverse lookup is sufficient.
    private nonisolated func recoverLogicalIDFromEventName(_ eventName: String, defaults: UserDefaults) -> String? {
        let parts = eventName.split(separator: ".")
        // Expect "usage.app.<hash>.min.<N>" — hash is index 2
        guard parts.count >= 5,
              parts[0] == "usage",
              parts[1] == "app",
              parts[parts.count - 2] == "min" else {
            return nil
        }
        let stableHashStr = String(parts[2])
        guard let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") else {
            return nil
        }
        for logicalID in trackedAppIDs {
            if defaults.string(forKey: "app_stable_hash_\(logicalID)") == stableHashStr {
                return logicalID
            }
        }
        return nil
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

    // MARK: - Extension-Side Sliding Window Refresh

    /// Rebuild the sliding window thresholds from within the extension.
    ///
    /// Called when the last registered threshold fires (window exhaustion imminent).
    /// With the sliding window approach, new thresholds start above current usage,
    /// so iOS fires zero catch-up events — the restart is clean.
    ///
    /// Safety: SKIP_REGRESSION blocks duplicate burst events post-restart.
    @discardableResult
    private nonisolated func extensionRebuildSlidingWindow(defaults: UserDefaults) -> Bool {
        guard let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids"),
              !trackedAppIDs.isEmpty else {
            debugLog("EXT_REBUILD_SKIP — no tracked_app_ids", defaults: defaults)
            return false
        }

        let todayDateString = Self.dayDateFormatter.string(from: Date())
        let now = Date().timeIntervalSince1970

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        var newWindowTops: [String: Int] = [:]

        for logicalID in trackedAppIDs {
            // Decode stored token — written by saveEventMappings() in the main app
            guard let tokenData = defaults.data(forKey: "app_token_\(logicalID)"),
                  let token = try? Self.propertyListDecoder.decode(ApplicationToken.self, from: tokenData) else {
                debugLog("EXT_REBUILD_SKIP_NO_TOKEN appID=\(logicalID.prefix(8))...", defaults: defaults)
                continue
            }

            // Read stable hash stored by scheduleActivity()
            guard let stableHashStr = defaults.string(forKey: "app_stable_hash_\(logicalID)") else {
                debugLog("EXT_REBUILD_SKIP_NO_HASH appID=\(logicalID.prefix(8))...", defaults: defaults)
                continue
            }

            // Compute current usage for this app (today only)
            let extDate = defaults.string(forKey: "ext_usage_\(logicalID)_date")
            let extTodaySeconds = (extDate == todayDateString)
                ? defaults.integer(forKey: "ext_usage_\(logicalID)_today")
                : 0
            let currentMin = extTodaySeconds / 60

            let category = defaults.string(forKey: "map_\(logicalID)_category") ?? "Learning"

            // Right-sized window per app. Main-app `scheduleActivity()` writes
            // `window_size_<id>` (Learning = 60, Reward = today's daily limit
            // capped at 240 if unlimited). Default to 60 if missing — backward
            // compatible with older builds that didn't write the key.
            let storedWindowSize = defaults.integer(forKey: "window_size_\(logicalID)")
            let appWindow = storedWindowSize > 0 ? max(60, storedWindowSize) : 60
            for minuteNumber in (currentMin + 1)...(currentMin + appWindow) {
                let eventName = DeviceActivityEvent.Name("usage.app.\(stableHashStr).min.\(minuteNumber)")
                let event: DeviceActivityEvent
                if #available(iOS 17.4, *) {
                    event = DeviceActivityEvent(
                        applications: [token],
                        threshold: DateComponents(minute: minuteNumber),
                        includesPastActivity: true
                    )
                } else {
                    event = DeviceActivityEvent(
                        applications: [token],
                        threshold: DateComponents(minute: minuteNumber)
                    )
                }
                events[eventName] = event

                // Write primitive map keys so the extension can process new events when they fire
                defaults.set(logicalID, forKey: "map_\(eventName.rawValue)_id")
                defaults.set(category, forKey: "map_\(eventName.rawValue)_category")
            }

            newWindowTops[logicalID] = currentMin + appWindow
            debugLog("EXT_REBUILD_APP appID=\(logicalID.prefix(8))... current=\(currentMin)min → new window \(currentMin + 1)-\(currentMin + appWindow) (\(appWindow) thresholds)", defaults: defaults)
            Self.logger.notice("EXT_REBUILD_APP app=\(logicalID.prefix(8))... current=\(currentMin)min window=\(currentMin + 1)-\(currentMin + appWindow)")
        }

        guard !events.isEmpty else {
            debugLog("EXT_REBUILD_NO_EVENTS — nothing to register", defaults: defaults)
            return false
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // Set restart timestamp BEFORE startMonitoring to close the race window
        // (mirrors the same pattern in scheduleActivity() in the main app)
        defaults.set(now, forKey: "monitoring_restart_timestamp")

        do {
            let center = DeviceActivityCenter()
            try center.startMonitoring(DeviceActivityName("ScreenTimeTracking"), during: schedule, events: events)

            // Success — update window tops so the check doesn't re-fire immediately
            for (logicalID, topMin) in newWindowTops {
                defaults.set(topMin, forKey: "window_top_min_\(logicalID)")
            }
            debugLog("EXT_REBUILD_SUCCESS events=\(events.count) apps=\(newWindowTops.count)", defaults: defaults)
            Self.logger.notice("EXT_REBUILD_SUCCESS events=\(events.count) apps=\(newWindowTops.count)")
            return true
        } catch {
            // Undo restart timestamp so SKIP_RESTART doesn't block real events
            defaults.removeObject(forKey: "monitoring_restart_timestamp")
            debugLog("EXT_REBUILD_FAILED: \(error)", defaults: defaults)
            Self.logger.error("EXT_REBUILD_FAILED: \(error.localizedDescription)")
            return false
        }
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

                // Reset ext_usage daily counters (must stay in sync with usage_ counters)
                defaults.set(0, forKey: "ext_usage_\(appID)_today")
                defaults.removeObject(forKey: "ext_usage_\(appID)_date")
                defaults.removeObject(forKey: "ext_usage_\(appID)_timestamp")

                // Reset iOS-claimed cumulative floor (see setUsageToThreshold for rationale).
                defaults.set(0, forKey: "ios_claimed_today_\(appID)")

                // Reset hourly buckets
                for h in 0..<24 {
                    defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
                }
                defaults.removeObject(forKey: "ext_usage_\(appID)_hourly_date")

                // Clear newly-added pin anchor at midnight: a "newly added" app from
                // yesterday is treated as already-known today (cumulative=0 anyway).
                defaults.removeObject(forKey: "app_first_seen_today_\(appID)")
            }
        }

        // Clear yesterday's pinned-apps set so today starts fresh
        defaults.removeObject(forKey: "pinned_apps_today")
        defaults.removeObject(forKey: "pinned_apps_today_date")

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

    /// Check all reward app goals and update shields accordingly.
    /// Called after each usage recording. Gates on POOLED Time Bank balance, not on
    /// today's per-goal threshold — so a child with carry-forward credit can spend it
    /// even on a day where they haven't crossed today's threshold (Device B fix), and
    /// a child who has spent their balance stays shielded even if the threshold is met
    /// (Device A fix). Per-app gates (downtime / dailyLimit) still override.
    private nonisolated func checkAndUpdateShields(configs: ExtensionShieldConfigsMinimal?, defaults: UserDefaults) {
        debugLog("SHIELD_CHECK: Starting shield update check", defaults: defaults)

        guard let configs = configs else {
            debugLog("SHIELD_CHECK: ❌ NO extensionShieldConfigs - ensure main app synced configs", defaults: defaults)
            return
        }

        let pool = computeEffectivePoolBalance(configs: configs, defaults: defaults)
        debugLog("SHIELD_CHECK: pool=\(pool)min across \(configs.goalConfigs.count) goal configs", defaults: defaults)

        // Pool empty → nothing to unshield this pass. checkAndBlockIfRewardTimeExhausted
        // will (re-)apply shields if needed.
        guard pool > 0 else {
            debugLog("SHIELD_CHECK: pool empty, no unshield", defaults: defaults)
            return
        }

        let rewardAppIDs = Set(configs.goalConfigs.map { $0.rewardAppLogicalID })

        for goalConfig in configs.goalConfigs {
            let shortID = String(goalConfig.rewardAppLogicalID.prefix(12))

            // Per-app overrides — pool > 0 is necessary but not sufficient.
            let dailyLimit = goalConfig.todayDailyLimit()
            if dailyLimit == 0 {
                debugLog("SHIELD_CHECK: \(shortID) dailyLimit=0 today — keeping shield", defaults: defaults)
                continue
            }
            if !isCurrentTimeInAllowedWindow(goalConfig) {
                debugLog("SHIELD_CHECK: \(shortID) outside allowed time window — keeping shield", defaults: defaults)
                continue
            }
            let usageMinutes = defaults.integer(
                forKey: "usage_\(goalConfig.rewardAppLogicalID)_today") / 60
            if dailyLimit < 1440 && usageMinutes >= dailyLimit {
                debugLog("SHIELD_CHECK: \(shortID) per-app daily limit reached (used=\(usageMinutes) >= \(dailyLimit)) — keeping shield", defaults: defaults)
                continue
            }

            // 2026-05-06 revert: pool > 0 alone is no longer sufficient. Kid must also have
            // met today's per-config learning goal. Earlier behavior (Apr 26 commit `172f72a`)
            // unshielded on pool-only carry-forward, which let kids skip today's learning when
            // they had Time Bank credit. Source-of-truth invariant — keep aligned with
            // BlockingCoordinator.evaluateBlockingState().
            let goalMet = checkGoalMet(goalConfig: goalConfig, rewardAppIDs: rewardAppIDs, defaults: defaults)
            if !goalMet {
                debugLog("SHIELD_CHECK: \(shortID) pool=\(pool)min but today's goal NOT met — keeping shield", defaults: defaults)
                continue
            }

            guard let token = try? Self.propertyListDecoder.decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) else {
                debugLog("SHIELD_CHECK: ❌ TOKEN DECODE FAILED for \(shortID) - tokenData may be invalid", defaults: defaults)
                continue
            }

            var currentShields = managedSettingsStore.shield.applications ?? Set()
            let containsToken = currentShields.contains(token)

            if containsToken {
                currentShields.remove(token)
                managedSettingsStore.shield.applications = currentShields.isEmpty ? nil : currentShields
                recordUnlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)
                debugLog("SHIELD_CHECK: ✅ REMOVED shield for \(shortID) (goalMet, pool=\(pool)min)", defaults: defaults)

                // Defensive guard: with goalMet=true, todayEarned should be > 0 unless
                // a linked goal has minutesRequired=0 (atypical config). Skip the
                // "Goal Complete!" fanfare in that edge case.
                let todayEarned = computeTodayEarnedForGoal(goalConfig, rewardAppIDs: rewardAppIDs, defaults: defaults)
                if todayEarned > 0 {
                    scheduleGoalCompletedNotification(rewardMinutes: todayEarned, rewardAppID: goalConfig.rewardAppLogicalID, defaults: defaults)
                }
            } else {
                debugLog("SHIELD_CHECK: ℹ️ \(shortID) goalMet+pool>0 but not currently shielded", defaults: defaults)
            }
        }
        debugLog("SHIELD_CHECK: Completed shield update check", defaults: defaults)
    }

    /// Check if a reward app's learning goal is met.
    ///
    /// `rewardAppIDs` (set of all reward-app logicalIDs from the configs) is used to filter
    /// stale entries: if a linkedLearningApp's logicalID is itself a reward app — usually
    /// because the parent flipped its category and old `linkedLearningApps` references
    /// weren't scrubbed — the entry is ignored. Reward-app *usage* must never count as
    /// learning toward another reward's goal, otherwise playing the reward app generates
    /// its own credit (pool grows during play, kid plays forever). Mirrors the main-app
    /// filter in `BlockingCoordinator.checkLearningGoal`.
    private nonisolated func checkGoalMet(
        goalConfig: ExtensionGoalConfigMinimal,
        rewardAppIDs: Set<String>,
        defaults: UserDefaults
    ) -> Bool {
        let shortID = String(goalConfig.rewardAppLogicalID.prefix(12))

        let validLinked = goalConfig.linkedLearningApps.filter { linked in
            if rewardAppIDs.contains(linked.learningAppLogicalID) {
                debugLog("GOAL_CHECK: \(shortID) skipping stale linked \(String(linked.learningAppLogicalID.prefix(12)))... (it's a reward app)", defaults: defaults)
                return false
            }
            return true
        }

        debugLog("GOAL_CHECK: \(shortID) mode=\(goalConfig.unlockMode) linkedApps=\(validLinked.count)", defaults: defaults)

        if validLinked.isEmpty {
            debugLog("GOAL_CHECK: ⚠️ \(shortID) has NO valid linked learning apps - goal cannot be met", defaults: defaults)
            return false
        }

        switch goalConfig.unlockMode {
        case "any":
            for linked in validLinked {
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
            for linked in validLinked {
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
        content.body = "You've earned \(Self.formatRewardDuration(rewardMinutes)) of reward time. Enjoy your games!"
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

    /// Check if any reward app should be blocked due to downtime, daily limit, learning goal not met,
    /// or exhausted Time Bank pool.
    /// Priority: dailyLimit==0 > Downtime > Daily limit exceeded > Learning goal not met > Pool empty.
    /// 2026-05-06 revert restored the per-config learning-goal block — pool > 0 alone no longer
    /// unshields, so this function must re-shield reward apps whose goal is fresh-for-the-day even
    /// when carry-forward bank credit exists. See `docs/SMART_THRESHOLD_FILTERING.md`
    /// "May 6, 2026 — Pool-Only Carry-Forward Unshield Reverted".
    private nonisolated func checkAndBlockIfRewardTimeExhausted(configs: ExtensionShieldConfigsMinimal?, defaults: UserDefaults) {
        guard let configs = configs else {
            return
        }

        // Pool is the same across all reward apps in this child's config — compute once.
        let pool = computeEffectivePoolBalance(configs: configs, defaults: defaults)
        let rewardAppIDs = Set(configs.goalConfigs.map { $0.rewardAppLogicalID })

        for goalConfig in configs.goalConfigs {
            // Get reward app usage (today). Use max(credited, iOS-claimed) so daily-limit
            // shielding reflects iOS's view even when LASTTHRESH_HOLD has stalled crediting.
            // See setUsageToThreshold's `ios_claimed_today_<id>` write for rationale.
            let credited = defaults.integer(forKey: "usage_\(goalConfig.rewardAppLogicalID)_today")
            let claimed = defaults.integer(forKey: "ios_claimed_today_\(goalConfig.rewardAppLogicalID)")
            let usageSeconds = max(credited, claimed)
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
                        defaults: defaults,
                        dailyLimitMinutes: 0,
                        nextAllowedDayName: goalConfig.nextAllowedDayDescription()
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
                        defaults: defaults,
                        dailyLimitMinutes: dailyLimit,
                        nextAllowedDayName: goalConfig.nextAllowedDayDescription()
                    )

                    debugLog("DAILY_LIMIT_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... used=\(usageMinutes)min >= limit=\(dailyLimit)min", defaults: defaults)
                }
                continue  // Skip reward time check - daily limit takes priority
            }

            // Check 1.5 (2026-05-06): Today's per-config learning goal not met → shield with
            // learningGoal reason regardless of pool. Restores pre-Apr-26 behavior; pool-only
            // carry-forward unshield was rolled back because kids skipped today's learning when
            // they had bank credit. Mirrors BlockingCoordinator.evaluateBlockingState gate.
            let goalMet = checkGoalMet(goalConfig: goalConfig, rewardAppIDs: rewardAppIDs, defaults: defaults)
            if !goalMet {
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

                    debugLog("LEARNING_GOAL_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... goal not met (pool=\(pool)min) — re-applying shield", defaults: defaults)
                }
                continue  // Skip pool-empty check - learning goal takes priority
            }

            // Check 2: Pool empty (only reachable when goal IS met) → re-apply shield with
            // rewardTimeExpired reason. Kid earned today's reward time but spent it all.
            if pool <= 0 {
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
                        reasonType: "rewardTimeExpired",
                        usedMinutes: usageMinutes,
                        defaults: defaults
                    )

                    debugLog("POOL_EMPTY_BLOCK: \(goalConfig.rewardAppLogicalID.prefix(12))... pool=\(pool)min — re-applying shield", defaults: defaults)
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

    /// Pool balance the child has available to spend on ANY reward app right now.
    /// Mirrors `AppUsageViewModel.cumulativeAvailableMinutes` (line 210) — the
    /// historical component is read from the App Group key the main app writes,
    /// the today-component is computed live by the extension.
    ///
    /// SOURCE-OF-TRUTH INVARIANT: if the main app's bank formula changes, this
    /// helper MUST be updated in the same commit. The matching main-app gate is
    /// `BlockingCoordinator.checkAvailableMinutes()` — keep them byte-equivalent.
    /// See `docs/SMART_THRESHOLD_FILTERING.md` "Apr 26–27, 2026 — Pooled Time Bank
    /// Shield Gate" and "May 3, 2026 — Pool-Divergence Re-shield Bypass".
    private nonisolated func computeEffectivePoolBalance(
        configs: ExtensionShieldConfigsMinimal,
        defaults: UserDefaults
    ) -> Int {
        let historical = defaults.integer(forKey: "bank_historical_remaining_minutes")

        // Defensive filter: a learning entry whose logicalID is also a reward app is a stale
        // reference (typically left over from a learning→reward category flip that didn't
        // scrub `linkedLearningApps`). Counting reward usage as learning lets the kid grow
        // the pool by playing the reward — see May 6, 2026 device repro on YouTube +
        // Mini Motorways. Mirrors `BlockingCoordinator.checkLearningGoal`.
        let rewardAppIDs = Set(configs.goalConfigs.map { $0.rewardAppLogicalID })

        // Today's earned: iterate UNIQUE learning apps across all goal configs.
        // A learning app may link to multiple reward apps with different
        // thresholds/ratios — match `AppUsageViewModel.totalEarnedMinutes` (line 156):
        // use the LOWEST threshold across all goals, and the FIRST-matching ratio.
        var seenLearningIDs = Set<String>()
        var todayEarned = 0
        for goalConfig in configs.goalConfigs {
            for linked in goalConfig.linkedLearningApps {
                guard !rewardAppIDs.contains(linked.learningAppLogicalID) else { continue }
                guard !seenLearningIDs.contains(linked.learningAppLogicalID) else { continue }
                seenLearningIDs.insert(linked.learningAppLogicalID)

                // Lowest threshold this learning app must clear (across all goals it feeds).
                let lowestThreshold = configs.goalConfigs
                    .flatMap { $0.linkedLearningApps }
                    .filter  { $0.learningAppLogicalID == linked.learningAppLogicalID }
                    .map     { $0.minutesRequired }
                    .min() ?? linked.minutesRequired

                let usageSeconds = defaults.integer(
                    forKey: "usage_\(linked.learningAppLogicalID)_today")
                let usageMinutes = usageSeconds / 60
                guard usageMinutes >= lowestThreshold else { continue }

                let ratio = Double(linked.rewardMinutesEarned) / Double(max(1, linked.ratioLearningMinutes))
                todayEarned += Int(Double(usageMinutes) * ratio)
            }
        }

        // Today's used: sum across all reward apps in the pool. Use the maximum of credited
        // (`usage_<id>_today`) and iOS-claimed (`ios_claimed_today_<id>`) so the shield reads
        // iOS's view of the kid's actual play even when LASTTHRESH_HOLD has stalled crediting.
        var todayUsed = 0
        for goalConfig in configs.goalConfigs {
            let credited = defaults.integer(forKey: "usage_\(goalConfig.rewardAppLogicalID)_today")
            let claimed = defaults.integer(forKey: "ios_claimed_today_\(goalConfig.rewardAppLogicalID)")
            todayUsed += max(credited, claimed) / 60
        }

        return max(0, historical + todayEarned - todayUsed)
    }

    /// Today's earned reward minutes for ONE goal config (no cross-goal dedupe).
    /// Used to decide whether a "Goal Complete!" notification should fire — pool-driven
    /// unshields where this goal earned nothing today must stay silent.
    private nonisolated func computeTodayEarnedForGoal(
        _ goalConfig: ExtensionGoalConfigMinimal,
        rewardAppIDs: Set<String>,
        defaults: UserDefaults
    ) -> Int {
        var earned = 0
        for linked in goalConfig.linkedLearningApps {
            // Same defensive filter as computeEffectivePoolBalance.
            guard !rewardAppIDs.contains(linked.learningAppLogicalID) else { continue }
            let usageSeconds = defaults.integer(
                forKey: "usage_\(linked.learningAppLogicalID)_today")
            let usageMinutes = usageSeconds / 60
            guard usageMinutes >= linked.minutesRequired else { continue }
            let ratio = Double(linked.rewardMinutesEarned) / Double(max(1, linked.ratioLearningMinutes))
            earned += Int(Double(usageMinutes) * ratio)
        }
        return earned
    }

    /// Format a duration in minutes for user-facing copy. <60 stays as "X min";
    /// ≥60 collapses to "Xh" or "Xh YYm". Mirror in NotificationService.swift.
    static fileprivate func formatRewardDuration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }

    /// Persist blocking reason for ShieldConfigurationExtension to display correct message.
    /// `dailyLimitMinutes` and `nextAllowedDayName` are written when known so the shield
    /// can render "Try again on Monday" / "off-limits today" copy without falling back
    /// to the generic message.
    private nonisolated func persistBlockingReason(
        tokenHash: String,
        reasonType: String,
        usedMinutes: Int,
        defaults: UserDefaults,
        dailyLimitMinutes: Int? = nil,
        nextAllowedDayName: String? = nil
    ) {
        let key = "appBlocking_\(tokenHash)"
        var blockingInfo: [String: Any] = [
            "tokenHash": tokenHash,
            "reasonType": reasonType,
            "updatedAt": Date().timeIntervalSince1970,
            "rewardUsedMinutes": usedMinutes
        ]
        if let dailyLimitMinutes { blockingInfo["dailyLimitMinutes"] = dailyLimitMinutes }
        if let nextAllowedDayName { blockingInfo["nextAllowedDayName"] = nextAllowedDayName }
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

    /// Mirror of DailyLimits.nextAllowedDayDescription on the extension side, so
    /// DAILY_ZERO_BLOCK / DAILY_LIMIT_BLOCK can persist a "Try again on Monday"-style
    /// hint without round-tripping through the main app.
    func nextAllowedDayDescription(from referenceDate: Date = Date()) -> String? {
        guard let perDay = dailyLimitsPerDay, perDay.count == 7 else { return nil }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEEE"

        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: referenceDate) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            if perDay[weekday - 1] > 0 {
                return offset == 1 ? "tomorrow" : formatter.string(from: candidate)
            }
        }
        return nil
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
