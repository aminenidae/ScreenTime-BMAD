import SwiftUI
import FamilyControls

struct ChildAppDetailView: View {
    let snapshot: RewardAppSnapshot
    let unlockedApp: UnlockedRewardApp?
    let linkedLearningApps: [LinkedLearningApp]
    let learningProgress: [String: (used: Int, required: Int, goalMet: Bool)]
    let unlockMode: UnlockMode
    let streakData: (current: Int, longest: Int, nextMilestone: Int?, progress: Double, bonusEarned: Int)?
    let dailyLimit: Int
    let previousDayUsage: Int?

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var isUnlocked: Bool {
        unlockedApp != nil
    }

    private var remainingMinutes: Int {
        unlockedApp?.remainingMinutes ?? 0
    }

    private var usedMinutes: Int {
        Int(snapshot.totalSeconds / 60)
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

                    // 2. Learning Progress (Most Important!)
                    LearningProgressCard(
                        linkedLearningApps: linkedLearningApps,
                        learningProgress: learningProgress,
                        unlockMode: unlockMode,
                        isUnlocked: isUnlocked
                    )

                    // 3. Streak Progress (if enabled for this app)
                    if let streakData = streakData {
                        AppStreakCard(
                            currentStreak: streakData.current,
                            longestStreak: streakData.longest,
                            nextMilestone: streakData.nextMilestone,
                            bonusMinutesEarned: streakData.bonusEarned,
                            progress: streakData.progress
                        )
                    }

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
        }
        .onAppear {
            // Ensure streaks are loaded
            StreakService.shared.loadStreaksForChild(childDeviceID: DeviceModeManager.shared.deviceID)
        }
    }
}
