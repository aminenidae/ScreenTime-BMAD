//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Created by Amine Nidae on 2025-11-22.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit
import FamilyControls
import CryptoKit

// MARK: - Blocking Reason Data Models (duplicated from main app - extensions can't share files)

/// Types of blocking reasons for shield messages
private enum BlockingReasonType: String, Codable {
    case learningGoal       // Reward app blocked until learning goal met
    case dailyLimitReached  // Used up daily allowed minutes
    case downtime           // Outside allowed time window
}

/// Per-app blocking data stored in App Group by token hash
private struct AppBlockingInfo: Codable {
    let tokenHash: String
    let reasonType: BlockingReasonType
    let updatedAt: Date

    // Learning goal context
    var learningTargetMinutes: Int?
    var learningCurrentMinutes: Int?

    // Daily limit context
    var dailyLimitMinutes: Int?
    var usedMinutes: Int?

    // Downtime context - full allowed time window
    var downtimeWindowStartHour: Int?
    var downtimeWindowStartMinute: Int?
    var downtimeWindowEndHour: Int?
    var downtimeWindowEndMinute: Int?
    var downtimeDayName: String?
    var downtimeSummaryMessage: String?  // Pre-computed summary from config

    // Legacy fields (backwards compatibility)
    var downtimeEndHour: Int?
    var downtimeEndMinute: Int?
}

// MARK: - Shield Theme Configuration

/// Visual theme for each blocking reason type
private struct ShieldTheme {
    let backgroundColor: UIColor
    let iconName: String
    let title: String
    let primaryButtonLabel: String
    let primaryButtonColor: UIColor
}

/// Custom shield configuration that matches the app's theme
/// Provides per-app blocking messages with different visuals for each blocking reason
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Theme Colors

    /// Vibrant Teal - For learning goal blocking (#00A6A6)
    private let vibrantTeal = UIColor(red: 0, green: 0.651, blue: 0.651, alpha: 1)

    /// Learning Peach - Button color for learning (#FFB4A3)
    private let learningPeach = UIColor(red: 1.0, green: 0.706, blue: 0.639, alpha: 1)

    /// Coral Red - For daily limit reached (#E66650)
    private let coralRed = UIColor(red: 0.9, green: 0.4, blue: 0.314, alpha: 1)

    /// Night Purple - For downtime (#4D4D80)
    private let nightPurple = UIColor(red: 0.302, green: 0.302, blue: 0.502, alpha: 1)

    // MARK: - Theme Definitions

    private var learningGoalTheme: ShieldTheme {
        ShieldTheme(
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            iconName: "book.fill",
            title: "Learning Time First!",
            primaryButtonLabel: "Go Learn",
            primaryButtonColor: learningPeach
        )
    }

    private var dailyLimitTheme: ShieldTheme {
        ShieldTheme(
            backgroundColor: coralRed.withAlphaComponent(0.95),
            iconName: "clock.badge.xmark.fill",
            title: "Daily Limit Reached",
            primaryButtonLabel: "OK",
            primaryButtonColor: .systemOrange
        )
    }

    private var downtimeTheme: ShieldTheme {
        ShieldTheme(
            backgroundColor: nightPurple.withAlphaComponent(0.95),
            iconName: "moon.zzz.fill",
            title: "Downtime Active",
            primaryButtonLabel: "OK",
            primaryButtonColor: .systemIndigo
        )
    }

    // MARK: - App Group Data Access

    private let appGroupID = "group.com.screentimerewards.shared"
    private let blockingKeyPrefix = "appBlocking_"

    // MARK: - Token Hashing (MUST match BlockingReasonService exactly)

    /// Generate a stable hash for an ApplicationToken
    private func tokenHash(for token: ApplicationToken) -> String {
        let tokenData = try? JSONEncoder().encode(token)
        guard let data = tokenData else { return "unknown" }
        let hash = SHA256.hash(data: data)
        return "token.sha256." + hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Per-App Blocking Info Lookup

    /// Get blocking info for a specific application
    private func getBlockingInfo(for application: Application) -> AppBlockingInfo? {
        guard let token = application.token else { return nil }
        let hash = tokenHash(for: token)
        return getBlockingInfo(forHash: hash)
    }

    /// Get blocking info by token hash
    private func getBlockingInfo(forHash hash: String) -> AppBlockingInfo? {
        let key = blockingKeyPrefix + hash
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(AppBlockingInfo.self, from: data)
    }

    // MARK: - Theme Selection

    /// Get the appropriate theme for a blocking reason
    private func getTheme(for reasonType: BlockingReasonType?) -> ShieldTheme {
        switch reasonType {
        case .downtime:
            return downtimeTheme
        case .dailyLimitReached:
            return dailyLimitTheme
        case .learningGoal, .none:
            return learningGoalTheme
        }
    }

    // MARK: - Message Generation

    /// Generate the appropriate subtitle message based on blocking info
    private func generateMessage(for blockingInfo: AppBlockingInfo?, context: String = "app") -> String {
        guard let info = blockingInfo else {
            // Fallback to generic learning goal message
            return "Complete your learning goal to unlock this \(context)."
        }

        switch info.reasonType {
        case .learningGoal:
            return generateLearningGoalMessage(info: info, context: context)
        case .dailyLimitReached:
            return generateDailyLimitMessage(info: info)
        case .downtime:
            return generateDowntimeMessage(info: info)
        }
    }

    /// Generate message for learning goal blocking
    private func generateLearningGoalMessage(info: AppBlockingInfo, context: String) -> String {
        guard let target = info.learningTargetMinutes,
              let current = info.learningCurrentMinutes else {
            return "Complete your learning goal to unlock this \(context)."
        }

        let remaining = max(0, target - current)

        if remaining == 0 {
            return "Great job! You've completed your learning goal!"
        } else if remaining == target {
            // No progress yet
            return "Complete \(target) minutes of learning to unlock this \(context). Let's get started!"
        } else if remaining <= 5 {
            // Almost there
            return "Almost there! Just \(remaining) more minutes to go!"
        } else {
            // In progress
            return "You need \(remaining) more minutes. You've done \(current) so far!"
        }
    }

    /// Generate message for daily limit reached
    private func generateDailyLimitMessage(info: AppBlockingInfo) -> String {
        guard let limit = info.dailyLimitMinutes else {
            return "You've reached your daily limit. Try again tomorrow!"
        }

        return "You used your \(limit) minutes for today. Come back tomorrow!"
    }

    /// Generate message for downtime blocking
    /// Format: "This app is only available:\n(summary message)"
    private func generateDowntimeMessage(info: AppBlockingInfo) -> String {
        // Use pre-computed summary from config if available
        if let summary = info.downtimeSummaryMessage {
            return "This app is only available:\n\(summary)"
        }

        // Fallback to full time window format
        if let startHour = info.downtimeWindowStartHour,
           let startMinute = info.downtimeWindowStartMinute,
           let endHour = info.downtimeWindowEndHour,
           let endMinute = info.downtimeWindowEndMinute,
           let dayName = info.downtimeDayName {
            let startTime = formatTime(hour: startHour, minute: startMinute)
            let endTime = formatTime(hour: endHour, minute: endMinute)
            return "This app is only available:\n\(dayName) between \(startTime) and \(endTime)"
        }

        // Fallback to legacy format
        if let endHour = info.downtimeEndHour,
           let endMinute = info.downtimeEndMinute {
            let timeString = formatTime(hour: endHour, minute: endMinute)
            return "This app is only available:\nAfter \(timeString)"
        }

        return "This app is in downtime. Check back later."
    }

    /// Format time as "7:00 AM" or "10:30 PM"
    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        if minute == 0 {
            return "\(displayHour) \(period)"
        } else {
            return String(format: "%d:%02d %@", displayHour, minute, period)
        }
    }

    // MARK: - Shield Configuration Builder

    /// Build a shield configuration with the given theme and message
    private func buildConfiguration(
        theme: ShieldTheme,
        subtitle: String,
        iconOverride: String? = nil
    ) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: theme.backgroundColor,
            icon: UIImage(systemName: iconOverride ?? theme.iconName),
            title: ShieldConfiguration.Label(
                text: theme.title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.9)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: theme.primaryButtonLabel,
                color: .white
            ),
            primaryButtonBackgroundColor: theme.primaryButtonColor,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.white.withAlphaComponent(0.8)
            )
        )
    }

    // MARK: - Shield Configurations (Per-App Lookup)

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // Look up THIS SPECIFIC app's blocking info
        let blockingInfo = getBlockingInfo(for: application)
        let theme = getTheme(for: blockingInfo?.reasonType)
        let subtitle = generateMessage(for: blockingInfo, context: "app")

        return buildConfiguration(theme: theme, subtitle: subtitle)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        // Look up THIS SPECIFIC app's blocking info
        let blockingInfo = getBlockingInfo(for: application)
        let theme = getTheme(for: blockingInfo?.reasonType)
        let subtitle = generateMessage(for: blockingInfo, context: "category")

        return buildConfiguration(theme: theme, subtitle: subtitle)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        // Web domains don't have tokens, use default learning goal theme
        let theme = learningGoalTheme
        let subtitle = "Complete your learning goal to unlock this site."

        return buildConfiguration(theme: theme, subtitle: subtitle, iconOverride: "globe")
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        // Web domains don't have tokens, use default learning goal theme
        let theme = learningGoalTheme
        let subtitle = "Complete your learning goal to unlock this category."

        return buildConfiguration(theme: theme, subtitle: subtitle, iconOverride: "globe")
    }
}
