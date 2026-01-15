import Foundation
import SwiftUI

// MARK: - Avatar Accessory

/// An accessory item that can be equipped on an avatar
struct AvatarAccessory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: AccessoryCategory
    let asset: String               // SF Symbol or image asset name
    let rarity: AccessoryRarity
    let unlockCriteria: AccessoryUnlockCriteria?

    var isUnlockable: Bool {
        unlockCriteria != nil
    }
}

// MARK: - Accessory Category

enum AccessoryCategory: String, Codable, CaseIterable {
    case hat = "hat"
    case glasses = "glasses"
    case background = "background"
    case effect = "effect"          // Particle effects, auras

    var displayName: String {
        switch self {
        case .hat: return "Hats"
        case .glasses: return "Glasses"
        case .background: return "Backgrounds"
        case .effect: return "Effects"
        }
    }

    var sfSymbol: String {
        switch self {
        case .hat: return "hat.widebrim.fill"
        case .glasses: return "eyeglasses"
        case .background: return "square.fill"
        case .effect: return "sparkle"
        }
    }

    var layerOrder: Int {
        switch self {
        case .background: return 0
        case .effect: return 1
        case .glasses: return 3
        case .hat: return 4
        }
    }
}

// MARK: - Accessory Rarity

enum AccessoryRarity: String, Codable, CaseIterable {
    case common = "common"
    case uncommon = "uncommon"
    case rare = "rare"
    case epic = "epic"
    case legendary = "legendary"

    var displayName: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    var color: Color {
        switch self {
        case .common: return .gray
        case .uncommon: return .green
        case .rare: return .blue
        case .epic: return .purple
        case .legendary: return .orange
        }
    }

    var glowIntensity: Double {
        switch self {
        case .common: return 0
        case .uncommon: return 0.2
        case .rare: return 0.4
        case .epic: return 0.6
        case .legendary: return 0.8
        }
    }
}

// MARK: - Unlock Criteria

struct AccessoryUnlockCriteria: Codable, Hashable {
    let type: UnlockType
    let value: Int

    enum UnlockType: String, Codable {
        case totalMinutes = "totalMinutes"      // Total learning minutes
        case streakDays = "streakDays"          // Consecutive days
        case badgesEarned = "badgesEarned"      // Number of badges
        case evolutionLevel = "evolutionLevel"  // Avatar evolution stage
        case challengesCompleted = "challengesCompleted"
    }

    var displayDescription: String {
        switch type {
        case .totalMinutes:
            let hours = value / 60
            return hours > 0 ? "Learn for \(hours) hours" : "Learn for \(value) minutes"
        case .streakDays:
            return "Maintain a \(value)-day streak"
        case .badgesEarned:
            return "Earn \(value) badges"
        case .evolutionLevel:
            return "Reach evolution level \(value)"
        case .challengesCompleted:
            return "Complete \(value) challenges"
        }
    }
}

// MARK: - Equipped Accessories State

struct EquippedAccessories: Codable, Hashable {
    var hat: String?
    var glasses: String?
    var background: String?
    var effect: String?

    mutating func equip(_ accessoryID: String, for category: AccessoryCategory) {
        switch category {
        case .hat: hat = accessoryID
        case .glasses: glasses = accessoryID
        case .background: background = accessoryID
        case .effect: effect = accessoryID
        }
    }

    mutating func unequip(_ category: AccessoryCategory) {
        switch category {
        case .hat: hat = nil
        case .glasses: glasses = nil
        case .background: background = nil
        case .effect: effect = nil
        }
    }

    func accessoryID(for category: AccessoryCategory) -> String? {
        switch category {
        case .hat: return hat
        case .glasses: return glasses
        case .background: return background
        case .effect: return effect
        }
    }

    var equippedCount: Int {
        [hat, glasses, background, effect].compactMap { $0 }.count
    }
}
