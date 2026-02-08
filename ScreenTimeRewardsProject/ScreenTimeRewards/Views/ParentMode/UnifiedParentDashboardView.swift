import SwiftUI
import Combine

/// Unified parent dashboard view that works with any DashboardDataProvider.
/// Used for both local (child device) and remote (parent device) contexts.
struct UnifiedParentDashboardView<Provider: DashboardDataProvider>: View {
    @ObservedObject var dataProvider: Provider

    /// Optional header view for context-specific headers
    var headerView: AnyView?

    /// Whether to show the exit button (for local context)
    var showExitButton: Bool = false

    /// Action for exit button
    var onExit: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                if let headerView = headerView {
                    headerView
                } else if showExitButton {
                    defaultHeader
                }

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Section 1: Usage Overview (with drill-down)
                        UsageOverviewSection(dataProvider: dataProvider)

                        // Section 2: Time Bank
                        TimeBankCard(
                            earnedMinutes: dataProvider.earnedMinutes + dataProvider.streakBonusMinutes,
                            usedMinutes: dataProvider.usedMinutes
                        )

                        // Section 3: Streaks Summary
                        StreaksSummarySection(dataProvider: dataProvider)

                        // Section 4: Daily/Weekly Trends
                        // Note: The chart is separate since it needs different data access
                        // For local context, we'll use DailyUsageChartCard with EnvironmentObject
                        // For remote context, we'll need a unified chart

                        // Bottom padding
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .refreshable {
            await dataProvider.refresh()
        }
    }

    // MARK: - Default Header (for local context)

    private var defaultHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    onExit?()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.vibrantTeal.opacity(0.1))
                        )
                }
                .accessibilityLabel("Go back")

                Spacer()

                Text("DASHBOARD")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Invisible spacer for balance
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Rectangle()
                .fill(AppTheme.border(for: colorScheme))
                .frame(height: 1)
        }
        .background(AppTheme.background(for: colorScheme))
    }
}

// MARK: - View Extension for Chart Integration

extension UnifiedParentDashboardView {
    /// Adds a chart view below the streaks section
    func withChart<ChartView: View>(@ViewBuilder chart: () -> ChartView) -> some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let headerView = headerView {
                    headerView
                } else if showExitButton {
                    defaultHeader
                }

                ScrollView {
                    VStack(spacing: 16) {
                        UsageOverviewSection(dataProvider: dataProvider)

                        TimeBankCard(
                            earnedMinutes: dataProvider.earnedMinutes + dataProvider.streakBonusMinutes,
                            usedMinutes: dataProvider.usedMinutes
                        )

                        StreaksSummarySection(dataProvider: dataProvider)

                        // Chart section
                        chart()

                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .refreshable {
            Task {
                await dataProvider.refresh()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    UnifiedParentDashboardView(
        dataProvider: PreviewUnifiedDashboardDataProvider(),
        showExitButton: true,
        onExit: {}
    )
}

// MARK: - Preview Helper

@MainActor
private final class PreviewUnifiedDashboardDataProvider: DashboardDataProvider {
    @Published var learningTimeSeconds: Int = 2400
    @Published var rewardTimeSeconds: Int = 900

    @Published var learningAppDetails: [AppUsageDetail] = [
        AppUsageDetail(id: "1", displayName: "Duolingo", category: .learning, todaySeconds: 1200, iconURL: nil, pointsPerMinute: 2, earnedPoints: 40),
        AppUsageDetail(id: "2", displayName: "Khan Academy", category: .learning, todaySeconds: 1200, iconURL: nil, pointsPerMinute: 2, earnedPoints: 40)
    ]

    @Published var rewardAppDetails: [AppUsageDetail] = [
        AppUsageDetail(id: "3", displayName: "YouTube", category: .reward, todaySeconds: 900, iconURL: nil, pointsPerMinute: 1, earnedPoints: 15)
    ]

    @Published var earnedMinutes: Int = 40
    @Published var usedMinutes: Int = 15
    @Published var streakBonusMinutes: Int = 5

    @Published var currentStreak: Int = 5
    @Published var longestStreak: Int = 12
    @Published var isStreakAtRisk: Bool = false
    @Published var streakProgress: Double = 0.7
    @Published var milestoneCycleDays: Int = 7
    @Published var potentialBonusMinutes: Int = 10

    @Published var dailyTotals: [DailyUsageTotals] = []

    @Published var isRemoteContext: Bool = false
    @Published var isLoading: Bool = false

    func refresh() async {}
}
