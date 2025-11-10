import Foundation

enum ChallengeGoalType: String, CaseIterable {
    case dailyMinutes = "daily_minutes"
    case weeklyMinutes = "weekly_minutes"
    case specificApps = "specific_apps"
    case streak = "streak"
    case pointsTarget = "points_target"

    var displayName: String {
        switch self {
        case .dailyMinutes:
            return "Daily Minutes"
        case .weeklyMinutes:
            return "Weekly Minutes"
        case .specificApps:
            return "Specific Apps"
        case .streak:
            return "Streak"
        case .pointsTarget:
            return "Points Target"
        }
    }
}
