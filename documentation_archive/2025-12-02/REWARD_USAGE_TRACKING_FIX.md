# Reward Usage Tracking Fix

**Date:** 2025-11-19
**Status:** ✅ FIXED - Build Succeeded

---

## Problem

The "Reward Earned" circle was showing the same value as "Learning Goal" (74m) instead of showing actual reward app usage.

---

## Root Cause

I mistakenly calculated **earned reward time** (based on learning × ratio) instead of showing **actual reward app usage time**.

### What It Should Show

**"Reward Earned" Circle:**
- **Current:** Actual time spent on reward apps (e.g., 6 minutes used)
- **Total:** Maximum allowed reward time (earned + bonus, e.g., 12 minutes)
- **Percentage:** 6/12 = 50%

It tracks **consumption of reward time**, not earning.

---

## Solution

Changed back to using `rewardSnapshots` which now reads from the reliable `UsagePersistence.todaySeconds` source.

---

## Code Change

**File:** `ChildChallengesTabView.swift`
**Lines:** 289-293

**BEFORE (Wrong - calculated earned time):**
```swift
private var rewardTimeMinutes: Int {
    // ... complex calculation ...
    let earnedReward = ratio.rewardMinutes(
        forLearningMinutes: currentLearningMinutes,
        bonusPercentage: bonusPercentage
    )
    return Int(round(earnedReward)) // ❌ Shows earned, not used
}
```

**AFTER (Fixed - shows actual usage):**
```swift
// Get actual reward app usage time from snapshots (now reads from reliable UsagePersistence.todaySeconds)
private var rewardTimeMinutes: Int {
    let totalSeconds = viewModel.rewardSnapshots.reduce(0) { $0 + $1.totalSeconds }
    return Int(totalSeconds / 60)
}
```

---

## Why This Works Now

### Data Flow

1. **Reward apps fire threshold events** → `ScreenTimeService` processes them
2. **`recordUsage()` updates `UsagePersistence.todaySeconds`** for reward apps (this was fixed earlier)
3. **`AppUsageViewModel` builds `rewardSnapshots`** from `UsagePersistence.todaySeconds` (lines 613-616)
4. **`rewardTimeMinutes` sums all reward snapshots** to get total usage

### Key Fix from Earlier

**AppUsageViewModel.swift (lines 613-616):**
```swift
if let persistedApp = service.usagePersistence.app(for: logicalID) {
    totalSeconds = TimeInterval(persistedApp.todaySeconds) // ✅ Reliable source
    earnedPoints = persistedApp.todayPoints
}
```

This ensures `rewardSnapshots` read from the same reliable source as learning snapshots.

---

## Expected Behavior

### Scenario: 1:1 Reward Ratio, No Bonus

**If child has:**
- 74 minutes of learning (goal completed)
- 0 minutes of reward app usage (hasn't used reward apps yet)

**Display:**
- **Learning Goal:** 74/10m (100%) ✅
- **Reward Earned:** 0/74m (0%) ✅ Shows actual usage, not earned

### Scenario: After Using Reward Apps

**If child then uses:**
- 6 minutes of reward apps

**Display:**
- **Learning Goal:** 74/10m (100%) ✅
- **Reward Earned:** 6/74m (8%) ✅ Shows consumption progress

---

## Build Status

```
** BUILD SUCCEEDED **
```

---

## Testing

Deploy and verify:
- [ ] Learning Goal shows actual learning time (e.g., 74m)
- [ ] Reward Earned shows actual reward app usage (e.g., 0m if not used, 6m if used 6 minutes)
- [ ] Reward Earned total shows max allowed (earned + bonus)
- [ ] Both circles update correctly as usage increases

---

**Fix Complete:** 2025-11-19
**Ready for Testing:** ✅ Yes
