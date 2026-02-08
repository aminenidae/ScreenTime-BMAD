# Parent Onboarding Flow Implementation Plan

**Version:** 1.0
**Date:** 2025-11-11
**Strategy:** Option A - Tiered Onboarding with Device-Specific Flows

---

## Table of Contents

1. [Overview](#overview)
2. [User Flow Architecture](#user-flow-architecture)
3. [Parent Device Flow](#parent-device-flow)
4. [Child Device Flow](#child-device-flow)
5. [Files to Create](#files-to-create)
6. [Files to Modify](#files-to-modify)
7. [Implementation Steps](#implementation-steps)
8. [Technical Specifications](#technical-specifications)
9. [Testing Checklist](#testing-checklist)
10. [Design Guidelines](#design-guidelines)

---

## Overview

### Goals
- Create a sophisticated dual-flow onboarding system
- Match standard parental control app patterns
- Parent device = free remote monitor (no paywall)
- Child device = monitored device (paywall required)
- Tiered approach: Show core value quickly, complete setup during trial

### Key Decisions
- **Parent Device Flow:** No paywall, guides installation on child device, shows QR code for pairing
- **Child Device Flow:** Includes authorization, quick learning app setup, and mandatory paywall
- **Pairing:** Not part of onboarding, happens post-setup from Settings
- **Back Navigation:** Fully supported throughout both flows
- **Subscription:** Only enforced on child device, trial auto-starts

---

## User Flow Architecture

```
App Launch
    ↓
Check Onboarding Status
    ↓
[Not Completed] → OnboardingFlowView
    ↓
Welcome Screen (common)
    ↓
Device Selection
    ↓
    ├─→ PARENT DEVICE (Remote Monitor)
    │   ├─→ Installation Guide
    │   ├─→ QR Code Generation
    │   └─→ Parent Dashboard (No Paywall)
    │
    └─→ CHILD DEVICE (Monitored)
        ├─→ Authorization Request
        ├─→ Quick Learning Setup
        ├─→ Paywall (Required)
        └─→ Setup Complete
```

---

## Parent Device Flow

**Purpose:** Guide parent to install app on child device and generate pairing QR code

### Flow Steps

1. **Welcome Screen**
   - Custom parent-focused messaging
   - Highlights: Remote monitoring, challenge creation, device management
   - Button: "Get Started"

2. **Device Selection**
   - Two options: Parent Device | Child Device
   - User selects "Parent Device"
   - Collects device name

3. **Installation Guide Screen** (NEW)
   - Header: "Set Up Remote Monitoring"
   - Instruction card with numbered steps:
     ```
     1. Download ScreenTime Rewards on your child's device
     2. Complete the setup on their device
     3. Return here to connect devices
     ```
   - Button: "I've Installed the App"
   - Progress indicator: Step 1 of 2

4. **Pairing QR Code Screen** (NEW)
   - Display QR code (generated via DevicePairingService)
   - Instructions: "On child device: Settings → Pair with Parent → Scan QR"
   - Waiting state with loading indicator
   - Success state when paired (or skip option)
   - Progress indicator: Step 2 of 2

5. **Parent Remote Dashboard**
   - Existing dashboard
   - Shows paired devices (or empty state)
   - No paywall anywhere

### Key Behaviors
- No subscription checks on parent device
- Parent device is always free (remote monitor only)
- QR code persists for future pairing attempts
- Can complete onboarding without child device paired

---

## Child Device Flow

**Purpose:** Set up monitoring with quick learning app selection and subscription gate

### Flow Steps

1. **Welcome Screen**
   - Child/family-focused messaging
   - "Transform Screen Time into Learning Time"
   - Button: "Get Started"

2. **Device Selection**
   - User selects "Child Device"
   - Collects device name

3. **Authorization Request** (EXISTING, extract from SetupFlowView)
   - Request FamilyControls permission
   - Required for app monitoring
   - Shows 3 benefits of authorization
   - Button: "Grant Permission"
   - Progress indicator: Step 1 of 4

4. **Quick Learning Setup** (NEW - Simplified)
   - Header: "Select 3-5 Learning Apps"
   - Subtitle: "Apps your child uses for education (you can add more later)"
   - Opens iOS FamilyActivityPicker
   - Shows simplified CategoryAssignmentView:
     - Grid of selected apps with icons
     - No inline editing
     - Default 10 pts/min for all apps
     - Message: "Customize points later in Learning tab"
   - Button: "Continue"
   - Progress indicator: Step 2 of 4

5. **Subscription Paywall** (EXISTING, modified for onboarding)
   - Full paywall UI with trial option
   - Required interaction (no dismiss button)
   - Shows Individual and Family tiers
   - Buttons: "Start Free Trial" | "Subscribe Now" | "Restore Purchase"
   - Progress indicator: Step 3 of 4

6. **Setup Complete**
   - Success checkmark animation
   - Quick tips for getting started
   - Optional: PIN setup for parent mode access
   - Button: "Start Using App"
   - Sets `hasCompletedChildOnboarding = true`
   - Progress indicator: Step 4 of 4

### Key Behaviors
- FamilyControls authorization is mandatory
- Learning app selection is required (minimum 1 app)
- Paywall cannot be skipped (must choose trial or purchase)
- Trial auto-starts in SubscriptionManager (existing behavior)
- No pairing step during onboarding

---

## Files to Create

### 1. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/OnboardingFlowView.swift`

**Purpose:** Main router that manages device selection and routes to appropriate coordinator

```swift
struct OnboardingFlowView: View {
    @StateObject private var deviceModeManager = DeviceModeManager.shared
    @AppStorage("hasCompletedParentOnboarding") private var parentComplete = false
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false
    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var selectedDeviceMode: DeviceMode?
    @State private var selectedDeviceName: String = ""

    enum OnboardingStep {
        case welcome
        case deviceSelection
        case parentFlow
        case childFlow
    }

    var body: some View {
        // Navigation logic based on step
    }
}
```

**Key Features:**
- Manages welcome + device selection (common to both flows)
- Routes to ParentOnboardingCoordinator or ChildOnboardingCoordinator
- Handles back navigation between coordinators
- Sets appropriate completion flags

---

### 2. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/ParentOnboardingCoordinator.swift`

**Purpose:** Manages parent device onboarding state machine

```swift
struct ParentOnboardingCoordinator: View {
    @State private var currentStep: ParentStep = .welcome
    @AppStorage("hasCompletedParentOnboarding") private var completed = false
    let deviceName: String

    enum ParentStep {
        case welcome
        case installationGuide
        case qrCode
        case complete
    }

    var body: some View {
        // Step management with back navigation
    }
}
```

**Key Features:**
- Linear flow: installation guide → QR code → dashboard
- Back button on each screen
- Progress indicators
- No paywall

---

### 3. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/ChildOnboardingCoordinator.swift`

**Purpose:** Manages child device onboarding state machine

```swift
struct ChildOnboardingCoordinator: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var currentStep: ChildStep = .authorization
    @AppStorage("hasCompletedChildOnboarding") private var completed = false
    let deviceName: String

    enum ChildStep {
        case authorization
        case learningSetup
        case paywall
        case complete
    }

    var body: some View {
        // Step management with back navigation
    }
}
```

**Key Features:**
- Linear flow: auth → learning setup → paywall → complete
- Back button on each screen
- Progress indicators
- Paywall required

---

### 4. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/ParentWelcomeScreen.swift`

**Purpose:** Welcome screen with parent-focused messaging

**Content:**
- App icon/logo at top
- Headline: "Transform Screen Time Management"
- 3 key features:
  - 📱 Monitor from anywhere - Remote dashboard for all devices
  - 🎯 Create challenges - Custom goals and rewards
  - 🔗 Connect devices - Secure device pairing
- Button: "Get Started"
- Uses AppTheme for styling

---

### 5. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/ParentDeviceSetupScreen.swift`

**Purpose:** Installation instructions for setting up child device

**UI Components:**
- Header: "Set Up Remote Monitoring"
- Instruction card with numbered steps:
  ```
  1️⃣ Download ScreenTime Rewards on your child's device
  2️⃣ Complete the setup on their device
  3️⃣ Return here to connect devices
  ```
- Note: "You'll need access to your child's device for initial setup"
- Button: "I've Installed the App"
- Back button
- Progress: Step 1 of 2

**Design:**
- Card-based layout
- Icons for each step
- Clear visual hierarchy
- AppTheme styling

---

### 6. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/ParentPairingScreen.swift`

**Purpose:** Display QR code and manage pairing state

**UI Components:**
- Header: "Connect Devices"
- QR code (large, centered)
- Instructions: "On child device: Settings → Pair with Parent → Scan this code"
- Waiting state: "Waiting for connection..." with spinner
- Success state: Checkmark animation + "Connected!"
- Button: "Skip for Now" (goes to dashboard)
- Back button
- Progress: Step 2 of 2

**Technical:**
- Use `DevicePairingService.createPairingSession()` to generate QR
- Listen for pairing completion
- Handle errors (CloudKit unavailable, etc.)

---

### 7. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/QuickLearningSetupScreen.swift`

**Purpose:** Simplified learning app selection for onboarding

**UI Components:**
- Header: "Select Learning Apps"
- Subtitle: "Choose 3-5 apps your child uses for education"
- Button: "Select Apps" (opens FamilyActivityPicker)
- Selected apps grid (after selection):
  - App icon + name
  - Default badge: "10 pts/min"
- Message: "You can customize points later in the Learning tab"
- Button: "Continue"
- Back button
- Progress: Step 2 of 4

**Technical:**
- Uses FamilyActivityPicker (iOS native)
- Saves to CategoryAssignmentView in "quick mode"
- Sets all apps to Learning category, 10 pts/min default
- Minimum 1 app required to continue
- Uses AppUsageViewModel to save selections

---

## Files to Modify

### 1. `/ScreenTimeRewardsProject/ScreenTimeRewards/ScreenTimeRewardsApp.swift`

**Location:** RootView within ScreenTimeRewardsApp

**Current Logic:**
```swift
struct RootView: View {
    var body: some View {
        if !subscriptionManager.hasAccess {
            SubscriptionLockoutView()
        } else if modeManager.needsDeviceSelection {
            DeviceSelectionView()
        } else if modeManager.isParentDevice {
            ParentRemoteDashboardView()
        } else if modeManager.isChildDevice {
            // Child flow...
        }
    }
}
```

**Modifications:**
```swift
struct RootView: View {
    @AppStorage("hasCompletedParentOnboarding") private var parentComplete = false
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false

    private var hasCompletedOnboarding: Bool {
        parentComplete || childComplete
    }

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingFlowView()  // NEW: First check
        } else if !subscriptionManager.hasAccess && modeManager.isChildDevice {
            SubscriptionLockoutView()  // Only for child devices
        } else if modeManager.isParentDevice {
            ParentRemoteDashboardView()
        } else if modeManager.isChildDevice {
            // Existing child mode logic...
        }
    }
}
```

**Key Changes:**
- Add onboarding check FIRST
- Only show SubscriptionLockoutView for child devices
- Parent device bypasses all subscription checks

---

### 2. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/DeviceSelection/DeviceSelectionView.swift`

**Current Behavior:**
- Standalone view that sets device mode immediately
- Dismisses after confirmation

**Modifications:**

Add optional callback parameter:
```swift
struct DeviceSelectionView: View {
    var onDeviceSelected: ((DeviceMode, String) -> Void)?  // NEW
    var showBackButton: Bool = false  // NEW

    // In confirmation dialog action:
    if let callback = onDeviceSelected {
        callback(mode, deviceName)  // Call callback instead of setting directly
    } else {
        DeviceModeManager.shared.setDeviceMode(mode, deviceName: deviceName)
    }
}
```

**Usage Contexts:**
- **Onboarding:** Pass callback to route to next step
- **Standalone:** No callback, sets mode and dismisses as before

---

### 3. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionPaywallView.swift`

**Current Behavior:**
- Standalone view with dismiss button
- Can be dismissed without interaction

**Modifications:**

Add onboarding parameters:
```swift
struct SubscriptionPaywallView: View {
    var isOnboarding: Bool = false  // NEW
    var onComplete: (() -> Void)?  // NEW
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            // Existing paywall UI...

            // Modify dismiss button:
            if !isOnboarding {
                Button("Maybe Later") { dismiss() }
            }
        }
        .toolbar {
            if !isOnboarding {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // In purchase/trial success handler:
    if let completion = onComplete {
        completion()
    } else {
        dismiss()
    }
}
```

**Key Changes:**
- Hide dismiss/close buttons when `isOnboarding == true`
- Call `onComplete` callback after subscription action
- Prevent dismissal during onboarding

---

### 4. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/CategoryAssignmentView.swift`

**Current Behavior:**
- Full configuration with inline point editing
- Detailed per-app settings

**Modifications:**

Add quick mode parameter:
```swift
struct CategoryAssignmentView: View {
    var quickMode: Bool = false  // NEW

    var body: some View {
        VStack {
            if quickMode {
                // Simplified UI
                ForEach(selectedApps) { app in
                    HStack {
                        AppIcon(app.token)
                        Text(app.name)
                        Spacer()
                        Text("10 pts/min")
                            .foregroundColor(.secondary)
                    }
                }

                Text("Customize points later in Learning tab")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Continue") {
                    saveWithDefaults()  // Save all with 10 pts/min
                }
            } else {
                // Existing detailed UI with inline editing
            }
        }
    }

    private func saveWithDefaults() {
        // Save all apps with default 10 pts/min, no per-app config
    }
}
```

**Key Changes:**
- Add `quickMode` for simplified onboarding
- Default all apps to 10 pts/min when in quick mode
- Show informational message about customizing later

---

### 5. `/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Setup/SetupFlowView.swift`

**Current Structure:**
- Contains WelcomeScreen, AuthorizationRequestScreen, PIN setup, Complete

**Modifications:**

Extract AuthorizationRequestScreen to standalone component:
```swift
// Create new file: /Views/Onboarding/AuthorizationRequestScreen.swift
struct AuthorizationRequestScreen: View {
    var onAuthorized: () -> Void  // Callback when authorized
    var onSkip: (() -> Void)?  // Optional skip (only for non-onboarding)

    var body: some View {
        // Existing authorization UI
        // Call onAuthorized() when permission granted
    }
}
```

**Impact:**
- Can be reused in ChildOnboardingCoordinator
- Maintains existing behavior in SetupFlowView
- Cleaner separation of concerns

---

## Implementation Steps

### Phase 1: Core Infrastructure (Foundation)

**Goal:** Set up the routing and coordinator structure

1. **Create OnboardingFlowView.swift**
   - Main router with welcome + device selection
   - State management for flow progression
   - Routing logic to coordinators

2. **Create ParentOnboardingCoordinator.swift**
   - Skeleton with step enum
   - Navigation state management
   - Placeholder screens

3. **Create ChildOnboardingCoordinator.swift**
   - Skeleton with step enum
   - Navigation state management
   - Placeholder screens

4. **Update RootView in ScreenTimeRewardsApp.swift**
   - Add onboarding status checks
   - Route to OnboardingFlowView
   - Test routing logic

**Testing:**
- App launches OnboardingFlowView when onboarding not completed
- Coordinators display placeholder content
- Navigation structure works

---

### Phase 2: Parent Device Flow

**Goal:** Build complete parent device onboarding

5. **Create ParentWelcomeScreen.swift**
   - Parent-focused copy and features
   - Theme styling
   - "Get Started" button

6. **Create ParentDeviceSetupScreen.swift**
   - Installation instruction card
   - Numbered steps with icons
   - "I've Installed the App" button
   - Back navigation

7. **Create ParentPairingScreen.swift**
   - QR code generation via DevicePairingService
   - Waiting state UI
   - Success state animation
   - Skip option
   - Error handling

8. **Wire up ParentOnboardingCoordinator**
   - Connect all screens
   - Implement step progression
   - Add back button navigation
   - Set completion flag

9. **Test Parent Device Flow**
   - Complete flow end-to-end
   - Test back navigation
   - Test QR code generation
   - Test completion and routing to dashboard
   - Verify no paywall appears

---

### Phase 3: Child Device Flow

**Goal:** Build complete child device onboarding with paywall

10. **Extract AuthorizationRequestScreen.swift**
    - Move from SetupFlowView to standalone component
    - Add completion callback
    - Update SetupFlowView to use new component
    - Test existing child setup still works

11. **Create QuickLearningSetupScreen.swift**
    - FamilyActivityPicker integration
    - Quick mode CategoryAssignmentView
    - App selection UI
    - Minimum validation (at least 1 app)

12. **Modify CategoryAssignmentView.swift**
    - Add `quickMode` parameter
    - Implement simplified UI for quick mode
    - Add default saving logic (10 pts/min)
    - Test both modes (quick and full)

13. **Modify SubscriptionPaywallView.swift**
    - Add `isOnboarding` parameter
    - Add `onComplete` callback
    - Conditional dismiss button
    - Test onboarding vs standalone contexts

14. **Wire up ChildOnboardingCoordinator**
    - Connect all screens in order
    - Implement step progression
    - Add back button navigation
    - Set completion flag

15. **Test Child Device Flow**
    - Complete flow end-to-end
    - Test authorization grant/deny
    - Test learning app selection
    - Test paywall interaction (trial and purchase)
    - Test back navigation
    - Verify completion routing

---

### Phase 4: Device Selection Integration

**Goal:** Connect common onboarding to device-specific flows

16. **Modify DeviceSelectionView.swift**
    - Add `onDeviceSelected` callback
    - Add `showBackButton` parameter
    - Implement conditional behavior
    - Test both callback and direct modes

17. **Complete OnboardingFlowView integration**
    - Handle device selection callback
    - Route to correct coordinator based on selection
    - Pass device name to coordinators
    - Implement back navigation from coordinators

18. **Test Device Selection Branching**
    - Select Parent Device → Parent flow
    - Select Child Device → Child flow
    - Navigate back to device selection
    - Change device selection mid-flow

---

### Phase 5: Polish & Edge Cases

**Goal:** Handle all edge cases and improve UX

19. **Add Progress Indicators**
    - Parent flow: "Step X of 2"
    - Child flow: "Step X of 4"
    - Visual progress bars where appropriate

20. **Implement Loading States**
    - QR code generation loading
    - FamilyControls permission waiting
    - Subscription processing
    - App saving progress

21. **Handle Error Scenarios**
    - Authorization denied
    - CloudKit unavailable (fallback mode)
    - Subscription purchase failure
    - Network errors
    - App crashes mid-onboarding

22. **Onboarding Resume Logic**
    - Save current step to UserDefaults
    - Resume from last step on app restart
    - Clear resume state on completion

23. **Empty State Handling**
    - No learning apps selected warning
    - No child device paired yet (parent dashboard)
    - Subscription lockout screens

---

### Phase 6: Testing & Validation

**Goal:** Comprehensive testing of all flows

24. **Functional Testing**
    - Run through testing checklist (see below)
    - Test on multiple device types (iPhone, iPad)
    - Test iOS version compatibility

25. **Integration Testing**
    - Trial auto-start verification
    - Device pairing after onboarding
    - Post-onboarding feature access
    - Subscription enforcement

26. **UX Testing**
    - Back navigation feels natural
    - Progress is clear
    - Error messages are helpful
    - Loading states are smooth

27. **Final Polish**
    - Animation timing
    - Transition smoothness
    - Text copywriting review
    - Accessibility labels
    - Dark mode support

---

## Technical Specifications

### State Management

**Onboarding Completion:**
```swift
@AppStorage("hasCompletedParentOnboarding") private var parentComplete = false
@AppStorage("hasCompletedChildOnboarding") private var childComplete = false
```

**Device Mode:**
```swift
DeviceModeManager.shared.deviceMode  // .parentDevice or .childDevice
DeviceModeManager.shared.deviceName  // User-provided name
DeviceModeManager.shared.deviceID    // Auto-generated UUID
```

**Subscription:**
```swift
SubscriptionManager.shared.hasAccess  // Bool - trial or active subscription
SubscriptionManager.shared.subscription  // UserSubscription entity
```

---

### Navigation Architecture

**Pattern:** Coordinator Pattern

Each flow has a coordinator that manages:
- Current step enum
- Step progression logic
- Back navigation
- Completion handling

**Example:**
```swift
struct ParentOnboardingCoordinator: View {
    @State private var currentStep: ParentStep = .installationGuide

    var body: some View {
        switch currentStep {
        case .installationGuide:
            ParentDeviceSetupScreen(onNext: { currentStep = .qrCode })
        case .qrCode:
            ParentPairingScreen(onComplete: { markComplete() })
        }
    }
}
```

---

### Service Integration

**DevicePairingService:**
```swift
// Generate QR code for pairing
let session = try await DevicePairingService.shared.createPairingSession()
// session.qrCodeImage - Display in QR code screen
```

**SubscriptionManager:**
```swift
// Already auto-starts trial on first launch
// No explicit call needed

// Check access (child device only)
if SubscriptionManager.shared.hasAccess {
    // Allow app usage
}
```

**DeviceModeManager:**
```swift
// Set device mode after selection
DeviceModeManager.shared.setDeviceMode(.parentDevice, deviceName: "Dad's iPhone")

// Check mode
if DeviceModeManager.shared.isParentDevice {
    // Show parent features
}
```

**AppUsageViewModel:**
```swift
// Save learning apps in quick mode
appUsageViewModel.saveSelectedApps(
    apps: selectedApps,
    category: .learning,
    pointsPerMinute: 10  // Default for all
)
```

---

### Data Persistence

**UserDefaults Keys:**
```swift
"hasCompletedParentOnboarding" -> Bool
"hasCompletedChildOnboarding" -> Bool
"onboardingCurrentStep" -> String (for resume)
"deviceMode" -> String (from DeviceModeManager)
"deviceID" -> String (from DeviceModeManager)
"deviceName" -> String (from DeviceModeManager)
```

**CoreData Entities:**
- `UserSubscription` - Trial and subscription data
- `RegisteredDevice` - Paired device information
- `Challenge` - Challenges created (post-onboarding)
- App categories stored in AppUsageViewModel state

---

### Routing Logic

```swift
// In RootView
if !hasCompletedOnboarding {
    OnboardingFlowView()
} else if modeManager.isParentDevice {
    ParentRemoteDashboardView()  // Never check subscription
} else if modeManager.isChildDevice {
    if !subscriptionManager.hasAccess {
        SubscriptionLockoutView()  // Only for child
    } else {
        // Child mode views
    }
}
```

---

## Testing Checklist

### Parent Device Flow

- [ ] Welcome screen displays with parent-focused copy
- [ ] "Get Started" navigates to device selection
- [ ] Selecting "Parent Device" routes to installation guide
- [ ] Installation guide displays all 3 steps clearly
- [ ] "I've Installed the App" navigates to QR code screen
- [ ] QR code generates successfully via DevicePairingService
- [ ] QR code is scannable (test with real child device)
- [ ] Waiting state displays while unpaired
- [ ] Success state shows when child device pairs
- [ ] "Skip for Now" routes to parent dashboard
- [ ] Back button works from QR screen to guide
- [ ] Back button works from guide to device selection
- [ ] Parent dashboard appears after completion
- [ ] `hasCompletedParentOnboarding` is set to true
- [ ] No paywall appears anywhere in parent flow
- [ ] Restarting app goes directly to parent dashboard
- [ ] Error handling for CloudKit unavailable

### Child Device Flow

- [ ] Welcome screen displays
- [ ] "Get Started" navigates to device selection
- [ ] Selecting "Child Device" routes to authorization
- [ ] Authorization screen requests FamilyControls permission
- [ ] Permission granted continues to learning setup
- [ ] Permission denied shows appropriate error
- [ ] Learning setup opens FamilyActivityPicker
- [ ] Selected apps display in grid
- [ ] Minimum 1 app required to continue
- [ ] Quick mode CategoryAssignmentView shows simplified UI
- [ ] All apps default to 10 pts/min
- [ ] "Continue" navigates to paywall
- [ ] Paywall displays with no dismiss button
- [ ] "Start Free Trial" creates trial and continues
- [ ] "Subscribe Now" opens purchase flow
- [ ] Successful purchase continues to complete screen
- [ ] Back button works through all steps
- [ ] Complete screen displays success state
- [ ] `hasCompletedChildOnboarding` is set to true
- [ ] Restarting app bypasses onboarding
- [ ] Learning apps are saved correctly
- [ ] Trial is active after completion
- [ ] Subscription lockout works if trial expires

### Integration Testing

- [ ] Trial auto-starts on first app launch
- [ ] Parent device never checks subscription
- [ ] Child device enforces subscription
- [ ] Device mode persists after onboarding
- [ ] Learning apps appear in Learning tab
- [ ] Can add reward apps post-onboarding
- [ ] Can create challenges post-onboarding
- [ ] Device pairing works after both onboarded
- [ ] Switching between parent/child mode works
- [ ] App data syncs correctly (if using iCloud)

### UX & Polish

- [ ] All transitions are smooth
- [ ] Loading states display appropriately
- [ ] Error messages are clear and helpful
- [ ] Progress indicators update correctly
- [ ] Back navigation feels natural
- [ ] No orphaned states (can always progress or go back)
- [ ] Dark mode works throughout
- [ ] AppTheme colors used consistently
- [ ] Text is readable and typo-free
- [ ] VoiceOver labels are present
- [ ] Works on iPhone (all sizes)
- [ ] Works on iPad (proper layout)

### Edge Cases

- [ ] App crash during onboarding resumes correctly
- [ ] Network loss during QR generation handled
- [ ] Purchase failure shows retry option
- [ ] Multiple rapid back-forward navigation works
- [ ] Changing device selection mid-flow works
- [ ] Onboarding with no internet connection
- [ ] Onboarding with restricted permissions
- [ ] Very long device name handles gracefully

---

## Design Guidelines

### Theme Usage

All screens should use `AppTheme` for consistency:

```swift
import Theme

// Colors
AppTheme.Colors.vibrantTeal      // Primary brand color
AppTheme.Colors.sunnyYellow      // Highlights, warnings
AppTheme.Colors.playfulCoral     // Rewards, CTAs
AppTheme.Colors.deepNavy         // Dark backgrounds
AppTheme.Colors.lightCream       // Light backgrounds

// Contextual functions (auto dark mode)
AppTheme.background(for: colorScheme)
AppTheme.card(for: colorScheme)
AppTheme.textPrimary(for: colorScheme)
AppTheme.textSecondary(for: colorScheme)

// Typography
AppTheme.Typography.largeTitle
AppTheme.Typography.title
AppTheme.Typography.body
AppTheme.Typography.caption

// Spacing
AppTheme.Spacing.xs   // 4pt
AppTheme.Spacing.sm   // 8pt
AppTheme.Spacing.md   // 16pt
AppTheme.Spacing.lg   // 24pt
AppTheme.Spacing.xl   // 32pt

// Corner radius
AppTheme.CornerRadius.small   // 8pt
AppTheme.CornerRadius.medium  // 12pt
AppTheme.CornerRadius.large   // 16pt
```

---

### Layout Patterns

**Card-based screens:**
```swift
VStack(spacing: AppTheme.Spacing.lg) {
    // Header
    Text("Screen Title")
        .font(AppTheme.Typography.largeTitle)

    // Instruction card
    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
        // Card content
    }
    .padding(AppTheme.Spacing.lg)
    .background(AppTheme.card(for: colorScheme))
    .cornerRadius(AppTheme.CornerRadius.large)

    Spacer()

    // Bottom CTA
    Button("Continue") { }
        .buttonStyle(PrimaryButtonStyle())
}
.padding(AppTheme.Spacing.lg)
.background(AppTheme.background(for: colorScheme))
```

**Progress indicators:**
```swift
HStack {
    Text("Step \(currentStep) of \(totalSteps)")
        .font(AppTheme.Typography.caption)
        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

    Spacer()
}
```

**Back buttons:**
```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button(action: { goBack() }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
        }
    }
}
```

---

### Animation Guidelines

**Page transitions:**
```swift
.transition(.asymmetric(
    insertion: .move(edge: .trailing),
    removal: .move(edge: .leading)
))
.animation(.easeInOut(duration: 0.3), value: currentStep)
```

**Success states:**
```swift
// Checkmark animation
Image(systemName: "checkmark.circle.fill")
    .font(.system(size: 60))
    .foregroundColor(.green)
    .scaleEffect(showSuccess ? 1.0 : 0.1)
    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showSuccess)
```

**Loading states:**
```swift
ProgressView()
    .progressViewStyle(CircularProgressViewStyle())
    .scaleEffect(1.5)
```

---

### Copy Guidelines

**Tone:**
- Friendly and encouraging
- Clear and concise
- Parent-focused (empowering, not restrictive)
- Action-oriented

**Examples:**

✅ Good:
- "Transform Screen Time into Learning Time"
- "Monitor from anywhere with our remote dashboard"
- "Create custom challenges your child will love"

❌ Avoid:
- "Restrict your child's device usage" (too negative)
- "Surveillance and monitoring capabilities" (too clinical)
- "Control every aspect of screen time" (too controlling)

**Button Labels:**
- Use action verbs: "Get Started", "Continue", "Grant Permission"
- Be specific: "I've Installed the App" vs "Next"
- Positive framing: "Start Free Trial" vs "Begin Free Period"

---

## Additional Notes

### Why Two Separate Completion Flags?

We use separate flags (`hasCompletedParentOnboarding` and `hasCompletedChildOnboarding`) instead of a single flag because:

1. **Device switching:** User might set up as parent, then later reset and use as child
2. **Multi-device households:** Same Apple ID on multiple devices with different roles
3. **Debugging:** Easier to test flows independently
4. **Analytics:** Track which flow users complete more often

---

### Subscription Logic Clarification

**Parent Device:**
- Never checks subscription
- All features always available
- Acts as remote monitor only
- Subscription verified through child device pairing

**Child Device:**
- Trial auto-starts on first launch (existing behavior in SubscriptionManager)
- Paywall during onboarding (before full app access)
- Subscription enforced throughout app usage
- Lockout screen if subscription expires

**Sync:**
- Both devices can use same Apple ID
- Subscription status syncs via iCloud (if enabled)
- Family Sharing allows parent to subscribe once for all devices

---

### Future Enhancements (Not in This Plan)

**Post-v1 features to consider:**

1. **Onboarding Resume:**
   - Save progress between steps
   - "Pick up where you left off" if app closes mid-flow

2. **Progressive Onboarding:**
   - Show tooltips for features post-onboarding
   - "Day 2: Set up reward apps!" push notifications

3. **Onboarding Skip:**
   - Allow advanced users to skip and explore
   - Show onboarding checklist in settings

4. **Multi-child Support:**
   - Onboarding for adding 2nd, 3rd child device
   - Streamlined flow for additional devices

5. **Video Tutorials:**
   - Embedded short videos explaining features
   - QR code scanning tutorial

---

## Success Criteria

### Metrics to Track

1. **Completion Rate:**
   - % of users who start onboarding and finish
   - Target: >80% completion rate

2. **Time to Complete:**
   - Average time from launch to onboarding complete
   - Parent flow target: <3 minutes
   - Child flow target: <5 minutes

3. **Drop-off Points:**
   - Where users abandon onboarding
   - Iterate on highest drop-off screens

4. **Trial → Paid Conversion:**
   - % of trial users who subscribe after onboarding
   - Benchmark against industry standards (typically 2-5%)

5. **Feature Usage:**
   - % who create challenges within 7 days
   - % who set up reward apps within 7 days
   - Indicates onboarding effectiveness

---

## Conclusion

This implementation plan provides a complete, production-ready onboarding system that:

✅ Matches standard parental control app patterns
✅ Respects user time with tiered approach
✅ Demonstrates value before asking for payment (child device)
✅ Provides free remote monitoring (parent device)
✅ Handles complex dual-flow logic cleanly
✅ Includes comprehensive testing and polish

The Dev agent should follow phases sequentially, testing each phase before moving to the next. All design decisions are documented and justified.

**Estimated implementation time:** 3-5 days for experienced SwiftUI developer

**Ready to implement!** 🚀
