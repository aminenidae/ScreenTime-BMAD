import Foundation

enum ChallengeGoalType: String, CaseIterable {
    case dailyQuest = "daily_quest"

    var displayName: String {
        switch self {
        case .dailyQuest:
            return "Daily Quest"
        }
    }
}
