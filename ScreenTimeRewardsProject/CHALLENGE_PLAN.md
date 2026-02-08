# Challenge System Enhancement Plan

## Executive Summary
This document outlines the plan to enhance the Challenge Builder in the ScreenTime Rewards app by replacing placeholder UI with functional app selection and adding 2-3 new challenge types based on user requirements.

---

## Current State Analysis

### ✅ What's Working
- **Core Infrastructure**: Challenge and ChallengeProgress Core Data entities with CloudKit sync
- **Progress Tracking**: Automatic updates when apps are used
- **Bonus Points System**: Awards percentage-based bonuses on completion
- **Streak System**: Tracks daily activity streaks
- **Badge System**: 6 starter badges with auto-unlock on criteria
- **Child UI**: Fully functional quest display with progress bars
- **Parent UI**: Challenge list view with grid layout

### ❌ What's Placeholder/Broken
- **Challenge Builder App Selection**: Shows hardcoded apps (Khan Kids, Duolingo, YT Kids, TikTok)
- **App Icons**: Gray placeholder rectangles instead of real app icons
- **Goal Type Options**: Only shows 2 of 4 available types in UI
- **Bonus Percentage**: Hardcoded to 10%, no UI control
- **Description Field**: State variable exists but no input field
- **Schedule Data**: Collected but not saved to Challenge entity
- **End Date**: No UI to configure
- **Reward App Selection**: No functionality to choose which apps unlock

### 🔄 Partially Implemented
- **Target Apps**: JSON storage works, progress tracking checks it correctly, but no UI to select apps

---

## User Requirements (From Questionnaire)

1. **Priority Challenge Types**:
   - ✅ Time-based (daily/weekly minutes)
   - ✅ Specific app focus
   - ✅ Streak & consistency
   - ✅ Points & efficiency

2. **App Selection**: Critical feature - parents need to select specific apps

3. **Scope**: Add 2-3 new challenge types + fix app selection (medium scope)

4. **Rewards**: Parent sets bonus % and chooses which reward apps to unlock

---

## Proposed Challenge Types

### 1. Time-Based Challenges (EXISTING - FIX)
**Type**: `dailyMinutes` or `weeklyMinutes`

**Description**:
- Daily: "Use learning apps for X minutes per day"
- Weekly: "Complete Y minutes of learning this week"

**What to Fix**:
- Already implemented in backend
- UI works but needs real app selection
- Currently shown in Challenge Builder

**Example**: "Complete 300 minutes of learning this week"

---

### 2. Specific App Focus (EXISTING - FIX)
**Type**: `specificApps`

**Description**: "Practice [specific learning apps] for X minutes"

**What to Fix**:
- Backend fully supports `targetAppsJSON`
- UI shows placeholder apps instead of actual selection
- Need to integrate with parent's configured learning apps

**Example**: "Practice Khan Academy for 60 minutes this week"

---

### 3. Daily Streak Challenge (EXISTING - EXPOSE IN UI)
**Type**: `streak`

**Description**: "Learn every day for X consecutive days"

**What to Fix**:
- Fully implemented in backend (StreakRecord, streak tracking)
- Defined in ChallengeGoalType enum
- **NOT shown in Challenge Builder UI** - need to add to picker

**Example**: "Learn every day for 7 days straight"

---

### 4. Points Target (NEW - IMPLEMENT)
**Type**: `pointsTarget` (NEW enum value needed)

**Description**: "Earn X points this week"

**What to Implement**:
- Add `pointsTarget` to `ChallengeGoalType` enum
- Add progress calculation in `ChallengeService.updateProgressForUsage()`
- Track earned points instead of minutes
- Show points input in UI (instead of minutes)

**Example**: "Earn 500 points this week for bonus rewards"

---

## Implementation Plan

### Phase 1: Data Model Updates

#### 1.1 Add New Challenge Goal Type
**File**: `ScreenTimeRewards/Services/ChallengeService.swift`

```swift
enum ChallengeGoalType: String, CaseIterable {
    case dailyMinutes = "daily_minutes"
    case weeklyMinutes = "weekly_minutes"
    case specificApps = "specific_apps"
    case streak = "streak"
    case pointsTarget = "points_target"  // NEW
}
```

#### 1.2 Add Reward Apps Storage to Challenge
**File**: Core Data model - need to add attribute

Add new optional attribute to Challenge entity:
- `rewardAppsJSON: String?` - JSON array of reward app tokens to unlock on completion

#### 1.3 Update Challenge Creation Method
**File**: `ScreenTimeRewards/Services/ChallengeService.swift`

Add parameter to `createChallenge()`:
```swift
func createChallenge(
    ...
    rewardApps: [String]?,  // NEW - array of reward app IDs
    ...
)
```

Store as JSON in `rewardAppsJSON` field

---

### Phase 2: Learning App Selection UI

#### 2.1 Remove Placeholder Learning Apps Grid
**File**: `ScreenTimeRewards/Views/ParentMode/ChallengeBuilderView.swift`

**Current Code** (lines ~200-250):
```swift
// Hardcoded apps grid
HStack {
    AppSelectionCard(name: "Khan Kids", isSelected: false)
    AppSelectionCard(name: "Duolingo", isSelected: false)
    // etc...
}
```

**Replace With**:
```swift
// Real app selection from child's configured apps
LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
    ForEach(viewModel.learningSnapshots) { snapshot in
        AppSelectionButton(
            token: snapshot.token,
            displayName: snapshot.displayName,
            isSelected: selectedLearningApps.contains(snapshot.token),
            onToggle: { toggleLearningApp(snapshot.token) }
        )
    }
}
```

#### 2.2 Create AppSelectionButton Component
**New Component**: Show real app icon + name + selection state

```swift
struct AppSelectionButton: View {
    let token: ApplicationToken
    let displayName: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack {
                // Real app icon
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(2.1)
                    .frame(width: 50, height: 50)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )

                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}
```

#### 2.3 Update State Management
Add to ChallengeBuilderView:
```swift
@State private var selectedLearningApps: Set<ApplicationToken> = []

func toggleLearningApp(_ token: ApplicationToken) {
    if selectedLearningApps.contains(token) {
        selectedLearningApps.remove(token)
    } else {
        selectedLearningApps.insert(token)
    }
}
```

---

### Phase 3: Reward App Selection UI

#### 3.1 Replace Placeholder Reward Apps Grid
Same approach as learning apps, but for `rewardSnapshots`

```swift
@State private var selectedRewardApps: Set<ApplicationToken> = []

LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
    ForEach(viewModel.rewardSnapshots) { snapshot in
        AppSelectionButton(
            token: snapshot.token,
            displayName: snapshot.displayName,
            isSelected: selectedRewardApps.contains(snapshot.token),
            onToggle: { toggleRewardApp(snapshot.token) }
        )
    }
}
```

#### 3.2 Show Selected Reward Apps as Challenge Reward
Update UI to show:
- "Complete this challenge to unlock:"
- List of selected reward app names
- Unlock duration (e.g., "30 minutes each")

---

### Phase 4: Goal Type Picker Updates

#### 4.1 Show All 4 Challenge Types
**Current**: Only shows "Time Spent" and "Tasks Completed"

**Update to**:
```swift
Picker("Goal Type", selection: $goalType) {
    Text("Daily Minutes").tag(ChallengeGoalType.dailyMinutes)
    Text("Weekly Minutes").tag(ChallengeGoalType.weeklyMinutes)
    Text("Specific Apps").tag(ChallengeGoalType.specificApps)
    Text("Daily Streak").tag(ChallengeGoalType.streak)
    Text("Points Target").tag(ChallengeGoalType.pointsTarget)
}
.pickerStyle(.menu) // Use dropdown instead of segmented control
```

#### 4.2 Dynamic Target Input
Show different input based on selected goal type:

```swift
switch goalType {
case .dailyMinutes, .weeklyMinutes:
    // Show minutes slider (existing)
    Slider(value: $targetMinutes, in: 0...120, step: 5)

case .specificApps:
    // Show minutes slider + app selection
    Slider(value: $targetMinutes, in: 0...120, step: 5)
    // App selection grid shown below

case .streak:
    // Show days stepper
    Stepper("Days: \(streakDays)", value: $streakDays, in: 1...30)

case .pointsTarget:
    // Show points slider
    Slider(value: $targetPoints, in: 0...1000, step: 50)
}
```

---

### Phase 5: Additional UI Fields

#### 5.1 Bonus Percentage Picker
```swift
Picker("Bonus Reward", selection: $bonusPercentage) {
    Text("5%").tag(5)
    Text("10%").tag(10)
    Text("15%").tag(15)
    Text("20%").tag(20)
    Text("25%").tag(25)
}
```

#### 5.2 Description Text Field
```swift
Section(header: Text("Description (Optional)")) {
    TextField("Add details about this challenge...", text: $description)
        .textFieldStyle(.roundedBorder)
}
```

#### 5.3 End Date Picker
```swift
Toggle("Set End Date", isOn: $hasEndDate)
if hasEndDate {
    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
}
```

---

### Phase 6: Backend Updates

#### 6.1 Points Target Progress Tracking
**File**: `ScreenTimeRewards/Services/ChallengeService.swift`

Update `updateProgressForUsage()` method:

```swift
func updateProgressForUsage(appID: String, duration: TimeInterval, earnedPoints: Int, deviceID: String) async {
    let challenges = try await fetchActiveChallenges(for: deviceID)

    for challenge in challenges {
        guard let progress = challengeProgress[challenge.challengeID] else { continue }

        switch challenge.goalType {
        case .dailyMinutes:
            // Existing logic

        case .weeklyMinutes:
            // Existing logic

        case .specificApps:
            // Existing logic

        case .streak:
            // Existing logic

        case .pointsTarget:
            // NEW: Track points instead of time
            progress.currentValue += Int32(earnedPoints)

            if progress.currentValue >= progress.targetValue {
                await completeChallenge(challenge, progress: progress)
            }
        }
    }
}
```

#### 6.2 Reward App Unlocking on Completion
Update `completeChallenge()` method:

```swift
private func completeChallenge(_ challenge: Challenge, progress: ChallengeProgress) async {
    // Existing bonus points logic

    // NEW: Unlock reward apps
    if let rewardAppsJSON = challenge.rewardAppsJSON,
       let rewardAppIDs = try? JSONDecoder().decode([String].self, from: rewardAppsJSON.data(using: .utf8)!) {

        for appID in rewardAppIDs {
            // Unlock each reward app for configured duration (e.g., 30 minutes)
            let unlockDuration = 30 // Could be configurable
            await unlockRewardApp(appID: appID, minutes: unlockDuration, deviceID: challenge.assignedTo)
        }
    }

    // Post completion notification
}
```

---

### Phase 7: Save Challenge with New Fields

#### 7.1 Update Challenge Creation Call
**File**: `ChallengeBuilderView.swift` - `saveChallenge()` method

```swift
func saveChallenge() {
    // Convert selected app tokens to string IDs
    let learningAppIDs = selectedLearningApps.map { getLogicalID(for: $0) }
    let rewardAppIDs = selectedRewardApps.map { getLogicalID(for: $0) }

    // Determine target value based on goal type
    let targetValue: Int
    switch goalType {
    case .dailyMinutes, .weeklyMinutes, .specificApps:
        targetValue = Int(targetMinutes)
    case .streak:
        targetValue = streakDays
    case .pointsTarget:
        targetValue = Int(targetPoints)
    }

    Task {
        try await challengeService.createChallenge(
            title: challengeName,
            description: description,
            goalType: goalType,
            targetValue: targetValue,
            bonusPercentage: bonusPercentage,
            targetApps: learningAppIDs.isEmpty ? nil : learningAppIDs,
            rewardApps: rewardAppIDs.isEmpty ? nil : rewardAppIDs,
            startDate: Date(),
            endDate: hasEndDate ? endDate : nil,
            activeDays: selectedDays, // Save schedule data
            startTime: startTime,
            endTime: endTime,
            createdBy: parentDeviceID,
            assignedTo: childDeviceID
        )
    }
}
```

---

### Phase 8: UI Display Updates

#### 8.1 Child Challenge Display
**File**: `ChildChallengesTabView.swift`

Update progress display to handle different goal types:

```swift
func progressText(for challenge: Challenge, progress: ChallengeProgress) -> String {
    switch challenge.goalType {
    case .dailyMinutes, .weeklyMinutes, .specificApps:
        return "\(progress.currentValue) / \(progress.targetValue) minutes"

    case .streak:
        return "\(progress.currentValue) / \(progress.targetValue) days"

    case .pointsTarget:
        return "\(progress.currentValue) / \(progress.targetValue) points"
    }
}
```

#### 8.2 Parent Challenge Detail View
**File**: `ChallengeDetailView.swift`

Fix hardcoded progress (line 341):
```swift
// BEFORE (hardcoded):
let progress = 35

// AFTER (real data):
let progress = challengeProgress[challenge.challengeID]?.currentValue ?? 0
```

Show reward apps that will unlock:
```swift
if let rewardAppsJSON = challenge.rewardAppsJSON {
    Section(header: Text("Rewards to Unlock")) {
        // Display reward app names
    }
}
```

---

## Testing Checklist

### Unit Tests
- [ ] Points target progress calculation
- [ ] Reward apps JSON encoding/decoding
- [ ] Challenge creation with all goal types
- [ ] Progress tracking for each goal type

### Integration Tests
- [ ] Create challenge on parent device → syncs to child
- [ ] Child uses learning app → progress updates
- [ ] Challenge completes → bonus points awarded
- [ ] Challenge completes → reward apps unlock
- [ ] Streak challenge tracks consecutive days

### UI Tests
- [ ] Learning app selection shows real apps with icons
- [ ] Reward app selection shows real apps with icons
- [ ] All 4 goal types appear in picker
- [ ] Dynamic target input changes based on goal type
- [ ] Bonus percentage picker works
- [ ] Description field saves correctly
- [ ] Child sees correct progress for all challenge types

---

## Out of Scope (Future Enhancements)

### Multi-App Diversity
- "Use 3 different learning apps this week"
- Requires counting distinct apps used

### Daily Consistency
- "Meet daily goal 5 out of 7 days"
- Requires tracking days meeting threshold

### Time-of-Day Challenges
- "Learn between 4-6 PM"
- Requires filtering session times

### Efficiency Challenges
- "Earn 100 points in 30 minutes"
- Requires points-per-minute ratio checking

### Milestone Chains
- Progressive goals across multiple days
- Requires new data structure for sub-goals

---

## Migration Considerations

### Core Data Changes
1. Add `rewardAppsJSON` attribute to Challenge entity
2. Add `pointsTarget` to ChallengeGoalType enum (code only, not schema)
3. Add `activeDays`, `startTime`, `endTime` attributes to Challenge entity (optional)

### Backward Compatibility
- Existing challenges will continue to work
- `rewardAppsJSON` is optional - nil means no specific reward apps
- New challenge types only available in updated app versions

---

## Success Metrics

1. **Functional App Selection**: Parents can select real learning/reward apps from child's configured list
2. **4 Challenge Types Working**: Daily, Weekly, Specific Apps, Streak all functional
3. **Points Target Implemented**: New challenge type tracks points instead of time
4. **Customizable Rewards**: Parent can set bonus % and choose reward apps
5. **Real Progress Display**: Child sees accurate progress for all challenge types
6. **Reward App Unlocking**: Completing challenge unlocks selected reward apps

---

## Timeline Estimate

- **Phase 1** (Data Model): 1-2 hours
- **Phase 2** (Learning App Selection): 2-3 hours
- **Phase 3** (Reward App Selection): 1-2 hours
- **Phase 4** (Goal Type Picker): 1 hour
- **Phase 5** (Additional UI Fields): 1-2 hours
- **Phase 6** (Backend Updates): 2-3 hours
- **Phase 7** (Save Integration): 1 hour
- **Phase 8** (UI Display): 1-2 hours
- **Testing**: 2-3 hours

**Total Estimated Time**: 12-19 hours

---

## Files to Modify

### Core Data
- `ScreenTimeRewards.xcdatamodeld` - Add attributes to Challenge entity

### Services
- `ScreenTimeRewards/Services/ChallengeService.swift` - Add points tracking, reward app unlocking

### View Models
- `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` - Pass app lists to Challenge Builder

### Views
- `ScreenTimeRewards/Views/ParentMode/ChallengeBuilderView.swift` - Main UI updates
- `ScreenTimeRewards/Views/ParentMode/ChallengeDetailView.swift` - Fix hardcoded progress
- `ScreenTimeRewards/Views/ChildMode/ChildChallengesTabView.swift` - Display updates for new types

### Models
- `ScreenTimeRewards/Models/Challenge+CoreDataProperties.swift` - Add new properties
- Add new `ChallengeGoalType` case to enum

---

## Notes

- Real app selection is critical per user requirements
- Focus on quality over quantity - 4 solid challenge types better than many half-baked ones
- Leverage existing infrastructure (streak tracking, points system, CloudKit sync)
- Keep child UI simple and game-like ("quests" terminology)
- Parent UI should be clear and easy to configure
