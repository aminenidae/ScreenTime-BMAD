import Foundation

struct Challenge: Codable, Identifiable {
    let id: String  // UUID
    let title: String
    let description: String
    let goalType: GoalType
    let targetValue: Int  // Minutes or days
    let bonusPercentage: Int  // 5-50%
    let targetApps: [String]?  // Optional specific learning app logical IDs
    let startDate: Date
    let endDate: Date?  // nil = ongoing
    let isActive: Bool
    let createdBy: String  // Parent device ID
    let assignedTo: String  // Child device ID

    enum GoalType: String, Codable {
        case dailyMinutes = "daily_minutes"
        case weeklyMinutes = "weekly_minutes"
        case specificApps = "specific_apps"
        case streak = "streak"
    }

    // Helper computed properties
    var isExpired: Bool {
        guard let endDate = endDate else { return false }
        return Date() > endDate
    }

    var durationText: String {
        if endDate == nil { return "Ongoing" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate!))"
    }
}