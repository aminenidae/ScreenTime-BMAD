# Fix Summary: Reward Apps Deletion Issue

## Problem
When clicking "Add More Apps" on the learning tab view, reward apps were being deleted. This was happening because:

1. When [presentLearningPicker()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L115-L133) was called, it was setting [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) to only include learning apps
2. This caused reward apps to be lost from the current selection
3. When [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) was called, it was working with an incomplete [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) that didn't include reward apps
4. Even though the retention logic was trying to preserve reward apps, they were already lost from [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49)

## Solution
Modified [presentLearningPicker()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L115-L133) and [presentRewardPicker()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L135-L147) methods to preserve apps from both categories:

```swift
func presentLearningPicker() {
    // FIX: Reset picker state before presenting to prevent ActivityPickerRemoteViewError
    resetPickerStateForNewPresentation()
    
    activePickerContext = .learning
    shouldPresentAssignmentAfterPickerDismiss = false
    // Set familySelection to include both learning apps and preserve reward apps
    // This prevents reward apps from being lost when opening the learning picker
    let learningSelection = selection(for: AppUsage.AppCategory.learning)
    let rewardSelection = selection(for: AppUsage.AppCategory.reward)
    
    var combinedSelection = learningSelection
    combinedSelection.applicationTokens.formUnion(rewardSelection.applicationTokens)
    
    familySelection = combinedSelection
    requestAuthorizationAndOpenPicker()
}

func presentRewardPicker() {
    // FIX: Reset picker state before presenting to prevent ActivityPickerRemoteViewError
    resetPickerStateForNewPresentation()
    
    activePickerContext = .reward
    shouldPresentAssignmentAfterPickerDismiss = false
    // Set familySelection to include both reward apps and preserve learning apps
    // This prevents learning apps from being lost when opening the reward picker
    let rewardSelection = selection(for: AppUsage.AppCategory.reward)
    let learningSelection = selection(for: AppUsage.AppCategory.learning)
    
    var combinedSelection = rewardSelection
    combinedSelection.applicationTokens.formUnion(learningSelection.applicationTokens)
    
    familySelection = combinedSelection
    requestAuthorizationAndOpenPicker()
}
```

## Result
With this fix:
1. When opening the learning picker, reward apps are preserved
2. When opening the reward picker, learning apps are preserved
3. The [mergeCurrentSelectionIntoMaster()](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L363-L413) method now works with a complete [familySelection](file:///Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift#L48-L49) that includes apps from both categories
4. Apps are no longer incorrectly deleted when switching between category pickers

## Testing
The fix has been built successfully and is ready for testing in the simulator or on device.