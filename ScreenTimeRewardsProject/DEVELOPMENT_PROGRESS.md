# ScreenTime Rewards App - Development Progress Documentation

**Last Updated:** 2025-10-17
**iOS Version:** 16.6+
**Xcode Version:** 15.0+
**Project Status:** Phase 2 - Core Features Implementation Complete

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Implemented Features](#implemented-features)
4. [File Structure](#file-structure)
5. [Key Technical Decisions](#key-technical-decisions)
6. [API & Framework Usage](#api--framework-usage)
7. [Testing Guide](#testing-guide)
8. [Known Issues & Limitations](#known-issues--limitations)
9. [Next Steps](#next-steps)
10. [Code Examples](#code-examples)

---

## Project Overview

### Concept
A parental control app that gamifies screen time:
- **Learning Apps**: Earn points when used (e.g., educational apps)
- **Reward Apps**: Cost points to access (e.g., games, social media)
- Parents configure apps, children earn/spend points through usage

### Current Phase
**Phase 2: Core Functionality**
- ✅ Two-tab interface (Learning/Rewards)
- ✅ App selection and categorization
- ✅ Points system (earning and spending)
- ✅ App blocking (shielding) for reward apps
- ✅ Usage time tracking
- ✅ Real-time monitoring

---

## Architecture

### Design Pattern
**MVVM (Model-View-ViewModel)**
- **Models**: `AppUsage`, `AppCategory`
- **Views**: `MainTabView`, `LearningTabView`, `RewardsTabView`, `CategoryAssignmentView`
- **ViewModels**: `AppUsageViewModel`
- **Services**: `ScreenTimeService`

### Data Flow
```
User Action → View → ViewModel → Service → Apple Frameworks
                ↓                    ↓
            UI Update ← Notifications ← Framework Callbacks
```

### Apple Frameworks Used
1. **FamilyControls**: App selection picker, authorization
2. **ManagedSettings**: App blocking (shielding)
3. **DeviceActivity**: Usage monitoring, event tracking
4. **SwiftUI**: Modern UI framework
5. **Combine**: Reactive data flow

---

## Implemented Features

### 1. Two-Tab Interface

**MainTabView.swift**
- Tab 1: Learning (Blue theme, book icon)
- Tab 2: Rewards (Orange theme, game controller icon)
- Entry point for the entire app

**Purpose**: Clear separation between earning and spending mechanics

---

### 2. Learning Tab

**File**: `LearningTabView.swift`

**Features**:
- Display total points earned from learning
- Show learning time formatted as HH:MM:SS
- List all selected learning apps with:
  - App name/icon (iOS 15.2+)
  - Points earned per minute
- **Buttons**:
  - "Select Learning Apps" / "Add More Apps" - Opens app picker
  - "View All Learning Apps" - Opens CategoryAssignmentView to see all apps
- Auto-categorization: All apps → `AppCategory.learning`

**Key Code Locations**:
```
LearningTabView.swift:25-36  → Total points display
LearningTabView.swift:44-78  → App list
LearningTabView.swift:97-112 → View All button
LearningTabView.swift:113-126 → CategoryAssignmentView integration
```

---

### 3. Rewards Tab

**File**: `RewardsTabView.swift`

**Features**:
- List all selected reward apps with:
  - App name/icon (iOS 15.2+)
  - Points cost per minute
- **Buttons**:
  - "Select Reward Apps" / "Add More Apps" - Opens app picker
  - "View All Reward Apps" - Opens CategoryAssignmentView
  - "Unlock All Reward Apps" - Removes shields from all reward apps
- Auto-categorization: All apps → `AppCategory.reward`
- **Automatic Shield**: Blocks apps immediately after "Save & Monitor"

**Key Code Locations**:
```
RewardsTabView.swift:24-59  → App list
RewardsTabView.swift:78-93  → View All button
RewardsTabView.swift:96-111 → Unlock button
RewardsTabView.swift:117-127 → Shield trigger on save
```

---

### 4. CategoryAssignmentView - The Monitoring Dashboard

**File**: `CategoryAssignmentView.swift`

**Purpose**:
This is the **ONLY view** where app names and icons are displayed properly due to iOS privacy restrictions. It serves as the main monitoring dashboard for parents.

**Features**:
- ✅ App icons and names (via `Label(token)`)
- ✅ Usage time display (e.g., "2h 15m", "45m", "30s")
- ✅ Points configuration with steppers
- ✅ Context-aware labels:
  - Learning: "Earn per minute"
  - Reward: "Cost per minute"
- ✅ Different point ranges:
  - Learning: 5-500 points, increment by 5
  - Reward: 50-1000 points, increment by 10
- ✅ Auto-categorization via `fixedCategory` parameter
- ✅ Category summary section
- ✅ Reward points summary section

**Key Code Locations**:
```
CategoryAssignmentView.swift:10-11  → Parameters (fixedCategory, usageTimes)
CategoryAssignmentView.swift:64-73  → Usage time display
CategoryAssignmentView.swift:75-92  → Points configuration
CategoryAssignmentView.swift:193-200 → Point ranges
CategoryAssignmentView.swift:231-244 → formatUsageTime()
```

**Auto-Categorization Logic**:
```swift
// Learning Tab passes:
fixedCategory: .learning

// Rewards Tab passes:
fixedCategory: .reward

// If fixedCategory is provided:
- Category picker is hidden
- All apps auto-assigned to that category
- User only sets points, not category
```

---

### 5. App Selection & Authorization

**File**: `AppUsageViewModel.swift`

**Flow**:
1. User taps "Select Apps" button
2. `requestAuthorizationAndOpenPicker()` called
3. Request FamilyControls authorization
4. Open `FamilyActivityPicker`
5. User selects apps
6. `onChange` detects selection
7. Open `CategoryAssignmentView` automatically

**Features**:
- ✅ Authorization request before picker
- ✅ Timeout detection (15 seconds)
- ✅ Retry mechanism
- ✅ Error handling
- ✅ Authorization status logging (DEBUG)

**Key Code Locations**:
```
AppUsageViewModel.swift:320-369 → requestAuthorizationAndOpenPicker()
AppUsageViewModel.swift:372-404 → Picker timeout logic
AppUsageViewModel.swift:419-440 → Retry mechanism
```

---

### 6. App Blocking (Shield) System

**File**: `ScreenTimeService.swift`

**How It Works**:
1. Parent selects reward apps in Rewards Tab
2. Sets points cost in CategoryAssignmentView
3. Taps "Save & Monitor"
4. `blockRewardApps()` immediately shields apps
5. Apps show shield screen when user tries to open them

**Shield Lifecycle**:
```
Block:   blockRewardApps(tokens) → ManagedSettings.shield.applications = tokens
Unblock: unlockRewardApps(tokens) → Remove tokens from shield set
Clear:   clearAllShields() → ManagedSettings.shield.applications = nil
```

**Important Research Finding**:
⚠️ **Shield Staleness**: If a reward app is already running when shield is applied, the user must **close and reopen** the app for the shield to appear. This is an Apple limitation, not a bug.

**Key Code Locations**:
```
ScreenTimeService.swift:609-628 → blockRewardApps()
ScreenTimeService.swift:631-658 → unblockRewardApps()
ScreenTimeService.swift:691-708 → clearAllShields()
ScreenTimeService.swift:603-606 → Shield tracking (currentlyShielded)
AppUsageViewModel.swift:530-545 → blockRewardApps() wrapper
AppUsageViewModel.swift:548-563 → unlockRewardApps() wrapper
```

**Shield Status Tracking**:
```swift
private var currentlyShielded: Set<ApplicationToken> = []
```

---

### 7. Usage Time Tracking & Monitoring

**Files**: `ScreenTimeService.swift`, `AppUsageViewModel.swift`

**Architecture**:
```
DeviceActivity Framework
    ↓
DeviceActivityMonitor (Extension)
    ↓
Darwin Notifications (IPC)
    ↓
ScreenTimeService.handleEventThresholdReached()
    ↓
recordUsage() → Updates AppUsage
    ↓
NotificationCenter.usageDidChangeNotification
    ↓
AppUsageViewModel.refreshData()
    ↓
UI Updates
```

**Monitoring Configuration**:
```swift
defaultThreshold = DateComponents(minute: 1)  // Record every 1 minute
```

**Recording Interval vs. Time Cap**:
- ⚠️ **NOT A CAP**: 1 minute is the recording interval
- Usage accumulates continuously
- Every 1 minute of usage triggers an event
- Example: 5 minutes of use = 5 events = 5 minutes recorded

**Critical Shield-Aware Recording**:
```swift
// ScreenTimeService.swift:836-842
if currentlyShielded.contains(application.token) {
    // Skip recording - this is shield time, not real usage
    continue
}
```

This prevents counting time when user is seeing the shield screen.

**Key Code Locations**:
```
ScreenTimeService.swift:76          → defaultThreshold = 1 minute
ScreenTimeService.swift:180-333     → configureMonitoring()
ScreenTimeService.swift:814-885     → recordUsage()
ScreenTimeService.swift:919-945     → handleEventThresholdReached()
ScreenTimeService.swift:887-893     → seconds() - converts threshold to duration
AppUsageViewModel.swift:529-586     → getUsageTimes() - maps tokens to usage
```

---

### 8. Points System

**Points Configuration**:
| Category | Minimum | Maximum | Step | Label |
|----------|---------|---------|------|-------|
| Learning | 5 | 500 | 5 | "Earn per minute:" |
| Reward | 50 | 1000 | 10 | "Cost per minute:" |

**Points Calculation**:
```swift
// Learning apps EARN points
earnedPoints = (usageTime / 60) * pointsPerMinute

// Reward apps COST points (future: will deduct from balance)
costPerMinute = configuredPoints
```

**Key Code Locations**:
```
CategoryAssignmentView.swift:193-200 → pointsRange()
CategoryAssignmentView.swift:184-191 → getDefaultRewardPoints()
CategoryAssignmentView.swift:202-209 → pointsLabel()
```

---

### 9. Usage Time Display

**File**: `CategoryAssignmentView.swift`

**Features**:
- Clock icon (blue) + formatted time
- Only shows when usage > 0
- Format logic:
  - Hours + minutes: "2h 15m"
  - Minutes only: "45m"
  - Seconds only: "30s"

**Implementation**:
```swift
// CategoryAssignmentView.swift:64-73
if let usageTime = usageTimes[token], usageTime > 0 {
    HStack {
        Image(systemName: "clock.fill")
            .font(.caption)
            .foregroundColor(.blue)
        Text("Used: \(formatUsageTime(usageTime))")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

**Data Flow**:
```
ScreenTimeService.appUsages (storage)
    ↓
AppUsageViewModel.getUsageTimes() (mapping)
    ↓
CategoryAssignmentView.usageTimes (display)
```

**Key Code Locations**:
```
AppUsageViewModel.swift:529-586     → getUsageTimes()
CategoryAssignmentView.swift:11     → usageTimes parameter
CategoryAssignmentView.swift:64-73  → Display logic
CategoryAssignmentView.swift:231-244 → formatUsageTime()
```

---

## File Structure

### Core Files

```
ScreenTimeRewardsProject/
├── ScreenTimeRewards/
│   ├── ScreenTimeRewardsApp.swift          # App entry point
│   ├── Info.plist                          # App configuration
│   ├── ScreenTimeRewards.entitlements      # Capabilities
│   │
│   ├── Models/
│   │   └── AppUsage.swift                  # Data model for app usage
│   │
│   ├── ViewModels/
│   │   └── AppUsageViewModel.swift         # MVVM ViewModel
│   │
│   ├── Views/
│   │   ├── MainTabView.swift               # Root tab container
│   │   ├── LearningTabView.swift           # Learning apps tab
│   │   ├── RewardsTabView.swift            # Reward apps tab
│   │   ├── CategoryAssignmentView.swift    # App configuration & monitoring
│   │   └── AppUsageView.swift              # Legacy view (for testing)
│   │
│   ├── Services/
│   │   ├── ScreenTimeService.swift         # Core service layer
│   │   └── Persistence.swift               # CoreData persistence
│   │
│   ├── Shared/
│   │   └── ScreenTimeNotifications.swift   # Darwin notification names
│   │
│   └── Assets.xcassets/                    # App icons and images
│
├── ScreenTimeActivityExtension/
│   ├── DeviceActivityMonitorExtension.swift # Background monitoring
│   ├── Info.plist
│   └── ScreenTimeActivityExtension.entitlements
│
└── ScreenTimeRewards.xcodeproj/
```

---

## Key Technical Decisions

### 1. Why Two-Tab Architecture?

**Decision**: Separate Learning and Rewards into distinct tabs

**Reasoning**:
- Clear mental model for children (earn vs. spend)
- Simplified UX (no manual categorization needed)
- Auto-categorization reduces parent setup time
- Visual distinction (colors, icons, terminology)

**Implementation**:
- `fixedCategory` parameter in CategoryAssignmentView
- Tab-specific button text ("Earn per minute" vs. "Cost per minute")
- Different point ranges per tab

---

### 2. Why CategoryAssignmentView as Main Dashboard?

**Decision**: Make CategoryAssignmentView accessible via "View All" buttons

**Reasoning**:
- **iOS Privacy Restriction**: App names/icons only visible via `Label(token)` in sheets
- Cannot display app names in regular lists reliably
- CategoryAssignmentView already has `Label(token)` implementation
- Dual purpose: Setup + Monitoring dashboard

**Alternative Considered**: Build separate monitoring view
- ❌ Would duplicate `Label(token)` code
- ❌ More maintenance overhead
- ✅ CategoryAssignmentView already works perfectly

---

### 3. Shield-Aware Recording

**Decision**: Skip recording usage when app is shielded

**Reasoning**:
- Shield screen time ≠ actual app usage
- Would inflate usage statistics
- Would give unearned points to children

**Implementation**:
```swift
if currentlyShielded.contains(application.token) {
    print("🛑 SKIPPING - shield time, not real usage")
    continue
}
```

**Location**: `ScreenTimeService.swift:836-842`

---

### 4. 1-Minute Recording Interval

**Decision**: Use 1-minute threshold for all apps

**Reasoning**:
- Granular enough for accurate tracking
- Not too frequent (performance concern)
- Matches common time-based UX patterns
- Can be customized per category later if needed

**Note**: This is NOT a cap - usage accumulates indefinitely

---

### 5. ApplicationToken as Key

**Decision**: Use `ApplicationToken` as dictionary key instead of bundle IDs

**Reasoning**:
- Bundle IDs may be `nil` due to iOS privacy
- `ApplicationToken` always available from picker
- Privacy-preserving by design
- Required for `ManagedSettings` and `DeviceActivity` APIs

**Limitation**: Tokens are not `Codable`, so persistence is limited
- Current solution: Store by token hash for session
- Future: Need better persistence strategy

---

## API & Framework Usage

### FamilyControls Framework

**Purpose**: App selection and authorization

**Key APIs**:
```swift
// Authorization
AuthorizationCenter.shared.requestAuthorization(for: .individual)
AuthorizationCenter.shared.authorizationStatus

// Picker
.familyActivityPicker(isPresented: $isPresented, selection: $selection)

// Token to UI
Label(token)  // iOS 15.2+ only
```

**Authorization States**:
- `0` = `.notDetermined` - Not asked yet
- `1` = `.denied` - User declined
- `2` = `.approved` - User granted access

**Files Using This**:
- `ScreenTimeService.swift:455-496` - Authorization
- `LearningTabView.swift:120-126` - Picker integration
- `RewardsTabView.swift:111-127` - Picker integration
- `CategoryAssignmentView.swift:36-38` - Label display

---

### ManagedSettings Framework

**Purpose**: App blocking (shielding)

**Key APIs**:
```swift
let store = ManagedSettingsStore()

// Block apps
store.shield.applications = Set<ApplicationToken>

// Unblock apps
store.shield.applications = nil  // Or remove specific tokens
```

**Shield Behavior**:
- Shows fullscreen shield overlay when user opens blocked app
- Persists across app restarts
- Requires app relaunch if already running (staleness)

**Files Using This**:
- `ScreenTimeService.swift:600-708` - Shield management
- `AppUsageViewModel.swift:530-572` - Shield wrappers

---

### DeviceActivity Framework

**Purpose**: Background usage monitoring

**Key APIs**:
```swift
let center = DeviceActivityCenter()
let monitor = DeviceActivityMonitor()

// Start monitoring
center.startMonitoring(
    activityName,
    during: schedule,
    events: [eventName: event]
)

// Event structure
DeviceActivityEvent(
    applications: Set<ApplicationToken>,
    threshold: DateComponents(minute: 1)
)

// Schedule (repeating daily)
DeviceActivitySchedule(
    intervalStart: DateComponents(hour: 0, minute: 0),
    intervalEnd: DateComponents(hour: 23, minute: 59),
    repeats: true
)
```

**Extension Callbacks**:
```swift
// In DeviceActivityMonitor subclass:
override func eventDidReachThreshold(
    _ event: DeviceActivityEvent.Name,
    activity: DeviceActivityName
) {
    // Send Darwin notification to main app
}
```

**Files Using This**:
- `ScreenTimeService.swift:498-563` - Monitoring setup
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` - Extension callbacks
- `ScreenTimeService.swift:344-368` - Darwin notification registration

---

### Darwin Notifications (IPC)

**Purpose**: Communication between app and extension

**Why Needed**: Extensions run in separate process, need IPC

**Notification Names**:
```swift
// ScreenTimeNotifications.swift
static let eventDidReachThreshold = "com.screentimerewards.eventDidReach"
static let intervalDidStart = "com.screentimerewards.intervalDidStart"
static let intervalDidEnd = "com.screentimerewards.intervalDidEnd"
// ... etc
```

**Flow**:
```
Extension: eventDidReachThreshold()
    ↓
Extension: Post Darwin notification
    ↓
Main App: CFNotificationCenter receives
    ↓
Main App: handleDarwinNotification()
    ↓
Main App: handleEventThresholdReached()
    ↓
Main App: recordUsage()
```

**Shared Data via App Group**:
```swift
// App Group: "group.com.screentimerewards.shared"

// Extension writes:
UserDefaults(suiteName: appGroupIdentifier)?.set(eventName, forKey: "lastEvent")

// Main app reads:
let eventRaw = sharedDefaults.string(forKey: "lastEvent")
```

**Files Using This**:
- `ScreenTimeService.swift:344-368` - Registration
- `ScreenTimeService.swift:370-451` - Handling
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` - Sending

---

## Testing Guide

### Pre-Testing Setup

1. **Device Requirements**:
   - Physical device OR simulator (iOS 16.6+)
   - iPad recommended (better screen real estate)

2. **Xcode Configuration**:
   - Set development team in Signing & Capabilities
   - Verify entitlements include:
     - Family Controls
     - App Groups: `group.com.screentimerewards.shared`

3. **Build & Deploy**:
   ```bash
   xcodebuild -project ScreenTimeRewards.xcodeproj \
              -scheme ScreenTimeRewards \
              -configuration Debug \
              -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
              build
   ```

---

### Test Case 1: Learning Apps Setup

**Objective**: Verify learning app selection and auto-categorization

**Steps**:
1. Launch app → Learning tab
2. Tap "Select Learning Apps"
3. Grant authorization when prompted
4. Select 2-3 educational apps (e.g., Books, Calculator)
5. Tap "Done"
6. **Verify**: CategoryAssignmentView opens automatically
7. **Verify**: All apps show as "Learning" category
8. **Verify**: Points default to 5, can adjust 5-500 by 5
9. Set points (e.g., Books = 10, Calculator = 15)
10. Tap "Save & Monitor"
11. **Verify**: Returns to Learning tab
12. **Verify**: Apps listed with icons (iOS 15.2+) and points

**Expected Debug Logs**:
```
[AppUsageViewModel] Requesting FamilyControls authorization
[AppUsageViewModel] ✅ Authorization request completed
[ScreenTimeService] Configuring monitoring with 3 applications
[ScreenTimeService] Category: Learning (user-assigned ✓)
[ScreenTimeService] ✅ Recorded usage for 0 apps (no usage yet)
```

---

### Test Case 2: Reward Apps Setup & Shield

**Objective**: Verify reward app blocking immediately after setup

**Steps**:
1. Launch app → Rewards tab
2. Tap "Select Reward Apps"
3. Select 1-2 apps (e.g., Games, Social media)
4. Tap "Done" → CategoryAssignmentView opens
5. **Verify**: All apps auto-categorized as "Reward"
6. **Verify**: Points default to 50, can adjust 50-1000 by 10
7. Set points (e.g., Instagram = 100)
8. Tap "Save & Monitor"
9. **Verify**: Returns to Rewards tab
10. **Verify**: Apps listed with points

**Shield Test**:
11. Exit app (home button)
12. Try to open a reward app
13. **Expected**: Shield screen appears immediately
14. **If shield doesn't appear**: Close app completely and reopen (shield staleness)

**Expected Debug Logs**:
```
[AppUsageViewModel] 🔒 Blocking 2 reward apps
[ScreenTimeService] 🔒 Blocking 2 reward apps
[ScreenTimeService] ✅ Shield applied to 2 apps in 0.XX seconds
[ScreenTimeService] ⚠️ IMPORTANT: If apps are already running, user must close and reopen them
```

---

### Test Case 3: Usage Time Tracking

**Objective**: Verify time accumulates beyond 1 minute

**Steps**:
1. Setup learning apps (Test Case 1)
2. Exit app
3. Use a learning app for **5+ minutes** continuously
4. Return to app → Learning tab
5. Tap "View All Learning Apps"
6. **Verify**: CategoryAssignmentView shows usage time
7. **Verify**: Time shows ~5 minutes (e.g., "5m" or "4m 55s")
8. **Verify**: Clock icon appears before time

**Monitoring Interval Check**:
- Events should fire every ~1 minute
- Usage should accumulate: 1m → 2m → 3m → 4m → 5m
- NOT capped at 1 minute

**Expected Debug Logs**:
```
[ScreenTimeService] Event threshold reached: usage.learning
[ScreenTimeService] Recording usage with duration: 60 seconds
[ScreenTimeService] ✅ Recording usage for Books - app is unblocked
[ScreenTimeService] ✅ Recorded usage for 1 apps
[ScreenTimeService] Notifying usage change to observers
```

**Repeat 5 times for 5 minutes of usage**

---

### Test Case 4: View All Apps (Monitoring Dashboard)

**Objective**: Verify CategoryAssignmentView as monitoring tool

**Steps**:
1. Setup both learning and reward apps
2. Use apps for a few minutes
3. Learning tab → Tap "View All Learning Apps"
4. **Verify**:
   - All learning apps displayed
   - App names and icons visible
   - Usage times shown (if any usage)
   - Points configuration intact
5. Tap "Cancel" to close
6. Rewards tab → Tap "View All Reward Apps"
7. **Verify**:
   - All reward apps displayed
   - App names and icons visible
   - Usage times shown (if any)
   - Points configuration intact

**Purpose Test**:
- Confirm this is the ONLY reliable way to see app names/icons
- Confirm it works as a monitoring dashboard
- Confirm real-time data updates

---

### Test Case 5: Unlock Reward Apps

**Objective**: Verify shield removal

**Steps**:
1. Setup reward apps with shield active (Test Case 2)
2. Verify apps are blocked (shield screen appears)
3. Return to app → Rewards tab
4. Tap "Unlock All Reward Apps"
5. Exit app
6. Close any running reward apps completely
7. Reopen a reward app
8. **Expected**: App opens normally (no shield)

**Expected Debug Logs**:
```
[AppUsageViewModel] 🔓 Unlocking 2 reward apps
[ScreenTimeService] 🔓 Unblocking 2 reward apps
[ScreenTimeService] ✅ Shield removed from 2 apps
[ScreenTimeService] Currently shielded: 0 apps
```

---

### Test Case 6: Points Calculation

**Objective**: Verify points are calculated correctly

**Steps**:
1. Setup learning app: Books = 10 points/minute
2. Use Books for exactly 5 minutes
3. Return to app
4. **Expected**: Books shows 50 points earned (5 × 10)
5. Learning tab total points: 50

**Calculation**:
```
earnedPoints = (usageTime / 60) * pointsPerMinute
             = (300 seconds / 60) * 10
             = 5 * 10
             = 50 points
```

**Check In**:
- `AppUsageView` (old view) → Total Reward Points
- Learning tab → Total Points Earned
- CategoryAssignmentView → Reward Points Summary

---

### Test Case 7: iPad Layout

**Objective**: Verify full-width layout on iPad

**Steps**:
1. Run on iPad simulator or device
2. **Verify**: App fills entire screen width
3. **Verify**: NOT constrained to narrow left column

**Fix Applied**:
```swift
.navigationViewStyle(.stack)  // Forces full-width
```

**Files with fix**:
- `MainTabView.swift` (if needed)
- `LearningTabView.swift:119`
- `RewardsTabView.swift:102`
- `AppUsageView.swift:185`

---

## Known Issues & Limitations

### 1. Shield Staleness

**Issue**: If a reward app is already running when shield is applied, the shield doesn't appear until app is relaunched.

**Cause**: iOS framework limitation

**Workaround**: Instruct user to:
1. Swipe up to see multitasking view
2. Swipe up on the reward app to close completely
3. Reopen the app → Shield appears

**Code Location**: `ScreenTimeService.swift:622`
```swift
print("⚠️ IMPORTANT: If apps are already running, user must close and reopen them")
```

**Research Finding**: Documented Apple limitation, not a bug in our code

---

### 2. ApplicationToken Persistence

**Issue**: `ApplicationToken` is not `Codable`, cannot be saved to disk easily

**Current Solution**: Store by token hash for current session
```swift
let tokenKey = String(entry.key.hashValue)
```

**Limitation**: Token mapping lost on app restart

**Future Solution Needed**:
- Use App Group + NSKeyedArchiver
- Or rebuild token mapping from FamilyActivitySelection on launch
- Or store parallel mapping: bundleID → category

**Code Location**: `AppUsageViewModel.swift:122-126`

---

### 3. App Names/Icons Visibility

**Issue**: App names and icons only reliably visible via `Label(token)` in sheets

**Cause**: iOS privacy restrictions

**Current Solution**: Use CategoryAssignmentView as monitoring dashboard

**Limitation**: Cannot build custom list views with app names

**Workaround**: "View All Apps" buttons in each tab

**Code Location**: `CategoryAssignmentView.swift:36-38`

---

### 4. Bundle Identifier May Be Nil

**Issue**: `application.bundleIdentifier` may be `nil` for privacy

**Impact**: Cannot reliably use bundle IDs for tracking

**Solution**: Use `ApplicationToken` as primary key, fallback to derived keys

**Code Location**: `ScreenTimeService.swift:849`
```swift
let storageKey = bundleIdentifier ?? "app.\(displayName.lowercased())"
```

---

### 5. No Real-Time Usage Updates

**Issue**: Usage data updates on 1-minute interval, not real-time

**Cause**: DeviceActivity threshold-based events

**Impact**: UI shows usage with up to 1-minute delay

**Future**: Could reduce threshold to 30 seconds, but may impact battery

---

### 6. Learning Apps Have No Time Limits (By Design)

**Status**: NOT A BUG - This is intentional

**Reasoning**: Learning apps should be unlimited to encourage education

**Future**: May add optional limits if parent requests

---

### 7. Learning App Usage Misattribution

**Status**: Fix implemented (2025-10-18) – needs on-device regression run with redacted app names.

**Issue**: After running one learning app, the Learning tab sometimes shows usage minutes and points under a different app.

**Root Cause**: Privacy restrictions hide bundle IDs and display names, so the monitoring pipeline derived storage keys like `Unknown App 0`. When `FamilyActivitySelection` reorders tokens (common as DeviceActivity restarts), those keys pointed to the wrong app and the UI rows swapped data even though category totals stayed correct.

**Resolution**: Persist usage by a stable `ApplicationToken`-based storage key. `ScreenTimeService` now archives each token into a deterministic key when configuring monitor events and records usage against that key. `AppUsageViewModel.getUsageTimes()` queries the service by token instead of guessing via bundle/display name heuristics. This keeps per-app minutes/points aligned with the actual app that generated them.

**Next Validation**: Re-run the Flowkey/Sololearn test on-device to confirm the per-app cards stay in sync. Note that `xcodebuild build -project ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards -destination 'generic/platform=iOS'` currently fails in the sandbox because Xcode cannot write to `DerivedData`; no code issues surfaced in compiler output.

**Code Locations**:
- `ScreenTimeService.swift` (token `storageKey`, `recordUsage`, new `getUsage(for:)` APIs)
- `AppUsageViewModel.swift` (`getUsageTimes()` token lookup)

---

## Next Steps

### Immediate Priorities

#### 1. Points Balance System
- [ ] Add global points balance
- [ ] Deduct points when reward apps are used
- [ ] Show balance in UI
- [ ] Block reward apps when balance = 0

#### 2. Time Limits for Reward Apps
- [ ] Allow parent to set daily time limit per reward app
- [ ] Block when limit reached
- [ ] Reset at midnight

#### 3. Parent PIN Protection
- [ ] Add PIN entry screen
- [ ] Lock settings behind PIN
- [ ] Allow child to view stats only

#### 4. Notifications
- [ ] Notify parent when child earns/spends points
- [ ] Notify child when reward app unlocked
- [ ] Daily summary notifications

---

### Phase 3: Advanced Features

#### 1. Child Mode vs. Parent Mode
- Parent mode: Full access, configuration
- Child mode: View stats, request unlocks

#### 2. Goals & Achievements
- Set learning goals (e.g., 60 minutes/day)
- Unlock bonus points for achieving goals
- Visual progress indicators

#### 3. App Usage Analytics
- Charts showing usage over time
- Most-used apps
- Points earned/spent history
- Weekly/monthly reports

#### 4. Multiple Children Support
- Separate profiles per child
- Individual points balances
- Family-wide settings

---

### Technical Debt

#### 1. Token Persistence
**Priority**: High
**Issue**: ApplicationToken not persisted
**Solution**: Implement proper token storage strategy

#### 2. CoreData Integration
**Priority**: Medium
**Issue**: Persistence.swift exists but unused
**Solution**: Integrate CoreData for long-term storage

#### 3. Unit Tests
**Priority**: High
**Issue**: No unit tests for ViewModel/Service
**Solution**: Add test coverage for business logic

#### 4. Error Handling
**Priority**: Medium
**Issue**: Limited user-facing error messages
**Solution**: Improve error messages and recovery flows

#### 5. Logging System
**Priority**: Low
**Issue**: DEBUG logs everywhere, no production logging
**Solution**: Implement proper logging framework

---

## Code Examples

### Example 1: Adding a New Tab

```swift
// 1. Create new view file: NewTabView.swift
import SwiftUI
import FamilyControls

struct NewTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()

    var body: some View {
        NavigationView {
            VStack {
                // Your content here
            }
            .navigationTitle("New Tab")
        }
        .navigationViewStyle(.stack)
    }
}

// 2. Add to MainTabView.swift
TabView {
    // ... existing tabs ...

    NewTabView()
        .tabItem {
            Label("New", systemImage: "star.fill")
        }
}
```

---

### Example 2: Custom Point Calculation

```swift
// In ScreenTimeService.swift or new service

func calculateCustomPoints(
    usage: AppUsage,
    multiplier: Double = 1.0
) -> Int {
    let basePoints = (usage.totalTime / 60) * Double(usage.rewardPoints)
    let bonusPoints = basePoints * multiplier
    return Int(bonusPoints)
}

// Usage:
let points = calculateCustomPoints(usage: appUsage, multiplier: 1.5) // 1.5x weekend bonus
```

---

### Example 3: Add New Notification Type

```swift
// 1. Add to ScreenTimeNotifications.swift
extension Notification.Name {
    static let pointsBalanceChanged = Notification.Name("ScreenTimeService.pointsBalanceChanged")
}

// 2. Post notification in ScreenTimeService.swift
private func updatePointsBalance(_ newBalance: Int) {
    NotificationCenter.default.post(
        name: .pointsBalanceChanged,
        object: nil,
        userInfo: ["balance": newBalance]
    )
}

// 3. Observe in ViewModel
NotificationCenter.default
    .publisher(for: .pointsBalanceChanged)
    .receive(on: RunLoop.main)
    .sink { notification in
        if let balance = notification.userInfo?["balance"] as? Int {
            self.pointsBalance = balance
        }
    }
    .store(in: &cancellables)
```

---

### Example 4: Query Usage Data

```swift
// Get total learning time today
let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())

let todayLearningTime = appUsages
    .filter { $0.category == .learning }
    .filter { $0.lastAccess >= today }
    .reduce(0) { $0 + $1.totalTime }

// Get top 3 most-used apps
let topApps = appUsages
    .sorted { $0.totalTime > $1.totalTime }
    .prefix(3)

// Get apps with usage > 1 hour
let highUsageApps = appUsages
    .filter { $0.totalTime > 3600 }
```

---

### Example 5: Custom Shield Configuration

```swift
// Shield specific apps with custom settings
let store = ManagedSettingsStore()

// Shield apps during specific time
let settings = ManagedSettingsStore()
settings.shield.applications = rewardTokens
settings.shield.applicationCategories = .all(except: learningCategories)

// Note: Time-based shielding requires additional DeviceActivity schedule
```

---

## Debugging Tips

### Enable Verbose Logging

All debug logs are wrapped in `#if DEBUG`:
```swift
#if DEBUG
print("[ScreenTimeService] Your debug message here")
#endif
```

**To view logs**:
1. Run from Xcode
2. Open Console app (Cmd+Space → Console)
3. Filter by "ScreenTimeService" or "AppUsageViewModel"

---

### Check Authorization Status

```swift
// In any view
Button("Check Auth") {
    let status = AuthorizationCenter.shared.authorizationStatus
    print("Status: \(status.rawValue)")
    print("0=notDetermined, 1=denied, 2=approved")
}
```

---

### Verify Shield Status

```swift
// In AppUsageView or add button to test
Button("Shield Status") {
    let status = viewModel.getShieldStatus()
    print("Blocked: \(status.blocked)")
    print("Accessible: \(status.accessible)")
}
```

---

### Monitor Extension Events

```swift
// In ScreenTimeService.swift - Already implemented
// Watch console for:
[ScreenTimeService] Event threshold reached: usage.learning
[ScreenTimeService] Recording usage with duration: 60 seconds
```

---

### Test Without Real Apps (DEBUG Only)

```swift
#if DEBUG
// In AppUsageView, add test button:
Button("Test Data") {
    viewModel.configureWithTestApplications()
}

// This creates fake usage data:
// - Books: 1 hour learning
// - Calculator: 10 minutes learning
// - Music: 30 minutes reward
#endif
```

---

## Glossary

**ApplicationToken**: Privacy-preserving identifier for an app, provided by FamilyControls framework

**Shield**: Fullscreen overlay that blocks access to an app (ManagedSettings)

**DeviceActivity**: Framework for monitoring app usage in background

**Darwin Notification**: System-level IPC mechanism for process communication

**App Group**: Shared container for data between app and extension

**Threshold**: Time interval that triggers a DeviceActivity event

**Monitoring Interval**: Same as threshold - time between usage recordings

**ViewModel**: Layer between View and Service in MVVM architecture

**FamilyActivitySelection**: Object containing apps selected from picker

**Session**: Single period of app usage from start to stop

**Usage**: Total accumulated time across all sessions

---

## Contact & Contribution

### Development Team
- Lead Developer: [Name]
- iOS Specialist: [Name]
- UX Designer: [Name]

### Code Review Process
1. Create feature branch from `main`
2. Implement feature with tests
3. Submit PR with description
4. Wait for review + approval
5. Merge to `main`

### Coding Standards
- Swift 5.0+
- SwiftUI for all new views
- MVVM architecture
- Meaningful variable names
- Comments for complex logic
- `#if DEBUG` for all debug logs

---

## Appendix: File-by-File Reference

### ScreenTimeRewardsApp.swift
**Purpose**: App entry point
**Key Code**: Sets `MainTabView` as root view
**Lines**: 13-20

### MainTabView.swift
**Purpose**: Tab container
**Tabs**: Learning, Rewards
**Key Code**: TabView with two tabs
**Lines**: 8-23

### LearningTabView.swift
**Purpose**: Learning apps interface
**Key Features**: Points earned, app list, View All button
**Integration**: CategoryAssignmentView with `fixedCategory: .learning`
**Lines**: 5-133

### RewardsTabView.swift
**Purpose**: Reward apps interface
**Key Features**: App list, View All, Unlock buttons
**Integration**: CategoryAssignmentView with `fixedCategory: .reward`, immediate shield
**Lines**: 5-146

### CategoryAssignmentView.swift
**Purpose**: App configuration + monitoring dashboard
**Key Features**: Auto-categorization, usage time, points config
**Critical**: Only place where app names/icons reliably display
**Lines**: 5-245

### AppUsageViewModel.swift
**Purpose**: MVVM ViewModel
**Responsibilities**: UI state, authorization, picker logic, data mapping
**Key Methods**: `getUsageTimes()`, `blockRewardApps()`, `unlockRewardApps()`
**Lines**: 7-668

### ScreenTimeService.swift
**Purpose**: Core service layer
**Responsibilities**: Monitoring, shielding, usage recording, notifications
**Key Methods**: `configureMonitoring()`, `blockRewardApps()`, `recordUsage()`
**Lines**: 9-1153

### AppUsage.swift
**Purpose**: Data model
**Properties**: bundleID, name, category, totalTime, sessions, rewardPoints
**Methods**: `recordUsage()`, `earnedRewardPoints` computed property

### DeviceActivityMonitorExtension.swift
**Purpose**: Background monitoring extension
**Runs**: In separate process
**Communication**: Darwin notifications + App Group

### ScreenTimeNotifications.swift
**Purpose**: Darwin notification name constants
**Usage**: Shared between app and extension

---

**End of Documentation**

*This documentation is a living document. Update as features are added or architecture changes.*
