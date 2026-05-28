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

    // MARK: - Shadow Burst Tracker (May 17, 2026)
    // Captures per-burst data for the proposed "trust max threshold on legit
    // catch-up" rule. Pure observation — no credit-behavior changes.
    // At burst close (next event after 5s+ gap), emits SHADOW_BURST_JUDGE with
    // per-app max threshold, growth, qualification signals, and what the rule
    // WOULD have set today to vs what it actually is.
    // See SMART_THRESHOLD_FILTERING.md "May 17 — Burst Quarantine-and-Judge".

    private nonisolated func shadowBurstTrack(
        appID: String,
        thresholdSeconds: Int,
        nowTimestamp: TimeInterval,
        defaults: UserDefaults
    ) {
        let lastEventGlobal = defaults.double(forKey: "shadow_burst_last_event_ts")
        let gap = lastEventGlobal > 0 ? nowTimestamp - lastEventGlobal : 999.0

        // If gap > 5s, previous burst has closed — emit log and reset state
        if gap > 5.0 && lastEventGlobal > 0 {
            shadowBurstEmit(nowTimestamp: nowTimestamp, defaults: defaults)
            shadowBurstReset(defaults: defaults)
        }

        // Burst start timestamp (set once per burst)
        if defaults.double(forKey: "shadow_burst_start_ts") == 0 {
            defaults.set(nowTimestamp, forKey: "shadow_burst_start_ts")
            // Wall-clock budget baseline: snapshot the timestamp of the most recent
            // credit BEFORE this burst began. We read `last_credited_global_timestamp`
            // here, before this event flows through applyCredit and updates it. The
            // snapshot is frozen for the lifetime of this burst — the burst's own
            // credits don't get to update its own budget reference. See
            // shadowBurstEmit's SHADOW_BUDGET_CHECK for the comparison.
            let lastCreditTs = defaults.double(forKey: "last_credited_global_timestamp")
            defaults.set(lastCreditTs, forKey: "shadow_burst_baseline_credit_ts")
        }
        defaults.set(nowTimestamp, forKey: "shadow_burst_last_event_ts")

        // Total event count across all apps in this burst
        defaults.set(defaults.integer(forKey: "shadow_burst_total_events") + 1,
                     forKey: "shadow_burst_total_events")

        // Per-app: count, max, min, today-at-start snapshot
        let countKey = "shadow_burst_count_\(appID)"
        let isFirstForApp = defaults.integer(forKey: countKey) == 0
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)

        let maxKey = "shadow_burst_max_thresh_\(appID)"
        if thresholdSeconds > defaults.integer(forKey: maxKey) {
            defaults.set(thresholdSeconds, forKey: maxKey)
        }

        let minKey = "shadow_burst_min_thresh_\(appID)"
        let curMin = defaults.integer(forKey: minKey)
        if curMin == 0 || thresholdSeconds < curMin {
            defaults.set(thresholdSeconds, forKey: minKey)
        }

        if isFirstForApp {
            // Snapshot today value when this app first appears in burst — for cold-start signal
            let todayAtStart = defaults.integer(forKey: "usage_\(appID)_today")
            defaults.set(todayAtStart, forKey: "shadow_burst_today_at_start_\(appID)")

            // Add to apps CSV
            let appsCSV = defaults.string(forKey: "shadow_burst_apps_csv") ?? ""
            let updated = appsCSV.isEmpty ? appID : appsCSV + "," + appID
            defaults.set(updated, forKey: "shadow_burst_apps_csv")
        }
    }

    private nonisolated func shadowBurstEmit(nowTimestamp: TimeInterval, defaults: UserDefaults) {
        let startTs = defaults.double(forKey: "shadow_burst_start_ts")
        let endTs = defaults.double(forKey: "shadow_burst_last_event_ts")
        let dur = endTs - startTs
        let totalEvents = defaults.integer(forKey: "shadow_burst_total_events")
        let appsCSV = defaults.string(forKey: "shadow_burst_apps_csv") ?? ""
        let apps = appsCSV.split(separator: ",").map(String.init)

        let lastKill = defaults.double(forKey: "ext_last_kill_timestamp")
        let timeSinceLastKill = lastKill > 0 ? Int(nowTimestamp - lastKill) : -1

        var anyColdStartHigh = false
        var anyGrowthOverBudget = false
        var appDetails: [String] = []

        for appID in apps {
            let count = defaults.integer(forKey: "shadow_burst_count_\(appID)")
            let maxThresh = defaults.integer(forKey: "shadow_burst_max_thresh_\(appID)")
            let todayAtStart = defaults.integer(forKey: "shadow_burst_today_at_start_\(appID)")
            let unlockTime = defaults.double(forKey: "ext_unlock_\(appID)_timestamp")
            let unshieldAgeSec = unlockTime > 0 ? Int(nowTimestamp - unlockTime) : -1
            let unshieldAgeMin = unshieldAgeSec > 0 ? unshieldAgeSec / 60 : -1

            let maxMin = maxThresh / 60
            let todayAtStartMin = todayAtStart / 60
            let growthMin = max(0, maxMin - todayAtStartMin)
            let isColdStart = todayAtStart == 0

            // Signal A: cold start + high threshold = suspicious phantom signature
            if isColdStart && maxMin > 30 {
                anyColdStartHigh = true
            }

            // Signal B: growth vs unshield budget (reward apps have meaningful unshield time)
            if unshieldAgeMin > 0 {
                let budgetWithGrace = unshieldAgeMin + (unshieldAgeMin / 10)
                if growthMin > budgetWithGrace {
                    anyGrowthOverBudget = true
                }
            }

            // What the rule WOULD do vs current state
            let actualToday = defaults.integer(forKey: "usage_\(appID)_today")
            let actualTodayMin = actualToday / 60
            let wouldSetMin = maxMin
            let deltaMin = wouldSetMin - actualTodayMin

            appDetails.append("\(appID.prefix(8)):evs=\(count):max=min.\(maxMin):start_today=\(todayAtStartMin)min:growth=\(growthMin)min:cold=\(isColdStart):unshield_age=\(unshieldAgeMin)min:would_set=\(wouldSetMin)min:actual=\(actualTodayMin)min:delta=\(deltaMin >= 0 ? "+" : "")\(deltaMin)min")
        }

        let coldStartSignal = anyColdStartHigh ? "fail" : "pass"
        let growthSignal = anyGrowthOverBudget ? "fail" : "pass"
        let verdict = (coldStartSignal == "pass" && growthSignal == "pass") ? "legit" : "phantom"

        debugLog("SHADOW_BURST_JUDGE dur=\(String(format: "%.1f", dur))s events=\(totalEvents) apps=\(apps.count) timeSinceKill=\(timeSinceLastKill)s signals=[COLD_START_HIGH=\(coldStartSignal) GROWTH_VS_UNSHIELD=\(growthSignal)] verdict=\(verdict) details=[\(appDetails.joined(separator: " | "))]", defaults: defaults)

        // 2026-05-23 — Wall-clock budget check (shadow only).
        //
        // A child can use only one app at a time, so the total minutes claimed
        // across all apps in a burst cannot exceed the wall-clock time available
        // before the burst started. Budget is measured from the timestamp of the
        // most recent legitimate credit before this burst began (snapshotted in
        // shadowBurstTrack when the burst opened) up to the burst's first event.
        //
        // This check is the rigorous defense against phantom kill-replay floods
        // that the shape-based signals (COLD_START_HIGH, GROWTH_VS_UNSHIELD) cannot
        // reliably distinguish from legitimate catch-up. Pure observation for now;
        // promote to enforcement after a few days of shadow data confirms it trips
        // on real floods (May 23 incident: 282min claim in ~25min window) without
        // tripping on legitimate catch-ups.
        // Heal-mode bypass: a heal-triggered catch-up is intentional. Its
        // claim by design fills today's elapsed budget (baseline is anchored
        // at start-of-today by performHealUsage), but when we later promote
        // the budget check to enforcement we don't want any math edge case
        // (e.g. heal right after midnight, tiny budget) to revert the heal's
        // own catch-up. Same pattern as the other anti-phantom defenses:
        // during heal the check logs verdict=heal-bypass and does nothing.
        let healActiveUntil = defaults.double(forKey: "heal_active_until")
        let inHealMode = nowTimestamp < healActiveUntil

        let baselineCreditTs = defaults.double(forKey: "shadow_burst_baseline_credit_ts")
        var totalGrowthMin = 0
        for appID in apps {
            let maxThresh = defaults.integer(forKey: "shadow_burst_max_thresh_\(appID)")
            let todayAtStart = defaults.integer(forKey: "shadow_burst_today_at_start_\(appID)")
            let growthSec = max(0, maxThresh - todayAtStart)
            totalGrowthMin += growthSec / 60
        }
        let wallclockSec = baselineCreditTs > 0 ? max(0.0, startTs - baselineCreditTs) : -1.0
        let wallclockMin = wallclockSec >= 0 ? Int(wallclockSec / 60.0) : -1
        let budgetMin = wallclockMin >= 0 ? Int(Double(wallclockMin) * 1.1) : -1
        let budgetVerdict: String
        if inHealMode {
            budgetVerdict = "heal-bypass"
        } else if budgetMin < 0 {
            budgetVerdict = "no-baseline"
        } else if totalGrowthMin > budgetMin {
            budgetVerdict = "exceeded"
        } else {
            budgetVerdict = "within"
        }
        debugLog("SHADOW_BUDGET_CHECK total_growth=\(totalGrowthMin)min wallclock=\(wallclockMin)min budget=\(budgetMin)min verdict=\(budgetVerdict) apps=\(apps.count) baseline_age=\(baselineCreditTs > 0 ? String(format: "%.0f", nowTimestamp - baselineCreditTs) + "s" : "none")", defaults: defaults)
    }

    private nonisolated func shadowBurstReset(defaults: UserDefaults) {
        let appsCSV = defaults.string(forKey: "shadow_burst_apps_csv") ?? ""
        let apps = appsCSV.split(separator: ",").map(String.init)

        defaults.set(0.0, forKey: "shadow_burst_start_ts")
        defaults.set(0.0, forKey: "shadow_burst_last_event_ts")
        defaults.set(0, forKey: "shadow_burst_total_events")
        defaults.removeObject(forKey: "shadow_burst_apps_csv")
        defaults.removeObject(forKey: "shadow_burst_baseline_credit_ts")

        for appID in apps {
            defaults.removeObject(forKey: "shadow_burst_count_\(appID)")
            defaults.removeObject(forKey: "shadow_burst_max_thresh_\(appID)")
            defaults.removeObject(forKey: "shadow_burst_min_thresh_\(appID)")
            defaults.removeObject(forKey: "shadow_burst_today_at_start_\(appID)")
        }
    }

    // MARK: - Phase B+C: credit-on-arrival with undo on flood (no buffer)
    //
    // See docs/THREE_PHASE_RECORDING_ARCHITECTURE.md (v4).
    //
    // Every event that passes Phase A is credited at arrival. We save the
    // pre-credit (usage_today, lastThreshold) per app so we can roll back
    // if a flood signal arrives later in the same 5-second burst window.
    // When the burst window closes (next event arrives with gap ≥ 5s), the
    // credits become final and the undo state is cleared.

    private static let burstWindowSeconds: TimeInterval = 5

    /// Process an event arrival after Phase A passed. Updates burst state,
    /// applies credit (with revert info saved), triggers sliding-window
    /// rebuild if needed. Returns true if credit was applied (caller should
    /// notify the main app), false if rejected (e.g. burst is in flood mode).
    private nonisolated func processEventAndCredit(appID: String, thresholdSeconds: Int, now: TimeInterval, defaults: UserDefaults) -> Bool {
        // Phase B+C: the burst state was already maintained on entry to
        // setUsageToThreshold (gap check + last_event_arrival_global update).
        // Here we just check flood mode and credit.

        if defaults.bool(forKey: "burst_is_flood") {
            // Earlier event in this same burst detected a flood. All subsequent
            // events in the window are silently dropped (no credit) so they
            // can't smuggle phantom usage in alongside.
            debugLog("BURST_FLOOD_SKIP appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s — burst already classified as flood, ignoring", defaults: defaults)
            Self.logger.notice("BURST_FLOOD_SKIP app=\(appID.prefix(8))... thresh=\(thresholdSeconds)s")
            return false
        }

        // Wall-clock budget enforcement: total growth across all apps in this
        // burst cannot exceed wall-clock since the last credit before the burst.
        // The shadow system already tracks these values — promote to enforce.
        let healActiveUntil = defaults.double(forKey: "heal_active_until")
        let inHealMode = now < healActiveUntil
        if !inHealMode {
            let baselineCreditTs = defaults.double(forKey: "shadow_burst_baseline_credit_ts")
            if baselineCreditTs > 0 {
                let wallclockSec = max(0.0, now - baselineCreditTs)
                let budgetSec = wallclockSec * 1.1 + 60
                var totalGrowthSec = 0
                let appsCSV = defaults.string(forKey: "shadow_burst_apps_csv") ?? ""
                for burstApp in appsCSV.split(separator: ",").map(String.init) {
                    let maxThresh = defaults.integer(forKey: "shadow_burst_max_thresh_\(burstApp)")
                    let todayAtStart = defaults.integer(forKey: "shadow_burst_today_at_start_\(burstApp)")
                    totalGrowthSec += max(0, maxThresh - todayAtStart)
                }
                // shadowBurstTrack already updated max_thresh for this event,
                // so totalGrowthSec includes the current event's contribution.
                // Only add the proposed delta for apps NOT yet in the burst CSV.
                let alreadyTracked = Set(appsCSV.split(separator: ",").map(String.init))
                let proposedAddition = alreadyTracked.contains(appID) ? 0 : max(0, thresholdSeconds - defaults.integer(forKey: "usage_\(appID)_today"))
                let proposedGrowth = totalGrowthSec + proposedAddition
                if Double(proposedGrowth) > budgetSec {
                    debugLog("SKIP_BURST_BUDGET appID=\(appID.prefix(8))... growth=\(proposedGrowth)s > budget=\(Int(budgetSec))s (wallclock=\(Int(wallclockSec))s) — phantom reject", defaults: defaults)
                    Self.logger.notice("SKIP_BURST_BUDGET app=\(appID.prefix(8))... growth=\(proposedGrowth)s budget=\(Int(budgetSec))s")
                    // iOS consumes every registered threshold during the flood even
                    // though we reject each event; without a rebuild the window is a
                    // dead husk and real usage accumulates invisibly (see "2026-05-21
                    // — Phantom flood + recovery hole" in
                    // THREE_PHASE_RECORDING_ARCHITECTURE.md). Mirror revertBurstCredits:
                    // lock the burst as flood so the remaining events short-circuit at
                    // the burst_is_flood check instead of re-triggering recovery
                    // per-event, then request a fresh sliding window. The flag
                    // auto-clears when the next genuine burst opens (Phase B gap check).
                    defaults.set(true, forKey: "burst_is_flood")
                    requestMainAppWindowRebuild(reason: "post-budget-recovery", defaults: defaults)
                    return false
                }
            }
        }

        // Save revert info IFF this is the first credit for this app in the
        // current burst window. Subsequent credits to the same app within
        // the burst stay covered by the same revert snapshot.
        var creditedApps = readBurstCreditedApps(defaults: defaults)
        if !creditedApps.contains(appID) {
            let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
            let currentLastThreshold = defaults.integer(forKey: "usage_\(appID)_lastThreshold")
            defaults.set(currentToday, forKey: "revert_today_\(appID)")
            defaults.set(currentLastThreshold, forKey: "revert_lastThreshold_\(appID)")
            creditedApps.insert(appID)
            writeBurstCreditedApps(creditedApps, defaults: defaults)
        }

        applyCredit(appID: appID, newThreshold: thresholdSeconds, now: now, defaults: defaults)
        promoteTierIfNeeded(appID: appID, thresholdSeconds: thresholdSeconds, defaults: defaults)
        triggerRebuildIfNearWindowTop(appID: appID, threshold: thresholdSeconds, now: now, defaults: defaults)
        return true
    }

    /// Clear the burst window state. Called by Phase B when an event arrives
    /// with gap ≥ 5s from the previous arrival — the previous burst is over,
    /// its credits are final, and we no longer need the undo info.
    private nonisolated func clearBurstState(defaults: UserDefaults) {
        let creditedApps = readBurstCreditedApps(defaults: defaults)
        for appID in creditedApps {
            defaults.removeObject(forKey: "revert_today_\(appID)")
            defaults.removeObject(forKey: "revert_lastThreshold_\(appID)")
        }
        defaults.removeObject(forKey: "burst_credited_apps_csv")
        defaults.removeObject(forKey: "burst_is_flood")
    }

    /// Roll back every credit applied during the current burst window. Called
    /// by Phase A's SKIP_SHIELDED branch when a shielded reward app fires
    /// while a burst is in progress — the entire burst is then declared a
    /// flood and locked into `burst_is_flood` mode.
    private nonisolated func revertBurstCredits(reason: String, defaults: UserDefaults) {
        let creditedApps = readBurstCreditedApps(defaults: defaults)
        guard !creditedApps.isEmpty else { return }

        var revertDescParts: [String] = []
        for appID in creditedApps {
            let revertToday = defaults.integer(forKey: "revert_today_\(appID)")
            let revertLastThresh = defaults.integer(forKey: "revert_lastThreshold_\(appID)")
            let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
            defaults.set(revertToday, forKey: "usage_\(appID)_today")
            defaults.set(revertLastThresh, forKey: "usage_\(appID)_lastThreshold")
            defaults.removeObject(forKey: "revert_today_\(appID)")
            defaults.removeObject(forKey: "revert_lastThreshold_\(appID)")
            revertDescParts.append("\(appID.prefix(8))(\(currentToday)s→\(revertToday)s)")
        }

        defaults.set(true, forKey: "burst_is_flood")
        defaults.removeObject(forKey: "burst_credited_apps_csv")

        let revertDesc = revertDescParts.sorted().joined(separator: ", ")
        debugLog("BURST_REVERT reason=\(reason) appsReverted=\(creditedApps.count) — \(revertDesc)", defaults: defaults)
        Self.logger.notice("BURST_REVERT reason=\(reason) appsReverted=\(creditedApps.count)")

        // Post-flood recovery: iOS consumed every registered threshold during the
        // flood burst, even though we rejected each event. Request a main-app
        // `restartMonitoring` so a fresh sliding window gets registered before
        // legit usage accumulates invisibly (see "2026-05-21 — Phantom flood +
        // recovery hole" in THREE_PHASE_RECORDING_ARCHITECTURE.md).
        requestMainAppWindowRebuild(reason: "post-flood-recovery", defaults: defaults)
    }

    private nonisolated func readBurstCreditedApps(defaults: UserDefaults) -> Set<String> {
        let csv = defaults.string(forKey: "burst_credited_apps_csv") ?? ""
        if csv.isEmpty { return [] }
        return Set(csv.split(separator: ",").map(String.init))
    }

    private nonisolated func writeBurstCreditedApps(_ apps: Set<String>, defaults: UserDefaults) {
        if apps.isEmpty {
            defaults.removeObject(forKey: "burst_credited_apps_csv")
        } else {
            defaults.set(apps.sorted().joined(separator: ","), forKey: "burst_credited_apps_csv")
        }
    }

    /// Apply credit for one app: SET `usage_today` and `lastThreshold` to
    /// `max(currentToday, newThreshold)`. iOS's threshold is the authoritative
    /// cumulative for that app; we trust the max value. The two fields are
    /// written the same value to keep them in lock-step.
    private nonisolated func applyCredit(appID: String, newThreshold: Int, now: TimeInterval, defaults: UserDefaults) {
        let currentToday = defaults.integer(forKey: "usage_\(appID)_today")
        let newToday = max(currentToday, newThreshold)
        let credited = newToday - currentToday

        defaults.set(newToday, forKey: "usage_\(appID)_today")
        defaults.set(newToday, forKey: "usage_\(appID)_lastThreshold")
        defaults.set(now, forKey: "usage_\(appID)_modified")
        // Per-day reset anchor — ensures cross-day logic stays consistent.
        let startOfToday = Self.calendar.startOfDay(for: Date(timeIntervalSince1970: now)).timeIntervalSince1970
        defaults.set(startOfToday, forKey: "usage_\(appID)_reset")

        // Global "last credited" anchor used by other code paths.
        defaults.set(now, forKey: "last_credited_global_timestamp")

        // Heal-mode keepalive: while heal_active_until is in the future, every
        // successful credit extends it by 30 more seconds. As long as iOS is
        // delivering catch-up events for ANY app, the heal window stays open.
        // The flag only expires when catch-up genuinely goes silent for 30s,
        // which is when the rebuild chain is actually done. Outside heal mode
        // the flag is 0/expired and the check is a no-op.
        let healActiveUntil = defaults.double(forKey: "heal_active_until")
        if now < healActiveUntil {
            defaults.set(now + 10, forKey: "heal_active_until")
        }

        // ext_ keys — totals and timestamps the main app and other code may read.
        // ext_usage_date MUST be set here: extensionRebuildSlidingWindow gates its
        // usage_today read on this key matching today's date. Without it, rebuilds
        // read current=0 and re-register from minute 1, exhausting the window.
        let dateString = Self.dayDateFormatter.string(from: Date(timeIntervalSince1970: now))
        defaults.set(dateString, forKey: "ext_usage_\(appID)_date")
        if credited > 0 {
            let currentTotal = defaults.integer(forKey: "ext_usage_\(appID)_total")
            defaults.set(currentTotal + credited, forKey: "ext_usage_\(appID)_total")
        }
        defaults.set(now, forKey: "ext_usage_\(appID)_timestamp")

        debugLog("RECORDED appID=\(appID.prefix(8))... oldToday=\(currentToday)s set newToday=\(newToday)s (thresh=\(newThreshold)s, +\(credited)s)", defaults: defaults)
        Self.logger.notice("SET app=\(appID.prefix(8))... today=\(newToday)s (+\(credited)s) thresh=\(newThreshold)s")

        defaults.set(now, forKey: "last_recorded_timestamp")
    }

    /// Tiered window promotion (May 25, 2026). Reward apps start at 5 thresholds
    /// (sentinel). Promote to 30 on first use, and to min(dailyLimit, 90) at 25 min.
    /// Each promotion triggers a window rebuild so iOS has the wider threshold range.
    private nonisolated func promoteTierIfNeeded(appID: String, thresholdSeconds: Int, defaults: UserDefaults) {
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
        guard category == "Reward" else { return }

        let currentWindow = defaults.integer(forKey: "window_size_\(appID)")
        let usageMin = thresholdSeconds / 60

        var promoted = false
        if currentWindow <= 5 && usageMin > 0 {
            let newWindow: Int
            if usageMin >= 25 {
                newWindow = 90
            } else {
                newWindow = 30
            }
            defaults.set(newWindow, forKey: "window_size_\(appID)")
            debugLog("TIER_PROMOTE appID=\(appID.prefix(8))... \(currentWindow)→\(newWindow) (usage=\(usageMin)min)", defaults: defaults)
            Self.logger.notice("TIER_PROMOTE app=\(appID.prefix(8))... \(currentWindow)→\(newWindow)")
            promoted = true
        } else if currentWindow <= 30 && usageMin >= 25 {
            let newWindow = 90
            defaults.set(newWindow, forKey: "window_size_\(appID)")
            debugLog("TIER_PROMOTE appID=\(appID.prefix(8))... \(currentWindow)→\(newWindow) (usage=\(usageMin)min)", defaults: defaults)
            Self.logger.notice("TIER_PROMOTE app=\(appID.prefix(8))... \(currentWindow)→\(newWindow)")
            promoted = true
        }
        if promoted {
            defaults.removeObject(forKey: "window_rebuild_request_\(appID)")
        }
    }

    /// If this event's threshold approaches the registered window top for this
    /// app, request a sliding-window rebuild so iOS has fresh thresholds to
    /// fire on for future usage. Per-app 60s debounce via
    /// `window_rebuild_request_<id>`.
    private nonisolated func triggerRebuildIfNearWindowTop(appID: String, threshold: Int, now: TimeInterval, defaults: UserDefaults) {
        let windowTopMin = defaults.integer(forKey: "window_top_min_\(appID)")
        guard windowTopMin > 0 else { return }
        let threshMin = threshold / 60
        guard threshMin >= windowTopMin - 5 else { return }

        // Heal mode: when the main app's healUsageData kicked off a catch-up,
        // it sets `heal_active_until` ~30s into the future. During that window
        // we shrink the per-app debounce from 60s → 1s so consecutive window
        // rebuilds can chain back-to-back. Without this, catch-up deadlocks
        // at the first window boundary because no further rebuilds can fire.
        //
        // Self-extending: every rebuild that fires while heal is active pushes
        // the expiry forward by another 15s. As long as catch-up keeps making
        // progress (more rebuilds firing), the window stays open. When events
        // stop arriving the flag naturally expires within ~15s and normal
        // debounce returns. Without this, a long catch-up (e.g. Instagram at
        // 116min needing 6 chained rebuilds) outlasts a fixed 30s window and
        // deadlocks at the boundary where the flag expired.
        let healActiveUntil = defaults.double(forKey: "heal_active_until")
        let inHealMode = now < healActiveUntil
        let debounceSec: Double = inHealMode ? 1.0 : 60.0

        let debounceKey = "window_rebuild_request_\(appID)"
        let lastRequest = defaults.double(forKey: debounceKey)
        guard (now - lastRequest) > debounceSec else { return }

        defaults.set(now, forKey: debounceKey)
        if inHealMode {
            defaults.set(now + 10, forKey: "heal_active_until")
        }
        debugLog("REBUILD_REQUEST appID=\(appID.prefix(8))... threshMin=\(threshMin) windowTop=\(windowTopMin) — approaching window top, requesting refresh", defaults: defaults)
        Self.logger.notice("REBUILD_REQUEST app=\(appID.prefix(8))... threshMin=\(threshMin)")
        requestMainAppWindowRebuild(reason: "credit-near-top-\(appID.prefix(8))", defaults: defaults)
        _ = extensionRebuildSlidingWindow(defaults: defaults, triggerAppID: appID, reason: "credit-near-top-\(appID.prefix(8))")
    }

    // MARK: - Heal (2026-05-23, extension-canonical)
    //
    // Self-healing reset: wipe today's recorded usage and ask iOS for the
    // authoritative cumulative via a sliding-window rebuild. Lives in the
    // extension because (1) ~90% of recording work already runs here, (2) auto-
    // heal triggers (e.g. wall-clock budget anomalies) fire from inside event
    // handlers and shouldn't depend on the main app being awake, and (3) iOS
    // can wake the extension via threshold events even when the main app is
    // terminated, so heal completes regardless of foreground state.
    //
    // Manual heal path: main app's button writes `heal_requested_at` + reason
    // and calls restartMonitoring. iOS delivers intervalDidStart to the
    // extension, which sees the flag and calls performHealUsage() before the
    // regular intervalDidStart logic runs.
    //
    // Auto-heal path: any extension-internal trigger (budget anomaly, judge
    // verdict, future heuristics) calls performHealUsage() directly. No
    // round-trip to the main app required.
    //
    // See docs/THREE_PHASE_RECORDING_ARCHITECTURE.md "2026-05-23 — Heal
    // mechanism" for the full design and rationale.

    /// Perform the heal: wipe today's per-app totals, reset state flags so the
    /// catch-up burst doesn't trip any anti-phantom defenses, then re-register
    /// the sliding window so iOS delivers fresh threshold events carrying its
    /// authoritative cumulative for today.
    private nonisolated func performHealUsage(reason: String, defaults: UserDefaults) {
        lifecycleLog("HEAL_USAGE_START — reason: \(reason)", defaults: defaults)
        Self.logger.notice("HEAL_USAGE_START reason=\(reason)")

        let appIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
        guard !appIDs.isEmpty else {
            lifecycleLog("HEAL_USAGE_SKIP — no tracked apps", defaults: defaults)
            return
        }

        let startOfToday = Self.calendar.startOfDay(for: Date()).timeIntervalSince1970
        let nowTs = Date().timeIntervalSince1970

        // Snapshot pre-heal totals for the audit trail.
        var preHealTotalSec = 0
        var preHealParts: [String] = []
        for appID in appIDs {
            let secs = defaults.integer(forKey: "usage_\(appID)_today")
            preHealTotalSec += secs
            if secs > 0 {
                preHealParts.append("\(appID.prefix(8))=\(secs / 60)min")
            }
        }

        // Zero each app's today counters, hourly buckets, and the shadow burst
        // tracker's per-app keys (the latter is what caused the apps=0 bug in
        // SHADOW_BUDGET_CHECK during the May 23 heal tests — heal cleared the
        // global shadow state but missed these per-app counters).
        for appID in appIDs {
            defaults.set(0, forKey: "usage_\(appID)_today")
            defaults.set(0, forKey: "usage_\(appID)_lastThreshold")
            defaults.set(nowTs, forKey: "usage_\(appID)_modified")
            defaults.set(startOfToday, forKey: "usage_\(appID)_reset")

            defaults.set(0, forKey: "ext_usage_\(appID)_today")
            defaults.removeObject(forKey: "ext_usage_\(appID)_timestamp")

            for h in 0..<24 {
                defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
            }

            // Shadow burst tracker per-app state — must clear so the heal's own
            // catch-up burst registers fresh app entries in shadow_burst_apps_csv.
            defaults.removeObject(forKey: "shadow_burst_count_\(appID)")
            defaults.removeObject(forKey: "shadow_burst_max_thresh_\(appID)")
            defaults.removeObject(forKey: "shadow_burst_min_thresh_\(appID)")
            defaults.removeObject(forKey: "shadow_burst_today_at_start_\(appID)")

            // Burst revert state from any in-flight burst.
            defaults.removeObject(forKey: "revert_today_\(appID)")
            defaults.removeObject(forKey: "revert_lastThreshold_\(appID)")
        }

        // Anchor wall-clock budget baseline at start-of-today so the upcoming
        // catch-up burst's total claim fits within today's elapsed budget.
        defaults.set(startOfToday, forKey: "last_credited_global_timestamp")

        // Activate heal mode so anti-phantom defenses (SKIP_FLOOD, SKIP_SHIELDED,
        // BURST_REVERT, PHANTOM_FLOOD_DETECTED, FIRST_EVENT_BUFFER) stand aside
        // while iOS delivers its authoritative catch-up. The flag self-extends
        // Duration must cover ALL batches + iOS delivery delay. Batches advance
        // every 10s × up to 6 batches = 60s, plus iOS can take 30-60s to deliver
        // catch-ups after the last batch. 120s covers worst case; keepalive in
        // applyCredit extends it further if catch-ups are still arriving.
        let batchCount = defaults.integer(forKey: "heal_batch_total")
        let healDuration = max(120.0, Double(batchCount) * 10.0 + 60.0)
        defaults.set(nowTs + healDuration, forKey: "heal_active_until")
        defaults.set(0, forKey: "heal_batch_last_processed")

        // Clear global burst/flood state for a clean restart.
        defaults.removeObject(forKey: "burst_credited_apps_csv")
        defaults.removeObject(forKey: "burst_is_flood")
        defaults.removeObject(forKey: "last_event_arrival_global")
        defaults.removeObject(forKey: "phantom_flood_active_until")

        // Reset shadow burst tracker globals.
        defaults.removeObject(forKey: "shadow_burst_apps_csv")
        defaults.set(0.0, forKey: "shadow_burst_start_ts")
        defaults.set(0.0, forKey: "shadow_burst_last_event_ts")
        defaults.set(0, forKey: "shadow_burst_total_events")
        defaults.removeObject(forKey: "shadow_burst_baseline_credit_ts")

        // Clear per-rebuild debounce timestamps so the catch-up chain isn't
        // blocked by stale per-app debounce. Heal-mode shortens debounce to 1s
        // anyway, but starting from a clean baseline keeps things predictable.
        // Also clear goal-completed notification flags — usage was reset so the
        // goal is un-met; the notification should fire again when re-earned.
        let todayKey = Self.dayDateFormatter.string(from: Date(timeIntervalSince1970: nowTs))
        for appID in appIDs {
            defaults.removeObject(forKey: "window_rebuild_request_\(appID)")
            defaults.removeObject(forKey: "ext_goal_notification_\(appID)_\(todayKey)")
        }

        let preHealMin = preHealTotalSec / 60
        let appsSummary = preHealParts.isEmpty ? "no prior usage" : preHealParts.joined(separator: ", ")
        lifecycleLog("HEAL_USAGE_RESET — cleared \(preHealMin)min across \(appIDs.count) apps [\(appsSummary)]", defaults: defaults)
        Self.logger.notice("HEAL_USAGE_RESET cleared=\(preHealMin)min apps=\(appIDs.count)")

        // Batch mode: if the main app set a batch plan, only register thresholds
        // for the current batch's apps. Future-batch apps keep window_size=0 so
        // extensionRebuildSlidingWindow skips them. This prevents the memory-
        // overload crash loop that occurs when 20 apps × 90 thresholds fire at once.
        if defaults.bool(forKey: "heal_batch_active"),
           let batchPlanData = defaults.data(forKey: "heal_batch_plan"),
           let batchPlan = try? JSONDecoder().decode([[String]].self, from: batchPlanData),
           !batchPlan.isEmpty {
            let currentBatch = defaults.integer(forKey: "heal_batch_current")
            let allowedApps = Set(batchPlan.prefix(currentBatch + 1).flatMap { $0 })
            for appID in appIDs where !allowedApps.contains(appID) {
                defaults.set(0, forKey: "window_size_\(appID)")
            }
            let batchApps = batchPlan[currentBatch]
            lifecycleLog("HEAL_BATCH_MODE — batch \(currentBatch) apps=[\(batchApps.map { String($0.prefix(8)) }.joined(separator: ","))] allowed=\(allowedApps.count) deferred=\(appIDs.count - allowedApps.count)", defaults: defaults)
        }

        // Re-register the sliding window. In batch mode, only the current batch's
        // apps have non-zero window_size, so only they get thresholds registered.
        let rebuildOK = extensionRebuildSlidingWindow(
            defaults: defaults,
            triggerAppID: nil,
            reason: "heal-\(reason)"
        )
        if !rebuildOK {
            lifecycleLog("HEAL_USAGE_REBUILD_FAILED — sliding-window re-registration failed; main app will retry on next foreground", defaults: defaults)
            Self.logger.error("HEAL_USAGE_REBUILD_FAILED — extension rebuild returned false")
            // Set the same flag the midnight path uses so the main app does a
            // safety-net scheduleActivity() the next time it's running.
            defaults.set(true, forKey: "midnight_pending_refresh")
            defaults.set(nowTs, forKey: "midnight_pending_timestamp")
        }

        // Notify the main app so its UI re-reads usage and shield state.
        notifyMainApp()

        lifecycleLog("HEAL_USAGE_DONE — iOS catch-up will rebuild today's usage", defaults: defaults)
        Self.logger.notice("HEAL_USAGE_DONE — rebuild dispatched")
    }

    /// Called from intervalDidStart on every monitoring restart. If the main
    /// app set `heal_requested_at` within the last 60 seconds, this is a
    /// heal-driven restart — drain the flag and perform the heal before the
    /// regular intervalDidStart processing runs.
    private nonisolated func consumeHealRequestIfPresent(defaults: UserDefaults) {
        let requestedAt = defaults.double(forKey: "heal_requested_at")
        guard requestedAt > 0 else { return }
        let age = Date().timeIntervalSince1970 - requestedAt
        guard age <= 60 else {
            // Stale request — drain without acting. Prevents a forgotten flag
            // from triggering an unexpected heal hours later.
            defaults.removeObject(forKey: "heal_requested_at")
            defaults.removeObject(forKey: "heal_requested_reason")
            lifecycleLog("HEAL_USAGE_STALE — request age=\(Int(age))s, draining without action", defaults: defaults)
            return
        }
        let reason = defaults.string(forKey: "heal_requested_reason") ?? "main-app-button"
        defaults.removeObject(forKey: "heal_requested_at")
        defaults.removeObject(forKey: "heal_requested_reason")
        performHealUsage(reason: reason, defaults: defaults)
    }

    /// Called from intervalDidStart to handle batched heal advancement.
    /// When the main app's timer advances heal_batch_current and triggers
    /// a restart, this runs in the new extension session to process the
    /// next batch of reward apps.
    private nonisolated func processHealBatchIfNeeded(defaults: UserDefaults) {
        guard defaults.bool(forKey: "heal_batch_active") else { return }
        let currentBatch = defaults.integer(forKey: "heal_batch_current")
        guard currentBatch > 0 else { return }

        // Prevent re-entry: extensionRebuildSlidingWindow calls startMonitoring
        // which triggers intervalDidStart which calls us again. Only run once
        // per batch number.
        let lastProcessed = defaults.integer(forKey: "heal_batch_last_processed")
        guard currentBatch > lastProcessed else { return }
        defaults.set(currentBatch, forKey: "heal_batch_last_processed")

        guard let batchPlanData = defaults.data(forKey: "heal_batch_plan"),
              let batchPlan = try? JSONDecoder().decode([[String]].self, from: batchPlanData) else {
            defaults.removeObject(forKey: "heal_batch_active")
            return
        }

        guard currentBatch < batchPlan.count else {
            defaults.removeObject(forKey: "heal_batch_active")
            defaults.removeObject(forKey: "heal_batch_plan")
            defaults.removeObject(forKey: "heal_batch_current")
            defaults.removeObject(forKey: "heal_batch_total")
            defaults.removeObject(forKey: "heal_batch_last_processed")
            lifecycleLog("HEAL_BATCH_DONE — all batches processed, cleaning up", defaults: defaults)
            return
        }

        let nowTs = Date().timeIntervalSince1970

        // Extend heal mode — ensure it covers remaining batches + iOS delivery delay.
        let currentHealUntil = defaults.double(forKey: "heal_active_until")
        let newHealUntil = max(currentHealUntil, nowTs + 60)
        defaults.set(newHealUntil, forKey: "heal_active_until")

        // Clear burst/flood state for clean batch processing
        defaults.removeObject(forKey: "burst_credited_apps_csv")
        defaults.removeObject(forKey: "burst_is_flood")
        defaults.removeObject(forKey: "last_event_arrival_global")
        defaults.removeObject(forKey: "phantom_flood_active_until")

        // Set window_size = 0 for apps in FUTURE batches
        let allowedApps = Set(batchPlan.prefix(currentBatch + 1).flatMap { $0 })
        let allApps = defaults.stringArray(forKey: "tracked_app_ids") ?? []
        for appID in allApps where !allowedApps.contains(appID) {
            defaults.set(0, forKey: "window_size_\(appID)")
        }

        // Restore window size for newly-allowed apps and clear rebuild debounce.
        let batchApps = batchPlan[currentBatch]
        for appID in batchApps {
            if defaults.integer(forKey: "window_size_\(appID)") <= 0 {
                let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
                defaults.set(category == "Learning" ? 30 : 5, forKey: "window_size_\(appID)")
            }
            defaults.removeObject(forKey: "window_rebuild_request_\(appID)")
        }

        lifecycleLog("HEAL_BATCH_PROCESS — batch \(currentBatch)/\(batchPlan.count - 1) apps=[\(batchApps.map { String($0.prefix(8)) }.joined(separator: ","))] allowed_total=\(allowedApps.count)", defaults: defaults)

        _ = extensionRebuildSlidingWindow(defaults: defaults, triggerAppID: nil, reason: "heal-batch-\(currentBatch)")
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
                    // Shadow burst-judge: record kill timestamp for the KILL_DENSITY signal.
                    // See SMART_THRESHOLD_FILTERING.md "May 17 — Burst Quarantine-and-Judge".
                    defaults.set(Date().timeIntervalSince1970, forKey: "ext_last_kill_timestamp")
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

            // Heal hook: if the main app's button just set heal_requested_at,
            // perform the heal here. Must run BEFORE the rest of intervalDidStart
            // so subsequent midnight/shield logic sees the post-heal state.
            consumeHealRequestIfPresent(defaults: defaults)
            processHealBatchIfNeeded(defaults: defaults)

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
                    let extDate = defaults.string(forKey: "ext_usage_\(diagAppID)_date") ?? "nil"
                    let lastThresh = defaults.integer(forKey: "usage_\(diagAppID)_lastThreshold")
                    let usageToday = defaults.integer(forKey: "usage_\(diagAppID)_today")
                    midnightDiagnosticLog("  APP_STATE \(diagAppID.prefix(8))... ext_date=\(extDate) lastThresh=\(lastThresh)s usage_today=\(usageToday)s", defaults: defaults)
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
                let rebuildSuccess = extensionRebuildSlidingWindow(defaults: defaults, triggerAppID: nil, reason: "midnight-ext-rebuild")
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
            extensionRebuildSlidingWindow(defaults: defaults, triggerAppID: appID, reason: "mapping-recovered")
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

        // Shadow burst-judge tracker — captures per-burst data for the proposed
        // "trust max threshold on legit catch-up" rule. No credit-behavior changes;
        // observation only. Logs SHADOW_BURST_JUDGE at burst close.
        // See SMART_THRESHOLD_FILTERING.md "May 17 — Burst Quarantine-and-Judge".
        shadowBurstTrack(
            appID: appID,
            thresholdSeconds: thresholdSeconds,
            nowTimestamp: Date().timeIntervalSince1970,
            defaults: defaults
        )

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

        // APPROACHING LIMIT NOTIFICATION: Fire when reward app hits 80% of daily limit
        checkAndNotifyApproachingLimit(appID: appID, usageSeconds: newToday, configs: shieldConfigs, defaults: defaults)

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


    /// Record +60s per valid event with robust filter chain.
    ///
    /// ARCHITECTURE (migration in progress — see docs/THREE_PHASE_RECORDING_ARCHITECTURE.md):
    ///
    ///   PHASE A — Hard rejects (no burst context required)
    ///     SKIP_MIDNIGHT, SKIP_INVALID, SKIP_STALE_FLUSH, SKIP_PIN_REPLAY,
    ///     SKIP_SHIELDED, SKIP_REGRESSION
    ///
    ///   LEGACY filters (to be removed after Phase B+C land)
    ///     SKIP_FLOOD, FIRST_EVENT_BUFFER, PHANTOM_FLOOD_DETECTED trigger,
    ///     SKIP_BURST_BUDGET, isMidDayBurst per-event-cap branching
    ///
    ///   PHASE B — Classify isolated vs burst (to be added)
    ///   PHASE C — Route (isolated → credit; burst → buffer + settle)
    ///
    /// Current code reflects the pre-migration filter chain. Section markers
    /// below identify which existing filters belong to which phase, but no
    /// code has been moved yet.
    private nonisolated func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults, shieldConfigs: ExtensionShieldConfigsMinimal?) -> Bool {
        let thresholdSeconds = thresholdSeconds
        // Flag set inside Filter 2.7 BUFFER_LEGIT branch so the recording code at
        // the end of the function knows to treat this event as a stale-catch-up:
        // the marker (`lastThreshold`) must be set to `newToday`, NOT to
        // `thresholdSeconds`, because BUFFER_LEGIT only credits 60s but iOS's
        // threshold can be much higher (e.g., 180s for min.3). Without this flag,
        // the marker gets set to thresholdSeconds and blocks every legit
        // per-minute event for the rest of the day (May 11 FAE1D45B incident).
        var fromBufferLegit = false
        let now = Date()
        let nowTimestamp = now.timeIntervalSince1970
        let midnightDiagActive = defaults.bool(forKey: "midnight_diagnostic_active")

        // ═══════════ FILTER CHAIN — applied to ALL events before any recording ═══════════
        // Compute calendar values once for use in both filters and recording
        let calendar = Self.calendar
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ DAY ROLLOVER — runs once on the first event of a new day        │
        // │ Resets usage_<id>_today, lastThreshold, hourly buckets, and     │
        // │ captures yesterday's pending archive. Without this, the new     │
        // │ architecture's early-return bypassed the legacy NEW_DAY branch  │
        // │ and yesterday's lastThreshold persisted into today, poisoning   │
        // │ today's SKIP_REGRESSION decisions.                              │
        // └─────────────────────────────────────────────────────────────────┘
        let globalResetKey = "global_daily_reset_timestamp"
        let lastGlobalReset = defaults.double(forKey: globalResetKey)
        if lastGlobalReset < startOfToday {
            debugLog("DAY_ROLLOVER triggeredBy=\(appID.prefix(8))... — running resetAllDailyCounters and clearing lastThresholds + burst state", defaults: defaults)
            Self.logger.notice("DAY_ROLLOVER triggeredBy=\(appID.prefix(8))...")
            resetAllDailyCounters(defaults: defaults, startOfToday: startOfToday)
            defaults.set(startOfToday, forKey: globalResetKey)
            // Clear the burst window state — yesterday's pending burst (if any)
            // is no longer relevant to today.
            clearBurstState(defaults: defaults)
            defaults.removeObject(forKey: "last_event_arrival_global")
            notifyMainApp()
        }

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ PHASE B — Burst window maintenance (predecessor check)          │
        // │ Gap from last event arrival decides whether we're inside the    │
        // │ current burst window or starting fresh. Done early so Phase A's │
        // │ SKIP_SHIELDED branch can use the burst state to detect floods.  │
        // └─────────────────────────────────────────────────────────────────┘
        let lastEventArrivalGlobal = defaults.double(forKey: "last_event_arrival_global")
        let gapSinceLastEvent = lastEventArrivalGlobal > 0
            ? nowTimestamp - lastEventArrivalGlobal
            : Double.greatestFiniteMagnitude
        if gapSinceLastEvent >= Self.burstWindowSeconds {
            // Previous burst (if any) is done — credits made within it are
            // now final, undo state is no longer needed.
            clearBurstState(defaults: defaults)
        }
        defaults.set(nowTimestamp, forKey: "last_event_arrival_global")

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ PHASE A — Hard rejects (no burst context required)              │
        // │ These filters reject events on physical or logical impossibility│
        // │ regardless of whether the event is part of a burst.             │
        // └─────────────────────────────────────────────────────────────────┘

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

        // Filter 1.5: SKIP_STALE_FLUSH — physical-impossibility check.
        // A threshold event today claiming more cumulative seconds than the wall-clock
        // since midnight necessarily reflects yesterday's iOS-cumulative being flushed
        // across the day boundary. Drop it before any state mutation so neither credit
        // nor lastThreshold gets poisoned. Catches the May 9 NEW_DAY race where a stale
        // min.111 (6660s) arrived at 00:05:18 (318s after midnight) and entered the
        // NEW_DAY branch before MIDNIGHT_RESET_COMPLETE finished — see SMART_THRESHOLD_FILTERING.md
        // "May 9–10, 2026 — Three-layer phantom-flood defense".
        let wallClockSinceMidnight = max(0, Int(nowTimestamp - startOfToday))
        if thresholdSeconds > wallClockSinceMidnight + 60 {
            debugLog("SKIP_STALE_FLUSH appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s > wallClockSinceMidnight+60=\(wallClockSinceMidnight + 60)s — yesterday's queued event", defaults: defaults)
            Self.logger.notice("SKIP_STALE_FLUSH app=\(appID.prefix(8))... thresh=\(thresholdSeconds)s wallClock=\(wallClockSinceMidnight)s")
            return false
        }

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ DIAGNOSTIC — shadow trackers (no enforcement)                   │
        // │ Logging-only paths used to evaluate candidate rules before      │
        // │ promoting them to enforcement. Stays as-is across phases.       │
        // └─────────────────────────────────────────────────────────────────┘

        // Shadow tracker (May 14, 2026): restart-window per-app threshold-snapshot rule.
        // Hypothesis: when monitoring restarts, only the restart's triggering app should
        // receive events; events for other apps must either advance past the pre-restart
        // lastThreshold or be rejected as iOS replay artifacts. For 10s after every restart,
        // log what this rule WOULD reject without actually rejecting. Compare SHADOW_RESTART_REJECT
        // log volume to real BURST_BYPASS / RECORDED entries to size the protection before
        // promoting to enforcement.
        let shadowSnapTs = defaults.double(forKey: "shadow_restart_snap_timestamp")
        let shadowAge = shadowSnapTs > 0 ? nowTimestamp - shadowSnapTs : Double.greatestFiniteMagnitude
        if shadowAge < 10 {
            let shadowTriggerPrefix = defaults.string(forKey: "shadow_restart_trigger_app_prefix") ?? ""
            let shadowSnap = defaults.integer(forKey: "shadow_restart_thresh_snap_\(appID)")
            let appPrefix = String(appID.prefix(8))
            let shadowReason: String?
            if shadowTriggerPrefix.isEmpty {
                shadowReason = "no-trigger-app"
            } else if appPrefix == shadowTriggerPrefix {
                shadowReason = nil
            } else if thresholdSeconds <= shadowSnap {
                shadowReason = "stale-replay-snap=\(shadowSnap)s"
            } else {
                shadowReason = nil
            }
            if let reason = shadowReason {
                let restartReason = defaults.string(forKey: "shadow_restart_reason") ?? "?"
                debugLog("SHADOW_RESTART_REJECT appID=\(appPrefix)... thresh=\(thresholdSeconds)s reason=\(reason) triggerApp=\(shadowTriggerPrefix.isEmpty ? "none" : shadowTriggerPrefix) ageSinceRestart=\(Int(shadowAge))s restartReason=\(restartReason) — diagnostic only", defaults: defaults)
            }
        }

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ LEGACY — burst-aware filters (TO BE REMOVED)                    │
        // │ These filters do their own burst-context detection with their   │
        // │ own time windows (5s, 10s). After Phase B+C land, this whole    │
        // │ block is replaced by the burst classifier + settlement logic.   │
        // │ Kept in place during migration; do not extend.                  │
        // └─────────────────────────────────────────────────────────────────┘

        // Filter 1.7: PHANTOM_FLOOD_LOCKOUT — once a flood has been detected
        // (by Filter 2's SKIP_SHIELDED-in-burst trigger below), a global flag locks
        // out ALL events for 5 minutes. This honors the "filters are cumulative"
        // principle: even an event that would otherwise pass Layer 2 (BUFFER_LEGIT)
        // is invalid if it arrived during a flood window. The flag is set BY a
        // shielded-reward-app event firing during a burst, and READ by every event
        // here at the top of the chain.
        //
        // Design principle (May 10, 2026): every filter decision answers "is this
        // burst a flood or a legit catch-up?" The strong phantom signal is events
        // firing for currently-shielded reward apps — kids physically cannot use
        // a blocked app, so those events MUST be phantom. When that signal appears
        // in a burst (≥1 other app has had a recent event), we lock out the whole
        // burst. Bursts WITHOUT a shielded-reward-app event are trusted as legit
        // catch-up — even on iPad-9th-gen-class devices where iOS regularly dumps
        // events for multiple legitimately-used apps at once.
        //
        // Storage:
        //   last_event_arrival_<id>     — timestamp of last event arrival (any outcome)
        //   phantom_flood_active_until  — global; lockout window active when now < this
        //
        // May 17, 2026 — Two scope refinements:
        // 1. Track every event arrival (move update BEFORE the lockout check), so the
        //    burst-context check below sees accurate timing even during the lockout.
        // 2. Lockout now only rejects burst-shaped events. Single isolated events
        //    arriving at normal cadence during a lockout BYPASS — phantom floods are
        //    burst-shaped by structural definition; isolated 60s-cadence events are
        //    not phantom (Device 3 May 17: legit app EC532D21 lost 7 min of credit
        //    because SKIP_FLOOD blocked its normal-cadence events during a misfire).
        let myAppLastArrival = defaults.double(forKey: "last_event_arrival_\(appID)")
        defaults.set(nowTimestamp, forKey: "last_event_arrival_\(appID)")

        // Heal-mode bypass: when the main app's healUsageData kicked off a
        // catch-up rebuild, anti-phantom defenses (SKIP_FLOOD, SKIP_SHIELDED,
        // BURST_REVERT, PHANTOM_FLOOD_DETECTED, FIRST_EVENT_BUFFER) must not
        // fire — the catch-up is intentional and represents iOS's authoritative
        // cumulative for today. Without this bypass the heal's own burst trips
        // the shielded-in-burst defense (reward apps re-shield during heal
        // because goals become unmet at usage=0), reverts every credit, and
        // locks out subsequent events for 30s (see 2026-05-23 11:46:35 log).
        let healActiveUntil = defaults.double(forKey: "heal_active_until")
        let inHealMode = nowTimestamp < healActiveUntil

        let floodActiveUntil = defaults.double(forKey: "phantom_flood_active_until")
        if !inHealMode && floodActiveUntil > nowTimestamp {
            // Burst-context check: is this event part of a tight burst?
            // - own app: prior event within 5s (this event is a follow-up in a burst)
            // - other apps: any tracked app had an event within 5s
            // If neither, this is an isolated event and the lockout doesn't apply.
            var isInBurst = false
            if myAppLastArrival > 0 && (nowTimestamp - myAppLastArrival) <= 5 {
                isInBurst = true
            } else {
                let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
                for trackedID in trackedAppIDs where trackedID != appID {
                    let arrival = defaults.double(forKey: "last_event_arrival_\(trackedID)")
                    if arrival > 0 && (nowTimestamp - arrival) <= 5 {
                        isInBurst = true
                        break
                    }
                }
            }
            if isInBurst {
                debugLog("SKIP_FLOOD appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s — phantom flood window active for \(Int(floodActiveUntil - nowTimestamp))s more (in burst)", defaults: defaults)
                Self.logger.notice("SKIP_FLOOD app=\(appID.prefix(8))... remaining=\(Int(floodActiveUntil - nowTimestamp))s in-burst")
                return false
            }
            // else: isolated event during lockout — bypass
            debugLog("SKIP_FLOOD_BYPASS appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s — flood window active but event is isolated (not part of a burst), trusting", defaults: defaults)
        }

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ PHASE A (continued) — SKIP_SHIELDED                             │
        // │ A reward app whose shield is currently up cannot be in use.     │
        // │ This is a physical-impossibility check; no burst context        │
        // │ required for the reject decision. The PHANTOM_FLOOD_DETECTED    │
        // │ side-effect uses burst context — that piece moves into Phase C  │
        // │ settlement after migration.                                     │
        // └─────────────────────────────────────────────────────────────────┘

        // Filter 2: Shielded reward app — user can't use a blocked app, so events are phantom
        let category = defaults.string(forKey: "map_\(appID)_category") ?? "Learning"
        Self.logger.notice("FILTER2_ENTRY app=\(appID.prefix(8))... category=\(category) thresh=\(thresholdSeconds)s")
        if category == "Reward" && !inHealMode {
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

                        // Guard: if THIS app was credited earlier in the same burst,
                        // the shield was applied mid-burst (daily limit crossed).
                        // The remaining catch-up events are real pre-shield usage —
                        // don't revert and don't escalate to flood.
                        let creditedApps = readBurstCreditedApps(defaults: defaults)
                        let shieldedDuringBurst = creditedApps.contains(appID)

                        if shieldedDuringBurst {
                            debugLog("SKIP_SHIELDED_MID_BURST appID=\(appID.prefix(8))... shield applied during this burst (daily limit) — blocking event but preserving burst credits", defaults: defaults)
                            Self.logger.notice("SKIP_SHIELDED_MID_BURST app=\(appID.prefix(8))... credits preserved")
                        } else {
                            // Pre-existing shield — this burst is phantom.
                            if !creditedApps.isEmpty {
                                revertBurstCredits(reason: "shield-in-burst-\(appID.prefix(8))", defaults: defaults)
                            }

                            let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
                            var otherAppsRecent = 0
                            for trackedID in trackedAppIDs where trackedID != appID {
                                let arrival = defaults.double(forKey: "last_event_arrival_\(trackedID)")
                                if arrival > 0 && (nowTimestamp - arrival) <= 10 {
                                    otherAppsRecent += 1
                                }
                            }
                            if otherAppsRecent >= 1 {
                                defaults.set(nowTimestamp + 30, forKey: "phantom_flood_active_until")
                                for trackedID in trackedAppIDs {
                                    defaults.removeObject(forKey: "first_event_start_\(trackedID)")
                                    defaults.removeObject(forKey: "first_event_max_thresh_\(trackedID)")
                                }
                                debugLog("PHANTOM_FLOOD_DETECTED: SKIP_SHIELDED on appID=\(appID.prefix(8))... + \(otherAppsRecent) other app(s) within 10s — burst is phantom, locking out 30s, clearing all open buffers", defaults: defaults)
                                Self.logger.notice("PHANTOM_FLOOD_DETECTED via SKIP_SHIELDED otherApps=\(otherAppsRecent) lockout=30s")
                            }
                        }
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

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ PHASE A (continued) — SKIP_PIN_REPLAY                           │
        // │ Wall-clock impossibility check for newly-pinned apps.           │
        // └─────────────────────────────────────────────────────────────────┘

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

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ LEGACY — FIRST_EVENT_BUFFER (TO BE REMOVED)                     │
        // │ First-event-of-day burst gate with 5s burst window and 60s hold.│
        // │ Replaced after migration by Phase C burst settlement, which     │
        // │ makes max-threshold-per-app a first-class concept.              │
        // └─────────────────────────────────────────────────────────────────┘

        // Filter 2.7: PER-APP MIN.1 BUFFER — first-event-of-day burst gate.
        // When an app's first event of the day is min>3, wait up to 60s for a min≤3
        // anchor. If one arrives, fast-forward to the highest threshold seen (legit
        // catchup). If not, give up the buffer and resume normal processing —
        // Filter 1.7 (burst-anchored flood detection) is responsible for rejecting
        // real phantom floods, not this buffer.
        //
        // Storage:
        //   first_event_start_<id>   — TimeInterval; when buffer opened. Cleared on
        //                              resolution (legit anchor or timeout).
        //   first_event_max_thresh_<id> — running max threshold seen during buffer.
        //
        // Note: the previously-sticky `phantom_suspect_<id>` app-day lockout was
        // removed on 2026-05-10 — it over-blocked legitimate post-restart usage
        // for the entire rest of the day. See SMART_THRESHOLD_FILTERING.md.
        let layer2_lastThreshold = defaults.integer(forKey: "usage_\(appID)_lastThreshold")
        let layer2_currentToday = defaults.integer(forKey: "usage_\(appID)_today")
        let isFirstEventOfDay = (layer2_lastThreshold == 0 && layer2_currentToday == 0)
        let firstEventStartKey = "first_event_start_\(appID)"
        let firstEventMaxThreshKey = "first_event_max_thresh_\(appID)"

        if isFirstEventOfDay {
            if thresholdSeconds <= 180 {
                // Acceptable first event (min.1, 2, or 3). If a buffer is open from
                // earlier high-min events, this is a legit catchup burst — fast-forward
                // to the highest threshold seen during the buffer (those high-min events
                // were rejected in HOLD and iOS won't redeliver them, so we credit them
                // here in one shot).
                if defaults.double(forKey: firstEventStartKey) > 0 {
                    // Anchor arrived. Credit this event at face value (60s via the
                    // recording flow below), and signal that the marker should be
                    // pinned to `newToday`, not to `thresholdSeconds` — see the
                    // `fromBufferLegit` declaration at the top of this function.
                    //
                    // The buffered HOLD events themselves are discarded (iOS will
                    // not re-deliver them; that's accepted). The point of this
                    // branch is "an anchor arrived, so credit one minute and let
                    // future events flow through normally" — not "credit the whole
                    // buffered range as legit," which is what the old fast-forward
                    // did and which caused the May 11 FAE1D45B 7-min blackout.
                    debugLog("FIRST_EVENT_BUFFER_LEGIT appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s — anchor accepted, marker will pin to newToday", defaults: defaults)
                    defaults.removeObject(forKey: firstEventStartKey)
                    defaults.removeObject(forKey: firstEventMaxThreshKey)
                    fromBufferLegit = true
                }
            } else {
                // Suspicious first event (high threshold). Either open a new buffer or
                // evaluate an existing one.
                let bufferStart = defaults.double(forKey: firstEventStartKey)
                if bufferStart == 0 {
                    // May 17, 2026 — Burst-context gate: only open buffer if this
                    // event is part of a burst. Isolated single events at normal
                    // cadence are trusted as legit catch-up (kid started using a new
                    // app; we missed earlier minutes because window wasn't registered
                    // or extension was restarted). Phantom floods always arrive as
                    // bursts, so the buffer's protection still applies in those cases.
                    //
                    // Without this gate, a kid starting a new app post-restart loses
                    // all credit until a low-min companion event arrives (which won't,
                    // because they're already past min.3 in real cumulative).
                    //
                    // 2026-05-23 heal-mode bypass: during heal, all bursts are
                    // intentional iOS catch-up — trust the high-threshold event
                    // directly instead of opening a buffer that would reject it.
                    var inBurst = false
                    let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
                    for trackedID in trackedAppIDs where trackedID != appID {
                        let arrival = defaults.double(forKey: "last_event_arrival_\(trackedID)")
                        if arrival > 0 && (nowTimestamp - arrival) <= 5 {
                            inBurst = true
                            break
                        }
                    }
                    if !inBurst || inHealMode {
                        debugLog("FIRST_EVENT_TRUST appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s — isolated event (no other apps in burst), trusting as legit catch-up", defaults: defaults)
                        Self.logger.notice("FIRST_EVENT_TRUST app=\(appID.prefix(8))... thresh=\(thresholdSeconds)s")
                        // Fall through to recording: rawDelta=60 (lastThresh=0 case)
                        // credits a conservative 60s; subsequent per-minute events
                        // credit 60s each via normal flow, gradually catching up.
                    } else {
                        // No buffer open AND in burst context. Start one. Reject this
                        // event (the high-min trigger), but remember its threshold so we
                        // can fast-forward if a low-min companion arrives.
                        defaults.set(nowTimestamp, forKey: firstEventStartKey)
                        defaults.set(thresholdSeconds, forKey: firstEventMaxThreshKey)
                        debugLog("FIRST_EVENT_BUFFER_OPEN appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s — in burst, waiting up to 60s for min≤3", defaults: defaults)
                        Self.logger.notice("FIRST_EVENT_BUFFER_OPEN app=\(appID.prefix(8))... thresh=\(thresholdSeconds)s")
                        return false
                    }
                } else {
                    let bufferAge = nowTimestamp - bufferStart
                    if bufferAge > 60 {
                        // Timeout. No min≤3 anchor in 60s — buffered events were
                        // probably phantom. Set lastThreshold to a small value (60s)
                        // so subsequent legit per-minute events flow through normally
                        // and isFirstEventOfDay no longer holds (we don't want to
                        // re-enter the buffer on the next event). Previously this
                        // anchored at maxSeen, which had the same poisoning problem
                        // as BUFFER_LEGIT — the rest of the day's tracking died
                        // when the phantom maxSeen was high.
                        defaults.removeObject(forKey: firstEventStartKey)
                        defaults.removeObject(forKey: firstEventMaxThreshKey)
                        defaults.set(60, forKey: "usage_\(appID)_lastThreshold")
                        defaults.set(startOfToday, forKey: "usage_\(appID)_reset")
                        debugLog("BUFFER_TIMEOUT_RESUME appID=\(appID.prefix(8))... no min≤3 in 60s — buffered events discarded, lastThreshold=60s so future per-minute events flow through", defaults: defaults)
                        Self.logger.notice("BUFFER_TIMEOUT_RESUME app=\(appID.prefix(8))... lastThreshold=60s")
                        return false
                    } else {
                        // Still in 60-second window. Update the running max so we can
                        // fast-forward correctly when min≤3 arrives, then reject this event.
                        let prevMax = defaults.integer(forKey: firstEventMaxThreshKey)
                        if thresholdSeconds > prevMax {
                            defaults.set(thresholdSeconds, forKey: firstEventMaxThreshKey)
                        }
                        debugLog("FIRST_EVENT_BUFFER_HOLD appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s bufferAge=\(Int(bufferAge))s maxSoFar=\(max(prevMax, thresholdSeconds))s — still waiting for min≤3", defaults: defaults)
                        return false
                    }
                }
            }
        }

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ PHASE A (continued) — SKIP_REGRESSION                           │
        // │ Threshold monotonicity. Same-day thresholds must strictly       │
        // │ increase; cross-day blocks exact duplicates only.               │
        // └─────────────────────────────────────────────────────────────────┘

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
                // Self-consistency diagnostic (no action — logging only).
                // If events arrive at clean ~60s wallclock cadence AND monotonically-
                // increasing thresholds AND all get SKIP_REGRESSION rejected, the
                // filter chain is contradicting reality: that cadence is the
                // unmistakable signature of real-time play (iOS can't fake it —
                // queue dumps arrive in milliseconds), so the rejections imply
                // marker poisoning or similar internal state corruption. Log an
                // ANOMALY line so the next bug in this class is visible
                // immediately, not discovered hours later from missing usage.
                let lastSkipKey = "skip_reg_last_arrival_\(appID)"
                let lastSkipThreshKey = "skip_reg_last_thresh_\(appID)"
                let skipCountKey = "skip_reg_consecutive_\(appID)"
                let lastSkipArrival = defaults.double(forKey: lastSkipKey)
                let lastSkipThresh = defaults.integer(forKey: lastSkipThreshKey)
                let wallGap = lastSkipArrival > 0 ? nowTimestamp - lastSkipArrival : 0
                let threshDelta = thresholdSeconds - lastSkipThresh
                let isCleanCadence = lastSkipArrival > 0 && wallGap >= 50 && wallGap <= 90 &&
                                     threshDelta >= 50 && threshDelta <= 150
                if isCleanCadence {
                    let newCount = defaults.integer(forKey: skipCountKey) + 1
                    if newCount == 3 {
                        debugLog("ANOMALY appID=\(appID.prefix(8))... 3 clean per-minute events rejected (wallGap=\(Int(wallGap))s threshΔ=\(threshDelta)s today=\(defaults.integer(forKey: "usage_\(appID)_today"))s marker=\(lastThreshold)s) — filter chain may be contradicting real-time play; investigate marker poisoning", defaults: defaults)
                        Self.logger.notice("ANOMALY app=\(appID.prefix(8))... clean cadence rejected, marker=\(lastThreshold)s")
                    }
                    defaults.set(nowTimestamp, forKey: lastSkipKey)
                    defaults.set(thresholdSeconds, forKey: lastSkipThreshKey)
                    defaults.set(newCount, forKey: skipCountKey)
                } else {
                    defaults.set(nowTimestamp, forKey: lastSkipKey)
                    defaults.set(thresholdSeconds, forKey: lastSkipThreshKey)
                    defaults.set(1, forKey: skipCountKey)
                }
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

        // ═══════════ PASSED ALL FILTERS — credit on arrival ═══════════

        // ┌─────────────────────────────────────────────────────────────────┐
        // │ PHASE C — Credit on arrival (no buffer)                         │
        // │                                                                 │
        // │ Phase B already updated the burst window state at the top of    │
        // │ this function. SKIP_SHIELDED in Phase A already reverted any    │
        // │ in-progress burst credits if a shielded reward app fired in     │
        // │ the burst window. Here we just apply the credit (SET to max     │
        // │ threshold) and save the per-app revert info in case a later     │
        // │ event in the same burst triggers a flood revert.                │
        // │                                                                 │
        // │ See docs/THREE_PHASE_RECORDING_ARCHITECTURE.md (v4).             │
        // │                                                                 │
        // │ The legacy recording code below is unreachable — left in place  │
        // │ for the migration window; will be removed once stable.          │
        // └─────────────────────────────────────────────────────────────────┘
        let credited = processEventAndCredit(
            appID: appID,
            thresholdSeconds: thresholdSeconds,
            now: nowTimestamp,
            defaults: defaults
        )
        return credited

        // ─── LEGACY recording path (UNREACHABLE — kept for migration window) ───

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

            // First event of the day credits cumulative usage equal to thresholdSeconds.
            // (For min.1 first events thresholdSeconds == 60. For Layer 2 fast-forward
            // acceptance — when a buffered burst of high-min events is resolved by min≤3 —
            // thresholdSeconds is overridden to the max threshold seen during the buffer,
            // so this records the full 10-min-or-whatever burst in one shot.)
            let initialUsage = thresholdSeconds
            debugLog("NEW_DAY appID=\(appID.prefix(8))... initialUsage=\(initialUsage)s thresh=\(thresholdSeconds)s", defaults: defaults)
            if midnightDiagActive { midnightDiagnosticLog("DIAG_NEW_DAY appID=\(appID.prefix(8))... initial=\(initialUsage)s thresh=\(thresholdSeconds)s", defaults: defaults) }
            Self.logger.notice("NEW_DAY app=\(appID.prefix(8))... initial=\(initialUsage)s thresh=\(thresholdSeconds)s")
            defaults.set(initialUsage, forKey: todayKey)
            defaults.set(startOfToday, forKey: todayResetKey)
            defaults.set(initialUsage, forKey: totalKey)
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
            defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

            // ext_ keys (today's seconds canonical lives in `usage_<id>_today` above —
            // ext_usage_<id>_today is no longer written. Step 3 of the unified-counter
            // refactor: see docs/UNIFIED_USAGE_COUNTER_PLAN.md.)
            debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... NEW_DAY today=\(initialUsage) total=\(initialUsage) date=\(dateString) hour=\(hour)", defaults: defaults)
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

            // Note: WINDOW_TOP_HIT rebuild trigger already fired at the top of this
            // function (pre-filter) — no duplicate check needed here.
            return true
        }

        // Per-event cap: governs how much credit a single threshold event can post.
        // Branches:
        //   - in-burst (catch-up dump or buffered Layer 2 burst) → Int.max, trust iOS
        //   - first-event-after-unlock → wall-clock since unlock (bounded by elapsed)
        //   - normal delivery → Int.max, trust threshold value, SKIP_BURST_BUDGET
        //     downstream bounds against wall-clock since last alive event
        //
        // The normal-delivery branch used to be a hard 60s cap. That rule threw away
        // recoverable credit any time iOS fired a threshold that advanced past our
        // recorded today (false rejects, extension kills, deferred batch flushes
        // — May 17 Device 2: Roblox today stuck at 120 min while iOS internally
        // tracked 145+ min). Trusting the threshold value in normal mode lets the
        // very next legit event close any gap automatically; SKIP_BURST_BUDGET
        // (now with jitter grace) catches single phantoms with inflated thresholds.
        //
        // Defense in depth (kept unchanged):
        //   - SKIP_MIDNIGHT (Filter 0) — blocks cross-day stale flushes.
        //   - SKIP_REGRESSION — blocks duplicates and out-of-order regressions.
        //   - lastThreshold high-water-mark anchor (May 1) — flood can't poison
        //     subsequent SKIP_REGRESSION decisions.
        //   - SKIP_BURST_BUDGET — bounds credit against wall-clock since last alive.
        let currentToday = defaults.integer(forKey: todayKey)
        let lastEventTime = defaults.double(forKey: "ext_usage_\(appID)_timestamp")
        let unlockTime = defaults.double(forKey: "ext_unlock_\(appID)_timestamp")
        let rawDelta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60

        let isFirstEventAfterUnlock = (unlockTime > lastEventTime) && (unlockTime > 0)
        // Burst-window bypass: when Layer 2 just accepted a buffered burst as legit, all
        // events that follow within 10s are out-of-order catch-up events from the same
        // iOS dump. Their deltas can legitimately exceed 60s (e.g., iOS dumps min.3 and
        // min.11 within 1s of each other). PER_EVENT_CAP would cap each at 60s and most
        // of the credit would be lost. Bypass the cap during this window so the full
        // delta lands. SKIP_REGRESSION still protects against duplicate events.
        //
        // 277a540 (full-credit on first event of buffered burst) was REVERTED May 11.
        // It helped the legit YouTube catch-up case (where shielded apps had 0
        // thresholds), but with the 5-threshold shielded sentinel now in place,
        // that case no longer happens — events fire per-minute from the moment of
        // unshield. Meanwhile the full-credit fix amplified phantom-burst inflation
        // by 20× (1 min phantom would become 20 min phantom). Conservative 60s
        // default for first-event-of-day restored.
        let burstActiveUntil = defaults.double(forKey: "burst_active_until_\(appID)")
        let isBurstActive = burstActiveUntil > nowTimestamp
        // Mid-day burst detection: iPad 9th-gen-class devices frequently go silent
        // mid-day, then iOS dumps a backlog of catch-up events at well-below-cadence
        // gaps. Layer 2's first-of-day buffer doesn't fire on these (because today>0
        // and lastThreshold>0). Detect via timing across ALL apps: if any monitored
        // app fired a credited event within the burst window, this event is part of
        // the same iOS flush. Bypass PER_EVENT_CAP so legit catch-up minutes aren't
        // capped at 60s each. SKIP_REGRESSION still blocks duplicates and out-of-order
        // regressions, and SKIP_BURST_BUDGET below bounds aggregate burst credit by
        // wall-clock since the burst began.
        //
        // BURST WINDOW = 30s (was 5s).
        // Normal per-minute recording fires at ~60s cadence. Events arriving at
        // 6s/10s/20s/30s gaps are NOT normal — they're catch-ups or phantoms. The
        // 5s window only caught tight iOS-flush batches and let through cascades
        // spread over a few seconds per event. 30s gives a comfortable margin
        // below the 60s normal cadence; legit cross-app events still arrive
        // >30s apart in practice (kid foregrounds one app at a time, and only
        // the foregrounded app accumulates threshold seconds).
        //
        // May 18, 2026 — CROSS-APP burst window (was same-app).
        // Device C (May 18 morning) hit a multi-app phantom flood during an
        // extension-kill cascade: 5 EXTENSION_KILLED in 25 seconds, iOS dumped
        // phantom events across 16 apps. Each app's own previous event was >5s ago,
        // but cross-app the events were 1-3s apart — clearly one iOS flush.
        // Using the global `last_credited_global_timestamp` catches this.
        let burstWindowSeconds: TimeInterval = 30
        let lastCreditedGlobal = defaults.double(forKey: "last_credited_global_timestamp")
        let isMidDayBurst = lastCreditedGlobal > 0 && (nowTimestamp - lastCreditedGlobal) < burstWindowSeconds
        let perEventCap: Int
        if isBurstActive || isMidDayBurst {
            perEventCap = Int.max
        } else if isFirstEventAfterUnlock {
            perEventCap = max(60, Int(nowTimestamp - unlockTime))
        } else {
            // NORMAL ISOLATED EVENT: trust the iOS threshold value.
            // No burst context (no app — including this one — fired within 5s
            // globally) and not the first event after an unshield. This is an
            // isolated event in the normal per-minute recording cadence, where
            // iOS's reported threshold reflects actual cumulative usage.
            //
            // The cross-app `isMidDayBurst` check above catches phantom-flood
            // cascades (multiple apps firing in quick succession after an
            // extension kill). Solo phantom events outside any burst window
            // have not historically been a problem in our logs.
            perEventCap = Int.max
        }
        let delta = max(0, min(rawDelta, perEventCap))
        if delta < rawDelta {
            let unlockAge = unlockTime > 0 ? Int(nowTimestamp - unlockTime) : -1
            debugLog("PER_EVENT_CAP appID=\(appID.prefix(8))... raw=\(rawDelta)s capped=\(delta)s perEvent=\(perEventCap)s unlockAge=\(unlockAge)s \(batteryContextString(defaults: defaults))", defaults: defaults)
        } else if rawDelta > 60 {
            let reason: String
            if isBurstActive { reason = "buffer-legit" }
            else if isMidDayBurst { reason = "mid-day-burst" }
            else { reason = "normal-recovery" }
            debugLog("BURST_BYPASS appID=\(appID.prefix(8))... raw=\(rawDelta)s credited=\(delta)s — \(reason), full delta", defaults: defaults)
        }

        // Layer 3: POST-UNSHIELD BUDGET — physical-impossibility on aggregate usage.
        // Total credited usage across all monitored apps since the last shield drop
        // cannot exceed wall-clock seconds since that shield drop (kid has one set of
        // hands, can foreground only one app at a time). Catches continuation phantom
        // on apps with prior real usage today (e.g., AbacusFlashMath afternoon
        // contamination) which Layer 2 cannot see because lastThreshold > 0.
        // See SMART_THRESHOLD_FILTERING.md "May 9–10, 2026".
        //
        // SCOPE (May 12, 2026): Reward apps only. The unshield timestamp is a
        // reward-app-only concept — it marks when a reward app's shield dropped.
        // Learning apps are never gated, so "wallclock since unshield" has no
        // semantic relationship to a learning-app catch-up burst. Applying the
        // budget to learning apps caused the May 12 Facebook incident: legit
        // 5-min catch-up burst rejected because Instagram's 10 min of credit
        // had already filled the budget (and Facebook had usageAtUnshield=0
        // so the burst-continuation exemption didn't fire). Learning-app
        // phantom-flood is still covered by Layer 1 (burst-anchored flood
        // detection) and Layer 2 (first-event-of-day buffer) — their reference
        // frames (burst window, first-event-of-day) apply correctly to
        // learning apps.
        let rewardAppIDs = Set(shieldConfigs?.goalConfigs.map { $0.rewardAppLogicalID } ?? [])
        let isRewardApp = rewardAppIDs.contains(appID)
        let lastUnshield = defaults.double(forKey: "last_unshield_timestamp")
        if isRewardApp, lastUnshield > 0, lastUnshield <= nowTimestamp {
            let wallClockSinceUnshield = max(0, Int(nowTimestamp - lastUnshield))
            // Burst-continuation exemption: when an unshield was just triggered by a
            // Layer 2 fast-forward credit, iOS may still be flushing the rest of the
            // same pre-unshield burst (out-of-order catch-up delivery). If the current
            // event's app already had usage at the unshield snapshot AND the unshield
            // happened within the last 60 s, the event is almost certainly a tail of
            // that legit burst, not new post-unshield activity. Don't block it.
            // Continuation phantom hours later (AFM-style) still hits the budget check
            // because wallClockSinceUnshield > 60s.
            let usageAtUnshieldForThisApp = defaults.integer(forKey: "usage_\(appID)_at_unshield")
            let isBurstContinuation = usageAtUnshieldForThisApp > 0 && wallClockSinceUnshield <= 60
            if isBurstContinuation {
                debugLog("BUDGET_EXEMPT_BURST appID=\(appID.prefix(8))... at_unshield=\(usageAtUnshieldForThisApp)s sinceUnshield=\(wallClockSinceUnshield)s — pre-unshield burst tail", defaults: defaults)
            } else {
                let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
                var totalPostUnshieldCredit = 0
                for trackedID in trackedAppIDs {
                    let usageNow = defaults.integer(forKey: "usage_\(trackedID)_today")
                    let usageAtUnshield = defaults.integer(forKey: "usage_\(trackedID)_at_unshield")
                    totalPostUnshieldCredit += max(0, usageNow - usageAtUnshield)
                }
                // 10 % grace accommodates iOS background-counting jitter (Device 1
                // observed ~3 % overshoot — 111 min credit vs 108 min wall-clock for a
                // genuinely heavy session).
                let grace = wallClockSinceUnshield / 10
                let proposedTotal = totalPostUnshieldCredit + delta
                if proposedTotal > wallClockSinceUnshield + grace {
                    debugLog("SKIP_BUDGET_EXCEEDED appID=\(appID.prefix(8))... totalPost=\(totalPostUnshieldCredit)s + delta=\(delta)s = \(proposedTotal)s > wallClockSinceUnshield=\(wallClockSinceUnshield)s + grace=\(grace)s — phantom contamination", defaults: defaults)
                    Self.logger.notice("SKIP_BUDGET_EXCEEDED app=\(appID.prefix(8))... proposed=\(proposedTotal)s budget=\(wallClockSinceUnshield + grace)s")
                    return false
                }
            }
        }

        // Cross-burst budget filter (phantom-flood enforcement). Tracks aggregate
        // credits during a catch-up burst vs wallclock since the last "alive" event
        // (any app). The kid can only use one app at a time, so total credits in a
        // burst cannot exceed wallclock seconds since monitoring was last firing
        // real-time events. A new burst starts on a wallclock gap ≥ `burstWindowSeconds`
        // (30s); events within the burst window share the same budget. Aligned with
        // `isMidDayBurst` above so burst classification and budget reset agree.
        //
        // May 17, 2026 — Scope narrowed to **bursts only** (`isMidDayBurst` true).
        // The previous "apply to every event" implementation broke normal
        // single-event recording: when iOS fires min.236 in normal cadence after
        // a 14-min gap, the implied credit (24 min) exceeded the wall-clock
        // budget (14 min), causing rejection. Every subsequent normal event hit
        // the same reject (Device 2 May 17: 59 min lost in a stuck loop).
        //
        // The right scope: phantom floods ARE bursts by structural definition
        // (many events in <5s). Single isolated events have never been a
        // phantom source in our logs. So gate the rejection on isMidDayBurst —
        // the first event of any potential burst (gap >5s from previous) always
        // passes; subsequent events within 5s of each other share the accumulated
        // budget. State (burst budget / credited) is tracked on every event so
        // the second-event-onward check has the right reference.
        //
        // Jitter grace (max 5s, 10% of budget) preserved from the May 17 earlier
        // fix — absorbs sub-5s scheduling jitter inside bursts.
        let lastAliveKey = "last_credited_global_timestamp"
        let burstBudgetKey = "burst_budget_seconds"
        let burstCreditedKey = "burst_credited_seconds"
        let lastAlive = defaults.double(forKey: lastAliveKey)
        let gapSinceAlive = lastAlive > 0 ? nowTimestamp - lastAlive : 0
        let isNewBurst = gapSinceAlive >= burstWindowSeconds
        var burstBudget = defaults.integer(forKey: burstBudgetKey)
        var burstCredited = defaults.integer(forKey: burstCreditedKey)
        if isNewBurst {
            burstBudget = Int(gapSinceAlive)
            burstCredited = 0
        }
        let proposedCredited = burstCredited + delta
        let jitterGrace = max(5, burstBudget / 10)
        if isMidDayBurst && lastAlive > 0 && proposedCredited > burstBudget + jitterGrace {
            debugLog("SKIP_BURST_BUDGET appID=\(appID.prefix(8))... burstCredited=\(burstCredited)s + delta=\(delta)s = \(proposedCredited)s > budget=\(burstBudget)s + grace=\(jitterGrace)s (wallclock since last alive event) — phantom-flood reject", defaults: defaults)
            Self.logger.notice("SKIP_BURST_BUDGET app=\(appID.prefix(8))... proposed=\(proposedCredited)s budget=\(burstBudget)s grace=\(jitterGrace)s")
            // Don't update burstCredited/lastAlive — rejecting this event means it
            // never happened from the budget's perspective. The burst budget keeps
            // its current value so subsequent events in the same burst are still
            // compared against the original wallclock window.
            defaults.set(burstBudget, forKey: burstBudgetKey)
            return false
        }
        defaults.set(proposedCredited, forKey: burstCreditedKey)
        defaults.set(burstBudget, forKey: burstBudgetKey)
        defaults.set(nowTimestamp, forKey: lastAliveKey)

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
        if wasStaleCatchup || fromBufferLegit {
            // Pin marker to `newToday` (the actual credited high-water mark) instead
            // of `thresholdSeconds` (iOS's claimed cumulative, which may be way
            // ahead of what we credited). Two paths into this branch:
            //   1. wasStaleCatchup — Apr 30 detection: rawDelta > perEventCap, i.e.,
            //      iOS jumped further than real time can justify in one event.
            //   2. fromBufferLegit — Filter 2.7 just credited an anchor that
            //      followed a high-min burst. We credited 60s but the anchor's
            //      threshold could be much higher; pinning to newToday prevents
            //      the marker from blocking real per-minute play later in the day.
            let newLastThreshold = max(lastThreshold, newToday)
            let reason = fromBufferLegit ? "buffer-legit anchor" : "stale catch-up"
            debugLog("LASTTHRESH_HOLD appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s held lastThresh=\(newLastThreshold)s (was \(lastThreshold)s) — \(reason) (raw=\(rawDelta)s perEventCap=\(perEventCap)s credited=\(delta)s)", defaults: defaults)
            defaults.set(newLastThreshold, forKey: lastThresholdKey)
        } else {
            defaults.set(thresholdSeconds, forKey: lastThresholdKey)
        }

        // Update total
        let currentTotal = defaults.integer(forKey: totalKey)
        defaults.set(currentTotal + delta, forKey: totalKey)
        defaults.set(nowTimestamp, forKey: "usage_\(appID)_modified")

        // ext_ keys (today's seconds canonical lives in `usage_<id>_today` above —
        // ext_usage_<id>_today is no longer written. Step 3 of the unified-counter
        // refactor: see docs/UNIFIED_USAGE_COUNTER_PLAN.md.)
        let currentExtTotal = defaults.integer(forKey: "ext_usage_\(appID)_total")

        debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... INCREMENT today=\(newToday) total=\(currentExtTotal + delta) hour=\(hour)", defaults: defaults)
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
        // Sliding-window rebuild trigger — fires when the kid's RECORDED cumulative
        // approaches the top of the registered window. State-based (not event-based)
        // so iOS catch-up bursts after MONITORING_START don't trigger spurious
        // rebuilds. 60-second debounce per app prevents cascade rebuilds when a
        // burst of catch-ups arrives in rapid succession (May 10: a single restart
        // caused 4 rebuilds in 28s, crediting 18 min in that window).
        let recordedTodayMin = defaults.integer(forKey: "usage_\(appID)_today") / 60
        let windowTopMin = defaults.integer(forKey: "window_top_min_\(appID)")
        if windowTopMin > 0 && recordedTodayMin >= windowTopMin - 5 {
            let rebuildRequestKey = "window_rebuild_request_\(appID)"
            let lastRequest = defaults.double(forKey: rebuildRequestKey)
            let elapsed = nowTimestamp - lastRequest
            if elapsed > 60 {
                defaults.set(nowTimestamp, forKey: rebuildRequestKey)
                debugLog("WINDOW_TOP_HIT appID=\(appID.prefix(8))... today=\(recordedTodayMin)min top=\(windowTopMin) → request main-app rebuild + ext fast-path", defaults: defaults)
                requestMainAppWindowRebuild(reason: "window-top-\(appID.prefix(8))", defaults: defaults)
                extensionRebuildSlidingWindow(defaults: defaults, triggerAppID: appID, reason: "window-top-\(appID.prefix(8))")
            } else {
                debugLog("WINDOW_TOP_HIT_DEBOUNCED appID=\(appID.prefix(8))... today=\(recordedTodayMin)min top=\(windowTopMin) — rebuild requested \(Int(elapsed))s ago", defaults: defaults)
            }
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
        let healActiveUntil = defaults.double(forKey: "heal_active_until")
        if Date().timeIntervalSince1970 < healActiveUntil {
            debugLog("WINDOW_REBUILD_SUPPRESSED reason=\(reason) — heal active, extension handles rebuilds", defaults: defaults)
            return
        }
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
    private nonisolated func extensionRebuildSlidingWindow(defaults: UserDefaults, triggerAppID: String? = nil, reason: String = "extension-fast-path") -> Bool {
        guard let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids"),
              !trackedAppIDs.isEmpty else {
            debugLog("EXT_REBUILD_SKIP — no tracked_app_ids", defaults: defaults)
            return false
        }

        let todayDateString = Self.dayDateFormatter.string(from: Date())
        let now = Date().timeIntervalSince1970

        // Shadow snapshot (May 14, 2026): capture pre-rebuild lastThreshold per app +
        // triggering app prefix. shouldRecordEvent() consults this for 10s post-restart
        // to log SHADOW_RESTART_REJECT for events that the per-app filter rule would
        // reject. Diagnostic-only — no enforcement.
        let triggerPrefix = triggerAppID.map { String($0.prefix(8)) } ?? ""
        defaults.set(reason, forKey: "shadow_restart_reason")
        defaults.set(triggerPrefix, forKey: "shadow_restart_trigger_app_prefix")
        defaults.set(now, forKey: "shadow_restart_snap_timestamp")
        for trackedID in trackedAppIDs {
            let snap = defaults.integer(forKey: "usage_\(trackedID)_lastThreshold")
            defaults.set(snap, forKey: "shadow_restart_thresh_snap_\(trackedID)")
        }

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

            // Compute current usage for this app (today only). Reads canonical
            // `usage_<id>_today`; freshness gated by `ext_usage_<id>_date` matching today.
            let extDate = defaults.string(forKey: "ext_usage_\(logicalID)_date")
            let todaySeconds = (extDate == todayDateString)
                ? defaults.integer(forKey: "usage_\(logicalID)_today")
                : 0
            let currentMin = todaySeconds / 60

            let category = defaults.string(forKey: "map_\(logicalID)_category") ?? "Learning"

            // Right-sized window per app. Main-app `scheduleActivity()` writes
            // `window_size_<id>` from its `windowSize(for:category:isShielded:)`:
            //   • 0 → app is shielded or disallowed today; do NOT register thresholds.
            //   • >0 → use that value as-is (no min/max — caller already capped).
            // Missing key (older build / never written) → default 60 for safety.
            let storedWindowSize = defaults.integer(forKey: "window_size_\(logicalID)")
            if defaults.object(forKey: "window_size_\(logicalID)") != nil && storedWindowSize <= 0 {
                continue   // explicit 0 from main app — skip this app entirely
            }
            let appWindow = storedWindowSize > 0 ? storedWindowSize : 60
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
                // Capture yesterday's value into a pending-archive key BEFORE the wipe.
                // Main app's drainPendingArchives() picks this up on next foreground —
                // without it, devices where the main app was closed at midnight lose
                // yesterday's per-app totals entirely (no dailyHistory entry).
                let yesterdaySeconds = defaults.integer(forKey: todayKey)
                let yesterdayDate = defaults.string(forKey: "ext_usage_\(appID)_date")
                if yesterdaySeconds > 0, let dateString = yesterdayDate {
                    defaults.set(yesterdaySeconds, forKey: "pending_archive_\(appID)_seconds")
                    defaults.set(dateString, forKey: "pending_archive_\(appID)_date")
                    debugLog("PENDING_ARCHIVE appID=\(appID.prefix(8))... seconds=\(yesterdaySeconds) date=\(dateString)", defaults: defaults)
                }

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

                // Reset hourly buckets
                for h in 0..<24 {
                    defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
                }
                defaults.removeObject(forKey: "ext_usage_\(appID)_hourly_date")

                // Clear newly-added pin anchor at midnight: a "newly added" app from
                // yesterday is treated as already-known today (cumulative=0 anyway).
                defaults.removeObject(forKey: "app_first_seen_today_\(appID)")

                // Three-layer phantom-flood defense state (May 9–10, 2026):
                //   • phantom_suspect_<id>          — sticky reject-all flag, must clear at midnight
                //   • first_event_start_<id>        — Layer 2 buffer-open timestamp
                //   • first_event_max_thresh_<id>   — Layer 2 max threshold seen during buffer
                //   • burst_active_until_<id>       — Layer 2 burst-window for PER_EVENT_CAP bypass
                //   • shadow_restart_thresh_snap_<id> — restart-window shadow snapshot
                //   • last_event_arrival_<id>       — Filter 1.7 flood detector arrival timestamp
                //   • usage_<id>_at_unshield        — Layer 3 budget snapshot
                defaults.removeObject(forKey: "phantom_suspect_\(appID)")
                defaults.removeObject(forKey: "first_event_start_\(appID)")
                defaults.removeObject(forKey: "first_event_max_thresh_\(appID)")
                defaults.removeObject(forKey: "burst_active_until_\(appID)")
                defaults.removeObject(forKey: "shadow_restart_thresh_snap_\(appID)")
                defaults.removeObject(forKey: "last_event_arrival_\(appID)")
                defaults.removeObject(forKey: "usage_\(appID)_at_unshield")
                defaults.removeObject(forKey: "phantom_recovery_last_arrival_\(appID)")
                defaults.removeObject(forKey: "phantom_recovery_last_thresh_\(appID)")
                defaults.removeObject(forKey: "phantom_recovery_count_\(appID)")
                defaults.removeObject(forKey: "window_rebuild_request_\(appID)")
                defaults.removeObject(forKey: "skip_reg_last_arrival_\(appID)")
                defaults.removeObject(forKey: "skip_reg_last_thresh_\(appID)")
                defaults.removeObject(forKey: "skip_reg_consecutive_\(appID)")
            }
        }

        // Clear yesterday's pinned-apps set so today starts fresh
        defaults.removeObject(forKey: "pinned_apps_today")
        defaults.removeObject(forKey: "pinned_apps_today_date")

        // Clear shield check flag so it re-evaluates after next restart
        defaults.removeObject(forKey: "ext_shield_check_after_restart")

        // Clear unshield anchor — fresh day starts with no active unshield window.
        defaults.removeObject(forKey: "last_unshield_timestamp")

        // Clear phantom-flood global flag so a flood window doesn't persist across midnight.
        defaults.removeObject(forKey: "phantom_flood_active_until")
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
        let historicalForLog = defaults.integer(forKey: "bank_historical_remaining_minutes")
        debugLog("SHIELD_CHECK: pool=\(pool)min historical=\(historicalForLog)min across \(configs.goalConfigs.count) goal configs", defaults: defaults)

        // Pool empty → nothing to unshield this pass. checkAndBlockIfRewardTimeExhausted
        // will (re-)apply shields if needed.
        guard pool > 0 else {
            debugLog("SHIELD_CHECK: pool empty, no unshield", defaults: defaults)
            return
        }

        let rewardAppIDs = Set(configs.goalConfigs.map { $0.rewardAppLogicalID })
        var anyShieldDropped = false

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
                anyShieldDropped = true
                debugLog("SHIELD_CHECK: ✅ REMOVED shield for \(shortID) (goalMet, pool=\(pool)min)", defaults: defaults)

                // May 25, 2026 — tiered windows: keep sentinel (5) on shield drop.
                // The extension promotes to 30 when the child starts using the app,
                // and to 90 when usage reaches 25 min. This keeps total threshold
                // count low (155 at unshield vs 1,260 with the old instant-90 approach)
                // and only allocates full windows to apps the child actually plays.
                // Replaces May 16 instant-90 upgrade that overloaded iOS threshold
                // delivery with 13+ apps × 90 thresholds at once.

                // Layer 3 anchor: track unshield-window for the post-unshield budget filter.
                // Snapshot all monitored apps' usage_<id>_today at this moment. If we're
                // already in an active unshield window (last_unshield_timestamp is recent),
                // don't reset — this is a continuation of the same window. A fresh window
                // is detected by ≥ 60s gap since the prior unshield event (which implies
                // a re-shield happened in between).
                let now = Date().timeIntervalSince1970
                let lastUnshieldStamp = defaults.double(forKey: "last_unshield_timestamp")
                if lastUnshieldStamp == 0 || (now - lastUnshieldStamp) > 60 {
                    defaults.set(now, forKey: "last_unshield_timestamp")
                    let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
                    for trackedID in trackedAppIDs {
                        let usageNow = defaults.integer(forKey: "usage_\(trackedID)_today")
                        defaults.set(usageNow, forKey: "usage_\(trackedID)_at_unshield")
                    }
                    debugLog("UNSHIELD_ANCHOR_SET timestamp=\(Int(now)) snapshotted=\(trackedAppIDs.count) apps", defaults: defaults)
                }

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

        // (Shield-drop rebuild trigger removed — May 10 cascade rollback. Was causing
        // a runaway loop with iOS dumping queued events on each rebuild. The 45-min
        // BG task will catch unshielded apps eventually. _ = anyShieldDropped silences
        // the unused-warning while we keep the bookkeeping in place for the next
        // attempt with proper debouncing.)
        _ = anyShieldDropped
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
        // 1-second trigger instead of nil. DeviceActivityMonitor extensions are
        // ephemeral — the process terminates synchronously after the callback
        // returns. `add(request)` is asynchronous; with trigger:nil iOS may not
        // commit the notification to the delivery queue before the process dies,
        // and the notification is silently dropped (May 11 confirmed: completion
        // logged ✅ Scheduled but the banner never appeared until main app launch
        // triggered the catch-up path). A 1-second TimeInterval trigger forces
        // iOS to persist the request to its scheduler before the process exits,
        // and the user-visible delay is imperceptible.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
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

    // MARK: - Approaching Limit Notification

    private nonisolated func checkAndNotifyApproachingLimit(
        appID: String,
        usageSeconds: Int,
        configs: ExtensionShieldConfigsMinimal?,
        defaults: UserDefaults
    ) {
        guard let configs = configs else { return }

        guard let goalConfig = configs.goalConfigs.first(where: { $0.rewardAppLogicalID == appID }) else {
            return
        }

        let dailyLimit = goalConfig.todayDailyLimit()
        guard dailyLimit > 0, dailyLimit < 1440 else { return }

        let usedMinutes = usageSeconds / 60
        let thresholdMinutes = Int(Double(dailyLimit) * 0.80)

        guard usedMinutes >= thresholdMinutes, usedMinutes < dailyLimit else { return }

        let todayKey = Self.dayDateFormatter.string(from: Date())
        let sentKey = "ext_approaching_limit_\(appID)_\(todayKey)"
        guard !defaults.bool(forKey: sentKey) else { return }

        let appName = defaults.string(forKey: "map_\(appID)_name") ?? "Reward App"
        let displayName = (appName.hasPrefix("Unknown App")) ? "Reward App" : appName
        let remaining = dailyLimit - usedMinutes

        let content = UNMutableNotificationContent()
        content.title = "Approaching Limit"
        content.body = "\(displayName): \(Self.formatRewardDuration(remaining)) remaining today"
        content.sound = .default
        content.categoryIdentifier = "dailyLimit"

        let identifier = "ext_approaching_limit_\(appID)_\(todayKey)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.debugLog("NOTIFICATION: ❌ Approaching limit failed - \(error.localizedDescription)", defaults: defaults)
            } else {
                defaults.set(true, forKey: sentKey)
                self?.debugLog("NOTIFICATION: ✅ Approaching limit for \(String(appID.prefix(12))) (\(displayName)) — \(remaining)min left of \(dailyLimit)min", defaults: defaults)
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
                defaults.set(5, forKey: "window_size_\(goalConfig.rewardAppLogicalID)")
                let dtk = Self.dayDateFormatter.string(from: Date())
                defaults.removeObject(forKey: "ext_goal_notification_\(goalConfig.rewardAppLogicalID)_\(dtk)")
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
                defaults.set(5, forKey: "window_size_\(goalConfig.rewardAppLogicalID)")
                let dltk = Self.dayDateFormatter.string(from: Date())
                defaults.removeObject(forKey: "ext_goal_notification_\(goalConfig.rewardAppLogicalID)_\(dltk)")
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
                defaults.set(5, forKey: "window_size_\(goalConfig.rewardAppLogicalID)")
                let lgtk = Self.dayDateFormatter.string(from: Date())
                defaults.removeObject(forKey: "ext_goal_notification_\(goalConfig.rewardAppLogicalID)_\(lgtk)")
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
        let rewardAppIDs = Set(configs.goalConfigs.map { $0.rewardAppLogicalID })

        // Build BankCalculator inputs from the extension's data sources. The
        // stale-reference filter (drop linkedLearningApps whose logicalID is also a reward
        // app — see May 6 2026 fix) is applied at the input boundary; BankCalculator
        // trusts whatever it gets.
        var todaySecondsByID: [String: Int] = [:]
        var ratioByLearningID: [String: Double] = [:]
        var bankGoalConfigs: [BankCalculator.GoalConfigInput] = []

        for goalConfig in configs.goalConfigs {
            let rewardID = goalConfig.rewardAppLogicalID
            todaySecondsByID[rewardID] = defaults.integer(forKey: "usage_\(rewardID)_today")

            var bankLinks: [BankCalculator.GoalConfigInput.LinkedLearning] = []
            for linked in goalConfig.linkedLearningApps {
                let learningID = linked.learningAppLogicalID
                guard !rewardAppIDs.contains(learningID) else { continue }
                bankLinks.append(.init(
                    learningAppLogicalID: learningID,
                    minutesRequired: linked.minutesRequired
                ))
                if todaySecondsByID[learningID] == nil {
                    todaySecondsByID[learningID] = defaults.integer(forKey: "usage_\(learningID)_today")
                }
                if ratioByLearningID[learningID] == nil {
                    ratioByLearningID[learningID] = Double(linked.rewardMinutesEarned)
                        / Double(max(1, linked.ratioLearningMinutes))
                }
            }

            bankGoalConfigs.append(.init(
                rewardAppLogicalID: rewardID,
                linkedLearning: bankLinks
            ))
        }

        let inputs = BankCalculator.Inputs(
            todaySecondsByLogicalID: todaySecondsByID,
            goalConfigs: bankGoalConfigs,
            ratioByLearningLogicalID: ratioByLearningID,
            historicalRemainingMinutes: historical
        )

        // Diagnostic breakdown: replicate BankCalculator's earned/used so the log
        // shows every component of the max(0, hist + earned - used) clamp, not
        // just the post-clamp pool. Cheap walk over inputs.
        var lowestThresholdByLearningID: [String: Int] = [:]
        for goal in inputs.goalConfigs {
            for link in goal.linkedLearning {
                let prior = lowestThresholdByLearningID[link.learningAppLogicalID] ?? Int.max
                lowestThresholdByLearningID[link.learningAppLogicalID] = min(prior, link.minutesRequired)
            }
        }
        var todayEarned = 0
        for (learningID, threshold) in lowestThresholdByLearningID {
            let usageMin = (inputs.todaySecondsByLogicalID[learningID] ?? 0) / 60
            guard usageMin >= threshold else { continue }
            let r = inputs.ratioByLearningLogicalID[learningID] ?? 1.0
            todayEarned += Int(Double(usageMin) * r)
        }
        var todayUsed = 0
        for goal in inputs.goalConfigs {
            todayUsed += (inputs.todaySecondsByLogicalID[goal.rewardAppLogicalID] ?? 0) / 60
        }
        debugLog("BANK_BREAKDOWN historical=\(historical)min todayEarned=\(todayEarned)min todayUsed=\(todayUsed)min raw=\(historical + todayEarned - todayUsed)min", defaults: defaults)

        return BankCalculator.computeBank(inputs)
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
