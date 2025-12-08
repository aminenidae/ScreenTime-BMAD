# Usage Doubling Bug Fix

**Date:** 2025-12-01
**Status:** Root cause identified, fix ready to implement

## Bug Summary

When a user adds a new app to the learning or reward list, the usage of **existing** apps gets doubled. Both `todaySeconds` and `totalSeconds` double.

### Symptoms
- User has App A with 4 minutes (240 seconds) tracked
- User adds App B to the list
- App A's usage jumps to 7 minutes (420 seconds) - an increase of ~180 seconds

---

## Investigation Timeline

### Phase 1: Initial Theory (DISPROVEN)
- **Theory:** Extension's deduplication check was failing
- **Result:** No "DEDUP CHECK" logs appeared in the extension during the bug
- **Conclusion:** Extension wasn't even firing - the bug was elsewhere

### Phase 2: Main App Investigation
- Added DEBUG-DOUBLE logging to `configureMonitoring()` flow
- **Finding:** Persistence values in BEFORE/AFTER configureMonitoring were IDENTICAL
- The doubling wasn't happening in the save loop

### Phase 3: Extension Catch-up Events (ROOT CAUSE FOUND)
- DiagnosticPolling showed extension values jumped from 240s to 420s
- Found sequence: `MONITORING RESTART` → `stopMonitoring` → `scheduleActivity` → `eventDidReachThreshold`
- **The extension WAS firing, but with new event names after monitoring restart**

---

## Root Cause

### The Problem: Event Index Reassignment

When a new app is added, `configureMonitoring()` rebuilds the `monitoredEvents` dictionary. The `eventIndex` counter starts at 0 and increments for each app, but the **order of apps can change** when new apps are added.

**Location:** `ScreenTimeService.swift` lines 758-798

```swift
var eventIndex = 0
for app in applications {
    for minuteNumber in startMinute...endMinute {
        let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex).min.\(minuteNumber)")
        // ...
    }
    eventIndex += 1
}
```

### Example Scenario

**Before adding new app:**
- App A has `eventIndex=0` → events: `usage.app.0.min.1`, `usage.app.0.min.2`, etc.
- Extension stores: `usage_<appA_logicalID>_lastThreshold = 240` (4 minutes reached)

**After adding App B:**
- App B gets `eventIndex=0` → events: `usage.app.0.min.1`, `usage.app.0.min.2`, etc.
- App A gets `eventIndex=1` → events: `usage.app.1.min.1`, `usage.app.1.min.2`, etc.
- **The mapping `map_usage.app.0.min.4_id` now points to App B, not App A!**

### Why Usage Doubles

When monitoring restarts, iOS fires catch-up threshold events for the **new** event names:

1. Event `usage.app.1.min.1` fires for App A (new event name after reindex)
2. Extension reads mapping: `map_usage.app.1.min.1_id` → App A's logicalID
3. Extension checks: `threshold=60s`, `lastThreshold=240s`
4. Since `60 < 240`, the dedup logic at line 196 treats this as a "NEW SESSION"
5. Extension adds 60 seconds (incorrectly - this threshold was already counted under the old event name)
6. This repeats for thresholds 2, 3, 4... adding 180-240 seconds

**Relevant extension code** (`DeviceActivityMonitorExtension.swift` lines 195-204):
```swift
// Three cases:
// 1. threshold > lastThreshold: normal progression, add 60s
// 2. threshold < lastThreshold: NEW SESSION (iOS reset counter), add 60s  // <-- BUG TRIGGER
// 3. threshold == lastThreshold: exact duplicate, skip

if thresholdSeconds == lastThreshold {
    return false
}

// Add exactly 60s (for both > and < cases)
let newToday = currentToday + 60
```

---

## The Fix (Two Parts)

### Part 1: Stable Event Names (ScreenTimeService.swift)

Instead of using a sequential `eventIndex` that changes when apps are added/removed, use a hash of the app's `logicalID` which is stable.

**Change in `ScreenTimeService.swift` line 787:**

```swift
// OLD (buggy):
let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex).min.\(minuteNumber)")

// NEW (fixed):
let appHash = abs(app.logicalID.hashValue) % 1_000_000  // 6-digit stable hash
let eventName = DeviceActivityEvent.Name("usage.app.\(appHash).min.\(minuteNumber)")
```

### Part 2: Fix Extension Dedup Logic (DeviceActivityMonitorExtension.swift)

Even with stable event names, iOS re-fires ALL thresholds when monitoring restarts. The extension was incorrectly treating `threshold < lastThreshold` as a "new session" and adding 60s.

**Change in `DeviceActivityMonitorExtension.swift` lines 194-203:**

```swift
// OLD (buggy):
// Case 2: threshold < lastThreshold: NEW SESSION (iOS reset counter), add 60s
if thresholdSeconds == lastThreshold {
    return false  // Only skip exact duplicates
}
// Add exactly 60s (for both > and < cases)

// NEW (fixed):
// Case 2: threshold <= lastThreshold → already counted OR catch-up after restart, SKIP
if thresholdSeconds <= lastThreshold {
    return false  // Skip ALL thresholds that don't increase
}
// Only add 60s when threshold strictly increases
```

### Why Both Fixes Are Needed

1. **Part 1 (hash)**: Ensures the same app always has the same event names
2. **Part 2 (dedup)**: Prevents catch-up thresholds from being double-counted

Without Part 2, even with stable event names, iOS would re-fire thresholds 1, 2, 3... after a restart, and the extension would count them as "new session" usage.

### Files Modified

| File | Lines | Change |
|------|-------|--------|
| `ScreenTimeService.swift` | 787 | Use `logicalID.hashValue` instead of `eventIndex` |
| `ScreenTimeService.swift` | 758, 798 | Remove unused `eventIndex` variable |
| `DeviceActivityMonitorExtension.swift` | 194-203 | Skip thresholds <= lastThreshold |

---

## Cleanup After Fix

Remove debug logging added during investigation:

1. **AppUsageViewModel.swift** - Remove DEBUG-DOUBLE logging blocks (around lines 912-942)
2. **ScreenTimeService.swift** - Remove DEBUG-DOUBLE logging (lines 713-716)

---

## Testing Plan

1. Build and run the app
2. Add App A as a learning app
3. Use App A for 3-4 minutes, verify tracking works
4. Add App B as a learning or reward app
5. **Verify App A's usage did NOT change** (this is the bug fix)
6. Continue using App A, verify tracking still works
7. Remove App B, verify App A's usage still correct

---

## Risk Assessment

**Low risk** - The change only affects event naming, not the tracking logic itself.

**Edge case:** Hash collisions (two apps with same hash) - extremely unlikely with 6-digit hash and typical number of apps (<20). If it occurs, events would be shared between apps, but wouldn't cause data loss.

**Rollback:** If issues arise, revert to `eventIndex` and implement alternative fix: preserve `lastThreshold` values across monitoring restarts by reading them before stop and writing them after start.
