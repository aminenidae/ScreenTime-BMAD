//
//  ShieldDataService.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-22.
//

import Foundation
import FamilyControls
import ManagedSettings

/// Shared data structure for challenge info displayed on shields
/// This data is written by the main app and read by the ShieldConfigurationExtension
struct ShieldChallengeData: Codable {
    let challengeTitle: String
    let targetAppNames: [String]  // Names of learning apps
    let targetMinutes: Int        // Goal in minutes
    let currentMinutes: Int       // Progress so far (main app's view)
    let updatedAt: Date

    // SOLUTION 2: Learning app IDs for extension goal checking
    // Extension sums usage for these apps to determine goal completion
    let learningAppIDs: [String]  // Logical IDs of learning apps (e.g., "com.duolingo")

    // SOLUTION 2b: Reward duration for extension to re-apply shields when expired
    let rewardDurationMinutes: Int  // How long rewards last (default 30)

    var minutesRemaining: Int {
        max(0, targetMinutes - currentMinutes)
    }

    var isComplete: Bool {
        currentMinutes >= targetMinutes
    }

    // Full initializer with all fields
    init(challengeTitle: String, targetAppNames: [String], targetMinutes: Int, currentMinutes: Int, updatedAt: Date, learningAppIDs: [String] = [], rewardDurationMinutes: Int = 30) {
        self.challengeTitle = challengeTitle
        self.targetAppNames = targetAppNames
        self.targetMinutes = targetMinutes
        self.currentMinutes = currentMinutes
        self.updatedAt = updatedAt
        self.learningAppIDs = learningAppIDs
        self.rewardDurationMinutes = rewardDurationMinutes
    }

    // Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challengeTitle = try container.decode(String.self, forKey: .challengeTitle)
        targetAppNames = try container.decode([String].self, forKey: .targetAppNames)
        targetMinutes = try container.decode(Int.self, forKey: .targetMinutes)
        currentMinutes = try container.decode(Int.self, forKey: .currentMinutes)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        learningAppIDs = try container.decodeIfPresent([String].self, forKey: .learningAppIDs) ?? []
        rewardDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .rewardDurationMinutes) ?? 30
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
        currentMinutes: Int,
        learningAppIDs: [String] = [],  // SOLUTION 2: For extension goal checking
        rewardDurationMinutes: Int = 30  // SOLUTION 2b: For extension to re-apply shields
    ) {
        let data = ShieldChallengeData(
            challengeTitle: challengeTitle,
            targetAppNames: targetAppNames,
            targetMinutes: targetMinutes,
            currentMinutes: currentMinutes,
            updatedAt: Date(),
            learningAppIDs: learningAppIDs,
            rewardDurationMinutes: rewardDurationMinutes
        )

        saveShieldData(data)

        #if DEBUG
        print("[ShieldDataService] 📊 Updated shield data: \(currentMinutes)/\(targetMinutes) min, learningAppIDs: \(learningAppIDs.count), rewardDuration: \(rewardDurationMinutes)min")
        #endif
    }

    // MARK: - Blocked App Tokens Persistence (SOLUTION 2b)

    private let blockedTokensKey = "blocked_app_tokens"

    /// Persist blocked app tokens so extension can re-apply shields when reward expires
    /// Call this when shields are initially applied
    func persistBlockedTokens(_ tokens: Set<ApplicationToken>) {
        guard let defaults = sharedDefaults else {
            print("⚠️ ShieldDataService: Could not access App Group for blocked tokens")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(Array(tokens))
            defaults.set(encoded, forKey: blockedTokensKey)
            defaults.synchronize()
            print("✅ ShieldDataService: Persisted \(tokens.count) blocked app tokens")
        } catch {
            print("❌ ShieldDataService: Failed to encode blocked tokens: \(error)")
        }
    }

    /// Retrieve blocked app tokens (called by extension to re-apply shields)
    func getBlockedTokens() -> Set<ApplicationToken>? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: blockedTokensKey) else {
            return nil
        }

        do {
            let tokens = try JSONDecoder().decode([ApplicationToken].self, from: data)
            return Set(tokens)
        } catch {
            print("❌ ShieldDataService: Failed to decode blocked tokens: \(error)")
            return nil
        }
    }

    /// Clear blocked tokens (e.g., when challenge ends)
    func clearBlockedTokens() {
        sharedDefaults?.removeObject(forKey: blockedTokensKey)
        sharedDefaults?.synchronize()
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
            defaults.synchronize()
            print("✅ ShieldDataService: Updated shield data - \(data.currentMinutes)/\(data.targetMinutes) min")
        } catch {
            print("❌ ShieldDataService: Failed to encode shield data: \(error)")
        }
    }

    /// Clears shield data (e.g., when no active challenges)
    func clearShieldData() {
        sharedDefaults?.removeObject(forKey: shieldDataKey)
        sharedDefaults?.synchronize()
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
