import Foundation

struct StreakRecord: Codable, Identifiable {
    let id: String  // UUID
    let childDeviceID: String
    let streakType: StreakType
    var currentStreak: Int
    var longestStreak: Int
    var lastActivityDate: Date

    enum StreakType: String, Codable {
        case daily = "daily"
        case weekly = "weekly"
    }

    // Calculated properties
    var streakMultiplier: Double {
        // +5% bonus per week of streak
        let weeks = currentStreak / 7
        return 1.0 + (Double(weeks) * 0.05)
    }

    var isAtRisk: Bool {
        // Streak at risk if no activity today
        let calendar = Calendar.current
        return !calendar.isDateInToday(lastActivityDate)
    }
}