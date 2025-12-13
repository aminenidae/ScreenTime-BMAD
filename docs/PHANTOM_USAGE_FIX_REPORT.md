# Phantom Usage Fix Report

**Date**: 2025-12-13
**Status**: RESOLVED ✅
**Base Commit**: `efa4207` (Fix build errors after challenge removal)

---

## Executive Summary

iOS DeviceActivityMonitor sends "phantom" threshold events for ALL monitored apps, not just the one being used. This caused usage values to inflate incorrectly. After multiple fix attempts, we identified that the extension's `ext_usage_*` keys use SET semantics which break real usage tracking after monitoring restarts.

---

## Problem Description

### Symptoms Observed
- Usage values suddenly drop mid-session (e.g., 15 min → 5 min)
- Usage sometimes inflates unexpectedly
- Affects both learning and reward apps equally
- ALL monitored apps receive usage increases even when only ONE app is used

### Critical Test Case
```
START:    6 minutes existing usage
ACTION:   Used learning app for 6 more minutes
EXPECTED: 12 minutes (720 seconds)
ACTUAL:   3 minutes (180 seconds)
```
Value dropped to LESS than starting point - not a reset-to-zero bug.

### Inflation Test Case
```
TEST:     Used ONE learning app for 2 minutes
RESULT:   ALL 5 apps received usage increases
TOTAL:    660 seconds (11 minutes) recorded when only 120 seconds used
```

---

## Architecture Overview

### Data Flow
```
iOS DeviceActivity Framework
         │
         ▼
┌─────────────────────────────────────────────┐
│  DeviceActivityMonitor Extension            │
│  (ScreenTimeActivityMonitorExtension)       │
│                                             │
│  eventDidReachThreshold() fires when app    │
│  usage hits 1min, 2min, 3min... 60min       │
│                                             │
│  Writes to two key sets:                    │
│  - usage_* keys (INCREMENT-based)           │
│  - ext_usage_* keys (SET-based)             │
└─────────────────────────────────────────────┘
         │
         │ Writes to App Group UserDefaults
         ▼
┌─────────────────────────────────────────────┐
│  Shared UserDefaults (App Group)            │
│                                             │
│  Legacy Keys (INCREMENT):                   │
│  - usage_<appID>_today (seconds)            │
│  - usage_<appID>_total (seconds)            │
│  - usage_<appID>_lastThreshold              │
│                                             │
│  Protected Keys (SET semantics):            │
│  - ext_usage_<appID>_today                  │
│  - ext_usage_<appID>_total                  │
│  - ext_usage_<appID>_date                   │
└─────────────────────────────────────────────┘
         │
         │ Darwin Notification triggers sync
         ▼
┌─────────────────────────────────────────────┐
│  Main App (ScreenTimeService)               │
│                                             │
│  readExtensionUsageData() syncs:            │
│  - Reads extension keys                     │
│  - Updates UsagePersistence (JSON)          │
│  - Updates in-memory appUsages              │
└─────────────────────────────────────────────┘
```

### Key Files
| File | Purpose |
|------|---------|
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Extension that records usage when thresholds fire |
| `ScreenTimeRewards/Services/ScreenTimeService.swift` | Main app service that syncs extension data |
| `ScreenTimeRewards/Shared/UsagePersistence.swift` | JSON-based persistence for usage data |

---

## Root Cause Analysis

### iOS DeviceActivityMonitor Behavior
iOS sends threshold events for ALL monitored apps, not just the active one. When monitoring starts or restarts:

1. iOS tracks usage for ALL apps in the background
2. When monitoring (re)starts, iOS fires "catch-up" threshold events
3. These events arrive for ALL apps within milliseconds
4. Events have LOWER thresholds than previously recorded

### Evidence from Logs
```
[11:24:38.001] EVENT appID=6D7C9194... min=6 currentToday=1440s lastThresh=1860s
[11:24:38.002] THRESH_DECREASE appID=6D7C9194... new=360s < last=1860s
[11:24:38.003] SKIP_RAPID appID=6D7C9194... timeSinceLastEvent=0s < 30s
[11:24:38.004] EVENT appID=25FCC5BC... min=7 currentToday=2820s lastThresh=2580s
```

All events arrived within 3ms - clearly phantom events, not real usage.

---

## Phantom Detection Mechanisms

The extension has three layers of phantom event detection:

### 1. SKIP_RESTART (120s window)
```swift
if timeSinceRestart < 120.0 && restartTimestamp > 0 {
    // Skip events within 120s of monitoring restart
    return false
}
```

### 2. SKIP_RAPID (30s per-app window)
```swift
if timeSinceLastEvent < 30.0 && lastEventTime > 0 {
    // Skip events within 30s of last event for same app
    return false
}
```

### 3. THRESH_DECREASE (threshold comparison)
```swift
if thresholdSeconds < lastThreshold {
    // Threshold decreased - likely catch-up event
    // Reset lastThreshold if not caught by above checks
}
```

---

## Fixes Attempted

### Fix 1: Reduced Thresholds (✅ Applied)

**Rationale**: Fewer thresholds = smaller phantom event surface area.

**Change**:
- File: `ScreenTimeService.swift:766`
- Before: 180 thresholds per app (3 hours)
- After: 60 thresholds per app (1 hour)

**Result**: Matches stable iPad build. Did not solve the problem alone.

---

### Fix 2: Sync Uses Protected Keys (✅ Applied)

**Rationale**: The `ext_usage_*` keys use SET semantics, making them immune to phantom inflation.

**Change**:
- File: `ScreenTimeService.swift:1058-1124`
- Before: Sync reads from `usage_*` keys (INCREMENT-based, vulnerable)
- After: Sync reads from `ext_usage_*` keys (SET-based, protected)

**Code**:
```swift
// Read from PROTECTED ext_ keys (SET semantics - source of truth)
let extTodayKey = "ext_usage_\(logicalID)_today"
let extTodaySeconds = defaults.integer(forKey: extTodayKey)
```

**Result**: Main app now reads correct values. But issue persisted.

---

### Fix 3: Trust Extension Completely (✅ Applied)

**Rationale**: If persisted value is higher than extension value, the persisted value is wrong (inflated).

**Change**:
- File: `ScreenTimeService.swift:1095-1108`
- Before: Only sync if `ext > persisted`
- After: Always sync `persisted = ext`

**Code Before**:
```swift
if isFromToday && extTodaySeconds > persistedApp.todaySeconds {
    persistedApp.todaySeconds = extTodaySeconds
}
```

**Code After**:
```swift
if isFromToday {
    persistedApp.todaySeconds = extTodaySeconds  // Always trust ext
}
```

**Edge Case Accepted**: Mid-day reinstall resets today to 0 (rare, acceptable).

**Result**: Fixes existing inflated data. But then real usage stopped recording.

---

### Fix 4: Revert ext_ Keys to INCREMENT (✅ Applied)

**Problem Discovered**: After applying Fixes 1-3, real usage stopped recording after monitoring restarts.

**Root Cause**: The `ext_usage_*` keys used SET semantics which rejected legitimate events when iOS restarted monitoring.

**Change**:
- File: `DeviceActivityMonitorExtension.swift:261-276`
- Before: `newExtToday = max(currentExtToday, thresholdSeconds)`
- After: `newExtToday = currentExtToday + 60`

**Result**: Real usage now records correctly. Matches stable iPad build.

---

### Fix 5: Enable DEBUG Polling (✅ Applied)

**Problem Discovered**: No real-time usage updates during Xcode debugging.

**Root Cause**: Darwin notifications don't work when running from Xcode debugger.

**Change**:
- File: `ScreenTimeService.swift:203-206, 1370-1405`
- Added `startDebugPolling()` that runs every 10 seconds in DEBUG mode
- Syncs extension data and notifies UI

**Code**:
```swift
#if DEBUG
startDebugPolling()
#endif
```

**Result**: Real-time sync every 10 seconds during Xcode debugging. Production unaffected.

---

## Why INCREMENT Works

1. **SKIP_RESTART** blocks events within 120s of monitoring restart
2. **SKIP_RAPID** blocks events within 30s of last event per app
3. Events that pass both checks are legitimate
4. INCREMENT correctly adds 60s for each legitimate event
5. This matches the stable iPad build behavior

---

## Stable iPad Build Reference

- **Build Date**: December 10, 2025 at 21:58
- **Commit**: `365ab23` (Dec 9, 23:31)
- **Commit Message**: "Fix earned minutes calculation"
- **Thresholds**: 60 per app
- **ext_ Key Logic**: INCREMENT (`current + 60`)
- **Sync Source**: Legacy `usage_*` keys

The stable build has been running for 3 days with:
- Up to 66 minutes of learning app usage
- No inflation
- No phantom usage
- Completely stable

---

## Implementation Checklist

- [x] Fix 1: Reduce thresholds from 180 to 60
- [x] Fix 2: Sync reads from ext_ keys
- [x] Fix 3: Trust extension completely (SET persisted = ext)
- [x] Fix 4: Revert ext_ keys from SET to INCREMENT
- [x] Fix 5: Enable DEBUG polling for Xcode builds
- [x] Test: Verify real usage records after monitoring restart
- [x] Test: Verify phantom events are still blocked
- [x] Test: Confirmed stable tracking for new and existing apps

## Resolution Summary

**Date Resolved**: 2025-12-13

The phantom usage issue has been resolved. Usage tracking now:
- Accurately increments by 60 seconds per minute of real usage
- Works correctly for both new apps and existing apps
- Blocks phantom events via SKIP_RESTART and SKIP_RAPID detection
- Syncs in real-time during Xcode debugging (via DEBUG polling)
- Uses Darwin notifications in production (TestFlight/App Store)

---

## Files Modified

| File | Lines | Change |
|------|-------|--------|
| `ScreenTimeService.swift` | 766 | Threshold 180 → 60 |
| `ScreenTimeService.swift` | 1058-1137 | Sync reads ext_ keys, trusts extension |
| `ScreenTimeService.swift` | 203-206, 1370-1405 | DEBUG polling for Xcode builds |
| `DeviceActivityMonitorExtension.swift` | 181-188 | NEW_DAY: ext_ keys use INCREMENT |
| `DeviceActivityMonitorExtension.swift` | 261-276 | Same-day: ext_ keys use INCREMENT |

---

## Lessons Learned

1. **SET semantics break after monitoring restart**: When iOS restarts monitoring and resets its internal counter, low threshold events are rejected because `max(high, low) = high`.

2. **Phantom detection is effective**: The SKIP_RESTART (120s) and SKIP_RAPID (30s) mechanisms successfully identify and block phantom events.

3. **INCREMENT + phantom detection = correct tracking**: Events that pass phantom detection are legitimate and should be recorded with INCREMENT.

4. **Stable reference is valuable**: Having a known-working build (iPad Dec 10) provided crucial comparison data.
