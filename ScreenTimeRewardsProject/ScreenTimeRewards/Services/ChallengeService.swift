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
    private let defaultRewardUnlockMinutes = 30

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
        goalType: ChallengeGoalType,
        targetValue: Int,
        bonusPercentage: Int,
        targetApps: [String]?,
        rewardApps: [String]?,
        startDate: Date,
        endDate: Date?,
        activeDays: [Int]?,
        startTime: Date?,
        endTime: Date?,
        createdBy: String,
        assignedTo: String,
        learningToRewardRatio: LearningToRewardRatio? = nil,
        progressTrackingMode: ProgressTrackingMode = .combined,
        streakBonusEnabled: Bool = false,
        streakTargetDays: Int = 7,
        streakBonusPercentage: Int = 25
    ) async throws {
        let context = persistenceController.container.viewContext

        // Create Core Data entity
        let challenge = Challenge(context: context)
        challenge.challengeID = UUID().uuidString
        challenge.title = title
        challenge.challengeDescription = description
        challenge.goalType = goalType.rawValue
        challenge.targetValue = Int32(targetValue)
        challenge.bonusPercentage = Int16(bonusPercentage)

        // Encode targetApps as JSON
        challenge.targetAppsJSON = encodeJSONArray(targetApps)
        challenge.rewardAppsJSON = encodeJSONArray(rewardApps)
        challenge.activeDays = encodeJSONArray(activeDays)
        challenge.learningToRewardRatioData = encodeJSONArray(learningToRewardRatio)

        challenge.startDate = startDate
        challenge.endDate = endDate
        challenge.startTime = startTime
        challenge.endTime = endTime
        challenge.isActive = true
        challenge.createdBy = createdBy
        challenge.assignedTo = assignedTo
        challenge.progressTrackingMode = progressTrackingMode.rawValue

        // Streak bonus settings
        challenge.streakBonusEnabled = streakBonusEnabled
        challenge.streakTargetDays = Int16(streakTargetDays)
        challenge.streakBonusPercentage = Int16(streakBonusPercentage)

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

    func updateProgressForUsage(appID: String, duration: TimeInterval, earnedPoints: Int, deviceID: String) async {
        let minutes = Int(duration / 60)
        let recordedActivity = duration > 0

        guard recordedActivity || minutes > 0 || earnedPoints > 0 else {
            return
        }

        #if DEBUG
        print("[ChallengeService] 📊 Usage event → \(minutes) min, \(earnedPoints) pts, appID: \(appID)")
        #endif

        guard let challenges = try? await fetchActiveChallenges(for: deviceID) else {
            return
        }

        for challenge in challenges {
            guard doesChallenge(challenge, applyTo: appID) else {
                continue
            }

            // All challenges are now daily quest type
            guard minutes > 0 else { continue }

            // Check if per-app tracking is enabled
            if challenge.isPerAppTracking {
                // Per-app tracking: each app must individually meet the target
                await updatePerAppProgress(
                    for: challenge,
                    appID: appID,
                    incrementBy: minutes,
                    resetStrategy: .daily
                )
            } else {
                // Combined tracking: all apps contribute to one total
                await updateProgress(for: challenge, incrementBy: minutes, resetStrategy: .daily)
            }
        }
    }

    private enum ProgressResetStrategy {
        case none
        case daily
        case weekly
    }

    private func updateProgress(for challenge: Challenge, incrementBy amount: Int, resetStrategy: ProgressResetStrategy) async {
        guard amount > 0,
              let challengeID = challenge.challengeID,
              let progress = try? await fetchProgress(for: challengeID) else {
            return
        }

        resetProgressIfNeeded(progress, using: resetStrategy)

        progress.currentValue += Int32(amount)
        progress.lastUpdated = Date()

        if progress.currentValue >= progress.targetValue && !progress.isCompleted {
            await complete(challenge: challenge, with: progress)
        }

        try? persistenceController.container.viewContext.save()
        challengeProgress[challengeID] = progress

        NotificationCenter.default.post(
            name: ChallengeService.challengeProgressUpdated,
            object: nil,
            userInfo: ["challengeID": challengeID, "progress": progress]
        )
    }

    private func resetProgressIfNeeded(_ progress: ChallengeProgress, using strategy: ProgressResetStrategy) {
        guard let lastUpdated = progress.lastUpdated else { return }
        let calendar = Calendar.current

        switch strategy {
        case .none:
            return
        case .daily:
            guard !calendar.isDateInToday(lastUpdated) else { return }
        case .weekly:
            let currentComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date())
            let lastComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: lastUpdated)
            guard currentComponents.weekOfYear != lastComponents.weekOfYear ||
                    currentComponents.yearForWeekOfYear != lastComponents.yearForWeekOfYear else {
                return
            }
        }

        progress.currentValue = 0
        progress.isCompleted = false
        progress.completedDate = nil
        progress.bonusPointsEarned = 0
    }

    private func complete(challenge: Challenge, with progress: ChallengeProgress) async {
        guard let challengeID = challenge.challengeID else { return }
        progress.isCompleted = true
        progress.completedDate = Date()

        let bonusPoints = try? await awardBonusPoints(for: challengeID)
        progress.bonusPointsEarned = Int32(bonusPoints ?? 0)

        let rewardApps = challenge.rewardAppIDs
        let rewardMinutes = challenge.rewardUnlockMinutes(defaultValue: defaultRewardUnlockMinutes)
        NotificationCenter.default.post(
            name: ChallengeService.challengeCompleted,
            object: nil,
            userInfo: [
                "challengeID": challengeID,
                "rewardApps": rewardApps,
                "rewardUnlockMinutes": rewardMinutes
            ]
        )

        if let childDeviceID = progress.childDeviceID {
            _ = await checkBadgeUnlocks(for: childDeviceID)

            // All challenges are daily quests - update streak if streak bonus is enabled
            if challenge.streakBonusEnabled {
                await updateStreak(for: childDeviceID, date: Date())
                // Check if streak target is met and award bonus
                await checkStreakBonus(for: challenge, childDeviceID: childDeviceID)
            }
        }
    }

    private func checkStreakBonus(for challenge: Challenge, childDeviceID: String) async {
        guard challenge.streakBonusEnabled else { return }

        let streakRecord = try? fetchStreakRecord(for: childDeviceID, createIfMissing: false)
        let currentStreak = streakRecord?.currentStreak ?? 0

        // Check if streak target is reached
        if currentStreak >= challenge.streakTargetDays {
            // Award streak bonus points
            let bonusPoints = Int(challenge.streakBonusPercentage)
            #if DEBUG
            print("[ChallengeService] 🔥 Streak bonus awarded: \(bonusPoints)% for \(currentStreak) day streak")
            #endif
            // Bonus points are tracked in the progress bonusPointsEarned field
        }
    }

    private func updateStreakProgress(for challenge: Challenge) async {
        guard let challengeID = challenge.challengeID,
              let childDeviceID = challenge.assignedTo,
              let progress = try? await fetchProgress(for: challengeID) else {
            return
        }

        await updateStreak(for: childDeviceID, date: Date())
        let streakValue = (try? fetchStreakRecord(for: childDeviceID, createIfMissing: false)?.currentStreak) ?? 0

        progress.currentValue = Int32(streakValue)
        progress.lastUpdated = Date()

        if progress.currentValue >= progress.targetValue && !progress.isCompleted {
            await complete(challenge: challenge, with: progress)
        }

        try? persistenceController.container.viewContext.save()
        challengeProgress[challengeID] = progress

        NotificationCenter.default.post(
            name: ChallengeService.challengeProgressUpdated,
            object: nil,
            userInfo: ["challengeID": challengeID, "progress": progress]
        )
    }

    private func doesChallenge(_ challenge: Challenge, applyTo appID: String) -> Bool {
        let targetApps = challenge.targetAppIDs
        return targetApps.isEmpty || targetApps.contains(appID)
    }

    // MARK: - Per-App Progress Tracking

    private func updatePerAppProgress(
        for challenge: Challenge,
        appID: String,
        incrementBy amount: Int,
        resetStrategy: ProgressResetStrategy
    ) async {
        guard amount > 0,
              let challengeID = challenge.challengeID else {
            return
        }

        // Fetch or create AppProgress for this specific app
        guard let appProgress = try? await fetchOrCreateAppProgress(
            challengeID: challengeID,
            appID: appID,
            targetValue: Int(challenge.targetValue)
        ) else {
            return
        }

        // Reset if needed based on strategy
        resetAppProgressIfNeeded(appProgress, using: resetStrategy)

        // Update progress for this specific app
        appProgress.currentMinutes += Int32(amount)
        appProgress.lastUpdated = Date()

        // Check if THIS app completed its target
        if appProgress.currentMinutes >= appProgress.targetMinutes && !appProgress.isCompleted {
            appProgress.isCompleted = true
        }

        try? persistenceController.container.viewContext.save()

        // Check if ALL apps completed (overall challenge completion)
        await checkPerAppChallengeCompletion(for: challenge)

        NotificationCenter.default.post(
            name: ChallengeService.challengeProgressUpdated,
            object: nil,
            userInfo: ["challengeID": challengeID, "appID": appID]
        )
    }

    private func checkPerAppChallengeCompletion(for challenge: Challenge) async {
        guard let challengeID = challenge.challengeID,
              let progress = try? await fetchProgress(for: challengeID) else {
            return
        }

        // Get all app progress records for this challenge
        guard let appProgressRecords = try? await fetchAllAppProgress(for: challengeID) else {
            return
        }

        let targetApps = challenge.targetAppIDs
        let requiredAppCount = targetApps.isEmpty ? appProgressRecords.count : targetApps.count

        // Check if all required apps have completed
        let completedCount = appProgressRecords.filter { $0.isCompleted }.count
        let allCompleted = completedCount >= requiredAppCount && requiredAppCount > 0

        // Calculate total minutes across all apps
        let totalMinutes = appProgressRecords.reduce(0) { $0 + Int($1.currentMinutes) }
        progress.currentValue = Int32(totalMinutes)

        if allCompleted && !progress.isCompleted {
            await complete(challenge: challenge, with: progress)
        }

        try? persistenceController.container.viewContext.save()
        challengeProgress[challengeID] = progress
    }

    private func fetchOrCreateAppProgress(
        challengeID: String,
        appID: String,
        targetValue: Int
    ) async throws -> AppProgress? {
        let context = persistenceController.container.viewContext
        let fetchRequest = AppProgress.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "challengeID == %@ AND appLogicalID == %@",
            challengeID, appID
        )
        fetchRequest.fetchLimit = 1

        if let existing = try context.fetch(fetchRequest).first {
            return existing
        }

        // Create new
        let appProgress = AppProgress(context: context)
        appProgress.appProgressID = UUID().uuidString
        appProgress.challengeID = challengeID
        appProgress.appLogicalID = appID
        appProgress.currentMinutes = 0
        appProgress.targetMinutes = Int32(targetValue)
        appProgress.isCompleted = false
        appProgress.lastUpdated = Date()

        try context.save()
        return appProgress
    }

    private func fetchAllAppProgress(for challengeID: String) async throws -> [AppProgress] {
        let context = persistenceController.container.viewContext
        let fetchRequest = AppProgress.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "challengeID == %@", challengeID)
        return try context.fetch(fetchRequest)
    }

    private func resetAppProgressIfNeeded(_ appProgress: AppProgress, using strategy: ProgressResetStrategy) {
        guard let lastUpdated = appProgress.lastUpdated else { return }
        let calendar = Calendar.current

        switch strategy {
        case .none:
            return
        case .daily:
            guard !calendar.isDateInToday(lastUpdated) else { return }
        case .weekly:
            let currentComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date())
            let lastComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: lastUpdated)
            guard currentComponents.weekOfYear != lastComponents.weekOfYear ||
                    currentComponents.yearForWeekOfYear != lastComponents.yearForWeekOfYear else {
                return
            }
        }

        appProgress.currentMinutes = 0
        appProgress.isCompleted = false
    }

    private func encodeJSONArray<T: Encodable>(_ value: T?) -> String? {
        guard
            let value,
            let data = try? JSONEncoder().encode(value),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return jsonString
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
