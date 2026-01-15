import SwiftUI
import Combine

/// Compact usage overview section with tap-to-expand drill-down.
/// Shows today's learning and reward time with tap actions to view per-app details.
struct UsageOverviewSection<Provider: DashboardDataProvider>: View {
    @ObservedObject var dataProvider: Provider

    @Environment(\.colorScheme) var colorScheme
    /// Single state variable for sheet - setting it triggers the sheet to present
    @State private var sheetCategory: AppUsageDetail.AppCategory?

    /// Check if we're in local context with access to snapshots
    private var localAdapter: LocalDashboardDataAdapter? {
        dataProvider as? LocalDashboardDataAdapter
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundColor(colorScheme == .light ? AppTheme.vibrantTeal : AppTheme.lightCream)

                Text("TODAY'S ACTIVITY")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(colorScheme == .light ? AppTheme.vibrantTeal : AppTheme.lightCream)

                Spacer()

                if dataProvider.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            // Usage cards
            HStack(spacing: 12) {
                // Learning Time Card - Tappable
                UsageStatCard(
                    icon: "book.fill",
                    label: "LEARNING",
                    minutes: dataProvider.learningTimeSeconds / 60,
                    color: AppTheme.vibrantTeal,
                    appCount: dataProvider.learningAppDetails.count
                ) {
                    #if DEBUG
                    print("[UsageOverviewSection] 📱 LEARNING card tapped")
                    print("[UsageOverviewSection]   isLocal: \(localAdapter != nil)")
                    print("[UsageOverviewSection]   learningAppDetails.count: \(dataProvider.learningAppDetails.count)")
                    print("[UsageOverviewSection]   rewardAppDetails.count: \(dataProvider.rewardAppDetails.count)")
                    print("[UsageOverviewSection]   isLoading: \(dataProvider.isLoading)")
                    #endif
                    sheetCategory = .learning  // Single state change triggers sheet
                }

                // Reward Time Card - Tappable
                UsageStatCard(
                    icon: "gamecontroller.fill",
                    label: "REWARD",
                    minutes: dataProvider.rewardTimeSeconds / 60,
                    color: AppTheme.playfulCoral,
                    appCount: dataProvider.rewardAppDetails.count
                ) {
                    #if DEBUG
                    print("[UsageOverviewSection] 🎮 REWARD card tapped")
                    print("[UsageOverviewSection]   isLocal: \(localAdapter != nil)")
                    print("[UsageOverviewSection]   learningAppDetails.count: \(dataProvider.learningAppDetails.count)")
                    print("[UsageOverviewSection]   rewardAppDetails.count: \(dataProvider.rewardAppDetails.count)")
                    print("[UsageOverviewSection]   isLoading: \(dataProvider.isLoading)")
                    #endif
                    sheetCategory = .reward  // Single state change triggers sheet
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
        )
        .sheet(item: $sheetCategory) { category in
            // category is guaranteed non-nil here - passed directly from the item binding
            // Use local sheet with tokens for child device, remote sheet with URLs for parent device
            if let adapter = localAdapter {
                // Child device: Use LocalAppUsageDetailSheet with actual app icons via tokens
                // Pass the adapter so the sheet observes data changes
                LocalAppUsageDetailSheet(
                    category: category == .learning ? .learning : .reward,
                    dataAdapter: adapter
                )
                .onAppear {
                    #if DEBUG
                    print("[UsageOverviewSection] 📋 LocalAppUsageDetailSheet appeared")
                    print("[UsageOverviewSection]   category: \(category)")
                    print("[UsageOverviewSection]   learningSnapshots.count: \(adapter.learningSnapshots.count)")
                    print("[UsageOverviewSection]   rewardSnapshots.count: \(adapter.rewardSnapshots.count)")
                    #endif
                }
            } else {
                // Parent device: Use AppUsageDetailSheet with CachedAppIcon
                // Pass the data provider so the sheet observes data changes
                AppUsageDetailSheet(
                    category: category,
                    dataProvider: dataProvider
                )
                .onAppear {
                    #if DEBUG
                    print("[UsageOverviewSection] 📋 AppUsageDetailSheet appeared")
                    print("[UsageOverviewSection]   category: \(category)")
                    print("[UsageOverviewSection]   learningAppDetails.count: \(dataProvider.learningAppDetails.count)")
                    print("[UsageOverviewSection]   rewardAppDetails.count: \(dataProvider.rewardAppDetails.count)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Usage Stat Card

private struct UsageStatCard: View {
    let icon: String
    let label: String
    let minutes: Int
    let color: Color
    let appCount: Int
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    /// Text color - only adjust teal for dark mode contrast, keep coral as-is
    private var textColor: Color {
        // Only fix contrast for teal (Learning card) in dark mode
        // Coral (Reward card) has good contrast and should stay coral
        if colorScheme == .dark && color == AppTheme.vibrantTeal {
            return AppTheme.lightCream
        }
        return color
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(textColor)

                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1)
                        .foregroundColor(textColor.opacity(0.8))

                    Spacer()

                    // Chevron indicator for drill-down
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textColor.opacity(0.5))
                }

                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(minutes)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(textColor)

                    Text("min")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(textColor.opacity(0.7))
                        .padding(.bottom, 4)
                }

                // App count hint
                Text("\(appCount) app\(appCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    UsageOverviewSection(dataProvider: PreviewDashboardDataProvider())
        .padding()
        .background(AppTheme.background(for: .light))
}

// MARK: - Preview Helper

@MainActor
private final class PreviewDashboardDataProvider: DashboardDataProvider {
    @Published var learningTimeSeconds: Int = 2400  // 40 min
    @Published var rewardTimeSeconds: Int = 900     // 15 min

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
