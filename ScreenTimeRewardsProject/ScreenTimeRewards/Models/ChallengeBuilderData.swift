import Foundation

/// Ordered steps that make up the V2 challenge onboarding flow.
/// Note: Schedule step removed - per-app scheduling is now handled inline during app selection
enum ChallengeBuilderStep: Int, CaseIterable, Identifiable {
    case details
    case learningApps
    case rewardApps
    case rewardConfig
    case summary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .details: return "Challenge Details"
        case .learningApps: return "Learning Apps"
        case .rewardApps: return "Reward Apps"
        case .rewardConfig: return "Rewards"
        case .summary: return "Review"
        }
    }
}

/// All mutable state captured throughout the multi-step creation flow.
struct ChallengeBuilderData: Equatable {
    struct GoalValueConfiguration {
        let range: ClosedRange<Int>
        let step: Int
        let defaultValue: Int
        let unit: String
    }

    struct StreakBonus: Equatable, Codable {
        var enabled: Bool = false
        var targetDays: Int = 7
        var bonusPercentage: Int = 25

        static let targetDaysRange: ClosedRange<Int> = 3...30
        static let bonusRange: ClosedRange<Int> = 0...100
    }

    struct Schedule: Equatable, Codable {
        var startDate: Date = Date()
        var hasEndDate: Bool = false
        var endDate: Date? = nil
        var repeatWeekly: Bool = true
        var activeDays: Set<Int> = [1, 2, 3, 4, 5] // Monday - Friday
        var isFullDay: Bool = true
        var startTime: Date = Schedule.makeDate(hour: 8)
        var endTime: Date = Schedule.makeDate(hour: 20)

        static func makeDate(hour: Int, minute: Int = 0) -> Date {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            return Calendar.current.date(from: components) ?? Date()
        }

        mutating func enforceDateConsistency() {
            if hasEndDate {
                if let endDate, endDate < startDate {
                    self.endDate = startDate
                } else if endDate == nil {
                    endDate = startDate
                }
            } else {
                endDate = nil
            }
        }

        mutating func setFullDay(_ value: Bool) {
            isFullDay = value
            if value {
                startTime = Schedule.makeDate(hour: 0)
                endTime = Schedule.makeDate(hour: 23, minute: 59)
            }
        }

        var usesCustomTimeRange: Bool { !isFullDay }

        var isValid: Bool {
            guard !activeDays.isEmpty else { return false }
            if hasEndDate {
                guard let endDate else { return false }
                guard endDate >= startDate else { return false }
            }

            if !isFullDay {
                return startTime < endTime
            }

            return true
        }

        /// Returns the maximum number of consecutive active days in the schedule
        func maxConsecutiveDays() -> Int {
            guard !activeDays.isEmpty else { return 0 }

            // Convert Set to sorted array (1-7 for Mon-Sun)
            let sortedDays = activeDays.sorted()

            // If all 7 days are selected, return 7
            if sortedDays.count == 7 {
                return 7
            }

            var maxStreak = 1
            var currentStreak = 1

            for i in 1..<sortedDays.count {
                // Check if days are consecutive (allowing wrap-around from Sunday to Monday)
                if sortedDays[i] == sortedDays[i-1] + 1 {
                    currentStreak += 1
                    maxStreak = max(maxStreak, currentStreak)
                } else {
                    currentStreak = 1
                }
            }

            // Check wrap-around: Sunday (7) to Monday (1)
            if sortedDays.contains(7) && sortedDays.contains(1) {
                // Count consecutive days from the end and beginning
                var endStreak = 1
                for i in stride(from: sortedDays.count - 2, through: 0, by: -1) {
                    if sortedDays[i] == sortedDays[i+1] - 1 {
                        endStreak += 1
                    } else {
                        break
                    }
                }

                var startStreak = 1
                for i in 1..<sortedDays.count {
                    if sortedDays[i] == sortedDays[i-1] + 1 {
                        startStreak += 1
                    } else {
                        break
                    }
                }

                maxStreak = max(maxStreak, endStreak + startStreak)
            }

            return maxStreak
        }

        /// Check if schedule meets the minimum consecutive days requirement
        func meetsStreakRequirement(targetDays: Int) -> Bool {
            return maxConsecutiveDays() >= targetDays
        }
    }

    static let dailyMinutesRange: ClosedRange<Int> = 10...240

    var title: String = ""
    var description: String = ""
    var goalType: ChallengeGoalType = .dailyQuest
    var dailyMinutesGoal: Int = 60
    var selectedLearningAppIDs: Set<String> = []
    var selectedRewardAppIDs: Set<String> = []
    var learningToRewardRatio: LearningToRewardRatio = .default
    var streakBonus = StreakBonus()
    var schedule = Schedule()
    var progressTrackingMode: ProgressTrackingMode = .combined

    // Per-app schedule configurations
    var learningAppConfigs: [String: AppScheduleConfiguration] = [:]
    var rewardAppConfigs: [String: AppScheduleConfiguration] = [:]

    // MARK: - Derived helpers
    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isDetailsStepValid: Bool {
        !trimmedTitle.isEmpty && Self.dailyMinutesRange.contains(dailyMinutesGoal)
    }

    var isRewardConfigValid: Bool {
        let ratioValid = learningToRewardRatio.rewardPerLearningMinute > 0
        let streakValid = !streakBonus.enabled || (
            StreakBonus.targetDaysRange.contains(streakBonus.targetDays) &&
            StreakBonus.bonusRange.contains(streakBonus.bonusPercentage)
        )
        return ratioValid && streakValid
    }

    var isScheduleStepValid: Bool {
        guard schedule.isValid else { return false }

        // If streak bonus is enabled, ensure schedule meets streak requirement
        if streakBonus.enabled {
            return schedule.meetsStreakRequirement(targetDays: streakBonus.targetDays)
        }

        return true
    }

    var isProgressTrackingModeValid: Bool {
        // Per-app requires at least 2 apps selected
        if progressTrackingMode == .perApp && selectedLearningAppIDs.count < 2 {
            return false
        }
        return true
    }

    /// Check if all selected learning apps have been configured
    var areLearningAppsConfigured: Bool {
        // Empty selection is valid (counts all learning apps)
        if selectedLearningAppIDs.isEmpty { return true }
        // All selected apps must have configs
        return selectedLearningAppIDs.allSatisfy { learningAppConfigs[$0] != nil }
    }

    /// Check if all selected reward apps have been configured
    var areRewardAppsConfigured: Bool {
        // Empty selection is valid
        if selectedRewardAppIDs.isEmpty { return true }
        // All selected apps must have configs
        return selectedRewardAppIDs.allSatisfy { rewardAppConfigs[$0] != nil }
    }

    /// Count of unconfigured learning apps
    var unconfiguredLearningAppCount: Int {
        selectedLearningAppIDs.filter { learningAppConfigs[$0] == nil }.count
    }

    /// Count of unconfigured reward apps
    var unconfiguredRewardAppCount: Int {
        selectedRewardAppIDs.filter { rewardAppConfigs[$0] == nil }.count
    }

    var canSubmit: Bool {
        isDetailsStepValid && isRewardConfigValid && isProgressTrackingModeValid &&
        areLearningAppsConfigured && areRewardAppsConfigured
    }

    mutating func setDailyMinutesGoal(_ value: Int) {
        dailyMinutesGoal = Self.dailyMinutesRange.clamp(value)
    }

    mutating func setStreakTargetDays(_ value: Int) {
        streakBonus.targetDays = StreakBonus.targetDaysRange.clamp(value)
    }

    mutating func setStreakBonusPercentage(_ value: Int) {
        streakBonus.bonusPercentage = StreakBonus.bonusRange.clamp(value)
    }

    mutating func setLearningRatioMinutes(_ value: Int) {
        let sanitized = max(1, value)
        learningToRewardRatio = learningToRewardRatio.updating(learningMinutes: sanitized)
    }

    mutating func setRewardRatioMinutes(_ value: Int) {
        let sanitized = max(0, value)
        learningToRewardRatio = learningToRewardRatio.updating(rewardMinutes: sanitized)
    }

    mutating func applyRatioPreset(_ ratio: LearningToRewardRatio) {
        learningToRewardRatio = ratio
    }

    /// Load existing challenge data into the builder for editing
    static func fromChallenge(_ challenge: Challenge) -> ChallengeBuilderData {
        var data = ChallengeBuilderData()

        // Basic info
        data.title = challenge.title ?? ""
        data.description = challenge.challengeDescription ?? ""

        // Goal type and target
        if let goalTypeString = challenge.goalType,
           let goalType = ChallengeGoalType(rawValue: goalTypeString) {
            data.goalType = goalType
        }
        data.dailyMinutesGoal = Int(challenge.targetValue)

        // Learning and reward apps
        let learningApps = challenge.targetAppIDs
        if !learningApps.isEmpty {
            data.selectedLearningAppIDs = Set(learningApps)
        }
        let rewardApps = challenge.rewardAppIDs
        if !rewardApps.isEmpty {
            data.selectedRewardAppIDs = Set(rewardApps)
        }

        // Learning to reward ratio
        if let ratio = challenge.learningToRewardRatio {
            data.learningToRewardRatio = ratio
        }

        // Streak bonus
        data.streakBonus.enabled = challenge.streakBonusEnabled
        data.streakBonus.targetDays = Int(challenge.streakTargetDays)
        data.streakBonus.bonusPercentage = Int(challenge.streakBonusPercentage)

        // Schedule
        if let startDate = challenge.startDate {
            data.schedule.startDate = startDate
        }
        if let endDate = challenge.endDate {
            data.schedule.hasEndDate = true
            data.schedule.endDate = endDate
        }
        let activeDaysArray = challenge.scheduledActiveDays
        if !activeDaysArray.isEmpty {
            data.schedule.activeDays = Set(activeDaysArray)
        }
        if let startTime = challenge.startTime, let endTime = challenge.endTime {
            data.schedule.isFullDay = false
            data.schedule.startTime = startTime
            data.schedule.endTime = endTime
        }

        // Progress tracking mode
        if let modeString = challenge.progressTrackingMode,
           let mode = ProgressTrackingMode(rawValue: modeString) {
            data.progressTrackingMode = mode
        }

        return data
    }
}

private extension ClosedRange where Bound: Comparable {
    func clamp(_ value: Bound) -> Bound {
        min(max(lowerBound, value), upperBound)
    }
}
