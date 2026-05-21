# Notification System Implementation Plan

## Overview
Implement 12 notifications across child local, parent push, and system categories.

## Notifications Summary

| # | Notification | Audience | Type | Trigger |
|---|-------------|----------|------|---------|
| 1 | Streak milestone achieved | Child | Local | StreakService milestone detection |
| 2 | Learning goal completed | Child | Local | BlockingCoordinator goal check |
| 3 | Approaching daily limit (80%) | Child | Local | BlockingCoordinator limit check |
| 4 | Downtime starting soon | Child | Local | Scheduled based on time window config |
| 5 | Time bank low | Child | Local | When reward minutes drop below threshold |
| 6 | Streak at risk | Child | Local | 7 PM + 1hr before downtime (cancellable) |
| 7 | Child reached daily limit | Parent | Push | CloudKit record from child device |
| 8 | Child learning goal completed | Parent | Push | CloudKit record from child device |
| 9 | Weekly usage summary | Parent | Push | Scheduled Sunday 6 PM |
| 10 | Child streak milestone | Parent | Push | CloudKit record from child device |
| 11 | Trial ending (7, 3, 0 days) | Both | Local | SubscriptionManager state change |
| 12 | Subscription expiring (7, 3, 0 days) | Both | Local | SubscriptionManager state change |

---

## New Files to Create

### 1. `/Services/NotificationService.swift`
Central service for all notification scheduling:
- Permission request (`requestAuthorization()`)
- Category registration (streak, goal, limit, downtime, subscription)
- Duplicate prevention via UserDefaults date-keyed tracking
- Schedule/cancel methods for each notification type
- Parent notification dispatch to CloudKit

### 2. `/Models/NotificationPayload.swift`
CloudKit record model for parent push notifications:
- `ParentNotificationPayload` struct with type, title, body, metadata
- `toCKRecord()` method for uploading to parent's shared zone

### 3. `/Services/DeepLinkManager.swift`
Handle notification tap navigation:
- `@Published pendingDestination: AppDestination?`
- Route based on notification type and action identifier

---

## Files to Modify

### `/AppDelegate.swift`
- Extend `userNotificationCenter(_:didReceive:)` to call `DeepLinkManager.shared.handleNotificationAction()`

### `/Services/BlockingCoordinator.swift`
**In `checkDailyLimit()` (~line 433):**
- Add 80% threshold check → `scheduleApproachingLimitNotification()`
- On 100% limit → `notifyParentOfDailyLimitReached()`

**In `checkAndUpdateStreak()` (~line 664):**
- After milestone → `scheduleStreakMilestoneNotification()` + `notifyParentOfStreakMilestone()`

### `/Services/ScreenTimeService.swift`
**In `unblockRewardApps()` (~line 2562):**
- Trigger `scheduleLearningGoalCompletedNotification()`
- Trigger `notifyParentOfLearningGoalCompleted()`
- Cancel streak-at-risk reminders for unlocked apps

### `/Services/StreakService.swift`
**After `notifyMilestoneAchieved()` (~line 321):**
- Call NotificationService for local + parent notifications

### `/Services/SubscriptionManager.swift`
**In `createTrialSubscription()` and `updateSubscriptionState()`:**
- Call `scheduleSubscriptionReminders(for: subscription)`

### `/Services/CloudKitSyncService.swift`
**Add new method:**
```swift
func sendParentNotification(_ payload: ParentNotificationPayload) async throws
```
- Create CKRecord in parent's shared zone
- CloudKit subscription triggers push to parent device

### `/Views/Onboarding/Screen4_AuthorizationView.swift`
- Add notification permission request after Screen Time authorization

---

## Implementation Phases

### Phase 1: Foundation
1. Create `NotificationService.swift` with:
   - Core singleton structure
   - `requestAuthorization()` method
   - `registerCategories()` for notification actions
   - Duplicate prevention with date-keyed UserDefaults

2. Create `NotificationPayload.swift` model

### Phase 2: Child Local Notifications
1. `scheduleStreakMilestoneNotification(milestone:bonusMinutes:appName:)`
2. `scheduleLearningGoalCompletedNotification(earnedMinutes:)`
3. `scheduleApproachingLimitNotification(appName:usedMinutes:limitMinutes:)`
4. `scheduleDowntimeWarning(for:appName:windowEndHour:windowEndMinute:)`
5. `scheduleTimeBankLowNotification(remainingMinutes:threshold:)`
6. `scheduleStreakAtRiskReminder(appLogicalID:appName:)` + `cancelStreakAtRiskReminders(for:)`

### Phase 3: Integration Points
1. Modify BlockingCoordinator for limit and streak triggers
2. Modify ScreenTimeService for goal completion triggers
3. Add permission request to onboarding

### Phase 4: Parent Push Notifications
1. Add `sendParentNotification()` to CloudKitSyncService
2. Implement `notifyParentOfDailyLimitReached()`
3. Implement `notifyParentOfLearningGoalCompleted()`
4. Implement `notifyParentOfStreakMilestone()`
5. Schedule weekly summary background task

### Phase 5: System & Deep Linking
1. Implement subscription reminder scheduling
2. Create DeepLinkManager
3. Extend AppDelegate notification action handler
4. Wire up deep link navigation in main app

### Phase 6: Testing
1. Test all 12 notification types manually
2. Verify duplicate prevention resets daily
3. Verify streak-at-risk cancellation when goal met
4. Test parent device receives CloudKit push
5. Test deep link navigation from each notification type

---

## Key Implementation Details

### Duplicate Prevention
```swift
private func hasNotificationBeenSent(identifier: String, today: Bool = true) -> Bool {
    let key = today ? "\(identifier)_\(dateKey())" : identifier
    let sent = defaults?.stringArray(forKey: sentNotificationsKey) ?? []
    return sent.contains(key)
}
```

### Cancellable Streak Reminders
- Schedule at 7 PM daily + 1 hour before downtime
- Store identifiers in UserDefaults
- Cancel when goal is met via `cancelStreakAtRiskReminders(for:)`

### Parent Push via CloudKit
- Child uploads `ParentNotification` record to shared zone
- CloudKit subscription on parent device triggers remote notification
- AppDelegate.handlePushNotification() already processes CloudKit pushes

### Notification Categories
| Category | Actions |
|----------|---------|
| STREAK_MILESTONE | View Streak |
| LEARNING_GOAL | Start Learning |
| STREAK_AT_RISK | Start Now, Remind in 1 hour |
| SUBSCRIPTION_REMINDER | Subscribe |

---

## Critical File Paths
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/NotificationService.swift` (NEW)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Models/NotificationPayload.swift` (NEW)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/DeepLinkManager.swift` (NEW)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift` (MODIFY)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift` (MODIFY)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/CloudKitSyncService.swift` (MODIFY)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/SubscriptionManager.swift` (MODIFY)
- `/ScreenTimeRewardsProject/ScreenTimeRewards/AppDelegate.swift` (MODIFY)
