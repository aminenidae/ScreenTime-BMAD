import Foundation

extension Challenge {
    var goalTypeEnum: ChallengeGoalType? {
        guard let goalType else { return nil }
        return ChallengeGoalType(rawValue: goalType)
    }

    var targetAppIDs: [String] {
        decodeIDs(from: targetAppsJSON)
    }

    var rewardAppIDs: [String] {
        decodeIDs(from: rewardAppsJSON)
    }

    var learningToRewardRatio: LearningToRewardRatio? {
        guard let ratio: LearningToRewardRatio = decode(from: learningToRewardRatioData) else {
            return nil
        }
        return ratio
    }

    var effectiveRewardRatio: LearningToRewardRatio {
        learningToRewardRatio ?? .default
    }

    var scheduledActiveDays: [Int] {
        guard let days: [Int] = decode(from: activeDays) else { return [] }
        return days
    }

    var progressTrackingModeEnum: ProgressTrackingMode {
        guard let mode = progressTrackingMode else { return .combined }
        return ProgressTrackingMode(rawValue: mode) ?? .combined
    }

    var isPerAppTracking: Bool {
        progressTrackingModeEnum == .perApp
    }

    func rewardUnlockMinutes(defaultValue: Int = 30) -> Int {
        let learningMinutes = max(1, Int(targetValue))
        let percentage = Int(bonusPercentage)
        let ratio = effectiveRewardRatio

        let rewardMinutes = ratio.rewardMinutes(
            forLearningMinutes: learningMinutes,
            bonusPercentage: percentage
        )

        let rounded = Int(round(rewardMinutes))
        if rounded > 0 {
            return rounded
        }
        return max(1, defaultValue)
    }

    private func decodeIDs(from jsonString: String?) -> [String] {
        guard let ids: [String] = decode(from: jsonString) else {
            return []
        }
        return ids
    }

    private func decode<T: Decodable>(from jsonString: String?) -> T? {
        guard
            let jsonString,
            let data = jsonString.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
