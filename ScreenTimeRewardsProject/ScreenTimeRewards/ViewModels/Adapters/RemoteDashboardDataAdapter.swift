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
        // Calculate from learning time and points per minute
        // For remote context, sum earned points from learning apps
        let calendar = Calendar.current
        let todayLearningRecords = viewModel.childDailyUsageHistory.filter {
            $0.category == "Learning" && calendar.isDateInToday($0.date)
        }

        var totalEarnedMinutes = 0

        for record in todayLearningRecords {
            let config = viewModel.childLearningAppsFullConfig.first { $0.logicalID == record.logicalID }
            let pointsPerMinute = config?.pointsPerMinute ?? 1
            let minutes = record.seconds / 60
            totalEarnedMinutes += minutes * pointsPerMinute
        }

        return totalEarnedMinutes
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

    // MARK: - Actions

    func refresh() async {
        guard let device = viewModel.selectedChildDevice else { return }
        await viewModel.loadChildData(for: device)
    }
}
