import Foundation

/// Ordered steps that make up the V2 challenge onboarding flow.
enum ChallengeBuilderStep: Int, CaseIterable, Identifiable {
    case details
    case learningApps
    case rewardApps
    case rewardConfig
    case schedule
    case summary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .details: return "Challenge Details"
        case .learningApps: return "Learning Apps"
        case .rewardApps: return "Reward Apps"
        case .rewardConfig: return "Rewards"
        case .schedule: return "Schedule"
        case .summary: return "Review"
        }
    }
}

/// All mutable state captured throughout the multi-step creation flow.
struct ChallengeBuilderData: Equatable {
    struct GoalValues: Equatable, Codable {
        var dailyMinutes: Int = 60
        var weeklyMinutes: Int = 120
        var specificAppsMinutes: Int = 20
        var streakDays: Int = 7
        var points: Int = 500

        func value(for type: ChallengeGoalType) -> Int {
            switch type {
            case .dailyMinutes: return dailyMinutes
            case .weeklyMinutes: return weeklyMinutes
            case .specificApps: return specificAppsMinutes
            case .streak: return streakDays
            case .pointsTarget: return points
            }
        }

        mutating func setValue(_ value: Int, for type: ChallengeGoalType) {
            switch type {
            case .dailyMinutes: dailyMinutes = value
            case .weeklyMinutes: weeklyMinutes = value
            case .specificApps: specificAppsMinutes = value
            case .streak: streakDays = value
            case .pointsTarget: points = value
            }
        }
    }

    struct GoalValueConfiguration {
        let range: ClosedRange<Int>
        let step: Int
        let defaultValue: Int
        let unit: String
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
    }

    static let bonusRange: ClosedRange<Int> = 0...50

    var title: String = ""
    var description: String = ""
    var goalType: ChallengeGoalType = .dailyMinutes
    var goalValues = GoalValues()
    var selectedLearningAppIDs: Set<String> = []
    var selectedRewardAppIDs: Set<String> = []
    var learningToRewardRatio: LearningToRewardRatio = .default
    var bonusPercentage: Int = 25
    var schedule = Schedule()

    // MARK: - Derived helpers
    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Currently active goal value for the chosen goal type.
    var activeGoalValue: Int {
        goalValues.value(for: goalType)
    }

    var activeGoalConfiguration: GoalValueConfiguration {
        Self.goalConfigurations[goalType] ?? GoalValueConfiguration(
            range: 1...100,
            step: 1,
            defaultValue: 1,
            unit: "units"
        )
    }

    var isDetailsStepValid: Bool {
        !trimmedTitle.isEmpty && activeGoalValue >= activeGoalConfiguration.range.lowerBound
    }

    var isRewardConfigValid: Bool {
        learningToRewardRatio.rewardPerLearningMinute > 0 && Self.bonusRange.contains(bonusPercentage)
    }

    var isScheduleStepValid: Bool {
        schedule.isValid
    }

    var canSubmit: Bool {
        isDetailsStepValid && isRewardConfigValid && isScheduleStepValid
    }

    mutating func setActiveGoalValue(_ value: Int) {
        let configuration = activeGoalConfiguration
        let clamped = configuration.range.clamp(value)
        goalValues.setValue(clamped, for: goalType)
    }

    mutating func setBonusPercentage(_ value: Int) {
        bonusPercentage = Self.bonusRange.clamp(value)
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

    static func goalConfiguration(for type: ChallengeGoalType) -> GoalValueConfiguration {
        goalConfigurations[type] ?? GoalValueConfiguration(range: 1...100, step: 1, defaultValue: 1, unit: "units")
    }

    private static let goalConfigurations: [ChallengeGoalType: GoalValueConfiguration] = [
        .dailyMinutes: GoalValueConfiguration(range: 10...240, step: 5, defaultValue: 60, unit: "min/day"),
        .weeklyMinutes: GoalValueConfiguration(range: 30...840, step: 15, defaultValue: 120, unit: "min/week"),
        .specificApps: GoalValueConfiguration(range: 5...180, step: 5, defaultValue: 20, unit: "min/app"),
        .streak: GoalValueConfiguration(range: 3...30, step: 1, defaultValue: 7, unit: "days"),
        .pointsTarget: GoalValueConfiguration(range: 100...5000, step: 50, defaultValue: 500, unit: "points")
    ]
}

private extension ClosedRange where Bound: Comparable {
    func clamp(_ value: Bound) -> Bound {
        min(max(lowerBound, value), upperBound)
    }
}
