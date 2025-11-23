# Usage Tracking Accuracy - Fix Documentation

**Date:** 2025-11-22
**Status:** RESOLVED
**Test Result:** 13 minutes tracked accurately

---

## Issue Summary

Usage tracking was not working after completing onboarding. Users could configure learning and reward apps, but when entering Child Mode, no usage was being recorded despite using the learning apps.

---

## Root Cause

**Monitoring was never started when entering Child Mode.**

The `startMonitoring()` function was only called during the initial onboarding setup flow (in `QuickLearningSetupScreen` and `QuickRewardSetupScreen`). After completing onboarding, when users entered Child Mode via `ModeSelectionView`, the app called `sessionManager.enterChildMode()` which only changed the mode state - it **never started monitoring**.

### Code Flow Before Fix

```
ModeSelectionView.handleChildModeSelection()
    └── sessionManager.enterChildMode()
        └── currentMode = .child  // Just changes state
            // NO monitoring started!
```

### Why Diagnostics Weren't Showing

The diagnostic logs were wrapped in `#if DEBUG` preprocessor directives, which may not have been active depending on the build configuration. Additionally, since monitoring never started, many diagnostic code paths were never reached.

---

## The Fix

### 1. Added `startMonitoring()` to ChildModeView.onAppear

**File:** `ScreenTimeRewards/Views/ChildMode/ChildModeView.swift`

```swift
.onAppear {
    // CRITICAL: Start monitoring when entering Child Mode
    // This was missing - monitoring only started during onboarding setup
    print("[ChildModeView] 📱 Child Mode appeared - starting monitoring")
    viewModel.startMonitoring(force: false)

    // Ensure challenges are loaded
    Task {
        await viewModel.loadChallengeData()
    }
}
```

### 2. Added Unconditional Logging

Removed `#if DEBUG` wrappers from critical logging in:

**File:** `ScreenTimeRewards/Services/ScreenTimeService.swift`

```swift
override private init() {
    // ... initialization code ...

    // ALWAYS print this - not wrapped in DEBUG - to diagnose tracking issues
    print("=" + String(repeating: "=", count: 50))
    print("[ScreenTimeService] 🚀 SERVICE INITIALIZED")
    print("[ScreenTimeService] appUsages count: \(appUsages.count)")
    print("[ScreenTimeService] isMonitoring: \(isMonitoring)")
    print("=" + String(repeating: "=", count: 50))

    // Auto-run diagnostics after 2 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        print("[ScreenTimeService] 📊 AUTO-DIAGNOSTICS RUNNING...")
        self?.printUsageTrackingDiagnostics()
    }
}

func startMonitoring(completion: @escaping (Result<Void, ScreenTimeServiceError>) -> Void) {
    // ALWAYS print - for troubleshooting
    print("[ScreenTimeService] 🎯 startMonitoring() called")

    // ... rest of function with unconditional logging ...
}
```

**File:** `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

```swift
func startMonitoring(force: Bool = false) {
    // ALWAYS print this - not wrapped in DEBUG - for troubleshooting
    print("[AppUsageViewModel] 🎯 startMonitoring() called (force=\(force), isMonitoring=\(isMonitoring))")

    // ... rest of function with unconditional logging ...
}
```

---

## Verification Test

### Test Procedure
1. Deleted and reinstalled the app (fresh start)
2. Added 3 learning apps and 2 reward apps during onboarding
3. Entered Child Mode
4. Used 1 learning app for 13 minutes
5. Checked logs for tracking accuracy

### Expected Log Output

```
===================================================
[ScreenTimeService] 🚀 SERVICE INITIALIZED
[ScreenTimeService] appUsages count: 0
[ScreenTimeService] isMonitoring: false
===================================================
[ChildModeView] 📱 Child Mode appeared - starting monitoring
[AppUsageViewModel] 🎯 startMonitoring() called (force=false, isMonitoring=false)
[AppUsageViewModel] 🚀 Starting monitoring...
[ScreenTimeService] 🎯 startMonitoring() called
[ScreenTimeService] ✅ Permission granted, scheduling activity...
[ScreenTimeService] ✅ Activity scheduled successfully!
[AppUsageViewModel] ✅ Monitoring started successfully!
```

### Actual Results (from xcresult log)

```
App Configuration:
[AppUsageViewModel] Category assignments: 3
[ScreenTimeService] Configuring monitoring with 3 applications

Monitoring Started:
[ScreenTimeService] Successfully started
Activity scheduled
✅ Monitoring
[ChildModeView] appeared - starting monitoring

Usage Tracking (minute-by-minute):
today=60s    → 1 minute
today=120s   → 2 minutes
today=180s   → 3 minutes
today=240s   → 4 minutes
today=300s   → 5 minutes
today=360s   → 6 minutes
today=420s   → 7 minutes
today=480s   → 8 minutes
today=540s   → 9 minutes
today=600s   → 10 minutes
today=720s   → 12 minutes
today=780s   → 13 minutes ✅
```

**Result:** 780 seconds = 13 minutes tracked accurately

---

## Technical Details

### Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main App                                  │
│  ┌─────────────────┐    ┌──────────────────────┐                │
│  │ ChildModeView   │───▶│ AppUsageViewModel    │                │
│  │   .onAppear()   │    │  .startMonitoring()  │                │
│  └─────────────────┘    └──────────┬───────────┘                │
│                                    │                             │
│                         ┌──────────▼───────────┐                │
│                         │ ScreenTimeService    │                │
│                         │  .startMonitoring()  │                │
│                         │  .scheduleActivity() │                │
│                         └──────────┬───────────┘                │
└────────────────────────────────────┼────────────────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │     DeviceActivityCenter        │
                    │  .startMonitoring(activity,     │
                    │     during: schedule,           │
                    │     events: thresholds)         │
                    └────────────────┬────────────────┘
                                     │
┌────────────────────────────────────▼────────────────────────────┐
│              DeviceActivityMonitor Extension                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ eventDidReachThreshold(_ event, activity)            │       │
│  │   └── recordUsageEfficiently(for: eventName)         │       │
│  │       └── setUsageToThreshold(appID, seconds)        │       │
│  │           └── UserDefaults (App Group)               │       │
│  │       └── notifyMainApp() (Darwin notification)      │       │
│  └──────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| ChildModeView | `Views/ChildMode/ChildModeView.swift` | Triggers monitoring on appear |
| AppUsageViewModel | `ViewModels/AppUsageViewModel.swift` | Coordinates monitoring state |
| ScreenTimeService | `Services/ScreenTimeService.swift` | Manages DeviceActivityCenter |
| DeviceActivityMonitorExtension | `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Records threshold events |

### Threshold Strategy

The app uses **1-minute static thresholds** with deduplication guards:

1. 60 pre-configured thresholds (1-60 minutes)
2. Extension fires `eventDidReachThreshold` when usage reaches each minute
3. SET semantics (not INCREMENT) prevent phantom usage accumulation
4. 55-second cooldown prevents duplicate recordings

---

## Files Modified

| File | Change |
|------|--------|
| `ChildModeView.swift` | Added `startMonitoring()` call in `.onAppear` |
| `ScreenTimeService.swift` | Removed `#if DEBUG` from critical logging |
| `AppUsageViewModel.swift` | Removed `#if DEBUG` from critical logging |

---

## Lessons Learned

1. **Always verify monitoring state** - The monitoring flag (`isMonitoring`) can be false even if the user completed onboarding
2. **Critical logging should be unconditional** - Wrapping essential diagnostics in `#if DEBUG` makes production debugging impossible
3. **View lifecycle matters** - `onAppear` is the correct place to ensure monitoring is active when entering a mode
4. **Fresh installs reveal issues** - Testing only with existing data can mask initialization bugs

---

## Related Issues

- **Phantom Usage Tracking**: Previously fixed by changing from INCREMENT to SET semantics in the extension (see `DeviceActivityMonitorExtension.swift`)
- **Shield Data Sync**: Dynamic shield messages implemented via `ShieldDataService.swift`
- **Reward App Unlocking**: Fixed to unlock ALL reward apps when challenge completes

---

## Test Log Location

```
/Users/ameen/Library/Developer/Xcode/DerivedData/ScreenTimeRewards-fvinpepdlvcbewejzvnbwpmuhtaw/Logs/Launch/Run-ScreenTimeRewards-2025.11.22_20-48-44--0600.xcresult
```
