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

    // MARK: - Condition Checks

    private struct DowntimeCheckResult {
        let isInDowntime: Bool
        // Full allowed time window
        let windowStartHour: Int?
        let windowStartMinute: Int?
        let windowEndHour: Int?
        let windowEndMinute: Int?
        let dayName: String?

        static func notInDowntime() -> DowntimeCheckResult {
            DowntimeCheckResult(
                isInDowntime: false,
                windowStartHour: nil,
                windowStartMinute: nil,
                windowEndHour: nil,
                windowEndMinute: nil,
                dayName: nil
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
        // Return the full allowed time window for display
        return DowntimeCheckResult(
            isInDowntime: true,
            windowStartHour: todayWindow.startHour,
            windowStartMinute: todayWindow.startMinute,
            windowEndHour: todayWindow.endHour,
            windowEndMinute: todayWindow.endMinute,
            dayName: getCurrentDayName()
        )
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
    }

    private func checkLearningGoal(logicalID: String) -> LearningGoalCheckResult {
        guard let config = scheduleService.getSchedule(for: logicalID) else {
            // No schedule = default learning requirement
            return LearningGoalCheckResult(isGoalMet: false, targetMinutes: 15, currentMinutes: 0)
        }

        let linkedApps = config.linkedLearningApps

        // No linked learning apps = goal is met (no requirement)
        if linkedApps.isEmpty {
            return LearningGoalCheckResult(isGoalMet: true, targetMinutes: 0, currentMinutes: 0)
        }

        // Calculate total required and current progress
        var totalTarget = 0
        var totalCurrent = 0

        switch config.unlockMode {
        case .all:
            // Must complete ALL linked apps
            for linkedApp in linkedApps {
                totalTarget += linkedApp.minutesRequired
                let currentMinutes = getTodayUsageMinutes(for: linkedApp.logicalID)
                // Cap progress at requirement (no overcounting)
                totalCurrent += min(currentMinutes, linkedApp.minutesRequired)
            }

        case .any:
            // Can complete ANY ONE linked app
            // Find the one with the best progress ratio
            var bestProgress: (target: Int, current: Int)? = nil

            for linkedApp in linkedApps {
                let currentMinutes = getTodayUsageMinutes(for: linkedApp.logicalID)
                let target = linkedApp.minutesRequired

                // Check if this app's goal is met
                if currentMinutes >= target {
                    return LearningGoalCheckResult(isGoalMet: true, targetMinutes: target, currentMinutes: currentMinutes)
                }

                // Track best progress
                if bestProgress == nil || currentMinutes > bestProgress!.current {
                    bestProgress = (target: target, current: currentMinutes)
                }
            }

            // None completed - return best progress
            if let best = bestProgress {
                return LearningGoalCheckResult(isGoalMet: false, targetMinutes: best.target, currentMinutes: best.current)
            }

            // Fallback
            return LearningGoalCheckResult(isGoalMet: false, targetMinutes: 15, currentMinutes: 0)
        }

        let isGoalMet = totalCurrent >= totalTarget
        return LearningGoalCheckResult(
            isGoalMet: isGoalMet,
            targetMinutes: totalTarget,
            currentMinutes: totalCurrent
        )
    }

    private func getTodayUsageMinutes(for logicalID: String) -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return 0
        }
        let usageSeconds = defaults.integer(forKey: "usage_\(logicalID)_today")
        return usageSeconds / 60
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
                    dayName: dayName
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
            #if DEBUG
            print("[BlockingCoordinator] No reward tokens to refresh")
            #endif
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
        }
    }
}
