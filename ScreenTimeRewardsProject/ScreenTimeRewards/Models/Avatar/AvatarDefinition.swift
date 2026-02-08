import Foundation

// MARK: - Avatar Definition

/// Defines a type of avatar that can be selected by the child
struct AvatarDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let baseAsset: String           // SF Symbol name or image asset name
    let lottieFile: String?         // Optional Lottie animation file
    let evolutionStages: [EvolutionStage]
    let ageRange: AgeRange          // Target age group
    let category: AvatarCategory

    var currentStage: EvolutionStage? {
        evolutionStages.first
    }

    func stage(for level: Int) -> EvolutionStage? {
        evolutionStages.first { $0.level == level }
    }

    func nextStage(after level: Int) -> EvolutionStage? {
        evolutionStages.first { $0.level == level + 1 }
    }
}

// MARK: - Evolution Stage

/// Represents a growth stage of an avatar
struct EvolutionStage: Codable, Identifiable, Hashable {
    let id: String
    let level: Int                  // 1-4 typically
    let name: String                // "Hatchling", "Explorer", "Champion", "Legend"
    let requiredMinutes: Int        // Total learning minutes to reach this stage
    let asset: String               // Stage-specific SF Symbol or asset
    let lottieFile: String?         // Optional stage-specific Lottie animation
    let sizeMultiplier: Double      // Visual scale (1.0, 1.1, 1.2, 1.3)
    let unlockMessage: String       // Message shown when evolving to this stage

    var requiredHours: Double {
        Double(requiredMinutes) / 60.0
    }
}

// MARK: - Avatar Category

enum AvatarCategory: String, Codable, CaseIterable {
    case creature = "creature"      // Animals, magical creatures
    case robot = "robot"            // Robots, machines
    case nature = "nature"          // Plants, elements
    case space = "space"            // Astronauts, aliens

    var displayName: String {
        switch self {
        case .creature: return "Creatures"
        case .robot: return "Robots"
        case .nature: return "Nature"
        case .space: return "Space"
        }
    }

    var sfSymbol: String {
        switch self {
        case .creature: return "pawprint.fill"
        case .robot: return "cpu.fill"
        case .nature: return "leaf.fill"
        case .space: return "sparkles"
        }
    }
}

// MARK: - Age Range

enum AgeRange: String, Codable, CaseIterable {
    case young = "young"        // 6-8 years
    case middle = "middle"      // 8-10 years
    case older = "older"        // 10-12 years
    case all = "all"            // All ages

    var displayName: String {
        switch self {
        case .young: return "Ages 6-8"
        case .middle: return "Ages 8-10"
        case .older: return "Ages 10-12"
        case .all: return "All Ages"
        }
    }

    func includes(age: Int) -> Bool {
        switch self {
        case .young: return age >= 6 && age <= 8
        case .middle: return age >= 8 && age <= 10
        case .older: return age >= 10 && age <= 12
        case .all: return age >= 6 && age <= 12
        }
    }
}

// MARK: - Avatar Mood

enum AvatarMood: String, Codable, CaseIterable {
    case happy = "happy"
    case excited = "excited"
    case sleepy = "sleepy"
    case neutral = "neutral"
    case sad = "sad"
    case celebrating = "celebrating"

    var sfSymbol: String {
        switch self {
        case .happy: return "face.smiling.fill"
        case .excited: return "star.fill"
        case .sleepy: return "moon.zzz.fill"
        case .neutral: return "face.dashed"
        case .sad: return "cloud.rain.fill"
        case .celebrating: return "party.popper.fill"
        }
    }

    var animationIntensity: Double {
        switch self {
        case .excited, .celebrating: return 1.5
        case .happy: return 1.0
        case .neutral: return 0.7
        case .sleepy, .sad: return 0.4
        }
    }
}
