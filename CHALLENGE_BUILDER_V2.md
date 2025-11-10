# Challenge Builder V2 - Multi-Step Onboarding Flow

## Overview

This document outlines the implementation plan for transforming the current single-page Challenge Builder into a multi-step onboarding flow, providing a more intuitive and guided experience for creating challenges.

---

## Current vs. Proposed Flow

### Current (V1)
- Single scrollable page with 4 sections
- All inputs visible at once
- Can be overwhelming for new users
- Limited contextual help

### Proposed (V2)
- 6-step guided flow with navigation
- One focused task per screen
- Progressive disclosure of options
- Inline help and validation per step
- Clear summary before submission

---

## Step-by-Step Flow

### Step 1: Challenge Details
**Purpose:** Define the challenge basics and goal type

**Content:**
- Challenge Name (required text field)
- Description (optional multi-line text field)
- Goal Type Selection with **inline expandable help cards**:
  - **Daily Minutes** 📅
    _Complete X minutes each day_
    Example: "Read for 30 minutes every day"
  - **Weekly Minutes** 📊
    _Complete X total minutes per week_
    Example: "Practice math for 120 minutes this week"
  - **Specific Apps** 📱
    _Use selected apps for X minutes_
    Example: "Use Duolingo for 20 minutes"
  - **Streak** 🔥
    _Maintain activity for X consecutive days_
    Example: "Learn for 7 days in a row"
  - **Points Target** ⭐
    _Earn X points from learning apps_
    Example: "Earn 500 points"
- Dynamic goal quantification input based on selected type:
  - Sliders for minutes/points
  - Stepper for streak days
  - Range labels and current value display

**Validation:**
- ✓ Name must not be empty
- ✓ Goal value must be within valid range for type

**Navigation:** Next → Step 2a

---

### Step 2a: Learning Apps Selection
**Purpose:** Choose which learning apps count toward the challenge

**Content:**
- Title: "Select Learning Apps"
- Subtitle: "Which apps should count toward this challenge?"
- Multi-select list using `AppSelectionRow` component
- Selection count indicator at top
- Empty state message: "Add learning apps from the Learning tab first"
- Help text: "Leave empty to count all learning apps"

**Validation:**
- No validation required (empty selection = all learning apps)

**Navigation:**
- Previous → Step 1
- Next → Step 2b

---

### Step 2b: Reward Apps Selection
**Purpose:** Choose which apps will be unlocked as rewards

**Content:**
- Title: "Choose Reward Apps"
- Subtitle: "Which apps will be unlocked as rewards?"
- Multi-select list using `AppSelectionRow` component
- Selection count indicator at top
- Empty state message: "Assign apps to Reward category first"
- Help text: "Select apps that will be unlocked upon completion"

**Validation:**
- No validation required (can have no rewards)

**Navigation:**
- Previous → Step 2a
- Next → Step 3

---

### Step 3: Reward Configuration
**Purpose:** Configure the learning-to-reward time ratio and bonus multiplier

**Content:**
- **NEW FEATURE: Learning to Reward Ratio**
  - Two number input fields in a row:
    ```
    [60] min learning = [30] min reward
    ```
  - Alternative: Preset ratio buttons (1:1, 2:1, 3:1, 4:1)
  - Explanation: "Set how much reward time is earned per learning time"

- **Bonus Percentage** (UPDATED RANGE: 0-50%)
  - Slider from 0% to 50% (was 5-25%)
  - Current value displayed: "+25%"
  - Segmented picker with common values: 0%, 10%, 20%, 30%, 40%, 50%

- **Preview Card:**
  ```
  📊 Reward Calculation:
  60 minutes of learning = 30 minutes reward
  +25% bonus = 37.5 minutes total reward time
  ```

**Validation:**
- ✓ Learning minutes > 0
- ✓ Reward minutes > 0
- ✓ Bonus percentage 0-50

**Navigation:**
- Previous → Step 2b
- Next → Step 4

---

### Step 4: Schedule
**Purpose:** Set when and how often the challenge is active

**Content:**
- **NEW FEATURE: Full Day Toggle**
  - Toggle switch: "Full Day" (default: OFF)
  - When ON: Automatically uses 00:00 - 23:59
  - When OFF: Show time picker inputs
  - Help text: "Enable for all-day challenges"

- **Time Range** (only visible when Full Day is OFF)
  - Start Time picker (default: 16:00)
  - End Time picker (default: 20:00)
  - Validation: End time must be after start time

- **Active Days**
  - Circular day selector buttons (S M T W T F S)
  - Multi-select
  - Default: M T W T F (weekdays)

- **Repeat Weekly**
  - Toggle switch (default: ON)
  - Help text: "Challenge repeats every week"

- **End Date**
  - Toggle: "Set End Date" (default: OFF)
  - When ON: Show date picker
  - Default date: 7 days from today
  - Validation: Must be after start date

**Validation:**
- ✓ If not full day: end time > start time
- ✓ At least one active day selected (recommended)
- ✓ If end date set: end date > start date

**Navigation:**
- Previous → Step 3
- Next → Step 5

---

### Step 5: Summary & Submission
**Purpose:** Review all settings before creating the challenge

**Content:**
- Title: "Review Challenge"
- Read-only summary cards:

  **Challenge Details**
  - Name: [Challenge Name]
  - Description: [Description or "No description"]
  - Goal: [Daily Minutes] - [60 minutes]

  **Apps**
  - Learning: [4 apps selected] or [All learning apps]
  - Rewards: [2 apps selected] or [No rewards]

  **Reward Rules**
  - Ratio: 60 min learning → 30 min reward
  - Bonus: +25%
  - Total reward time: 37.5 minutes

  **Schedule**
  - Time: [Full Day] or [16:00 - 20:00]
  - Days: M T W T F
  - Repeat: Weekly
  - End: [January 15, 2025] or [No end date]

- **Three Action Buttons:**
  - **Cancel** (text button, top right corner)
    - Dismisses flow without saving
    - Shows confirmation alert
  - **Return** (secondary button, bottom left)
    - Goes back to Step 4 (Schedule)
    - Allows making final adjustments
  - **Submit** (primary button, bottom right)
    - Saves challenge and dismisses
    - Shows success message

**Validation:**
- ✓ All previous validations pass
- ✓ Ready to create challenge

**Navigation:**
- Previous (Return button) → Step 4
- Cancel → Dismiss entire flow
- Submit → Save & dismiss

---

## Technical Architecture

### Data Model

#### ChallengeBuilderData.swift
Centralized model to replace scattered `@State` variables:

```swift
import Foundation
import SwiftUI

struct ChallengeBuilderData {
    // Step 1: Challenge Details
    var title: String = ""
    var description: String = ""
    var goalType: ChallengeGoalType = .dailyMinutes
    var targetValue: Int = 60

    // Step 2a & 2b: App Selection
    var selectedLearningAppIDs: Set<String> = []
    var selectedRewardAppIDs: Set<String> = []

    // Step 3: Reward Configuration (NEW)
    var learningMinutes: Int = 60     // X minutes of learning
    var rewardMinutes: Int = 30       // = Y minutes of reward
    var bonusPercentage: Int = 0      // 0-50% (expanded range)

    // Step 4: Schedule
    var isFullDay: Bool = false       // NEW: Full day toggle
    var startTime: Date = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
    var endTime: Date = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    var activeDays: Set<Int> = [1, 2, 3, 4, 5]  // Mon-Fri
    var repeatWeekly: Bool = true
    var hasEndDate: Bool = false
    var endDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var startDate: Date = Date()

    // Computed Properties
    var actualRewardMinutes: Int {
        let baseReward = rewardMinutes
        let bonus = baseReward * bonusPercentage / 100
        return baseReward + bonus
    }

    var isStep1Valid: Bool {
        !title.isEmpty && isTargetValueValid
    }

    var isTargetValueValid: Bool {
        switch goalType {
        case .dailyMinutes:
            return targetValue >= 15 && targetValue <= 240
        case .weeklyMinutes:
            return targetValue >= 60 && targetValue <= 1440
        case .specificApps:
            return targetValue >= 15 && targetValue <= 360
        case .streak:
            return targetValue >= 3 && targetValue <= 30
        case .pointsTarget:
            return targetValue >= 100 && targetValue <= 1000
        }
    }

    var isStep3Valid: Bool {
        learningMinutes > 0 && rewardMinutes > 0 && bonusPercentage >= 0 && bonusPercentage <= 50
    }

    var isStep4Valid: Bool {
        if !isFullDay {
            guard endTime > startTime else { return false }
        }
        if hasEndDate {
            guard endDate > startDate else { return false }
        }
        return !activeDays.isEmpty
    }
}
```

#### LearningToRewardRatio.swift
Helper model for ratio display:

```swift
import Foundation

struct LearningToRewardRatio {
    var learningMinutes: Int
    var rewardMinutes: Int

    var ratio: Double {
        Double(rewardMinutes) / Double(learningMinutes)
    }

    var displayText: String {
        "\(learningMinutes) min learning = \(rewardMinutes) min reward"
    }

    var simplifiedRatio: String {
        let gcd = greatestCommonDivisor(learningMinutes, rewardMinutes)
        let simplified = "\(learningMinutes / gcd):\(rewardMinutes / gcd)"
        return simplified
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? a : greatestCommonDivisor(b, a % b)
    }

    static let presets: [(learning: Int, reward: Int)] = [
        (60, 60),   // 1:1
        (60, 30),   // 2:1
        (60, 20),   // 3:1
        (60, 15),   // 4:1
    ]
}
```

---

### Coordinator Pattern

#### ChallengeBuilderCoordinator.swift
State management and navigation logic:

```swift
import Foundation
import SwiftUI
import Observation

@Observable
class ChallengeBuilderCoordinator {
    enum Step: Int, CaseIterable, Identifiable {
        case details = 0
        case learningApps = 1
        case rewardApps = 2
        case rewardConfig = 3
        case schedule = 4
        case summary = 5

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .details: return "Create Your Challenge"
            case .learningApps: return "Select Learning Apps"
            case .rewardApps: return "Choose Reward Apps"
            case .rewardConfig: return "Set Up Rewards"
            case .schedule: return "Set Schedule"
            case .summary: return "Review Challenge"
            }
        }

        var stepNumber: Int { rawValue + 1 }
    }

    var currentStep: Step = .details
    var challengeData = ChallengeBuilderData()

    var canGoNext: Bool {
        validateCurrentStep()
    }

    var canGoPrevious: Bool {
        currentStep.rawValue > 0
    }

    var progressPercent: Double {
        Double(currentStep.rawValue + 1) / Double(Step.allCases.count)
    }

    func nextStep() {
        guard canGoNext else { return }
        guard currentStep.rawValue < Step.allCases.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = Step(rawValue: currentStep.rawValue + 1) ?? currentStep
        }
    }

    func previousStep() {
        guard canGoPrevious else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = Step(rawValue: currentStep.rawValue - 1) ?? currentStep
        }
    }

    func goToStep(_ step: Step) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }

    func reset() {
        currentStep = .details
        challengeData = ChallengeBuilderData()
    }

    private func validateCurrentStep() -> Bool {
        switch currentStep {
        case .details:
            return challengeData.isStep1Valid
        case .learningApps:
            return true  // No validation (empty = all apps)
        case .rewardApps:
            return true  // No validation
        case .rewardConfig:
            return challengeData.isStep3Valid
        case .schedule:
            return challengeData.isStep4Valid
        case .summary:
            return true  // All previous validations passed
        }
    }
}
```

---

## UI Components

### Component 1: ChallengeBuilderProgressIndicator.swift

Visual progress indicator showing current step:

```swift
import SwiftUI

struct ChallengeBuilderProgressIndicator: View {
    let currentStep: ChallengeBuilderCoordinator.Step
    let totalSteps: Int = 6

    var body: some View {
        VStack(spacing: 8) {
            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep.rawValue ? Color.primary : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            // Step text
            Text("Step \(currentStep.stepNumber) of \(totalSteps)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }
}
```

---

### Component 2: ChallengeBuilderNavigationFooter.swift

Reusable navigation buttons:

```swift
import SwiftUI

struct ChallengeBuilderNavigationFooter: View {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                // Previous button
                Button(action: onPrevious) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Previous")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(canGoPrevious ? .primary : .gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.clear)
                }
                .disabled(!canGoPrevious)

                // Next button
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canGoNext ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canGoNext)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
    }
}
```

---

### Component 3: GoalTypeHelpCard.swift

Expandable help card for goal types:

```swift
import SwiftUI

struct GoalTypeHelpCard: View {
    let goalType: ChallengeGoalType
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: goalType.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(goalType.accentColor)
                        .frame(width: 32, height: 32)
                        .background(goalType.accentColor.opacity(0.1))
                        .clipShape(Circle())

                    // Name
                    Text(goalType.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goalType.description)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    Text("Example: \(goalType.example)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(goalType.accentColor)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// Extension to ChallengeGoalType for help content
extension ChallengeGoalType {
    var description: String {
        switch self {
        case .dailyMinutes:
            return "Complete a specific number of minutes each day"
        case .weeklyMinutes:
            return "Complete a total number of minutes over the entire week"
        case .specificApps:
            return "Use only selected learning apps for a set amount of time"
        case .streak:
            return "Maintain consistent learning activity for consecutive days"
        case .pointsTarget:
            return "Earn a specific number of points from learning activities"
        }
    }

    var example: String {
        switch self {
        case .dailyMinutes:
            return "Read for 30 minutes every day"
        case .weeklyMinutes:
            return "Practice math for 120 minutes this week"
        case .specificApps:
            return "Use Duolingo for 20 minutes"
        case .streak:
            return "Learn for 7 days in a row"
        case .pointsTarget:
            return "Earn 500 points"
        }
    }
}
```

---

## Step Views Implementation

### Step 1: ChallengeDetailsStepView.swift

```swift
import SwiftUI

struct ChallengeDetailsStepView: View {
    @Binding var data: ChallengeBuilderData

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Challenge Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Challenge Name")
                        .font(.system(size: 16, weight: .semibold))

                    TextField("e.g., Weekday Reading Goal", text: $data.title)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.system(size: 16, weight: .semibold))

                    TextField("Add details about this challenge...", text: $data.description, axis: .vertical)
                        .font(.system(size: 16))
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }

                // Goal Type Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Goal Type")
                        .font(.system(size: 16, weight: .semibold))

                    ForEach(ChallengeGoalType.allCases, id: \.self) { type in
                        GoalTypeHelpCard(goalType: type)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(data.goalType == type ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                data.goalType = type
                            }
                    }
                }

                // Goal Quantification
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Target")
                        .font(.system(size: 16, weight: .semibold))

                    goalInputControl
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var goalInputControl: some View {
        // Implementation similar to existing ChallengeBuilderView
        // Sliders, steppers based on goal type
        EmptyView()
    }
}
```

---

## Data Persistence

### CoreData Schema Updates

Add new field to Challenge entity:

```swift
// Challenge+CoreDataProperties.swift
extension Challenge {
    @NSManaged public var learningToRewardRatioData: String?  // JSON: {"learning":60,"reward":30}
}

// Challenge+Helpers.swift
extension Challenge {
    var learningToRewardRatio: LearningToRewardRatio? {
        guard let data = learningToRewardRatioData,
              let jsonData = data.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LearningToRewardRatio.self, from: jsonData) else {
            // Default ratio if not set (backward compatibility)
            return LearningToRewardRatio(learningMinutes: 60, rewardMinutes: 30)
        }
        return decoded
    }

    func setLearningToRewardRatio(_ ratio: LearningToRewardRatio) {
        if let encoded = try? JSONEncoder().encode(ratio),
           let jsonString = String(data: encoded, encoding: .utf8) {
            learningToRewardRatioData = jsonString
        }
    }
}
```

### ChallengeService Updates

```swift
// Add parameters to createChallenge
func createChallenge(
    // ... existing parameters
    learningMinutes: Int,
    rewardMinutes: Int,
    bonusPercentage: Int,  // Now 0-50 instead of 5-25
    isFullDay: Bool
) async {
    let challenge = Challenge(context: context)
    // ... existing setup

    // NEW: Store ratio
    let ratio = LearningToRewardRatio(
        learningMinutes: learningMinutes,
        rewardMinutes: rewardMinutes
    )
    challenge.setLearningToRewardRatio(ratio)

    // NEW: Handle full day times
    if isFullDay {
        challenge.startTime = Calendar.current.startOfDay(for: Date())
        challenge.endTime = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
    } else {
        challenge.startTime = startTime
        challenge.endTime = endTime
    }

    challenge.bonusPercentage = Int16(bonusPercentage)

    // ... rest of implementation
}
```

---

## Testing Plan

### Unit Tests
- [ ] ChallengeBuilderData validation logic
- [ ] LearningToRewardRatio calculations
- [ ] Coordinator step navigation
- [ ] CoreData encoding/decoding of ratio

### Integration Tests
- [ ] Full flow: Details → Summary → Submit
- [ ] Navigation: Forward and backward through all steps
- [ ] Validation: Cannot proceed with invalid data
- [ ] Data persistence: Challenge saved correctly

### UI Tests
- [ ] All steps render correctly
- [ ] Goal type help cards expand/collapse
- [ ] Full Day toggle shows/hides time pickers
- [ ] Summary displays all data correctly
- [ ] Submit creates challenge
- [ ] Cancel dismisses without saving

### Edge Cases
- [ ] Empty learning app selection (should use all)
- [ ] Empty reward app selection (no rewards)
- [ ] Full day vs. custom time range
- [ ] No end date vs. specific end date
- [ ] Various goal types and values

---

## Migration & Rollout

### Phase 1: Parallel Development
- Build V2 alongside existing V1 (✅ complete – lives under `ChallengeBuilder/`)
- No invasive edits to V1 view (✅ old builder untouched besides feature flag hook)
- New files only (✅ all new SwiftUI steps/components isolated in subfolder)

### Phase 2: Feature Flag (Optional)
- Add environment variable: `USE_CHALLENGE_BUILDER_V2`
- ParentChallengesTabView now reads this flag to switch between V1 and the new multi-step flow (✅ implemented via scheme env var)
- Toggle between old/new in ParentChallengesTabView
- Beta test with subset of users

### Phase 3: Data Migration
- Add `learningToRewardRatioData` field to CoreData (JSON-encoded `LearningToRewardRatio`)
- Create migration for existing challenges
- Default ratio: 2:1 (60 min learning = 30 min reward)
- Expand bonusPercentage validation to 0-50%

### Phase 4: Full Replacement
- Remove feature flag
- Delete old ChallengeBuilderView code
- Archive V1 in documentation

---

## Timeline Estimate

| Phase | Task | Estimated Time |
|-------|------|----------------|
| 1 | Data models & coordinator | 2-3 hours |
| 2 | Base UI components | 2-3 hours |
| 3 | Step 1: Challenge Details | 2 hours |
| 4 | Step 2a & 2b: App Selection | 2 hours |
| 5 | Step 3: Reward Config | 2 hours |
| 6 | Step 4: Schedule | 1.5 hours |
| 7 | Step 5: Summary | 1.5 hours |
| 8 | Main container refactor | 2 hours |
| 9 | CoreData updates | 2 hours |
| 10 | Testing & polish | 3-4 hours |
| **Total** | | **20-23 hours** |

---

## Success Criteria

- ✅ Users can create challenges through 6-step guided flow
- ✅ Each step validates input before allowing progression
- ✅ Inline help explains goal types clearly
- ✅ Learning-to-reward ratio is configurable
- ✅ Bonus percentage range expanded to 0-50%
- ✅ Completed challenges unlock reward minutes based on the configured ratio + bonus
- ✅ Child celebration view announces the exact reward minutes earned
- ✅ App selection pills show real icons/names (per API limits) with compact centered layout
- ✅ Quick ratio presets now cover both effort-heavy (4:1…) and reward-heavy (1:4…) options
- ✅ Feature flag (`USE_CHALLENGE_BUILDER_V2`) documented and hooked up in `ParentChallengesTabView`
- ✅ Ratio/bonus configuration persists through Core Data (`learningToRewardRatioData`) and powers reward unlock logic/UI across parent + child surfaces
- ✅ Full Day toggle simplifies scheduling
- ✅ Summary provides complete review before submission
- ✅ All existing functionality preserved
- ✅ No regressions in challenge creation
- ✅ Code is maintainable and well-documented

---

## Appendix

### File Structure
```
ScreenTimeRewardsProject/
  ScreenTimeRewards/
    Views/
      ParentMode/
        ChallengeBuilder/
          ChallengeBuilderView.swift (refactored)
          ChallengeBuilderCoordinator.swift (new)

          Components/
            ChallengeBuilderProgressIndicator.swift (new)
            ChallengeBuilderNavigationFooter.swift (new)
            GoalTypeHelpCard.swift (new)

          Steps/
            ChallengeDetailsStepView.swift (new)
            LearningAppsStepView.swift (new)
            RewardAppsStepView.swift (new)
            RewardConfigStepView.swift (new)
            ScheduleStepView.swift (new)
            SummaryStepView.swift (new)
      ParentMode/
        ChallengeBuilderView.swift (original V1 kept for fallback/flag)

    Models/
      ChallengeBuilderData.swift (new)
      LearningToRewardRatio.swift (new)

    CoreData/
      Challenge+CoreDataProperties.swift (updated)
      Challenge+Helpers.swift (updated)

    Services/
      ChallengeService.swift (updated)

    ViewModels/
      ChallengeViewModel.swift (updated)

Documentation/
  CHALLENGE_BUILDER_V2.md (this file)
```

### Dependencies
- iOS 15.2+ (for FamilyControls Label API)
- SwiftUI
- CoreData
- Observation framework (for @Observable coordinator)

### References
- Current implementation: `ChallengeBuilderView.swift`
- Design system: Colors struct in ChallengeBuilderView
- App selection pattern: `AppSelectionRow` component
- Navigation pattern: Custom nav bars in existing views

---

**Document Version:** 1.0
**Last Updated:** January 2025
**Author:** Challenge Builder V2 Implementation Team
