import SwiftUI
import Combine

/// Wrapper that displays per-app streak information using DashboardDataProvider data.
/// Shows streak progress for each reward app with streaks enabled.
struct StreaksSummarySection<Provider: DashboardDataProvider>: View {
    @ObservedObject var dataProvider: Provider

    var body: some View {
        // Show per-app streaks if any apps have streaks enabled
        if !dataProvider.perAppStreaks.isEmpty {
            PerAppStreakCard(streaks: dataProvider.perAppStreaks)
        } else {
            // Empty state when no streak-enabled apps
            noStreaksCard
        }
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

                    Text("Enable streaks on reward apps to track daily progress")
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

#Preview("Per-App Streaks") {
    StreaksSummarySection(dataProvider: PreviewStreakProvider(streaks: [
        PerAppStreakInfo(appLogicalID: "1", appName: "YouTube", iconURL: nil, token: nil, currentStreak: 5, daysToNextMilestone: 2, isAtRisk: false),
        PerAppStreakInfo(appLogicalID: "2", appName: "Roblox", iconURL: nil, token: nil, currentStreak: 3, daysToNextMilestone: 4, isAtRisk: true),
        PerAppStreakInfo(appLogicalID: "3", appName: "Minecraft", iconURL: nil, token: nil, currentStreak: 12, daysToNextMilestone: 2, isAtRisk: false)
    ]))
        .padding()
        .background(AppTheme.background(for: .light))
}

#Preview("No Streak-Enabled Apps") {
    StreaksSummarySection(dataProvider: PreviewStreakProvider(streaks: []))
        .padding()
        .background(AppTheme.background(for: .light))
}

// MARK: - Preview Helper

@MainActor
private final class PreviewStreakProvider: DashboardDataProvider {
    @Published var perAppStreaks: [PerAppStreakInfo]

    init(streaks: [PerAppStreakInfo]) {
        self.perAppStreaks = streaks
    }

    @Published var learningTimeSeconds: Int = 0
    @Published var rewardTimeSeconds: Int = 0
    @Published var learningAppDetails: [AppUsageDetail] = []
    @Published var rewardAppDetails: [AppUsageDetail] = []
    @Published var earnedMinutes: Int = 0
    @Published var usedMinutes: Int = 0
    @Published var streakBonusMinutes: Int = 0
    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var isStreakAtRisk: Bool = false
    @Published var streakProgress: Double = 0
    @Published var milestoneCycleDays: Int = 7
    @Published var potentialBonusMinutes: Int = 10
    @Published var dailyTotals: [DailyUsageTotals] = []
    @Published var isRemoteContext: Bool = false
    @Published var isLoading: Bool = false

    func refresh() async {}
}
