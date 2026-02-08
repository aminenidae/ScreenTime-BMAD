import Foundation
import Combine

/// Manages notification settings for the app
final class NotificationSettingsManager: ObservableObject {
    static let shared = NotificationSettingsManager()

    private let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    // MARK: - Setting Keys
    private enum Keys {
        static let dailyLimitNotifications = "notif_dailyLimit"
        static let learningGoalNotifications = "notif_learningGoal"
        static let streakNotifications = "notif_streak"
        static let downtimeNotifications = "notif_downtime"
        static let rewardTimeNotifications = "notif_rewardTime"
        static let parentAlertsEnabled = "notif_parentAlerts"
        static let soundEnabled = "notif_sound"
        static let badgeEnabled = "notif_badge"
    }

    // MARK: - Published Properties
    @Published var dailyLimitNotificationsEnabled: Bool {
        didSet { defaults?.set(dailyLimitNotificationsEnabled, forKey: Keys.dailyLimitNotifications) }
    }

    @Published var learningGoalNotificationsEnabled: Bool {
        didSet { defaults?.set(learningGoalNotificationsEnabled, forKey: Keys.learningGoalNotifications) }
    }

    @Published var streakNotificationsEnabled: Bool {
        didSet { defaults?.set(streakNotificationsEnabled, forKey: Keys.streakNotifications) }
    }

    @Published var downtimeNotificationsEnabled: Bool {
        didSet { defaults?.set(downtimeNotificationsEnabled, forKey: Keys.downtimeNotifications) }
    }

    @Published var rewardTimeNotificationsEnabled: Bool {
        didSet { defaults?.set(rewardTimeNotificationsEnabled, forKey: Keys.rewardTimeNotifications) }
    }

    @Published var parentAlertsEnabled: Bool {
        didSet { defaults?.set(parentAlertsEnabled, forKey: Keys.parentAlertsEnabled) }
    }

    @Published var soundEnabled: Bool {
        didSet { defaults?.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    @Published var badgeEnabled: Bool {
        didSet { defaults?.set(badgeEnabled, forKey: Keys.badgeEnabled) }
    }

    // MARK: - Initialization
    private init() {
        // Load saved settings with defaults
        self.dailyLimitNotificationsEnabled = defaults?.bool(forKey: Keys.dailyLimitNotifications) ?? true
        self.learningGoalNotificationsEnabled = defaults?.bool(forKey: Keys.learningGoalNotifications) ?? true
        self.streakNotificationsEnabled = defaults?.bool(forKey: Keys.streakNotifications) ?? true
        self.downtimeNotificationsEnabled = defaults?.bool(forKey: Keys.downtimeNotifications) ?? true
        self.rewardTimeNotificationsEnabled = defaults?.bool(forKey: Keys.rewardTimeNotifications) ?? true
        self.parentAlertsEnabled = defaults?.bool(forKey: Keys.parentAlertsEnabled) ?? true
        self.soundEnabled = defaults?.bool(forKey: Keys.soundEnabled) ?? true
        self.badgeEnabled = defaults?.bool(forKey: Keys.badgeEnabled) ?? true
    }

    // MARK: - Helper Methods

    /// Check if a specific notification type is enabled
    func isEnabled(for type: NotificationType) -> Bool {
        switch type {
        case .dailyLimit:
            return dailyLimitNotificationsEnabled
        case .learningGoal:
            return learningGoalNotificationsEnabled
        case .streak:
            return streakNotificationsEnabled
        case .downtime:
            return downtimeNotificationsEnabled
        case .rewardTime:
            return rewardTimeNotificationsEnabled
        case .parentAlert:
            return parentAlertsEnabled
        }
    }

    /// Check if a specific notification category is enabled (by string key)
    func isEnabled(for categoryRawValue: String) -> Bool {
        switch categoryRawValue {
        case "dailyLimit", "dailyLimitWarning":
            return dailyLimitNotificationsEnabled
        case "learningGoal":
            return learningGoalNotificationsEnabled
        case "streak":
            return streakNotificationsEnabled
        case "downtime":
            return downtimeNotificationsEnabled
        case "rewardTime", "rewardTimeWarning":
            return rewardTimeNotificationsEnabled
        case "parentAlert":
            return parentAlertsEnabled
        default:
            return true // Default to enabled for unknown categories
        }
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        dailyLimitNotificationsEnabled = true
        learningGoalNotificationsEnabled = true
        streakNotificationsEnabled = true
        downtimeNotificationsEnabled = true
        rewardTimeNotificationsEnabled = true
        parentAlertsEnabled = true
        soundEnabled = true
        badgeEnabled = true
    }

    // MARK: - Notification Types
    enum NotificationType {
        case dailyLimit
        case learningGoal
        case streak
        case downtime
        case rewardTime
        case parentAlert
    }
}
