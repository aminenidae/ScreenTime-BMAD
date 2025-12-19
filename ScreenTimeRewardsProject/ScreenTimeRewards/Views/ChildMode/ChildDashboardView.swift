import SwiftUI
import FamilyControls
import ManagedSettings

/// Redesigned child dashboard with Time Bank metaphor
/// Shows learning apps as earning source and reward apps as spending destination
struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

    // Design colors matching ModeSelectionView
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
    // Very light coral for background (Pastel Pink/Peach)
    private let veryLightCoral = Color(red: 1.0, green: 0.94, blue: 0.92)
    private let accentYellow = Color(red: 0.98, green: 0.80, blue: 0.30)

    // MARK: - Computed Properties

    /// Total learning time today (in seconds)
    private var totalLearningSeconds: TimeInterval {
        viewModel.learningSnapshots.reduce(0) { $0 + $1.totalSeconds }
    }

    /// Total reward time used today (in seconds)
    private var totalRewardUsedSeconds: TimeInterval {
        viewModel.rewardSnapshots.reduce(0) { $0 + $1.totalSeconds }
    }

    /// Total earned reward minutes (from linked learning goals)
    /// This is the total earned from learning - does NOT include reward app usage
    private var totalEarnedMinutes: Int {
        viewModel.totalEarnedMinutes
    }

    /// Total reward minutes used
    private var totalUsedMinutes: Int {
        Int(totalRewardUsedSeconds / 60)
    }

    /// Remaining reward minutes
    private var remainingMinutes: Int {
        viewModel.availableLearningPoints
    }

    var body: some View {
        ZStack {
            // Background
            veryLightCoral
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with exit button
                headerSection

                ScrollView {
                    VStack(spacing: 16) {
                        // Hero Time Bank Card
                        TimeBankCard(
                            earnedMinutes: totalEarnedMinutes,
                            usedMinutes: totalUsedMinutes
                        )

                        // Learning Apps Section
                        LearningAppListSection(
                            snapshots: viewModel.learningSnapshots,
                            totalSeconds: totalLearningSeconds
                        )

                        // Reward Apps Section
                        RewardAppListSection(
                            snapshots: viewModel.rewardSnapshots,
                            remainingMinutes: remainingMinutes,
                            unlockedApps: viewModel.unlockedRewardApps
                        )

                        // Empty state when no apps configured
                        if viewModel.learningSnapshots.isEmpty && viewModel.rewardSnapshots.isEmpty {
                            emptyStateView
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    sessionManager.exitToSelection()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tealColor)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(tealColor.opacity(0.1))
                        )
                }

                Spacer()

                Text("DASHBOARD")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                    .foregroundColor(tealColor)

                Spacer()

                // Invisible spacer for balance
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Rectangle()
                .fill(tealColor.opacity(0.15))
                .frame(height: 1)
        }
        .background(veryLightCoral)
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.regular) {
            // Friendly illustration
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.vibrantTeal.opacity(0.1), AppTheme.playfulCoral.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            Text("GETTING STARTED")
                .font(.system(size: 28, weight: .bold))
                .tracking(3)
                .foregroundColor(tealColor)

            Text("Ask a parent to set up your learning and reward apps to start earning play time!")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tealColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, AppTheme.Spacing.huge)
    }
}

// MARK: - Preview

#Preview("With Data") {
    ChildDashboardView()
        .environmentObject(AppUsageViewModel())
        .environmentObject(SessionManager.shared)
}

#Preview("Dark Mode") {
    ChildDashboardView()
        .environmentObject(AppUsageViewModel())
        .environmentObject(SessionManager.shared)
        .preferredColorScheme(.dark)
}
