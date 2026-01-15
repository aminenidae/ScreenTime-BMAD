import Foundation

/// Describes the unlocking rules for a badge.
struct BadgeCriteria: Codable {
    enum CriteriaType: String, Codable {
        case challengesCompleted = "challenges_completed"
        case streakDays = "streak_days"
        case totalLearningMinutes = "total_learning_minutes"
        case totalPointsEarned = "total_points_earned"
    }

    let type: CriteriaType
    let threshold: Int
}

