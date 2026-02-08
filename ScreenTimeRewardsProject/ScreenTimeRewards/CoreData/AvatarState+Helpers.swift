//
//  AvatarState+Helpers.swift
//  ScreenTimeRewards
//

import Foundation
import CoreData

extension AvatarState {

    // MARK: - Computed Properties

    var mood: AvatarMood {
        get {
            AvatarMood(rawValue: currentMood ?? "happy") ?? .happy
        }
        set {
            currentMood = newValue.rawValue
        }
    }

    var equippedAccessories: EquippedAccessories {
        get {
            guard let json = equippedAccessoriesJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(EquippedAccessories.self, from: data) else {
                return EquippedAccessories()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                equippedAccessoriesJSON = json
            }
        }
    }

    var unlockedAccessoryIDs: Set<String> {
        get {
            guard let json = unlockedAccessoriesJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                // Include starter accessories by default
                return Set(AvatarCatalog.starterAccessories().map { $0.id })
            }
            return Set(decoded)
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue)),
               let json = String(data: data, encoding: .utf8) {
                unlockedAccessoriesJSON = json
            }
        }
    }

    // MARK: - Avatar Definition

    var avatarDefinition: AvatarDefinition? {
        guard let id = avatarID else { return nil }
        return AvatarCatalog.avatar(for: id)
    }

    var currentEvolutionStage: EvolutionStage? {
        avatarDefinition?.stage(for: Int(currentStageLevel))
    }

    var nextEvolutionStage: EvolutionStage? {
        avatarDefinition?.nextStage(after: Int(currentStageLevel))
    }

    // MARK: - Progress Calculations

    var minutesToNextEvolution: Int? {
        guard let next = nextEvolutionStage else { return nil }
        return max(0, next.requiredMinutes - Int(totalNurturingMinutes))
    }

    var progressToNextEvolution: Double {
        guard let current = currentEvolutionStage,
              let next = nextEvolutionStage else {
            return 1.0 // Max level
        }

        let progressRange = next.requiredMinutes - current.requiredMinutes
        guard progressRange > 0 else { return 1.0 }

        let currentProgress = Int(totalNurturingMinutes) - current.requiredMinutes
        return min(1.0, max(0.0, Double(currentProgress) / Double(progressRange)))
    }

    var isMaxLevel: Bool {
        guard let definition = avatarDefinition else { return false }
        return Int(currentStageLevel) >= (definition.evolutionStages.map { $0.level }.max() ?? 1)
    }

    // MARK: - Factory Methods

    static func create(
        in context: NSManagedObjectContext,
        avatarID: String,
        childDeviceID: String
    ) -> AvatarState {
        let state = AvatarState(context: context)
        state.stateID = UUID().uuidString
        state.avatarID = avatarID
        state.childDeviceID = childDeviceID
        state.currentStageLevel = 1
        state.currentMood = AvatarMood.happy.rawValue
        state.totalNurturingMinutes = 0
        state.createdAt = Date()
        state.lastInteractionDate = Date()

        // Initialize with starter accessories unlocked
        let starters = AvatarCatalog.starterAccessories().map { $0.id }
        state.unlockedAccessoryIDs = Set(starters)
        state.equippedAccessories = EquippedAccessories()

        return state
    }

    // MARK: - Actions

    func addNurturingMinutes(_ minutes: Int) -> EvolutionStage? {
        totalNurturingMinutes += Int32(minutes)
        lastInteractionDate = Date()

        // Check for evolution
        return checkEvolution()
    }

    func checkEvolution() -> EvolutionStage? {
        guard let definition = avatarDefinition else { return nil }

        // Find the highest stage we qualify for
        let qualifyingStages = definition.evolutionStages.filter {
            $0.requiredMinutes <= Int(totalNurturingMinutes)
        }

        guard let highestQualifying = qualifyingStages.max(by: { $0.level < $1.level }),
              highestQualifying.level > currentStageLevel else {
            return nil
        }

        // Evolve!
        let previousLevel = currentStageLevel
        currentStageLevel = Int16(highestQualifying.level)

        // Return the new stage if we actually evolved
        return previousLevel < currentStageLevel ? highestQualifying : nil
    }

    func equipAccessory(_ accessory: AvatarAccessory) -> Bool {
        guard unlockedAccessoryIDs.contains(accessory.id) else { return false }

        var equipped = equippedAccessories
        equipped.equip(accessory.id, for: accessory.category)
        equippedAccessories = equipped
        return true
    }

    func unequipAccessory(category: AccessoryCategory) {
        var equipped = equippedAccessories
        equipped.unequip(category)
        equippedAccessories = equipped
    }

    func unlockAccessory(_ accessoryID: String) {
        var unlocked = unlockedAccessoryIDs
        unlocked.insert(accessoryID)
        unlockedAccessoryIDs = unlocked
    }

    func updateMood(basedOn activityLevel: ActivityLevel) {
        mood = activityLevel.suggestedMood
    }
}

// MARK: - Activity Level

enum ActivityLevel {
    case veryActive      // Lots of learning today
    case active          // Good amount of learning
    case moderate        // Some learning
    case inactive        // No learning today
    case sleeping        // Late night / early morning

    var suggestedMood: AvatarMood {
        switch self {
        case .veryActive: return .excited
        case .active: return .happy
        case .moderate: return .neutral
        case .inactive: return .sad
        case .sleeping: return .sleepy
        }
    }

    static func from(minutesToday: Int, hour: Int) -> ActivityLevel {
        // Night time
        if hour < 6 || hour >= 22 {
            return .sleeping
        }

        // Based on learning minutes
        switch minutesToday {
        case 60...: return .veryActive
        case 30..<60: return .active
        case 10..<30: return .moderate
        default: return .inactive
        }
    }
}
