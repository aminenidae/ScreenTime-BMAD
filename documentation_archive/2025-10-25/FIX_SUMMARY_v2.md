# Fix Summary v2: Reward Apps Deletion Issue (Corrected Approach)

## Problem Analysis
After carefully analyzing the logs and code, I identified the real issue:

1. When clicking "Add More Apps" on the learning tab, [presentLearningPicker()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L115-L133) correctly sets [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) to only include learning apps
2. However, in the [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) method, after merging the selections, the code was incorrectly setting:
   ```swift
   masterSelection = merged
   familySelection = merged  // <-- This was the problem!
   ```
3. This meant that [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) now contained both learning and reward apps
4. When [selection(for: AppUsage.AppCategory.learning)](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L415-L451) was later called, it would filter from this merged selection that contained both categories, causing the picker to show reward apps in the learning context

## Solution
Modified the [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) method to preserve the correct state:

```swift
masterSelection = merged
// FIX: Don't set familySelection to the merged selection
// Instead, keep familySelection as is (containing only the current context's apps)
// This ensures that subsequent calls to selection(for:) work correctly
activePickerContext = nil
```

## Key Changes
1. **Preserve [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) state**: Keep [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) containing only the current context's apps
2. **Update [masterSelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L47-L47) with merged tokens**: [masterSelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L47-L47) now contains all tokens from both categories for persistence
3. **Maintain proper separation**: Learning picker still only shows learning apps, reward picker still only shows reward apps

## Result
With this fix:
1. When opening the learning picker, only learning apps are shown (reward apps are properly filtered out)
2. When opening the reward picker, only reward apps are shown (learning apps are properly filtered out)
3. The [masterSelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L47-L47) properly retains all apps from both categories for persistence
4. Apps are no longer incorrectly deleted when switching between category pickers
5. The retention logic in [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) correctly preserves apps from the non-active category

## Testing
The fix has been built successfully and is ready for testing in the simulator or on device.