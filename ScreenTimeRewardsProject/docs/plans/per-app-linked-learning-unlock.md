# Shield Unlock for Per-App Linked Learning Requirements

## Problem Summary

The per-app configuration UI allows parents to set "Unlock Requirements" (linked learning apps with minute requirements) for reward apps, but **the unlock logic is not implemented**. When a child completes the required learning time, the shield remains on the reward app because nothing checks these per-app requirements.

## Root Cause Analysis

1. **Data Model Exists**: `AppScheduleConfiguration` has `linkedLearningApps: [LinkedLearningApp]` with `minutesRequired` and `unlockMode` (AND/OR)

2. **UI Exists**: `LinkedLearningAppsPicker` allows configuration in `AppConfigurationSheet`

3. **Persistence Exists**: `AppScheduleService` saves/loads configurations to UserDefaults

4. **Missing Logic**: No code checks if linked learning app requirements are met and triggers shield removal

5. **Missing Data**: `LinkedLearningApp` only has `minutesRequired` (how long to use learning app), but not `minutesGranted` (how long the reward app stays unlocked after meeting requirement)

Current unlock mechanisms:
- **Challenge-based**: `syncShieldData()` checks `activeChallenges` and calls `unlockRewardApps()` when goal met
- **Point-based**: `unlockRewardApp(token:minutes:)` for manual point redemption

Neither of these uses the per-app `linkedLearningApps` configuration.

## User Requirements

- Each linked learning app should grant a specific number of minutes of reward access (parent-configurable)
- Shield should show progress: "Use [App Name] for X more minutes to unlock"

## Implementation Plan

### Step 0: Extend LinkedLearningApp Model

Add `minutesGranted` property to `LinkedLearningApp` in `AppScheduleConfig.swift`:

```swift
struct LinkedLearningApp: Codable, Equatable, Hashable {
    let logicalID: String      // ID of the learning app
    var minutesRequired: Int   // minutes needed to use learning app (e.g., 15, 30, 45)
    var minutesGranted: Int    // minutes of reward access granted when requirement met
    var goalPeriod: GoalPeriod // daily or weekly

    static func defaultRequirement(logicalID: String) -> LinkedLearningApp {
        LinkedLearningApp(
            logicalID: logicalID,
            minutesRequired: 15,
            minutesGranted: 30,  // Default: 15 min learning grants 30 min reward
            goalPeriod: .daily
        )
    }
}
```

### Step 0b: Update LinkedLearningAppsPicker UI

Add UI in `LinkedLearningAppsPicker.swift` to let parent configure `minutesGranted` for each linked app.

### Step 1: Add Requirement Check Method to AppScheduleService

Add method to `AppScheduleService.swift`:

```swift
/// Check if a reward app's linked learning requirements are met
/// Returns (isMet: Bool, minutesToGrant: Int, progress: [...])
func checkLinkedLearningRequirementsMet(
    for rewardAppID: String,
    learningUsage: [String: Int]  // logicalID -> minutes used today
) -> (isMet: Bool, minutesToGrant: Int, progress: [(appName: String, current: Int, required: Int)]) {
    guard let config = schedules[rewardAppID],
          !config.linkedLearningApps.isEmpty else {
        return (true, 0, [])  // No requirements = met (but 0 minutes to grant)
    }

    var progress: [(String, Int, Int)] = []
    var metCount = 0
    var totalMinutesToGrant = 0

    for linkedApp in config.linkedLearningApps {
        let currentMinutes = learningUsage[linkedApp.logicalID] ?? 0
        let required = linkedApp.minutesRequired
        progress.append((linkedApp.logicalID, currentMinutes, required))

        if currentMinutes >= required {
            metCount += 1
            totalMinutesToGrant += linkedApp.minutesGranted
        }
    }

    let isMet: Bool
    switch config.unlockMode {
    case .all:
        isMet = metCount == config.linkedLearningApps.count
    case .any:
        isMet = metCount > 0
    }

    return (isMet, totalMinutesToGrant, progress)
}
```

### Step 2: Integrate Check into Usage Update Flow

In `AppUsageViewModel.swift`, add new method `syncPerAppUnlocks()`:

```swift
/// Check and unlock reward apps based on per-app linked learning requirements
private func syncPerAppUnlocks() {
    let scheduleService = AppScheduleService.shared

    // Build learning usage map: logicalID -> minutes today
    var learningUsage: [String: Int] = [:]
    for snapshot in learningSnapshots {
        learningUsage[snapshot.logicalID] = Int(snapshot.totalSeconds / 60)
    }

    // Check each reward app with linked requirements
    for snapshot in rewardSnapshots {
        let logicalID = snapshot.logicalID
        guard let config = scheduleService.getSchedule(for: logicalID),
              !config.linkedLearningApps.isEmpty else {
            continue
        }

        let (isMet, minutesToGrant, _) = scheduleService.checkLinkedLearningRequirementsMet(
            for: logicalID,
            learningUsage: learningUsage
        )

        if isMet && minutesToGrant > 0 {
            // Check if already unlocked with per-app unlock
            if let existing = unlockedRewardApps[snapshot.token], existing.isPerAppUnlock {
                continue  // Already unlocked via this mechanism
            }

            #if DEBUG
            print("[AppUsageViewModel] 🔓 Per-app requirement met for \(snapshot.displayName)")
            print("[AppUsageViewModel]   Granting \(minutesToGrant) minutes of access")
            #endif

            // Unlock this specific reward app with time-limited access
            service.unblockRewardApps(tokens: [snapshot.token])

            // Track as unlocked with granted minutes converted to points
            let tokenHash = service.usagePersistence.tokenHash(for: snapshot.token)
            let pointsToReserve = minutesToGrant * snapshot.pointsPerMinute
            let unlockedApp = UnlockedRewardApp(
                token: snapshot.token,
                tokenHash: tokenHash,
                reservedPoints: pointsToReserve,
                pointsPerMinute: snapshot.pointsPerMinute,
                isChallengeReward: false,
                isPerAppUnlock: true  // New flag
            )
            unlockedRewardApps[snapshot.token] = unlockedApp
            persistUnlockedApps()
        }
    }
}
```

### Step 3: Call syncPerAppUnlocks in the Update Flow

Add call to `syncPerAppUnlocks()` in `updateSnapshots()` after line 715:

```swift
// Sync shield data for dynamic shield messages
syncShieldData()

// Check per-app linked learning requirements
syncPerAppUnlocks()
```

### Step 4: Update Shield Display to Show Per-App Progress

Modify `ShieldDataService.swift` and `ShieldConfigurationExtension.swift` to support per-app progress display:

1. Add per-app unlock progress to shared data
2. Display "Use [Learning App] for X more minutes to unlock" on shield

### Step 5: Save Linked Apps to Extension (Optional Enhancement)

Update `AppScheduleService.saveScheduleForExtension()` to include linked learning app data for extension access.

## Files to Modify

1. **`ScreenTimeRewards/Models/AppScheduleConfig.swift`**
   - Add `minutesGranted: Int` property to `LinkedLearningApp` struct
   - Update `defaultRequirement()` factory method

2. **`ScreenTimeRewards/Views/AppConfig/Components/LinkedLearningAppsPicker.swift`**
   - Add UI picker for `minutesGranted` (how long the reward stays unlocked)

3. **`ScreenTimeRewards/Services/AppScheduleService.swift`**
   - Add `checkLinkedLearningRequirementsMet()` method
   - Add `saveLinkedLearningAppsForExtension()` to share with extension

4. **`ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`**
   - Add `syncPerAppUnlocks()` method
   - Call it from `updateSnapshots()` after `syncShieldData()`

5. **`ScreenTimeRewards/Models/AppUsage.swift`** (UnlockedRewardApp struct)
   - Add `isPerAppUnlock: Bool` flag to differentiate unlock types
   - Uses `reservedPoints` for time-limited access (consumed as app is used)

6. **`ScreenTimeRewards/Services/ShieldDataService.swift`**
   - Add per-app progress data structure for shield display

7. **`ShieldConfigurationExtension/ShieldConfigurationExtension.swift`**
   - Display linked learning app requirements and progress on shield

## Testing Plan

1. **Model Migration**: Verify existing `AppScheduleConfiguration` data loads correctly with new `minutesGranted` field (migration handling)
2. **UI Configuration**: Configure a reward app with linked learning app, set both `minutesRequired` and `minutesGranted`
3. **Shield Application**: Verify shield is applied to reward app with progress message showing
4. **Usage Tracking**: Use the linked learning app, verify usage updates in app UI and shield message
5. **Unlock Trigger**: When requirement met, verify shield is removed and `minutesGranted` access is applied
6. **Time Consumption**: Verify reward app usage consumes the granted time (reservedPoints decreases)
7. **Re-lock**: When granted time expires, verify app re-locks
8. **Multi-App**: Test with multiple linked apps (AND mode and OR mode)
9. **Daily Reset**: Verify per-app unlock state resets at midnight
