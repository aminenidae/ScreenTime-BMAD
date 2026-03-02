# Shield Management Fix

**Date**: 2026-03-01
**Branch**: `feature/sliding-window-thresholds`

---

## Problems Fixed

Three shield management failures were identified and resolved:

1. **New day (Bug 1)**: After a child completes their learning goal (shield lifted), the reward app stays accessible the next morning — no shield is re-applied at midnight.

2. **Shield not lifting (Bug 2, investigated, resolved)**: Initial concern that the extension couldn't lift shields autonomously. Confirmed via device testing that the extension's direct `ManagedSettingsStore` writes work correctly — the shield lifts automatically when the learning goal is met.

3. **0-minute daily limit not enforced (Bug 3)**: When the parent sets a reward app's daily limit to 0 minutes for a day, the child can still access the reward app after completing the learning goal. The `dailyLimit = 0` case was not treated as an unconditional block.

---

## Bug 1 — New Day (Shield Not Re-Applied at Midnight)

### Root Cause

At midnight, `intervalDidStart()` fires in the `DeviceActivityMonitor` extension and calls two functions:

```swift
checkAndUpdateShields()               // Only LIFTS shields (when goal IS met)
checkAndBlockIfRewardTimeExhausted()  // Blocks for: downtime, daily limit, reward time exhausted
```

`checkAndBlockIfRewardTimeExhausted()` had three checks:

| # | Condition | Action |
|---|-----------|--------|
| 0 | Outside allowed time window (downtime) | Block |
| 1 | Daily reward limit reached | Block |
| 2 | Reward time exhausted (`earnedMinutes > 0 && usageMinutes >= earnedMinutes`) | Block |

At midnight, **Check 2 never fires** because `earnedMinutes = 0` (no learning has been done today yet). The **"learning goal not yet met"** case was simply absent.

### Fix

Added **Check 2: Learning goal not met → re-block** between the daily limit check and the reward time check in `checkAndBlockIfRewardTimeExhausted()`.

**File**: `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`

**New priority order:**
1. Downtime → block, `continue`
2. Daily limit exceeded → block, `continue`
3. **Learning goal not yet met → block, `continue`** ← new
4. Reward time exhausted → block (only reached when goal IS met but time is used up)

```swift
// Check 2: Learning goal not yet met — re-block at start of new day
let isGoalMet = checkGoalMet(goalConfig: goalConfig, defaults: defaults)
if !isGoalMet {
    guard let token = try? PropertyListDecoder().decode(
        ApplicationToken.self,
        from: goalConfig.rewardAppTokenData
    ) else { continue }

    var currentShields = managedSettingsStore.shield.applications ?? Set()
    if !currentShields.contains(token) {
        currentShields.insert(token)
        managedSettingsStore.shield.applications = currentShields
        recordBlockState(rewardAppLogicalID: goalConfig.rewardAppLogicalID, defaults: defaults)
        persistBlockingReason(tokenHash: goalConfig.rewardAppLogicalID, reasonType: "learningGoal", ...)
        debugLog("LEARNING_GOAL_BLOCK: ... goal not met — re-applying shield")
    }
    continue  // skip reward time check — earnedMinutes would be 0 anyway
}
```

### When This Fires

| Trigger | Behavior |
|---------|----------|
| `intervalDidStart()` at midnight | All reward apps with incomplete goals get re-blocked |
| Any threshold event during the day | Keeps reward apps blocked until goal is met |
| After `checkAndUpdateShields()` lifts the shield (goal met) | Check 2 sees `isGoalMet = true` → falls through to reward time check |

---

## Bug 3 — 0-Minute Daily Limit Not Enforced After Goal Completion

### Root Cause

When a parent sets `dailyLimit = 0` for a day, the existing **Check 1** in `checkAndBlockIfRewardTimeExhausted()` relied on `usageMinutes >= dailyLimit` (i.e., `0 >= 0`) to detect the block. This is semantically fragile:

- `dailyLimit = 0` means **"app is blocked for the entire day"** — an unconditional rule
- Check 1's condition `usageMinutes >= dailyLimit` was designed for **"you've used up your quota"**
- If extension config data is stale (e.g., `dailyLimitMinutes` fallback returns 60 instead of 0), Check 1 becomes `0 >= 60 = false` → doesn't fire → Check 2 (goal met, falls through) → Check 3 (earnedMinutes=0, doesn't fire) → **shield stays lifted**

The same fragility existed in the main app's `BlockingCoordinator.evaluateBlockingState()`: if `checkDailyLimit()` was bypassed or returned a wrong value, and the learning goal was met, the app could be unblocked.

### Fix

Made `dailyLimit == 0` an **explicit, unconditional block** at the absolute highest priority in both the extension and the main app.

**Files modified:**
1. `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
2. `ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift`

#### Extension — Check -1 (before downtime)

Added at the TOP of `checkAndBlockIfRewardTimeExhausted()`, before Check 0 (downtime):

```swift
// Check -1 (Absolute Highest Priority): App completely blocked for today (dailyLimit == 0)
let zeroLimitCheck = goalConfig.todayDailyLimit()
if zeroLimitCheck == 0 {
    // ensure shield is applied
    if !currentShields.contains(token) {
        currentShields.insert(token)
        managedSettingsStore.shield.applications = currentShields
        recordBlockState(...)
        persistBlockingReason(...reasonType: "dailyLimitReached"...)
        debugLog("DAILY_ZERO_BLOCK: ... dailyLimit=0 — app blocked entire day")
    }
    continue  // skip all other checks
}
```

Why before downtime? Downtime only blocks during specific time windows. `dailyLimit=0` should block ALL day including inside the allowed time window.

#### Main App — `evaluateBlockingState()` short-circuit

Added AFTER the logicalID guard, BEFORE all other checks:

```swift
// Short-circuit: dailyLimit == 0 means app is completely blocked for today.
if let config = scheduleService.getSchedule(for: logicalID),
   config.dailyLimits.todayLimit == 0 {
    return BlockingDecision(
        shouldBlock: true,
        primaryReason: .dailyLimitReached,
        allActiveReasons: [.dailyLimitReached],
        dailyLimitMinutes: 0,
        usedMinutes: 0
    )
}
```

This prevents `checkLearningGoal()`, `checkAvailableMinutes()`, or any other path from unblocking an app that has `dailyLimit = 0`.

### Updated Priority Order in Extension

| Priority | Check | Condition | Action |
|----------|-------|-----------|--------|
| -1 | Zero limit | `dailyLimit == 0` | Block (unconditional) |
| 0 | Downtime | Outside allowed time window | Block |
| 1 | Daily limit exceeded | `dailyLimit < 1440 && usageMinutes >= dailyLimit` | Block |
| 2 | Learning goal not met | `!isGoalMet` | Block |
| 3 | Reward time exhausted | `earnedMinutes > 0 && usageMinutes >= earnedMinutes` | Block |

---

## What Was NOT Changed

- `checkAndUpdateShields()` — the existing `todayLimit == 0 → continue` guard (prevents lifting when limit=0) was already present and is sufficient.
- `AppScheduleService`, `DailyLimits`, `DailyLimitsPicker` — data model is correct.
- `syncGoalConfigsToExtension()` — config sync chain is correct.
- Shield lift behavior confirmed working via device test. Extension's direct `ManagedSettingsStore` writes persist correctly.
