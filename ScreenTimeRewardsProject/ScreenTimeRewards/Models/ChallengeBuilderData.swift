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
        schedule.isValid
    }

    var isProgressTrackingModeValid: Bool {
        // Per-app requires at least 2 apps selected
        if progressTrackingMode == .perApp && selectedLearningAppIDs.count < 2 {
            return false
        }
        return true
    }

    var canSubmit: Bool {
        isDetailsStepValid && isRewardConfigValid && isScheduleStepValid && isProgressTrackingModeValid
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
}

private extension ClosedRange where Bound: Comparable {
    func clamp(_ value: Bound) -> Bound {
        min(max(lowerBound, value), upperBound)
    }
}
