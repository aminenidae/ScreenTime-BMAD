import Foundation

// MARK: - Avatar Catalog

/// Static catalog of all available avatars and accessories
/// Replace placeholder assets with custom Lottie/images when ready
struct AvatarCatalog {

    // MARK: - Avatars

    static let allAvatars: [AvatarDefinition] = [
        starBuddy,
        roboHelper,
        forestSprite
    ]

    /// Friendly star creature - great for all ages
    static let starBuddy = AvatarDefinition(
        id: "star_buddy",
        name: "Star Buddy",
        description: "A friendly star creature who loves to learn!",
        baseAsset: "star.fill",
        lottieFile: nil, // Replace with Lottie file when available
        evolutionStages: [
            EvolutionStage(
                id: "star_buddy_1",
                level: 1,
                name: "Twinkle",
                requiredMinutes: 0,
                asset: "star.fill",
                lottieFile: nil,
                sizeMultiplier: 1.0,
                unlockMessage: "Welcome, little Twinkle!"
            ),
            EvolutionStage(
                id: "star_buddy_2",
                level: 2,
                name: "Sparkle",
                requiredMinutes: 60,      // 1 hour
                asset: "star.circle.fill",
                lottieFile: nil,
                sizeMultiplier: 1.1,
                unlockMessage: "You've grown into a Sparkle!"
            ),
            EvolutionStage(
                id: "star_buddy_3",
                level: 3,
                name: "Shine",
                requiredMinutes: 300,     // 5 hours
                asset: "sparkles",
                lottieFile: nil,
                sizeMultiplier: 1.2,
                unlockMessage: "Amazing! You're now a Shine!"
            ),
            EvolutionStage(
                id: "star_buddy_4",
                level: 4,
                name: "Supernova",
                requiredMinutes: 600,     // 10 hours
                asset: "sun.max.fill",
                lottieFile: nil,
                sizeMultiplier: 1.3,
                unlockMessage: "Incredible! You've become a Supernova!"
            )
        ],
        ageRange: .all,
        category: .space
    )

    /// Robot helper - appeals to 8-12 year olds
    static let roboHelper = AvatarDefinition(
        id: "robo_helper",
        name: "Robo Helper",
        description: "A smart robot friend who grows smarter with you!",
        baseAsset: "cpu.fill",
        lottieFile: nil,
        evolutionStages: [
            EvolutionStage(
                id: "robo_helper_1",
                level: 1,
                name: "Beep",
                requiredMinutes: 0,
                asset: "cpu.fill",
                lottieFile: nil,
                sizeMultiplier: 1.0,
                unlockMessage: "Beep boop! Hello friend!"
            ),
            EvolutionStage(
                id: "robo_helper_2",
                level: 2,
                name: "Circuit",
                requiredMinutes: 60,
                asset: "memorychip.fill",
                lottieFile: nil,
                sizeMultiplier: 1.1,
                unlockMessage: "Circuits upgraded to Circuit!"
            ),
            EvolutionStage(
                id: "robo_helper_3",
                level: 3,
                name: "Processor",
                requiredMinutes: 300,
                asset: "brain.head.profile.fill",
                lottieFile: nil,
                sizeMultiplier: 1.2,
                unlockMessage: "Processing power increased! Now a Processor!"
            ),
            EvolutionStage(
                id: "robo_helper_4",
                level: 4,
                name: "Quantum",
                requiredMinutes: 600,
                asset: "atom",
                lottieFile: nil,
                sizeMultiplier: 1.3,
                unlockMessage: "Maximum power! You're a Quantum!"
            )
        ],
        ageRange: .older,
        category: .robot
    )

    /// Forest sprite - great for younger kids
    static let forestSprite = AvatarDefinition(
        id: "forest_sprite",
        name: "Forest Sprite",
        description: "A magical forest friend who grows with nature!",
        baseAsset: "leaf.fill",
        lottieFile: nil,
        evolutionStages: [
            EvolutionStage(
                id: "forest_sprite_1",
                level: 1,
                name: "Seedling",
                requiredMinutes: 0,
                asset: "leaf.fill",
                lottieFile: nil,
                sizeMultiplier: 1.0,
                unlockMessage: "A tiny Seedling appears!"
            ),
            EvolutionStage(
                id: "forest_sprite_2",
                level: 2,
                name: "Sprout",
                requiredMinutes: 60,
                asset: "camera.macro",
                lottieFile: nil,
                sizeMultiplier: 1.1,
                unlockMessage: "You've grown into a Sprout!"
            ),
            EvolutionStage(
                id: "forest_sprite_3",
                level: 3,
                name: "Bloom",
                requiredMinutes: 300,
                asset: "laurel.leading",
                lottieFile: nil,
                sizeMultiplier: 1.2,
                unlockMessage: "Beautiful! You're now a Bloom!"
            ),
            EvolutionStage(
                id: "forest_sprite_4",
                level: 4,
                name: "Ancient Oak",
                requiredMinutes: 600,
                asset: "tree.fill",
                lottieFile: nil,
                sizeMultiplier: 1.3,
                unlockMessage: "Magnificent! You've become an Ancient Oak!"
            )
        ],
        ageRange: .young,
        category: .nature
    )

    // MARK: - Accessories

    static let allAccessories: [AvatarAccessory] = hats + glasses + backgrounds + effects

    static let hats: [AvatarAccessory] = [
        AvatarAccessory(
            id: "hat_crown",
            name: "Crown",
            category: .hat,
            asset: "crown.fill",
            rarity: .rare,
            unlockCriteria: AccessoryUnlockCriteria(type: .badgesEarned, value: 5)
        ),
        AvatarAccessory(
            id: "hat_party",
            name: "Party Hat",
            category: .hat,
            asset: "party.popper.fill",
            rarity: .common,
            unlockCriteria: nil // Starter item
        ),
        AvatarAccessory(
            id: "hat_wizard",
            name: "Wizard Hat",
            category: .hat,
            asset: "wand.and.stars",
            rarity: .epic,
            unlockCriteria: AccessoryUnlockCriteria(type: .totalMinutes, value: 300)
        ),
        AvatarAccessory(
            id: "hat_cap",
            name: "Baseball Cap",
            category: .hat,
            asset: "figure.baseball",
            rarity: .uncommon,
            unlockCriteria: AccessoryUnlockCriteria(type: .streakDays, value: 3)
        )
    ]

    static let glasses: [AvatarAccessory] = [
        AvatarAccessory(
            id: "glasses_smart",
            name: "Smart Glasses",
            category: .glasses,
            asset: "eyeglasses",
            rarity: .common,
            unlockCriteria: nil // Starter item
        ),
        AvatarAccessory(
            id: "glasses_star",
            name: "Star Glasses",
            category: .glasses,
            asset: "star.fill",
            rarity: .rare,
            unlockCriteria: AccessoryUnlockCriteria(type: .challengesCompleted, value: 3)
        ),
        AvatarAccessory(
            id: "glasses_heart",
            name: "Heart Glasses",
            category: .glasses,
            asset: "heart.fill",
            rarity: .uncommon,
            unlockCriteria: AccessoryUnlockCriteria(type: .totalMinutes, value: 120)
        )
    ]

    static let backgrounds: [AvatarAccessory] = [
        AvatarAccessory(
            id: "bg_rainbow",
            name: "Rainbow",
            category: .background,
            asset: "rainbow",
            rarity: .rare,
            unlockCriteria: AccessoryUnlockCriteria(type: .streakDays, value: 7)
        ),
        AvatarAccessory(
            id: "bg_stars",
            name: "Starfield",
            category: .background,
            asset: "sparkles",
            rarity: .common,
            unlockCriteria: nil // Starter item
        ),
        AvatarAccessory(
            id: "bg_clouds",
            name: "Cloud Nine",
            category: .background,
            asset: "cloud.fill",
            rarity: .uncommon,
            unlockCriteria: AccessoryUnlockCriteria(type: .totalMinutes, value: 60)
        ),
        AvatarAccessory(
            id: "bg_aurora",
            name: "Aurora",
            category: .background,
            asset: "sun.horizon.fill",
            rarity: .legendary,
            unlockCriteria: AccessoryUnlockCriteria(type: .evolutionLevel, value: 4)
        )
    ]

    static let effects: [AvatarAccessory] = [
        AvatarAccessory(
            id: "effect_sparkle",
            name: "Sparkle Trail",
            category: .effect,
            asset: "sparkle",
            rarity: .uncommon,
            unlockCriteria: AccessoryUnlockCriteria(type: .totalMinutes, value: 30)
        ),
        AvatarAccessory(
            id: "effect_hearts",
            name: "Heart Burst",
            category: .effect,
            asset: "heart.circle.fill",
            rarity: .rare,
            unlockCriteria: AccessoryUnlockCriteria(type: .badgesEarned, value: 3)
        ),
        AvatarAccessory(
            id: "effect_lightning",
            name: "Lightning Aura",
            category: .effect,
            asset: "bolt.fill",
            rarity: .epic,
            unlockCriteria: AccessoryUnlockCriteria(type: .streakDays, value: 14)
        )
    ]

    // MARK: - Helper Methods

    static func avatar(for id: String) -> AvatarDefinition? {
        allAvatars.first { $0.id == id }
    }

    static func accessory(for id: String) -> AvatarAccessory? {
        allAccessories.first { $0.id == id }
    }

    static func accessories(for category: AccessoryCategory) -> [AvatarAccessory] {
        allAccessories.filter { $0.category == category }
    }

    static func starterAccessories() -> [AvatarAccessory] {
        allAccessories.filter { $0.unlockCriteria == nil }
    }

    static var defaultAvatarID: String {
        starBuddy.id
    }
}
