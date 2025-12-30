import Foundation
import ManagedSettings
import Combine

/// Result of evaluating blocking state for an app
struct BlockingDecision {
    let shouldBlock: Bool
    let primaryReason: BlockingReasonType?
    let allActiveReasons: Set<BlockingReasonType>

    // Context data for the primary reason
    // Downtime - full allowed time window
    var downtimeWindowStartHour: Int?
    var downtimeWindowStartMinute: Int?
    var downtimeWindowEndHour: Int?
    var downtimeWindowEndMinute: Int?
    var downtimeDayName: String?
    var downtimeSummaryMessage: String?

    // Daily limit
    var dailyLimitMinutes: Int?
    var usedMinutes: Int?

    // Learning goal
    var learningTargetMinutes: Int?
    var learningCurrentMinutes: Int?

    static let unblocked = BlockingDecision(
        shouldBlock: false,
        primaryReason: nil,
        allActiveReasons: []
    )
}

/// Coordinates blocking decisions and ensures BlockingReasonService is called
/// before shields are applied. Determines WHY an app is blocked and persists
/// that reason for the ShieldConfigurationExtension to display.
@MainActor
class BlockingCoordinator: ObservableObject {
    static let shared = BlockingCoordinator()

    // MARK: - Dependencies

    private let blockingReasonService = BlockingReasonService.shared
    private let scheduleService = AppScheduleService.shared
    private let appGroupID = "group.com.screentimerewards.shared"

    // Weak reference to avoid retain cycle - will be set by ScreenTimeService
    private weak var screenTimeService: ScreenTimeService?

    // MARK: - Refresh Timer

    private var refreshTimer: Timer?
    private var currentRewardTokens: Set<ApplicationToken> = []

    // MARK: - Initialization

    private init() {}

    /// Set the screen time service (call this from ScreenTimeService.init)
    func setScreenTimeService(_ service: ScreenTimeService) {
        self.screenTimeService = service
    }

    // MARK: - Core Decision Logic

    /// Evaluate blocking state for a single app
    /// Returns whether it should be blocked and why
    func evaluateBlockingState(for token: ApplicationToken) -> BlockingDecision {
        guard let service = screenTimeService else {
            return .unblocked
        }

        guard let logicalID = service.getLogicalID(for: token) else {
            // Unknown app - default to learning goal blocking
            return BlockingDecision(
                shouldBlock: true,
                primaryReason: .learningGoal,
                allActiveReasons: [.learningGoal],
                learningTargetMinutes: 15,
                learningCurrentMinutes: 0
            )
        }

        var activeReasons: Set<BlockingReasonType> = []
        var decision = BlockingDecision.unblocked

        // 1. Check Downtime (Priority 1 - Highest)
        let downtimeCheck = checkDowntime(logicalID: logicalID)
        if downtimeCheck.isInDowntime {
            activeReasons.insert(.downtime)
            decision.downtimeWindowStartHour = downtimeCheck.windowStartHour
            decision.downtimeWindowStartMinute = downtimeCheck.windowStartMinute
            decision.downtimeWindowEndHour = downtimeCheck.windowEndHour
            decision.downtimeWindowEndMinute = downtimeCheck.windowEndMinute
            decision.downtimeDayName = downtimeCheck.dayName
            decision.downtimeSummaryMessage = downtimeCheck.summaryMessage
        }

        // 2. Check Daily Limit (Priority 2)
        let limitCheck = checkDailyLimit(logicalID: logicalID)
        if limitCheck.isOverLimit {
            activeReasons.insert(.dailyLimitReached)
            decision.dailyLimitMinutes = limitCheck.limitMinutes
            decision.usedMinutes = limitCheck.usedMinutes
        }

        // 3. Check Learning Goal (Priority 3 - Lowest)
        let learningCheck = checkLearningGoal(logicalID: logicalID)
        if !learningCheck.isGoalMet {
            activeReasons.insert(.learningGoal)
            decision.learningTargetMinutes = learningCheck.targetMinutes
            decision.learningCurrentMinutes = learningCheck.currentMinutes
        }

        // Determine if blocked (any active reason)
        let shouldBlock = !activeReasons.isEmpty

        // Determine primary reason (highest priority)
        var primaryReason: BlockingReasonType?
        if activeReasons.contains(.downtime) {
            primaryReason = .downtime
        } else if activeReasons.contains(.dailyLimitReached) {
            primaryReason = .dailyLimitReached
        } else if activeReasons.contains(.learningGoal) {
            primaryReason = .learningGoal
        }

        return BlockingDecision(
            shouldBlock: shouldBlock,
            primaryReason: primaryReason,
            allActiveReasons: activeReasons,
            downtimeWindowStartHour: decision.downtimeWindowStartHour,
            downtimeWindowStartMinute: decision.downtimeWindowStartMinute,
            downtimeWindowEndHour: decision.downtimeWindowEndHour,
            downtimeWindowEndMinute: decision.downtimeWindowEndMinute,
            downtimeDayName: decision.downtimeDayName,
            downtimeSummaryMessage: decision.downtimeSummaryMessage,
            dailyLimitMinutes: decision.dailyLimitMinutes,
            usedMinutes: decision.usedMinutes,
            learningTargetMinutes: decision.learningTargetMinutes,
            learningCurrentMinutes: decision.learningCurrentMinutes
        )
    }

    /// Check if app can be unlocked (all conditions clear)
    func canUnlockApp(token: ApplicationToken) -> Bool {
        let decision = evaluateBlockingState(for: token)
        return !decision.shouldBlock
    }

    /// Get the reward minutes earned for a specific reward app based on its linked learning goals
    /// Returns 0 if goals are not met, otherwise returns the configured rewardMinutesEarned
    func getEarnedRewardMinutes(for token: ApplicationToken) -> Int {
        guard let service = screenTimeService,
              let logicalID = service.getLogicalID(for: token) else {
            return 0
        }
        let learningCheck = checkLearningGoal(logicalID: logicalID)
        return learningCheck.rewardMinutesEarned
    }

    /// Get total earned reward minutes across all reward apps
    func getTotalEarnedRewardMinutes(for tokens: Set<ApplicationToken>) -> Int {
        var total = 0
        for token in tokens {
            total += getEarnedRewardMinutes(for: token)
        }
        return total
    }

    // MARK: - Condition Checks

    private struct DowntimeCheckResult {
        let isInDowntime: Bool
        // Full allowed time window
        let windowStartHour: Int?
        let windowStartMinute: Int?
        let windowEndHour: Int?
        let windowEndMinute: Int?
        let dayName: String?
        let summaryMessage: String?

        static func notInDowntime() -> DowntimeCheckResult {
            DowntimeCheckResult(
                isInDowntime: false,
                windowStartHour: nil,
                windowStartMinute: nil,
                windowEndHour: nil,
                windowEndMinute: nil,
                dayName: nil,
                summaryMessage: nil
            )
        }
    }

    /// Get current day name (e.g., "Monday", "Tuesday")
    private func getCurrentDayName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"  // Full day name
        return formatter.string(from: Date())
    }

    private func checkDowntime(logicalID: String) -> DowntimeCheckResult {
        guard let config = scheduleService.getSchedule(for: logicalID) else {
            // No schedule = no downtime
            return .notInDowntime()
        }

        guard config.isEnabled else {
            // Disabled schedule = no restrictions
            return .notInDowntime()
        }

        let todayWindow = config.todayTimeWindow

        // Full day access = no downtime
        if todayWindow.isFullDay {
            return .notInDowntime()
        }

        // Check if current time is within the allowed window
        if todayWindow.contains(date: Date()) {
            return .notInDowntime()
        }

        // Outside allowed window = in downtime
        // Generate summary message using the same logic as AppConfigurationSheet
        let summaryMessage = generateConfigSummary(config: config)

        // Return the full allowed time window for display
        return DowntimeCheckResult(
            isInDowntime: true,
            windowStartHour: todayWindow.startHour,
            windowStartMinute: todayWindow.startMinute,
            windowEndHour: todayWindow.endHour,
            windowEndMinute: todayWindow.endMinute,
            dayName: getCurrentDayName(),
            summaryMessage: summaryMessage
        )
    }

    // MARK: - Summary Message Generation (mirrors AppConfigurationSheet)

    /// Generate a summary message for the app's schedule configuration
    /// This matches the Summary card format in AppConfigurationSheet
    private func generateConfigSummary(config: AppScheduleConfiguration) -> String {
        let limits = config.dailyLimits
        let useAdvancedTime = config.useAdvancedTimeWindowConfig
        let useAdvancedLimits = config.useAdvancedDayConfig

        // If either time windows or limits are per-day, use smart grouping
        if useAdvancedTime || useAdvancedLimits {
            return buildSmartSummary(config: config, limits: limits, useAdvancedTime: useAdvancedTime)
        }

        // Simple mode
        let timeWindow = config.allowedTimeWindow
        let timeRange = timeWindow.isFullDay ? "anytime" : "between \(formatTime(hour: timeWindow.startHour, minute: timeWindow.startMinute)) and \(formatTime(hour: timeWindow.endHour, minute: timeWindow.endMinute))"

        if limits.weekdayLimit == limits.weekendLimit {
            // 1 line - same for all days
            return formatFullLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange)
        } else {
            // 2 lines - weekday vs weekend
            let weekdayLine = "Weekdays (Mon-Fri): \(formatUsageLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange))"
            let weekendLine = "Weekends (Sat-Sun): \(formatUsageLine(limits.weekendLimit, timeWindow: timeWindow, timeRange: timeRange))"
            return "\(weekdayLine)\n\(weekendLine)"
        }
    }

    /// Build smart summary that groups days with identical settings
    private func buildSmartSummary(config: AppScheduleConfiguration, limits: DailyLimits, useAdvancedTime: Bool) -> String {
        // Helper to get config key for a day (combines time window + limit)
        func configKey(for weekday: Int) -> String {
            let window = useAdvancedTime ? config.dailyTimeWindows.window(for: weekday) : config.allowedTimeWindow
            let limit = limits.limit(for: weekday)
            return "\(window.startHour):\(window.startMinute)-\(window.endHour):\(window.endMinute)|\(limit)"
        }

        // Helper to format a day's summary
        func summaryFor(weekday: Int) -> String {
            let window = useAdvancedTime ? config.dailyTimeWindows.window(for: weekday) : config.allowedTimeWindow
            let limitMinutes = limits.limit(for: weekday)
            let timeRange = window.isFullDay ? "anytime" : "between \(formatTime(hour: window.startHour, minute: window.startMinute)) and \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return formatUsageLine(limitMinutes, timeWindow: window, timeRange: timeRange)
        }

        // Check if all weekdays (Mon-Fri: 2-6) are the same
        let weekdayKeys = (2...6).map { configKey(for: $0) }
        let allWeekdaysSame = Set(weekdayKeys).count == 1

        // Check if both weekend days (Sat: 7, Sun: 1) are the same
        let satKey = configKey(for: 7)
        let sunKey = configKey(for: 1)
        let weekendSame = satKey == sunKey

        // Check if everything is the same
        let allKeys = (1...7).map { configKey(for: $0) }
        if Set(allKeys).count == 1 {
            // All 7 days identical - show 1 line
            let window = useAdvancedTime ? config.dailyTimeWindows.window(for: 2) : config.allowedTimeWindow
            let timeRange = window.isFullDay ? "anytime" : "between \(formatTime(hour: window.startHour, minute: window.startMinute)) and \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return formatFullLine(limits.limit(for: 2), timeWindow: window, timeRange: timeRange)
        }

        // Check if weekdays same AND weekends same (classic pattern)
        if allWeekdaysSame && weekendSame {
            let weekdayLine = "Weekdays (Mon-Fri): \(summaryFor(weekday: 2))"
            let weekendLine = "Weekends (Sat-Sun): \(summaryFor(weekday: 7))"
            return "\(weekdayLine)\n\(weekendLine)"
        }

        var lines: [String] = []

        // Weekdays: show grouped or individual
        if allWeekdaysSame {
            lines.append("Weekdays (Mon-Fri): \(summaryFor(weekday: 2))")
        } else {
            // Show individual weekdays
            for weekday in 2...6 {
                lines.append("\(dayName(for: weekday)): \(summaryFor(weekday: weekday))")
            }
        }

        // Weekend: show grouped or individual
        if weekendSame {
            lines.append("Weekends (Sat-Sun): \(summaryFor(weekday: 7))")
        } else {
            lines.append("Saturday: \(summaryFor(weekday: 7))")
            lines.append("Sunday: \(summaryFor(weekday: 1))")
        }

        return lines.joined(separator: "\n")
    }

    private func formatFullLine(_ minutes: Int, timeWindow: AllowedTimeWindow, timeRange: String) -> String {
        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            if timeWindow.isFullDay {
                return "Available anytime"
            } else {
                return "Available \(timeRange)"
            }
        } else {
            return "Available for \(formatDuration(minutes)) \(timeRange)"
        }
    }

    private func formatUsageLine(_ minutes: Int, timeWindow: AllowedTimeWindow, timeRange: String) -> String {
        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            return timeRange
        } else {
            return "\(formatDuration(minutes)) \(timeRange)"
        }
    }

    private func dayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return ""
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 1440 {
            return "unlimited"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        if minute == 0 {
            return "\(displayHour) \(period)"
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    private struct DailyLimitCheckResult {
        let isOverLimit: Bool
        let limitMinutes: Int?
        let usedMinutes: Int?
    }

    private func checkDailyLimit(logicalID: String) -> DailyLimitCheckResult {
        guard let config = scheduleService.getSchedule(for: logicalID) else {
            // No schedule = no limit
            return DailyLimitCheckResult(isOverLimit: false, limitMinutes: nil, usedMinutes: nil)
        }

        let todayLimit = config.dailyLimits.todayLimit

        // 1440 minutes = 24 hours = unlimited
        if todayLimit >= 1440 {
            return DailyLimitCheckResult(isOverLimit: false, limitMinutes: nil, usedMinutes: nil)
        }

        // Get today's usage from App Group
        let usedMinutes = getTodayUsageMinutes(for: logicalID)

        if usedMinutes >= todayLimit {
            return DailyLimitCheckResult(
                isOverLimit: true,
                limitMinutes: todayLimit,
                usedMinutes: usedMinutes
            )
        }

        return DailyLimitCheckResult(isOverLimit: false, limitMinutes: nil, usedMinutes: nil)
    }

    private struct LearningGoalCheckResult {
        let isGoalMet: Bool
        let targetMinutes: Int
        let currentMinutes: Int
        let rewardMinutesEarned: Int  // Reward minutes earned when goal is met
    }

    private func checkLearningGoal(logicalID: String) -> LearningGoalCheckResult {
        guard let config = scheduleService.getSchedule(for: logicalID) else {
            // No schedule = default learning requirement
            return LearningGoalCheckResult(isGoalMet: false, targetMinutes: 15, currentMinutes: 0, rewardMinutesEarned: 0)
        }

        let linkedApps = config.linkedLearningApps

        // No linked learning apps = goal is met (no requirement, no reward)
        if linkedApps.isEmpty {
            return LearningGoalCheckResult(isGoalMet: true, targetMinutes: 0, currentMinutes: 0, rewardMinutesEarned: 0)
        }

        // Calculate total required, current progress, and reward earned
        var totalTarget = 0
        var totalCurrent = 0
        var totalRewardEarned = 0

        switch config.unlockMode {
        case .all:
            // Must complete ALL linked apps - sum all rewards when ALL goals met
            var allGoalsMet = true
            for linkedApp in linkedApps {
                totalTarget += linkedApp.minutesRequired
                let currentMinutes = getTodayUsageMinutes(for: linkedApp.logicalID)
                // Cap progress at requirement (no overcounting)
                let cappedCurrent = min(currentMinutes, linkedApp.minutesRequired)
                totalCurrent += cappedCurrent

                // Check if this individual goal is met (at least 1 round completed)
                if currentMinutes >= linkedApp.minutesRequired {
                    // Calculate proportional reward (Threshold + Proportional)
                    // Use max(1, ...) to prevent division by zero
                    let ratio = Double(linkedApp.rewardMinutesEarned) / Double(max(1, linkedApp.minutesRequired))
                    let earned = Double(currentMinutes) * ratio
                    totalRewardEarned += Int(earned)
                } else {
                    allGoalsMet = false
                }
            }

            // Only award rewards if ALL goals are met
            if !allGoalsMet {
                totalRewardEarned = 0
            }

        case .any:
            // Can complete ANY ONE linked app - award that app's reward
            var bestProgress: (target: Int, current: Int, reward: Int)? = nil

            for linkedApp in linkedApps {
                let currentMinutes = getTodayUsageMinutes(for: linkedApp.logicalID)
                let target = linkedApp.minutesRequired

                // Check if this app's goal is met (at least 1 round completed)
                if currentMinutes >= target {
                    // Calculate proportional reward (Threshold + Proportional)
                    // Use max(1, ...) to prevent division by zero
                    let ratio = Double(linkedApp.rewardMinutesEarned) / Double(max(1, target))
                    let earned = Double(currentMinutes) * ratio
                    let earnedInt = Int(earned)

                    return LearningGoalCheckResult(
                        isGoalMet: true,
                        targetMinutes: target,
                        currentMinutes: currentMinutes,
                        rewardMinutesEarned: earnedInt
                    )
                }

                // Track best progress
                if bestProgress == nil || currentMinutes > bestProgress!.current {
                    bestProgress = (target: target, current: currentMinutes, reward: linkedApp.rewardMinutesEarned)
                }
            }

            // None completed - return best progress (no reward yet)
            if let best = bestProgress {
                return LearningGoalCheckResult(
                    isGoalMet: false,
                    targetMinutes: best.target,
                    currentMinutes: best.current,
                    rewardMinutesEarned: 0
                )
            }

            // Fallback
            return LearningGoalCheckResult(isGoalMet: false, targetMinutes: 15, currentMinutes: 0, rewardMinutesEarned: 0)
        }

        let isGoalMet = totalCurrent >= totalTarget
        return LearningGoalCheckResult(
            isGoalMet: isGoalMet,
            targetMinutes: totalTarget,
            currentMinutes: totalCurrent,
            rewardMinutesEarned: isGoalMet ? totalRewardEarned : 0
        )
    }

    private func getTodayUsageMinutes(for logicalID: String) -> Int {
        // Read from UsagePersistence (same source as app cards) instead of UserDefaults
        // This ensures bank card and app cards show consistent usage times
        guard let persistedApp = screenTimeService?.usagePersistence.app(for: logicalID) else {
            return 0
        }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        if persistedApp.lastResetDate >= startOfToday {
            return persistedApp.todaySeconds / 60
        }
        return 0
    }

    // MARK: - Sync All Reward Apps

    /// Sync blocking state for all reward apps
    /// Call this when reward apps are assigned, when learning goal is met, etc.
    func syncAllRewardApps(tokens: Set<ApplicationToken>) {
        guard let service = screenTimeService else {
            #if DEBUG
            print("[BlockingCoordinator] ScreenTimeService not set, skipping sync")
            #endif
            return
        }

        currentRewardTokens = tokens

        var tokensToBlock: Set<ApplicationToken> = []
        var tokensToUnblock: Set<ApplicationToken> = []

        for token in tokens {
            let decision = evaluateBlockingState(for: token)

            if decision.shouldBlock {
                // Set blocking reason before blocking
                setBlockingReason(for: token, decision: decision)
                tokensToBlock.insert(token)
            } else {
                // Clear blocking reason and unblock
                blockingReasonService.clearBlockingReason(token: token)
                tokensToUnblock.insert(token)
            }
        }

        #if DEBUG
        print("[BlockingCoordinator] Sync result: \(tokensToBlock.count) to block, \(tokensToUnblock.count) to unblock")
        #endif

        // Apply shields
        if !tokensToBlock.isEmpty {
            service.blockRewardApps(tokens: tokensToBlock)
        }
        if !tokensToUnblock.isEmpty {
            service.unblockRewardApps(tokens: tokensToUnblock)
        }
        
        // Check Streak
        checkAndUpdateStreak()
    }

    /// Check and update streak status based on goals
    private func checkAndUpdateStreak() {
        guard !currentRewardTokens.isEmpty else { return }

        let streakService = StreakService.shared
        let deviceID = DeviceModeManager.shared.deviceID

        // Check streak for EACH reward app independently
        for token in currentRewardTokens {
            guard let logicalID = screenTimeService?.getLogicalID(for: token),
                  let config = scheduleService.getSchedule(for: logicalID),
                  let streakSettings = config.streakSettings,
                  streakSettings.isEnabled else {
                continue
            }

            // Check if this app's learning goals are met
            let learningCheck = checkLearningGoal(logicalID: logicalID)
            let isGoalMet = learningCheck.isGoalMet

            // Update streak for this specific app
            streakService.checkAndUpdateStreak(
                goalsCompleted: isGoalMet,
                for: deviceID,
                appLogicalID: logicalID,
                settings: streakSettings
            )

            // Check for milestones
            if let milestone = streakService.checkMilestoneAchievement(
                for: logicalID,
                settings: streakSettings
            ) {
                if streakService.shouldApplyBonus(
                    for: milestone,
                    appLogicalID: logicalID,
                    settings: streakSettings
                ) {
                    let earnedMinutes = learningCheck.rewardMinutesEarned
                    let bonus = streakService.calculateBonusMinutes(
                        earnedMinutes: earnedMinutes,
                        settings: streakSettings,
                        multiplier: milestone
                    )

                    if bonus > 0 {
                        streakService.grantBonusMinutes(bonus, for: logicalID)
                        streakService.markMilestoneEarned(
                            milestone,
                            for: logicalID,
                            settings: streakSettings
                        )

                        // Post notification for milestone achievement
                        streakService.notifyMilestoneAchieved(
                            milestone: milestone,
                            bonusMinutes: bonus,
                            appLogicalID: logicalID
                        )

                        print("[BlockingCoordinator] 🏆 Streak Milestone \(milestone) for \(logicalID)! Granted \(bonus) bonus minutes.")
                    }
                }
            }
        }
    }

    /// Set the blocking reason in BlockingReasonService based on decision
    private func setBlockingReason(for token: ApplicationToken, decision: BlockingDecision) {
        guard let reason = decision.primaryReason else { return }

        switch reason {
        case .downtime:
            if let startHour = decision.downtimeWindowStartHour,
               let startMinute = decision.downtimeWindowStartMinute,
               let endHour = decision.downtimeWindowEndHour,
               let endMinute = decision.downtimeWindowEndMinute,
               let dayName = decision.downtimeDayName {
                blockingReasonService.setDowntimeBlocking(
                    token: token,
                    windowStartHour: startHour,
                    windowStartMinute: startMinute,
                    windowEndHour: endHour,
                    windowEndMinute: endMinute,
                    dayName: dayName,
                    summaryMessage: decision.downtimeSummaryMessage
                )
            }

        case .dailyLimitReached:
            if let limitMinutes = decision.dailyLimitMinutes,
               let usedMinutes = decision.usedMinutes {
                blockingReasonService.setDailyLimitBlocking(
                    token: token,
                    limitMinutes: limitMinutes,
                    usedMinutes: usedMinutes
                )
            }

        case .learningGoal:
            blockingReasonService.setLearningGoalBlocking(
                token: token,
                targetMinutes: decision.learningTargetMinutes ?? 15,
                currentMinutes: decision.learningCurrentMinutes ?? 0
            )

        case .rewardTimeExpired:
            // This case is handled directly in AppUsageViewModel.consumeReservedPoints()
            // when reward time expires, not through BlockingCoordinator evaluation
            break
        }

        #if DEBUG
        let hash = blockingReasonService.tokenHash(for: token)
        print("[BlockingCoordinator] Set \(reason.rawValue) blocking for token \(hash.prefix(20))...")
        #endif
    }

    // MARK: - Periodic Refresh

    /// Start periodic refresh of blocking states (every 60 seconds)
    func startPeriodicRefresh() {
        stopPeriodicRefresh()

        #if DEBUG
        print("[BlockingCoordinator] Starting periodic refresh (60s interval)")
        #endif

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.refreshAllBlockingStates()
            }
        }
    }

    /// Stop periodic refresh
    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        #if DEBUG
        print("[BlockingCoordinator] Stopped periodic refresh")
        #endif
    }

    /// Refresh all blocking states for currently tracked reward apps
    func refreshAllBlockingStates() {
        guard !currentRewardTokens.isEmpty else {
            return
        }

        #if DEBUG
        print("[BlockingCoordinator] Refreshing \(currentRewardTokens.count) reward apps")
        #endif

        syncAllRewardApps(tokens: currentRewardTokens)
    }

    /// Update tracked reward tokens (call when app selection changes)
    func updateTrackedTokens(_ tokens: Set<ApplicationToken>) {
        currentRewardTokens = tokens
    }
}

// MARK: - BlockingReasonType Extension

extension BlockingReasonType {
    /// User-friendly display message for each blocking reason
    var displayMessage: String {
        switch self {
        case .downtime:
            return "in downtime"
        case .dailyLimitReached:
            return "daily limit reached"
        case .learningGoal:
            return "learning goal not met"
        case .rewardTimeExpired:
            return "reward time expired"
        }
    }
}
