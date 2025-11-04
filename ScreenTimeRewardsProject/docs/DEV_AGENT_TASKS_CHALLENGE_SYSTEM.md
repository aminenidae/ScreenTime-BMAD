# Dev Agent Tasks - Challenge System Implementation

**Priority:** HIGH
**Date:** November 3, 2025
**Estimated Time:** 4 weeks (broken into 4 phases)
**Complexity:** HIGH - New feature with gamification

---

## Overview

Implement a comprehensive gamification system with Challenges, Streaks, Badges, and Levels. This is a **major feature** requiring:
- New data models and Core Data entities
- New service layer (ChallengeService)
- Parent UI for challenge creation
- Child UI for viewing progress
- CloudKit sync integration
- Real-time progress tracking
- Animation and celebration effects

**See full specification:** `docs/CHALLENGE_SYSTEM_IMPLEMENTATION_SPEC.md`

---

## Implementation Phases

This implementation is broken into **4 phases** to manage complexity:

1. **Phase 1:** Core Data Models & Service (Week 1) - ~40 hours
2. **Phase 2:** Parent Challenge Creation UI (Week 2) - ~40 hours
3. **Phase 3:** Child Experience & Progress Tracking (Week 3) - ~40 hours
4. **Phase 4:** Gamification (Badges, Streaks, Animations) (Week 4) - ~40 hours

---

## PHASE 1: Core Foundation (Week 1)

### Task 1.1: Create Data Models ⚡ (3 hours)

#### Files to Create

**1. Challenge Model**
**Create:** `ScreenTimeRewards/Models/Challenge.swift`

```swift
import Foundation

struct Challenge: Codable, Identifiable {
    let id: String  // UUID
    let title: String
    let description: String
    let goalType: GoalType
    let targetValue: Int  // Minutes or days
    let bonusPercentage: Int  // 5-50%
    let targetApps: [String]?  // Optional specific learning app logical IDs
    let startDate: Date
    let endDate: Date?  // nil = ongoing
    let isActive: Bool
    let createdBy: String  // Parent device ID
    let assignedTo: String  // Child device ID

    enum GoalType: String, Codable {
        case dailyMinutes = "daily_minutes"
        case weeklyMinutes = "weekly_minutes"
        case specificApps = "specific_apps"
        case streak = "streak"
    }

    // Helper computed properties
    var isExpired: Bool {
        guard let endDate = endDate else { return false }
        return Date() > endDate
    }

    var durationText: String {
        if endDate == nil { return "Ongoing" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate!))"
    }
}
```

**2. ChallengeProgress Model**
**Create:** `ScreenTimeRewards/Models/ChallengeProgress.swift`

```swift
import Foundation

struct ChallengeProgress: Codable, Identifiable {
    let id: String  // UUID
    let challengeID: String
    let childDeviceID: String
    var currentValue: Int  // Current minutes or streak count
    let targetValue: Int
    var isCompleted: Bool
    var completedDate: Date?
    var bonusPointsEarned: Int
    var lastUpdated: Date

    // Computed properties
    var progressPercentage: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(currentValue) / Double(targetValue), 1.0) * 100
    }

    var remainingValue: Int {
        return max(0, targetValue - currentValue)
    }

    var isNearCompletion: Bool {
        return progressPercentage >= 90
    }
}
```

**3. Badge Model**
**Create:** `ScreenTimeRewards/Models/Badge.swift`

```swift
import Foundation

struct Badge: Codable, Identifiable {
    let id: String  // UUID
    let name: String
    let description: String
    let iconName: String  // SF Symbol name
    var unlockedAt: Date?
    let criteria: BadgeCriteria
    let childDeviceID: String

    struct BadgeCriteria: Codable {
        let type: CriteriaType
        let threshold: Int

        enum CriteriaType: String, Codable {
            case challengesCompleted = "challenges_completed"
            case streakDays = "streak_days"
            case totalLearningMinutes = "total_learning_minutes"
            case totalPointsEarned = "total_points_earned"
        }
    }

    var isUnlocked: Bool {
        return unlockedAt != nil
    }
}
```

**4. StreakRecord Model**
**Create:** `ScreenTimeRewards/Models/StreakRecord.swift`

```swift
import Foundation

struct StreakRecord: Codable, Identifiable {
    let id: String  // UUID
    let childDeviceID: String
    let streakType: StreakType
    var currentStreak: Int
    var longestStreak: Int
    var lastActivityDate: Date

    enum StreakType: String, Codable {
        case daily = "daily"
        case weekly = "weekly"
    }

    // Calculated properties
    var streakMultiplier: Double {
        // +5% bonus per week of streak
        let weeks = currentStreak / 7
        return 1.0 + (Double(weeks) * 0.05)
    }

    var isAtRisk: Bool {
        // Streak at risk if no activity today
        let calendar = Calendar.current
        return !calendar.isDateInToday(lastActivityDate)
    }
}
```

**5. ChallengeTemplate Model**
**Create:** `ScreenTimeRewards/Models/ChallengeTemplate.swift`

```swift
import Foundation
import SwiftUI

struct ChallengeTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String  // SF Symbol
    let goalType: Challenge.GoalType
    let suggestedTarget: Int
    let suggestedBonus: Int
    let colorHex: String

    static let allTemplates: [ChallengeTemplate] = [
        ChallengeTemplate(
            id: "daily_dynamo",
            name: "Daily Dynamo",
            description: "Complete 60 minutes of learning every day",
            icon: "bolt.fill",
            goalType: .dailyMinutes,
            suggestedTarget: 60,
            suggestedBonus: 10,
            colorHex: "#FFB800"
        ),
        ChallengeTemplate(
            id: "weekend_warrior",
            name: "Weekend Warrior",
            description: "Learn 180 minutes over the weekend",
            icon: "trophy.fill",
            goalType: .weeklyMinutes,
            suggestedTarget: 180,
            suggestedBonus: 15,
            colorHex: "#FF6B35"
        ),
        ChallengeTemplate(
            id: "app_master",
            name: "App Master",
            description: "Spend 5 hours in your favorite learning app this week",
            icon: "target",
            goalType: .specificApps,
            suggestedTarget: 300,
            suggestedBonus: 20,
            colorHex: "#4ECDC4"
        ),
        ChallengeTemplate(
            id: "streak_champion",
            name: "Streak Champion",
            description: "Maintain a 7-day learning streak",
            icon: "flame.fill",
            goalType: .streak,
            suggestedTarget: 7,
            suggestedBonus: 25,
            colorHex: "#FF3366"
        ),
        ChallengeTemplate(
            id: "quick_start",
            name: "Quick Start",
            description: "Just 15 minutes of learning per day",
            icon: "star.fill",
            goalType: .dailyMinutes,
            suggestedTarget: 15,
            suggestedBonus: 5,
            colorHex: "#95E1D3"
        )
    ]
}

// Helper extension for Color from hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

**6. BadgeDefinitions**
**Create:** `ScreenTimeRewards/Models/BadgeDefinitions.swift`

```swift
import Foundation

struct BadgeDefinition {
    let id: String
    let name: String
    let description: String
    let icon: String
    let criteria: Badge.BadgeCriteria

    static let starterBadges: [BadgeDefinition] = [
        BadgeDefinition(
            id: "first_steps",
            name: "First Steps",
            description: "Complete your first challenge",
            icon: "figure.walk",
            criteria: Badge.BadgeCriteria(type: .challengesCompleted, threshold: 1)
        ),
        BadgeDefinition(
            id: "week_warrior",
            name: "Week Warrior",
            description: "Maintain a 7-day streak",
            icon: "calendar",
            criteria: Badge.BadgeCriteria(type: .streakDays, threshold: 7)
        ),
        BadgeDefinition(
            id: "month_master",
            name: "Month Master",
            description: "Maintain a 30-day streak",
            icon: "calendar.badge.plus",
            criteria: Badge.BadgeCriteria(type: .streakDays, threshold: 30)
        ),
        BadgeDefinition(
            id: "learning_legend",
            name: "Learning Legend",
            description: "Complete 100 hours of learning",
            icon: "brain.head.profile",
            criteria: Badge.BadgeCriteria(type: .totalLearningMinutes, threshold: 6000)
        ),
        BadgeDefinition(
            id: "point_collector",
            name: "Point Collector",
            description: "Earn 10,000 learning points",
            icon: "star.circle.fill",
            criteria: Badge.BadgeCriteria(type: .totalPointsEarned, threshold: 10000)
        ),
        BadgeDefinition(
            id: "challenge_champion",
            name: "Challenge Champion",
            description: "Complete 10 challenges",
            icon: "rosette",
            criteria: Badge.BadgeCriteria(type: .challengesCompleted, threshold: 10)
        )
    ]
}
```

---

### Task 1.2: Update Core Data Schema 🔧 (2 hours)

**File:** `ScreenTimeRewards/ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`

**IMPORTANT:** Open Xcode and use the Core Data Model Editor for this task. Do NOT edit the XML directly in production.

**Add the following entities:**

1. **Challenge Entity**
   - Attributes:
     - challengeID (String, indexed)
     - title (String)
     - challengeDescription (String)
     - goalType (String)
     - targetValue (Integer 32)
     - bonusPercentage (Integer 16, default: 10)
     - targetAppsJSON (String, optional)
     - startDate (Date)
     - endDate (Date, optional)
     - isActive (Boolean, default: YES)
     - createdBy (String, indexed)
     - assignedTo (String, indexed)

2. **ChallengeProgress Entity**
   - Attributes:
     - progressID (String, indexed)
     - challengeID (String, indexed)
     - childDeviceID (String, indexed)
     - currentValue (Integer 32, default: 0)
     - targetValue (Integer 32, default: 0)
     - isCompleted (Boolean, default: NO)
     - completedDate (Date, optional)
     - bonusPointsEarned (Integer 32, default: 0)
     - lastUpdated (Date)

3. **Badge Entity**
   - Attributes:
     - badgeID (String, indexed)
     - badgeName (String)
     - badgeDescription (String)
     - iconName (String)
     - unlockedAt (Date, optional)
     - criteriaJSON (String)
     - childDeviceID (String, indexed)

4. **StreakRecord Entity**
   - Attributes:
     - streakID (String, indexed)
     - childDeviceID (String, indexed)
     - streakType (String)
     - currentStreak (Integer 16, default: 0)
     - longestStreak (Integer 16, default: 0)
     - lastActivityDate (Date)

**Configure CloudKit Sync:**
- Check "Used with CloudKit" for all entities
- Set all entities to syncable = YES

---

### Task 1.3: Create ChallengeService 🔧 (8 hours)

**Create:** `ScreenTimeRewards/Services/ChallengeService.swift`

This is a **large file** (~500+ lines). Here's the structure:

```swift
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

    func createChallenge(_ challenge: Challenge) async throws {
        let context = persistenceController.container.viewContext

        // Create Core Data entity
        let entity = NSEntityDescription.entity(forEntityName: "Challenge", in: context)!
        let cdChallenge = NSManagedObject(entity: entity, insertInto: context)

        cdChallenge.setValue(challenge.id, forKey: "challengeID")
        cdChallenge.setValue(challenge.title, forKey: "title")
        cdChallenge.setValue(challenge.description, forKey: "challengeDescription")
        cdChallenge.setValue(challenge.goalType.rawValue, forKey: "goalType")
        cdChallenge.setValue(challenge.targetValue, forKey: "targetValue")
        cdChallenge.setValue(challenge.bonusPercentage, forKey: "bonusPercentage")

        // Encode targetApps as JSON
        if let targetApps = challenge.targetApps {
            let json = try? JSONEncoder().encode(targetApps)
            cdChallenge.setValue(String(data: json!, encoding: .utf8), forKey: "targetAppsJSON")
        }

        cdChallenge.setValue(challenge.startDate, forKey: "startDate")
        cdChallenge.setValue(challenge.endDate, forKey: "endDate")
        cdChallenge.setValue(challenge.isActive, forKey: "isActive")
        cdChallenge.setValue(challenge.createdBy, forKey: "createdBy")
        cdChallenge.setValue(challenge.assignedTo, forKey: "assignedTo")

        try context.save()

        // Create initial progress entry for child
        let progress = ChallengeProgress(
            id: UUID().uuidString,
            challengeID: challenge.id,
            childDeviceID: challenge.assignedTo,
            currentValue: 0,
            targetValue: challenge.targetValue,
            isCompleted: false,
            completedDate: nil,
            bonusPointsEarned: 0,
            lastUpdated: Date()
        )

        try await saveProgress(progress)

        #if DEBUG
        print("[ChallengeService] ✅ Created challenge: \(challenge.title)")
        #endif
    }

    func fetchActiveChallenges(for deviceID: String) async throws -> [Challenge] {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Challenge")
        fetchRequest.predicate = NSPredicate(
            format: "assignedTo == %@ AND isActive == YES",
            deviceID
        )

        let results = try context.fetch(fetchRequest)
        let challenges = results.compactMap { cdChallenge -> Challenge? in
            guard let id = cdChallenge.value(forKey: "challengeID") as? String,
                  let title = cdChallenge.value(forKey: "title") as? String,
                  let description = cdChallenge.value(forKey: "challengeDescription") as? String,
                  let goalTypeRaw = cdChallenge.value(forKey: "goalType") as? String,
                  let goalType = Challenge.GoalType(rawValue: goalTypeRaw),
                  let targetValue = cdChallenge.value(forKey: "targetValue") as? Int,
                  let bonusPercentage = cdChallenge.value(forKey: "bonusPercentage") as? Int,
                  let startDate = cdChallenge.value(forKey: "startDate") as? Date,
                  let isActive = cdChallenge.value(forKey: "isActive") as? Bool,
                  let createdBy = cdChallenge.value(forKey: "createdBy") as? String,
                  let assignedTo = cdChallenge.value(forKey: "assignedTo") as? String else {
                return nil
            }

            let endDate = cdChallenge.value(forKey: "endDate") as? Date

            // Decode targetApps if present
            var targetApps: [String]? = nil
            if let json = cdChallenge.value(forKey: "targetAppsJSON") as? String,
               let data = json.data(using: .utf8) {
                targetApps = try? JSONDecoder().decode([String].self, from: data)
            }

            return Challenge(
                id: id,
                title: title,
                description: description,
                goalType: goalType,
                targetValue: targetValue,
                bonusPercentage: bonusPercentage,
                targetApps: targetApps,
                startDate: startDate,
                endDate: endDate,
                isActive: isActive,
                createdBy: createdBy,
                assignedTo: assignedTo
            )
        }

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
            let appliestoApp: Bool
            if let targetApps = challenge.targetApps {
                appliestoApp = targetApps.contains(appID)
            } else {
                // If no specific apps, applies to all learning apps
                appliestoApp = true
            }

            guard appliestoApp else { continue }

            // Update progress based on goal type
            switch challenge.goalType {
            case .dailyMinutes:
                await updateDailyProgress(for: challenge.id, incrementBy: minutes)
            case .weeklyMinutes:
                await updateWeeklyProgress(for: challenge.id, incrementBy: minutes)
            case .specificApps:
                await updateProgress(for: challenge.id, incrementBy: minutes)
            case .streak:
                // Streak is updated separately based on daily goals
                continue
            }
        }
    }

    private func updateProgress(for challengeID: String, incrementBy minutes: Int) async {
        guard var progress = challengeProgress[challengeID] else {
            // Fetch from Core Data if not in memory
            if let fetchedProgress = try? await fetchProgress(for: challengeID) {
                challengeProgress[challengeID] = fetchedProgress
                await updateProgress(for: challengeID, incrementBy: minutes)
            }
            return
        }

        progress.currentValue += minutes
        progress.lastUpdated = Date()

        // Check for completion
        if progress.currentValue >= progress.targetValue && !progress.isCompleted {
            progress.isCompleted = true
            progress.completedDate = Date()

            // Award bonus points
            let bonusPoints = try? await awardBonusPoints(for: challengeID)
            progress.bonusPointsEarned = bonusPoints ?? 0

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
            await checkBadgeUnlocks(for: progress.childDeviceID)
        }

        // Save progress
        challengeProgress[challengeID] = progress
        try? await saveProgress(progress)

        // Post progress update notification
        NotificationCenter.default.post(
            name: ChallengeService.challengeProgressUpdated,
            object: nil,
            userInfo: ["challengeID": challengeID, "progress": progress]
        )
    }

    private func updateDailyProgress(for challengeID: String, incrementBy minutes: Int) async {
        // Reset progress if new day
        guard var progress = challengeProgress[challengeID] else { return }

        let calendar = Calendar.current
        if !calendar.isDateInToday(progress.lastUpdated) {
            // New day - reset progress
            progress.currentValue = 0
            progress.isCompleted = false
            progress.completedDate = nil
        }

        challengeProgress[challengeID] = progress
        await updateProgress(for: challengeID, incrementBy: minutes)
    }

    private func updateWeeklyProgress(for challengeID: String, incrementBy minutes: Int) async {
        // Reset progress if new week
        guard var progress = challengeProgress[challengeID] else { return }

        let calendar = Calendar.current
        let currentWeek = calendar.component(.weekOfYear, from: Date())
        let progressWeek = calendar.component(.weekOfYear, from: progress.lastUpdated)

        if currentWeek != progressWeek {
            // New week - reset progress
            progress.currentValue = 0
            progress.isCompleted = false
            progress.completedDate = nil
        }

        challengeProgress[challengeID] = progress
        await updateProgress(for: challengeID, incrementBy: minutes)
    }

    // MARK: - Bonus Calculation

    func calculateBonusPoints(basePoints: Int, for deviceID: String) -> Int {
        var totalBonus = 0

        // Apply challenge bonuses
        for (challengeID, progress) in challengeProgress where progress.isCompleted {
            // Find the challenge
            if let challenge = activeChallenges.first(where: { $0.id == challengeID }) {
                let bonus = (basePoints * challenge.bonusPercentage) / 100
                totalBonus += bonus
            }
        }

        // Apply streak multiplier
        if let streak = currentStreak {
            let multiplier = streak.streakMultiplier - 1.0  // Get bonus percentage
            let streakBonus = Int(Double(basePoints) * multiplier)
            totalBonus += streakBonus
        }

        #if DEBUG
        print("[ChallengeService] 💰 Bonus calculation: \(basePoints) base + \(totalBonus) bonus")
        #endif

        return totalBonus
    }

    func awardBonusPoints(for challengeID: String) async throws -> Int {
        guard let progress = challengeProgress[challengeID],
              let challenge = activeChallenges.first(where: { $0.id == challengeID }) else {
            return 0
        }

        // Calculate bonus based on base learning points earned during challenge
        // This would need integration with AppUsageViewModel to get actual base points
        // For now, use a simple calculation
        let basePoints = progress.currentValue * 10  // Assume 10 points per minute
        let bonusPoints = (basePoints * challenge.bonusPercentage) / 100

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

    private func saveProgress(_ progress: ChallengeProgress) async throws {
        let context = persistenceController.container.viewContext

        // Check if progress already exists
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChallengeProgress")
        fetchRequest.predicate = NSPredicate(format: "progressID == %@", progress.id)

        let results = try context.fetch(fetchRequest)
        let cdProgress: NSManagedObject

        if let existing = results.first {
            cdProgress = existing
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "ChallengeProgress", in: context)!
            cdProgress = NSManagedObject(entity: entity, insertInto: context)
            cdProgress.setValue(progress.id, forKey: "progressID")
        }

        cdProgress.setValue(progress.challengeID, forKey: "challengeID")
        cdProgress.setValue(progress.childDeviceID, forKey: "childDeviceID")
        cdProgress.setValue(progress.currentValue, forKey: "currentValue")
        cdProgress.setValue(progress.targetValue, forKey: "targetValue")
        cdProgress.setValue(progress.isCompleted, forKey: "isCompleted")
        cdProgress.setValue(progress.completedDate, forKey: "completedDate")
        cdProgress.setValue(progress.bonusPointsEarned, forKey: "bonusPointsEarned")
        cdProgress.setValue(progress.lastUpdated, forKey: "lastUpdated")

        try context.save()
    }

    private func fetchProgress(for challengeID: String) async throws -> ChallengeProgress? {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChallengeProgress")
        fetchRequest.predicate = NSPredicate(format: "challengeID == %@", challengeID)

        let results = try context.fetch(fetchRequest)
        guard let cdProgress = results.first else { return nil }

        guard let id = cdProgress.value(forKey: "progressID") as? String,
              let challengeID = cdProgress.value(forKey: "challengeID") as? String,
              let childDeviceID = cdProgress.value(forKey: "childDeviceID") as? String,
              let currentValue = cdProgress.value(forKey: "currentValue") as? Int,
              let targetValue = cdProgress.value(forKey: "targetValue") as? Int,
              let isCompleted = cdProgress.value(forKey: "isCompleted") as? Bool,
              let bonusPointsEarned = cdProgress.value(forKey: "bonusPointsEarned") as? Int,
              let lastUpdated = cdProgress.value(forKey: "lastUpdated") as? Date else {
            return nil
        }

        let completedDate = cdProgress.value(forKey: "completedDate") as? Date

        return ChallengeProgress(
            id: id,
            challengeID: challengeID,
            childDeviceID: childDeviceID,
            currentValue: currentValue,
            targetValue: targetValue,
            isCompleted: isCompleted,
            completedDate: completedDate,
            bonusPointsEarned: bonusPointsEarned,
            lastUpdated: lastUpdated
        )
    }
}
```

**Note:** This is a foundation. Badge and Streak methods will be completed in Phase 4.

---

### Task 1.4: Integrate with ScreenTimeService 🔧 (2 hours)

**File:** `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Find the section where learning app usage is recorded** (around line 800-900, look for `recordUsage` or similar).

**ADD after recording usage:**

```swift
// EXISTING CODE: Record usage to persistence
usagePersistence.recordUsage(
    logicalID: logicalID,
    displayName: displayName,
    category: category,
    duration: duration,
    pointsPerMinute: rewardPoints,
    endTime: Date()
)

// NEW CODE: Notify challenge service of learning app usage
if category == .learning {
    Task {
        await ChallengeService.shared.updateProgressForUsage(
            appID: logicalID,
            duration: duration,
            deviceID: DeviceModeManager.shared.deviceID
        )
    }
}
```

---

### Task 1.5: Integrate with AppUsageViewModel 🔧 (2 hours)

**File:** `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

**ADD properties (after line ~100):**

```swift
// MARK: - Challenge Integration
@Published var activeChallenges: [Challenge] = []
@Published var challengeProgress: [String: ChallengeProgress] = [:]
@Published var currentStreak: Int = 0
private let challengeService = ChallengeService.shared
```

**ADD computed property:**

```swift
/// Total learning points with challenge bonuses applied
var totalLearningPointsWithBonuses: Int {
    let basePoints = learningRewardPoints
    let bonusPoints = challengeService.calculateBonusPoints(
        basePoints: basePoints,
        for: DeviceModeManager.shared.deviceID
    )

    #if DEBUG
    print("[AppUsageViewModel] 💰 Learning points: \(basePoints) + bonus: \(bonusPoints)")
    #endif

    return basePoints + bonusPoints
}
```

**MODIFY init() to observe challenge notifications:**

```swift
init(service: ScreenTimeService = .shared) {
    // ... existing init code ...

    // NEW: Observe challenge notifications
    NotificationCenter.default.addObserver(
        forName: ChallengeService.challengeProgressUpdated,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        Task { @MainActor in
            self?.loadChallengeData()
        }
    }

    NotificationCenter.default.addObserver(
        forName: ChallengeService.challengeCompleted,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        Task { @MainActor in
            // Show celebration animation
            self?.showChallengeCompletionAnimation()
        }
    }
}
```

**ADD helper method:**

```swift
private func loadChallengeData() {
    Task {
        do {
            let deviceID = DeviceModeManager.shared.deviceID
            activeChallenges = try await challengeService.fetchActiveChallenges(for: deviceID)
            challengeProgress = challengeService.challengeProgress
        } catch {
            #if DEBUG
            print("[AppUsageViewModel] ❌ Failed to load challenges: \(error)")
            #endif
        }
    }
}

private func showChallengeCompletionAnimation() {
    // TODO: Implement in Phase 3
    #if DEBUG
    print("[AppUsageViewModel] 🎉 Challenge completed!")
    #endif
}
```

---

### Task 1.6: Build & Test Phase 1 ✅ (3 hours)

**Build the project:**

```bash
xcodebuild -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -sdk iphoneos \
  -configuration Debug \
  build
```

**Test checklist:**
- [ ] All new models compile without errors
- [ ] Core Data schema updated successfully (check in Xcode)
- [ ] ChallengeService singleton initializes
- [ ] ScreenTimeService integration compiles
- [ ] AppUsageViewModel compiles with new properties
- [ ] No runtime crashes on app launch

**Manual testing:**
- [ ] Create a test challenge programmatically
- [ ] Verify it saves to Core Data
- [ ] Check CloudKit Dashboard for sync (after 30-60 seconds)
- [ ] Simulate learning app usage
- [ ] Verify progress updates

---

## PHASE 2: Parent Challenge Creation UI (Week 2)

### Task 2.1: Add Challenges Tab to Parent Mode 🔧 (1 hour)

**File:** `ScreenTimeRewards/Views/MainTabView.swift`

**MODIFY the TabView section (around line 15-36):**

```swift
TabView {
    RewardsTabView()
        .tabItem {
            Label("Rewards", systemImage: "gamecontroller.fill")
        }
        .navigationTitle("Rewards")

    LearningTabView()
        .tabItem {
            Label("Learning", systemImage: "book.fill")
        }
        .navigationTitle("Learning")

    // Settings Tab (Parent Mode only) - Phase 2
    if isParentMode {
        SettingsTabView()
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .navigationTitle("Settings")
    }

    // NEW: Challenges Tab (Parent Mode only)
    if isParentMode {
        ParentChallengesTabView()
            .tabItem {
                Label("Challenges", systemImage: "trophy.fill")
            }
            .navigationTitle("Challenges")
    }
}
```

---

### Task 2.2: Create ParentChallengesTabView 🆕 (4 hours)

**Create:** `ScreenTimeRewards/Views/ParentMode/ParentChallengesTabView.swift`

```swift
import SwiftUI

struct ParentChallengesTabView: View {
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var showingChallengeBuilder = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 1.0, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Create Challenge Button
                    createChallengeButton

                    // Preconfigured Templates
                    if !viewModel.activeChallenges.isEmpty {
                        Divider()
                            .padding(.horizontal)
                    }

                    templatesSection

                    // Active Challenges List
                    if !viewModel.activeChallenges.isEmpty {
                        activeChallengesSection
                    } else {
                        emptyStateView
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingChallengeBuilder) {
            ChallengeBuilderView()
        }
        .task {
            await viewModel.loadChallenges()
        }
    }
}

// MARK: - Subviews

private extension ParentChallengesTabView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Challenges")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Motivate learning with goals and rewards")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    var createChallengeButton: some View {
        Button(action: {
            showingChallengeBuilder = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Create Custom Challenge")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    var templatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Start Templates")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(ChallengeTemplate.allTemplates) { template in
                        ChallengeTemplateCard(template: template) {
                            // Use template
                            showingChallengeBuilder = true
                            viewModel.selectTemplate(template)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Challenges (\(viewModel.activeChallenges.count))")
                .font(.headline)
                .padding(.horizontal)

            ForEach(viewModel.activeChallenges) { challenge in
                NavigationLink(destination: ChallengeDetailView(challenge: challenge)) {
                    ParentChallengeCard(challenge: challenge, progress: viewModel.challengeProgress[challenge.id])
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Active Challenges")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Create a challenge to motivate your child's learning")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }
}
```

---

### Task 2.3: Create ChallengeTemplateCard 🆕 (1 hour)

**Create:** `ScreenTimeRewards/Views/ParentMode/ChallengeTemplateCard.swift`

```swift
import SwiftUI

struct ChallengeTemplateCard: View {
    let template: ChallengeTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                Image(systemName: template.icon)
                    .font(.system(size: 40))
                    .foregroundColor(Color(hex: template.colorHex))

                // Title
                Text(template.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                // Description
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                // Stats
                HStack {
                    Label("\(template.suggestedTarget) min", systemImage: "clock")
                        .font(.caption2)
                    Spacer()
                    Label("+\(template.suggestedBonus)%", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .frame(width: 180, height: 220)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: template.colorHex).opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: template.colorHex), lineWidth: 2)
            )
        }
    }
}
```

---

### Task 2.4: Create ChallengeBuilderView 🆕 (6 hours)

**Create:** `ScreenTimeRewards/Views/ParentMode/ChallengeBuilderView.swift`

This is a **large file** with form fields for custom challenge creation. See full implementation in specification document.

**Key sections:**
- Title & Description fields
- Goal Type picker (Daily/Weekly/Specific Apps/Streak)
- Target value slider
- Bonus percentage slider
- App selection (for specific apps goal)
- Date pickers (start/end)
- Save/Cancel buttons

---

### Task 2.5: Create ChallengeViewModel 🆕 (3 hours)

**Create:** `ScreenTimeRewards/ViewModels/ChallengeViewModel.swift`

```swift
import Foundation
import Combine

@MainActor
class ChallengeViewModel: ObservableObject {
    @Published var activeChallenges: [Challenge] = []
    @Published var challengeProgress: [String: ChallengeProgress] = [:]
    @Published var selectedTemplate: ChallengeTemplate?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let challengeService = ChallengeService.shared

    func loadChallenges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let deviceID = DeviceModeManager.shared.deviceID
            activeChallenges = try await challengeService.fetchActiveChallenges(for: deviceID)
            challengeProgress = challengeService.challengeProgress
        } catch {
            errorMessage = "Failed to load challenges: \(error.localizedDescription)"
        }
    }

    func selectTemplate(_ template: ChallengeTemplate) {
        selectedTemplate = template
    }

    func createChallenge(_ challenge: Challenge) async {
        do {
            try await challengeService.createChallenge(challenge)
            await loadChallenges()
        } catch {
            errorMessage = "Failed to create challenge: \(error.localizedDescription)"
        }
    }
}
```

---

### Task 2.6: Build & Test Phase 2 ✅ (3 hours)

**Test checklist:**
- [ ] Challenges tab appears in Parent Mode (4th tab)
- [ ] Challenges tab NOT visible in Child Mode
- [ ] Template cards display correctly with colors
- [ ] Tapping template opens challenge builder
- [ ] Custom challenge builder form works
- [ ] Can create and save challenges
- [ ] Challenges sync to CloudKit
- [ ] Challenges list displays created challenges

---

## PHASE 3: Child Experience (Week 3)

### Task 3.1: Add Challenge Summary Card to Child Dashboard 🔧 (3 hours)

**File:** `ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift`

**ADD after pointsCard (around line 30):**

```swift
// Challenge Summary Card
if !viewModel.activeChallenges.isEmpty {
    challengeSummaryCard
}
```

**ADD computed property:**

```swift
var challengeSummaryCard: some View {
    NavigationLink(destination: ChildChallengesTabView()) {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                Text("Active Challenges")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            // Show nearest to completion
            if let nearestChallenge = viewModel.activeChallenges.first,
               let progress = viewModel.challengeProgress[nearestChallenge.id] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(nearestChallenge.title)
                        .font(.subheadline)

                    ProgressView(value: Double(progress.currentValue), total: Double(progress.targetValue))
                        .tint(.green)

                    HStack {
                        Text("\(progress.currentValue)/\(progress.targetValue) min")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(progress.progressPercentage))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Streak display
            if viewModel.currentStreak > 0 {
                HStack {
                    Text("🔥")
                    Text("\(viewModel.currentStreak) day streak!")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
    }
}
```

---

### Task 3.2: Create ChildChallengesTabView 🆕 (6 hours)

**Create:** `ScreenTimeRewards/Views/ChildMode/ChildChallengesTabView.swift`

**Add 3rd tab to Child Mode MainTabView:**

```swift
// In MainTabView.swift, add after LearningTabView in CHILD mode:

if !isParentMode {
    ChildChallengesTabView()
        .tabItem {
            Label("Challenges", systemImage: "star.fill")
        }
        .navigationTitle("Challenges")
}
```

**ChildChallengesTabView implementation:**

```swift
import SwiftUI

struct ChildChallengesTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Active Challenges
                if !viewModel.activeChallenges.isEmpty {
                    activeChallengesSection
                } else {
                    emptyStateView
                }

                // Streak Section
                if viewModel.currentStreak > 0 {
                    streakSection
                }

                // Badges Section
                badgesSection

                Spacer()
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadChallengeData()
        }
    }
}

// MARK: - Subviews

private extension ChildChallengesTabView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Text("⭐")
                .font(.system(size: 60))

            Text("Your Challenges")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Complete goals to earn bonus points!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Challenges")
                .font(.headline)
                .padding(.horizontal)

            ForEach(viewModel.activeChallenges) { challenge in
                ChildChallengeCard(
                    challenge: challenge,
                    progress: viewModel.challengeProgress[challenge.id]
                )
            }
        }
    }

    var streakSection: some View {
        VStack(spacing: 12) {
            Text("🔥")
                .font(.system(size: 80))

            Text("\(viewModel.currentStreak) Day Streak!")
                .font(.title)
                .fontWeight(.bold)

            Text("Keep it going! Come back tomorrow to continue your streak.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(0.1))
        )
    }

    var badgesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Badges")
                .font(.headline)
                .padding(.horizontal)

            // TODO: Implement badge grid in Phase 4
            Text("Badge system coming soon!")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Active Challenges")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Ask your parent to create a challenge for you!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }
}
```

---

### Task 3.3: Create ChildChallengeCard 🆕 (4 hours)

**Create:** `ScreenTimeRewards/Views/ChildMode/ChildChallengeCard.swift`

```swift
import SwiftUI

struct ChildChallengeCard: View {
    let challenge: Challenge
    let progress: ChallengeProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: goalTypeIcon)
                    .font(.title2)
                    .foregroundColor(goalTypeColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.headline)

                    Text(challenge.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Progress Bar
            if let progress = progress {
                VStack(alignment: .leading, spacing: 8) {
                    // Animated progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)

                            // Progress fill
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progressGradient(for: progress.progressPercentage))
                                .frame(width: geometry.size.width * min(progress.progressPercentage / 100, 1.0), height: 16)
                                .animation(.spring(), value: progress.currentValue)
                        }
                    }
                    .frame(height: 16)

                    // Progress text
                    HStack {
                        Text("\(progress.currentValue)/\(progress.targetValue) \(valueUnit)")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(progress.progressPercentage))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Bonus info
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                Text("+\(challenge.bonusPercentage)% bonus points")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.top, 4)

            // Completion badge
            if progress?.isCompleted == true {
                completionBadge
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: progress?.isCompleted == true ? 3 : 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private var goalTypeIcon: String {
        switch challenge.goalType {
        case .dailyMinutes: return "sun.max.fill"
        case .weeklyMinutes: return "calendar"
        case .specificApps: return "app.fill"
        case .streak: return "flame.fill"
        }
    }

    private var goalTypeColor: Color {
        switch challenge.goalType {
        case .dailyMinutes: return .orange
        case .weeklyMinutes: return .blue
        case .specificApps: return .green
        case .streak: return .red
        }
    }

    private var valueUnit: String {
        switch challenge.goalType {
        case .dailyMinutes, .weeklyMinutes, .specificApps: return "min"
        case .streak: return "days"
        }
    }

    private var backgroundColor: Color {
        if progress?.isCompleted == true {
            return Color(hex: "#FFD700").opacity(0.15)  // Gold
        }
        return Color.blue.opacity(0.05)
    }

    private var borderColor: Color {
        if progress?.isCompleted == true {
            return Color(hex: "#FFD700")  // Gold
        }
        return Color.gray.opacity(0.3)
    }

    private func progressGradient(for percentage: Double) -> LinearGradient {
        if percentage >= 90 {
            // Near completion - green
            return LinearGradient(
                colors: [.green, .green.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if percentage >= 50 {
            // Good progress - blue to green
            return LinearGradient(
                colors: [.blue, .green],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            // Early progress - blue
            return LinearGradient(
                colors: [.blue, .blue.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var completionBadge: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Completed!")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.15))
        )
    }
}
```

---

### Task 3.4: Add Real-time Progress Updates 🔧 (4 hours)

**AppUsageViewModel already has challenge notification observers from Phase 1.**

**ADD animation method:**

```swift
@Published var showCompletionCelebration = false
@Published var completedChallengeID: String?

private func showChallengeCompletionAnimation() {
    // Extract challengeID from notification
    if let challengeID = ..., // Get from notification
       let challenge = activeChallenges.first(where: { $0.id == challengeID }) {
        completedChallengeID = challengeID
        showCompletionCelebration = true

        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.showCompletionCelebration = false
        }
    }
}
```

---

### Task 3.5: Build & Test Phase 3 ✅ (3 hours)

**Test checklist:**
- [ ] Challenge summary card appears on child dashboard
- [ ] Tapping summary card navigates to Challenges tab
- [ ] Child sees 3 tabs: Rewards, Learning, Challenges
- [ ] Challenge cards display with correct progress
- [ ] Progress bars animate smoothly
- [ ] Completion state shows gold border + badge
- [ ] Real-time updates work (use learning app, see progress update)
- [ ] Streak counter displays correctly

---

## PHASE 4: Gamification & Polish (Week 4)

### Task 4.1: Implement Badge System 🆕 (6 hours)

**Complete badge methods in ChallengeService:**

```swift
func checkBadgeUnlocks(for deviceID: String) async -> [Badge] {
    var newlyUnlocked: [Badge] = []

    // Fetch all badges for this child
    let badges = try? await fetchBadges(for: deviceID)
    guard let badges = badges else { return [] }

    // Check each badge criteria
    for badge in badges where !badge.isUnlocked {
        let shouldUnlock: Bool

        switch badge.criteria.type {
        case .challengesCompleted:
            let completedCount = challengeProgress.values.filter { $0.isCompleted }.count
            shouldUnlock = completedCount >= badge.criteria.threshold

        case .streakDays:
            if let streak = currentStreak {
                shouldUnlock = streak.currentStreak >= badge.criteria.threshold
            } else {
                shouldUnlock = false
            }

        case .totalLearningMinutes:
            // Get total from AppUsageViewModel
            // This requires integration
            shouldUnlock = false  // TODO

        case .totalPointsEarned:
            // Get total from AppUsageViewModel
            shouldUnlock = false  // TODO
        }

        if shouldUnlock {
            try? await unlockBadge(badge.id)
            newlyUnlocked.append(badge)
        }
    }

    return newlyUnlocked
}
```

---

### Task 4.2: Implement Streak System 🆕 (5 hours)

**Complete streak methods in ChallengeService.**

---

### Task 4.3: Create Completion Animation 🆕 (4 hours)

**Create:** `ScreenTimeRewards/Views/Shared/CompletionCelebrationView.swift`

Confetti animation when challenge completes.

---

### Task 4.4: Create Badge Grid UI 🆕 (3 hours)

**Create:** `ScreenTimeRewards/Views/ChildMode/BadgeGridView.swift`

Grid layout displaying all badges (locked/unlocked).

---

### Task 4.5: Final Polish & Bug Fixes 🔧 (6 hours)

- Animations
- Edge cases
- Error handling
- UI polish

---

### Task 4.6: End-to-End Testing ✅ (6 hours)

**Full flow testing:**
- [ ] Parent creates challenge → syncs to child
- [ ] Child uses learning app → progress updates in real-time
- [ ] Challenge completes → bonus points awarded
- [ ] Badge unlocks → notification shown
- [ ] Streak increments → multiplier applies
- [ ] Parent views child's progress
- [ ] Challenge expires → deactivates automatically

---

## Build Command

```bash
xcodebuild -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -sdk iphoneos \
  -configuration Debug \
  build
```

---

## Total Time Estimate

- **Phase 1:** ~40 hours (1 week)
- **Phase 2:** ~40 hours (1 week)
- **Phase 3:** ~40 hours (1 week)
- **Phase 4:** ~40 hours (1 week)

**Total:** ~160 hours (4 weeks full-time)

---

## Success Criteria

- ✅ Parent can create challenges from templates or custom
- ✅ Challenges sync to child device via CloudKit
- ✅ Child sees active challenges with progress bars
- ✅ Progress updates in real-time as child uses learning apps
- ✅ Bonus points calculated and applied correctly
- ✅ Streak system tracks consecutive days
- ✅ Badges unlock based on achievements
- ✅ Animations enhance user experience
- ✅ No crashes or data loss
- ✅ All tests pass

---

**Start with Phase 1, test thoroughly, then proceed to Phase 2.**

**Good luck! 🚀**
