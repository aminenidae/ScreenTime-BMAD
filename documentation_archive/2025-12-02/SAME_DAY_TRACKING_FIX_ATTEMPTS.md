# Same-Day Usage Tracking Fix Attempts

**Date:** 2025-11-26
**Stable Commit:** v1.0.0-Beta (`1e9b46c`)
**Branch:** fix/usage-tracking-accuracy

---

## Problem Statement

Apps with existing usage **from TODAY** don't receive threshold events when the main app is relaunched.

**Example:**
1. App has 91 min usage from earlier today
2. Close main app, use learning app for 6 minutes
3. Relaunch main app → only 3 minutes recorded instead of 6

**Root Cause Theory:**
When `scheduleActivity()` is called, iOS re-registers thresholds 1-240. But iOS sees the app already has 91+ min cumulative usage, so thresholds 1-91 are "already exceeded" and won't fire. Only threshold 92+ will fire when usage reaches that point.

---

## Fix Attempts & Results

### Attempt 1: Preserve Monitoring (DON'T restart if already active)

**Theory:** If iOS already has monitoring registered (`deviceActivityCenter.activities` contains our activity), don't call `scheduleActivity()` to preserve threshold state.

**Code Change:**
```swift
let isAlreadyMonitoring = deviceActivityCenter.activities.contains(activityName)
if isAlreadyMonitoring && !isNewDay {
    // DON'T restart - preserve threshold state
    isMonitoring = true
} else {
    // Restart needed
    try scheduleActivity()
}
```

**Result:** ❌ FAILED
- NO `eventDidReachThreshold` events fired at all
- Usage stuck at previous value
- Extension was alive (heartbeat updating) but receiving no events

**Learning:** Even if the activity is registered with iOS, the EVENTS within it can become stale. `deviceActivityCenter.activities` only tells you if the activity is registered, NOT if events are valid.

---

### Attempt 2: ALWAYS call scheduleActivity() to refresh events

**Theory:** The extension's cascade protection (`skip if usage >= threshold`) should handle rapid-fire events gracefully, so we can safely restart monitoring every time.

**Code Change:**
```swift
// ALWAYS call scheduleActivity() to refresh event registrations
deviceActivityCenter.stopMonitoring([activityName])
try scheduleActivity()
```

**Result:** ⚠️ PARTIAL SUCCESS
- Thresholds now continue correctly (105, 106, 107... not reset to 1)
- BUT iOS only fired ~50% of expected events
- User ran 6 minutes, only 3 events fired
- Event timing was irregular (14s gap, then 92s gap)

**Learning:** iOS DeviceActivityMonitor is inherently unreliable - it doesn't guarantee every threshold fires. This is an iOS limitation, not our code.

---

### Attempt 3: DeviceActivityReport polling (previously tried)

**Theory:** Use DeviceActivityReport to read actual cumulative usage and catch missed threshold events.

**Result:** ❌ NOT VIABLE
- DeviceActivityReport is a **UI-only view extension**
- It only updates when the view is visible in the main app
- Does NOT work in background - cannot catch up on missed events when main app is closed

**Code Evidence:**
```swift
// MARK: - Report-based tracking (DISABLED - doesn't work in background)
// DeviceActivityReport is a UI-only view extension, won't update in background
```

---

## Key Learnings

1. **`deviceActivityCenter.activities`** only shows if activity is registered, NOT if events are valid/fresh

2. **iOS DeviceActivityMonitor is unreliable** - threshold events can be:
   - Batched (multiple fire close together)
   - Delayed (irregular timing)
   - Skipped entirely (~50% miss rate observed)

3. **DeviceActivityReport is UI-only** - cannot be used for background tracking

4. **Restarting monitoring clears iOS's internal threshold state** - but NOT restarting can leave stale event registrations

5. **The cascade protection works** - extension's `skip if usage >= threshold` logic correctly handles rapid-fire events

---

## What Works (Stable v1.0.0-Beta)

- New app tracking (first time) ✅
- 60-second threshold events fire reliably for new apps ✅
- Darwin notifications deliver correctly ✅
- Crash recovery (restart monitoring after app killed) ✅

## What Doesn't Work

- Same-day existing usage: events stop firing after app relaunch
- iOS threshold firing is ~50% reliable for existing usage

---

## Possible Future Approaches (NOT YET TRIED)

### Option A: Hybrid approach
- Keep threshold-based tracking as primary
- Add a "catch-up" mechanism when main app returns to foreground
- Query extension's persisted usage directly (not via DeviceActivityReport)

### Option B: More frequent thresholds
- Register thresholds every 30 seconds instead of 60
- More chances for iOS to fire at least some events
- Risk: may hit iOS event limits

### Option C: Accept iOS limitation
- Document that same-day tracking has ~50% accuracy after app relaunch
- Rely on extension's direct persistence (which IS accurate)
- Sync from extension's UserDefaults when main app opens

### Option D: Investigate iOS threshold registration
- Log exactly which thresholds are being registered
- Check if iOS has limits on threshold count per activity
- Test with fewer apps to see if event reliability improves

---

## Files Modified During Attempts

| File | Changes Made | Reverted |
|------|--------------|----------|
| `ScreenTimeService.swift` | `restoreFromPersistence()` - conditional vs always restart | ✅ Yes |
| `AppUsageViewModel.swift` | Removed monitoring restart from `updateSnapshots()` | ✅ Yes |

---

## Test Data Reference

**Before test (v1.0.0-Beta):**
- Unknown App 0: 104 min (6240s)

**After 6-minute test:**
- Expected: 110 min (6600s)
- Actual: 107 min (6420s) - only 3 events fired

**Event timestamps:**
| Event | Time | Usage | Gap |
|-------|------|-------|-----|
| 1 | 05:20:43 | 105m | - |
| 2 | 05:20:57 | 106m | 14s |
| 3 | 05:22:29 | 107m | 92s |

---

## Extension Log Key

The extension writes to UserDefaults key `extension_debug_log`. Check this to see if `eventDidReachThreshold` is being called by iOS.

If no `eventDidReachThreshold` in extension log → iOS isn't firing events
If events in extension log but not in main app → Darwin notification issue
