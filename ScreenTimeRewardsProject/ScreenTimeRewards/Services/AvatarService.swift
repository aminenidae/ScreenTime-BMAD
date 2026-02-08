//
//  AvatarService.swift
//  ScreenTimeRewards
//
//  Manages avatar state, evolution, and accessory management
//

import Foundation
import CoreData
import Combine

@MainActor
class AvatarService: ObservableObject {

    // MARK: - Singleton

    static let shared = AvatarService()

    // MARK: - Published State

    @Published private(set) var currentAvatarState: AvatarState?
    @Published private(set) var availableAvatars: [AvatarDefinition] = AvatarCatalog.allAvatars
    @Published private(set) var unlockedAvatarIDs: Set<String> = []
    @Published private(set) var pendingEvolution: EvolutionStage?
    @Published private(set) var recentlyUnlockedAccessories: [AvatarAccessory] = []

    // MARK: - Notifications

    static let avatarEvolved = Notification.Name("AvatarEvolved")
    static let accessoryUnlocked = Notification.Name("AccessoryUnlocked")
    static let moodChanged = Notification.Name("AvatarMoodChanged")

    // MARK: - Private Properties

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // Default unlocked avatars (starters)
        unlockedAvatarIDs = Set([AvatarCatalog.defaultAvatarID])
    }

    // MARK: - Avatar Management

    /// Loads or creates avatar state for a child device
    func loadAvatarState(for childDeviceID: String) async {
        let request = AvatarState.fetchRequest()
        request.predicate = NSPredicate(format: "childDeviceID == %@", childDeviceID)
        request.fetchLimit = 1

        do {
            let results = try viewContext.fetch(request)
            if let existing = results.first {
                currentAvatarState = existing
                updateMoodBasedOnTime()
            } else {
                // Create new avatar state with default avatar
                let newState = AvatarState.create(
                    in: viewContext,
                    avatarID: AvatarCatalog.defaultAvatarID,
                    childDeviceID: childDeviceID
                )
                try viewContext.save()
                currentAvatarState = newState
            }
        } catch {
            print("[AvatarService] Error loading avatar state: \(error)")
        }
    }

    /// Changes the selected avatar
    func selectAvatar(_ avatarID: String) async -> Bool {
        guard unlockedAvatarIDs.contains(avatarID),
              let state = currentAvatarState else {
            return false
        }

        state.avatarID = avatarID
        // Reset to stage 1 for new avatar but keep total minutes
        // This allows evolution progress to be recalculated
        _ = state.checkEvolution()

        do {
            try viewContext.save()
            objectWillChange.send()
            return true
        } catch {
            print("[AvatarService] Error selecting avatar: \(error)")
            return false
        }
    }

    // MARK: - Progress & Evolution

    /// Records learning activity and checks for evolution
    func recordLearningActivity(minutes: Int) async -> EvolutionStage? {
        guard let state = currentAvatarState else { return nil }

        let evolvedStage = state.addNurturingMinutes(minutes)

        // Check for accessory unlocks
        let newAccessories = checkAccessoryUnlocks(state: state)
        if !newAccessories.isEmpty {
            recentlyUnlockedAccessories = newAccessories
            for accessory in newAccessories {
                NotificationCenter.default.post(
                    name: Self.accessoryUnlocked,
                    object: accessory
                )
            }
        }

        // Update mood based on activity
        let hour = Calendar.current.component(.hour, from: Date())
        state.updateMood(basedOn: ActivityLevel.from(minutesToday: minutes, hour: hour))

        do {
            try viewContext.save()
            objectWillChange.send()

            if let evolved = evolvedStage {
                pendingEvolution = evolved
                NotificationCenter.default.post(
                    name: Self.avatarEvolved,
                    object: evolved
                )
            }

            return evolvedStage
        } catch {
            print("[AvatarService] Error saving activity: \(error)")
            return nil
        }
    }

    /// Clears the pending evolution after it's been shown
    func clearPendingEvolution() {
        pendingEvolution = nil
    }

    /// Clears recently unlocked accessories after they've been shown
    func clearRecentlyUnlockedAccessories() {
        recentlyUnlockedAccessories = []
    }

    // MARK: - Mood

    /// Updates avatar mood based on current time and activity
    func updateMoodBasedOnTime() {
        guard let state = currentAvatarState else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        let todayMinutes = Int(state.totalNurturingMinutes) // Simplified - should track daily

        state.updateMood(basedOn: ActivityLevel.from(minutesToday: todayMinutes, hour: hour))

        do {
            try viewContext.save()
            NotificationCenter.default.post(name: Self.moodChanged, object: state.mood)
        } catch {
            print("[AvatarService] Error updating mood: \(error)")
        }
    }

    // MARK: - Accessories

    /// Equips an accessory to the avatar
    func equipAccessory(_ accessory: AvatarAccessory) async -> Bool {
        guard let state = currentAvatarState else { return false }

        let success = state.equipAccessory(accessory)
        if success {
            do {
                try viewContext.save()
                objectWillChange.send()
            } catch {
                print("[AvatarService] Error equipping accessory: \(error)")
                return false
            }
        }
        return success
    }

    /// Unequips an accessory category
    func unequipAccessory(category: AccessoryCategory) async {
        guard let state = currentAvatarState else { return }

        state.unequipAccessory(category: category)
        do {
            try viewContext.save()
            objectWillChange.send()
        } catch {
            print("[AvatarService] Error unequipping accessory: \(error)")
        }
    }

    /// Gets all unlocked accessories for the current avatar
    func getUnlockedAccessories() -> [AvatarAccessory] {
        guard let state = currentAvatarState else { return [] }
        return AvatarCatalog.allAccessories.filter { state.unlockedAccessoryIDs.contains($0.id) }
    }

    /// Gets unlocked accessories for a specific category
    func getUnlockedAccessories(for category: AccessoryCategory) -> [AvatarAccessory] {
        getUnlockedAccessories().filter { $0.category == category }
    }

    /// Gets the currently equipped accessory for a category
    func getEquippedAccessory(for category: AccessoryCategory) -> AvatarAccessory? {
        guard let state = currentAvatarState,
              let accessoryID = state.equippedAccessories.accessoryID(for: category) else {
            return nil
        }
        return AvatarCatalog.accessory(for: accessoryID)
    }

    // MARK: - Private Helpers

    private func checkAccessoryUnlocks(state: AvatarState) -> [AvatarAccessory] {
        var newlyUnlocked: [AvatarAccessory] = []

        for accessory in AvatarCatalog.allAccessories {
            // Skip if already unlocked
            guard !state.unlockedAccessoryIDs.contains(accessory.id) else { continue }

            // Check unlock criteria
            if let criteria = accessory.unlockCriteria {
                let shouldUnlock: Bool

                switch criteria.type {
                case .totalMinutes:
                    shouldUnlock = Int(state.totalNurturingMinutes) >= criteria.value
                case .evolutionLevel:
                    shouldUnlock = Int(state.currentStageLevel) >= criteria.value
                case .streakDays:
                    // Would need to integrate with StreakRecord
                    shouldUnlock = false
                case .badgesEarned:
                    // Would need to integrate with Badge count
                    shouldUnlock = false
                case .challengesCompleted:
                    // Would need to integrate with Challenge count
                    shouldUnlock = false
                }

                if shouldUnlock {
                    state.unlockAccessory(accessory.id)
                    newlyUnlocked.append(accessory)
                }
            }
        }

        return newlyUnlocked
    }

    // MARK: - Statistics

    var totalLearningMinutes: Int {
        Int(currentAvatarState?.totalNurturingMinutes ?? 0)
    }

    var currentEvolutionLevel: Int {
        Int(currentAvatarState?.currentStageLevel ?? 1)
    }

    var progressToNextLevel: Double {
        currentAvatarState?.progressToNextEvolution ?? 0
    }

    var minutesToNextLevel: Int? {
        currentAvatarState?.minutesToNextEvolution
    }

    var isMaxLevel: Bool {
        currentAvatarState?.isMaxLevel ?? false
    }
}
