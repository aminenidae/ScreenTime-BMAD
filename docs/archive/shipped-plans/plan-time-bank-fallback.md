# Plan: Time Bank Fallback Calculation on Parent Device

## Problem Statement
The parent device's time bank (earned/available minutes) shows 0 when the child's main app hasn't been launched, because the pre-calculated `DailySnapshotDTO` isn't uploaded to CloudKit. However, the parent already has individual app usage records synced from CloudKit that can be used to calculate time bank values as a fallback.

## Solution Overview
- **Primary source**: `DailySnapshotDTO` from CloudKit (includes historical rollover)
- **Fallback source**: Calculate from `childDailyUsageHistory` + `childRewardAppsFullConfig` linked apps

## Files to Modify

### 1. `ParentRemoteViewModel.swift`
Add computed properties for fallback time bank calculations.

### 2. `RemoteDashboardDataAdapter.swift`
Update `earnedMinutes` and `availableMinutes` to use fallback when snapshot is unavailable.

---

## Implementation Details

### Step 1: Add to ParentRemoteViewModel.swift

Add these computed properties (after the existing `todayTotals` around line 490):

```swift
// MARK: - Fallback Time Bank Calculations

/// Check if the daily snapshot is available and fresh (today's date)
var hasValidDailySnapshot: Bool {
    guard let snapshot = childDailySnapshot else { return false }
    return Calendar.current.isDateInToday(snapshot.date)
}

/// Get all unique learning app IDs that are linked to at least one reward app
private var uniqueLinkedLearningAppIDs: Set<String> {
    var linkedIDs = Set<String>()
    for rewardConfig in childRewardAppsFullConfig {
        for linkedApp in rewardConfig.linkedLearningApps {
            linkedIDs.insert(linkedApp.logicalID)
        }
    }
    return linkedIDs
}

/// Calculate earned minutes from usage history (fallback when DailySnapshotDTO unavailable)
var fallbackEarnedMinutes: Int {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let linkedIDs = uniqueLinkedLearningAppIDs

    // Sum today's usage for learning apps that are linked to reward apps
    var totalEarned = 0
    for record in childDailyUsageHistory {
        guard calendar.isDate(record.date, inSameDayAs: today),
              record.category == "Learning",
              linkedIDs.contains(record.logicalID) else {
            continue
        }
        totalEarned += record.seconds / 60
    }

    #if DEBUG
    print("[ParentRemoteViewModel] Fallback earnedMinutes: \(totalEarned) from \(linkedIDs.count) linked learning apps")
    #endif

    return totalEarned
}

/// Calculate available minutes from usage history (fallback when DailySnapshotDTO unavailable)
/// Note: This is today-only calculation; historical rollover requires child's main app
var fallbackAvailableMinutes: Int {
    let earned = fallbackEarnedMinutes
    let used = todayTotals.rewardSeconds / 60
    return max(0, earned - used)
}
```

### Step 2: Update RemoteDashboardDataAdapter.swift

Replace `earnedMinutes` (lines 99-107):

```swift
var earnedMinutes: Int {
    // Primary: Use pre-calculated value from synced daily snapshot
    if viewModel.hasValidDailySnapshot,
       let snapshot = viewModel.childDailySnapshot {
        #if DEBUG
        print("[RemoteDashboardDataAdapter] earnedMinutes = \(snapshot.totalEarnedMinutes) (from snapshot)")
        #endif
        return snapshot.totalEarnedMinutes
    }

    // Fallback: Calculate from usage history + linked app configs
    let fallback = viewModel.fallbackEarnedMinutes
    #if DEBUG
    print("[RemoteDashboardDataAdapter] earnedMinutes = \(fallback) (FALLBACK - no valid snapshot)")
    #endif
    return fallback
}
```

Replace `availableMinutes` (lines 125-132):

```swift
var availableMinutes: Int {
    // Primary: Use cumulative available from synced daily snapshot (includes rollover)
    if viewModel.hasValidDailySnapshot,
       let snapshot = viewModel.childDailySnapshot {
        #if DEBUG
        print("[RemoteDashboardDataAdapter] availableMinutes = \(snapshot.cumulativeAvailableMinutes) (from snapshot)")
        #endif
        return snapshot.cumulativeAvailableMinutes
    }

    // Fallback: Calculate from usage history (today only, no rollover)
    let fallback = viewModel.fallbackAvailableMinutes
    #if DEBUG
    print("[RemoteDashboardDataAdapter] availableMinutes = \(fallback) (FALLBACK - today only)")
    #endif
    return fallback
}
```

---

## Decision Logic

| Condition | Source | Notes |
|-----------|--------|-------|
| `childDailySnapshot != nil` AND today's date | Primary (Snapshot) | Best accuracy, includes rollover |
| `childDailySnapshot == nil` OR stale | Fallback (Calculated) | Today only, no rollover |

---

## Calculation Logic (matches child's AppUsageViewModel)

**Earned Minutes:**
1. Get unique linked learning app IDs from all reward apps' `linkedLearningApps`
2. Filter today's `childDailyUsageHistory` for learning category with those IDs
3. Sum `seconds / 60`

**Used Minutes:**
- Already works: `todayTotals.rewardSeconds / 60`

**Available Minutes:**
- Primary: `snapshot.cumulativeAvailableMinutes` (includes historical rollover)
- Fallback: `max(0, earned - used)` (today only)

---

## Known Limitation

The fallback calculation cannot include historical rollover minutes because that data is only available in the child's `UsagePersistence`. The fallback shows today's balance only. When the child app runs, the full cumulative balance with rollover becomes available.

---

## Verification Steps

1. **Setup**: Ensure child device has learning and reward apps configured with linked apps
2. **Test Fallback**:
   - Force-quit child's main app (ensure DailySnapshotDTO is not uploaded)
   - Use learning apps on child for a few minutes
   - Wait for extension sync (up to 30 min) or trigger manual sync
   - Check parent device - should show earned minutes from fallback calculation
3. **Test Primary**:
   - Launch child's main app (this uploads DailySnapshotDTO)
   - Wait for sync
   - Parent should show values from snapshot (may include rollover)
4. **Verify Logs**:
   - Check for "(from snapshot)" when snapshot available
   - Check for "(FALLBACK)" when using calculated values
