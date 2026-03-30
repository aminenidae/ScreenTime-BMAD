# Streak Rewards Feature Implementation Plan (Per-App Configuration)

## Overview
Implement a per-app "Streak Rewards" feature that grants percentage-based bonus reward time when children hit daily streak milestones. Each reward app has its own independent streak configuration, making the UX more practical and less confusing than a global system.

## User Requirements
- **Bonus Type**: Percentage multiplier per app (e.g., +10% of earned time)
- **Per-App Configuration**: Each reward app has independent streak settings
- **Parent Control**: Toggle on/off + customize bonus percentage and milestones per app
- **Bonus Application**: Applied when milestones are reached (7, 14, 30, 60, 90 days)
- **Configuration Location**: Integrated into App Configuration Sheet (reward apps only)

## Key Design Decision: Per-App vs Global

**Previous Approach (Global)**:
- Single streak configuration in Settings tab
- Global "streak rule" (.anyGoal or .allGoals) applying to all learning apps
- Confusing UX: parents had to understand "any goal" vs "all goals" logic

**New Approach (Per-App)**:
- Each reward app has its own streak settings
- No confusing streak rules - each app tracks independently
- Settings integrated into App Configuration Sheet
- More intuitive: "Earn bonus time for YouTube by using Khan Academy daily"

---

## Implementation Steps

### 1. DATA MODEL UPDATES

#### 1.1 Add AppStreakSettings Model
**File: `ScreenTimeRewards/Models/StreakSettings.swift`** (MODIFY)

Add new struct for per-app settings (keep existing `StreakSettings` for migration):

```swift
/// Per-app streak configuration (embedded in AppScheduleConfiguration)
struct AppStreakSettings: Codable, Equatable, Hashable {
    var isEnabled: Bool = false
    var bonusPercentage: Int = 10  // 5, 10, 15, 20, 25
    var milestones: [Int] = [7, 14, 30]
    var earnedMilestones: Set<Int> = []

    mutating func setBonusPercentage(_ percentage: Int) {
        let validPercentages = [5, 10, 15, 20, 25]
        if validPercentages.contains(percentage) {
            self.bonusPercentage = percentage
        }
    }

    static let defaultSettings = AppStreakSettings(
        isEnabled: false,
        bonusPercentage: 10,
        milestones: [7, 14, 30],
        earnedMilestones: []
    )
}
```

**Note**: No `streakRule` field - per-app streaks don't need "any goal" vs "all goals" logic.

#### 1.2 Update AppScheduleConfiguration
**File: `ScreenTimeRewards/Models/AppScheduleConfig.swift`** (MODIFY)

Add streak settings field to `AppScheduleConfiguration` struct (line 432):

```swift
// Streak configuration (for reward apps only)
var streakSettings: AppStreakSettings?
```

Update initializer to include:
```swift
streakSettings: AppStreakSettings? = nil
```

Update `defaultReward` static method:
```swift
static func defaultReward(logicalID: String) -> AppScheduleConfiguration {
    AppScheduleConfiguration(
        // ... existing parameters ...
        streakSettings: .defaultSettings  // Enable by default for new reward apps
    )
}
```

#### 1.3 Update CoreData Schema
**File: `ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`** (MODIFY)

Add attribute to `StreakRecord` entity:
```xml
<attribute name="appLogicalID" optional="YES" attributeType="String"/>
```

Add fetch indexes for performance:
```xml
<fetchIndex name="byAppLogicalID">
    <fetchIndexElement property="appLogicalID" type="Binary" order="ascending"/>
</fetchIndex>
<fetchIndex name="byChildDeviceIDAndApp">
    <fetchIndexElement property="childDeviceID" type="Binary" order="ascending"/>
    <fetchIndexElement property="appLogicalID" type="Binary" order="ascending"/>
</fetchIndex>
```

**File: `ScreenTimeRewards/CoreData/StreakRecord+CoreDataProperties.swift`** (MODIFY)

Add property (line 27):
```swift
@NSManaged public var appLogicalID: String?
```

---

### 2. SERVICE LAYER REFACTORING

#### 2.1 Refactor StreakService for Per-App Support
**File: `ScreenTimeRewards/Services/StreakService.swift`** (MAJOR REFACTOR)

**Remove**:
- `@Published var settings: StreakSettings` (global settings)
- `@Published var currentStreakRecord: StreakRecord?` (single record)

**Add**:
```swift
// Per-app streak records cache (key: appLogicalID)
@Published private(set) var streakRecords: [String: StreakRecord] = [:]
```

**Update method signatures**:

```swift
// Check and update streak for a specific app
func checkAndUpdateStreak(
    goalsCompleted: Bool,
    for childDeviceID: String,
    appLogicalID: String,
    settings: AppStreakSettings
)

// Get or create streak record for specific app
func getOrCreateStreakRecord(
    for childDeviceID: String,
    appLogicalID: String
) -> StreakRecord

// Check milestone for specific app
func checkMilestoneAchievement(
    for appLogicalID: String,
    settings: AppStreakSettings
) -> Int?

// Grant bonus for specific app
func grantBonusMinutes(_ minutes: Int, for appLogicalID: String)

// Get total bonus for specific app
func getTotalBonusMinutes(for appLogicalID: String) -> Int

// Check if bonus should be applied
func shouldApplyBonus(
    for milestone: Int,
    appLogicalID: String,
    settings: AppStreakSettings
) -> Bool

// Mark milestone as earned
func markMilestoneEarned(
    _ milestone: Int,
    for appLogicalID: String,
    settings: AppStreakSettings
)
```

**Add helper methods**:

```swift
// Load all streak records for a child
func loadStreaksForChild(childDeviceID: String)

// Get aggregate stats across all apps (for child dashboard)
func getAggregateStreak(for childDeviceID: String) -> (current: Int, longest: Int, isAtRisk: Bool)

// Get next milestone for a specific streak value
func getNextMilestone(for currentStreak: Int, settings: AppStreakSettings) -> Int?

// Calculate progress to next milestone
func progressToNextMilestone(current: Int, settings: AppStreakSettings) -> Double
```

**Update bonus storage**:
- Per-app keys: `"streak_bonus_{appLogicalID}"`

**Update CoreData fetch**:
```swift
request.predicate = NSPredicate(
    format: "childDeviceID == %@ AND appLogicalID == %@",
    childDeviceID,
    appLogicalID
)
```

#### 2.2 Update BlockingCoordinator
**File: `ScreenTimeRewards/Services/BlockingCoordinator.swift`** (MODIFY)

Replace `checkAndUpdateStreak()` method (lines 632-668):

```swift
private func checkAndUpdateStreak() {
    guard !currentRewardTokens.isEmpty else { return }

    let streakService = StreakService.shared
    let deviceID = DeviceModeManager.shared.deviceID

    // Check streak for EACH reward app independently
    for token in currentRewardTokens {
        guard let logicalID = screenTimeService?.getLogicalID(for: token),
              let config = scheduleService.getSchedule(for: logicalID),
              let streakSettings = config.streakSettings,
              streakSettings.isEnabled else {
            continue
        }

        // Check if this app's learning goals are met
        let learningCheck = checkLearningGoal(logicalID: logicalID)
        let isGoalMet = learningCheck.isGoalMet

        // Update streak for this specific app
        streakService.checkAndUpdateStreak(
            goalsCompleted: isGoalMet,
            for: deviceID,
            appLogicalID: logicalID,
            settings: streakSettings
        )

        // Check for milestones
        if let milestone = streakService.checkMilestoneAchievement(
            for: logicalID,
            settings: streakSettings
        ) {
            if streakService.shouldApplyBonus(
                for: milestone,
                appLogicalID: logicalID,
                settings: streakSettings
            ) {
                let earnedMinutes = learningCheck.rewardMinutesEarned
                let bonus = streakService.calculateBonusMinutes(
                    earnedMinutes: earnedMinutes,
                    bonusPercentage: streakSettings.bonusPercentage
                )

                if bonus > 0 {
                    streakService.grantBonusMinutes(bonus, for: logicalID)
                    streakService.markMilestoneEarned(
                        milestone,
                        for: logicalID,
                        settings: streakSettings
                    )

                    // Post notification for milestone achievement
                    streakService.notifyMilestoneAchieved(
                        milestone: milestone,
                        bonusMinutes: bonus,
                        appLogicalID: logicalID
                    )

                    print("[BlockingCoordinator] 🏆 Streak Milestone \(milestone) for \(logicalID)! Granted \(bonus) bonus minutes.")
                }
            }
        }
    }
}
```

---

### 3. UI UPDATES

#### 3.1 Add Streak Section to AppConfigurationSheet
**File: `ScreenTimeRewards/Views/AppConfig/AppConfigurationSheet.swift`** (MODIFY)

Add after Linked Apps section (around line 128):

```swift
// Streak Rewards Section (reward apps only)
if appType == .reward {
    Rectangle()
        .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
        .frame(height: 1)

    StreakSettingsPicker(
        streakSettings: $localConfig.streakSettings
    )
    .id("config_streak_section")
    .tutorialTarget("config_streak")
}
```

#### 3.2 Create StreakSettingsPicker Component
**File: `ScreenTimeRewards/Views/AppConfig/Components/StreakSettingsPicker.swift`** (NEW)

Create collapsible card component matching AppConfigurationSheet style:

```swift
import SwiftUI

struct StreakSettingsPicker: View {
    @Binding var streakSettings: AppStreakSettings?
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded: Bool = false

    private let availableMilestones = [7, 14, 30, 60, 90]
    private let bonusOptions = [5, 10, 15, 20, 25]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with toggle
            headerSection

            if isExpanded, let settings = streakSettings {
                Divider()

                // Bonus percentage picker
                bonusSection(settings: settings)

                // Milestones selection
                milestonesSection(settings: settings)
            }
        }
        .padding(16)
        .appCard(colorScheme)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("STREAK REWARDS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { streakSettings?.isEnabled ?? false },
                    set: { enabled in
                        if streakSettings == nil {
                            streakSettings = .defaultSettings
                        }
                        streakSettings?.isEnabled = enabled
                        isExpanded = enabled
                    }
                ))
                .tint(AppTheme.vibrantTeal)
            }

            Text("Grant bonus time when daily learning goals are met consistently")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }

    private func bonusSection(settings: AppStreakSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BONUS REWARD")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Picker("Bonus Percentage", selection: Binding(
                get: { settings.bonusPercentage },
                set: { streakSettings?.setBonusPercentage($0) }
            )) {
                ForEach(bonusOptions, id: \.self) { percent in
                    Text("+\(percent)%").tag(percent)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }

    private func milestonesSection(settings: AppStreakSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MILESTONES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            ForEach(availableMilestones, id: \.self) { days in
                Toggle(isOn: Binding(
                    get: { settings.milestones.contains(days) },
                    set: { isSelected in
                        if isSelected {
                            if !(streakSettings?.milestones.contains(days) ?? false) {
                                streakSettings?.milestones.append(days)
                                streakSettings?.milestones.sort()
                            }
                        } else {
                            streakSettings?.milestones.removeAll { $0 == days }
                        }
                    }
                )) {
                    HStack {
                        Text("\(days) Days")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        if settings.earnedMilestones.contains(days) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(AppTheme.sunnyYellow)
                                .font(.caption)
                        }
                    }
                }
                .tint(AppTheme.vibrantTeal)

                if days != availableMilestones.last {
                    Divider()
                }
            }
        }
    }
}
```

#### 3.3 Update ChildStreakCard for Multi-App Display
**File: `ScreenTimeRewards/Views/ChildMode/Components/ChildStreakCard.swift`** (MODIFY)

Update to support multiple app streaks:

```swift
struct ChildStreakCard: View {
    let aggregateStreak: (current: Int, longest: Int, isAtRisk: Bool)
    let appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)]
    let nextMilestone: Int?
    let progress: Double
    let hasAnyStreaksEnabled: Bool

    @State private var showDetailView = false

    var body: some View {
        if hasAnyStreaksEnabled && aggregateStreak.current > 0 {
            VStack(spacing: 16) {
                headerSection
                streakDisplay
                milestoneProgress

                // Show detail button if multiple apps have streaks
                if appStreaks.count > 1 {
                    detailButton
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .sheet(isPresented: $showDetailView) {
                StreakDetailView(appStreaks: appStreaks)
            }
        }
    }

    private var detailButton: some View {
        Button(action: { showDetailView = true }) {
            HStack {
                Text("View All \(appStreaks.count) Streaks")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .foregroundColor(AppTheme.vibrantTeal)
        }
    }

    // ... existing streak display code ...
}
```

#### 3.4 Create StreakDetailView Component
**File: `ScreenTimeRewards/Views/ChildMode/Components/StreakDetailView.swift`** (NEW)

Simple list showing all app streaks:

```swift
import SwiftUI

struct StreakDetailView: View {
    let appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)]
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(appStreaks, id: \.appName) { streak in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(streak.appName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            if streak.isAtRisk {
                                Text("At Risk")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(AppTheme.sunnyYellow)
                            Text("\(streak.currentStreak)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("All Streaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

#### 3.5 Remove StreakSettingsView from Settings Tab
**File: `ScreenTimeRewards/Views/SettingsTabView.swift`** (MODIFY)

Remove:
- "REWARDS" section containing `streakRewardsRow` (lines 63-66)
- `@State private var showingStreakSettings` variable
- `.sheet(isPresented: $showingStreakSettings)` presentation

---

### 4. DATA MIGRATION

#### 4.1 Create Migration Service
**File: `ScreenTimeRewards/Services/StreakMigrationService.swift`** (NEW)

```swift
import Foundation
import CoreData

@MainActor
class StreakMigrationService {
    static let shared = StreakMigrationService()
    private let migrationKey = "streak_migration_v1_completed"
    private let userDefaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    func performMigrationIfNeeded() async {
        guard !(userDefaults?.bool(forKey: migrationKey) ?? false) else {
            print("[StreakMigration] Migration already completed")
            return
        }

        print("[StreakMigration] Starting migration from global to per-app streaks")

        // 1. Load global streak settings (if any)
        let globalSettings = loadGlobalSettings()

        // 2. Get all reward apps
        let scheduleService = AppScheduleService.shared
        let rewardApps = scheduleService.schedules.values.filter { config in
            !config.linkedLearningApps.isEmpty
        }

        print("[StreakMigration] Found \(rewardApps.count) reward apps to migrate")

        // 3. Migrate global settings to each reward app
        for config in rewardApps {
            var updatedConfig = config

            if globalSettings.isEnabled {
                updatedConfig.streakSettings = AppStreakSettings(
                    isEnabled: globalSettings.isEnabled,
                    bonusPercentage: globalSettings.bonusPercentage,
                    milestones: globalSettings.milestones,
                    earnedMilestones: globalSettings.earnedMilestones
                )
            } else {
                updatedConfig.streakSettings = .defaultSettings
            }

            try? scheduleService.saveSchedule(updatedConfig)
            print("[StreakMigration] Migrated settings for app: \(config.id)")
        }

        // 4. Migrate existing StreakRecord to first reward app
        if let firstRewardApp = rewardApps.first {
            migrateExistingStreakRecord(to: firstRewardApp.id)
        }

        // 5. Mark migration complete
        userDefaults?.set(true, forKey: migrationKey)
        print("[StreakMigration] Migration completed successfully")
    }

    private func loadGlobalSettings() -> StreakSettings {
        guard let data = userDefaults?.data(forKey: "streak_settings"),
              let settings = try? JSONDecoder().decode(StreakSettings.self, from: data) else {
            return StreakSettings()
        }
        return settings
    }

    private func migrateExistingStreakRecord(to appLogicalID: String) {
        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        let request: NSFetchRequest<StreakRecord> = StreakRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "childDeviceID == %@ AND appLogicalID == nil",
            deviceID
        )
        request.fetchLimit = 1

        do {
            if let existingRecord = try context.fetch(request).first {
                existingRecord.appLogicalID = appLogicalID
                try context.save()
                print("[StreakMigration] Migrated existing streak record to app: \(appLogicalID)")
            }
        } catch {
            print("[StreakMigration] Error migrating streak record: \(error)")
        }
    }
}
```

#### 4.2 Trigger Migration on App Launch
**File: `ScreenTimeRewards/ScreenTimeRewardsApp.swift`** (MODIFY)

Add to initialization (after session setup):

```swift
init() {
    // ... existing initialization ...

    // Perform streak migration if needed
    Task { @MainActor in
        await StreakMigrationService.shared.performMigrationIfNeeded()
    }
}
```

---

### 5. VIEW MODEL UPDATES

#### 5.1 Update ChildDashboardView
**File: `ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift`** (MODIFY)

Update streak card instantiation (around lines 72-79):

```swift
// Streak Card - show aggregate across all apps
let streakService = StreakService.shared
let deviceID = DeviceModeManager.shared.deviceID
let aggregateStreak = streakService.getAggregateStreak(for: deviceID)

// Get individual app streaks for detail view
let appStreaks = viewModel.rewardSnapshots.compactMap { snapshot -> (String, Int, Bool)? in
    guard let record = streakService.streakRecords[snapshot.logicalID] else { return nil }
    return (snapshot.displayName, Int(record.currentStreak), record.isAtRisk)
}

ChildStreakCard(
    aggregateStreak: aggregateStreak,
    appStreaks: appStreaks,
    nextMilestone: streakService.getNextMilestone(for: aggregateStreak.current),
    progress: streakService.progressToNextMilestone(current: aggregateStreak.current),
    hasAnyStreaksEnabled: !streakService.streakRecords.isEmpty
)
```

#### 5.2 Update AppUsageViewModel
**File: `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`** (MODIFY)

Update `totalStreakBonusMinutes` calculation (around line 100):

```swift
// Calculate total streak bonus across ALL apps
var totalStreakBonusMinutes: Int {
    let streakService = StreakService.shared
    return currentRewardTokens.reduce(0) { total, token in
        guard let logicalID = resolvedLogicalID(for: token) else { return total }
        return total + streakService.getTotalBonusMinutes(for: logicalID)
    }
}
```

---

## Files Summary

### Files to Modify (12)
1. `ScreenTimeRewards/Models/StreakSettings.swift` - Add AppStreakSettings
2. `ScreenTimeRewards/Models/AppScheduleConfig.swift` - Add streakSettings field
3. `ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents` - Add appLogicalID
4. `ScreenTimeRewards/CoreData/StreakRecord+CoreDataProperties.swift` - Add appLogicalID property
5. `ScreenTimeRewards/Services/StreakService.swift` - Major refactor for per-app support
6. `ScreenTimeRewards/Services/BlockingCoordinator.swift` - Update checkAndUpdateStreak
7. `ScreenTimeRewards/Views/AppConfig/AppConfigurationSheet.swift` - Add streak section
8. `ScreenTimeRewards/Views/ChildMode/Components/ChildStreakCard.swift` - Support multi-app
9. `ScreenTimeRewards/Views/SettingsTabView.swift` - Remove streak settings row
10. `ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift` - Update streak card usage
11. `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` - Update bonus calculation
12. `ScreenTimeRewards/ScreenTimeRewardsApp.swift` - Add migration trigger

### Files to Create (3)
1. `ScreenTimeRewards/Views/AppConfig/Components/StreakSettingsPicker.swift` - New UI component
2. `ScreenTimeRewards/Services/StreakMigrationService.swift` - Migration logic
3. `ScreenTimeRewards/Views/ChildMode/Components/StreakDetailView.swift` - Detail view

### Files to Delete (After Migration Period)
1. `ScreenTimeRewards/Views/Settings/StreakSettingsView.swift` - Global settings UI (deprecated)

---

## Implementation Order

1. **Phase 1**: Data models (Steps 1.1-1.3) - Foundation
2. **Phase 2**: Migration service (Steps 4.1-4.2) - Before service refactoring
3. **Phase 3**: Service refactoring (Steps 2.1-2.2) - Core logic
4. **Phase 4**: UI components (Steps 3.1-3.4) - User interface
5. **Phase 5**: Remove global UI (Step 3.5) - Cleanup
6. **Phase 6**: View model updates (Steps 5.1-5.2) - Integration
7. **Phase 7**: Testing and validation - Verification

---

## Key Design Decisions

1. **Per-App Only**: Streak settings only for reward apps (where they make sense)
2. **No Streak Rule**: Removed `.anyGoal` vs `.allGoals` - each app tracks independently
3. **Automatic Migration**: Zero user intervention, preserves existing data
4. **Aggregate Display**: Child sees highest streak by default, can view details
5. **Backward Compatible**: CoreData appLogicalID is optional, existing records have nil
6. **Per-App Bonuses**: Separate bonus tracking per app using prefixed UserDefaults keys

---

## Migration Strategy

1. On first launch after update, StreakMigrationService runs automatically
2. Global StreakSettings (if exist) copied to all existing reward apps
3. Existing StreakRecord (appLogicalID = nil) assigned to first reward app
4. Migration flag set in UserDefaults to prevent re-running
5. User's streak progress preserved seamlessly - no data loss

---

## Data Persistence

- **AppStreakSettings**: Embedded in AppScheduleConfiguration (JSON in UserDefaults)
- **StreakRecord**: Core Data entity with appLogicalID field
  - One record per (childDeviceID, appLogicalID) pair
  - Properties: `currentStreak`, `longestStreak`, `lastActivityDate`, `appLogicalID`
- **Bonus Minutes**: Per-app keys in UserDefaults: `"streak_bonus_{appLogicalID}"`

---

## Edge Cases Handled

1. **Duplicate Bonuses**: Track in `earnedMilestones` set per app, check before applying
2. **Milestone Changes**: Don't reset earned milestones, new milestones check against set
3. **Mid-Streak Enable**: No retroactive bonuses, tracking starts when enabled
4. **Multi-Device**: Separate `StreakRecord` per child device ID and app
5. **Settings Changes**: Preserve streak count when changing per-app settings
6. **Migration Safety**: Only runs once, idempotent operation
7. **No Reward Apps**: Migration handles gracefully (no-op if no reward apps exist)

---

## UX Improvements Over Global System

1. **Clearer Configuration**: Parents configure streaks where they configure the app
2. **No Confusing Rules**: Eliminated "any goal" vs "all goals" confusion
3. **App-Specific Motivation**: Different reward apps can have different streak incentives
4. **Better Discovery**: Streak settings in app config sheet (parents already there)
5. **Flexible Rewards**: Can enable streaks for some reward apps, not others

---

## Critical Files for Implementation

- **ScreenTimeRewards/Services/StreakService.swift** - Core business logic requiring complete refactor
- **ScreenTimeRewards/Models/AppScheduleConfig.swift** - Data model where streak settings embedded
- **ScreenTimeRewards/Services/BlockingCoordinator.swift** - Streak checking logic per-app
- **ScreenTimeRewards/Views/AppConfig/AppConfigurationSheet.swift** - UI entry point
- **ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents** - Schema changes

## Implementation Notes (2025-12-25)
- **Parent UI**: Implemented custom Stepper controls for Cycle Days and Bonus Value. Added dynamic summary footer that displays estimated reward minutes.
- **Child UI**: Added 'potential bonus' footer message to `AppStreakCard`.
- **Logic**: Refactored to retroactive bonus calculation (Daily Reward × Streak Length).
