# FIX: Phantom Usage After App Launch

**Date:** 2026-01-28
**Branch:** `fix/phantom-usage-investigation`
**Status:** IMPLEMENTED

---

## Problem
Phantom usage is being recorded after launching the app - confirmed through investigation.

## Root Cause (CONFIRMED)
The extension's phantom protection (SKIP_RESTART) is nested inside `if thresholdSeconds < lastThreshold` block, so it only runs when threshold **decreases**. On app launch, thresholds increase from 0, bypassing the protection entirely.

## Fix: Move SKIP_RESTART Before Threshold Comparison

**File:** `DeviceActivityMonitorExtension.swift`

Move the SKIP_RESTART check to run BEFORE any threshold comparisons, so it applies to ALL events within 55 seconds of monitoring restart.

### Current Code (around line 258-272):
The SKIP_RESTART check is INSIDE the `if thresholdSeconds < lastThreshold` block.

### Fixed Code:
Add SKIP_RESTART check IMMEDIATELY after getting `timeSinceRestart`, BEFORE Case 1/2/3 checks:

```swift
// Global restart check - main app sets this when monitoring starts/restarts
let restartTimestamp = defaults.double(forKey: "monitoring_restart_timestamp")
let timeSinceRestart = nowTimestamp - restartTimestamp

// INVESTIGATION logging (keep for now)
let isInPhantomWindow = timeSinceRestart < 55.0 && restartTimestamp > 0
// ... existing logging ...

// FIX: Check restart filter BEFORE threshold comparison
// This catches phantom events on app launch where thresholds start from 0
if timeSinceRestart < 55.0 && restartTimestamp > 0 {
    debugLog("SKIP_RESTART_GLOBAL appID=\(appID.prefix(8))... timeSinceRestart=\(Int(timeSinceRestart))s < 55s (PHANTOM BLOCKED)", defaults: defaults)
    defaults.set(nowTimestamp, forKey: "usage_\(appID)_lastEventTime")
    return false
}

// Case 1: Duplicate threshold
if thresholdSeconds == lastThreshold {
    // ... existing code
}
```

### Also: Remove Duplicate Check from Case 2
The existing SKIP_RESTART inside Case 2 (threshold decreased) can remain as a secondary check, but will rarely trigger now.

## Files Modified

| File | Change |
|------|--------|
| `DeviceActivityMonitorExtension.swift` | Add SKIP_RESTART check before threshold comparison (55s threshold) |

## Verification Steps

1. Install new build on child device
2. Force-quit app completely
3. Launch app
4. Do NOT use any apps for 60 seconds
5. Check parent dashboard - should NOT show phantom usage
6. After 60 seconds, use a learning app for 2+ minutes
7. Verify only real usage is recorded

---

# Investigation Details

## Enhanced Logging Added

Added detailed logging at the TOP of `setUsageToThreshold()` to capture:
- Whether this is within restart window
- The threshold values and comparison result
- Which case (1, 2, or 3) the event falls into

### Logging Code Added:

```swift
let isInPhantomWindow = timeSinceRestart < 55.0 && restartTimestamp > 0
let wouldSkipIfChecked = thresholdSeconds < lastThreshold && isInPhantomWindow

debugLog("🔍 PHANTOM_CHECK appID=\(appID.prefix(8))...", defaults: defaults)
debugLog("   timeSinceRestart=\(Int(timeSinceRestart))s restartTS=\(restartTimestamp > 0 ? "SET" : "UNSET")", defaults: defaults)
debugLog("   threshold=\(thresholdSeconds) lastThreshold=\(lastThreshold) comparison=\(thresholdSeconds < lastThreshold ? "DECREASED" : thresholdSeconds == lastThreshold ? "EQUAL" : "INCREASED")", defaults: defaults)
debugLog("   isPhantomWindow=\(isInPhantomWindow) wouldSkipIfChecked=\(wouldSkipIfChecked)", defaults: defaults)
```

### Case Logging:

```swift
// Case 1: Duplicate threshold
if thresholdSeconds == lastThreshold {
    debugLog("CASE_1_DUP: threshold=lastThreshold=\(thresholdSeconds)", defaults: defaults)
    return false
}

// Case 2: Threshold decreased
if thresholdSeconds < lastThreshold {
    debugLog("CASE_2_DECREASE: \(thresholdSeconds) < \(lastThreshold)", defaults: defaults)
    // ... existing SKIP_RESTART and SKIP_RAPID checks ...
}

// Case 3: Normal progression
debugLog("CASE_3_PROGRESS: \(thresholdSeconds) > \(lastThreshold)", defaults: defaults)
```

---

# In-App Extension Log Viewer

## Purpose
View extension debug logs without needing Xcode/Console.app.

## Implementation

### File Created: `ExtensionLogViewerView.swift`

```swift
import SwiftUI
import Combine

struct ExtensionLogViewerView: View {
    @State private var logText: String = "Loading..."
    @State private var autoRefresh = true
    @State private var filterText = ""
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let appGroupID = "group.com.screentimerewards.shared"

    // Features:
    // - Auto-refresh toggle (2-second interval)
    // - Filter/search box
    // - Copy logs button
    // - Clear logs button
    // - Reads from UserDefaults key "extension_debug_log"
}
```

### Integration: `SettingsTabView.swift`

Added to DIAGNOSTICS section:
```swift
NavigationLink(destination: ExtensionLogViewerView()) {
    HStack {
        Image(systemName: "doc.text.magnifyingglass")
            .foregroundColor(.blue)
        Text("View Extension Logs")
        Spacer()
    }
}
```

## Bug Fixed
Initial implementation used wrong app group ID (`group.i6dev.ScreenTimeRewards`).
Fixed to use correct ID: `group.com.screentimerewards.shared`

---

# Key Learnings

1. **Phantom Protection Gap**: The original SKIP_RESTART check was only triggered when thresholds decreased, but on app launch thresholds always increase from 0.

2. **Extension Communication**: The main app sets `monitoring_restart_timestamp` when monitoring starts/restarts. The extension checks this to detect phantom events.

3. **55-Second Threshold**: User prefers 55-second phantom window (slightly less than 60-second threshold intervals) to catch all phantom events without blocking legitimate usage.

4. **App Group ID Consistency**: Always use `group.com.screentimerewards.shared` for UserDefaults communication between main app and extension.

---

# UPDATE: Race Condition Fix (2026-01-30)

## New Issue Discovered

After implementing the above fixes, phantom usage was still occurring. Log analysis revealed:

**Evidence from logs:**
- Unknown App 0 showed `currentToday=2820s` (47 min), real usage was 2640s (44 min)
- Hourly breakdown showed `h19=180s` but user confirmed NO usage after 19:00
- All catch-up events in the log (at `timeSinceRestart=46-51s`) were being blocked correctly
- But 3 phantom minutes had already been credited BEFORE the log window

## Root Cause: Race Condition

The timestamp was being set AFTER `startMonitoring()`:

```swift
// ScreenTimeService.swift (BEFORE fix)
try deviceActivityCenter.startMonitoring(...)  // Events start arriving immediately!
// ... some debug prints ...
sharedDefaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")  // TOO LATE
```

**The race window:**
1. `startMonitoring()` called → extension starts receiving catch-up events
2. Events for min 45, 46, 47 arrive immediately (within first few ms)
3. Extension checks `restartTimestamp` but it's still `0` (not yet written)
4. Early phantom check: `if timeSinceRestart < 55 && restartTimestamp > 0` → fails because `restartTimestamp == 0`
5. Events pass to threshold gate, Case 3 (progressive) records them as valid usage
6. Main app finally writes `monitoring_restart_timestamp`
7. Subsequent events are blocked, but damage is done

## Fix Applied

### 1. ScreenTimeService.swift (line ~2288)

Moved timestamp write BEFORE `startMonitoring()`:

```swift
// CRITICAL: Set restart timestamp BEFORE starting monitoring
// This closes the race window where events could arrive before the timestamp is set
if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
    sharedDefaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")
}

try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)
```

### 2. DeviceActivityMonitorExtension.swift (line ~44)

Added fallback in `init()` for edge cases:

```swift
override nonisolated init() {
    super.init()
    if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
        defaults.set(true, forKey: "extension_initialized_flag")
        defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")

        // Fallback: ensure restart timestamp exists to prevent phantom events
        if defaults.double(forKey: "monitoring_restart_timestamp") == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")
        }
    }
}
```

## Protection Layers Summary

The system now has 5 layers of defense:

| Layer | Mechanism | Location | Time Window |
|-------|-----------|----------|-------------|
| **Layer 1** | Early phantom check (restartTimestamp guard) | Lines 249-260 | 55 seconds after restart |
| **Layer 2** | Day rollover protection | Lines 263-302 | Resets lastThreshold on new day |
| **Layer 3** | Threshold gate (3-case logic) | Lines 327-363 | Duplicate/decrease/progress checks |
| **Layer 4** | Rapid-fire detection | Line 345 | 30 seconds between same-app events |
| **Layer 5** | Sanity check | Lines 310-317 | Corrupted state recovery |

## Verification

1. Build and deploy to device
2. Use apps to accumulate usage
3. Trigger restart (change app selection)
4. Check logs - should see `🕐 Set monitoring_restart_timestamp BEFORE startMonitoring`
5. ALL catch-up events should show `PHANTOM_BLOCKED_EARLY`
6. Verify hourly totals don't increase during restart
