# Challenge System - Complete Implementation Specification

**Date:** November 3, 2025
**Priority:** HIGH - Major Feature Addition
**Status:** Ready for Implementation
**Estimated Time:** 4 weeks (4 phases)

---

## Overview

Implement a comprehensive gamification system with **Challenges**, **Streaks**, **Badges**, and **Levels** to motivate children to use learning apps. Parents can create custom challenges or choose from preconfigured templates.

### Core Requirements

- ✅ **Bonus Points System:** Challenges award bonus learning points (e.g., +10%)
- ✅ **Real-time Progress:** Updates instantly as child uses learning apps
- ✅ **Dual View:** Summary on dashboard + dedicated Challenges tab
- ✅ **Full Gamification:** Progress bars, Streaks, Levels & Badges

---

## Architecture Overview

### System Components

```
Parent Device:
├── ChallengesTabView (4th tab)
│   ├── Active Challenges List
│   ├── Create Challenge Button → ChallengeBuilderView
│   ├── Preconfigured Templates
│   └── Challenge Statistics
└── CloudKit Sync → Push challenges to child device

Child Device:
├── ChildDashboardView (modified)
│   └── Challenge Summary Card (new)
├── ChallengesTabView (3rd tab - new)
│   ├── Active Challenges with Progress Bars
│   ├── Streak Display 🔥
│   ├── Badge Grid
│   └── Completed Challenges History
└── Real-time Progress Updates → Sync to parent
```

---

## Data Models

### 1. Challenge Model

**Purpose:** Represents a challenge configuration created by parent.

**File:** `Models/Challenge.swift`

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
        // Format date range
        return "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate!.formatted(date: .abbreviated, time: .omitted))"
    }
}
```

### 2. ChallengeProgress Model

**Purpose:** Tracks child's real-time progress on challenges.

**File:** `Models/ChallengeProgress.swift`

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

### 3. Badge Model

**Purpose:** Represents achievement badges that children can unlock.

**File:** `Models/Badge.swift`

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

### 4. StreakRecord Model

**Purpose:** Tracks consecutive daily/weekly achievements.

**File:** `Models/StreakRecord.swift`

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

---

## Core Data Schema

### Entities to Add

Add to `ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`:

```xml
<!-- Challenge Entity -->
<entity name="Challenge" representedClassName="Challenge" syncable="YES">
    <attribute name="challengeID" attributeType="String"/>
    <attribute name="title" attributeType="String"/>
    <attribute name="challengeDescription" attributeType="String"/>
    <attribute name="goalType" attributeType="String"/>
    <attribute name="targetValue" attributeType="Integer 32" defaultValueString="0"/>
    <attribute name="bonusPercentage" attributeType="Integer 16" defaultValueString="10"/>
    <attribute name="targetAppsJSON" optional="YES" attributeType="String"/>
    <attribute name="startDate" attributeType="Date"/>
    <attribute name="endDate" optional="YES" attributeType="Date"/>
    <attribute name="isActive" attributeType="Boolean" defaultValueString="YES"/>
    <attribute name="createdBy" attributeType="String"/>
    <attribute name="assignedTo" attributeType="String"/>
    <fetchIndex name="byChallengeID">
        <fetchIndexElement property="challengeID" type="Binary" order="ascending"/>
    </fetchIndex>
    <fetchIndex name="byAssignedTo">
        <fetchIndexElement property="assignedTo" type="Binary" order="ascending"/>
    </fetchIndex>
</entity>

<!-- ChallengeProgress Entity -->
<entity name="ChallengeProgress" representedClassName="ChallengeProgress" syncable="YES">
    <attribute name="progressID" attributeType="String"/>
    <attribute name="challengeID" attributeType="String"/>
    <attribute name="childDeviceID" attributeType="String"/>
    <attribute name="currentValue" attributeType="Integer 32" defaultValueString="0"/>
    <attribute name="targetValue" attributeType="Integer 32" defaultValueString="0"/>
    <attribute name="isCompleted" attributeType="Boolean" defaultValueString="NO"/>
    <attribute name="completedDate" optional="YES" attributeType="Date"/>
    <attribute name="bonusPointsEarned" attributeType="Integer 32" defaultValueString="0"/>
    <attribute name="lastUpdated" attributeType="Date"/>
    <fetchIndex name="byProgressID">
        <fetchIndexElement property="progressID" type="Binary" order="ascending"/>
    </fetchIndex>
    <fetchIndex name="byChallengeID">
        <fetchIndexElement property="challengeID" type="Binary" order="ascending"/>
    </fetchIndex>
</entity>

<!-- Badge Entity -->
<entity name="Badge" representedClassName="Badge" syncable="YES">
    <attribute name="badgeID" attributeType="String"/>
    <attribute name="badgeName" attributeType="String"/>
    <attribute name="badgeDescription" attributeType="String"/>
    <attribute name="iconName" attributeType="String"/>
    <attribute name="unlockedAt" optional="YES" attributeType="Date"/>
    <attribute name="criteriaJSON" attributeType="String"/>
    <attribute name="childDeviceID" attributeType="String"/>
    <fetchIndex name="byBadgeID">
        <fetchIndexElement property="badgeID" type="Binary" order="ascending"/>
    </fetchIndex>
    <fetchIndex name="byChildDeviceID">
        <fetchIndexElement property="childDeviceID" type="Binary" order="ascending"/>
    </fetchIndex>
</entity>

<!-- StreakRecord Entity -->
<entity name="StreakRecord" representedClassName="StreakRecord" syncable="YES">
    <attribute name="streakID" attributeType="String"/>
    <attribute name="childDeviceID" attributeType="String"/>
    <attribute name="streakType" attributeType="String"/>
    <attribute name="currentStreak" attributeType="Integer 16" defaultValueString="0"/>
    <attribute name="longestStreak" attributeType="Integer 16" defaultValueString="0"/>
    <attribute name="lastActivityDate" attributeType="Date"/>
    <fetchIndex name="byStreakID">
        <fetchIndexElement property="streakID" type="Binary" order="ascending"/>
    </fetchIndex>
    <fetchIndex name="byChildDeviceID">
        <fetchIndexElement property="childDeviceID" type="Binary" order="ascending"/>
    </fetchIndex>
</entity>
```

---

## Services

### ChallengeService

**Purpose:** Central service managing all challenge logic, progress tracking, and bonus calculations.

**File:** `Services/ChallengeService.swift`

**Key Methods:**

```swift
@MainActor
class ChallengeService: ObservableObject {
    static let shared = ChallengeService()

    // MARK: - Published Properties
    @Published private(set) var activeChallenges: [Challenge] = []
    @Published private(set) var challengeProgress: [String: ChallengeProgress] = [:]

    // MARK: - Notifications
    static let challengeProgressUpdated = Notification.Name("ChallengeProgressUpdated")
    static let challengeCompleted = Notification.Name("ChallengeCompleted")
    static let badgeUnlocked = Notification.Name("BadgeUnlocked")

    // MARK: - Challenge Management
    func createChallenge(_ challenge: Challenge) async throws
    func activateChallenge(_ challengeID: String) async throws
    func deactivateChallenge(_ challengeID: String) async throws
    func fetchActiveChallenges(for deviceID: String) async throws -> [Challenge]

    // MARK: - Progress Tracking (Real-time)
    func updateProgress(for challengeID: String, incrementBy minutes: Int) async
    func updateProgressForUsage(appID: String, duration: TimeInterval, deviceID: String) async
    func checkChallengeCompletion(_ challengeID: String) async -> Bool

    // MARK: - Bonus Calculation
    func calculateBonusPoints(basePoints: Int, for deviceID: String) -> Int
    func awardBonusPoints(for challengeID: String) async throws -> Int

    // MARK: - Badge System
    func checkBadgeUnlocks(for deviceID: String) async -> [Badge]
    func unlockBadge(_ badgeID: String) async throws
    func fetchBadges(for deviceID: String) async throws -> [Badge]

    // MARK: - Streak System
    func updateStreak(for deviceID: String, date: Date) async
    func breakStreak(for deviceID: String) async
    func fetchStreak(for deviceID: String) async throws -> StreakRecord?
    func calculateStreakMultiplier(_ streak: Int) -> Double
}
```

---

## Preconfigured Templates

### Template Definitions

**File:** `Models/ChallengeTemplate.swift`

```swift
struct ChallengeTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String  // SF Symbol
    let goalType: Challenge.GoalType
    let suggestedTarget: Int
    let suggestedBonus: Int
    let color: String  // Hex color for UI

    static let allTemplates: [ChallengeTemplate] = [
        ChallengeTemplate(
            id: "daily_dynamo",
            name: "Daily Dynamo",
            description: "Complete 60 minutes of learning every day",
            icon: "bolt.fill",
            goalType: .dailyMinutes,
            suggestedTarget: 60,
            suggestedBonus: 10,
            color: "#FFB800"
        ),
        ChallengeTemplate(
            id: "weekend_warrior",
            name: "Weekend Warrior",
            description: "Learn 180 minutes over the weekend",
            icon: "trophy.fill",
            goalType: .weeklyMinutes,
            suggestedTarget: 180,
            suggestedBonus: 15,
            color: "#FF6B35"
        ),
        ChallengeTemplate(
            id: "app_master",
            name: "App Master",
            description: "Spend 5 hours in your favorite learning app this week",
            icon: "target",
            goalType: .specificApps,
            suggestedTarget: 300,
            suggestedBonus: 20,
            color: "#4ECDC4"
        ),
        ChallengeTemplate(
            id: "streak_champion",
            name: "Streak Champion",
            description: "Maintain a 7-day learning streak",
            icon: "flame.fill",
            goalType: .streak,
            suggestedTarget: 7,
            suggestedBonus: 25,
            color: "#FF3366"
        ),
        ChallengeTemplate(
            id: "quick_start",
            name: "Quick Start",
            description: "Just 15 minutes of learning per day",
            icon: "star.fill",
            goalType: .dailyMinutes,
            suggestedTarget: 15,
            suggestedBonus: 5,
            color: "#95E1D3"
        )
    ]
}
```

---

## Starter Badges

**File:** `Models/BadgeDefinitions.swift`

```swift
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

## Integration Points

### 1. AppUsageViewModel Integration

**File:** `ViewModels/AppUsageViewModel.swift`

**Add properties:**
```swift
// Challenge integration
@Published var activeChallenges: [Challenge] = []
@Published var challengeProgress: [String: ChallengeProgress] = [:]
@Published var currentStreak: Int = 0
private let challengeService = ChallengeService.shared
```

**Modify points calculation:**
```swift
/// Calculate total learning points with challenge bonuses applied
var totalLearningPointsWithBonuses: Int {
    let basePoints = learningRewardPoints
    let bonusPoints = challengeService.calculateBonusPoints(basePoints: basePoints, for: deviceID)
    return basePoints + bonusPoints
}
```

### 2. ScreenTimeService Integration

**File:** `Services/ScreenTimeService.swift`

**Add challenge update hook after recording usage:**
```swift
// EXISTING: Record usage to persistence
usagePersistence.recordUsage(...)

// NEW: Notify challenge service of learning app usage
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

## CloudKit Sync Strategy

### Parent → Child (Challenge Distribution)

1. **Parent creates challenge** → Save to Core Data
2. **NSPersistentCloudKitContainer** automatically syncs to CloudKit
3. **Child device** receives via CloudKit push notification
4. **Child's ChallengeService** fetches and activates challenge locally

### Child → Parent (Progress Reporting)

1. **Child makes progress** → Update `ChallengeProgress` in Core Data
2. **Real-time sync** to CloudKit via NSPersistentCloudKitContainer
3. **Parent device** receives push and updates UI
4. **Parent can view** live progress in `ChallengeDetailView`

**No custom CloudKit code needed** - NSPersistentCloudKitContainer handles all sync automatically.

---

## Visual Design Guidelines

### Color Palette

```swift
extension Color {
    // Challenge colors
    static let challengeGold = Color(hex: "#FFB800")
    static let challengeOrange = Color(hex: "#FF6B35")
    static let challengeTeal = Color(hex: "#4ECDC4")
    static let challengeRed = Color(hex: "#FF3366")
    static let challengeMint = Color(hex: "#95E1D3")

    // Progress states
    static let progressBlue = Color.blue
    static let progressGreen = Color.green
    static let completedGold = Color(hex: "#FFD700")
}
```

### Progress Bar Design

- **0-50%:** Blue gradient
- **51-89%:** Blue → Green gradient
- **90-99%:** Pulsing green (near completion)
- **100%:** Gold with shine animation

### Card Design

- **Rounded corners:** 16pt
- **Shadow:** soft drop shadow
- **Padding:** 16pt internal
- **Gradient backgrounds** for completed challenges

---

## Animations

### Completion Celebration

```swift
// Confetti effect when challenge completes
// Scale + fade animation for badges
// Pulse effect for progress bars near completion
// Fire emoji animation for streak milestones
```

**Use:**
- `withAnimation(.spring())`
- `ConfettiView` library or custom particle system
- SF Symbols with `.symbolEffect()` modifier (iOS 17+)

---

## Testing Checklist

### Unit Tests
- [ ] Challenge creation with valid/invalid data
- [ ] Progress calculation accuracy
- [ ] Bonus points calculation
- [ ] Streak logic (increment, break, restore)
- [ ] Badge unlock conditions

### Integration Tests
- [ ] CloudKit sync (parent creates → child receives)
- [ ] Real-time progress updates
- [ ] Multi-challenge bonus stacking
- [ ] Streak multiplier application

### UI Tests
- [ ] Challenge builder workflow
- [ ] Progress bar rendering
- [ ] Badge grid display
- [ ] Completion animations
- [ ] Tab navigation (Parent 4 tabs, Child 3 tabs)

---

## Success Metrics

- **Engagement:** Child checks Challenges tab daily (target: 80% of days)
- **Motivation:** Learning app usage increase (target: +30%)
- **Completion Rate:** Challenges completed (target: 70%+)
- **Streak Retention:** Average streak length (target: 5+ days)
- **Parent Adoption:** Parents create challenges (target: 90% of parents)

---

## Reference Documentation

- **Phase 1:** Parent Dashboard (completed)
- **Phase 2:** Child Device UX/UI (in progress)
- **Phase 3:** Challenge System (this document)

---

**End of Specification**
