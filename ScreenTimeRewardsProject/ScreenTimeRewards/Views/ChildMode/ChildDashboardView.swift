import SwiftUI
import FamilyControls
import ManagedSettings

/// Redesigned child dashboard with Time Bank metaphor
/// Shows learning apps as earning source and reward apps as spending destination
struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

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
    private var totalEarnedMinutes: Int {
        viewModel.availableLearningPoints + Int(totalRewardUsedSeconds / 60)
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
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xLarge) {
                    // Header with exit button
                    headerSection

                    // Hero Time Bank Card
                    TimeBankCard(
                        earnedMinutes: totalEarnedMinutes,
                        usedMinutes: totalUsedMinutes
                    )
                    .padding(.horizontal, AppTheme.Spacing.regular)

                    // Learning Apps Section
                    LearningAppListSection(
                        snapshots: viewModel.learningSnapshots,
                        totalSeconds: totalLearningSeconds
                    )
                    .padding(.horizontal, AppTheme.Spacing.regular)

                    // Reward Apps Section
                    RewardAppListSection(
                        snapshots: viewModel.rewardSnapshots,
                        remainingMinutes: remainingMinutes,
                        unlockedApps: viewModel.unlockedRewardApps
                    )
                    .padding(.horizontal, AppTheme.Spacing.regular)

                    // Empty state when no apps configured
                    if viewModel.learningSnapshots.isEmpty && viewModel.rewardSnapshots.isEmpty {
                        emptyStateView
                    }

                    Spacer(minLength: AppTheme.Spacing.huge)
                }
                .padding(.top, AppTheme.Spacing.regular)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            // Greeting with avatar
            HStack(spacing: 12) {
                // Avatar circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.vibrantTeal.opacity(0.3), AppTheme.playfulCoral.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.vibrantTeal)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingText)
                        .font(AppTheme.Typography.title3)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Ready to learn and play?")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            // Exit button
            Button {
                sessionManager.exitToSelection()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(AppTheme.vibrantTeal.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.regular)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good morning!"
        } else if hour < 17 {
            return "Good afternoon!"
        } else {
            return "Good evening!"
        }
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

            Text("Getting Started")
                .font(AppTheme.Typography.title2)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Ask a parent to set up your learning and reward apps to start earning play time!")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
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
