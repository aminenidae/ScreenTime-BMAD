# User Session Implementation Plan
## Parent and Child Mode Feature

**Date:** October 26, 2025
**Feature:** Dual User Profile System with Authentication
**Status:** Ready for Implementation

---

## Executive Summary

This document outlines the implementation plan for adding Parent and Child user profiles to the ScreenTime Rewards application. The Parent Mode will be protected by Apple's biometric authentication (FaceID/TouchID) or device PIN, while Child Mode will be directly accessible with a simplified, read-only view.

---

## 1. Feature Requirements

### 1.1 Parent Mode
- **Access:** Protected by biometric authentication (FaceID/TouchID) or device PIN
- **Functionality:** Full access to all existing features
  - Learning Apps tab (view, add, remove, configure)
  - Reward Apps tab (view, add, remove, unlock/lock, configure)
  - Category assignment
  - Points configuration
  - Monitoring controls
  - App usage statistics
  - All management and configuration features

### 1.2 Child Mode
- **Access:** Directly accessible without authentication
- **Functionality:** Read-only view showing:
  - Total available points
  - Total earned points
  - List of **used apps only** (apps with recorded usage time > 0)
    - Learning apps: Show app name, time used, points earned
    - Reward apps: Show app name, time used, lock status
  - Simple, child-friendly interface
  - No ability to modify settings or unlock apps

### 1.3 Mode Selection
- Initial view when app launches
- Two clear buttons: "Parent Mode" and "Child Mode"
- Parent Mode button triggers authentication before access
- Child Mode button provides immediate access

---

## 2. Architecture Design

### 2.1 Component Overview

```
ScreenTimeRewardsApp (root)
    └── ModeSelectionView (new)
        ├── ParentModeContainer (new wrapper)
        │   ├── AuthenticationService (handles biometric/PIN)
        │   └── MainTabView (existing - all current features)
        │       ├── LearningTabView
        │       └── RewardsTabView
        └── ChildModeView (new)
            └── ChildDashboardView (new)
```

### 2.2 New Components

#### 2.2.1 SessionManager
**Purpose:** Manage current user session and mode state
**Responsibilities:**
- Track active user mode (parent/child)
- Manage authentication state for parent mode
- Provide session lifecycle management
- Persist last authentication time (for auto-timeout)

**Properties:**
```swift
enum UserMode {
    case none
    case parent
    case child
}

@Published var currentMode: UserMode
@Published var isParentAuthenticated: Bool
var lastAuthenticationTime: Date?
```

**Methods:**
```swift
func enterParentMode(authenticated: Bool)
func enterChildMode()
func exitToSelection()
func requiresReAuthentication() -> Bool
```

#### 2.2.2 AuthenticationService
**Purpose:** Handle biometric and PIN authentication using LocalAuthentication framework
**Responsibilities:**
- Request biometric authentication (FaceID/TouchID)
- Fallback to device PIN if biometric fails
- Handle authentication errors gracefully
- Provide user-friendly error messages

**Key Methods:**
```swift
func authenticate(reason: String, completion: @escaping (Result<Void, AuthError>) -> Void)
func canAuthenticateWithBiometrics() -> Bool
func biometricType() -> BiometricType // .faceID, .touchID, .none
```

**Implementation:**
```swift
import LocalAuthentication

class AuthenticationService {
    func authenticate(reason: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(.failure(.notAvailable))
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(.authenticationFailed))
                }
            }
        }
    }
}
```

#### 2.2.3 ModeSelectionView
**Purpose:** Initial view for selecting Parent or Child mode
**Responsibilities:**
- Display mode selection options
- Trigger authentication for Parent mode
- Navigate to appropriate mode view
- Handle authentication failures

**UI Layout:**
```
┌─────────────────────────────────┐
│                                 │
│    ScreenTime Rewards           │
│                                 │
│    ┌───────────────────────┐   │
│    │   👨‍👩‍👧‍👦 Parent Mode    │   │
│    │   (Protected)          │   │
│    └───────────────────────┘   │
│                                 │
│    ┌───────────────────────┐   │
│    │   👶 Child Mode        │   │
│    │   (Open Access)        │   │
│    └───────────────────────┘   │
│                                 │
└─────────────────────────────────┘
```

#### 2.2.4 ChildModeView
**Purpose:** Child-friendly dashboard showing usage and points
**Responsibilities:**
- Display total available points (large, prominent)
- Show total earned points
- List only used apps (usage time > 0)
- Differentiate between learning and reward apps
- Read-only interface (no buttons to modify)

**UI Layout:**
```
┌─────────────────────────────────┐
│  Child Dashboard        [Exit]  │
├─────────────────────────────────┤
│                                 │
│      Available Points           │
│          ┌─────┐                │
│          │ 450 │                │
│          └─────┘                │
│                                 │
│      Total Earned: 650          │
│      Reserved: 200              │
│                                 │
├─────────────────────────────────┤
│  📚 Learning Apps Used          │
├─────────────────────────────────┤
│  📖 Khan Academy                │
│      ⏱ 25 min • 250 pts earned  │
│                                 │
│  🧮 Duolingo                    │
│      ⏱ 15 min • 150 pts earned  │
│                                 │
├─────────────────────────────────┤
│  🎮 Reward Apps Used            │
├─────────────────────────────────┤
│  🎮 Minecraft                   │
│      ⏱ 10 min • 🔓 Unlocked     │
│                                 │
│  📺 YouTube                     │
│      ⏱ 5 min • 🔒 Locked        │
│                                 │
└─────────────────────────────────┘
```

#### 2.2.5 ParentModeContainer
**Purpose:** Wrapper for existing MainTabView with authentication guard
**Responsibilities:**
- Enforce authentication before showing MainTabView
- Show authentication UI when not authenticated
- Provide "Exit Parent Mode" option
- Handle session timeout (optional feature)

---

## 3. Data Flow

### 3.1 App Launch Flow

```
1. App Launches
   └─> ScreenTimeRewardsApp
       └─> ModeSelectionView
           ├─> User taps "Parent Mode"
           │   └─> AuthenticationService.authenticate()
           │       ├─> Success: SessionManager.enterParentMode()
           │       │   └─> Navigate to ParentModeContainer
           │       │       └─> Show MainTabView (existing)
           │       └─> Failure: Show error alert
           │           └─> Stay on ModeSelectionView
           │
           └─> User taps "Child Mode"
               └─> SessionManager.enterChildMode()
                   └─> Navigate to ChildModeView
                       └─> Show ChildDashboardView
```

### 3.2 Data Access Patterns

#### Parent Mode:
- Full read/write access to AppUsageViewModel
- Can modify all settings and configurations
- Can trigger monitoring start/stop
- Can lock/unlock reward apps

#### Child Mode:
- Read-only access to AppUsageViewModel
- Filter apps to show only used apps (totalSeconds > 0)
- Display computed values (points, usage time)
- No ability to modify any settings

---

## 4. Implementation Plan

### Phase 1: Foundation (Day 1) - COMPLETED ✅
**Completed:** October 26, 2025
**Tasks:**
1. Create `SessionManager.swift`
   - Enum UserMode
   - Published properties for mode tracking
   - Session lifecycle methods

2. Create `AuthenticationService.swift`
   - Import LocalAuthentication
   - Implement authenticate() method
   - Add biometric capability detection
   - Error handling and user messaging

3. Create `AuthError.swift`
   - Define error types
   - User-friendly error descriptions

**Files Created:**
- `/Services/SessionManager.swift`
- `/Services/AuthenticationService.swift`
- `/Models/AuthError.swift`

**Acceptance Criteria:**
- ✅ SessionManager can track mode state
- ✅ AuthenticationService can trigger biometric prompt
- ✅ Error handling works correctly

**Completion Report:** See [PHASE1_COMPLETION_REPORT.md](ScreenTimeRewardsProject/docs/PHASE1_COMPLETION_REPORT.md) for detailed information.

---

### Phase 2: Mode Selection (Day 1-2) - COMPLETED ✅
**Completed:** October 26, 2025
**Tasks:**
1. Create `ModeSelectionView.swift`
   - Two prominent buttons (Parent/Child)
   - Integrate with SessionManager
   - Trigger authentication for Parent mode
   - Handle authentication errors

2. Update `ScreenTimeRewardsApp.swift`
   - Initialize SessionManager
   - Show ModeSelectionView as root view
   - Add environment objects

**Files Created:**
- `/Views/ModeSelectionView.swift`

**Files Modified:**
- `/ScreenTimeRewardsApp.swift`

**Acceptance Criteria:**
- ✅ Mode selection view appears on launch
- ✅ Parent mode button triggers authentication
- ✅ Child mode button navigates immediately
- ✅ Error messages display correctly

**Completion Report:** See [PHASE2_COMPLETION_REPORT.md](ScreenTimeRewardsProject/docs/PHASE2_COMPLETION_REPORT.md) for detailed information.

---

### Phase 3: Child Mode Views (Day 2-3)
**Tasks:**
1. Create `ChildModeView.swift`
   - Navigation container
   - Exit button
   - Inject AppUsageViewModel

2. Create `ChildDashboardView.swift`
   - Points display (large, prominent)
   - Filtered used apps list
   - Learning apps section
   - Reward apps section
   - Read-only interface

3. Add filtering logic to AppUsageViewModel
   - Method to get used learning apps
   - Method to get used reward apps
   - Computed properties for child mode

**Files to Create:**
- `/Views/ChildMode/ChildModeView.swift`
- `/Views/ChildMode/ChildDashboardView.swift`

**Files to Modify:**
- `/ViewModels/AppUsageViewModel.swift` (add filtering methods)

**Acceptance Criteria:**
- Child dashboard displays points correctly
- Only apps with usage > 0 are shown
- Clear distinction between learning/reward apps
- No interactive controls visible
- Exit button returns to mode selection

---

### Phase 4: Parent Mode Integration (Day 3)
**Tasks:**
1. Create `ParentModeContainer.swift`
   - Wrap existing MainTabView
   - Add authentication guard
   - Add "Exit Parent Mode" button
   - Handle session management

2. Update navigation flow
   - Ensure proper navigation from selection to parent mode
   - Test deep linking and state restoration

**Files to Create:**
- `/Views/ParentMode/ParentModeContainer.swift`

**Files to Modify:**
- `/ScreenTimeRewardsApp.swift`

**Acceptance Criteria:**
- Parent mode requires authentication
- MainTabView functions as before
- Exit button returns to mode selection
- All existing features work correctly

---

### Phase 5: Testing and Polish (Day 4)
**Tasks:**
1. Test authentication flows
   - FaceID success/failure
   - TouchID success/failure
   - PIN fallback
   - No biometric available scenario

2. Test mode switching
   - Parent to selection
   - Child to selection
   - Multiple switches

3. Test data consistency
   - Child mode shows correct data
   - Parent mode can modify everything
   - Real-time updates work

4. UI/UX polish
   - Child-friendly colors and fonts
   - Clear labeling
   - Accessibility support
   - Error message clarity

5. Add Info.plist entries
   - NSFaceIDUsageDescription
   - Privacy descriptions

**Files to Modify:**
- `/Info.plist`

**Acceptance Criteria:**
- All authentication scenarios work
- Mode switching is smooth
- Data is consistent across modes
- UI is polished and child-friendly
- Privacy descriptions are present

---

## 5. Technical Specifications

### 5.1 LocalAuthentication Integration

**Framework:** LocalAuthentication
**Policy:** `.deviceOwnerAuthentication` (supports biometric + PIN fallback)

**Info.plist Requirements:**
```xml
<key>NSFaceIDUsageDescription</key>
<string>Parent mode requires authentication to access app settings and controls</string>
```

**Error Handling:**
- LAError.authenticationFailed → "Authentication failed. Please try again."
- LAError.userCancel → "Authentication cancelled."
- LAError.biometryNotAvailable → "Biometric authentication not available on this device."
- LAError.biometryNotEnrolled → "No biometric authentication enrolled. Please set up FaceID or TouchID in Settings."

### 5.2 Session Management

**Session Duration:** No automatic timeout (user must manually exit)
**Future Enhancement:** Optional auto-timeout after inactivity period

**State Persistence:**
- Do NOT persist authentication state (require re-auth on app restart)
- Persist last selected mode for UX convenience (optional)

### 5.3 Child Mode Data Filtering

**Used Apps Filter:**
```swift
extension AppUsageViewModel {
    var usedLearningApps: [LearningAppSnapshot] {
        learningSnapshots.filter { $0.totalSeconds > 0 }
    }

    var usedRewardApps: [RewardAppSnapshot] {
        rewardSnapshots.filter { $0.totalSeconds > 0 }
    }
}
```

---

## 6. File Structure

### New Files
```
ScreenTimeRewards/
├── Services/
│   ├── SessionManager.swift          [NEW]
│   └── AuthenticationService.swift   [NEW]
├── Models/
│   └── AuthError.swift                [NEW]
├── Views/
│   ├── ModeSelectionView.swift       [NEW]
│   ├── ParentMode/
│   │   └── ParentModeContainer.swift [NEW]
│   └── ChildMode/
│       ├── ChildModeView.swift       [NEW]
│       └── ChildDashboardView.swift  [NEW]
```

### Modified Files
```
ScreenTimeRewards/
├── ScreenTimeRewardsApp.swift        [MODIFY]
├── ViewModels/
│   └── AppUsageViewModel.swift       [MODIFY - add child mode helpers]
└── Info.plist                        [MODIFY - add biometric description]
```

### Unchanged Files (Existing Functionality)
```
ScreenTimeRewards/
├── Views/
│   ├── MainTabView.swift             [UNCHANGED]
│   ├── LearningTabView.swift         [UNCHANGED]
│   ├── RewardsTabView.swift          [UNCHANGED]
│   ├── CategoryAssignmentView.swift  [UNCHANGED]
│   └── AppUsageView.swift            [UNCHANGED]
├── Services/
│   └── ScreenTimeService.swift       [UNCHANGED]
└── Shared/
    └── UsagePersistence.swift        [UNCHANGED]
```

---

## 7. Code Examples

### 7.1 SessionManager Implementation

```swift
import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    enum UserMode: String {
        case none
        case parent
        case child
    }

    @Published var currentMode: UserMode = .none
    @Published var isParentAuthenticated: Bool = false

    private var lastAuthenticationTime: Date?
    private let authenticationTimeout: TimeInterval = 1800 // 30 minutes

    static let shared = SessionManager()

    private init() {}

    func enterParentMode(authenticated: Bool) {
        guard authenticated else { return }

        currentMode = .parent
        isParentAuthenticated = true
        lastAuthenticationTime = Date()

        #if DEBUG
        print("[SessionManager] Entered Parent Mode")
        #endif
    }

    func enterChildMode() {
        currentMode = .child
        isParentAuthenticated = false

        #if DEBUG
        print("[SessionManager] Entered Child Mode")
        #endif
    }

    func exitToSelection() {
        currentMode = .none
        isParentAuthenticated = false
        lastAuthenticationTime = nil

        #if DEBUG
        print("[SessionManager] Exited to Mode Selection")
        #endif
    }

    func requiresReAuthentication() -> Bool {
        guard let lastAuth = lastAuthenticationTime else { return true }
        return Date().timeIntervalSince(lastAuth) > authenticationTimeout
    }
}
```

### 7.2 ModeSelectionView Implementation

```swift
import SwiftUI

struct ModeSelectionView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var authService = AuthenticationService()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAuthenticating: Bool = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                // App title and logo
                VStack(spacing: 16) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("ScreenTime Rewards")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Choose your mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Mode selection buttons
                VStack(spacing: 20) {
                    // Parent Mode button
                    Button(action: handleParentModeSelection) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.2.fill")
                                .font(.title)

                            VStack(alignment: .leading) {
                                Text("Parent Mode")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("Protected - Full Access")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Spacer()

                            Image(systemName: "faceid")
                                .font(.title)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                    }
                    .disabled(isAuthenticating)

                    // Child Mode button
                    Button(action: handleChildModeSelection) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.fill")
                                .font(.title)

                            VStack(alignment: .leading) {
                                Text("Child Mode")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("Open Access - View Only")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Spacer()

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                    }
                    .disabled(isAuthenticating)
                }
                .padding(.horizontal, 30)
            }

            // Loading overlay
            if isAuthenticating {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func handleParentModeSelection() {
        isAuthenticating = true

        authService.authenticate(reason: "Access Parent Mode to manage app settings") { result in
            isAuthenticating = false

            switch result {
            case .success:
                sessionManager.enterParentMode(authenticated: true)

            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleChildModeSelection() {
        sessionManager.enterChildMode()
    }
}
```

### 7.3 ChildDashboardView Implementation

```swift
import SwiftUI
import FamilyControls

struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Points card
                pointsCard

                // Learning apps section
                if !viewModel.usedLearningApps.isEmpty {
                    learningAppsSection
                }

                // Reward apps section
                if !viewModel.usedRewardApps.isEmpty {
                    rewardAppsSection
                }

                // Empty state
                if viewModel.usedLearningApps.isEmpty && viewModel.usedRewardApps.isEmpty {
                    emptyStateView
                }

                Spacer()
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private extension ChildDashboardView {
    var pointsCard: some View {
        VStack(spacing: 12) {
            Text("Your Points")
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(viewModel.availableLearningPoints)")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.blue)

            HStack(spacing: 30) {
                VStack {
                    Text("\(viewModel.learningRewardPoints)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Total Earned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(viewModel.reservedLearningPoints)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("Reserved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.1))
        )
    }

    var learningAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
                Text("Learning Apps")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(viewModel.usedLearningApps) { snapshot in
                learningAppCard(snapshot: snapshot)
            }
        }
    }

    func learningAppCard(snapshot: LearningAppSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .font(.body)
                        .fontWeight(.medium)
                } else {
                    Text(snapshot.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(viewModel.formatTime(snapshot.totalSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(snapshot.earnedPoints) pts earned")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    var rewardAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.orange)
                Text("Reward Apps")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(viewModel.usedRewardApps) { snapshot in
                rewardAppCard(snapshot: snapshot)
            }
        }
    }

    func rewardAppCard(snapshot: RewardAppSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .font(.body)
                        .fontWeight(.medium)
                } else {
                    Text(snapshot.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(viewModel.formatTime(snapshot.totalSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    if viewModel.unlockedRewardApps[snapshot.token] != nil {
                        Text("Unlocked")
                            .font(.caption)
                            .foregroundColor(.green)
                        Image(systemName: "lock.open.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Locked")
                            .font(.caption)
                            .foregroundColor(.red)
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Apps Used Yet")
                .font(.title3)
                .fontWeight(.medium)

            Text("Start using learning apps to earn points!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
```

---

## 8. Testing Checklist

### Authentication Testing
- [ ] FaceID authentication succeeds
- [ ] FaceID authentication fails (user cancels)
- [ ] FaceID authentication fails (wrong biometric)
- [ ] TouchID authentication succeeds
- [ ] TouchID authentication fails
- [ ] PIN fallback works when biometric fails
- [ ] Error messages are clear and actionable
- [ ] No biometric enrolled scenario handled gracefully

### Mode Selection Testing
- [ ] Parent mode button triggers authentication
- [ ] Child mode button navigates immediately
- [ ] Mode selection view appears on app launch
- [ ] Navigation is smooth and responsive
- [ ] Error alerts display correctly

### Parent Mode Testing
- [ ] All existing features work as before
- [ ] Learning tab fully functional
- [ ] Rewards tab fully functional
- [ ] Category assignment works
- [ ] App monitoring works
- [ ] Shield management works
- [ ] Exit button returns to mode selection
- [ ] Re-entering requires re-authentication

### Child Mode Testing
- [ ] Available points display correctly
- [ ] Total earned points display correctly
- [ ] Reserved points display correctly
- [ ] Only used apps appear in list (totalSeconds > 0)
- [ ] Learning apps section shows correct data
- [ ] Reward apps section shows correct data
- [ ] Lock status displays correctly for reward apps
- [ ] No interactive controls visible
- [ ] Exit button returns to mode selection
- [ ] Real-time updates work (points change when parent mode modifies)
- [ ] Empty state shows when no apps used

### Data Consistency Testing
- [ ] Child mode shows same data as parent mode
- [ ] Changes in parent mode reflect in child mode
- [ ] App usage data is accurate
- [ ] Points calculations are correct
- [ ] Lock/unlock status is consistent

### Edge Cases
- [ ] Switching between modes multiple times
- [ ] Authentication timeout handling
- [ ] App backgrounding during authentication
- [ ] App termination and restart
- [ ] No internet connection (all features are local)
- [ ] Device rotation (landscape/portrait)

---

## 9. Privacy and Security Considerations

### 9.1 Authentication
- Use Apple's LocalAuthentication framework (native, secure)
- Do NOT store authentication credentials
- Do NOT implement custom PIN or password
- Rely on device security (FaceID/TouchID/device PIN)

### 9.2 Data Access
- Child mode has READ-ONLY access
- No way to bypass parent mode protection from child mode
- No backdoor or debug mode in production builds

### 9.3 Info.plist Requirements
```xml
<key>NSFaceIDUsageDescription</key>
<string>Parent mode requires authentication to access app settings and controls</string>
```

---

## 10. Future Enhancements (Out of Scope for Initial Implementation)

### Phase 2 Enhancements
1. **Session Timeout:** Auto-logout from parent mode after inactivity
2. **PIN Code Option:** Custom 4-digit PIN as alternative to biometric
3. **Multiple Child Profiles:** Support for multiple children with individual dashboards
4. **Parent Mode Notifications:** Alert parent when child mode is accessed
5. **Usage Reports in Child Mode:** Weekly/monthly summaries for child
6. **Achievements and Badges:** Gamification for children in child mode
7. **Parent Mode Quick Actions:** Quick unlock specific app without full parent mode access

---

## 11. Developer Notes

### Key Implementation Guidelines

1. **Separation of Concerns:**
   - Keep authentication logic in AuthenticationService
   - Keep session management in SessionManager
   - Keep view logic in respective view files

2. **State Management:**
   - Use @StateObject for SessionManager (single source of truth)
   - Use @EnvironmentObject to pass to child views
   - Keep authentication state in SessionManager, not in views

3. **Error Handling:**
   - Always handle authentication errors gracefully
   - Provide clear, user-friendly error messages
   - Never crash on authentication failure

4. **Testing:**
   - Test on physical devices (Simulator doesn't support FaceID fully)
   - Test all authentication scenarios
   - Test mode switching thoroughly

5. **Code Style:**
   - Follow existing code style in the project
   - Add #if DEBUG logging for development
   - Comment complex authentication logic

### Common Pitfalls to Avoid

1. **Don't** store authentication state permanently
2. **Don't** implement custom authentication (use Apple's framework)
3. **Don't** allow child mode to access parent mode features
4. **Don't** forget Info.plist descriptions (app will crash)
5. **Don't** test only on Simulator (use real devices)

---

## 12. Success Criteria

The implementation is considered complete when:

1. ⬜ Mode selection appears on app launch
2. ⬜ Parent mode requires biometric/PIN authentication
3. ⬜ Child mode is directly accessible
4. ⬜ Parent mode shows all existing features unchanged
5. ⬜ Child mode shows only used apps with correct data
6. ⬜ Exit buttons return to mode selection
7. ⬜ Re-entering parent mode requires re-authentication
8. ⬜ All authentication scenarios handled gracefully
9. ⬜ UI is polished and user-friendly
10. ⬜ Info.plist has required privacy descriptions
11. ⬜ All tests pass
12. ✅ Documentation is updated

---

## 13. Timeline Estimate

| Phase | Duration | Tasks | Status |
|-------|----------|-------|--------|
| Phase 1: Foundation | 4-6 hours | SessionManager, AuthenticationService, AuthError | ✅ Completed (Oct 26, 2025) |
| Phase 2: Mode Selection | 3-4 hours | ModeSelectionView, App integration | ⬜ Not Started |
| Phase 3: Child Mode | 6-8 hours | ChildModeView, ChildDashboardView, ViewModel updates | ⬜ Not Started |
| Phase 4: Parent Mode | 2-3 hours | ParentModeContainer, Integration | ⬜ Not Started |
| Phase 5: Testing & Polish | 4-6 hours | All testing scenarios, UI polish | ⬜ Not Started |
| **Total** | **19-27 hours** | **≈ 3-4 working days** | |

---

## 14. Questions for Stakeholder

Before implementation begins, clarify:

1. Should parent mode have an auto-timeout? If yes, what duration?
2. Should we remember the last selected mode for convenience?
3. Should child mode show apps with 0 seconds of usage? (Current plan: NO)
4. What should happen if biometric authentication is not available on device?
5. Should we add a "Forgot Parent Access" feature? (e.g., email reset)
6. Color scheme preferences for child mode? (Current: friendly, playful)
7. Font size preferences for child mode? (Current: larger, more readable)

---

## Appendix A: LocalAuthentication API Reference

### Key Classes
- `LAContext`: Manages authentication context
- `LAPolicy`: Defines authentication policy
  - `.deviceOwnerAuthentication`: Biometric + PIN fallback
  - `.deviceOwnerAuthenticationWithBiometrics`: Biometric only (no PIN)

### Key Methods
```swift
func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: (Bool, Error?) -> Void)
```

### Key Properties
```swift
var biometryType: LABiometryType { get }
// .faceID, .touchID, .none
```

---

## Appendix B: References

- [Apple LocalAuthentication Documentation](https://developer.apple.com/documentation/localauthentication)
- [Human Interface Guidelines - Authentication](https://developer.apple.com/design/human-interface-guidelines/authentication)
- [FamilyControls Framework Documentation](https://developer.apple.com/documentation/familycontrols)
- [Screen Time API Best Practices](https://developer.apple.com/documentation/screentime)

---

**Document Version:** 1.1
**Last Updated:** October 26, 2025
**Author:** AI Development Agent
**Reviewed By:** [Pending]
**Approved By:** [Pending]
