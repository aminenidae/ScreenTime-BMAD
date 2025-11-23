//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Created by Amine Nidae on 2025-11-22.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Custom shield configuration that matches the app's theme
/// Provides a kid-friendly, encouraging shield screen
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Theme Colors (matching AppTheme)

    /// Vibrant Teal - Primary accent (#00A6A6)
    private let vibrantTeal = UIColor(red: 0, green: 0.651, blue: 0.651, alpha: 1)

    /// Learning Peach - Soft peachy-coral (#FFB4A3)
    private let learningPeach = UIColor(red: 1.0, green: 0.706, blue: 0.639, alpha: 1)

    // MARK: - Shield Configurations

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "book.fill"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Complete your learning goal to unlock this app. You've got this!",
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
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "book.fill"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Complete your learning goal to unlock this category. Keep going!",
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
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "globe"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Complete your learning goal to browse this site.",
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
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: vibrantTeal.withAlphaComponent(0.95),
            icon: UIImage(systemName: "globe"),
            title: ShieldConfiguration.Label(
                text: "Learning Time First!",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Complete your learning goal to browse this category.",
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
