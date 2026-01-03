import SwiftUI
import Combine

/// Wrapper that displays ChildAppStreakCard using DashboardDataProvider data.
/// Shows aggregate streak information across all apps.
struct StreaksSummarySection<Provider: DashboardDataProvider>: View {
    @ObservedObject var dataProvider: Provider

    var body: some View {
        // Only show if there's streak data (currentStreak > 0 or longestStreak > 0)
        if dataProvider.currentStreak > 0 || dataProvider.longestStreak > 0 {
            ChildAppStreakCard(
                currentStreak: dataProvider.currentStreak,
                longestStreak: dataProvider.longestStreak,
                nextMilestone: nextMilestone,
                progress: dataProvider.streakProgress,
                milestoneCycleDays: dataProvider.milestoneCycleDays,
                isAtRisk: dataProvider.isStreakAtRisk,
                potentialBonus: dataProvider.potentialBonusMinutes
            )
        } else {
            // Empty state when no streaks yet
            noStreaksCard
        }
    }

    private var nextMilestone: Int? {
        let cycle = dataProvider.milestoneCycleDays
        let current = dataProvider.currentStreak
        let next = ((current / cycle) + 1) * cycle
        return next
    }

    @Environment(\.colorScheme) private var colorScheme

    private var noStreaksCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.sunnyYellow.opacity(0.5))

                Text("DAILY STREAK")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            HStack(spacing: 16) {
                Image(systemName: "flame")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.sunnyYellow.opacity(0.3))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start your streak!")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Complete learning goals daily to build a streak and earn bonus minutes")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview("Active Streak") {
    StreaksSummarySection(dataProvider: PreviewStreakProvider(current: 5, longest: 12, progress: 0.7))
        .padding()
        .background(AppTheme.background(for: .light))
}

#Preview("No Streak") {
    StreaksSummarySection(dataProvider: PreviewStreakProvider(current: 0, longest: 0, progress: 0))
        .padding()
        .background(AppTheme.background(for: .light))
}

#Preview("At Risk") {
    StreaksSummarySection(dataProvider: PreviewStreakProvider(current: 6, longest: 6, progress: 0.86, atRisk: true))
        .padding()
        .background(AppTheme.background(for: .light))
}

// MARK: - Preview Helper

@MainActor
private final class PreviewStreakProvider: DashboardDataProvider {
    @Published var currentStreak: Int
    @Published var longestStreak: Int
    @Published var streakProgress: Double
    @Published var isStreakAtRisk: Bool

    init(current: Int, longest: Int, progress: Double, atRisk: Bool = false) {
        self.currentStreak = current
        self.longestStreak = longest
        self.streakProgress = progress
        self.isStreakAtRisk = atRisk
    }

    @Published var learningTimeSeconds: Int = 0
    @Published var rewardTimeSeconds: Int = 0
    @Published var learningAppDetails: [AppUsageDetail] = []
    @Published var rewardAppDetails: [AppUsageDetail] = []
    @Published var earnedMinutes: Int = 0
    @Published var usedMinutes: Int = 0
    @Published var streakBonusMinutes: Int = 0
    @Published var milestoneCycleDays: Int = 7
    @Published var potentialBonusMinutes: Int = 10
    @Published var dailyTotals: [DailyUsageTotals] = []
    @Published var isRemoteContext: Bool = false
    @Published var isLoading: Bool = false

    func refresh() async {}
}
