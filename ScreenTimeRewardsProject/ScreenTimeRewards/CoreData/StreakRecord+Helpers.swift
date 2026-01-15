import Foundation

extension StreakRecord {
    enum StreakType: String {
        case daily
        case weekly
    }

    var streakTypeEnum: StreakType {
        get {
            if let streakType,
               let type = StreakType(rawValue: streakType) {
                return type
            }
            return .daily
        }
        set {
            streakType = newValue.rawValue
        }
    }

    /// Whether the streak risks breaking because today's activity is missing.
    var isAtRisk: Bool {
        guard let lastActivityDate else { return false }
        return !Calendar.current.isDateInToday(lastActivityDate)
    }
}

