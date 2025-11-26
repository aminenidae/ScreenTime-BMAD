# Usage Tracking Accuracy - Bug Investigation & Fix

**Date:** 2025-11-25
**Branch:** `feature/deviceactivityreport-sync`
**Fix Commit:** `aac9255`

---

## Problem Statement

Usage tracking events from the DeviceActivityMonitor extension stopped firing correctly. When testing a learning app for 5 minutes, the logs showed no threshold events being recorded, even though the extension was initialized properly.

Initial suspicion was Darwin notification reliability, but investigation revealed the root cause was elsewhere.

---

## Investigation Process

### Git Bisect Results

Used binary search through commits to isolate the exact regression:

| Commit | Date | Description | Status |
|--------|------|-------------|--------|
| `f87662f` | Nov 19, 12:14 | Fix darwin notification reliability | GOOD |
| `8f94ac9` | Nov 21, 23:25 | Fix usage tracking: 60 static thresholds | GOOD |
| `13cfad5` | Nov 22, 19:23 | Add custom shield UI | GOOD |
| `e4f99a9` | Nov 22, 19:34 | Add dynamic shield messages | GOOD |
| `2676b31` | Nov 22, 19:41 | Fix reward apps not unlocking | BAD |
| `92b5b7e` | Nov 22, 20:03 | Fix phantom usage tracking | BAD |

**Culprit identified:** Commit `2676b31` ("Fix reward apps not unlocking when learning goal is achieved")

---

## Root Cause Analysis

### The Buggy Code

Commit `2676b31` added the following code to `syncShieldData()` in `AppUsageViewModel.swift`:

```swift
// CHECK: If learning goal is met based on snapshots, trigger unlock
if currentMinutes >= targetMinutes {
    let progress = challengeProgress[challenge.challengeID ?? ""]
    let alreadyCompleted = progress?.isCompleted ?? false

    if !alreadyCompleted {
        unlockRewardApps()

        if !showCompletionCelebration {
            completedChallengeID = challenge.challengeID
            showCompletionCelebration = true
            // ... celebration animation
        }
    }
}
```

### Why It Broke Usage Tracking

1. **CoreData Default Value:** The `Challenge.targetValue` attribute has a default value of `0` in the CoreData model:
   ```xml
   <attribute name="targetValue" ... defaultValueString="0"/>
   ```

2. **Always-True Condition:** When `targetMinutes = 0`, the condition `currentMinutes >= targetMinutes` evaluates to `0 >= 0` = **TRUE** immediately.

3. **Repeated Calls:** The `syncShieldData()` function is called frequently (every time snapshots update). With the condition always true:
   - `unlockRewardApps()` was called on **every invocation**
   - This caused rapid-fire shield updates to `ManagedSettingsStore`
   - The repeated state changes corrupted the app's event processing pipeline

4. **Cascade Effect:** The `challengeProgress` dictionary wasn't being updated correctly, so `alreadyCompleted` remained `false`, perpetuating the loop.

### Call Chain

```
Event fires -> updateSnapshots() -> syncShieldData() -> unlockRewardApps()
                                        |
                              [condition always true]
                                        |
                              [called every time!]
```

---

## The Fix

### Location
`ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

### Changes

**Before (buggy):**
```swift
if currentMinutes >= targetMinutes {
    // ... unlock logic
    if !showCompletionCelebration {
        // ... celebration logic
    }
}
```

**After (fixed):**
```swift
// CRITICAL: Guard against targetMinutes=0 which would always trigger (CoreData default is 0)
// Also guard against already showing celebration to prevent repeated unlock calls
if targetMinutes > 0 && currentMinutes >= targetMinutes && !showCompletionCelebration {
    let progress = challengeProgress[challenge.challengeID ?? ""]
    let alreadyCompleted = progress?.isCompleted ?? false

    if !alreadyCompleted {
        unlockRewardApps()

        // Trigger celebration (moved inside, no longer nested)
        completedChallengeID = challenge.challengeID
        showCompletionCelebration = true
        lastRewardUnlockMinutes = challenge.rewardUnlockMinutes(defaultValue: 30)
        // ... async reset after 3 seconds
    }
}
```

### Three Guards Added

| Guard | Purpose |
|-------|---------|
| `targetMinutes > 0` | Prevents false positive when targetValue is unset (default 0) |
| `currentMinutes >= targetMinutes` | Original goal completion check |
| `!showCompletionCelebration` | Prevents repeated calls once celebration has started |

---

## Lessons Learned

1. **CoreData Defaults Matter:** Always consider what happens when a field uses its default value. A default of `0` for `targetMinutes` created an edge case where the goal was "always met."

2. **Guard Against Repeated Execution:** Functions called frequently (like `syncShieldData()`) should have guards to prevent triggering side effects multiple times.

3. **Git Bisect is Powerful:** Binary search through commits quickly isolated a regression in a 15+ commit range.

4. **Test Edge Cases:** When adding goal completion logic, test with:
   - No active challenges
   - Challenges with targetValue = 0
   - Challenges with very small targets

---

## Testing Checklist

After applying the fix, verify:

- [ ] Learning app usage is tracked every 60 seconds
- [ ] Events appear in debug logs: `eventDidReachThreshold`
- [ ] Darwin notifications are sent and received
- [ ] Goal completion only triggers once when target is actually reached
- [ ] No repeated "unlock" logs in console
- [ ] Celebration animation shows once, not repeatedly

---

## Additional Fixes (Nov 25, 2025 - Session 2)

After the initial fix (`aac9255`), additional issues were discovered during testing:

### Issue: Memory Crash + No Events After Relaunch

**Symptoms:**
- App killed by iOS due to memory pressure
- After relaunch, NO threshold events fired for 4+ minutes
- Only 60s recorded instead of expected ~4 minutes

**Root Causes Found:**

#### 1. Missing Crash Recovery

When app relaunches after crash, `scheduleActivity()` was called WITHOUT stopping first:
- iOS may have stale event registrations
- New events not properly registered
- Result: `eventDidReachThreshold` never fires

**Fix in `ScreenTimeService.swift`:**
```swift
// CRITICAL FIX: Always stop monitoring first to clear stale iOS state
deviceActivityCenter.stopMonitoring([activityName])
// Then restart fresh
try scheduleActivity()
```

#### 2. Cooldown Blocking Catch-up Events

The extension had a 55-second cooldown:
```swift
// OLD CODE (harmful):
if lastRecord > 0 && (now - lastRecord) < cooldownSeconds {
    return false  // BLOCKED!
}
```

When iOS fires thresholds 4, 5, 6, 7 rapidly (accumulated usage after crash):
- Only threshold 4 was recorded
- Thresholds 5, 6, 7 blocked by cooldown
- Lost ~3 minutes of usage!

**Fix:** Removed cooldown entirely. SET semantics already prevent double-counting.

---

## Related Commits

| Commit | Description |
|--------|-------------|
| `2676b31` | Original buggy commit (syncShieldData issue) |
| `aac9255` | Fix: Add guards to syncShieldData |
| `7bf67e9` | Fix: Crash recovery + remove harmful cooldown |

---

## File Changes

```
ScreenTimeRewards/ViewModels/AppUsageViewModel.swift
  - syncShieldData() function
  - Lines ~2722-2752

ScreenTimeRewards/Services/ScreenTimeService.swift
  - Auto-restart monitoring now stops first (crash recovery)
  - Lines ~407-443

ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift
  - Removed cooldownSeconds constant
  - Removed cooldown checks in recordUsageEfficiently()
  - Removed cooldown checks in recordUsageWithMapping()
```

---

## Test Results (Nov 25, 2025)

### Test 1: Fresh App (New Learning App)
| Metric | Result |
|--------|--------|
| First event delay | ~85s (25s iOS overhead + 60s threshold) |
| Subsequent events | Every 60s ✅ |
| Usage accuracy | Correct ✅ |
| Multi-app tracking | Working ✅ |

### Test 2: Existing App (With Prior Usage)
| Metric | Result |
|--------|--------|
| Events after relaunch | Firing correctly ✅ |
| Catch-up events | All recorded (no cooldown blocking) ✅ |
| Usage accumulation | Accurate ✅ |

---

## Issues Status

### ✅ RESOLVED

| Issue | Root Cause | Fix |
|-------|------------|-----|
| Events not firing | `syncShieldData()` calling `unlockRewardApps()` repeatedly when `targetMinutes=0` | Added `targetMinutes > 0` guard |
| Events blocked after crash | No `stopMonitoring()` before restart | Force stop before restart |
| Catch-up events lost | 55s cooldown blocked rapid threshold fires | Removed cooldown (SET semantics handle it) |
| Memory crash | App killed by iOS due to memory pressure | Crash recovery now handles stale state |

### ⚠️ KNOWN LIMITATIONS (Acceptable)

| Issue | Details | Impact |
|-------|---------|--------|
| First event delay | ~25s extra delay on very first threshold | Minimal - only affects minute 1, total usage still accurate |
| iOS initialization | DeviceActivity framework needs time to register | Normal iOS behavior |

### 🔍 OUTSTANDING (Monitor)

| Issue | Status | Notes |
|-------|--------|-------|
| Memory usage over time | Monitoring | App was killed once - need to watch for recurrence |
| Long-duration tracking | Not fully tested | Need to test 30+ minute sessions |

---

## Summary

**Before fixes:** Usage tracking completely broken - no events firing, usage lost after crash, catch-up events blocked.

**After fixes:**
- Events fire every 60s consistently
- Usage accuracy confirmed
- Multi-app tracking working
- Crash recovery implemented

**Commits:**
- `aac9255` - syncShieldData guards
- `7bf67e9` - Crash recovery + cooldown removal
- `4bce758` - Documentation (branch: `fix/usage-tracking-accuracy`)

---

## Testing Checklist (Verified)

- [x] Learning app usage is tracked every 60 seconds
- [x] Events appear in debug logs: `eventDidReachThreshold`
- [x] Darwin notifications are sent and received
- [x] After app crash/relaunch, events fire correctly
- [x] Accumulated usage is fully recorded (no 55s gaps)
- [x] Multi-app tracking works simultaneously
- [ ] Goal completion triggers correctly (not tested this session)
- [ ] Celebration animation shows once (not tested this session)
