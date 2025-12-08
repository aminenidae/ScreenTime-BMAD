/# Plan: Protect Extension Usage Data (Read-Only)

## Problem Statement
The main app currently writes to extension usage keys (`usage_{appID}_today`) in two places:
1. **Stale data cleanup** (ScreenTimeService.swift:1179) - clears extension data when reset timestamp is old
2. **Force reset** (UsagePersistence.swift:481) - clears extension data during manual reset

This creates race conditions and potential data corruption.

## Key Insight
The extension **already handles its own day rollover** (DeviceActivityMonitorExtension.swift:144-167):
```swift
if lastReset < startOfToday {
    resetAllDailyCounters(...)  // Extension resets itself
}
```

So the main app doesn't NEED to clear extension data - it just needs to **handle stale data correctly on the read side**.

---

## Solution: Read-Only Extension Data with Sync Baselines

### Principle
- Extension data is **source of truth**, never modified by main app
- Main app tracks **sync baselines** to handle resets without touching extension
- All day rollover logic stays in extension

### New Concept: Sync Baseline
Instead of clearing extension data, we track "what value to ignore":

```swift
// New keys in UsagePersistence (NOT in extension namespace)
sync_baseline_{appID}_value: Int      // Extension value at time of reset
sync_baseline_{appID}_timestamp: Date // When baseline was set
```

**Sync formula:**
```swift
effectiveUsage = max(0, extensionToday - baseline)
```

---

## Changes Required

### Change 1: Remove Stale Data Cleanup Write
**File:** `ScreenTimeService.swift` (around line 1179)

**Before:**
```swift
if extensionResetTimestamp < startOfToday {
    defaults.set(0, forKey: todayKey)       // ← WRITES
    defaults.set(startOfToday, forKey: resetKey)  // ← WRITES
}
```

**After:**
```swift
if extensionResetTimestamp < startOfToday {
    // Extension hasn't reset yet - treat as 0 but DON'T modify extension
    #if DEBUG
    print("[ScreenTimeService] Extension data stale for \(logicalID) - treating as 0")
    #endif
    continue  // Skip this app in sync, extension will self-reset on next event
}
```

**Rationale:** Extension will reset itself when next threshold fires. Main app doesn't need to intervene.

---

### Change 2: Replace Force Reset Write with Baseline
**File:** `UsagePersistence.swift` (around line 481)

**Before:**
```swift
let todayKey = "usage_\(logicalID)_today"
userDefaults?.set(0, forKey: todayKey)  // ← WRITES TO EXTENSION
```

**After:**
```swift
// Set baseline to current extension value instead of clearing it
let todayKey = "usage_\(logicalID)_today"
let currentExtensionValue = userDefaults?.integer(forKey: todayKey) ?? 0
let baselineKey = "sync_baseline_\(logicalID)_value"
let baselineTimestampKey = "sync_baseline_\(logicalID)_timestamp"
userDefaults?.set(currentExtensionValue, forKey: baselineKey)
userDefaults?.set(Date().timeIntervalSince1970, forKey: baselineTimestampKey)
print("[UsagePersistence] 🔧 Set sync baseline for \(logicalID): \(currentExtensionValue)s")
```

---

### Change 3: Update Sync Logic to Use Baseline
**File:** `ScreenTimeService.swift` - `readExtensionUsageData()`

**Before:**
```swift
let todaySeconds = defaults.integer(forKey: todayKey)
// Use todaySeconds directly
```

**After:**
```swift
let todaySeconds = defaults.integer(forKey: todayKey)
let baselineKey = "sync_baseline_\(logicalID)_value"
let baselineTimestampKey = "sync_baseline_\(logicalID)_timestamp"
let baseline = defaults.integer(forKey: baselineKey)
let baselineTimestamp = defaults.double(forKey: baselineTimestampKey)

// Only apply baseline if it was set today
let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
let effectiveBaseline = baselineTimestamp >= startOfToday ? baseline : 0

let effectiveToday = max(0, todaySeconds - effectiveBaseline)
// Use effectiveToday for sync
```

---

### Change 4: Clear Baseline on Day Rollover
**File:** `UsagePersistence.swift` - `resetDailyCounters()` or `handleMidnightTransition()`

Add baseline cleanup when day changes:
```swift
// Clear baselines on new day (they're no longer relevant)
let baselineKey = "sync_baseline_\(logicalID)_value"
let baselineTimestampKey = "sync_baseline_\(logicalID)_timestamp"
userDefaults?.removeObject(forKey: baselineKey)
userDefaults?.removeObject(forKey: baselineTimestampKey)
```

---

## Summary of Files to Modify

| File | Change | Purpose |
|------|--------|---------|
| `ScreenTimeService.swift:1179` | Remove write, add skip logic | Stop clearing stale extension data |
| `UsagePersistence.swift:481` | Replace write with baseline set | Stop clearing extension on force reset |
| `ScreenTimeService.swift` (readExtensionUsageData) | Add baseline subtraction | Use baseline in sync calculation |
| `UsagePersistence.swift` (day rollover) | Clear baselines | Clean up old baselines |

---

## Benefits

1. **Extension data is immutable** from main app perspective
2. **No race conditions** - main app can't corrupt extension data
3. **Extension self-heals** - it resets itself on next threshold fire
4. **Force reset still works** - baseline mechanism achieves same effect without modifying extension
5. **Audit trail** - baselines can be logged for debugging

---

## Risk Analysis

| Risk | Mitigation |
|------|------------|
| Baseline not cleared on day rollover | Check baselineTimestamp against startOfToday |
| Multiple force resets same day | Each sets new baseline, always works |
| Extension resets before main app reads | baseline=0 by default, effectiveToday = extensionToday |

---

## Testing Plan

1. **Normal usage:** Verify sync still works without baseline
2. **Force reset:** Verify baseline is set, usage shows 0 after reset
3. **Post-reset usage:** Verify new usage (extension - baseline) is tracked correctly
4. **Day rollover:** Verify baseline cleared, new day starts fresh
5. **Stale data:** Verify stale extension data is ignored (not cleared)

---

## Example Flow

```
Time    Extension    Baseline    Effective
─────────────────────────────────────────
10:00   120s         0           120s      (normal sync)
10:05   [FORCE RESET]
        120s         120s        0s        (baseline set)
10:10   180s         120s        60s       (new usage tracked)
─────────────────────────────────────────
Next day: baseline cleared, extension resets itself
```
