import SwiftUI
import FamilyControls
import ManagedSettings

/// Redesigned child dashboard with Time Bank metaphor
/// Shows learning apps as earning source and reward apps as spending destination
struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var avatarService = AvatarService.shared
    @Environment(\.colorScheme) var colorScheme

    // Design colors matching ModeSelectionView
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
    // Very light coral for background (Pastel Pink/Peach)
    private let veryLightCoral = Color(red: 1.0, green: 0.94, blue: 0.92)
    private let accentYellow = Color(red: 0.98, green: 0.80, blue: 0.30)

    @State private var showAvatarCustomization = false

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

            ScrollView {
                VStack(spacing: 24) {
                    // Header with exit button
                    headerSection

                    // Avatar Hero Section
                    AvatarHeroSection(
                        avatarService: avatarService,
                        onAvatarTap: {
                            showAvatarCustomization = true
                        }
                    )

                    // Hero Time Bank Card
                    TimeBankCard(
                        earnedMinutes: totalEarnedMinutes,
                        usedMinutes: totalUsedMinutes
                    )
                    .padding(.horizontal, 16)

                    // Learning Apps Section
                    LearningAppListSection(
                        snapshots: viewModel.learningSnapshots,
                        totalSeconds: totalLearningSeconds
                    )
                    .padding(.horizontal, 16)

                    // Reward Apps Section
                    RewardAppListSection(
                        snapshots: viewModel.rewardSnapshots,
                        remainingMinutes: remainingMinutes,
                        unlockedApps: viewModel.unlockedRewardApps
                    )
                    .padding(.horizontal, 16)

                    // Empty state when no apps configured
                    if viewModel.learningSnapshots.isEmpty && viewModel.rewardSnapshots.isEmpty {
                        emptyStateView
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            // Load avatar state when view appears
            let deviceID = DeviceModeManager.shared.deviceID
            await avatarService.loadAvatarState(for: deviceID)
        }
        .sheet(isPresented: $showAvatarCustomization) {
            AvatarCustomizationView(avatarService: avatarService)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            // Greeting with small avatar
            HStack(spacing: 12) {
                // Small avatar
                AvatarView(
                    avatarState: avatarService.currentAvatarState,
                    size: .small,
                    showMood: false,
                    isInteractive: false
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingText)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tealColor)

                    Text("Ready to learn and play?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(tealColor.opacity(0.8))
                }
            }

            Spacer()

            // Exit button
            Button {
                sessionManager.exitToSelection()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tealColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tealColor.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 16)
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
