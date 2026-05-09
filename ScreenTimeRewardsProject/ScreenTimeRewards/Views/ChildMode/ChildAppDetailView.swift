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

    /// Mirrors `RewardUnlockCard.isUnlocked` so the dashboard card and detail view
    /// agree. Goal-unlocked apps (no manual session yet) appear unlocked on the
    /// card; without this alignment, the detail view would show "locked" and the
    /// "Complete these to unlock" header — a visible inconsistency.
    private var isUnlocked: Bool {
        let isManuallyUnlocked = unlockedApp != nil
        let isGoalUnlocked = BlockingCoordinator.shared.canUnlockApp(token: snapshot.token)
        return isManuallyUnlocked || isGoalUnlocked
    }

    /// Real reason this app is blocked. Surfaced so the LearningProgressCard
    /// header can show the actual cause (daily limit / downtime / …) instead of
    /// always saying "Finish your goal" — even when the goal is already met.
    private var blockingReason: BlockingReasonType? {
        BlockingCoordinator.shared.evaluateBlockingState(for: snapshot.token).primaryReason
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
            func estimatedRewardFor(_ app: LinkedLearningApp) -> Int {
                let schedule = AppScheduleService.shared.getSchedule(for: app.logicalID)
                let ratioL = schedule?.ratioLearningMinutes ?? 1
                let ratioR = schedule?.rewardMinutesEarned ?? 1
                guard ratioL > 0 else { return 0 }
                return (app.minutesRequired / ratioL) * ratioR
            }
            switch unlockMode {
            case .all:
                estimatedReward = linkedLearningApps.reduce(0) { $0 + estimatedRewardFor($1) }
            case .any:
                estimatedReward = linkedLearningApps.map { estimatedRewardFor($0) }.max() ?? 0
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
                        totalDailyLimit: dailyLimit,
                        usedMinutes: usedMinutes,
                        hasActiveSession: unlockedApp != nil
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
                        isUnlocked: isUnlocked,
                        blockingReason: blockingReason,
                        dailyLimit: dailyLimit
                    )

                    // 4. Time Bank Visualization — only meaningful when there's an
                    // active timed session (manual unlock with allocated minutes) AND
                    // a real per-app daily cap. Goal-unlocked-without-session has no
                    // allocation to visualize; dailyLimit >= 1440 means "no per-app
                    // cap" so the "X of 1440 min" ring is nonsense.
                    if unlockedApp != nil && dailyLimit > 0 && dailyLimit < 1440 {
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

                    // 6. Quick Stats — disabled. Was rendering hardcoded placeholders
                    // (4 days used / 25 min longest / 180 min earned) presented as
                    // real data. Re-enable when the underlying stats are wired up.
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
