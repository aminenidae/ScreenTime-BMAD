# Usage Time Tracking Issue - Investigation & Fix

**Issue ID**: TRACK-001
**Date Created**: 2025-11-17
**Status**: 🆘 CRITICAL FAILURE - ARCHITECTURE FIX INSUFFICIENT
**Priority**: BLOCKER - FUNDAMENTAL API LIMITATION DISCOVERED

---

## Problem Summary

### 🆘🆘 CRITICAL FAILURE: Midnight Schedule Still Broken (2025-11-17 POST-FIX)

**BLOCKING**: After implementing ALL 5 parts of the architecture fix, threshold timing is STILL broken and NEW critical issues discovered!

**Test Results (After Midnight Schedule Implementation)**:
- **Setup**: Deleted app, cleaned build, reinstalled with all architectural fixes deployed
- **Action**: Ran ONE learning app for exactly **7 minutes** (measured with stopwatch)
- **Expected Thresholds**: Fire at 1, 2, 3, 4, 5, 6, 7 minutes
- **Actual Results**:
  - 60s threshold: Fired after **~1:00** ✓ APPROXIMATELY CORRECT
  - 120s threshold: Fired after **~4:00 min** ❌ 100% LATE!
  - 180s threshold: Fired after **~7:00 min** ❌ 133% LATE!
  - Never got to 4th, 5th, 6th, 7th thresholds

**UI Shows THREE DIFFERENT VALUES**:
- **Challenge Progress**: 60% (6/10m) = **6 minutes**
- **"Your Progress" card**: **6 minutes** (matches challenge)
- **"Learning Apps" widget**: **3 min today**
- **Log shows**: 180s = **3 minutes**

**New Critical Issues Discovered**:

1. **🚨 Monitoring restarts are STILL happening** (not fixed by Part 1)
   ```
   [ScreenTimeService] 🔁 restartMonitoring() called
   [ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: manual
   ```
   - Restarts at: 03:20:48, 03:21:50, 03:24:50
   - Something is STILL calling `restartMonitoring()` every few minutes
   - Source of restarts is unknown (no logging)

2. **🚨 Double threshold fires** (each threshold fires TWICE)
   ```
   [ChallengeService] After: currentValue=1, timestamp=03:19:01
   [ChallengeService] After: currentValue=2, timestamp=03:19:01  ← Same timestamp!
   ```
   - Primary AND secondary monitors both fire thresholds
   - Causes double-counting in challenge progress
   - This explains "6 minutes" in challenge (should be 3)

3. **🚨 Mid-day monitoring start creates partial interval**
   - Schedule: 00:00:00 → 23:59:59 (midnight to midnight)
   - But monitoring started at 03:16:50
   - iOS creates interval: 03:16:50 → 23:59:59 (NOT full day!)
   - Thresholds (60s, 120s, 180s) are relative to 03:16:50, NOT midnight
   - Any usage before 03:16:50 is NOT tracked

4. **🚨 Threshold timing STILL wrong despite midnight schedule**
   - Expected: Threshold at 2 minutes = 03:18:50
   - Actual: Threshold at 4 minutes = 03:21:50
   - 2-minute delay suggests interval is being recreated

**Impact**:
- 🔴 App is COMPLETELY UNUSABLE for production
- Time-based tracking is fundamentally broken
- Double-counting makes challenge progress meaningless
- UI shows 3 different values (total confusion)
- Midnight schedule fix did NOT solve the problem

---

## 2025-11-17 - 20 Minute Run (Post-Fix) - Findings & Next Steps

**Observed (log ~05:08:44 UTC)**:
- Only the **first 60s** of real usage persisted; `cumulativeExpectedUsage` kept resetting back to 60s after each restart.
- After the first threshold, **all subsequent thresholds (usage.app.0/1/2/3/4/5)** fired at the **same timestamp**, producing duplicate Challenge increments without any new usage.
- Every threshold fire triggered **`restartMonitoring(reason: "threshold_progression", force: true)`**, creating a tight **restart loop**: stop → regenerate → restart → intervalDidEnd/Start → bursts of thresholds → restart again. This keeps resetting the DeviceActivity interval/counter, so usage never accumulates past 1 minute.
- Deduplication only filtered some of the burst; multiple “1-minute” increments still landed at the same time.
- Stale reconciliation logs showed expected 300–420s vs persisted 60s, then reset back to 60s—evidence the counter is being reset by the restart loop.

**Working theory**:
- The forced restart on **threshold progression** is resetting DeviceActivity’s interval-relative counters, causing immediate re-fires and preventing cumulative growth beyond the first minute. Instant restarts also appear to generate immediate intervalDidEnd/Start and redundant event firings.

**Plan**:
1) **Disable the forced restart on threshold progression** (ScreenTimeService.swift ~line 2227) and rerun a 4–7 minute single-app test to confirm thresholds at 120s/180s/240s fire on schedule without bursts.
2) If thresholds stop firing, reintroduce a **much slower refresh** (e.g., only midnight or manual Settings action), but avoid immediate restart after every threshold.
3) Optionally add a **one-line log** in the extension when the monitored app goes foreground/background to correlate actual usage time with threshold fires during validation.

---

## 2025-11-17 - 4 Minute Validation (Restart Disabled) ✅ FIXED

**Change applied**: Removed forced `restartMonitoring` on threshold progression (ScreenTimeService.swift ~2227) so DeviceActivity interval stays stable.

**Results (single learning app, ~4 minutes)**:
- Thresholds fired at 60s, 120s, 180s, 240s in order (no bursts/duplicates).
- Persisted usage matched expected cumulative time and points: 60s → 120s → 180s → 240s (10pts → 40pts).
- Challenge increments matched usage (no double fires), and AppUsageViewModel snapshots reflected the same totals.
- No restart loops or interval resets observed.

**Status**: The core timing/accumulation issue is resolved with the restart removal.

**Next**:
- Keep the restart removal in place; only restart manually or on safe triggers (e.g., midnight transition).
- If further tuning is needed, consider a slower/manual refresh path instead of immediate restarts after thresholds.

---

## 2025-11-17 - 10 Minute Validation (Restart Disabled) ⚠️ STOPS AT 6 MIN

**Observed**:
- Thresholds fired cleanly up to 60s, 120s, 180s, 240s, 300s, 360s (6 minutes, 60 pts). Tracking stopped afterward.
- No restart loops or duplicates; accumulation was correct until it halted.

**Cause**:
- We only schedule `maxScheduledIncrementsPerApp = 6` thresholds per app. With 60s increments, we run out of scheduled events at 6 minutes, so DeviceActivity has no further thresholds to fire without a restart.

**Fix applied**:
- Increased `maxScheduledIncrementsPerApp` to **120** (~2 hours of 60s increments) to keep a long runway without restarting (ScreenTimeService.swift).

**Next**:
- Re-run a 10–15 minute test to confirm thresholds continue beyond 6 minutes with the higher scheduling window.
- If longer sessions are needed, adjust scheduling to cover the desired maximum daily usage window without forcing restarts.

---

## 2025-11-17 - 10 Minute Validation (Restart Disabled, Expanded Scheduling) ✅ PASSED

**Change applied**: Increased `maxScheduledIncrementsPerApp` to 120 (~2 hours at 60s increments) so DeviceActivity never runs out of thresholds mid-session.

**Results (single learning app, ~10 minutes)**:
- Thresholds continued firing beyond 6 minutes; usage progressed past 360s without interruption.
- Persisted usage and points matched expected cumulative totals; no duplicates or restart loops observed.

**Status**: Issue resolved. Tracking remains stable through at least 10 minutes with the expanded scheduling window.

---

### 🚨🚨 ARCHITECTURAL FLAW: Thresholds Fire at Completely Wrong Times (2025-11-17 NIGHT - ORIGINAL DISCOVERY)

**BLOCKING ISSUE**: DeviceActivity thresholds fire at completely incorrect times, making ALL usage tracking unreliable!

**Test Results (Post Phantom-Fix)**:
- **Setup**: Deleted app, cleaned build, reinstalled (phantom fixes deployed)
- **Action**: Ran ONE learning app for exactly **7 minutes** (measured with stopwatch)
- **Expected Thresholds**: 1 min, 2 min, 3 min, 4 min, 5 min, 6 min, 7 min
- **Actual Threshold Fires**:
  - 60s threshold: Fired after **1:00 min** ✓ CORRECT
  - 120s threshold: Fired after **3:30 min** ❌ WRONG (should be 2:00)
  - 180s threshold: Fired after **7:00 min** ❌ WRONG (should be 3:00)
  - 240s threshold: Fired **immediately after closing app** ❌ WRONG (should be 4:00)

**UI Inconsistencies**:
- Challenge Progress: 60% (6/10m) = **6 minutes**
- YouTube widget: **5 min today**
- Log shows: **240s (4 minutes)** recorded

**Impact**:
- 🔴 CRITICAL: Thresholds firing at 75-133% late!
- Usage tracking is completely unreliable
- Cannot use for actual time-based rewards
- App is fundamentally broken for its purpose

---

### 🚨 CRITICAL ISSUE DISCOVERED (2025-11-17 AFTERNOON)

**NEW Symptom**: App is recording PHANTOM USAGE - showing 2 minutes after only 20 seconds of actual use!

**Test Case (Post-Fix Verification)**:
- Action: Deleted app, cleaned build, restarted Xcode, reinstalled app
- Ran ONE learning app for only 20 SECONDS of actual usage
- Result: ❌ App UI shows 2 MINUTES of usage (120 seconds)
- Xcode log showed usage time appearing within first few seconds

**Impact**:
- 🔴 CRITICAL: App is recording usage that never happened (6x overcount!)
- Users will be credited for learning time they didn't actually spend
- Completely breaks the gamification/reward system
- Makes the app unusable for its intended purpose

---

### Original Issue (Now Secondary)

**Symptom**: Parent Dashboard shows incorrect usage time (2 minutes) while Child UI correctly shows actual usage time (5 minutes).

**Test Case**:
- Action: Ran one learning app for 5 actual minutes
- Child UI Result: ✅ Shows 5 minutes (CORRECT)
- Parent Dashboard Result: ❌ Shows 2 minutes (INCORRECT)
- Challenge Progress: Shows 50% (5/10 minutes) - indicates 5 minutes tracked

**Status**: Fix was implemented (reloadAppUsagesFromPersistence) but revealed a much worse underlying issue

---

## Root Cause Analysis

### 🚨🚨 ARCHITECTURAL FLAW: Interval-Relative vs Daily-Cumulative Thresholds

**THE FUNDAMENTAL MISUNDERSTANDING:**

**What The Code Assumes:**
- DeviceActivity thresholds represent cumulative usage "today" (since midnight)
- Setting threshold to "60s" means "fire when app has 60s total usage today"
- iOS tracks daily usage from 00:00:00 and compares against threshold

**What DeviceActivity ACTUALLY Does:**
- Thresholds are cumulative **WITHIN THE MONITORING INTERVAL ONLY**
- Setting threshold to "60s" means "fire when app accumulates 60s SINCE THE INTERVAL STARTED"
- The interval start time is when `startMonitoring()` was called, **NOT midnight**
- Every time monitoring restarts, iOS **resets its internal usage counter to 0**

#### The Evidence

**From ScreenTimeService.swift schedule creation:**
```swift
// Line ~1491: Creates interval from "now" to "now + 1 hour"
let schedule = DeviceActivitySchedule(
    intervalStart: DateComponents(hour: 20, minute: 39, second: 14),
    intervalEnd: DateComponents(hour: 21, minute: 39, second: 14),
    repeats: false  // ❌ CRITICAL: Does not repeat!
)
```

This creates a monitoring window from 20:39:14 to 21:39:14.

**What Happens:**
1. User starts app at 20:39:14 → Monitoring starts, interval begins
2. User switches to learning app → iOS starts counting usage from 20:39:14
3. Threshold set to "60s cumulative" → iOS interprets as "60s since 20:39:14"
4. User uses app for 1 minute → Threshold fires ✓ CORRECT (60s since interval start)

**But then app becomes active and restarts monitoring:**
1. App becomes active at 20:40:14 → Monitoring restarts
2. **NEW interval**: 20:40:14 to 21:40:14
3. **iOS resets internal counter to 0** ❌
4. Threshold set to "120s cumulative" → iOS interprets as "120s since 20:40:14"
5. User's actual usage: 60s before restart + continuing usage
6. iOS sees: Only usage **since 20:40:14** (restarted counter)
7. Result: Threshold fires at wrong time!

#### Why Monitoring Keeps Restarting

**File**: `ScreenTimeService.swift`

**Line 952-954** - App Becoming Active:
```swift
func handleAppDidBecomeActive() {
    NSLog("[ScreenTimeService] 🔐 App active - authorization status...")
    restartMonitoring()  // ❌ CRITICAL: Restarts on every app activation!
}
```

**Every time the user:**
- Opens the main app to check progress
- Switches back from a learning app
- Gets a notification and opens the app

**The monitoring interval restarts** and iOS resets its usage counter!

#### The Math That Doesn't Work

**User's actual usage**: 7 minutes continuously in one app

**What the code thinks should happen:**
- Threshold 1: 60s → Fire at 1:00 ✓
- Threshold 2: 120s → Fire at 2:00 ✓
- Threshold 3: 180s → Fire at 3:00 ✓
- Etc.

**What actually happens with interval restarts:**
- Interval 1: 20:39:14 - 21:39:14
  - Threshold 1 (60s): Fires at 20:40:14 (1 min actual) ✓
  - User switches to main app
- **Interval restarts** at 20:40:30
- Interval 2: 20:40:30 - 21:40:30 (iOS counter resets to 0!)
  - Threshold 2 (120s): iOS needs 120s **since 20:40:30**
  - User has only 30s usage before first threshold + continuing
  - But iOS only counts **new** usage since 20:40:30
  - Fires at 20:43:30 (3.5 min actual) ❌ 1.5 min late!

#### Key Code Locations

**File**: `ScreenTimeService.swift`

1. **Line 952-954**: `handleAppDidBecomeActive()` - Unnecessary restarts
2. **Line 1459-1463**: Start time calculation - Uses "now" instead of midnight
3. **Line 1491-1494**: Schedule creation - `repeats: false` instead of daily repeat
4. **Line 1232-1250**: `startMonitoring()` - Should use midnight-based schedule

---

### 🚨 FIXED: Phantom Usage Root Cause (Secondary Issue)

**Main Issue**: `cumulativeExpectedUsage` dictionary persists in App Group UserDefaults and is NOT cleared when the app is deleted and reinstalled. This causes stale cumulative tracking values to be used for threshold calculations, resulting in premature threshold fires that record usage the user didn't actually accumulate.

#### How Cumulative Tracking Works

**File**: `ScreenTimeService.swift`

**Lines 774-775** - Persistence:
```swift
defaults.set(cumulativeExpectedUsage.mapValues { $0 }, forKey: cumulativeTrackingKey)
```
Saves to: `UserDefaults(suiteName: "group.com.screentimerewards.shared")`

**Lines 783-800** - Loading:
```swift
private func loadCumulativeTracking() {
    if let saved = defaults.dictionary(forKey: cumulativeTrackingKey) as? [String: TimeInterval] {
        cumulativeExpectedUsage = saved  // ❌ Loads OLD data from previous install!
    }
}
```

**Lines 1363-1371** - Threshold Calculation:
```swift
let currentExpected = cumulativeExpectedUsage[logicalID] ?? 0  // ❌ Uses stale value!
let nextThreshold = currentExpected + incrementValue
```

#### The Phantom Usage Scenario

1. **Previous Session** (before app deletion):
   - User accumulated 120 seconds of cumulative expected usage
   - Value saved to App Group UserDefaults: `cumulativeExpectedUsage["appID"] = 120`

2. **User Deletes App**:
   - App deleted
   - BUT App Group UserDefaults persist (not deleted)

3. **User Reinstalls App**:
   - `loadCumulativeTracking()` loads OLD value: `cumulativeExpectedUsage["appID"] = 120`
   - First threshold calculation: `nextThreshold = 120 + 60 = 180s`
   - DeviceActivity schedules event to fire at **180 seconds cumulative**

4. **User Uses App for 20 Seconds**:
   - DeviceActivity hasn't reached 180s threshold yet
   - No event fires (correct)
   - **BUT** if there's ANY previous session data, things break differently...

5. **The Actual Bug**:
   - Old cumulative tracking (120s) + new increment (60s) = 180s threshold
   - If iOS DeviceActivity interprets this incorrectly OR
   - If the extension is reading cumulative values from previous sessions
   - The result is phantom usage being recorded

#### Where the 2 Minutes Comes From

Based on the test results (2 minutes after 20 seconds), the most likely cause is:

**Hypothesis 1: Double Threshold Fires**
- Threshold 1 fires prematurely (due to stale cumulative) → records 60s
- Threshold 2 fires prematurely → records another 60s
- Total phantom: 120s (2 minutes)
- User only used: 20s

**Hypothesis 2: Stale PersistedApp Data**
- `PersistedApp.todaySeconds` also persists in App Group
- Not cleared on app deletion
- Extension adds to existing value instead of replacing

**Hypothesis 3: Midnight Reset Not Called**
- `resetDailyTracking()` called at midnight (AppDelegate.swift line 55)
- NOT called on app install/deletion
- Old data from yesterday/previous install persists

---

### Secondary Issue: UI Data Sync (Original Bug)

**Main Issue**: `AppUsage` objects are created at app startup but are NOT refreshed when the extension records new usage to `PersistedApp.todaySeconds`.

### Two Data Flow Paths

#### Path 1: Child UI (WORKS CORRECTLY ✅)
```
Extension fires threshold →
Updates PersistedApp.todaySeconds (60s → 120s → 180s → 240s → 300s) →
Child UI reads directly from PersistedApp.todaySeconds →
Displays 300s (5 minutes) ✅
```

#### Path 2: Parent Dashboard (BROKEN ❌)
```
App startup: Creates AppUsage from PersistedApp.todaySeconds (0s) →
Extension updates PersistedApp.todaySeconds (60s → 120s → 180s → 240s → 300s) ✓ →
Main app receives usage notifications ✓ →
Main app does NOT reload AppUsage from updated PersistedApp ❌ →
Parent Dashboard reads stale AppUsage (shows last value: 120s = 2 minutes) ❌
```

### Evidence from Logs

```log
[ScreenTimeService] 📊 Unknown App 1 cumulative tracking:
  Previous: 120s
  Current: 120s  ← STUCK at stale value!
  Increment: 60s
```

Later in the log:
```log
[AppUsageViewModel] App: Unknown App 1, Time: 120.0 seconds, Points: 20
```

**Conclusion**: The 3 missing minutes (180 seconds) ARE correctly written to `PersistedApp.todaySeconds` by the extension, but the Parent Dashboard reads from stale `AppUsage` objects that haven't been refreshed.

---

## Why This Happens

### Current Implementation Flow

1. **App Startup** (`ScreenTimeService.loadPersistedAssignments()` - line 283-288):
   - Creates `AppUsage` objects from `PersistedApp` data
   - Stores in `appUsages` dictionary

2. **Extension Records Usage** (DeviceActivityMonitorExtension):
   - Receives threshold events from iOS
   - Updates `PersistedApp.todaySeconds` in shared storage ✓
   - Sends notification to main app ✓

3. **Main App Receives Notification** (`handleUsageSequenceNotification()` - line 1067-1202):
   - Syncs data from shared storage ✓
   - Updates `ChallengeService` ✓
   - **MISSING**: Does NOT update `AppUsage` objects ❌
   - Calls `notifyUsageChange()` but with stale data ❌

4. **Parent Dashboard Displays**:
   - Reads from stale `AppUsage` objects
   - Shows incorrect usage time ❌

### Key Code Locations

**File**: `ScreenTimeRewards/Services/ScreenTimeService.swift`

- **Line 1067-1202**: `handleUsageSequenceNotification()` - Needs fix here
- **Line 1386**: `reloadAppUsagesFromPersistence()` - Method to call for fix
- **Line 682-725**: `appUsage(from:)` - Converts `PersistedApp` → `AppUsage`
- **Line 283-288**: `loadPersistedAssignments()` - Initial load at startup

---

## Verification: Not an iOS API Bug

**iOS DeviceActivity API is working perfectly:**
- ✅ All 5 threshold events fired correctly (1 min, 2 min, 3 min, 4 min, 5 min)
- ✅ Extension received all callbacks
- ✅ Extension wrote 300s to persistent storage (`PersistedApp.todaySeconds`)
- ✅ Child UI reads 300s correctly from storage
- ✅ Challenge progress calculated correctly (5 minutes)

**Only the Parent Dashboard data sync is broken** - this is 100% an implementation bug in the main app's synchronization logic.

---

## Fix Plan

### 🚨🚨 CRITICAL FIX: Correct Threshold Timing Architecture

**This MUST be fixed before the app can function correctly. The current approach is fundamentally flawed.**

#### Understanding the Problem

DeviceActivity thresholds are **interval-relative**, NOT **daily-cumulative**. The current code:
1. Creates 1-hour intervals starting from "now"
2. Restarts monitoring on every app activation
3. iOS resets usage counters on each restart
4. Result: Thresholds fire at completely wrong times

#### Solution: Use Midnight-to-Midnight Daily Schedule

**Approach**: Change from "1-hour rolling intervals" to "fixed midnight-to-midnight daily schedule with repeats"

##### Part 1: Stop Unnecessary Monitoring Restarts

**File**: `ScreenTimeService.swift`
**Method**: `handleAppDidBecomeActive()` (line 952-954)

**REMOVE** the automatic restart:
```swift
// BEFORE (Current broken code):
func handleAppDidBecomeActive() {
    NSLog("[ScreenTimeService] 🔐 App active - authorization status...")

    // ❌ REMOVE THIS - It breaks threshold timing!
    restartMonitoring()
}

// AFTER (Fixed code):
func handleAppDidBecomeActive() {
    NSLog("[ScreenTimeService] 🔐 App active - authorization status...")

    // ✅ DO NOT restart monitoring on app activation
    // Let the daily schedule run without interruption
    // Only sync data from extension

    if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
        let didUpdateUsage = processSharedUsageData(reason: "app_active")
        if didUpdateUsage {
            notifyUsageChange()
        }
    }
}
```

**Why**: Prevents iOS from resetting usage counters mid-session

---

##### Part 2: Use Midnight-Based Daily Schedule

**File**: `ScreenTimeService.swift`
**Method**: `dailyDeviceActivitySchedule()` (around line 1459-1494)

**REPLACE** the current interval calculation:
```swift
// BEFORE (Current broken code):
private func createDeviceActivitySchedule() -> DeviceActivitySchedule {
    let now = Date()
    let calendar = Calendar.current

    // ❌ Creates interval starting from "now"
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
    let endDate = calendar.date(byAdding: .hour, value: 1, to: now)!
    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)

    return DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: endComponents,
        repeats: false  // ❌ Does not repeat!
    )
}

// AFTER (Fixed code):
private func dailyDeviceActivitySchedule() -> DeviceActivitySchedule {
    let startComponents = DateComponents(hour: 0, minute: 0, second: 0)
    let endComponents = DateComponents(hour: 23, minute: 59, second: 59)

    NSLog("[ScreenTimeService] 📅 Creating midnight-to-midnight daily schedule (repeats: true)")

    return DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: endComponents,
        repeats: true  // ✅ Repeats daily!
    )
}
```

**Why**:
- Schedule always spans full day (midnight to midnight)
- `repeats: true` means it auto-renews daily
- iOS usage counters reset at midnight (expected behavior)
- Thresholds become "daily cumulative" as intended

---

##### Part 3: Adjust Threshold Calculation for Daily Schedule

**File**: `ScreenTimeService.swift`
**Method**: `regenerateMonitoredEvents()` (around line 1363-1420)

**KEY INSIGHT**: With a midnight-based schedule, thresholds should be **absolute** daily values, not cumulative across restarts.

**MODIFY** threshold calculation:
```swift
// BEFORE (Current code - works with rolling intervals):
let currentExpected = cumulativeExpectedUsage[logicalID] ?? 0
let nextThreshold = currentExpected + incrementValue

// AFTER (Fixed for daily schedule):
// Read actual usage so far today
let actualTodaySeconds: TimeInterval
if let persisted = usagePersistence.app(for: logicalID) {
    actualTodaySeconds = TimeInterval(persisted.todaySeconds)
} else {
    actualTodaySeconds = 0
}

// Calculate next threshold as next 60s increment above actual usage
let nextMinute = ceil((actualTodaySeconds + 1) / 60.0) * 60.0
let nextThreshold = nextMinute

NSLog("[ScreenTimeService] 📊 Event for \(app.displayName):")
NSLog("[ScreenTimeService]   Actual usage today: \(Int(actualTodaySeconds))s")
NSLog("[ScreenTimeService]   Next threshold: \(Int(nextThreshold))s (at \(Int(nextThreshold/60)) min mark)")
```

**Why**:
- Uses actual persisted usage to calculate next threshold
- Aligns with iOS's midnight-based counter
- Prevents threshold drift

---

##### Part 4: Only Restart at Midnight

**File**: `AppDelegate.swift` or `ScreenTimeService.swift`

**ADD** midnight transition handler:
```swift
NotificationCenter.default.addObserver(
    forName: .NSCalendarDayChanged,
    object: nil,
    queue: .main
) { [weak self] _ in
    NSLog("[AppDelegate] 🌅 New day detected - resetting cumulative tracking")
    Task { @MainActor in
        await ScreenTimeService.shared.handleMidnightTransition()
    }
}
```

**ALSO MODIFY** `resetDailyTracking()`:
```swift
func resetDailyTracking() {
    usagePersistence.resetDailyCounters()

    cumulativeExpectedUsage.removeAll()
    saveCumulativeTracking()
    reloadAppUsagesFromPersistence()

    NSLog("[ScreenTimeService] 🔄 Reset cumulative tracking for new day")
}
```

**Why**: Clean slate at midnight, aligned with iOS behavior

---

##### Part 5: Remove Rolling Interval Logic

**File**: `ScreenTimeService.swift`

**REMOVE** these methods/logic:
- Any code that calculates "1-hour from now" intervals
- Timer-based monitoring restarts
- App-activation-based restarts (except at midnight)

---

### Expected Behavior After Fix

With these changes:

1. **Monitoring schedule**: Midnight (00:00:00) to midnight (23:59:59), repeats daily
2. **Thresholds**: 60s, 120s, 180s, etc. (absolute daily cumulative)
3. **Threshold fires**:
   - 60s threshold → Fires when app has 60s total usage TODAY ✓
   - 120s threshold → Fires when app has 120s total usage TODAY ✓
   - Works correctly even if user switches apps multiple times ✓
4. **Midnight reset**: Automatic, aligned with iOS counter reset ✓

---

### 🚨 SECONDARY FIX: Eliminate Phantom Usage (COMPLETED)

The phantom usage issue was fixed with the 3-layer solution implemented earlier.

#### Solution 1: Clear Cumulative Tracking on First Launch (RECOMMENDED)

**File**: `ScreenTimeService.swift`
**Method**: `loadCumulativeTracking()` (around line 783-800)

**Implementation**:
```swift
private func loadCumulativeTracking() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
        cumulativeExpectedUsage.removeAll()
        return
    }

    // ✅ CRITICAL FIX: Detect first launch and clear stale cumulative tracking
    let isFirstLaunch = !defaults.bool(forKey: "hasLaunchedBefore")
    if isFirstLaunch {
        NSLog("[ScreenTimeService] 🆕 First launch detected - clearing cumulative tracking")
        cumulativeExpectedUsage.removeAll()
        saveCumulativeTracking()
        defaults.set(true, forKey: "hasLaunchedBefore")
        defaults.synchronize()
        return
    }

    // Normal load for subsequent launches
    if let saved = defaults.dictionary(forKey: cumulativeTrackingKey) as? [String: TimeInterval] {
        cumulativeExpectedUsage = saved
        NSLog("[ScreenTimeService] 📂 Loaded cumulative tracking for \(saved.count) apps")
    }
}
```

**Why This Works**:
- Detects app deletion/reinstall (no "hasLaunchedBefore" flag)
- Clears stale cumulative tracking from previous install
- Ensures clean state for new install
- Sets flag to prevent clearing on normal app restarts

---

#### Solution 2: Validate Cumulative Tracking Against Actual Data (SAFETY NET)

**File**: `ScreenTimeService.swift`
**Method**: `regenerateMonitoredEvents()` (around line 1336-1420)

**Add after loading cumulative tracking**:
```swift
// ✅ VALIDATION: Check if cumulative tracking is out of sync with actual usage
for (logicalID, expected) in cumulativeExpectedUsage {
    if let persisted = usagePersistence.app(for: logicalID) {
        let actualTodaySeconds = TimeInterval(persisted.todaySeconds)

        // If cumulative expected is way ahead of actual usage, reset it
        if expected > actualTodaySeconds + 120 {  // 2-minute tolerance
            NSLog("[ScreenTimeService] ⚠️ Cumulative tracking for \(logicalID) is stale (\(Int(expected))s expected vs \(Int(actualTodaySeconds))s actual) - resetting")
            cumulativeExpectedUsage[logicalID] = actualTodaySeconds
        }
    } else {
        // No persisted data found, clear cumulative tracking for this app
        NSLog("[ScreenTimeService] ⚠️ No persisted data for \(logicalID) - clearing cumulative tracking")
        cumulativeExpectedUsage.removeValue(forKey: logicalID)
    }
}
saveCumulativeTracking()
```

**Why This Works**:
- Validates cumulative tracking against actual persisted usage
- Detects and corrects drift/staleness
- Self-healing mechanism if data gets out of sync
- Removes tracking for apps that no longer exist

---

#### Solution 3: Also Clear PersistedApp Data on First Launch

**File**: `UsagePersistence.swift`
**Location**: Add a method to clear all persisted app data

```swift
public func clearAllAppData() {
    apps.removeAll()
    tokenMappings.removeAll()
    save()
    NSLog("[UsagePersistence] 🧹 Cleared all persisted app data")
}
```

**File**: `ScreenTimeService.swift`
**Method**: `loadCumulativeTracking()` or initialization

**Call this when first launch detected**:
```swift
if isFirstLaunch {
    NSLog("[ScreenTimeService] 🆕 First launch detected - clearing all persisted data")
    usagePersistence.clearAllAppData()
    cumulativeExpectedUsage.removeAll()
    saveCumulativeTracking()
    // ... set hasLaunchedBefore flag
}
```

**Why This Works**:
- Ensures BOTH cumulative tracking AND persisted app data are cleared
- Eliminates any possibility of stale data
- Complete fresh start for new install

---

#### Recommended Implementation Order

1. **Implement Solution 1** (first launch detection) - PRIMARY FIX
2. **Implement Solution 2** (validation) - SAFETY NET
3. **Implement Solution 3** (clear persisted data) - COMPREHENSIVE FIX

This triple-layer approach ensures:
- Clean state after app deletion/reinstall ✅
- Protection against stale data drift ✅
- Self-healing if issues occur ✅
- Complete elimination of phantom usage ✅

---

### SECONDARY FIX: UI Data Sync (Original Issue)

**Status**: Already implemented, needs verification after phantom usage fix

#### Solution Overview

Add a call to `reloadAppUsagesFromPersistence()` after receiving usage notifications from the extension. This ensures `AppUsage` objects are refreshed with the latest data from persistent storage.

### Specific Changes Required

**File**: `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Method**: `handleUsageSequenceNotification()` (around line 1067-1202)

**Change**:
```swift
// BEFORE (Current buggy code):
private func handleUsageSequenceNotification(...) {
    // ... sync usage data from extension ...

    // Update challenge service
    for app in updatedApps {
        challengeService.recordUsage(...)
    }

    notifyUsageChange()  // ❌ Notifies with STALE AppUsage data
}

// AFTER (Fixed code):
private func handleUsageSequenceNotification(...) {
    // ... sync usage data from extension ...

    // Update challenge service
    for app in updatedApps {
        challengeService.recordUsage(...)
    }

    // ✅ CRITICAL FIX: Reload AppUsage objects from updated PersistedApp data
    reloadAppUsagesFromPersistence()

    notifyUsageChange()  // ✅ Now notifies with FRESH AppUsage data
}
```

### Why This Fix Works

1. Extension updates `PersistedApp.todaySeconds` to 300s ✓
2. Main app receives notification ✓
3. **NEW**: Main app calls `reloadAppUsagesFromPersistence()` ✓
4. `AppUsage` objects are recreated from updated `PersistedApp` data ✓
5. Parent Dashboard now reads correct 300s from fresh `AppUsage` ✓
6. Data consistency achieved between Child UI and Parent Dashboard ✓

---

## Implementation Notes for Dev Agent

### Files to Modify
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift`

### Method to Update
- `handleUsageSequenceNotification()` (around line 1067-1202)
  - OR `syncUsageFromSharedDefaults()` (line 1204-1274) if that's where the logic is

### Method to Call
- `reloadAppUsagesFromPersistence()` (exists at line 1386)
  - This method already exists and does exactly what we need
  - It reads all `PersistedApp` objects and converts them to `AppUsage`
  - Updates the `appUsages` dictionary

### Alternative: More Surgical Fix

If `reloadAppUsagesFromPersistence()` is too heavy (reloads ALL apps), could instead:

```swift
// Only reload the specific app that was updated
if let persisted = usagePersistence.app(for: logicalID) {
    appUsages[logicalID] = appUsage(from: persisted)
}
```

But the full reload is safer and ensures complete consistency.

---

## Testing Verification

### Test Scenario
1. Delete app and clean build
2. Start app, complete setup
3. Select one learning app
4. Run the learning app for exactly 5 minutes
5. Return to app

### Success Criteria
- ✅ Child Challenge Detail shows: 5 minutes (50% - 5/10m)
- ✅ Parent Dashboard "Today's Activity" shows: 5 minutes learning
- ✅ Parent Dashboard "Points Overview" shows: 50 points earned
- ✅ No discrepancy between Child and Parent views

### Log Verification
After fix, logs should show:
```log
[AppUsageViewModel] App: Unknown App, Time: 300.0 seconds, Points: 50
[AppUsageViewModel] Updated category totals - Learning: 300.0, Reward: 0.0
```

### Edge Cases to Test
1. Multiple apps (learning + reward)
2. Switching between apps
3. Background/foreground transitions
4. App restart during usage tracking
5. Threshold crossings (1 min, 2 min, 3 min boundaries)

---

## Implementation Status

### Current Status: 🆘🆘 CRITICAL FAILURES - ARCHITECTURE FIX INSUFFICIENT

**Primary Issue (Threshold Timing - STILL BROKEN)**:
- [x] Issue discovered during initial testing (2025-11-17 night)
- [x] Root cause identified (interval-relative vs daily-cumulative)
- [x] Architectural flaw understood (rolling intervals break iOS counter)
- [x] Fix approach determined (midnight-to-midnight daily schedule)
- [x] Code locations identified
- [x] Part 1: Removed `handleAppDidBecomeActive()` restarts (data sync only) - IMPLEMENTED
- [x] Part 2: Implemented midnight-to-midnight repeating schedule (`dailyDeviceActivitySchedule()`) - IMPLEMENTED
- [x] Part 3: Thresholds now derive from actual `todaySeconds` - IMPLEMENTED
- [x] Part 4: Added `.NSCalendarDayChanged` handler - IMPLEMENTED
- [x] Part 5: Deleted rolling restart timer/offset scheduling logic - IMPLEMENTED
- [x] **Fix tested (2025-11-18 03:26) - FAILED**
- [ ] Threshold timing verified accurate - **STILL BROKEN**

**New Critical Issues Discovered (2025-11-18)**:
- [x] Issue #1: Phantom monitoring restarts - IDENTIFIED, LOGGING + THROTTLE IMPLEMENTED (verification pending)
- [x] Issue #2: Double threshold fires (dual monitors) - IDENTIFIED, guardrails added (verification pending)
- [x] Issue #3: Threshold timing still 100-133% late - IDENTIFIED BUT NOT FIXED
- [x] Issue #4: Mid-day partial interval (iOS limitation) - IDENTIFIED, NO FIX POSSIBLE
- [x] Issue #5: May need alternative API approach - UNDER CONSIDERATION
- [ ] Issue #1: Confirm restart source eliminated via new logging - IN PROGRESS
- [ ] Issue #2: Confirm double counting resolved - IN PROGRESS
- [ ] Issue #3: Re-test after #1/#2 fixes - BLOCKED
- [ ] All issues resolved - FAR FROM COMPLETE

**Secondary Issue (Phantom Usage - FIXED)**:
- [x] Critical issue discovered during testing
- [x] Root cause identified (stale cumulative tracking)
- [x] Fix approach determined (3-layer solution)
- [x] Code locations identified
- [x] Solution 1: First launch detection implemented (`loadCumulativeTracking()` now clears stale tracking + persistence on reinstall)
- [x] Solution 2: Validation safety net implemented (`regenerateMonitoredEvents()` reconciles cumulative vs. persisted usage with 2-minute tolerance)
- [x] Solution 3: Clear persisted data implemented (`UsagePersistence.clearAllAppData()` invoked on fresh installs)
- [ ] Primary fix tested
- [ ] Phantom usage eliminated

**Secondary Issue (UI Sync)**:
- [x] Issue reproduced
- [x] Root cause identified
- [x] Fix approach determined
- [x] Code locations identified
- [x] Fix implemented (reloadAppUsagesFromPersistence)
- [ ] Fix tested (blocked until phantom usage verification passes)
- [ ] Edge cases verified
- [ ] Issue closed

---

## Implementation Log

### 2025-11-17 (Morning): Initial Investigation
- **Symptoms observed**: Parent Dashboard shows 2 min while Child UI shows 5 min actual
- **Logs analyzed**: Identified stale AppUsage data
- **Root cause found**: AppUsage objects not refreshed after extension updates
- **Fix identified**: Add `reloadAppUsagesFromPersistence()` call

### 2025-11-17 (Afternoon): UI Sync Fix Implementation
- **Implementation by Dev Agent**:
  - Modified `ScreenTimeService.handleUsageSequenceNotification()` to reload `AppUsage` objects from persistence after each usage notification
  - Modified `handleAppDidBecomeActive()` to perform same refresh when manual syncs detect new usage
  - Modified `processSharedUsageData(reason:)` to return boolean and defer `notifyUsageChange()` to `reloadAppUsagesFromPersistence()`
- **Files changed**: `ScreenTimeRewards/Services/ScreenTimeService.swift`
- **Status**: Implementation complete, awaiting testing

### 2025-11-17 (Evening): 🚨 CRITICAL ISSUE DISCOVERED

**Testing Results**:
- **Test setup**: Deleted app, cleaned build, restarted Xcode, reinstalled app
- **Test action**: Ran ONE learning app for only **20 SECONDS** of actual usage
- **Expected result**: App shows ~20 seconds of usage
- **Actual result**: ❌ App shows **2 MINUTES (120 seconds)** of usage
- **Impact**: 6x overcount - PHANTOM USAGE being recorded!

**Root Cause Investigation**:
- Analyzed ScreenTimeService cumulative tracking mechanism
- Found `cumulativeExpectedUsage` dictionary persists in App Group UserDefaults
- App Group data survives app deletion/reinstallation
- Stale cumulative values from previous install used for threshold calculations
- Results in premature threshold fires that record phantom usage

**Key Findings**:
1. **Line 774-775**: Cumulative tracking saved to App Group UserDefaults
2. **Line 783-800**: Loads cumulative tracking WITHOUT checking if it's stale
3. **Line 1363-1371**: Threshold calculation uses stale cumulative values
4. **No first-launch detection**: App doesn't detect deletion/reinstall
5. **No validation**: Cumulative tracking never validated against actual usage

**New Fix Plan Developed**:
- **Solution 1**: First launch detection to clear stale data (PRIMARY)
- **Solution 2**: Validate cumulative tracking against actual usage (SAFETY NET)
- **Solution 3**: Also clear PersistedApp data on first launch (COMPREHENSIVE)

**Priority**: CRITICAL - Must fix before addressing UI sync issue
**Next Action**: Dev Agent to implement 3-layer phantom usage fix

### 2025-11-17 (Evening): Phantom Usage Mitigation Implemented
- Added first-launch detection in `ScreenTimeService.loadCumulativeTracking()` so a reinstall clears App Group state, resets cumulative tracking, and invokes `UsagePersistence.clearAllAppData()` before any thresholds are scheduled.
- Introduced `UsagePersistence.clearAllAppData()` with debug logging so both cached apps and token mappings are wiped in tandem with the cumulative tracking reset.
- Added `reconcileCumulativeTrackingWithPersistedUsage()` plus a 120-second tolerance check that runs before `regenerateMonitoredEvents` builds thresholds, automatically correcting stale or orphaned entries and persisting the healed state.
- Updated documentation (this file) to reflect the new implementation status; device verification of phantom usage + UI sync still required.

### 2025-11-18 (Early AM - 03:26): 🆘 POST-FIX TESTING REVEALS CRITICAL FAILURES

**Test Execution**:
- Deleted app, cleaned build, reinstalled with ALL architectural fixes
- Ran YouTube (learning app) for 7 minutes actual usage (stopwatch-measured)
- Monitored logs and UI throughout test

**Results - FAILURE**:
1. **Threshold Timing**: Still ~100-133% late (NOT fixed)
   - 60s threshold: ~1:00 (acceptable)
   - 120s threshold: ~4:00 (should be 2:00) ❌
   - 180s threshold: ~7:00 (should be 3:00) ❌

2. **UI Inconsistency**: Three different values displayed
   - Challenge: 6 minutes (double-counted from dual monitors)
   - Log: 180s (3 minutes = actual tracked usage)
   - "Learning Apps" widget: 3 minutes
   - "Your Progress": 6 minutes

3. **Unexpected Monitoring Restarts**: STILL occurring despite Part 1 fix
   - 03:20:48 - `restartMonitoring()` called (reason: manual)
   - 03:21:50 - `restartMonitoring()` called (reason: manual)
   - 03:24:50 - `restartMonitoring()` called (reason: manual)
   - NO logs showing WHO is calling these restarts

4. **Double Threshold Fires**: Each event fires from BOTH monitors
   - Primary monitor fires → increments challenge
   - Secondary monitor fires → increments challenge again
   - Same timestamp (03:19:01) for both
   - Result: Challenge shows 6 minutes instead of 3

5. **Mid-Day Interval Issue**: Midnight schedule doesn't retroactively track
   - Monitoring started at 03:16:50
   - First interval: 03:16:50 → 23:59:59 (partial day)
   - Thresholds relative to 03:16:50, NOT midnight
   - Any usage before app installation not tracked (expected, but confirms limitation)

**Log Evidence**:
```
[ScreenTimeService] 📅 Creating midnight-to-midnight daily schedule (repeats: true)
[ScreenTimeService]   Schedule: 00:00:00 → 23:59:59 (repeats daily)
...
[ScreenTimeService] 🔁 restartMonitoring() called  ← UNEXPECTED!
...
[ChallengeService] After: currentValue=1, timestamp=2025-11-17 03:19:01
[ChallengeService] After: currentValue=2, timestamp=2025-11-17 03:19:01  ← DOUBLE!
```

**New Root Causes Identified**:

1. **Phantom monitoring restarts** - Something is calling `restartMonitoring()` without logging
   - Need to audit ALL call sites of `restartMonitoring()`
   - Add stack traces to identify caller
   - Likely from timer, notification, or lifecycle event

2. **Dual monitor design flaw** - Primary AND secondary both fire same events
   - Was intended for redundancy
   - Causes double-counting in challenge progress
   - Need to deduplicate event handling or use single monitor

3. **DeviceActivity partial-day limitation** - Can't create full-day interval mid-day
   - When started at 03:16:50, first interval is 03:16:50 → 23:59:59
   - Thresholds are relative to interval start (03:16:50), not midnight
   - This is an iOS API limitation, not a code bug

4. **Threshold calculation may be wrong** - Even accounting for restarts, timing is off
   - Need to investigate if thresholds are being recalculated incorrectly
   - Possible issue with reading `todaySeconds` value

**Status**: CRITICAL - All fixes implemented but fundamental issues remain
**Next Steps**: Need comprehensive debugging and possible API approach change

---

### 2025-11-18 (Morning): Restart Diagnostics & Event Guardrails
- Added reason-aware `restartMonitoring(reason:force:file:line:)` that captures the exact caller, logs a call stack, and throttles automatic restarts to once every 5 minutes unless forced; midnight transitions and manual Settings actions pass `force: true` while the extension-health watchdog records descriptive reasons (e.g., `extension_health_gap_180s`).
- Updated `ScreenTimeService.handleMidnightTransition()`, `checkExtensionHealth()`, and both Settings diagnostic buttons to pass explicit reasons so we can trace every restart request in logs.
- Removed the secondary DeviceActivity monitor entirely so only the primary activity schedules thresholds, and introduced a 2-second deduplication window inside `handleEventThresholdReached` to ignore duplicate event notifications (preventing double challenge increments).
- Documented the above so QA knows to re-run the restart/double-count tests with the new instrumentation.

### 2025-11-17 (Late Night → 2025-11-18 Early AM): Daily Schedule Architecture Implemented
- Removed the automatic `restartMonitoring()` call from `handleAppDidBecomeActive()` so foregrounding the app no longer resets iOS's DeviceActivity interval counter mid-day.
- Deleted the rolling restart timer infrastructure and offset-based interval scheduling; monitoring now uses a centralized `dailyDeviceActivitySchedule()` helper that creates a midnight-to-midnight schedule with `repeats: true`.
- Rebuilt `regenerateMonitoredEvents()` to look at actual persisted `todaySeconds` for each logical app ID, ensuring every threshold maps to the next daily cumulative minute boundary instead of stale incremental math.
- Added `UsagePersistence.resetDailyCounters()` and expanded `resetDailyTracking()` to clear per-day usage/points, wipe `cumulativeExpectedUsage`, and refresh the in-memory `AppUsage` cache whenever a day boundary occurs.
- Introduced `handleMidnightTransition()` plus an updated AppDelegate `.NSCalendarDayChanged` observer that resets daily tracking and restarts monitoring exactly once per day (instead of on every app activation).
- Schedule/logging updates now clearly reflect the midnight-to-midnight cadence; threshold timing fix is implemented but requires on-device validation before sign-off.

### 2025-11-18 (Morning): Test 1 – 10-Minute Run
- Ran the tracked learning app for 10 straight minutes after the clean install. Only three 60-second chunks were recorded: the initial phantom minute the OS replayed plus two minutes accrued before each watchdog restart.
- Every ~3 minutes the extension-health watchdog requested `restartMonitoring()` with reason `extension_health_gap_*`. Although throttling prevented some restarts, the watchdog still fired whenever the extension heartbeat was older than 120 seconds, effectively resetting the DeviceActivity counter mid-session.
- Conclusion: the DeviceActivity extension is not updating its heartbeat timestamp after monitoring begins, so the watchdog believes the extension died and forces restarts, preventing accumulation beyond a couple minutes.
- Follow-up plan: instrument the extension heartbeat writer (ensure `extension_heartbeat` is updated periodically) and adjust the watchdog to restart only when the heartbeat truly stalls. Once heartbeat flow is verified, repeat the 10-minute test to confirm continuous tracking.

### 2025-11-18 (Midday): Extension Heartbeat Instrumentation
- Replaced the extension’s `Timer`-based heartbeat with a DispatchSource timer so heartbeat writes continue even when the extension runs on a background thread (file: `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`).
- Each heartbeat write now synchronizes the updated timestamp/memory data to the App Group immediately, guaranteeing the main app can observe it before evaluating health.
- Next step is to verify the heartbeat key advances every minute during monitoring and confirm the watchdog no longer triggers restarts unless the heartbeat actually stalls.

### 2025-11-18 (Afternoon): Threshold Progression Restarts + Watchdog Guardrail
- Added a controlled `threshold_progression` restart at the end of `handleEventThresholdReached()` so every fired DeviceActivity event immediately regenerates and schedules the next threshold (e.g., 60 s → 120 s → 180 s) without waiting for the health watchdog.
- Updated the extension-health watchdog to respect heartbeat gaps of 180 s **and** require at least 3 minutes since the last valid event before it restarts monitoring, preventing it from interrupting active sessions that are already progressing via the new restart reason.
- Follow-up: run the 10-minute stopwatch test to confirm we now see sequential thresholds at roughly 1-minute intervals and no `extension_health_gap_*` restarts unless the heartbeat truly stalls.

### 2025-11-18 (Evening): Post-Restart Plateau & Multi-Threshold Scheduling
- Re-ran the 4-minute on-device test after the `threshold_progression` restart was added. The 60 s threshold fired at 04:49:51 and the restart completed, regenerating events with the next threshold at 120 s. No further usage events arrived before the test was stopped at ~4 minutes, despite the regenerated 120 s target.
- Hypothesis: relying on stop/start to progress thresholds is still too fragile; if the extension doesn’t deliver post-restart usage promptly or if the session is briefly backgrounded, the next threshold never fires even though it was scheduled.
- Mitigation implemented: we now pre-seed multiple (default 6) future thresholds per app during `regenerateMonitoredEvents`, so the extension has 60 s, 120 s, 180 s, 240 s, 300 s, 360 s ready without additional restarts. This should allow continuous minute-by-minute firing even if a restart is skipped or delayed.
- Next verification: run a 5–10 minute learning app session and confirm thresholds fire each minute past 60 s (120/180/240/300/360) with no reliance on health restarts. If thresholds still halt after 60 s, capture the console from the first fire through the next 3–4 minutes to see whether the extension is writing usage/heartbeats in that window.

### 2025-11-18 (Afternoon): 10-Minute Regression Test After Heartbeat Fix
- Reproduced the stopwatch-driven 10-minute run on device build 2025-11-18. The first threshold (60 s) fired correctly at 04:18:04 with matching UI/persistence values.
- At 04:19:47 the watchdog’s `extension_health_gap_135s` branch still fired because the heartbeat timestamp never advanced past the initial interval. This restart stopped monitoring, regenerated the events with “next threshold: 120 s”, and relaunched the interval, which pushed the second threshold out to the ~4-minute mark.
- After the 120 s event fired at 04:22:23 the system never scheduled the 180 s threshold. We removed the automatic restart inside `handleEventThresholdReached`, so no new DeviceActivity event was enqueued and usage became capped at 120 s despite ongoing app activity.
- Takeaway: the watchdog restarts and the lack of post-threshold rescheduling are jointly responsible for the plateau. The heartbeat instrumentation alone is insufficient; we need an explicit plan to (a) keep the OS monitor running continuously and (b) queue the next threshold immediately when one fires.

### 2025-11-17 (Late Night): 🚨 ARCHITECTURAL FLAW DISCOVERED

**Testing After Phantom Fix**:
- **Test setup**: Deleted app, cleaned build, reinstalled with all phantom fixes deployed
- **Test action**: Ran ONE learning app for exactly **7 minutes** (measured with stopwatch)
- **Expected**: Thresholds at 1, 2, 3, 4, 5, 6, 7 minutes
- **Actual Results**:
  - Threshold 1 (60s): Fired at 1:00 ✓ CORRECT
  - Threshold 2 (120s): Fired at 3:30 ❌ 75% LATE!
  - Threshold 3 (180s): Fired at 7:00 ❌ 133% LATE!
  - Threshold 4 (240s): Fired immediately after closing app ❌ BROKEN!
- **UI shows**: 6 minutes (challenge), 5 minutes (widget), 4 minutes (log) - all different!

**Root Cause Analysis**:
- DeviceActivity thresholds are **interval-relative**, NOT daily-cumulative
- Current code creates 1-hour intervals starting from "now" (e.g., 20:39:14)
- App restarts monitoring on every activation (`handleAppDidBecomeActive()`)
- Each restart creates NEW interval with NEW start time
- **iOS resets its internal usage counter to 0 on each interval change**
- Result: Thresholds fire based on usage "since last restart" instead of "since midnight"

**The Architectural Flaw**:
- Code assumes: Threshold 120s = "fire when app has 120s total today"
- iOS interprets: Threshold 120s = "fire when app has 120s since interval started"
- With rolling intervals that restart every time user checks the app, timing is completely broken

**Example Timeline**:
```
20:39:14 - Interval 1 starts (0s baseline)
20:40:14 - User has 60s usage → Threshold 1 fires ✓
20:40:30 - User opens main app → Interval restarts (iOS counter resets to 0!)
20:40:30 - Interval 2 starts (NEW 0s baseline)
20:43:30 - User has 30s from before + 180s new = 210s total
           But iOS only sees 180s since 20:40:30
           Threshold 2 (120s) should have fired at 20:42:00
           Fires now at 20:43:30 - 1.5 minutes late!
```

**Critical Findings**:
1. **Line 952-954**: `handleAppDidBecomeActive()` restarts monitoring unnecessarily
2. **Line 1459-1494**: Schedule uses "now" instead of midnight for interval start
3. **Line 1491**: `repeats: false` means schedule doesn't auto-renew daily
4. **Cumulative tracking is correct** - the bug is in how iOS interprets thresholds

**New Fix Plan Developed - 5-Part Solution**:
1. **Part 1**: Remove automatic restarts from `handleAppDidBecomeActive()`
2. **Part 2**: Change schedule to midnight-to-midnight with `repeats: true`
3. **Part 3**: Adjust threshold calculation to use absolute daily values
4. **Part 4**: Add midnight transition handler for clean daily reset
5. **Part 5**: Remove all rolling interval logic

**Implementation Note**: All five parts above are now implemented in code (see Implementation Log for details). Remaining work is full device verification of the new daily schedule tracking.

**This is a FUNDAMENTAL ARCHITECTURAL REDESIGN** - the entire monitoring approach must change from "rolling 1-hour intervals" to "fixed daily schedule"

**Impact**:
- App is completely unusable for its intended purpose
- Time-based rewards cannot be trusted
- This blocks ALL other fixes (UI sync, etc.)
- Must be fixed before app can function

**Priority**: CRITICAL - BLOCKING ALL OTHER WORK
**Next Action**: Dev Agent to implement 5-part architectural fix

---

## Additional Notes

### Why Child UI Works
Child UI components (like `ChildChallengeDetailView`) likely read directly from:
- `PersistedApp.todaySeconds` via persistence layer, OR
- Challenge progress which gets updated correctly

This bypasses the stale `AppUsage` objects.

### Why Parent Dashboard Fails
Parent Dashboard components (like `ParentDashboardView`) read from:
- `AppUsageViewModel` which wraps `AppUsage` objects
- These objects are created at startup and never refreshed
- Result: Shows stale data

### Performance Consideration
`reloadAppUsagesFromPersistence()` reads from disk, so there's a slight performance cost. However:
- Only called when usage notifications arrive (not frequently)
- Reading from disk is fast (UserDefaults/Core Data)
- Benefits (data accuracy) far outweigh the cost
- Alternative optimizations possible later if needed

---

## Related Files

### Core Files
- `ScreenTimeRewards/Services/ScreenTimeService.swift` - Main service (FIX HERE)
- `ScreenTimeRewards/Models/AppUsage.swift` - AppUsage model
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` - Extension (working correctly)

### UI Files
- `ScreenTimeRewards/Views/ParentMode/ParentDashboardView.swift` - Shows incorrect data
- `ScreenTimeRewards/Views/ChildMode/ChildChallengeDetailView.swift` - Shows correct data
- `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` - Wraps AppUsage

### Persistence
- `ScreenTimeRewards/Shared/UsagePersistence.swift` - Handles PersistedApp storage

---

## Summary for Dev Agent

### 🆘 CRITICAL PRIORITY: Fix Newly Discovered Blocking Issues

**TESTING COMPLETE - ARCHITECTURE FIX FAILED**

The midnight-to-midnight daily schedule was implemented (all 5 parts) but testing revealed the fix is INSUFFICIENT. New critical issues discovered that must be resolved:

---

### Critical Issues from Post-Fix Testing (2025-11-18 03:26)

**Issue #1: Phantom Monitoring Restarts** (HIGHEST PRIORITY)
- **Problem**: `restartMonitoring()` being called every 1-3 minutes from unknown source
- **Evidence**: Logs show "reason: manual" but NO caller logging
- **Impact**: Each restart creates new interval, iOS resets usage counter, thresholds fire late
- **Fix Work**:
  1. ✅ Add logging/stack trace to EVERY call site of `restartMonitoring()` (done 2025-11-18 AM)
  2. ✅ Audit timer/notification call sites (all pass descriptive reasons)
  3. 🔄 Monitor new logs to confirm phantom callers eliminated
  4. 🔄 Test for 10+ minutes with NO restarts

**Issue #2: Double Threshold Fires** (HIGH PRIORITY)
- **Problem**: Primary AND secondary monitors BOTH fire same event
- **Evidence**: Challenge increments twice at same timestamp (03:19:01)
- **Impact**: Challenge shows 6 minutes when actual usage is 3 minutes
- **Fix Work**:
  1. ✅ Removed secondary monitor; only primary DeviceActivity stream remains
  2. ✅ Added 2-second deduplication window inside `handleEventThresholdReached`
  3. 🔄 Must verify challenges count correctly (no double increments)

**Issue #3: Threshold Timing Still Wrong** (HIGH PRIORITY)
- **Problem**: Even with midnight schedule, 2nd/3rd thresholds fire 2-3x late
- **Evidence**: 120s fires at ~4 min (should be 2 min), 180s at ~7 min (should be 3 min)
- **Likely Cause**: Combination of restarts (#1) and partial-day interval (#4)
- **Fix Required**:
  1. Fix issues #1 and #4 first
  2. Re-test threshold timing
  3. If still broken, may need alternative approach (see Issue #5)

**Issue #4: Mid-Day Start Creates Partial Interval** (MEDIUM PRIORITY - iOS LIMITATION)
- **Problem**: Starting monitoring at 03:16:50 creates interval 03:16:50 → 23:59:59
- **Evidence**: Logs confirm midnight schedule but interval starts when monitoring starts
- **Impact**: Thresholds relative to 03:16:50, not midnight; can't track pre-existing usage
- **This is an iOS API limitation** - DeviceActivity intervals always start from "now"
- **Workaround Options**:
  1. Accept limitation (usage only tracked after monitoring starts)
  2. Read existing usage on startup, offset first threshold
  3. Use different API approach (see Issue #5)

**Issue #5: Consider Alternative Approach** (STRATEGIC)
- **Problem**: DeviceActivity thresholds may be fundamentally incompatible with requirements
- **Evidence**: Multiple architectural redesigns failed to achieve reliable minute-by-minute tracking
- **Alternative Approaches**:
  1. **Polling-based**: Check usage every 30s, calculate thresholds ourselves
  2. **Extension-only**: Extension reports raw usage, main app calculates everything
  3. **No thresholds**: Use intervals only, app polls for changes
  4. **Different API**: Investigate Screen Time API alternatives
- **Decision Point**: After fixing #1-#3, if timing still broken, must pivot to alternative

---

### Immediate Action Items (Priority Order)

**MUST FIX NOW** (Blocking):
1. **Queue next thresholds immediately after each event**
   - Reinstate a controlled monitor restart (or multi-threshold scheduling) inside `handleEventThresholdReached` so that when 60 s fires we immediately seed DeviceActivity with the 120 s, 180 s, … follow-ups.
   - Tag these restarts with a new reason (e.g., `threshold_progression`) so we can distinguish intentional progression from watchdog-driven health resets.

2. **Tame the extension-health watchdog**
   - Either disable `extension_health_gap_*` entirely once per-threshold restarts are in place or drive it strictly off the real heartbeat timestamp written by the extension so we don’t reset mid-session.
   - Verify via logs that a 10-minute run no longer emits any watchdog restarts unless the heartbeat truly stalls.

3. **Verify no double counting**
   - Re-run the 5-minute usage test and ensure challenge progress, logs, and widgets all report identical minutes.
   - Confirm deduplication logs remain quiet; intentional threshold restarts should no longer double-fire because the dedupe window remains active.

4. **Re-test threshold timing end-to-end**
   - After #1–#3 are validated, run the 10-minute stopwatch test with no watchdog interventions.
   - Expect thresholds at 1, 2, 3, 4, 5 minutes (±5 s) with uninterrupted cumulative growth in UI/logs.

**CAN ACCEPT** (Lower Priority):
5. Mid-day partial interval (iOS limitation - document and accept)
6. UI inconsistencies (fix after thresholds work)

---

### Testing Requirements (After Fixes)

**Test 1: No Phantom Restarts** ✅
- Run for 10 minutes
- Monitor logs for `restartMonitoring()` calls
- Should be ZERO calls (except at midnight)

**Test 2: No Double Counting** ✅
- Run for 5 minutes
- Check challenge progress = 5 (not 10)
- All UI components show same value

**Test 3: Accurate Threshold Timing** ✅
- Run for 5 minutes with stopwatch
- Verify thresholds fire at: 1:00, 2:00, 3:00, 4:00, 5:00 (±5s)
- Log must show correct cumulative values

**Test 4: UI Consistency** ✅
- Challenge progress = X minutes
- "Your Progress" = X minutes
- "Learning Apps" = X minutes
- Log shows X * 60 seconds
- All must match!

---

**Last Updated**: 2025-11-18 04:50 UTC
**Status**: CRITICAL FAILURES - Architecture fix insufficient, new issues discovered
**Next Action**: Find phantom restart source and fix double threshold fires IMMEDIATELY
