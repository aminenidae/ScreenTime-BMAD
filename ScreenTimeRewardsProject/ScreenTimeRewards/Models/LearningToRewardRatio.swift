import Foundation

/// Represents a configurable mapping between learning time and reward time.
struct LearningToRewardRatio: Equatable, Codable {
    static let `default` = LearningToRewardRatio(learningMinutes: 30, rewardMinutes: 30)

    /// Preset ratios exposed in the UI for quick selection.
    static let presetRatios: [LearningToRewardRatio] = [
        LearningToRewardRatio(learningMinutes: 60, rewardMinutes: 60), // 1:1
        LearningToRewardRatio(learningMinutes: 60, rewardMinutes: 30), // 2:1
        LearningToRewardRatio(learningMinutes: 60, rewardMinutes: 20), // 3:1
        LearningToRewardRatio(learningMinutes: 60, rewardMinutes: 15)  // 4:1
    ]

    private(set) var learningMinutes: Int
    private(set) var rewardMinutes: Int

    init(learningMinutes: Int, rewardMinutes: Int) {
        // Avoid invalid math by enforcing sane minimums.
        self.learningMinutes = max(1, learningMinutes)
        self.rewardMinutes = max(0, rewardMinutes)
    }

    /// Returns the amount of reward time granted for each learning minute.
    var rewardPerLearningMinute: Double {
        guard learningMinutes > 0 else { return 0 }
        return Double(rewardMinutes) / Double(learningMinutes)
    }

    /// Calculates base reward minutes for a given amount of learning minutes.
    func rewardMinutes(forLearningMinutes minutes: Int) -> Double {
        guard minutes > 0 else { return 0 }
        return Double(minutes) * rewardPerLearningMinute
    }

    /// Calculates total reward minutes including the configured bonus percentage.
    func rewardMinutes(forLearningMinutes minutes: Int, bonusPercentage: Int) -> Double {
        let base = rewardMinutes(forLearningMinutes: minutes)
        let multiplier = 1 + (Double(bonusPercentage) / 100)
        return base * multiplier
    }

    /// Creates a new ratio while preserving immutability.
    func updating(learningMinutes: Int? = nil, rewardMinutes: Int? = nil) -> LearningToRewardRatio {
        LearningToRewardRatio(
            learningMinutes: learningMinutes ?? self.learningMinutes,
            rewardMinutes: rewardMinutes ?? self.rewardMinutes
        )
    }

    /// Human readable text used in UI preview cards.
    var formattedDescription: String {
        "\(learningMinutes) min learning = \(rewardMinutes) min reward"
    }
}
