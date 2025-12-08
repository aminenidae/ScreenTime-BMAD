# Reward Time Calculation Fix

**Date:** 2025-11-19
**Status:** ✅ FIXED - Build Succeeded

---

## Problem

The "Reward Earned" circle was showing the same value as "Learning Goal" (74/10m).

**Cause:** I mistakenly copied the learning time to both circles when fixing the data source issue.

---

## Solution

Changed `rewardTimeMinutes` to calculate **earned reward time** based on current learning progress and the challenge's reward ratio.

---

## Code Change

**File:** `ChildChallengesTabView.swift`
**Lines:** 289-308

**BEFORE (Wrong - showed learning time):**
```swift
private var rewardTimeMinutes: Int {
    guard let firstChallenge = viewModel.activeChallenges.first,
          let challengeID = firstChallenge.challengeID,
          let progress = viewModel.challengeProgress[challengeID] else {
        return 0
    }
    return Int(progress.currentValue) // ❌ Just copying learning time
}
```

**AFTER (Fixed - calculates reward time):**
```swift
private var rewardTimeMinutes: Int {
    guard let firstChallenge = viewModel.activeChallenges.first,
          let challengeID = firstChallenge.challengeID,
          let progress = viewModel.challengeProgress[challengeID] else {
        return 0
    }

    // Apply reward ratio to current learning progress
    let currentLearningMinutes = Int(progress.currentValue)
    let bonusPercentage = Int(firstChallenge.bonusPercentage)
    let ratio = firstChallenge.effectiveRewardRatio

    let earnedReward = ratio.rewardMinutes(
        forLearningMinutes: currentLearningMinutes,
        bonusPercentage: bonusPercentage
    )

    return Int(round(earnedReward))
}
```

---

## How It Works

### Reward Calculation Formula
1. Get **current learning progress** from ChallengeProgress (e.g., 74 minutes)
2. Get **reward ratio** from challenge (e.g., 1:1)
3. Get **bonus percentage** from challenge (e.g., 0%)
4. Apply formula: `ratio.rewardMinutes(forLearningMinutes: 74, bonusPercentage: 0)`
5. Round the result

### Example
- **Learning completed:** 74 minutes
- **Reward ratio:** 1:1 (1 minute of reward per 1 minute of learning)
- **Bonus:** 0%
- **Result:** 74 minutes of reward earned

If the ratio was 1:2 (1 learning : 2 reward):
- **Learning completed:** 74 minutes
- **Reward ratio:** 1:2
- **Result:** 148 minutes of reward earned (74 × 2)

---

## Expected UI After Fix

### Quest Central "Today's Progress"
- **Learning Goal:** 74/10m (100%) ← From ChallengeProgress.currentValue
- **Reward Earned:** 74/10m (100%) ← Calculated from current progress × reward ratio

---

## Build Status

```
** BUILD SUCCEEDED **
```

---

## Testing

Deploy and verify:
- [ ] "Learning Goal" shows learning time (e.g., 74m)
- [ ] "Reward Earned" shows calculated reward time based on ratio (e.g., 74m for 1:1, 148m for 1:2)
- [ ] Both values update correctly as learning progress increases

---

**Fix Complete:** 2025-11-19
**Ready for Testing:** ✅ Yes
