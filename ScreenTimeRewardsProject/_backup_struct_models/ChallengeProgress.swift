import Foundation

struct ChallengeProgress: Codable, Identifiable {
    let id: String  // UUID
    let challengeID: String
    let childDeviceID: String
    var currentValue: Int  // Current minutes or streak count
    let targetValue: Int
    var isCompleted: Bool
    var completedDate: Date?
    var bonusPointsEarned: Int
    var lastUpdated: Date

    // Computed properties
    var progressPercentage: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(currentValue) / Double(targetValue), 1.0) * 100
    }

    var remainingValue: Int {
        return max(0, targetValue - currentValue)
    }

    var isNearCompletion: Bool {
        return progressPercentage >= 90
    }
}