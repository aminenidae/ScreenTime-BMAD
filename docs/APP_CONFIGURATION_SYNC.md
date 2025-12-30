# App Configuration Sync: Parent Dashboard Enhancement

**Date:** December 30, 2024
**Status:** Implemented (Full Config + Shield State Sync)
**Related Files:** ScreenTimeService.swift, CloudKitSyncService.swift, ParentRemoteViewModel.swift, ChildUsageDashboardView.swift, AppScheduleConfig.swift

---

## Overview

This document describes the implementation of real-time app configuration syncing between child and parent devices. The parent dashboard shows complete app configuration including schedules, linked learning goals, streak settings, and live shield state (blocked/unlocked status).

---

## Features

### What Gets Synced

| Feature | Description |
|---------|-------------|
| **Basic App Info** | App name, category (Learning/Reward), enabled status |
| **Schedule Config** | Time windows, daily limits |
| **Linked Learning Goals** | App names, required minutes, unlock mode (all/any) |
| **Streak Settings** | Bonus configuration when enabled |
| **Shield State** | Live blocked/unlocked status for reward apps |

### Parent Dashboard Display

```
Today's Activity:
[Learning: 45m] [Rewards: 30m]

Reward Apps:
[YouTube] [BLOCKED]
├─ Last 7 days: 2h 15m
├─ 🕐 3pm - 8pm  ⏱ 45 min/day
├─ 🔓 Unlock Requirements (Complete All):
│   • Khan Academy • 15min daily
│   • Duolingo • 10min daily
├─ 🔥 Streak bonus: 10%
```

---

## Data Flow

### Child Device → CloudKit

```
CHILD DEVICE:
┌─────────────────────────────────────────────────────────────┐
│  User configures app (category, schedule, linked goals)     │
│                    ↓                                        │
│  ScreenTimeService.assignCategory() called                  │
│                    ↓                                        │
│  syncAppConfigurationToCloudKit() triggered                 │
│                    ↓                                        │
│  CloudKitSyncService.uploadAppConfigurationsToParent()      │
│  - Includes: scheduleConfigJSON, linkedAppsJSON, streakJSON │
│  - Enriches linked apps with display names                  │
│                    ↓                                        │
│  CloudKitSyncService.uploadShieldStatesToParent()           │
│  - Reads shield states from app group UserDefaults          │
│  - Uploads blocked/unlocked status for reward apps          │
│                    ↓                                        │
│  Uploads to CloudKit Shared Zone                            │
└─────────────────────────────────────────────────────────────┘
```

### CloudKit → Parent Device

```
PARENT DEVICE:
┌─────────────────────────────────────────────────────────────┐
│  Parent opens child dashboard                               │
│                    ↓                                        │
│  ParentRemoteViewModel.loadChildData(for: device)           │
│                    ↓                                        │
│  fetchChildAppConfigurationsFullDTO()                       │
│  - Enumerates all zones to find shared data                 │
│  - Decodes JSON fields (schedule, linkedApps, streaks)      │
│                    ↓                                        │
│  fetchChildShieldStates()                                   │
│  - Gets live blocked/unlocked status                        │
│                    ↓                                        │
│  ChildUsageDashboardView displays full config + status      │
└─────────────────────────────────────────────────────────────┘
```

---

## CloudKit Schema

### CD_AppConfiguration Record

| Field | Type | Description |
|-------|------|-------------|
| `CD_logicalID` | String | Unique app identifier |
| `CD_deviceID` | String | Child device UUID (from DeviceModeManager) |
| `CD_displayName` | String | User-visible app name |
| `CD_category` | String | "Learning" or "Reward" |
| `CD_isEnabled` | Bool | Tracking enabled |
| `CD_blockingEnabled` | Bool | Blocking enabled |
| `CD_lastModified` | Date | Last update timestamp |
| `CD_scheduleConfigJSON` | String | JSON: time windows, daily limits |
| `CD_linkedAppsJSON` | String | JSON: linked learning apps with names |
| `CD_unlockMode` | String | "all" or "any" |
| `CD_streakSettingsJSON` | String | JSON: streak bonus config |
| `CD_dailyLimitSummary` | String | Quick display: "45 min/day" |
| `CD_timeWindowSummary` | String | Quick display: "3pm - 8pm" |

### CD_ShieldState Record

| Field | Type | Description |
|-------|------|-------------|
| `CD_rewardAppLogicalID` | String | Reward app ID |
| `CD_deviceID` | String | Child device UUID |
| `CD_isUnlocked` | Bool | Currently unlocked? |
| `CD_unlockedAt` | Date | When unlocked (if applicable) |
| `CD_reason` | String | "learning_goal_met", etc. |
| `CD_syncTimestamp` | Date | Last sync time |
| `CD_rewardAppDisplayName` | String | App name for display |

---

## Key Implementation Details

### 1. DeviceID Consistency

**Important:** Always use `DeviceModeManager.shared.deviceID` instead of `UIDevice.current.identifierForVendor`. The vendor ID can change after app reinstall, but DeviceModeManager preserves the ID from device registration.

Files using consistent deviceID:
- `CloudKitSyncService.swift` - `uploadAppConfigurationsToParent()`
- `ScreenTimeService.swift` - `syncAppConfigurationToCloudKit()`, `backfillAppConfigurationsForCloudKit()`

### 2. Linked App Names

The `LinkedLearningApp` struct includes a `displayName` field:

```swift
struct LinkedLearningApp: Codable {
    let logicalID: String
    var displayName: String?  // Populated when syncing to CloudKit
    var minutesRequired: Int
    var goalPeriod: GoalPeriod
    var rewardMinutesEarned: Int
}
```

When uploading, `CloudKitSyncService` enriches linked apps with display names:
```swift
for i in enrichedLinkedApps.indices {
    if enrichedLinkedApps[i].displayName == nil {
        enrichedLinkedApps[i].displayName = ScreenTimeService.shared.getDisplayName(for: linkedLogicalID)
    }
}
```

### 3. Zone Enumeration

Parent device must enumerate all zones to find shared data:
```swift
let zones = try await db.allRecordZones()
for zone in zones {
    if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName { continue }
    // Query this zone for records
}
```

### 4. Automatic Sync Triggers

Shield states and app configs are synced when:
- Child device opens app (in `ScreenTimeRewardsApp.swift` `.active` handler)
- User assigns app to category
- User modifies app schedule

---

## DTOs

### FullAppConfigDTO

Contains all decoded config data from CloudKit:
- Basic fields (name, category, enabled)
- `scheduleConfig: AppScheduleConfiguration?`
- `linkedLearningApps: [LinkedLearningApp]`
- `unlockMode: UnlockMode`
- `streakSettings: AppStreakSettings?`

### ShieldStateDTO

Contains live shield status:
- `isUnlocked: Bool`
- `unlockedAt: Date?`
- `reason: String`
- `statusDisplay: String` - "Unlocked at 3:45 PM" or "Blocked"
- `statusIcon: String` - "lock.open.fill" or "lock.fill"

---

## Parent UI Components

### ChildUsageDashboardView

Three-tab layout:
1. **Home** - Today's learning/reward time summary
2. **Learning** - All learning apps
3. **Rewards** - All reward apps with shield state badges

### FullAppConfigRow

Displays app with full config:
- Shield status badge (BLOCKED/UNLOCKED)
- Lock icon overlay on app icon
- Schedule info (time window, daily limit)
- Linked requirements with app names and minutes
- Streak bonus if enabled

---

## Troubleshooting

### Apps Not Appearing on Parent

1. **Check deviceID consistency** - Ensure child's CD_AppConfiguration uses same deviceID as CD_RegisteredDevice
2. **Verify zone access** - Parent must be able to access child's shared zone
3. **Debug logs** - Look for `[CloudKitSyncService]` and `[ParentRemoteViewModel]` logs

### Shield States Not Syncing

1. **Check app group** - Shield states are stored in `group.com.screentimerewards.shared`
2. **Verify ExtensionShieldStates** - Check if extension is writing to UserDefaults
3. **Trigger sync** - Open child app to trigger upload

---

## Related Documentation

- [USAGERECORD_SYNC_FIX.md](./USAGERECORD_SYNC_FIX.md) - UsageRecord CloudKit sync
- [PARENT_DATA_SYNC_FIX.md](./PARENT_DATA_SYNC_FIX.md) - Parent device data synchronization
