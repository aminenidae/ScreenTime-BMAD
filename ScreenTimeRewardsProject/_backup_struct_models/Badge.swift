import Foundation

struct Badge: Codable, Identifiable {
    let id: String  // UUID
    let name: String
    let description: String
    let iconName: String  // SF Symbol name
    var unlockedAt: Date?
    let criteria: BadgeCriteria
    let childDeviceID: String

    struct BadgeCriteria: Codable {
        let type: CriteriaType
        let threshold: Int

        enum CriteriaType: String, Codable {
            case challengesCompleted = "challenges_completed"
            case streakDays = "streak_days"
            case totalLearningMinutes = "total_learning_minutes"
            case totalPointsEarned = "total_points_earned"
        }
    }

    var isUnlocked: Bool {
        return unlockedAt != nil
    }
}