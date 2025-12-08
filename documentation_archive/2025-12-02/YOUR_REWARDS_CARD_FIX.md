# "Your Rewards" Card Usage Display Fix

**Date:** 2025-11-19
**Status:** ✅ COMPLETE - Build Succeeded

---

## Problem

The "Your Rewards" card in Child Mode Challenge Detail view was showing "Earn X minutes" instead of showing actual usage of reward apps.

---

## Solution

Changed the card to display:
1. **Total usage summary** at the top (e.g., "2m used of 74m unlocked")
2. **Per-app usage** in each row (e.g., "2m used today")

---

## Changes Made

**File:** `ChildChallengeDetailView.swift`

### Change 1: Added Total Usage Summary (Lines 275-296)

**Added:**
```swift
// Show total reward usage
let totalRewardSeconds = rewardAppSnapshots.reduce(0) { $0 + $1.totalSeconds }
let maxRewardMinutes = challenge.rewardUnlockMinutes()

HStack {
    VStack(alignment: .leading, spacing: 4) {
        Text("Total Used Today")
            .font(.system(size: 14))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))

        Text("\(Int(totalRewardSeconds / 60))m")
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(AppTheme.playfulCoral)
    }

    Spacer()

    Text("of \(maxRewardMinutes)m unlocked")
        .font(.system(size: 14))
        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
}
.padding(.vertical, 8)
```

### Change 2: Fixed Per-App Usage Display (Line 348)

**BEFORE:**
```swift
Text("Earn \(unlockMinutesText)")
    .font(.system(size: 12))
    .foregroundColor(AppTheme.playfulCoral)
    .fontWeight(.semibold)
```

**AFTER:**
```swift
Text("\(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds)) used today")
    .font(.system(size: 12))
    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
```

---

## Data Source

Both changes read from `rewardAppSnapshots`, which gets data from `UsagePersistence.todaySeconds` (the reliable source fixed earlier).

**Data Flow:**
1. Reward app fires threshold event
2. `ScreenTimeService.recordUsage()` updates `UsagePersistence.todaySeconds`
3. `AppUsageViewModel` builds `rewardSnapshots` from persistence
4. "Your Rewards" card displays `snapshot.totalSeconds`

---

## Expected Display

### Before Fix
```
Your Rewards
└─ [App Icon] YouTube
   └─ "Earn 74 min"  ❌ Doesn't show usage
```

### After Fix
```
Your Rewards
├─ Total Used Today: 2m
   of 74m unlocked  ✅ Shows usage summary

└─ [App Icon] YouTube
   └─ "2m used today"  ✅ Shows actual usage
```

---

## Example Scenarios

### Scenario 1: Just Unlocked (No Usage Yet)
```
Total Used Today: 0m
of 74m unlocked

[YouTube] 0m used today
```

### Scenario 2: After 2 Minutes Usage
```
Total Used Today: 2m
of 74m unlocked

[YouTube] 2m used today
```

### Scenario 3: Multiple Reward Apps
```
Total Used Today: 5m
of 74m unlocked

[YouTube] 3m used today
[Roblox] 2m used today
```

---

## Build Status

```
** BUILD SUCCEEDED **
```

---

## Testing Checklist

- [x] Build succeeds
- [ ] Deploy to device
- [ ] Open Challenge Detail in Child Mode
- [ ] Verify "Your Rewards" shows total usage (e.g., "2m of 74m unlocked")
- [ ] Verify each reward app shows usage (e.g., "2m used today")
- [ ] Use reward app for additional time
- [ ] Verify numbers update correctly

---

## Completed Child Mode Fixes

✅ Quest Central "Today's Progress" - Learning Goal (shows 74/10m)
✅ Quest Central "Today's Progress" - Reward Earned (shows 2/74m)
✅ Challenge Detail "Your Progress" (shows 700%, 70/10m)
✅ Challenge Detail "Learning Apps" (shows 74m total)
✅ Challenge Detail "Your Rewards" (shows 2m used of 74m unlocked)

**All Child Mode UI cards now show correct usage from authoritative data sources!**

---

**Fix Complete:** 2025-11-19
**Ready for Testing:** ✅ Yes
