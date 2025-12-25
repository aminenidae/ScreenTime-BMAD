import Foundation

enum StreakRule: String, Codable, CaseIterable {
    case anyGoal = "Any Learning Goal"
    case allGoals = "All Learning Goals"
}

struct StreakSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var bonusPercentage: Int = 10 // Default 10%
    var streakRule: StreakRule = .anyGoal
    var milestones: [Int] = [7, 14, 30] // Default milestones
    var earnedMilestones: Set<Int> = []
    
    // Helper to ensure valid percentage
    mutating func setBonusPercentage(_ percentage: Int) {
        let validPercentages = [5, 10, 15, 20, 25]
        if validPercentages.contains(percentage) {
            self.bonusPercentage = percentage
        }
    }
}

/// Per-app streak configuration (embedded in AppScheduleConfiguration)
struct AppStreakSettings: Codable, Equatable, Hashable {
    var isEnabled: Bool = false
    var bonusPercentage: Int = 10  // 5, 10, 15, 20, 25
    var milestones: [Int] = [7, 14, 30]
    var earnedMilestones: Set<Int> = []

    mutating func setBonusPercentage(_ percentage: Int) {
        let validPercentages = [5, 10, 15, 20, 25]
        if validPercentages.contains(percentage) {
            self.bonusPercentage = percentage
        }
    }

    static let defaultSettings = AppStreakSettings(
        isEnabled: false,
        bonusPercentage: 10,
        milestones: [7, 14, 30],
        earnedMilestones: []
    )
}
