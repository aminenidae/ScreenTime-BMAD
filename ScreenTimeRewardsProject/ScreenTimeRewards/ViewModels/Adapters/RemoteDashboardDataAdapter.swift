import Foundation
import SwiftUI
import Combine

/// Adapter that wraps ParentRemoteViewModel for the remote (parent device) dashboard context.
/// Conforms to DashboardDataProvider to enable unified dashboard views.
@MainActor
final class RemoteDashboardDataAdapter: DashboardDataProvider {
    private let viewModel: ParentRemoteViewModel
    private var cancellables = Set<AnyCancellable>()

    // Published properties to trigger SwiftUI updates
    @Published private var refreshTrigger = false

    init(viewModel: ParentRemoteViewModel) {
        self.viewModel = viewModel

        setupBinding()
    }

    private func setupBinding() {
        // Forward objectWillChange from underlying view model
        viewModel.objectWillChange
            .sink { [weak self] _ in
                #if DEBUG
                print("[RemoteDashboardDataAdapter] 🔔 viewModel.objectWillChange received")
                print("[RemoteDashboardDataAdapter]   childLearningAppsFullConfig.count: \(self?.viewModel.childLearningAppsFullConfig.count ?? -1)")
                print("[RemoteDashboardDataAdapter]   childRewardAppsFullConfig.count: \(self?.viewModel.childRewardAppsFullConfig.count ?? -1)")
                #endif
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Usage Overview

    var learningTimeSeconds: Int {
        viewModel.todayTotals.learningSeconds
    }

    var rewardTimeSeconds: Int {
        viewModel.todayTotals.rewardSeconds
    }

    var learningAppDetails: [AppUsageDetail] {
        let calendar = Calendar.current

        // Get today's usage grouped by logicalID
        let todayRecords = viewModel.childDailyUsageHistory.filter {
            $0.category == "Learning" && calendar.isDateInToday($0.date)
        }
        let usageByApp = Dictionary(grouping: todayRecords) { $0.logicalID }

        // Map ALL configured learning apps, using today's usage where available
        return viewModel.childLearningAppsFullConfig.map { config in
            let records = usageByApp[config.logicalID] ?? []
            let totalSeconds = records.reduce(0) { $0 + $1.seconds }

            return AppUsageDetail(
                id: config.logicalID,
                displayName: config.displayName,
                category: .learning,
                todaySeconds: totalSeconds,
                iconURL: config.iconURL,
                pointsPerMinute: config.pointsPerMinute,
                earnedPoints: (totalSeconds / 60) * config.pointsPerMinute
            )
        }.sorted { $0.todaySeconds > $1.todaySeconds }
    }

    var rewardAppDetails: [AppUsageDetail] {
        let calendar = Calendar.current

        // Get today's usage grouped by logicalID
        let todayRecords = viewModel.childDailyUsageHistory.filter {
            $0.category == "Reward" && calendar.isDateInToday($0.date)
        }
        let usageByApp = Dictionary(grouping: todayRecords) { $0.logicalID }

        // Map ALL configured reward apps, using today's usage where available
        return viewModel.childRewardAppsFullConfig.map { config in
            let records = usageByApp[config.logicalID] ?? []
            let totalSeconds = records.reduce(0) { $0 + $1.seconds }

            return AppUsageDetail(
                id: config.logicalID,
                displayName: config.displayName,
                category: .reward,
                todaySeconds: totalSeconds,
                iconURL: config.iconURL,
                pointsPerMinute: config.pointsPerMinute,
                earnedPoints: (totalSeconds / 60) * config.pointsPerMinute
            )
        }.sorted { $0.todaySeconds > $1.todaySeconds }
    }

    // MARK: - Time Bank

    var earnedMinutes: Int {
        // Primary: Use pre-calculated value from synced daily snapshot
        if viewModel.hasValidDailySnapshot,
           let snapshot = viewModel.childDailySnapshot {
            #if DEBUG
            print("[RemoteDashboardDataAdapter] earnedMinutes = \(snapshot.totalEarnedMinutes) (from snapshot)")
            #endif
            return snapshot.totalEarnedMinutes
        }

        // Fallback: Calculate from usage history + linked app configs
        let fallback = viewModel.fallbackEarnedMinutes
        #if DEBUG
        print("[RemoteDashboardDataAdapter] earnedMinutes = \(fallback) (FALLBACK - no valid snapshot)")
        #endif
        return fallback
    }

    var usedMinutes: Int {
        // Minutes spent on reward apps today
        viewModel.todayTotals.rewardSeconds / 60
    }

    var streakBonusMinutes: Int {
        // Streak bonus requires knowing the streak settings and calculating bonus
        // For now, use a simple calculation based on current streak
        guard let summary = viewModel.childStreakSummary else { return 0 }

        // Calculate bonus based on completed milestone cycles
        // Using default settings: bonus every 7 days, 10 minutes per milestone
        let completedCycles = summary.maxCurrentStreak / AppStreakSettings.defaultSettings.streakCycleDays
        return completedCycles * AppStreakSettings.defaultSettings.bonusValue
    }

    var availableMinutes: Int {
        // Primary: Use cumulative available from synced daily snapshot (includes rollover)
        if viewModel.hasValidDailySnapshot,
           let snapshot = viewModel.childDailySnapshot {
            #if DEBUG
            print("[RemoteDashboardDataAdapter] availableMinutes = \(snapshot.cumulativeAvailableMinutes) (from snapshot)")
            #endif
            return snapshot.cumulativeAvailableMinutes
        }

        // Fallback: Calculate from usage history (today only, no rollover)
        let fallback = viewModel.fallbackAvailableMinutes
        #if DEBUG
        print("[RemoteDashboardDataAdapter] availableMinutes = \(fallback) (FALLBACK - today only)")
        #endif
        return fallback
    }

    // MARK: - Streaks

    var currentStreak: Int {
        viewModel.childStreakSummary?.maxCurrentStreak ?? 0
    }

    var longestStreak: Int {
        viewModel.childStreakSummary?.maxLongestStreak ?? 0
    }

    var isStreakAtRisk: Bool {
        viewModel.childStreakSummary?.anyAtRisk ?? false
    }

    var streakProgress: Double {
        // Progress within current milestone cycle
        let current = currentStreak
        let cycleDays = milestoneCycleDays
        let daysInCurrentCycle = current % cycleDays
        return cycleDays > 0 ? Double(daysInCurrentCycle) / Double(cycleDays) : 0
    }

    var milestoneCycleDays: Int {
        AppStreakSettings.defaultSettings.streakCycleDays
    }

    var potentialBonusMinutes: Int {
        AppStreakSettings.defaultSettings.bonusValue
    }

    var perAppStreaks: [PerAppStreakInfo] {
        var results: [PerAppStreakInfo] = []

        for config in viewModel.childRewardAppsFullConfig {
            guard let settings = config.streakSettings, settings.isEnabled else { continue }

            let streakRecord = viewModel.childStreakRecords.first { $0.appLogicalID == config.logicalID }
            let current = streakRecord?.currentStreak ?? 0
            let cycleDays = settings.streakCycleDays
            let nextMilestone = ((current / cycleDays) + 1) * cycleDays

            results.append(PerAppStreakInfo(
                appLogicalID: config.logicalID,
                appName: config.displayName,
                iconURL: config.iconURL,
                token: nil,  // Remote context uses URL-based icons
                currentStreak: current,
                daysToNextMilestone: nextMilestone - current,
                isAtRisk: streakRecord?.isAtRisk ?? false
            ))
        }
        return results
    }

    // MARK: - Trends

    var dailyTotals: [DailyUsageTotals] {
        viewModel.aggregatedDailyTotals.map {
            DailyUsageTotals(
                date: $0.date,
                learningSeconds: $0.learningSeconds,
                rewardSeconds: $0.rewardSeconds
            )
        }
    }

    // MARK: - Context

    var isRemoteContext: Bool { true }

    var deviceName: String? {
        viewModel.selectedChildDevice?.deviceName
    }

    var isLoading: Bool {
        viewModel.isLoading
    }

    var errorMessage: String? {
        viewModel.errorMessage
    }

    // MARK: - Extension Sync Status (Remote Diagnostics)

    /// Extension sync status for remote diagnostics
    /// Shows if the child's DeviceActivityMonitor extension is syncing correctly
    var extensionSyncStatus: ExtensionSyncStatusDTO? {
        viewModel.extensionSyncStatus
    }

    /// Human-readable extension sync status for display
    var extensionSyncDisplayStatus: String? {
        // Always return a value in remote context so parent can see sync status
        extensionSyncStatus?.displayStatus ?? "Extension has not synced yet"
    }

    // MARK: - Actions

    func refresh() async {
        guard let device = viewModel.selectedChildDevice else { return }
        await viewModel.loadChildData(for: device)
    }
}
