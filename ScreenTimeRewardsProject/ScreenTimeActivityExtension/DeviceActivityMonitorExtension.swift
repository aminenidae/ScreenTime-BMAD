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
        let trimmedLines = Array(lines.suffix(1499)) // Keep last 1499 to add 1 more (1500 total)
        log = (trimmedLines + [entry]).joined(separator: "\n")
        defaults.set(log, forKey: "extension_debug_log")
    }

    // MARK: - Phantom Flood Restart Signaling

    /// Track phantom flood events and signal main app when restart is needed
    /// When iOS sends catch-up events after restart, they "consume" thresholds and iOS won't send new events
    /// By detecting this flood and triggering a monitoring restart, we reset iOS's threshold state
    private nonisolated func trackPhantomFloodForRestart(defaults: UserDefaults) {
        let now = Date().timeIntervalSince1970
        let phantomWindowStart = defaults.double(forKey: "phantom_flood_window_start")
        var phantomCount = defaults.integer(forKey: "phantom_flood_count")

        // Reset window if > 60s old
        if now - phantomWindowStart > 60 || phantomWindowStart == 0 {
            phantomCount = 1
            defaults.set(now, forKey: "phantom_flood_window_start")
        } else {
            phantomCount += 1
        }
        defaults.set(phantomCount, forKey: "phantom_flood_count")

        debugLog("📊 PHANTOM_FLOOD_TRACK: count=\(phantomCount) windowAge=\(Int(now - phantomWindowStart))s", defaults: defaults)

        // Read previous event time BEFORE updating (for quiet gap detection)
        let previousEventTime = defaults.double(forKey: "phantom_flood_last_event_time")
        let gapSincePrevious = previousEventTime > 0 ? now - previousEventTime : 0
        defaults.set(now, forKey: "phantom_flood_last_event_time")

        // If 5+ phantom events in 60s, flag for main app restart
        if phantomCount >= 5 {
            // Flag for main-app restart (Darwin notification + BGTask + foreground check)
            if !defaults.bool(forKey: "phantom_flood_detected") {
                defaults.set(true, forKey: "phantom_flood_detected")
                // Send Darwin notification for immediate main-app restart (if app is active)
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.screentimerewards.phantomRestartNeeded" as CFString),
                    nil, nil, true
                )
                debugLog("🚨 FLOOD_DETECTED: count=\(phantomCount) - flagged for main app restart + Darwin notification sent", defaults: defaults)
            }

            let floodDuration = now - phantomWindowStart
            let floodSettled = gapSincePrevious > 20
            let floodMostlyDone = floodDuration > 3 && phantomCount >= 20

            if floodSettled || floodMostlyDone {
                debugLog("🚨 FLOOD_SETTLED: gap=\(String(format: "%.1f", gapSincePrevious))s duration=\(String(format: "%.1f", floodDuration))s count=\(phantomCount) - awaiting main app restart", defaults: defaults)
            } else {
                debugLog("🚨 PHANTOM_FLOOD: count=\(phantomCount) gap=\(String(format: "%.1f", gapSincePrevious))s duration=\(String(format: "%.1f", floodDuration))s - waiting", defaults: defaults)
            }
        }
    }

    /// Track the highest threshold minute seen per app during a flood.
    /// Used by restartMonitoringFromExtension to skip already-passed thresholds.
    /// Lightweight: ~2 UserDefaults ops (1 read + 1 conditional write).
    private nonisolated func trackFloodMaxThreshold(eventName: String, defaults: UserDefaults) {
        let parts = eventName.split(separator: ".")
        // Format: usage.app.<stableHash>.min.<N>
        guard parts.count == 5, parts[0] == "usage", parts[1] == "app",
              parts[3] == "min", let minute = Int(parts[4]) else { return }
        let stableHash = String(parts[2])
        let key = "flood_max_min_\(stableHash)"
        let currentMax = defaults.integer(forKey: key)
        if minute > currentMax {
            defaults.set(minute, forKey: key)
        }
    }

    /// Restart monitoring directly from the extension by reconstructing events from UserDefaults
    /// This eliminates the ~15 min gap of waiting for main app or BGTask to restart
    private nonisolated func restartMonitoringFromExtension(defaults: UserDefaults) {
        debugLog("🔄 EXT_RESTART: Attempting monitoring restart from extension", defaults: defaults)

        let allKeys = Array(defaults.dictionaryRepresentation().keys)

        // Step 1: Build token cache from ext_token_<stableHash> keys
        var tokenCache: [String: ApplicationToken] = [:]
        for key in allKeys where key.hasPrefix("ext_token_") {
            let stableHash = String(key.dropFirst("ext_token_".count))
            if let data = defaults.data(forKey: key),
               let token = try? PropertyListDecoder().decode(ApplicationToken.self, from: data) {
                tokenCache[stableHash] = token
            }
        }

        guard !tokenCache.isEmpty else {
            debugLog("❌ EXT_RESTART: No tokens found - falling back to main app restart", defaults: defaults)
            return
        }

        // Step 2: Reconstruct events dictionary from event mappings + tokens
        // Only register thresholds ABOVE each app's current usage to prevent catch-up floods
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        var skippedCount = 0
        for key in allKeys where key.hasPrefix("map_usage.app.") && key.hasSuffix("_id") {
            // Extract event name from key "map_<eventName>_id"
            let withoutPrefix = key.dropFirst(4)  // Remove "map_"
            let eventName = String(withoutPrefix.dropLast(3))  // Remove "_id"

            // Parse stableHash from event name "usage.app.<stableHash>.min.<N>"
            let parts = eventName.split(separator: ".")
            guard parts.count == 5 else { continue }
            let stableHash = String(parts[2])

            guard let token = tokenCache[stableHash] else { continue }

            let thresholdSec = defaults.integer(forKey: "map_\(eventName)_sec")
            guard thresholdSec > 0 else { continue }

            let thresholdMin = thresholdSec / 60
            // Smart filtering: skip thresholds at or below current usage to prevent catch-up floods
            let floodMaxMin = defaults.integer(forKey: "flood_max_min_\(stableHash)")
            let appID = defaults.string(forKey: "map_\(eventName)_id") ?? ""
            let currentTodayMin = appID.isEmpty ? 0 : defaults.integer(forKey: "usage_\(appID)_today") / 60
            let skipBelow = max(floodMaxMin, currentTodayMin)
            if skipBelow > 0 && thresholdMin <= skipBelow {
                skippedCount += 1
                continue
            }

            // Reconstruct threshold as DateComponents (thresholds are whole minutes)
            let threshold = DateComponents(minute: thresholdSec / 60)
            events[DeviceActivityEvent.Name(eventName)] = DeviceActivityEvent(
                applications: Set([token]),
                threshold: threshold
            )
        }
        debugLog("🔄 EXT_RESTART: Built \(events.count) future events, skipped \(skippedCount) already-passed", defaults: defaults)

        guard !events.isEmpty else {
            debugLog("❌ EXT_RESTART: Could not reconstruct events (0 built) - falling back to main app", defaults: defaults)
            return
        }

        // Step 3: Get activity name (stored by main app)
        let activityNameRaw = defaults.string(forKey: "ext_monitoring_activity_name") ?? "ScreenTimeTracking"
        let activityName = DeviceActivityName(activityNameRaw)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // Step 4: Stop current monitoring
        let center = DeviceActivityCenter()
        center.stopMonitoring([activityName])

        // Step 5: Set restart timestamp BEFORE starting (for phantom event filtering)
        let now = Date().timeIntervalSince1970
        defaults.set(now, forKey: "monitoring_restart_timestamp")
        defaults.set(now, forKey: "ext_last_monitoring_restart")
        defaults.set("extension", forKey: "last_restart_source")

        // Step 6: Start fresh monitoring session
        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
            debugLog("✅ EXT_RESTART: Successfully restarted monitoring with \(events.count) events (\(tokenCache.count) apps)", defaults: defaults)
            // Persist result for diagnostics (survives log truncation)
            defaults.set("success:\(events.count)events_\(tokenCache.count)apps", forKey: "ext_restart_result")
            defaults.set(Date().timeIntervalSince1970, forKey: "ext_restart_result_time")
            // Clear flood flags on success - fresh session has all thresholds reset
            defaults.set(false, forKey: "phantom_flood_detected")
            defaults.set(0, forKey: "phantom_flood_count")
            defaults.set(0, forKey: "phantom_flood_window_start") // Force catch-up to start own window
            // Increment restart count (allows up to 3 per flood cycle)
            // NOTE: flood_max_min keys intentionally NOT cleared — they accumulate
            // across restarts so each subsequent restart skips more already-passed thresholds
            defaults.set(defaults.integer(forKey: "ext_restart_count_this_flood") + 1, forKey: "ext_restart_count_this_flood")
        } catch {
            debugLog("❌ EXT_RESTART: startMonitoring failed - \(error.localizedDescription)", defaults: defaults)
            // Persist failure for diagnostics
            defaults.set("failed:\(error.localizedDescription)", forKey: "ext_restart_result")
            defaults.set(Date().timeIntervalSince1970, forKey: "ext_restart_result_time")
            // Re-flag so main app/BGTask can attempt restart
            defaults.set(true, forKey: "phantom_flood_detected")
        }
    }

    // MARK: - Lifecycle
    override nonisolated init() {
        super.init()
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(true, forKey: "extension_initialized_flag")
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")

            // Fallback: ensure restart timestamp exists to prevent phantom events
            // This covers edge cases where extension initializes before main app sets the timestamp
            if defaults.double(forKey: "monitoring_restart_timestamp") == 0 {
                defaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")
            }
        }
    }

    // MARK: - Interval Events
    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            // Clear monitoring-ended flag — monitoring is active again
            defaults.set(0.0, forKey: "monitoring_ended_timestamp")
            debugLog("INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)

            // Log restart diagnostics (persisted values survive log truncation during floods)
            if let restartResult = defaults.string(forKey: "ext_restart_result") {
                let restartTime = defaults.double(forKey: "ext_restart_result_time")
                let ago = restartTime > 0 ? "\(Int(Date().timeIntervalSince1970 - restartTime))s ago" : "unknown"
                debugLog("📋 RESTART_DIAG: result=\(restartResult) (\(ago))", defaults: defaults)
            }
            let restartSource = defaults.string(forKey: "last_restart_source") ?? "unknown"
            debugLog("📋 RESTART_SOURCE: \(restartSource)", defaults: defaults)
            let floodCount = defaults.integer(forKey: "phantom_flood_count")
            if floodCount > 0 {
                debugLog("📋 FLOOD_STATE: count=\(floodCount) detected=\(defaults.bool(forKey: "phantom_flood_detected"))", defaults: defaults)
            }
        }
        updateHeartbeat()
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            // Flush any buffered event - if monitoring ends without rapid-fire, it's legitimate
            let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")
            if bufferTimestamp > 0 {
                debugLog("✅ INTERVAL_END_FLUSH: recording buffered event (monitoring ended without flood)", defaults: defaults)
                flushBufferedEvent(defaults: defaults)
            }
            debugLog("INTERVAL_END activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)

            // Flag that monitoring ended — main app recovery stack will detect and restart if needed
            // Normal midnight: INTERVAL_START follows within ~1s and clears this flag
            // Silent death: flag stays set → recovery triggers restart
            defaults.set(Date().timeIntervalSince1970, forKey: "monitoring_ended_timestamp")
            debugLog("📡 INTERVAL_END: flagged monitoring_ended_timestamp (recovery via timer/BGTask)", defaults: defaults)
        }
    }

    // MARK: - Threshold Event Handler
    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        // Console visibility for development
        print("🔔 [EXTENSION] THRESHOLD EVENT: \(event.rawValue)")

        // Log FIRST - before any processing that could fail
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            // Increment persistent counter to track total events received
            let eventCount = defaults.integer(forKey: "ext_total_events_received") + 1
            defaults.set(eventCount, forKey: "ext_total_events_received")

            // Track max threshold per app for ALL events (used by smart restart filtering)
            trackFloodMaxThreshold(eventName: event.rawValue, defaults: defaults)

            // === STALE FLOOD WINDOW CHECK ===
            // After an ext restart, catch-up events (~1s) and the first real event (~55s)
            // must NOT be counted in the same flood window. A 50s timeout cleanly separates them.
            // Without this, the first real event pushes count to 20 → false FLOOD_RESTART.
            let staleWindowStart = defaults.double(forKey: "phantom_flood_window_start")
            if staleWindowStart > 0 {
                let windowAge = Date().timeIntervalSince1970 - staleWindowStart
                if windowAge > 50 {
                    defaults.set(0, forKey: "phantom_flood_count")
                    defaults.set(0, forKey: "phantom_flood_window_start")
                    defaults.set(false, forKey: "phantom_flood_detected")
                }
            }

            // LIGHTWEIGHT FLOOD MODE: When a flood is in progress (5+ phantom events),
            // skip ALL heavy processing to prevent iOS from killing the extension.
            // Normal path: ~50+ UserDefaults ops per event (MAPPING_AUDIT scans 500+ keys).
            // Lightweight: ~5 ops (counter + log + flood tracking). 10x less resource pressure.
            // Events during a flood are guaranteed phantoms, so zero data loss from skipping.
            let floodCount = defaults.integer(forKey: "phantom_flood_count")
            if floodCount >= 5 {
                debugLog("⚡ FLOOD_SKIP: count=\(floodCount) event=\(event.rawValue.suffix(20))", defaults: defaults)
                trackPhantomFloodForRestart(defaults: defaults)
                return
            }

            debugLog("THRESHOLD_CALL event=\(event.rawValue)", defaults: defaults)
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

        // === ENHANCED DIAGNOSTIC: Extract token hash from event name ===
        // Format: usage.app.<tokenHash>.min.<minute>
        let eventComponents = eventName.split(separator: ".")
        let tokenHash: String
        if eventComponents.count >= 3 && eventComponents[0] == "usage" && eventComponents[1] == "app" {
            tokenHash = String(eventComponents[2])
        } else {
            tokenHash = "UNKNOWN"
        }

        debugLog("📥 EVENT_RECV: raw=\(eventName)", defaults: defaults)
        debugLog("📥 EVENT_RECV: tokenHash=\(tokenHash)", defaults: defaults)

        // 1. Read event mapping (primitives only)
        let mapIdKey = "map_\(eventName)_id"

        // DIAGNOSTIC: Count total map keys and audit for duplicates
        let allMapKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("map_") && $0.hasSuffix("_id") }

        // Check how many events map to each appID (detect potential contamination)
        var appIDCounts: [String: Int] = [:]
        for key in allMapKeys {
            if let id = defaults.string(forKey: key) {
                appIDCounts[id, default: 0] += 1
            }
        }
        let uniqueAppIDs = appIDCounts.keys.count
        let maxEventsPerApp = appIDCounts.values.max() ?? 0
        debugLog("📊 MAPPING_AUDIT: totalMaps=\(allMapKeys.count) uniqueApps=\(uniqueAppIDs) maxEventsPerApp=\(maxEventsPerApp)", defaults: defaults)

        guard let appID = defaults.string(forKey: mapIdKey) else {
            // Try to read from JSON eventMappings as fallback
            if let mapping = readEventMappingFromJSON(eventName: eventName, defaults: defaults) {
                return recordUsageWithMapping(mapping, eventName: eventName, defaults: defaults)
            }
            debugLog("❌ NO_MAPPING: tokenHash=\(tokenHash) mapKey=\(mapIdKey)", defaults: defaults)
            return false
        }

        // DIAGNOSTIC: Log the resolved appID and category
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Unknown"
        let displayName = defaults.string(forKey: "map_\(appID)_name") ?? "Unknown"

        // === CROSS-APP CORRELATION: Track which apps record in sequence ===
        let lastRecordedAppID = defaults.string(forKey: "debug_last_recorded_appID") ?? "none"
        let lastRecordedTime = defaults.double(forKey: "debug_last_recorded_time")
        let lastRecordedName = defaults.string(forKey: "debug_last_recorded_name") ?? "none"
        let now = Date().timeIntervalSince1970
        let timeSinceLastRecord = lastRecordedTime > 0 ? Int(now - lastRecordedTime) : -1

        if lastRecordedAppID != appID && lastRecordedAppID != "none" && timeSinceLastRecord >= 0 && timeSinceLastRecord < 120 {
            // Different app recorded recently - potential contamination signal
            debugLog("⚠️ CROSS_APP: prev=\(lastRecordedName) (\(lastRecordedAppID.prefix(8))...) → now=\(displayName) (\(appID.prefix(8))...) gap=\(timeSinceLastRecord)s", defaults: defaults)
        }

        debugLog("✅ EVENT_RESOLVE: tokenHash=\(tokenHash) → appID=\(appID.prefix(12))... name=\(displayName) cat=\(category)", defaults: defaults)

        // 2. Extract the minute number from event name (e.g., "usage.app.0.min.15" → 15)
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        // DEBUG: Log event received with current state
        let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
        let currentThreshold = defaults.integer(forKey: "usage_\(appID)_lastThreshold")
        debugLog("EVENT appID=\(appID.prefix(8))... min=\(thresholdMinutes) currentToday=\(currentToday)s lastThresh=\(currentThreshold)s", defaults: defaults)

        // Console visibility for development
        print("📝 [EXTENSION] Recording: app=\(appID.prefix(8))... minute=\(thresholdMinutes) currentToday=\(currentToday)s")

        // 3. Process event through phantom filter + buffer system
        // Note: setUsageToThreshold now buffers valid events instead of recording immediately
        // Recording happens when buffer is flushed (on next validated event or INTERVAL_END)
        _ = setUsageToThreshold(appID: appID, thresholdSeconds: thresholdSeconds, defaults: defaults, eventName: eventName)

        // Check if event was buffered (vs blocked)
        // If phantom_buffer_appID matches this appID, the event is waiting for validation
        let bufferedAppID = defaults.string(forKey: "phantom_buffer_appID") ?? ""
        let wasBuffered = bufferedAppID == appID

        if wasBuffered {
            // Event is buffered, waiting for validation
            // Recording + notifications will happen when buffer is flushed
            debugLog("📦 EVENT_BUFFERED: appID=\(appID.prefix(8))... name=\(displayName) (waiting for validation)", defaults: defaults)

            // Update debug tracking for buffered event
            defaults.set(appID, forKey: "debug_last_buffered_appID")
            defaults.set(Date().timeIntervalSince1970, forKey: "debug_last_buffered_time")
            defaults.set(displayName, forKey: "debug_last_buffered_name")
        } else {
            // Event was blocked (phantom/duplicate)
            debugLog("⏭️ EVENT_BLOCKED: appID=\(appID.prefix(8))... name=\(displayName) (phantom/duplicate)", defaults: defaults)
        }

        // Return false - actual recording happens via buffer flush
        // The triggerPostRecordActions in recordValidatedUsage handles re-arm, shields, CloudKit, etc.
        return false
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

    /// Phantom-protected usage recording with event buffering
    /// Returns true if event was buffered (will be recorded later), false if blocked
    ///
    /// ATTEMPT 12: Simplified filter hierarchy with delayed recording
    /// 1. Filter 1: timeSinceRestart < 55s → BLOCK (can't have 60s usage in <55s)
    /// 2. Filter 2: timeSinceLastRecordedEvent < 55s → BLOCK (thresholds are 60s apart)
    /// 3. Events passing both filters → BUFFER (validate later when next event arrives)
    ///
    /// The buffer catches the first phantom event retroactively when rapid-fire follows
    private nonisolated func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults, eventName: String = "") -> Bool {
        let lastThresholdKey = "usage_\(appID)_lastThreshold"
        let lastEventTimeKey = "usage_\(appID)_lastEventTime"
        let now = Date()
        let nowTimestamp = now.timeIntervalSince1970

        // === PHANTOM DETECTION SETUP ===
        let restartTimestamp = defaults.double(forKey: "monitoring_restart_timestamp")
        let timeSinceRestart = restartTimestamp > 0 ? nowTimestamp - restartTimestamp : 999.0

        // Use last RECORDED timestamp (not last event timestamp) for cadence check
        // This ensures we measure against validated events, not phantom events
        let lastRecordedTimestamp = defaults.double(forKey: "last_recorded_timestamp")
        let timeSinceLastRecorded = lastRecordedTimestamp > 0 ? nowTimestamp - lastRecordedTimestamp : 999.0

        // Also track last event time for logging purposes
        let lastEventTime = defaults.double(forKey: lastEventTimeKey)
        let timeSinceLastEvent = lastEventTime > 0 ? nowTimestamp - lastEventTime : 999.0

        // Update last event time (track all events, even blocked ones)
        defaults.set(nowTimestamp, forKey: lastEventTimeKey)

        // Log diagnostic info
        let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
        let lastThreshold = defaults.integer(forKey: lastThresholdKey)
        debugLog("📥 PHANTOM_CHECK appID=\(appID.prefix(8))... threshold=\(thresholdSeconds)s currentToday=\(currentToday)s", defaults: defaults)
        debugLog("   timeSinceRestart=\(Int(timeSinceRestart))s timeSinceLastRecorded=\(Int(timeSinceLastRecorded))s timeSinceLastEvent=\(Int(timeSinceLastEvent))s", defaults: defaults)

        // === FILTER 1: MONITORING GAP ===
        // Block events within 55s of monitoring restart
        // Rationale: Can't accumulate 60s of app usage in less than 55s after restart
        if timeSinceRestart < 55.0 {
            debugLog("🛡️ MONITORING_GAP_BLOCK: \(Int(timeSinceRestart))s since restart (<55s)", defaults: defaults)

            // Check if there's a buffered event - count rapid events before discarding
            // Only discard after 3+ rapid events (real flood), not just 1-2 (could be out-of-order)
            let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")
            if bufferTimestamp > 0 {
                let timeSinceBuffer = nowTimestamp - bufferTimestamp
                if timeSinceBuffer < 15.0 {
                    let rapidCount = defaults.integer(forKey: "rapid_fire_count_since_buffer") + 1
                    defaults.set(rapidCount, forKey: "rapid_fire_count_since_buffer")

                    if rapidCount >= 3 {
                        debugLog("🚨 PHANTOM_FLOOD: \(rapidCount) rapid events - discarding buffer", defaults: defaults)
                        clearBuffer(defaults: defaults)
                    } else {
                        debugLog("⚠️ RAPID_EVENT: count=\(rapidCount)/3 (keeping buffer, not a flood yet)", defaults: defaults)
                    }
                }
            }

            // Track for flood detection (triggers delayed restart)
            trackPhantomFloodForRestart(defaults: defaults)
            return false
        }

        // === FILTER 2: EVENT CADENCE ===
        // Block events within 55s of last RECORDED event
        // Rationale: Threshold events fire every 60s of usage - can't have two within 55s
        if timeSinceLastRecorded < 55.0 {
            debugLog("🛡️ CADENCE_BLOCK: \(Int(timeSinceLastRecorded))s since last recorded (<55s)", defaults: defaults)

            // Check if there's a buffered event - count rapid events before discarding
            // Only discard after 3+ rapid events (real flood), not just 1-2 (could be out-of-order)
            let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")
            if bufferTimestamp > 0 {
                let timeSinceBuffer = nowTimestamp - bufferTimestamp
                if timeSinceBuffer < 15.0 {
                    let rapidCount = defaults.integer(forKey: "rapid_fire_count_since_buffer") + 1
                    defaults.set(rapidCount, forKey: "rapid_fire_count_since_buffer")

                    if rapidCount >= 3 {
                        debugLog("🚨 PHANTOM_FLOOD: \(rapidCount) rapid events - discarding buffer", defaults: defaults)
                        clearBuffer(defaults: defaults)
                    } else {
                        debugLog("⚠️ RAPID_EVENT: count=\(rapidCount)/3 (keeping buffer, not a flood yet)", defaults: defaults)
                    }
                }
            }

            // Track for flood detection
            trackPhantomFloodForRestart(defaults: defaults)
            return false
        }

        // === FILTER 3: LOCKED REWARD APP ===
        // If a reward app is locked (shielded), any usage is phantom
        // User can't use a locked app, so events are iOS catching up on old thresholds
        if isRewardAppLocked(appID: appID, defaults: defaults) {
            debugLog("🔒 LOCKED_REWARD_BLOCK: \(appID.prefix(8))... is locked - usage is phantom", defaults: defaults)
            trackPhantomFloodForRestart(defaults: defaults)
            return false
        }

        // === DUPLICATE THRESHOLD CHECK ===
        // Same threshold as last recorded = true duplicate, skip
        if thresholdSeconds == lastThreshold && lastThreshold > 0 {
            debugLog("📋 DUPLICATE_SKIP: threshold=\(thresholdSeconds)s == lastThreshold", defaults: defaults)
            return false
        }

        // === EVENT PASSED FILTERS - CHECK BUFFER ===
        let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")

        if bufferTimestamp > 0 {
            // There's a buffered event waiting for validation
            let timeSinceBuffer = nowTimestamp - bufferTimestamp

            if timeSinceBuffer < 15.0 {
                // New event arrived soon after buffer
                // Count rapid events - only discard after 3+ (real flood pattern)
                let rapidCount = defaults.integer(forKey: "rapid_fire_count_since_buffer") + 1
                defaults.set(rapidCount, forKey: "rapid_fire_count_since_buffer")

                if rapidCount >= 3 {
                    // 3+ rapid events = real flood, discard buffer
                    debugLog("🚨 PHANTOM_FLOOD: \(rapidCount) rapid events - discarding buffer", defaults: defaults)
                    clearBuffer(defaults: defaults)
                } else {
                    // 1-2 rapid events but new event passed filters = likely out-of-order
                    // Flush the buffer (it's probably legitimate) and continue
                    debugLog("⚠️ RAPID_BUT_VALID: count=\(rapidCount)/3, new event passed filters - flushing buffer", defaults: defaults)
                    flushBufferedEvent(defaults: defaults)
                }
                // Continue to buffer the new event below
            } else {
                // Buffer is old enough (>=15s) - record it as legitimate
                debugLog("✅ BUFFER_VALIDATED: no rapid-fire within 15s - flushing buffer", defaults: defaults)
                flushBufferedEvent(defaults: defaults)
            }
        }

        // === BUFFER THE CURRENT EVENT ===
        // Don't record immediately - wait to see if rapid-fire follows
        debugLog("📦 BUFFERING: \(appID.prefix(8))... threshold=\(thresholdSeconds)s (will validate on next event or INTERVAL_END)", defaults: defaults)
        bufferEvent(appID: appID, threshold: thresholdSeconds, eventName: eventName, defaults: defaults)

        // Update last threshold for duplicate detection
        defaults.set(thresholdSeconds, forKey: lastThresholdKey)

        // Return false because we haven't recorded yet (event is buffered)
        // The actual recording happens in flushBufferedEvent
        return false
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
    /// Note: With buffering system, this now delegates to setUsageToThreshold
    /// Actual recording happens when buffer is flushed via triggerPostRecordActions
    private nonisolated func recordUsageWithMapping(_ mapping: (appID: String, increment: Int, displayName: String, category: String, rewardPoints: Int), eventName: String, defaults: UserDefaults) -> Bool {
        // Extract threshold minutes from event name
        let thresholdMinutes = extractMinuteFromEventName(eventName)
        let thresholdSeconds = thresholdMinutes * 60

        // Process through phantom filter + buffer system
        _ = setUsageToThreshold(appID: mapping.appID, thresholdSeconds: thresholdSeconds, defaults: defaults, eventName: eventName)

        // Check if event was buffered
        let bufferedAppID = defaults.string(forKey: "phantom_buffer_appID") ?? ""
        let wasBuffered = bufferedAppID == mapping.appID

        if wasBuffered {
            debugLog("📦 EVENT_BUFFERED (mapping): appID=\(mapping.appID.prefix(8))... name=\(mapping.displayName)", defaults: defaults)
        }

        // Return false - actual recording happens via buffer flush
        // JSON persistence update is handled in triggerPostRecordActions
        return false
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

    // MARK: - Event Buffer (Phantom Flood Detection)

    /// Buffer an event for later validation (don't record immediately)
    /// If rapid-fire events follow, this was phantom - discard it
    /// If no rapid-fire follows, this was legitimate - record it
    private nonisolated func bufferEvent(appID: String, threshold: Int, eventName: String, defaults: UserDefaults) {
        defaults.set(appID, forKey: "phantom_buffer_appID")
        defaults.set(threshold, forKey: "phantom_buffer_threshold")
        defaults.set(Date().timeIntervalSince1970, forKey: "phantom_buffer_timestamp")
        defaults.set(eventName, forKey: "phantom_buffer_eventName")
        // Reset rapid-fire counter when new buffer is created
        defaults.set(0, forKey: "rapid_fire_count_since_buffer")
        debugLog("📦 BUFFERED: \(appID.prefix(8))... threshold=\(threshold)s (waiting to validate)", defaults: defaults)
    }

    /// Clear the buffer without recording (phantom flood detected)
    private nonisolated func clearBuffer(defaults: UserDefaults) {
        let appID = defaults.string(forKey: "phantom_buffer_appID") ?? "unknown"
        debugLog("🗑️ BUFFER_DISCARDED: \(appID.prefix(8))... (phantom flood detected)", defaults: defaults)
        defaults.removeObject(forKey: "phantom_buffer_appID")
        defaults.removeObject(forKey: "phantom_buffer_threshold")
        defaults.removeObject(forKey: "phantom_buffer_timestamp")
        defaults.removeObject(forKey: "phantom_buffer_eventName")
        defaults.set(0, forKey: "rapid_fire_count_since_buffer")
    }

    /// Flush the buffered event as legitimate usage (no rapid-fire followed)
    private nonisolated func flushBufferedEvent(defaults: UserDefaults) {
        guard let appID = defaults.string(forKey: "phantom_buffer_appID"),
              !appID.isEmpty else { return }

        let threshold = defaults.integer(forKey: "phantom_buffer_threshold")
        let eventName = defaults.string(forKey: "phantom_buffer_eventName") ?? ""
        let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")
        let age = Int(Date().timeIntervalSince1970 - bufferTimestamp)

        debugLog("✅ BUFFER_FLUSH: recording \(appID.prefix(8))... threshold=\(threshold)s (buffered \(age)s ago)", defaults: defaults)

        // Record the usage (bypass phantom filters - already validated)
        recordValidatedUsage(appID: appID, thresholdSeconds: threshold, eventName: eventName, defaults: defaults)

        // Clear buffer and reset rapid-fire counter
        defaults.removeObject(forKey: "phantom_buffer_appID")
        defaults.removeObject(forKey: "phantom_buffer_threshold")
        defaults.removeObject(forKey: "phantom_buffer_timestamp")
        defaults.removeObject(forKey: "phantom_buffer_eventName")
        defaults.set(0, forKey: "rapid_fire_count_since_buffer")
    }

    /// Check if a reward app is currently locked (shielded)
    /// Returns true if the app is a reward app AND is currently shielded
    /// Used to filter phantom usage events for locked apps
    private nonisolated func isRewardAppLocked(appID: String, defaults: UserDefaults) -> Bool {
        // Check if this is a reward app
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Unknown"
        guard category == "Reward" else { return false }

        // Get the token for this reward app from extensionShieldConfigs
        guard let data = defaults.data(forKey: "extensionShieldConfigs"),
              let configs = try? JSONDecoder().decode(ExtensionShieldConfigsMinimal.self, from: data) else {
            return false
        }

        // Find the goalConfig for this appID
        guard let goalConfig = configs.goalConfigs.first(where: { $0.rewardAppLogicalID == appID }) else {
            return false
        }

        // Decode the token
        guard let token = try? PropertyListDecoder().decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) else {
            return false
        }

        // Check if token is in shields
        let currentShields = managedSettingsStore.shield.applications ?? Set()
        return currentShields.contains(token)
    }

    /// Record usage that has been validated (passed phantom filters and buffer check)
    /// This is the actual recording logic, extracted from setUsageToThreshold
    private nonisolated func recordValidatedUsage(appID: String, thresholdSeconds: Int, eventName: String, defaults: UserDefaults) {
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

            // First event of new day
            debugLog("NEW_DAY appID=\(appID.prefix(8))... setting today=60s (first event)", defaults: defaults)

            defaults.set(60, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            defaults.set(60, forKey: totalKey)
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
            defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")
            defaults.set(nowTimestamp, forKey: "last_recorded_timestamp")
            defaults.set(appID, forKey: "last_recorded_appID")

            // === PROTECTED ext_ KEYS ===
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

            // Signal re-arm and trigger side effects
            triggerPostRecordActions(appID: appID, eventName: eventName, defaults: defaults)
            return
        }

        // === SAME DAY: INCREMENT ===
        let currentToday = defaults.integer(forKey: todayKey)
        let newToday = currentToday + 60

        debugLog("📋 VALIDATED_INCREMENT: \(appID.prefix(8))... currentToday=\(currentToday)s +60 → newToday=\(newToday)s", defaults: defaults)
        print("✅ [EXTENSION] Validated +60s for \(appID.prefix(8))... - total today: \(newToday)s")

        defaults.set(newToday, forKey: todayKey)
        defaults.set(thresholdSeconds, forKey: lastThresholdKey)
        defaults.set(nowTimestamp, forKey: "last_recorded_timestamp")
        defaults.set(appID, forKey: "last_recorded_appID")

        // Update total
        let currentTotal = defaults.integer(forKey: totalKey)
        let newTotal = currentTotal + 60
        defaults.set(newTotal, forKey: totalKey)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

        // === PROTECTED ext_ KEYS (INCREMENT) ===
        let currentExtToday = defaults.integer(forKey: "ext_usage_\(appID)_today")
        let currentExtTotal = defaults.integer(forKey: "ext_usage_\(appID)_total")
        let currentExtDate = defaults.string(forKey: "ext_usage_\(appID)_date")

        let newExtToday: Int
        if currentExtDate == dateString {
            newExtToday = currentExtToday + 60
        } else {
            newExtToday = 60
        }

        debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... INCREMENT today=\(newExtToday) total=\(currentExtTotal + 60) hour=\(hour) (was today=\(currentExtToday))", defaults: defaults)
        defaults.set(newExtToday, forKey: "ext_usage_\(appID)_today")
        defaults.set(currentExtTotal + 60, forKey: "ext_usage_\(appID)_total")
        defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
        defaults.set(hour, forKey: "ext_usage_\(appID)_hour")
        defaults.set(nowTimestamp, forKey: "ext_usage_\(appID)_timestamp")

        // === HOURLY BUCKET TRACKING (INCREMENT) ===
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

        // Signal re-arm and trigger side effects
        triggerPostRecordActions(appID: appID, eventName: eventName, defaults: defaults)
    }

    /// Trigger all post-record actions (re-arm signal, shield check, CloudKit sync)
    private nonisolated func triggerPostRecordActions(appID: String, eventName: String, defaults: UserDefaults) {
        let now = Date().timeIntervalSince1970

        // Signal re-arm request for continuous tracking
        defaults.set(true, forKey: "rearm_\(appID)_requested")
        defaults.set(now, forKey: "rearm_\(appID)_time")

        // EXTENSION SHIELD CONTROL: Check if any reward app goals are now met (unlocking)
        checkAndUpdateShields(defaults: defaults)

        // EXTENSION SHIELD BLOCKING: Check if any reward app has exhausted its earned time
        checkAndBlockIfRewardTimeExhausted(defaults: defaults)

        // EXTENSION CLOUDKIT SYNC: Sync usage directly to parent's CloudKit zone
        debugLog("TRIGGERING_CLOUDKIT_SYNC from recordValidatedUsage", defaults: defaults)
        ExtensionCloudKitSync.shared.syncUsageToParent(defaults: defaults)

        // Notify main app
        notifyMainApp()
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
