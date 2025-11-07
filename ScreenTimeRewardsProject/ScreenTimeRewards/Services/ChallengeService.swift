import Foundation
import CoreData
import Combine

@MainActor
class ChallengeService: ObservableObject {
    static let shared = ChallengeService()

    // MARK: - Dependencies
    private let persistenceController = PersistenceController.shared
    private struct BadgeMetrics {
        let completedChallenges: Int
        let currentStreak: Int
        let totalLearningMinutes: Int
        let totalPointsEarned: Int
    }

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
        let progressRequest: NSFetchRequest<ChallengeProgress> = ChallengeProgress.fetchRequest()
        progressRequest.predicate = NSPredicate(format: "childDeviceID == %@", deviceID)
        let progressResults = try context.fetch(progressRequest)
        var progressMap: [String: ChallengeProgress] = [:]
        for progress in progressResults {
            if let id = progress.challengeID {
                progressMap[id] = progress
            }
        }
        challengeProgress = progressMap
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
        let didReachTarget = progress.currentValue >= progress.targetValue && !progress.isCompleted
        if didReachTarget {
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
            if let childDeviceID = progress.childDeviceID,
               let challenge = activeChallenges.first(where: { $0.challengeID == challengeID }),
               let goalType = challenge.goalType,
               goalType == "daily_minutes" || goalType == "streak" {
                await updateStreak(for: childDeviceID, date: Date())
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
            let multiplier = calculateStreakMultiplier(Int(streak.currentStreak))
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
        let context = persistenceController.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID
        do {
            try ensureStarterBadgesExist(for: deviceID, in: context)
        } catch {
            #if DEBUG
            print("[ChallengeService] ⚠️ Failed to initialize starter badges: \(error)")
            #endif
        }
    }

    func checkBadgeUnlocks(for deviceID: String) async -> [Badge] {
        let context = persistenceController.container.viewContext
        var newlyUnlocked: [Badge] = []

        do {
            let badges = try await fetchBadges(for: deviceID)
            let metrics = try badgeMetrics(for: deviceID)

            for badge in badges where !badge.isUnlocked {
                guard let criteria = badge.criteria else { continue }
                let shouldUnlock: Bool

                switch criteria.type {
                case .challengesCompleted:
                    shouldUnlock = metrics.completedChallenges >= criteria.threshold
                case .streakDays:
                    shouldUnlock = metrics.currentStreak >= criteria.threshold
                case .totalLearningMinutes:
                    shouldUnlock = metrics.totalLearningMinutes >= criteria.threshold
                case .totalPointsEarned:
                    shouldUnlock = metrics.totalPointsEarned >= criteria.threshold
                }

                if shouldUnlock {
                    try await unlockBadge(badge)
                    newlyUnlocked.append(badge)
                }
            }

            unlockedBadges = badges.filter { $0.isUnlocked }
        } catch {
            #if DEBUG
            print("[ChallengeService] ⚠️ Failed to evaluate badges: \(error)")
            #endif
        }

        if context.hasChanges {
            try? context.save()
        }

        return newlyUnlocked
    }

    // MARK: - Streak System

    func updateStreak(for deviceID: String, date: Date) async {
        let context = persistenceController.container.viewContext
        do {
            let streakRecord = try fetchOrCreateStreak(for: deviceID)
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)

            if let lastActivity = streakRecord.lastActivityDate {
                let lastStart = calendar.startOfDay(for: lastActivity)
                if startOfDay == lastStart {
                    currentStreak = streakRecord
                    return
                }

                if let days = calendar.dateComponents([.day], from: lastStart, to: startOfDay).day {
                    if days == 1 {
                        streakRecord.currentStreak += 1
                    } else if days > 1 {
                        streakRecord.currentStreak = 1
                    }
                }
            } else {
                streakRecord.currentStreak = 1
            }

            streakRecord.lastActivityDate = date
            if streakRecord.currentStreak > streakRecord.longestStreak {
                streakRecord.longestStreak = streakRecord.currentStreak
            }

            try context.save()
            currentStreak = streakRecord

            NotificationCenter.default.post(
                name: ChallengeService.streakUpdated,
                object: nil,
                userInfo: [
                    "deviceID": deviceID,
                    "currentStreak": streakRecord.currentStreak
                ]
            )
        } catch {
            #if DEBUG
            print("[ChallengeService] ⚠️ Failed to update streak: \(error)")
            #endif
        }
    }

    func breakStreak(for deviceID: String) async {
        let context = persistenceController.container.viewContext
        do {
            guard let streakRecord = try fetchStreakRecord(for: deviceID, createIfMissing: false) else {
                return
            }
            streakRecord.currentStreak = 0
            streakRecord.lastActivityDate = nil
            try context.save()
            currentStreak = streakRecord

            NotificationCenter.default.post(
                name: ChallengeService.streakUpdated,
                object: nil,
                userInfo: [
                    "deviceID": deviceID,
                    "currentStreak": streakRecord.currentStreak
                ]
            )
        } catch {
            #if DEBUG
            print("[ChallengeService] ⚠️ Failed to break streak: \(error)")
            #endif
        }
    }

    func fetchStreak(for deviceID: String) async throws -> StreakRecord? {
        if let record = try fetchStreakRecord(for: deviceID, createIfMissing: false) {
            currentStreak = record
            return record
        }
        return nil
    }

    func calculateStreakMultiplier(_ streak: Int) -> Double {
        guard streak > 0 else { return 0.0 }
        return min(Double(streak) * 0.01, 0.30)
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

    private func ensureStarterBadgesExist(for deviceID: String, in context: NSManagedObjectContext) throws {
        let fetchRequest: NSFetchRequest<Badge> = Badge.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "childDeviceID == %@", deviceID)
        let existingBadges = try context.fetch(fetchRequest)
        let existingIDs = Set(existingBadges.compactMap { $0.badgeID })

        for definition in BadgeDefinition.starterBadges where !existingIDs.contains(definition.id) {
            let badge = Badge(context: context)
            badge.badgeID = definition.id
            badge.badgeName = definition.name
            badge.badgeDescription = definition.description
            badge.iconName = definition.icon
            badge.childDeviceID = deviceID
            badge.unlockedAt = nil

            if let data = try? JSONEncoder().encode(definition.criteria) {
                badge.criteriaJSON = String(data: data, encoding: .utf8)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    func fetchBadges(for deviceID: String) async throws -> [Badge] {
        let context = persistenceController.container.viewContext
        try ensureStarterBadgesExist(for: deviceID, in: context)

        let fetchRequest: NSFetchRequest<Badge> = Badge.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "childDeviceID == %@", deviceID)
        let badges = try context.fetch(fetchRequest)

        let sorted = badges.sorted { lhs, rhs in
            switch (lhs.isUnlocked, rhs.isUnlocked) {
            case (true, false):
                return true
            case (false, true):
                return false
            default:
                let leftName = lhs.badgeName ?? ""
                let rightName = rhs.badgeName ?? ""
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
        }

        unlockedBadges = sorted.filter { $0.isUnlocked }
        return sorted
    }

    private func unlockBadge(_ badge: Badge) async throws {
        guard badge.unlockedAt == nil else { return }
        badge.unlockedAt = Date()
        try badge.managedObjectContext?.save()

        if let deviceID = badge.childDeviceID {
            NotificationCenter.default.post(
                name: ChallengeService.badgeUnlocked,
                object: nil,
                userInfo: [
                    "deviceID": deviceID,
                    "badgeID": badge.badgeID ?? ""
                ]
            )
        }
    }

    private func fetchStreakRecord(for deviceID: String, createIfMissing: Bool) throws -> StreakRecord? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<StreakRecord> = StreakRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "childDeviceID == %@", deviceID)
        fetchRequest.fetchLimit = 1

        if let record = try context.fetch(fetchRequest).first {
            return record
        }

        guard createIfMissing else { return nil }

        let streakRecord = StreakRecord(context: context)
        streakRecord.streakID = UUID().uuidString
        streakRecord.childDeviceID = deviceID
        streakRecord.streakTypeEnum = .daily
        streakRecord.currentStreak = 0
        streakRecord.longestStreak = 0
        streakRecord.lastActivityDate = nil

        try context.save()
        return streakRecord
    }

    private func fetchOrCreateStreak(for deviceID: String) throws -> StreakRecord {
        if let record = try fetchStreakRecord(for: deviceID, createIfMissing: true) {
            return record
        }
        throw NSError(
            domain: "ChallengeService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create streak record"]
        )
    }

    private func badgeMetrics(for deviceID: String) throws -> BadgeMetrics {
        let context = persistenceController.container.viewContext

        let completedRequest: NSFetchRequest<NSFetchRequestResult> = ChallengeProgress.fetchRequest()
        completedRequest.predicate = NSPredicate(format: "childDeviceID == %@ AND isCompleted == YES", deviceID)
        completedRequest.resultType = .countResultType
        let completedChallenges = try context.count(for: completedRequest)

        let streakValue = try fetchStreakRecord(for: deviceID, createIfMissing: false)?.currentStreak ?? 0

        let summaryRequest: NSFetchRequest<DailySummary> = DailySummary.fetchRequest()
        summaryRequest.predicate = NSPredicate(format: "deviceID == %@", deviceID)
        let summaries = try context.fetch(summaryRequest)

        let totals = summaries.reduce(into: (seconds: 0, points: 0)) { result, summary in
            result.seconds += Int(summary.totalLearningSeconds)
            result.points += Int(summary.totalPointsEarned)
        }

        return BadgeMetrics(
            completedChallenges: completedChallenges,
            currentStreak: Int(streakValue),
            totalLearningMinutes: totals.seconds / 60,
            totalPointsEarned: totals.points
        )
    }
}
