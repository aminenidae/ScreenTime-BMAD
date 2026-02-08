//
//  ShieldDataService.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-22.
//

import Foundation

/// Shared data structure for challenge info displayed on shields
/// This data is written by the main app and read by the ShieldConfigurationExtension
struct ShieldChallengeData: Codable {
    let challengeTitle: String
    let targetAppNames: [String]  // Names of learning apps
    let targetMinutes: Int        // Goal in minutes
    let currentMinutes: Int       // Progress so far
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

/// Service to share challenge data between main app and shield extension via App Groups
class ShieldDataService {
    static let shared = ShieldDataService()

    private let appGroupID = "group.com.screentimerewards.shared"
    private let shieldDataKey = "shield_challenge_data"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    // MARK: - Main App Methods (Write)

    /// Updates the shield data with current challenge info
    /// Call this whenever challenge progress changes
    func updateShieldData(
        challengeTitle: String,
        targetAppNames: [String],
        targetMinutes: Int,
        currentMinutes: Int
    ) {
        let data = ShieldChallengeData(
            challengeTitle: challengeTitle,
            targetAppNames: targetAppNames,
            targetMinutes: targetMinutes,
            currentMinutes: currentMinutes,
            updatedAt: Date()
        )

        saveShieldData(data)
    }

    /// Saves shield challenge data to shared UserDefaults
    private func saveShieldData(_ data: ShieldChallengeData) {
        guard let defaults = sharedDefaults else {
            print("⚠️ ShieldDataService: Could not access App Group UserDefaults")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: shieldDataKey)
            print("✅ ShieldDataService: Updated shield data - \(data.currentMinutes)/\(data.targetMinutes) min")
        } catch {
            print("❌ ShieldDataService: Failed to encode shield data: \(error)")
        }
    }

    /// Clears shield data (e.g., when no active challenges)
    func clearShieldData() {
        sharedDefaults?.removeObject(forKey: shieldDataKey)
    }

    // MARK: - Shield Extension Methods (Read)

    /// Retrieves the current shield challenge data
    /// Called by ShieldConfigurationExtension to display dynamic info
    func getShieldData() -> ShieldChallengeData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: shieldDataKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ShieldChallengeData.self, from: data)
        } catch {
            print("❌ ShieldDataService: Failed to decode shield data: \(error)")
            return nil
        }
    }
}
