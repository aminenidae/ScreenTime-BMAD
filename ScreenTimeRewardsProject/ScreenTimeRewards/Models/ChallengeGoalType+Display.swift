import SwiftUI

extension ChallengeGoalType {
    var iconName: String {
        switch self {
        case .dailyQuest:
            return "target"
        }
    }

    var accentColor: Color {
        switch self {
        case .dailyQuest:
            return .blue
        }
    }

    var valueUnitLabel: String {
        switch self {
        case .dailyQuest:
            return "minutes"
        }
    }
}
