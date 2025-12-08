# Per-App Schedule and Time Limit Configuration

## Overview

Replace challenge-level scheduling with per-app schedule and time limit controls. When a parent taps an app card (learning or reward), it toggles selection AND opens a configuration sheet.

## Requirements Summary

- **Per-app configuration** for both learning and reward apps
- **Tap behavior**: Toggle selection + open config sheet
- **Allowed hours**: Start time - end time picker
- **Daily limits**: Different limits per day (weekday/weekend default, with advanced per-day option)
- **Remove**: Challenge-level schedule step from builder

## UX Decisions

### Multi-App Selection Flow
When parent selects multiple apps from the picker:
1. Apps appear in list marked **"⚠️ Not configured"**
2. Parent must tap each app to open config sheet and set limits
3. **Validation**: Cannot proceed to next step until ALL apps are configured
4. Visual indicator shows configured vs unconfigured state

### Default Behavior by App Type
| App Type | Default Limits | Rationale |
|----------|---------------|-----------|
| **Learning** | No defaults - REQUIRED to set | Parent must consciously decide learning goals |
| **Reward** | Stricter defaults suggested | Reward apps should be more restricted by default |

### Card States
- **Unconfigured**: Gray border, "⚠️ Tap to configure" subtitle
- **Configured**: Blue border, summary text (e.g., "2h weekdays, 3h weekends")

---

## 1. Data Model

### New File: `Models/AppScheduleConfig.swift`

```swift
struct AllowedTimeWindow: Codable, Equatable {
    var startHour: Int        // 0-23
    var startMinute: Int      // 0-59
    var endHour: Int          // 0-23
    var endMinute: Int        // 0-59

    static let fullDay = AllowedTimeWindow(startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)
    var isFullDay: Bool { startHour == 0 && startMinute == 0 && endHour == 23 && endMinute == 59 }
}

struct DailyLimits: Codable, Equatable {
    var monday: Int
    var tuesday: Int
    var wednesday: Int
    var thursday: Int
    var friday: Int
    var saturday: Int
    var sunday: Int

    init(weekdayMinutes: Int, weekendMinutes: Int) {
        monday = weekdayMinutes; tuesday = weekdayMinutes
        wednesday = weekdayMinutes; thursday = weekdayMinutes; friday = weekdayMinutes
        saturday = weekendMinutes; sunday = weekendMinutes
    }

    func limit(for weekday: Int) -> Int // 1=Sun, 7=Sat
    var isWeekdayWeekendPattern: Bool
    var weekdayLimit: Int { monday }
    var weekendLimit: Int { saturday }

    static let unlimited = DailyLimits(weekdayMinutes: 1440, weekendMinutes: 1440)
}

struct AppScheduleConfiguration: Codable, Equatable, Identifiable {
    let id: String  // logicalID
    var allowedTimeWindow: AllowedTimeWindow
    var dailyLimits: DailyLimits
    var isEnabled: Bool
    var useAdvancedDayConfig: Bool  // false = weekday/weekend mode
}
```

### CoreData: Add `AppSchedule` Entity

| Attribute | Type |
|-----------|------|
| scheduleID | String |
| logicalID | String |
| deviceID | String |
| allowedStartHour/Minute | Int16 |
| allowedEndHour/Minute | Int16 |
| mondayLimit - sundayLimit | Int16 (7 attrs) |
| isEnabled | Boolean |
| useAdvancedDayConfig | Boolean |
| lastModified | Date |

---

## 2. UI Components

### New: `Views/AppConfig/AppConfigurationSheet.swift`

Sheet presented on app card tap:

1. **Header**: App icon + name + category badge
2. **Allowed Hours Section**:
   - Toggle: "Full Day Access" (default ON)
   - When OFF: Start/End time pickers
3. **Daily Limits Section**:
   - Default: Weekday stepper + Weekend stepper
   - "Advanced Settings" toggle
   - When ON: 7 individual day steppers
   - Range: 0-480 min, 5-min increments
4. **Enable Toggle**: Master on/off
5. **Save/Cancel buttons**

### New: `Views/AppConfig/Components/`
- `TimeWindowPicker.swift`
- `DailyLimitsPicker.swift`

### Modify: `ChallengeBuilderAppSelectionRow.swift`

Add properties:
```swift
var configuration: AppScheduleConfiguration?
var onConfigure: (() -> Void)?
var isConfigured: Bool { configuration != nil }
```

Changes:
- Tap → toggle + call `onConfigure`
- **Unconfigured state**: Gray border, "⚠️ Tap to configure" subtitle
- **Configured state**: Blue border, summary text (e.g., "2h weekdays, 3h weekends"), gear icon

---

## 3. Service Layer

### New: `Services/AppScheduleService.swift`

```swift
@MainActor
class AppScheduleService: ObservableObject {
    static let shared = AppScheduleService()
    @Published private(set) var schedules: [String: AppScheduleConfiguration] = [:]

    func loadSchedules() async
    func saveSchedule(_ config: AppScheduleConfiguration) async throws
    func deleteSchedule(for logicalID: String) async throws
    func getSchedule(for logicalID: String) -> AppScheduleConfiguration?
    func isAppCurrentlyAllowed(_ logicalID: String) -> Bool
    func remainingDailyLimit(for logicalID: String, usedMinutes: Int) -> Int
}
```

### Modify: `ScreenTimeService.swift`

Add:
- `enforceAppSchedules()` - Check all apps against schedules
- `startScheduleEnforcementTimer()` - Run every minute
- Block via `managedSettingsStore.shield.applications`

### Modify: `DeviceActivityMonitorExtension.swift`

Read schedule from shared UserDefaults keys:
- `schedule_<logicalID>_dailyLimit`
- `schedule_<logicalID>_windowStart`
- `schedule_<logicalID>_windowEnd`

---

## 4. Files to Remove/Modify

### Remove:
- `ScheduleStepView.swift` (or repurpose)
- `.schedule` case from `ChallengeBuilderStep` enum
- Schedule struct usage from `ChallengeBuilderData.swift`

### Modify:
| File | Change |
|------|--------|
| `LearningAppsStepView.swift` | Add config sheet state, pass config to rows |
| `RewardAppsStepView.swift` | Same |
| `ChallengeBuilderFlowView.swift` | Remove schedule step |
| `AppUsageViewModel.swift` | Add scheduleConfig to snapshots |

---

## 5. Enforcement Strategy

### Time Window (allowed hours)
Use `DeviceActivitySchedule` to block OUTSIDE allowed window.

### Daily Limits
Use `DeviceActivityEvent` thresholds per app.

### Shield Control
```swift
// Block
managedSettingsStore.shield.applications?.insert(token)
// Unblock
managedSettingsStore.shield.applications?.remove(token)
```

---

## 6. Implementation Order

| Phase | Tasks |
|-------|-------|
| **1. Data** | AppScheduleConfig.swift, CoreData entity, AppScheduleService |
| **2. UI** | TimeWindowPicker, DailyLimitsPicker, AppConfigurationSheet |
| **3. Integration** | Update app selection views, modify row component, add configured/unconfigured states |
| **4. Validation** | Block "Next" button until all selected apps are configured |
| **5. Removal** | Remove challenge schedule step and related code |
| **6. Enforcement** | ScreenTimeService + extension updates |
| **7. Polish** | Config summaries, edge cases, testing |

---

## Critical Files

| File | Action |
|------|--------|
| `Models/AppScheduleConfig.swift` | CREATE |
| `Services/AppScheduleService.swift` | CREATE |
| `Views/AppConfig/AppConfigurationSheet.swift` | CREATE |
| `Views/AppConfig/Components/TimeWindowPicker.swift` | CREATE |
| `Views/AppConfig/Components/DailyLimitsPicker.swift` | CREATE |
| `ChallengeBuilderAppSelectionRow.swift` | MODIFY |
| `LearningAppsStepView.swift` | MODIFY |
| `RewardAppsStepView.swift` | MODIFY |
| `ScreenTimeService.swift` | MODIFY |
| `DeviceActivityMonitorExtension.swift` | MODIFY |
| `ScheduleStepView.swift` | REMOVE/DEPRECATE |
| `ChallengeBuilderFlowView.swift` | MODIFY (remove schedule step) |
