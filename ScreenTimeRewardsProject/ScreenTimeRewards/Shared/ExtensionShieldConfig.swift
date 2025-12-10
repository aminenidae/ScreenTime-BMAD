import Foundation

// MARK: - Extension Shield Configuration
// Lightweight structures for sharing goal configurations between main app and extension
// These are designed to be small and efficient for extension memory constraints (~6MB limit)

/// Lightweight goal configuration for a single reward app
/// Stored in App Group UserDefaults for extension access
struct ExtensionGoalConfig: Codable, Equatable {
    let rewardAppLogicalID: String
    let rewardAppTokenData: Data  // Serialized ApplicationToken
    let linkedLearningApps: [LinkedGoal]
    let unlockMode: String  // "all" or "any"

    struct LinkedGoal: Codable, Equatable {
        let learningAppLogicalID: String
        let minutesRequired: Int
    }
}

/// Container for all goal configs - written by main app, read by extension
struct ExtensionShieldConfigs: Codable {
    var goalConfigs: [ExtensionGoalConfig]
    var lastUpdated: Date

    /// UserDefaults key for storing configs
    static let userDefaultsKey = "extensionShieldConfigs"
}

// MARK: - Extension Shield State
// Tracks which reward apps have been unlocked by the extension

/// State of a reward app's shield as determined by the extension
struct ExtensionShieldState: Codable {
    let rewardAppLogicalID: String
    let isUnlocked: Bool
    let unlockedAt: Date?
    let reason: String  // e.g., "learning_goal_met", "all_goals_met"
}

/// Container for shield states - written by extension, read by main app
struct ExtensionShieldStates: Codable {
    var states: [String: ExtensionShieldState]  // keyed by rewardAppLogicalID
    var lastUpdated: Date

    /// UserDefaults key for storing states
    static let userDefaultsKey = "extensionShieldStates"

    init() {
        states = [:]
        lastUpdated = Date()
    }
}
