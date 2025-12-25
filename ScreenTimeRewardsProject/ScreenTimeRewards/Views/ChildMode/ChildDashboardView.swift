import SwiftUI
import FamilyControls
import ManagedSettings

/// Redesigned child dashboard with Time Bank metaphor
/// Shows learning apps as earning source and reward apps as spending destination
struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

    @StateObject private var streakService = StreakService.shared
    @State private var showMilestoneCelebration = false
    @State private var achievedMilestone: Int = 0
    @State private var milestoneBonus: Int = 0
    @State private var milestoneAppName: String = ""

    // Design colors matching ModeSelectionView
    
    
    
    // Very light coral for background (Pastel Pink/Peach)
    
    

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

    private var aggregateStreak: (current: Int, longest: Int, isAtRisk: Bool) {
        streakService.getAggregateStreak(for: DeviceModeManager.shared.deviceID)
    }

    private var appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)] {
        viewModel.rewardSnapshots.compactMap { snapshot -> (String, Int, Bool)? in
            guard let record = streakService.streakRecords[snapshot.logicalID] else { return nil }
            return (snapshot.displayName, Int(record.currentStreak), record.isAtRisk)
        }
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
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
                        
                        // Streak Card
                        let deviceID = DeviceModeManager.shared.deviceID
                        let aggregate = streakService.getAggregateStreak(for: deviceID)
                        
                        // Get settings from app with highest streak for progress calculation
                        let highestAppID = streakService.streakRecords
                            .max(by: { $0.value.currentStreak < $1.value.currentStreak })?
                            .key
                        
                        let streakSettings = highestAppID.flatMap { appID in
                            AppScheduleService.shared.getSchedule(for: appID)?.streakSettings
                        }
                        
                        ChildStreakCard(
                            aggregateStreak: aggregate,
                            appStreaks: appStreaks,
                            nextMilestone: streakService.getNextMilestone(
                                for: aggregate.current,
                                settings: streakSettings ?? .defaultSettings
                            ),
                            progress: streakService.progressToNextMilestone(
                                current: aggregate.current,
                                settings: streakSettings ?? .defaultSettings
                            ),
                            hasAnyStreaksEnabled: !streakService.streakRecords.isEmpty
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
        .onAppear {
            streakService.loadStreaksForChild(childDeviceID: DeviceModeManager.shared.deviceID)
        }
        .overlay {
            if showMilestoneCelebration {
                StreakMilestoneCelebration(
                    milestone: achievedMilestone,
                    bonusMinutes: milestoneBonus,
                    appName: milestoneAppName,
                    isPresented: $showMilestoneCelebration
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(999)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .streakMilestoneAchieved)) { notification in
            if let milestone = notification.userInfo?["milestone"] as? Int,
               let bonus = notification.userInfo?["bonusMinutes"] as? Int,
               let appLogicalID = notification.userInfo?["appLogicalID"] as? String {
                
                achievedMilestone = milestone
                milestoneBonus = bonus
                
                // Get app name from logicalID
                if let appName = viewModel.rewardSnapshots
                    .first(where: { $0.logicalID == appLogicalID })?.displayName {
                    milestoneAppName = appName
                } else {
                    milestoneAppName = "App"
                }
                
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showMilestoneCelebration = true
                }
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
                        .foregroundColor(AppTheme.vibrantTeal)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.vibrantTeal.opacity(0.1))
                        )
                }

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
                .fill(AppTheme.vibrantTeal.opacity(0.15))
                .frame(height: 1)
        }
        .background(AppTheme.background(for: colorScheme))
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
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Ask a parent to set up your learning and reward apps to start earning play time!")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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
