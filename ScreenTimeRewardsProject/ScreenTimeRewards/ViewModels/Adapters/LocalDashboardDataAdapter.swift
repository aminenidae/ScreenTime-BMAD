import Foundation
import SwiftUI
import Combine

/// Adapter that wraps AppUsageViewModel for the local (child device) dashboard context.
/// Conforms to DashboardDataProvider to enable unified dashboard views.
@MainActor
final class LocalDashboardDataAdapter: DashboardDataProvider {
    private var viewModel: AppUsageViewModel
    private let streakService: StreakService
    private var cancellables = Set<AnyCancellable>()

    // Published properties to trigger SwiftUI updates
    @Published private var refreshTrigger = false

    init(viewModel: AppUsageViewModel, streakService: StreakService = .shared) {
        self.viewModel = viewModel
        self.streakService = streakService

        setupBinding()
    }

    /// Updates the underlying view model (used when EnvironmentObject becomes available)
    func updateViewModel(_ newViewModel: AppUsageViewModel) {
        guard viewModel !== newViewModel else { return }
        cancellables.removeAll()
        viewModel = newViewModel
        setupBinding()
        objectWillChange.send()
    }

    private func setupBinding() {
        // Forward objectWillChange from underlying view model
        viewModel.objectWillChange
            .sink { [weak self] _ in
                #if DEBUG
                print("[LocalDashboardDataAdapter] 🔔 viewModel.objectWillChange received")
                print("[LocalDashboardDataAdapter]   learningSnapshots.count: \(self?.viewModel.learningSnapshots.count ?? -1)")
                print("[LocalDashboardDataAdapter]   rewardSnapshots.count: \(self?.viewModel.rewardSnapshots.count ?? -1)")
                #endif
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Usage Overview

    var learningTimeSeconds: Int {
        Int(viewModel.learningTime)
    }

    var rewardTimeSeconds: Int {
        Int(viewModel.rewardTime)
    }

    /// Direct access to learning snapshots (for local context icon display with tokens)
    var learningSnapshots: [LearningAppSnapshot] {
        viewModel.learningSnapshots
    }

    /// Direct access to reward snapshots (for local context icon display with tokens)
    var rewardSnapshots: [RewardAppSnapshot] {
        viewModel.rewardSnapshots
    }

    var learningAppDetails: [AppUsageDetail] {
        viewModel.learningSnapshots.map { snapshot in
            AppUsageDetail(
                id: snapshot.tokenHash,
                displayName: snapshot.displayName,
                category: .learning,
                todaySeconds: Int(snapshot.totalSeconds),
                iconURL: nil,  // Local context doesn't have icon URLs
                pointsPerMinute: snapshot.pointsPerMinute,
                earnedPoints: snapshot.earnedPoints
            )
        }
    }

    var rewardAppDetails: [AppUsageDetail] {
        viewModel.rewardSnapshots.map { snapshot in
            AppUsageDetail(
                id: snapshot.tokenHash,
                displayName: snapshot.displayName,
                category: .reward,
                todaySeconds: Int(snapshot.totalSeconds),
                iconURL: nil,
                pointsPerMinute: snapshot.pointsPerMinute,
                earnedPoints: snapshot.earnedPoints
            )
        }
    }

    // MARK: - Time Bank

    var earnedMinutes: Int {
        viewModel.totalEarnedMinutes
    }

    var usedMinutes: Int {
        viewModel.totalUsedMinutes
    }

    var streakBonusMinutes: Int {
        viewModel.totalStreakBonusMinutes
    }

    // MARK: - Streaks

    private var deviceID: String {
        DeviceModeManager.shared.deviceID
    }

    private var aggregateStreak: (current: Int, longest: Int, isAtRisk: Bool) {
        streakService.getAggregateStreak(for: deviceID)
    }

    var currentStreak: Int {
        aggregateStreak.current
    }

    var longestStreak: Int {
        aggregateStreak.longest
    }

    var isStreakAtRisk: Bool {
        aggregateStreak.isAtRisk
    }

    var streakProgress: Double {
        streakService.progressToNextMilestone(current: currentStreak)
    }

    var milestoneCycleDays: Int {
        AppStreakSettings.defaultSettings.streakCycleDays
    }

    var potentialBonusMinutes: Int {
        AppStreakSettings.defaultSettings.bonusValue
    }

    var perAppStreaks: [PerAppStreakInfo] {
        var results: [PerAppStreakInfo] = []

        for snapshot in viewModel.rewardSnapshots {
            guard let config = AppScheduleService.shared.getSchedule(for: snapshot.logicalID),
                  let settings = config.streakSettings,
                  settings.isEnabled else { continue }

            let record = streakService.streakRecords[snapshot.logicalID]
            let current = Int(record?.currentStreak ?? 0)
            let cycleDays = settings.streakCycleDays
            let nextMilestone = ((current / cycleDays) + 1) * cycleDays

            results.append(PerAppStreakInfo(
                appLogicalID: snapshot.logicalID,
                appName: snapshot.displayName,
                iconURL: nil,
                token: snapshot.token,  // Pass token for local context icon display
                currentStreak: current,
                daysToNextMilestone: nextMilestone - current,
                isAtRisk: record?.isAtRisk ?? false
            ))
        }
        return results
    }

    // MARK: - Trends

    var dailyTotals: [DailyUsageTotals] {
        // Build from app history mapping
        var dateMap: [Date: (learning: Int, reward: Int)] = [:]

        // Aggregate learning apps
        for snapshot in viewModel.learningSnapshots {
            if let history = viewModel.appHistoryMapping[snapshot.logicalID] {
                for day in history {
                    let startOfDay = Calendar.current.startOfDay(for: day.date)
                    var existing = dateMap[startOfDay] ?? (0, 0)
                    existing.learning += day.seconds
                    dateMap[startOfDay] = existing
                }
            }
        }

        // Aggregate reward apps
        for snapshot in viewModel.rewardSnapshots {
            if let history = viewModel.appHistoryMapping[snapshot.logicalID] {
                for day in history {
                    let startOfDay = Calendar.current.startOfDay(for: day.date)
                    var existing = dateMap[startOfDay] ?? (0, 0)
                    existing.reward += day.seconds
                    dateMap[startOfDay] = existing
                }
            }
        }

        // Convert to array sorted by date (most recent first)
        return dateMap.map { DailyUsageTotals(date: $0.key, learningSeconds: $0.value.learning, rewardSeconds: $0.value.reward) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Context

    var isRemoteContext: Bool { false }

    var isLoading: Bool { false }

    // MARK: - Actions

    func refresh() async {
        // Local view model refreshes automatically via Screen Time monitoring
        // Trigger a UI update
        refreshTrigger.toggle()
    }
}
