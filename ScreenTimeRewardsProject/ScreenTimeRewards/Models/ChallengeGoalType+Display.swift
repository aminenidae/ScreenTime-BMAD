import SwiftUI

extension ChallengeGoalType {
    var iconName: String {
        switch self {
        case .dailyMinutes:
            return "sun.max.fill"
        case .weeklyMinutes:
            return "calendar"
        case .specificApps:
            return "app.fill"
        case .streak:
            return "flame.fill"
        case .pointsTarget:
            return "target"
        }
    }

    var accentColor: Color {
        switch self {
        case .dailyMinutes:
            return .orange
        case .weeklyMinutes:
            return .blue
        case .specificApps:
            return .green
        case .streak:
            return .red
        case .pointsTarget:
            return .purple
        }
    }

    var valueUnitLabel: String {
        switch self {
        case .dailyMinutes, .weeklyMinutes, .specificApps:
            return "minutes"
        case .streak:
            return "days"
        case .pointsTarget:
            return "points"
        }
    }
}
