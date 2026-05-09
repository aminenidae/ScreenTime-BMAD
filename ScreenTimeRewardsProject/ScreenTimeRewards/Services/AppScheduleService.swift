import Foundation
import SwiftUI
import Combine

/// Service for managing per-app schedule configurations
@MainActor
class AppScheduleService: ObservableObject {
    static let shared = AppScheduleService()

    // MARK: - Published Properties

    @Published private(set) var schedules: [String: AppScheduleConfiguration] = [:]

    /// Append-only history of schedule versions, indexed by logicalID.
    /// Each array is sorted ascending by `effectiveFromDay`.
    @Published private(set) var versions: [String: [AppScheduleVersion]] = [:]

    // MARK: - Private Properties

    private let userDefaultsKey = "AppScheduleConfigurations"
    private let versionsKey = "AppScheduleVersions"
    private let versioningMigrationKey = "schedule_versioning_v1"
    private let sharedDefaults: UserDefaults?

    // MARK: - Initialization

    private init() {
        // Use app group for sharing with extensions
        sharedDefaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")
        loadSchedules()
        loadVersions()
        seedInitialVersionsIfNeeded()
    }

    // MARK: - Public Methods

    /// Load all saved schedules from UserDefaults
    func loadSchedules() {
        guard let data = sharedDefaults?.data(forKey: userDefaultsKey) else {
            return
        }

        do {
            let configs = try JSONDecoder().decode([AppScheduleConfiguration].self, from: data)
            var schedulesDict: [String: AppScheduleConfiguration] = [:]
            for config in configs {
                schedulesDict[config.id] = config
            }
            schedules = schedulesDict

            // One-time migration: copy per-link ratios to learning app schedules
            migrateRatiosToLearningApps()
        } catch {
            print("[AppScheduleService] Failed to decode schedules: \(error)")
        }
    }

    /// One-time migration: move per-link ratios from LinkedLearningApp to the learning app's own schedule.
    /// Only runs once (guarded by UserDefaults flag).
    private func migrateRatiosToLearningApps() {
        let migrationKey = "ratio_migration_v1"
        guard sharedDefaults?.bool(forKey: migrationKey) != true else { return }

        var didMigrate = false

        // Iterate all schedules looking for reward apps with linked learning apps
        for (_, schedule) in schedules {
            for linked in schedule.linkedLearningApps {
                // Skip default 1:1 ratios — nothing to migrate
                guard linked.ratioLearningMinutes != 1 || linked.rewardMinutesEarned != 1 else { continue }

                // Only migrate if the learning app's schedule still has default ratio
                if var learningSchedule = schedules[linked.logicalID],
                   learningSchedule.ratioLearningMinutes == 1,
                   learningSchedule.rewardMinutesEarned == 1 {
                    learningSchedule.ratioLearningMinutes = linked.ratioLearningMinutes
                    learningSchedule.rewardMinutesEarned = linked.rewardMinutesEarned
                    schedules[linked.logicalID] = learningSchedule
                    didMigrate = true
                    #if DEBUG
                    print("[AppScheduleService] Migrated ratio \(linked.ratioLearningMinutes):\(linked.rewardMinutesEarned) to learning app \(linked.logicalID)")
                    #endif
                }
            }
        }

        if didMigrate {
            try? persistSchedules()
        }
        sharedDefaults?.set(true, forKey: migrationKey)
    }

    /// Save a schedule configuration for an app.
    ///
    /// Phase 2: also appends an `AppScheduleVersion` history row. The version's
    /// `effectiveFromDay` follows the §2E policy:
    ///   - effective TODAY if the kid has done no learning yet today (no row to re-price), OR
    ///   - effective TOMORROW otherwise (preserves today's earned at today's old ratio).
    func saveSchedule(_ config: AppScheduleConfiguration) throws {
        // BEFORE mutating: freeze any learning app whose gating eligibility this
        // save would reduce or remove. Walks both old and new linkedLearningApps
        // so threshold-tightening edits are caught alongside outright removals.
        // Must run while `schedules` still reflects the OLD state — see
        // `freezeAffectedLearningContribution`.
        let oldLinkedIDs: Set<String> = Set((schedules[config.id]?.linkedLearningApps ?? []).map { $0.logicalID })
        let newLinkedIDs: Set<String> = Set(config.linkedLearningApps.map { $0.logicalID })
        let affected = oldLinkedIDs.union(newLinkedIDs)
        for learningID in affected {
            freezeAffectedLearningContribution(learningLogicalID: learningID, changedRewardConfig: config)
        }

        schedules[config.id] = config
        try persistSchedules()

        // Also save individual keys for extension access
        saveScheduleForExtension(config)

        // Append a versioned snapshot.
        let effectiveFromDay = decideEffectiveFromDay(for: config)
        appendVersion(for: config, effectiveFromDay: effectiveFromDay)

        // Sync goal configs to extension if this config has linked learning apps
        // This allows the extension to control shields directly
        if !config.linkedLearningApps.isEmpty {
            Task { @MainActor in
                ScreenTimeService.shared.syncGoalConfigsToExtension()
            }
        }
    }

    /// Delete a schedule configuration
    func deleteSchedule(for logicalID: String) throws {
        // If we're deleting a reward schedule that linked any learning apps,
        // those learning apps are losing this link — freeze each affected one
        // BEFORE the schedule disappears (so their old contribution survives).
        if let removedConfig = schedules[logicalID], !removedConfig.linkedLearningApps.isEmpty {
            // Build a synthetic "new state" of the deleted schedule: same id but
            // empty linked list. freezeAffectedLearningContribution will then see
            // the link drop and freeze the loss.
            var emptied = removedConfig
            emptied.linkedLearningApps = []
            for link in removedConfig.linkedLearningApps {
                freezeAffectedLearningContribution(
                    learningLogicalID: link.logicalID,
                    changedRewardConfig: emptied
                )
            }
        }

        schedules.removeValue(forKey: logicalID)
        try persistSchedules()

        // Remove extension keys
        removeScheduleForExtension(logicalID)

        // Re-sync goal configs to extension (in case deleted config was a reward app)
        Task { @MainActor in
            ScreenTimeService.shared.syncGoalConfigsToExtension()
        }
    }

    /// Get schedule for a specific app
    func getSchedule(for logicalID: String) -> AppScheduleConfiguration? {
        schedules[logicalID]
    }

    /// Check if an app is currently allowed based on its schedule
    func isAppCurrentlyAllowed(_ logicalID: String) -> Bool {
        guard let config = schedules[logicalID] else {
            return true // No config = allowed
        }

        guard config.isEnabled else {
            return false // Disabled apps are not allowed
        }

        return config.isCurrentlyInAllowedWindow
    }

    /// Calculate remaining daily limit for an app
    func remainingDailyLimit(for logicalID: String, usedMinutes: Int) -> Int {
        guard let config = schedules[logicalID] else {
            return Int.max // No config = unlimited
        }

        let todayLimit = config.dailyLimits.todayLimit
        return max(0, todayLimit - usedMinutes)
    }

    /// Get all schedules for a set of app IDs
    func getSchedules(for logicalIDs: Set<String>) -> [String: AppScheduleConfiguration] {
        var result: [String: AppScheduleConfiguration] = [:]
        for id in logicalIDs {
            if let config = schedules[id] {
                result[id] = config
            }
        }
        return result
    }

    /// Batch save multiple configurations (for challenge creation)
    func saveSchedules(_ configs: [AppScheduleConfiguration]) throws {
        for config in configs {
            // Same freeze sweep as saveSchedule, applied per config in order.
            let oldLinkedIDs: Set<String> = Set((schedules[config.id]?.linkedLearningApps ?? []).map { $0.logicalID })
            let newLinkedIDs: Set<String> = Set(config.linkedLearningApps.map { $0.logicalID })
            for learningID in oldLinkedIDs.union(newLinkedIDs) {
                freezeAffectedLearningContribution(learningLogicalID: learningID, changedRewardConfig: config)
            }

            schedules[config.id] = config
            saveScheduleForExtension(config)
            // Phase 2: per-config versioning for batch saves too.
            let effectiveFromDay = decideEffectiveFromDay(for: config)
            appendVersion(for: config, effectiveFromDay: effectiveFromDay)
        }
        try persistSchedules()

        // Sync goal configs to extension if any config has linked learning apps
        let hasLinkedApps = configs.contains { !$0.linkedLearningApps.isEmpty }
        if hasLinkedApps {
            Task { @MainActor in
                ScreenTimeService.shared.syncGoalConfigsToExtension()
            }
        }
    }

    /// Strip stale `linkedLearningApps` entries that point at apps now categorized as `.reward`.
    ///
    /// Walks every schedule and drops linked entries whose logicalID is in `rewardAppLogicalIDs`.
    /// Persists + re-syncs to the extension only if any schedule actually changed.
    ///
    /// Why: a learning↔reward category flip leaves stale references in *other* reward apps'
    /// `linkedLearningApps` lists. The extension and main-app shield calculations now defensively
    /// filter such references at runtime (May 6, 2026 — see `docs/SMART_THRESHOLD_FILTERING.md`),
    /// but this scrub is the durable fix: clean the data so the UI ("Complete Goal: use YouTube
    /// for 15 min") doesn't show impossible requirements either.
    ///
    /// Call this after any category mutation — see `ScreenTimeService.scrubStaleLinkedLearningReferences()`.
    func scrubLinkedReferences(rewardAppLogicalIDs: Set<String>) {
        guard !rewardAppLogicalIDs.isEmpty else { return }

        var didMutate = false
        var mutatedConfigs: [AppScheduleConfiguration] = []

        for (scheduleID, schedule) in schedules {
            // Don't touch a reward app's linked-learning list if the only stale entry IS itself —
            // a self-link is a separate UX bug, not in scope for this scrub.
            let filtered = schedule.linkedLearningApps.filter { linked in
                !rewardAppLogicalIDs.contains(linked.logicalID) || linked.logicalID == scheduleID
            }
            guard filtered.count < schedule.linkedLearningApps.count else { continue }

            var updated = schedule
            updated.linkedLearningApps = filtered
            schedules[scheduleID] = updated
            mutatedConfigs.append(updated)
            didMutate = true

            #if DEBUG
            let removed = schedule.linkedLearningApps.count - filtered.count
            print("[AppScheduleService] 🧹 Scrubbed \(removed) stale linked learning ref(s) from schedule \(scheduleID.prefix(12))...")
            #endif
        }

        guard didMutate else { return }

        do { try persistSchedules() } catch {
            print("[AppScheduleService] ⚠️ Failed to persist after scrub: \(error)")
        }
        for config in mutatedConfigs {
            saveScheduleForExtension(config)
        }

        // Re-sync goal configs so the extension picks up the cleaned linkedLearningApps.
        Task { @MainActor in
            ScreenTimeService.shared.syncGoalConfigsToExtension()
        }
    }

    /// Create default configurations for a set of app IDs
    func createDefaultConfigs(for logicalIDs: Set<String>, type: AppType) -> [String: AppScheduleConfiguration] {
        var configs: [String: AppScheduleConfiguration] = [:]
        for id in logicalIDs {
            switch type {
            case .learning:
                configs[id] = .defaultLearning(logicalID: id)
            case .reward:
                configs[id] = .defaultReward(logicalID: id)
            }
        }
        return configs
    }

    // MARK: - Schedule Versioning (Phase 2)

    /// Find the schedule version active for a given app on a given day.
    /// Returns the most recent version whose `effectiveFromDay <= day`.
    /// Falls back to the current schedule (wrapped in a synthetic version) if no
    /// version row matches — covers the upgrade window before the seed migration runs.
    func versionActive(logicalID: String, on day: String) -> AppScheduleVersion? {
        if let history = versions[logicalID], !history.isEmpty {
            // history is kept sorted ascending by effectiveFromDay
            for version in history.reversed() {
                if version.effectiveFromDay <= day {
                    return version
                }
            }
        }
        // Fallback: current schedule treated as effective forever.
        if let current = schedules[logicalID] {
            return AppScheduleVersion(from: current, effectiveFromDay: AppScheduleVersion.earliestDay)
        }
        return nil
    }

    /// Convenience overload: look up by `Date`.
    func versionActive(logicalID: String, on date: Date) -> AppScheduleVersion? {
        versionActive(logicalID: logicalID, on: AppScheduleVersion.dayKey(for: date))
    }

    /// Effective ratio (rewardMinutes / learningMinutes) for `logicalID` on `day`,
    /// honoring the day+1 effective-from policy. Today's live bank readers MUST
    /// route through this — reading `schedule.rewardMinutesEarned /
    /// schedule.ratioLearningMinutes` directly re-prices today instantly when a
    /// parent edits the ratio mid-day, defeating `decideEffectiveFromDay`.
    func ratio(logicalID: String, on day: String = AppScheduleVersion.todayKey) -> Double {
        versionActive(logicalID: logicalID, on: day)?.ratio ?? 1.0
    }

    /// Effective `(rewardMinutesEarned, ratioLearningMinutes)` integer pair for
    /// `logicalID` on `day`. Used by the extension-config sync, which writes the
    /// pair (not a Double) into `ExtensionGoalConfig.LinkedGoal`.
    func ratioFields(logicalID: String, on day: String = AppScheduleVersion.todayKey)
        -> (rewardMinutesEarned: Int, ratioLearningMinutes: Int)?
    {
        guard let v = versionActive(logicalID: logicalID, on: day) else { return nil }
        return (v.rewardMinutesEarned, v.ratioLearningMinutes)
    }

    // MARK: - Link-Removal Freeze (preserve today's bank across an unlink)

    /// Hold today's bank value constant across a schedule edit that would change
    /// a learning app's `todayEarned` contribution. Without this, removing a
    /// goal link (or raising its threshold past today's usage) visibly wipes
    /// today's contribution from `BankCalculator.todayEarned` until midnight.
    /// Mirrors the May 7 category-flip freeze pattern, per-affected-learning-app.
    ///
    /// Call BEFORE mutating `schedules` so `schedules.values` still reflects the
    /// OLD state. The new state is reconstructed by swapping `newConfig` in.
    ///
    /// Symmetric: positive `loss` (link removed / threshold raised past usage)
    /// → bake into baseline + add to absorbed-rows map.
    /// Negative `loss` (link added / threshold lowered into range) → reverse a
    /// prior freeze on the same (today, learningID) pair. The absorbed-rows
    /// helper drops the entry once the running total reaches zero, so today's
    /// dailyHistory row gets re-included at midnight as if the freeze never
    /// happened.
    private func freezeAffectedLearningContribution(
        learningLogicalID: String,
        changedRewardConfig newConfig: AppScheduleConfiguration
    ) {
        let usageKey = "usage_\(learningLogicalID)_today"
        let usageSeconds = sharedDefaults?.integer(forKey: usageKey) ?? 0
        let usageMinutes = usageSeconds / 60
        guard usageMinutes > 0 else { return }

        let oldConfigs = Array(schedules.values)
        var newConfigs = oldConfigs
        if let idx = newConfigs.firstIndex(where: { $0.id == newConfig.id }) {
            newConfigs[idx] = newConfig
        } else {
            newConfigs.append(newConfig)
        }

        let oldLowest = Self.lowestThreshold(for: learningLogicalID, across: oldConfigs)
        let newLowest = Self.lowestThreshold(for: learningLogicalID, across: newConfigs)

        let r = ratio(logicalID: learningLogicalID)
        let oldContribution = (oldLowest.map { usageMinutes >= $0 } ?? false)
            ? Int(Double(usageMinutes) * r) : 0
        let newContribution = (newLowest.map { usageMinutes >= $0 } ?? false)
            ? Int(Double(usageMinutes) * r) : 0
        let loss = oldContribution - newContribution
        guard loss != 0 else { return }

        // Bound the negative case so we never reverse more than was previously
        // baked in (e.g. a brand-new link with no prior freeze must not push
        // baseline negative). Read absorbed amount via the persistence helper.
        let todayKey = AppScheduleVersion.todayKey
        let priorAbsorbed = ScreenTimeService.shared.usagePersistence
            .loadAbsorbedHistoryRows()[todayKey]?[learningLogicalID] ?? 0
        let appliedLoss: Int
        if loss < 0 {
            appliedLoss = -min(priorAbsorbed, -loss)
        } else {
            appliedLoss = loss
        }
        guard appliedLoss != 0 else { return }

        let baselineKey = "bank_baseline_minutes_v1"
        let current = sharedDefaults?.integer(forKey: baselineKey) ?? 0
        sharedDefaults?.set(current + appliedLoss, forKey: baselineKey)

        ScreenTimeService.shared.usagePersistence
            .adjustHistoryRowAbsorption(logicalID: learningLogicalID, dayKey: todayKey, byMinutes: appliedLoss)

        #if DEBUG
        print("[AppScheduleService] 🔒 Bank freeze L=\(learningLogicalID.prefix(8))... " +
              "usage=\(usageMinutes)m oldLowest=\(oldLowest.map(String.init) ?? "nil") " +
              "newLowest=\(newLowest.map(String.init) ?? "nil") rawLoss=\(loss)m " +
              "applied=\(appliedLoss)m priorAbsorbed=\(priorAbsorbed)m day=\(todayKey)")
        #endif
    }

    /// Lowest `minutesRequired` for `learningLogicalID` across every reward
    /// schedule's `linkedLearningApps`. Returns nil when no schedule references
    /// the learning app.
    private static func lowestThreshold(
        for learningLogicalID: String,
        across configs: [AppScheduleConfiguration]
    ) -> Int? {
        var lowest: Int? = nil
        for config in configs {
            for link in config.linkedLearningApps where link.logicalID == learningLogicalID {
                lowest = lowest.map { Swift.min($0, link.minutesRequired) } ?? link.minutesRequired
            }
        }
        return lowest
    }

    /// Decide whether a save takes effect today or tomorrow.
    /// Today if the kid has done zero learning on this app today (no row to
    /// re-price); tomorrow otherwise.
    private func decideEffectiveFromDay(for config: AppScheduleConfiguration) -> String {
        // Reads the live extension counter — represents today's actual learning.
        let usageKey = "usage_\(config.id)_today"
        let todaySeconds = sharedDefaults?.integer(forKey: usageKey) ?? 0
        return todaySeconds == 0 ? AppScheduleVersion.todayKey : AppScheduleVersion.tomorrowKey
    }

    /// Append a version row for `config` with the given effective day. If a row
    /// already exists for the same `effectiveFromDay`, replace it (latest write
    /// wins for a given day).
    private func appendVersion(for config: AppScheduleConfiguration, effectiveFromDay: String) {
        let new = AppScheduleVersion(from: config, effectiveFromDay: effectiveFromDay)
        var history = versions[config.id] ?? []
        history.removeAll { $0.effectiveFromDay == effectiveFromDay }
        history.append(new)
        history.sort { $0.effectiveFromDay < $1.effectiveFromDay }
        versions[config.id] = history
        persistVersions()
    }

    /// One-time migration: seed an `effectiveFromDay = "1970-01-01"` version for every
    /// existing schedule, carrying its current values. Result: kids see no bank jump
    /// on upgrade because all historical days resolve to the same ratio they had.
    private func seedInitialVersionsIfNeeded() {
        guard sharedDefaults?.bool(forKey: versioningMigrationKey) != true else { return }

        let now = Date()
        for (logicalID, config) in schedules where versions[logicalID]?.isEmpty != false {
            let seed = AppScheduleVersion(
                from: config,
                effectiveFromDay: AppScheduleVersion.earliestDay,
                createdAt: now
            )
            versions[logicalID] = [seed]
        }
        persistVersions()
        sharedDefaults?.set(true, forKey: versioningMigrationKey)
        #if DEBUG
        print("[AppScheduleService] 📜 schedule_versioning_v1: seeded \(versions.count) initial versions")
        #endif
    }

    private func loadVersions() {
        guard let data = sharedDefaults?.data(forKey: versionsKey) else { return }
        do {
            let flat = try JSONDecoder().decode([AppScheduleVersion].self, from: data)
            var byID: [String: [AppScheduleVersion]] = [:]
            for v in flat {
                byID[v.logicalID, default: []].append(v)
            }
            for key in byID.keys {
                byID[key]?.sort { $0.effectiveFromDay < $1.effectiveFromDay }
            }
            versions = byID
        } catch {
            #if DEBUG
            print("[AppScheduleService] Failed to decode schedule versions: \(error)")
            #endif
        }
    }

    private func persistVersions() {
        let flat = versions.values.flatMap { $0 }
        if let data = try? JSONEncoder().encode(flat) {
            sharedDefaults?.set(data, forKey: versionsKey)
        }
    }

    /// Drop versions strictly older than `cutoffDay`. Called when day rolls over to
    /// keep the array bounded by the 30-day `dailyHistory` window. Always retains
    /// the most recent version even if it's older than the cutoff (need at least
    /// one row to resolve `versionActive`).
    func pruneVersionsOlderThan(_ cutoffDay: String) {
        var didChange = false
        for (logicalID, history) in versions {
            guard !history.isEmpty else { continue }
            let kept = history.filter { $0.effectiveFromDay >= cutoffDay }
            // Always retain the most recent version even if older than cutoff.
            let lastBeforeCutoff = history.last { $0.effectiveFromDay < cutoffDay }
            var pruned = kept
            if pruned.isEmpty, let last = lastBeforeCutoff {
                pruned = [last]
            } else if let last = lastBeforeCutoff,
                      let firstKept = pruned.first,
                      last.effectiveFromDay < firstKept.effectiveFromDay {
                pruned.insert(last, at: 0)
            }
            if pruned.count != history.count {
                versions[logicalID] = pruned
                didChange = true
            }
        }
        if didChange {
            persistVersions()
        }
    }

    /// Build a ratio map: learningLogicalID → ratio active on `day`.
    /// Used by bank computation to apply per-day historical ratios.
    func ratioMap(on day: String, for logicalIDs: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for logicalID in logicalIDs {
            if let version = versionActive(logicalID: logicalID, on: day) {
                result[logicalID] = version.ratio
            }
        }
        return result
    }

    /// Today's recorded learning seconds for a single app, read from the extension's
    /// live counter in App Group UserDefaults. Used by the schedule-edit dialog to
    /// decide whether a new ratio takes effect today (no learning yet) or tomorrow.
    func effectiveLearningSecondsToday(forLogicalID logicalID: String) -> Int {
        sharedDefaults?.integer(forKey: "usage_\(logicalID)_today") ?? 0
    }

    // MARK: - Private Methods

    private func persistSchedules() throws {
        let configs = Array(schedules.values)
        let data = try JSONEncoder().encode(configs)
        sharedDefaults?.set(data, forKey: userDefaultsKey)
    }

    /// Save individual schedule keys for extension access
    private func saveScheduleForExtension(_ config: AppScheduleConfiguration) {
        let prefix = "schedule_\(config.id)"

        // Daily limit for today
        sharedDefaults?.set(config.dailyLimits.todayLimit, forKey: "\(prefix)_dailyLimit")

        // Time window
        let windowStart = config.allowedTimeWindow.startHour * 60 + config.allowedTimeWindow.startMinute
        let windowEnd = config.allowedTimeWindow.endHour * 60 + config.allowedTimeWindow.endMinute
        sharedDefaults?.set(windowStart, forKey: "\(prefix)_windowStart")
        sharedDefaults?.set(windowEnd, forKey: "\(prefix)_windowEnd")

        // Enabled state
        sharedDefaults?.set(config.isEnabled, forKey: "\(prefix)_enabled")

        // Individual day limits for more granular control
        sharedDefaults?.set(config.dailyLimits.sunday, forKey: "\(prefix)_limitSun")
        sharedDefaults?.set(config.dailyLimits.monday, forKey: "\(prefix)_limitMon")
        sharedDefaults?.set(config.dailyLimits.tuesday, forKey: "\(prefix)_limitTue")
        sharedDefaults?.set(config.dailyLimits.wednesday, forKey: "\(prefix)_limitWed")
        sharedDefaults?.set(config.dailyLimits.thursday, forKey: "\(prefix)_limitThu")
        sharedDefaults?.set(config.dailyLimits.friday, forKey: "\(prefix)_limitFri")
        sharedDefaults?.set(config.dailyLimits.saturday, forKey: "\(prefix)_limitSat")
    }

    private func removeScheduleForExtension(_ logicalID: String) {
        let prefix = "schedule_\(logicalID)"
        let keys = [
            "\(prefix)_dailyLimit",
            "\(prefix)_windowStart",
            "\(prefix)_windowEnd",
            "\(prefix)_enabled",
            "\(prefix)_limitSun",
            "\(prefix)_limitMon",
            "\(prefix)_limitTue",
            "\(prefix)_limitWed",
            "\(prefix)_limitThu",
            "\(prefix)_limitFri",
            "\(prefix)_limitSat"
        ]
        for key in keys {
            sharedDefaults?.removeObject(forKey: key)
        }
    }
}

// MARK: - Supporting Types

enum AppType {
    case learning
    case reward
}
