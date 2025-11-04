import Foundation
import CoreData
import Combine

@MainActor
class ChallengeService: ObservableObject {
    static let shared = ChallengeService()

    // MARK: - Dependencies
    private let persistenceController = PersistenceController.shared

    // MARK: - Published Properties
    @Published private(set) var activeChallenges: [Challenge] = []
    @Published private(set) var challengeProgress: [String: ChallengeProgress] = [:]
    @Published private(set) var unlockedBadges: [Badge] = []
    @Published private(set) var currentStreak: StreakRecord?

    // MARK: - Notifications
    static let challengeProgressUpdated = Notification.Name("ChallengeProgressUpdated")
    static let challengeCompleted = Notification.Name("ChallengeCompleted")
    static let badgeUnlocked = Notification.Name("BadgeUnlocked")
    static let streakUpdated = Notification.Name("StreakUpdated")

    private init() {
        // Initialize badges for new users
        Task {
            await initializeStarterBadges()
        }
    }

    // MARK: - Challenge Management

    func createChallenge(
        title: String,
        description: String,
        goalType: String,
        targetValue: Int,
        bonusPercentage: Int,
        targetApps: [String]?,
        startDate: Date,
        endDate: Date?,
        createdBy: String,
        assignedTo: String
    ) async throws {
        let context = persistenceController.container.viewContext

        // Create Core Data entity
        let challenge = Challenge(context: context)
        challenge.challengeID = UUID().uuidString
        challenge.title = title
        challenge.challengeDescription = description
        challenge.goalType = goalType
        challenge.targetValue = Int32(targetValue)
        challenge.bonusPercentage = Int16(bonusPercentage)

        // Encode targetApps as JSON
        if let targetApps = targetApps {
            let json = try? JSONEncoder().encode(targetApps)
            challenge.targetAppsJSON = String(data: json!, encoding: .utf8)
        }

        challenge.startDate = startDate
        challenge.endDate = endDate
        challenge.isActive = true
        challenge.createdBy = createdBy
        challenge.assignedTo = assignedTo

        try context.save()

        // Create initial progress entry for child
        let progress = ChallengeProgress(context: context)
        progress.progressID = UUID().uuidString
        progress.challengeID = challenge.challengeID
        progress.childDeviceID = assignedTo
        progress.currentValue = 0
        progress.targetValue = Int32(targetValue)
        progress.isCompleted = false
        progress.completedDate = nil
        progress.bonusPointsEarned = 0
        progress.lastUpdated = Date()

        try context.save()

        #if DEBUG
        print("[ChallengeService] ✅ Created challenge: \(title)")
        #endif
    }

    func fetchActiveChallenges(for deviceID: String) async throws -> [Challenge] {
        let context = persistenceController.container.viewContext
        let fetchRequest = Challenge.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "assignedTo == %@ AND isActive == YES",
            deviceID
        )

        let challenges = try context.fetch(fetchRequest)
        activeChallenges = challenges
        return challenges
    }

    // MARK: - Progress Tracking

    func updateProgressForUsage(appID: String, duration: TimeInterval, deviceID: String) async {
        let minutes = Int(duration / 60)

        #if DEBUG
        print("[ChallengeService] 📊 Updating progress for \(minutes) minutes on app: \(appID)")
        #endif

        // Fetch active challenges for this device
        guard let challenges = try? await fetchActiveChallenges(for: deviceID) else {
            return
        }

        for challenge in challenges {
            // Check if this challenge applies to this app
            let appliesToApp: Bool
            if let jsonString = challenge.targetAppsJSON,
               let data = jsonString.data(using: .utf8),
               let targetApps = try? JSONDecoder().decode([String].self, from: data) {
                appliesToApp = targetApps.contains(appID)
            } else {
                // If no specific apps, applies to all learning apps
                appliesToApp = true
            }

            guard appliesToApp else { continue }

            // Update progress based on goal type
            guard let challengeID = challenge.challengeID,
                  let goalType = challenge.goalType else { continue }

            switch goalType {
            case "daily_minutes":
                await updateDailyProgress(for: challengeID, incrementBy: minutes)
            case "weekly_minutes":
                await updateWeeklyProgress(for: challengeID, incrementBy: minutes)
            case "specific_apps":
                await updateProgress(for: challengeID, incrementBy: minutes)
            case "streak":
                // Streak is updated separately based on daily goals
                continue
            default:
                continue
            }
        }
    }

    private func updateProgress(for challengeID: String, incrementBy minutes: Int) async {
        guard let progress = try? await fetchProgress(for: challengeID) else {
            return
        }

        let context = persistenceController.container.viewContext

        progress.currentValue += Int32(minutes)
        progress.lastUpdated = Date()

        // Check for completion
        if progress.currentValue >= progress.targetValue && !progress.isCompleted {
            progress.isCompleted = true
            progress.completedDate = Date()

            // Award bonus points
            let bonusPoints = try? await awardBonusPoints(for: challengeID)
            progress.bonusPointsEarned = Int32(bonusPoints ?? 0)

            #if DEBUG
            print("[ChallengeService] 🎉 Challenge completed! Bonus points: \(progress.bonusPointsEarned)")
            #endif

            // Post notification
            NotificationCenter.default.post(
                name: ChallengeService.challengeCompleted,
                object: nil,
                userInfo: ["challengeID": challengeID]
            )

            // Check for badge unlocks
            if let childDeviceID = progress.childDeviceID {
                await checkBadgeUnlocks(for: childDeviceID)
            }
        }

        // Save progress
        try? context.save()

        // Update in-memory cache
        challengeProgress[challengeID] = progress

        // Post progress update notification
        NotificationCenter.default.post(
            name: ChallengeService.challengeProgressUpdated,
            object: nil,
            userInfo: ["challengeID": challengeID, "progress": progress]
        )
    }

    private func updateDailyProgress(for challengeID: String, incrementBy minutes: Int) async {
        // Reset progress if new day
        guard let progress = try? await fetchProgress(for: challengeID) else { return }

        let calendar = Calendar.current
        if let lastUpdated = progress.lastUpdated,
           !calendar.isDateInToday(lastUpdated) {
            // New day - reset progress
            progress.currentValue = 0
            progress.isCompleted = false
            progress.completedDate = nil
        }

        await updateProgress(for: challengeID, incrementBy: minutes)
    }

    private func updateWeeklyProgress(for challengeID: String, incrementBy minutes: Int) async {
        // Reset progress if new week
        guard let progress = try? await fetchProgress(for: challengeID) else { return }

        let calendar = Calendar.current
        let currentWeek = calendar.component(.weekOfYear, from: Date())

        if let lastUpdated = progress.lastUpdated {
            let progressWeek = calendar.component(.weekOfYear, from: lastUpdated)

            if currentWeek != progressWeek {
                // New week - reset progress
                progress.currentValue = 0
                progress.isCompleted = false
                progress.completedDate = nil
            }
        }

        await updateProgress(for: challengeID, incrementBy: minutes)
    }

    // MARK: - Bonus Calculation

    func calculateBonusPoints(basePoints: Int, for deviceID: String) -> Int {
        var totalBonus = 0

        // Apply challenge bonuses
        for (challengeID, progress) in challengeProgress where progress.isCompleted {
            // Find the challenge
            if let challenge = activeChallenges.first(where: { $0.challengeID == challengeID }) {
                let bonus = (basePoints * Int(challenge.bonusPercentage)) / 100
                totalBonus += bonus
            }
        }

        // Apply streak multiplier
        if let streak = currentStreak {
            let currentStreakValue = streak.currentStreak
            // Simple multiplier: 1% per streak day, max 30%
            let multiplier = min(Double(currentStreakValue) * 0.01, 0.30)
            let streakBonus = Int(Double(basePoints) * multiplier)
            totalBonus += streakBonus
        }

        #if DEBUG
        print("[ChallengeService] 💰 Bonus calculation: \(basePoints) base + \(totalBonus) bonus")
        #endif

        return totalBonus
    }

    func awardBonusPoints(for challengeID: String) async throws -> Int {
        guard let progress = try? await fetchProgress(for: challengeID),
              let challenge = activeChallenges.first(where: { $0.challengeID == challengeID }) else {
            return 0
        }

        // Calculate bonus based on base learning points earned during challenge
        // This would need integration with AppUsageViewModel to get actual base points
        // For now, use a simple calculation
        let basePoints = Int(progress.currentValue) * 10  // Assume 10 points per minute
        let bonusPoints = (basePoints * Int(challenge.bonusPercentage)) / 100

        return bonusPoints
    }

    // MARK: - Badge System

    private func initializeStarterBadges() async {
        // TODO: Create badge entries for each child device
        // This should be called when a new child device is registered
    }

    func checkBadgeUnlocks(for deviceID: String) async -> [Badge] {
        // TODO: Implement badge unlock logic
        // Check each badge's criteria against current stats
        // Unlock any badges that meet criteria
        return []
    }

    // MARK: - Streak System

    func updateStreak(for deviceID: String, date: Date) async {
        // TODO: Implement streak tracking
        // Check if daily goal was met
        // Increment or reset streak accordingly
    }

    // MARK: - Persistence Helpers

    private func fetchProgress(for challengeID: String) async throws -> ChallengeProgress? {
        let context = persistenceController.container.viewContext
        let fetchRequest = ChallengeProgress.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "challengeID == %@", challengeID)
        fetchRequest.fetchLimit = 1

        let results = try context.fetch(fetchRequest)
        return results.first
    }
}
