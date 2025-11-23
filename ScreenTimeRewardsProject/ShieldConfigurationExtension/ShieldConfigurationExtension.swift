//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Created by Amine Nidae on 2025-11-22.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

// MARK: - Shared Data Model (duplicated from main app for extension access)

/// Challenge data shared from main app via App Groups
private struct ShieldChallengeData: Codable {
    let challengeTitle: String
    let targetAppNames: [String]
    let targetMinutes: Int
    let currentMinutes: Int
    let updatedAt: Date

    var minutesRemaining: Int {
        max(0, targetMinutes - currentMinutes)
    }

    var isComplete: Bool {
        currentMinutes >= targetMinutes
    }

    /// Formatted string for target apps (e.g., "Duolingo and Khan Academy")
    var targetAppsFormatted: String {
        guard !targetAppNames.isEmpty else { return "learning apps" }

        if targetAppNames.count == 1 {
            return targetAppNames[0]
        } else if targetAppNames.count == 2 {
            return "\(targetAppNames[0]) and \(targetAppNames[1])"
        } else {
            let allButLast = targetAppNames.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(targetAppNames.last!)"
        }
    }
}

/// Custom shield configuration that matches the app's theme
/// Provides a kid-friendly, encouraging shield screen with dynamic progress info
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Theme Colors (matching AppTheme)

    /// Vibrant Teal - Primary accent (#00A6A6)
    private let vibrantTeal = UIColor(red: 0, green: 0.651, blue: 0.651, alpha: 1)

    /// Learning Peach - Soft peachy-coral (#FFB4A3)
    private let learningPeach = UIColor(red: 1.0, green: 0.706, blue: 0.639, alpha: 1)

    // MARK: - App Group Data Access

    private let appGroupID = "group.com.screentimerewards.shared"
    private let shieldDataKey = "shield_challenge_data"

    /// Retrieves challenge data from shared App Group UserDefaults
    private func getChallengeData() -> ShieldChallengeData? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: shieldDataKey) else {
            return nil
        }

        return try? JSONDecoder().decode(ShieldChallengeData.self, from: data)
    }

    // MARK: - Dynamic Message Generation

    /// Generates a dynamic subtitle message based on current challenge progress
    private func generateDynamicSubtitle(for context: String = "app") -> String {
        guard let challengeData = getChallengeData() else {
            // Fallback to generic message if no data available
            return "Complete your learning goal to unlock this \(context). You've got this!"
        }

        let remaining = challengeData.minutesRemaining
        let target = challengeData.targetMinutes
        let apps = challengeData.targetAppsFormatted

        if challengeData.isComplete {
            return "Great job! You've completed your learning goal! 🎉"
        }

        if remaining == target {
            // No progress yet
            return "Complete \(target) minutes of \(apps) to unlock this \(context). Let's get started!"
        } else if remaining <= 5 {
            // Almost there!
            return "Almost there! Just \(remaining) more minutes of \(apps) to go! 💪"
        } else {
            // In progress
            return "You need \(remaining) more minutes of \(apps). You've done \(challengeData.currentMinutes) so far!"
        }
    }

    /// Generates a short progress indicator
    private func generateProgressIndicator() -> String {
        guard let data = getChallengeData(), data.targetMinutes > 0 else {
            return ""
        }
        return "\(data.currentMinutes)/\(data.targetMinutes) min"
    }

    // MARK: - Shield Configurations

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let subtitle = generateDynamicSubtitle(for: "app")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "book.fill"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.9)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Go Learn",
                color: .white
            ),
            primaryButtonBackgroundColor: learningPeach,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.white.withAlphaComponent(0.8)
            )
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let subtitle = generateDynamicSubtitle(for: "category")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "book.fill"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.9)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Go Learn",
                color: .white
            ),
            primaryButtonBackgroundColor: learningPeach,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.white.withAlphaComponent(0.8)
            )
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let subtitle = generateDynamicSubtitle(for: "site")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "globe"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.9)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Go Learn",
                color: .white
            ),
            primaryButtonBackgroundColor: learningPeach,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.white.withAlphaComponent(0.8)
            )
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let subtitle = generateDynamicSubtitle(for: "category")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "globe"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.9)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Go Learn",
                color: .white
            ),
            primaryButtonBackgroundColor: learningPeach,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.white.withAlphaComponent(0.8)
            )
        )
    }
}
