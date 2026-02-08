# Task M Fixes Summary

**Date:** 2025-10-24
**Developer:** Code Agent
**Issue:** App removal issues in ScreenTime Rewards

## Problem Description

The app removal functionality had several issues that caused incorrect behavior:

1. **Orphaned tokens in selections** - When removing a reward app, the token stayed in `masterSelection`, causing it to appear in the Learning tab with previous data
2. **Persistence re-saving** - Instead of deleting cached data, the system was re-saving it with the old category
3. **Snapshot rendering of orphaned tokens** - The `updateSnapshots()` method would render removed tokens by falling back to `.learning` category

## Solution Implemented

### 1. Added deleteApp Method to UsagePersistence

Added a new method to properly delete persisted app data:

```swift
/// Delete a persisted app by its logical ID
/// - Parameter logicalID: The logical ID of the app to delete
func deleteApp(logicalID: LogicalAppID) {
    cachedApps.removeValue(forKey: logicalID)
    persistApps()
    
    #if DEBUG
    print("[UsagePersistence] 🗑️ Deleted app with logicalID: \(logicalID)")
    #endif
}
```

### 2. Fixed removeAppWithoutConfirmation Method

Updated the app removal method to properly clean up all selection sources:

```swift
// 5. Update all selection sources to remove this token
// Remove from familySelection
familySelection.applicationTokens.remove(token)

// Remove from masterSelection
masterSelection.applicationTokens.remove(token)

// Remove from pendingSelection if present
pendingSelection.applicationTokens.remove(token)

// Remove from sortedApplications (this will be rebuilt in step 6)
```

Also changed from re-saving to deleting persisted data:

```swift
// Delete the persisted data for this app instead of re-saving it
service.usagePersistence.deleteApp(logicalID: logicalID)
```

### 3. Updated updateSnapshots Method

Added a check to skip orphaned tokens that are no longer in familySelection:

```swift
// TASK M FIX: Confirm the token still exists in familySelection before processing
// If it's not selected anymore, skip the entry so orphaned tokens never render
if !familySelection.applicationTokens.contains(token) {
    #if DEBUG
    print("[AppUsageViewModel] Skipping orphaned token: \(token.hashValue)")
    #endif
    continue
}
```

## Validation

The fixes resolve all the reported issues:

1. ✅ **Removed apps no longer appear in wrong categories** - Tokens are properly removed from all selection sources
2. ✅ **Persistence is properly cleaned up** - Cached data is deleted instead of re-saved
3. ✅ **Orphaned tokens are not rendered** - The snapshot generation skips tokens not in familySelection
4. ✅ **Shield logic is preserved** - Reward apps still have their shields properly removed

## Files Modified

1. `ScreenTimeRewards/Shared/UsagePersistence.swift` - Added `deleteApp` method
2. `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` - Fixed `removeAppWithoutConfirmation` method and `updateSnapshots` method

## Impact

The fixes ensure that app removal works correctly with proper cleanup of all data sources, preventing the issues where removed apps would appear in the wrong category or retain their previous data.