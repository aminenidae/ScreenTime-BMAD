# ScreenTime Rewards App - Reward Apps Deletion Issue Summary

## Overview
This document summarizes an issue encountered in the ScreenTime Rewards app where reward apps were being incorrectly deleted when clicking "Add More Apps" on the learning tab view. Multiple fix attempts were made, with varying degrees of success.

## Initial Problem
When a user clicked "Add More Apps" on the learning tab view, reward apps were being deleted from the app. This was confirmed through log analysis which showed:
- Initially: `Learning: 2, Reward: 2` apps
- After opening learning picker: `Learning: 2, Reward: 0` apps with "Skipping orphaned token" messages

## Root Cause Analysis
Through careful analysis of the logs and code, the issue was traced to state management problems in the ViewModel during the app selection process:

1. The [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) was being incorrectly overwritten during the [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) process
2. This caused apps from one category to be lost when working with the other category
3. The retention logic was working correctly, but the state was being corrupted during the merge process

## Fix Attempts

### Attempt 1: Incorrect Approach (Reverted)
**Approach**: Modified [presentLearningPicker()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L115-L133) and [presentRewardPicker()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L135-L147) to include apps from both categories in [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49)

**Result**: This approach was incorrect because it violated the design principle of category-specific selection. It caused the learning picker to show reward apps, which was a previously fixed issue.

**Action Taken**: This change was reverted to maintain proper category separation.

### Attempt 2: Correct Approach (Current Implementation)
**Approach**: Fixed the state management in [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) by ensuring [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) retains only the current context's apps while [masterSelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L47-L47) contains all apps for persistence.

**Key Change**:
```swift
// In mergeCurrentSelectionIntoMaster()
masterSelection = merged
// FIX: Don't set familySelection to the merged selection
// Instead, keep familySelection as is (containing only the current context's apps)
// This ensures that subsequent calls to selection(for:) work correctly
activePickerContext = nil
```

**Result**: This approach maintains proper separation between categories while ensuring all apps are preserved in the master selection for persistence.

## Current Status
The fix has been implemented and the app builds successfully. However, further testing is needed to verify that:
1. Apps are no longer incorrectly deleted when switching between category pickers
2. Category-specific pickers only show relevant apps
3. All existing functionality remains intact

## Next Steps
1. Conduct thorough testing of the fix in the simulator
2. Verify that the issue is completely resolved
3. Test edge cases and ensure no regressions were introduced
4. Document the final solution in the project documentation

## Files Modified
- `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`
- `/Users/ameen/Documents/ScreenTime-BMAD/FIX_SUMMARY.md` (documentation)
- `/Users/ameen/Documents/ScreenTime-BMAD/FIX_SUMMARY_v2.md` (documentation)
- `/Users/ameen/Documents/ScreenTime-BMAD/ISSUE_SUMMARY_FOR_PM.md` (this document)

## Build Status
- ✅ App builds successfully
- ✅ App installs on simulator
- ⚠️ Further functional testing required