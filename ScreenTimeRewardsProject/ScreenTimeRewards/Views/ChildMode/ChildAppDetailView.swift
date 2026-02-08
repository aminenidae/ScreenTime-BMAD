import SwiftUI
import FamilyControls
import ManagedSettings

struct ChildAppDetailView: View {
    let snapshot: RewardAppSnapshot
    let unlockedApp: UnlockedRewardApp?
    let linkedLearningApps: [LinkedLearningApp]
    let learningProgress: [String: (used: Int, required: Int, goalMet: Bool)]
    let learningAppTokens: [String: ApplicationToken]
    let unlockMode: UnlockMode
    let streakSettings: AppStreakSettings?
    let dailyLimit: Int
    let previousDayUsage: Int?

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var streakService = StreakService.shared

    @State private var showMilestoneCelebration = false
    @State private var achievedMilestone: Int = 0
    @State private var milestoneBonus: Int = 0

    private var isUnlocked: Bool {
        unlockedApp != nil
    }

    private var remainingMinutes: Int {
        unlockedApp?.remainingMinutes ?? 0
    }

    private var usedMinutes: Int {
        Int(snapshot.totalSeconds / 60)
    }

    private var streakData: (current: Int, longest: Int, nextMilestone: Int?, progress: Double, bonusEarned: Int)? {
        guard let settings = streakSettings, settings.isEnabled else { return nil }
        
        let logicalID = snapshot.logicalID
        guard let record = streakService.streakRecords[logicalID] else {
            // If settings enabled but no record yet, show empty/zero state
            return (0, 0, streakService.getNextMilestone(for: 0, settings: settings), 0.0, 0)
        }
        
        let current = Int(record.currentStreak)
        let longest = Int(record.longestStreak)
        let nextMilestone = streakService.getNextMilestone(for: current, settings: settings)
        let progress = streakService.progressToNextMilestone(current: current, settings: settings)
        let bonusEarned = streakService.getTotalBonusMinutes(for: logicalID)
        
        return (current, longest, nextMilestone, progress, bonusEarned)
    }

    private var potentialBonusMinutes: Int {
        guard let settings = streakSettings, settings.isEnabled else { return 0 }
        
        let multiplier = Double(settings.streakCycleDays)
        var totalBonus = 0
        
        switch settings.bonusType {
        case .percentage:
            // Calculate estimated reward basis
            var estimatedReward = 0
            switch unlockMode {
            case .all:
                estimatedReward = linkedLearningApps.reduce(0) { $0 + $1.rewardMinutesEarned }
            case .any:
                estimatedReward = linkedLearningApps.map { $0.rewardMinutesEarned }.max() ?? 0
            }
            
            // (Daily Reward * Percentage) * Cycle Days
            let dailyBonus = Double(estimatedReward) * (Double(settings.bonusValue) / 100.0)
            totalBonus = Int(dailyBonus * multiplier)
            
        case .fixedMinutes:
            // Fixed Amount * Cycle Days
            totalBonus = Int(Double(settings.bonusValue) * multiplier)
        }
        
        return totalBonus
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Hero Header
                    AppHeroHeaderCard(
                        appName: snapshot.displayName,
                        token: snapshot.token,
                        isUnlocked: isUnlocked,
                        remainingMinutes: remainingMinutes,
                        totalDailyLimit: dailyLimit
                    )

                    // 2. Streak Progress (if enabled for this app)
                    if let streakData = streakData, let settings = streakSettings {
                        ChildAppStreakCard(
                            currentStreak: streakData.current,
                            longestStreak: streakData.longest,
                            nextMilestone: streakData.nextMilestone,
                            progress: streakData.progress,
                            milestoneCycleDays: settings.streakCycleDays,
                            isAtRisk: streakService.streakRecords[snapshot.logicalID]?.isAtRisk ?? false,
                            potentialBonus: potentialBonusMinutes
                        )
                    }

                    // 3. Unlock Requirements (Learning Progress)
                    LearningProgressCard(
                        linkedLearningApps: linkedLearningApps,
                        learningProgress: learningProgress,
                        learningAppTokens: learningAppTokens,
                        unlockMode: unlockMode,
                        isUnlocked: isUnlocked
                    )

                    // 4. Time Bank Visualization
                    if isUnlocked {
                        TimeBankVisualizationCard(
                            remainingMinutes: remainingMinutes,
                            dailyLimit: dailyLimit,
                            usedMinutes: usedMinutes
                        )
                    }

                    // 5. Usage Today (if unlocked)
                    if isUnlocked && usedMinutes > 0 {
                        UsageTodayCard(
                            usedMinutes: usedMinutes,
                            previousDayUsage: previousDayUsage
                        )
                    }

                    // 6. Quick Stats (optional)
                    if isUnlocked {
                        QuickStatsCard(
                            daysUsedThisWeek: 4, // Would be calculated in real implementation
                            longestSessionMinutes: 25, // Would be calculated in real implementation
                            totalEarnedThisMonth: 180 // Would be calculated in real implementation
                        )
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("BACK")
                                .font(.system(size: 14, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundColor(AppTheme.playfulCoral)
                    }
                }
            }
            .overlay {
                if showMilestoneCelebration {
                    StreakMilestoneCelebration(
                        milestone: achievedMilestone,
                        bonusMinutes: milestoneBonus,
                        appName: snapshot.displayName,
                        isPresented: $showMilestoneCelebration
                    )
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(999)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .streakMilestoneAchieved)) { notification in
            if let milestone = notification.userInfo?["milestone"] as? Int,
               let bonus = notification.userInfo?["bonusMinutes"] as? Int,
               let appLogicalID = notification.userInfo?["appLogicalID"] as? String,
               appLogicalID == snapshot.logicalID {

                achievedMilestone = milestone
                milestoneBonus = bonus

                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showMilestoneCelebration = true
                }
            }
        }
        .onAppear {
            // Ensure streaks are loaded
            StreakService.shared.loadStreaksForChild(childDeviceID: DeviceModeManager.shared.deviceID)
        }
    }
}
