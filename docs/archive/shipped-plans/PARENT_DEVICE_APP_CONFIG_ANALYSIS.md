# Parent Device App Configuration: Technical Deep-Dive

> **Branch:** `feature/parent-device-app-config`
> **Date:** December 30, 2024
> **Status:** Feasibility Analysis & Implementation Plan

---

## Executive Summary

This document analyzes the feasibility of allowing parents to modify app configurations from their device for apps already configured on the child's device. **The feature is fully feasible** using existing infrastructure.

### Key Findings

| Capability | Feasibility | Reasoning |
|------------|-------------|-----------|
| Modify daily limits | **YES** | Config stored as JSON, can be remotely updated |
| Change time windows | **YES** | Part of AppScheduleConfiguration |
| Enable/disable apps | **YES** | Simple boolean toggle |
| Change points/minute | **YES** | Integer field on AppConfiguration |
| Set linked learning apps | **YES** | Array of LinkedLearningApp objects |
| Configure streaks | **YES** | AppStreakSettings struct |
| Add NEW apps to track | **NO** | Requires FamilyActivityPicker (child device only) |

---

## 1. Current Architecture

### 1.1 Data Flow: Child to Parent (Existing)

```
CHILD DEVICE                    CLOUDKIT                         PARENT DEVICE
     |                              |                                  |
[AppConfiguration]                  |                                  |
[AppScheduleConfiguration]          |                                  |
[LinkedLearningApps]                |                                  |
[StreakSettings]                    |                                  |
     |                              |                                  |
     +--[CloudKitSyncService]------>|                                  |
        uploadAppConfigurationsToParent()                               |
                                    |                                  |
                                    |  CD_AppConfiguration             |
                                    |  + CD_scheduleConfigJSON         |
                                    |  + CD_linkedAppsJSON             |
                                    |  + CD_streakSettingsJSON         |
                                    |                                  |
                                    +--------------------------------->|
                                                                       |
                                               [ParentRemoteViewModel] |
                                               fetchChildAppConfigurationsFullDTO()
                                                                       |
                                               [FullAppConfigDTO]      |
                                               - scheduleConfig        |
                                               - linkedLearningApps    |
                                               - streakSettings        |
```

### 1.2 Parent to Child Commands (Existing Infrastructure - Unused)

```swift
// File: Services/CloudKitSyncService.swift (lines 179-206)
func sendConfigurationToChild(deviceID: String, configuration: AppConfiguration) async throws {
    let command = ConfigurationCommand(context: context)
    command.commandID = UUID().uuidString
    command.targetDeviceID = deviceID
    command.commandType = "update_configuration"
    command.payloadJSON = try JSONSerialization.data(withJSONObject: configDict).base64EncodedString()
    command.createdAt = Date()
    command.status = "pending"
    try context.save()
}
```

**Current Limitation:** This method only sends basic fields (logicalID, category, pointsPerMinute, isEnabled, blockingEnabled). It does NOT include:
- Schedule configuration (daily limits, time windows)
- Linked learning apps
- Streak settings

### 1.3 Core Data Model: ConfigurationCommand

```swift
// File: Models/ConfigurationCommand.swift
@NSManaged public var commandID: String?
@NSManaged public var targetDeviceID: String?
@NSManaged public var commandType: String?      // "update_configuration", "request_sync"
@NSManaged public var payloadJSON: String?      // Base64-encoded JSON
@NSManaged public var createdAt: Date?
@NSManaged public var executedAt: Date?
@NSManaged public var status: String?           // "pending", "executed", "failed"
@NSManaged public var errorMessage: String?
```

---

## 2. Proposed Data Flow: Parent Modifies Child Config

```
PARENT DEVICE                         CLOUDKIT                           CHILD DEVICE
     |                                    |                                   |
[ParentAppEditSheet]                      |                                   |
  - Edit daily limits                     |                                   |
  - Edit time windows                     |                                   |
  - Toggle enabled                        |                                   |
  - Edit streak settings                  |                                   |
     |                                    |                                   |
     v                                    |                                   |
[ParentRemoteViewModel]                   |                                   |
sendFullConfigUpdate()                    |                                   |
     |                                    |                                   |
     v                                    |                                   |
[CloudKitSyncService]                     |                                   |
sendFullConfigurationCommand()            |                                   |
     |                                    |                                   |
     |  ConfigurationCommand              |                                   |
     |  commandType: "update_full_config" |                                   |
     |  payloadJSON: FullConfigUpdatePayload                                  |
     |                                    |                                   |
     +--------------------------------->  |                                   |
                                          |                                   |
                        [NSPersistentCloudKitContainer auto-syncs]            |
                                          |                                   |
                                          +---------------------------------> |
                                                                              |
                                                    [Background Task wakes]   |
                                                    (every 15 min)            |
                                                              OR              |
                                                    [Push notification]       |
                                                                              |
                                                                              v
                                          |               [ChildBackgroundSyncService]
                                          |               checkForConfigurationUpdates()
                                                                              |
                                          |                                   v
                                                          [ChildConfigCommandProcessor]
                                          |               processCommand()
                                                                              |
                                          |                                   v
                                                          [AppScheduleService]
                                          |               applyRemoteConfiguration()
                                                                              |
                                          |                                   v
                                                          [ScreenTimeService]
                                          |               syncGoalConfigsToExtension()
                                                                              |
                                          |  [Command marked executed]        |
                                          |<----------------------------------|
                                                                              |
                                          |  [Updated configs synced back]    |
     |<-----------------------------------|<----------------------------------|
     |                                    |                                   |
[UI refreshes via                         |                                   |
 CloudKit notification]                   |                                   |
```

---

## 3. Implementation Components

### 3.1 New Files to Create

| File | Location | Purpose |
|------|----------|---------|
| `ParentAppEditSheet.swift` | `Views/ParentRemote/` | Full edit UI for parent |
| `ParentTimeWindowPicker.swift` | `Views/ParentRemote/Components/` | Time window editor |
| `ParentDailyLimitsPicker.swift` | `Views/ParentRemote/Components/` | Daily limits editor |
| `ParentStreakSettingsPicker.swift` | `Views/ParentRemote/Components/` | Streak editor |
| `ConfigSyncStatusView.swift` | `Views/ParentRemote/Components/` | Sync status indicator |
| `ChildConfigCommandProcessor.swift` | `Services/` | Command processor on child |
| `FullConfigUpdatePayload.swift` | `Models/` | Payload struct for commands |
| `MutableAppConfigDTO.swift` | `Models/` | Editable config DTO |

### 3.2 Files to Modify

| File | Changes |
|------|---------|
| `CloudKitSyncService.swift` | Add `sendFullConfigurationCommand()` method |
| `ChildBackgroundSyncService.swift` | Extend `checkForConfigurationUpdates()` for new command type |
| `ParentRemoteViewModel.swift` | Add edit state, `sendFullConfigUpdate()` method |
| `ParentAppDetailView.swift` | Add Edit button and sheet presentation |
| `AppScheduleService.swift` | Add `applyRemoteConfiguration()` method |

---

## 4. Payload Structure

### 4.1 FullConfigUpdatePayload

```swift
struct FullConfigUpdatePayload: Codable {
    // Command metadata
    let commandID: String
    let parentDeviceID: String
    let parentModifiedAt: Date
    let version: Int  // Optimistic locking

    // Target
    let logicalID: String
    let deviceID: String

    // Basic config
    var category: String
    var pointsPerMinute: Int
    var isEnabled: Bool
    var blockingEnabled: Bool

    // Full schedule
    var scheduleConfig: AppScheduleConfiguration?

    // Linked learning apps (for reward apps)
    var linkedLearningApps: [LinkedLearningApp]
    var unlockMode: UnlockMode

    // Streak settings
    var streakSettings: AppStreakSettings?
}
```

### 4.2 Existing Nested Types (Reused)

```swift
// AppScheduleConfiguration (already exists)
struct AppScheduleConfiguration: Codable {
    var allowedTimeWindow: AllowedTimeWindow
    var dailyTimeWindows: DailyTimeWindows
    var useAdvancedTimeWindowConfig: Bool
    var dailyLimits: DailyLimits
    var useAdvancedDayConfig: Bool
    var isEnabled: Bool
}

// LinkedLearningApp (already exists)
struct LinkedLearningApp: Codable {
    var logicalID: String
    var displayName: String
    var minutesRequired: Int
    var goalPeriod: GoalPeriod  // .daily or .weekly
    var rewardMinutesEarned: Int
}

// AppStreakSettings (already exists)
struct AppStreakSettings: Codable {
    var isEnabled: Bool
    var bonusValue: Int
    var bonusType: BonusType  // .percentage or .fixedMinutes
    var streakCycleDays: Int
}
```

---

## 5. Conflict Resolution Strategy

### 5.1 Default: Parent Wins

When parent and child edit the same config:
1. Parent's modification timestamp compared to child's
2. If parent's timestamp is newer, parent wins
3. Child's local changes are overwritten
4. Child syncs updated config back to confirm

### 5.2 Edge Cases

| Scenario | Resolution |
|----------|------------|
| Parent edits while child offline | Command queued; applied when child syncs |
| Child edits while command in flight | Parent command takes precedence |
| Multiple commands pending | Process in createdAt order |
| Command older than 7 days | Mark as expired, skip processing |

---

## 6. Implementation Phases

### Phase 1: Data Layer (Foundation)
1. Create `FullConfigUpdatePayload.swift`
2. Create `MutableAppConfigDTO.swift`
3. Extend `ConfigurationCommand` (add priority, retryCount if needed)

### Phase 2: CloudKit Commands
1. Add `sendFullConfigurationCommand()` to CloudKitSyncService
2. Create `ChildConfigCommandProcessor.swift`
3. Extend `checkForConfigurationUpdates()` in ChildBackgroundSyncService

### Phase 3: Parent UI
1. Create `ParentAppEditSheet.swift`
2. Create picker components (time window, daily limits, streak)
3. Add Edit button to `ParentAppDetailView.swift`
4. Add sync status indicator

### Phase 4: Child Processing
1. Add `applyRemoteConfiguration()` to AppScheduleService
2. Integrate with ScreenTimeService
3. Sync updated config back to CloudKit

### Phase 5: Real-time Updates
1. Add push notification for immediate sync
2. Implement polling fallback
3. Add confirmation feedback to parent UI

---

## 7. Apple Privacy Constraints

### What Parents CANNOT Do Remotely

1. **Select new apps to track** - FamilyActivityPicker requires device-local access
2. **View child's full app library** - Apple privacy restriction
3. **See app icons for untracked apps** - ApplicationToken is opaque
4. **Access Screen Time API directly** - Requires authorization on child device

### What This Means for UX

- Parent sees list of apps child has already configured
- Parent can only modify configurations for those apps
- "Add New App" must show message: "New apps can only be added from [child]'s device"
- Linked learning apps picker is limited to apps child has configured as Learning

---

## 8. Security Considerations

| Aspect | Implementation |
|--------|----------------|
| Verify pairing | Check parentDeviceID matches stored pairing context |
| Prevent spoofing | Commands only processed if from paired parent's zone |
| Rate limiting | Max 10 commands per minute per device |
| Audit trail | Store command history with timestamps |

---

## 9. Critical Files Reference

### Parent Device
- `Views/ParentRemote/ParentAppDetailView.swift` - Add Edit button (line ~91)
- `ViewModels/ParentRemoteViewModel.swift` - Add edit state management
- `Services/CloudKitSyncService.swift` - Add full command method (after line 206)

### Child Device
- `Services/ChildBackgroundSyncService.swift` - Extend command processing (line ~148)
- `Services/AppScheduleService.swift` - Add remote config application
- `Services/ScreenTimeService.swift` - Apply config changes

### Shared
- `Models/ConfigurationCommand.swift` - Command entity
- `Models/AppScheduleConfig.swift` - Schedule structures
- `Models/FullAppConfigDTO.swift` - Config DTO (add mutable version)

---

## 10. Testing Checklist

- [ ] Parent edits daily limits -> Child receives and applies
- [ ] Parent edits time windows -> Child restricts app access accordingly
- [ ] Parent toggles enabled -> Child shields/unshields app
- [ ] Parent edits streak settings -> Child bonus calculations update
- [ ] Child offline during command -> Command processed on reconnect
- [ ] Simultaneous parent/child edit -> Parent wins, child syncs back
- [ ] Command fails -> Retry up to 3 times, then mark failed
- [ ] Parent UI shows sync status (pending -> syncing -> confirmed)

---

## Appendix A: Existing Method Signatures

### CloudKitSyncService (to extend)
```swift
// Line 179 - Existing basic method
func sendConfigurationToChild(deviceID: String, configuration: AppConfiguration)

// Line 208 - Existing sync request
func requestChildSync(deviceID: String)

// To Add:
func sendFullConfigurationCommand(deviceID: String, config: FullConfigUpdatePayload)
```

### ChildBackgroundSyncService (to extend)
```swift
// Line 148 - Existing method to extend
func checkForConfigurationUpdates() async throws {
    // Currently only handles basic config updates
    // Need to add: "update_full_config" command type
}
```

### AppScheduleService (to extend)
```swift
// Existing: saveSchedule(_ config: AppScheduleConfiguration)
// To Add: applyRemoteConfiguration(_ payload: FullConfigUpdatePayload)
```
