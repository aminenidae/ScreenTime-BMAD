import Foundation

enum StreakRule: String, Codable, CaseIterable {
    case anyGoal = "Any Learning Goal"
    case allGoals = "All Learning Goals"
}

enum StreakBonusType: String, Codable, CaseIterable {
    case percentage = "Percentage"
    case fixedMinutes = "Fixed Minutes"
}

struct StreakSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var bonusValue: Int = 10 // Percentage or Minutes
    var bonusType: StreakBonusType = .percentage
    var streakRule: StreakRule = .anyGoal
    var streakCycleDays: Int = 7
    var earnedMilestones: Set<Int> = []
    
    // Helper to ensure valid value
    mutating func setBonusValue(_ value: Int) {
        self.bonusValue = value
    }
}

/// Per-app streak configuration (embedded in AppScheduleConfiguration)
struct AppStreakSettings: Codable, Equatable, Hashable {
    var isEnabled: Bool = false
    var bonusValue: Int = 10
    var bonusType: StreakBonusType = .percentage
    var streakCycleDays: Int = 7
    var earnedMilestones: Set<Int> = []

    mutating func setBonusValue(_ value: Int) {
        self.bonusValue = value
    }
    
    mutating func setStreakCycle(_ days: Int) {
        self.streakCycleDays = max(1, days)
    }

    static let defaultSettings = AppStreakSettings(
        isEnabled: false,
        bonusValue: 10,
        bonusType: .percentage,
        streakCycleDays: 7,
        earnedMilestones: []
    )
}
