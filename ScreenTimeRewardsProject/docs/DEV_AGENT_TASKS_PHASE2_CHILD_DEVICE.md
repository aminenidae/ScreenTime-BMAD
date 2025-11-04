# Dev Agent Tasks - Phase 2: Child Device Cleanup + Settings Tab

**Priority:** HIGH
**Date:** November 2, 2025 (Updated)
**Estimated Time:** 40 minutes
**Security Impact:** HIGH - Removes child access to administrative functions

---

## Overview

Clean up child device interface by:
1. Removing debug features
2. Creating dedicated Settings tab for Parent Mode
3. Moving administrative controls to Settings tab (authentication-protected)
4. Improving security
5. Simplifying child user experience

---

## Task 1: Delete "Show Authentication Debug" Button ⚡ (2 minutes)

### File
`ScreenTimeRewards/Views/ModeSelectionView.swift`

### Changes

**DELETE line 21:**
```swift
@State private var showDebugView: Bool = false
```

**DELETE lines 140-148:**
```swift
// DEBUG: Button to show debug view
#if DEBUG
Button("Show Authentication Debug") {
    showDebugView = true
}
.padding()
.background(Color.orange)
.foregroundColor(.white)
.cornerRadius(10)
#endif
```

**DELETE lines 214-217:**
```swift
// DEBUG: Sheet for debug view
.sheet(isPresented: $showDebugView) {
    DebugAuthView()
}
```

**Result:** No debug button in mode selection screen.

---

## Task 2: Delete "Debug Actions" Section ⚡ (3 minutes)

### File
`ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift`

### Changes

**DELETE lines 37-40:**
```swift
// 🔴 TASK 13: Add Manual Test Button for Upload - CRITICAL
#if DEBUG
debugActionsSection
#endif
```

**DELETE lines 272-330 (entire debugActionsSection):**
```swift
// 🔴 TASK 13: Debug Actions Section
#if DEBUG
var debugActionsSection: some View {
    Section("Debug Actions") {
        // ... entire section (58 lines)
    }
}
#endif
```

**Result:** No debug tools in child dashboard.

---

## Task 3: Create Settings Tab View 🆕 (15 minutes)

### New File
**Create:** `ScreenTimeRewards/Views/SettingsTabView.swift`

This new view will house all Parent Mode administrative controls in one organized place.

```swift
import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showingPairingView = false
    @State private var showResetConfirmation = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared

    var body: some View {
        ZStack {
            // Soft gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 1.0),  // Soft purple
                    Color(red: 0.95, green: 0.97, blue: 1.0),  // Soft blue
                    Color(red: 1.0, green: 0.97, blue: 0.95)   // Soft peach
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Parent Mode Controls")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Exit Parent Mode Button
                    exitParentModeSection

                    Divider()
                        .padding(.horizontal)

                    // Parent Monitoring (Pairing)
                    parentMonitoringSection

                    Divider()
                        .padding(.horizontal)

                    // Device Settings (Reset)
                    deviceSettingsSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }
    }
}

// MARK: - Sections

private extension SettingsTabView {
    var exitParentModeSection: some View {
        VStack(spacing: 12) {
            Text("Mode")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                sessionManager.exitToSelection()
            }) {
                HStack {
                    Image(systemName: "arrow.backward.circle.fill")
                    Text("Exit Parent Mode")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }

    var parentMonitoringSection: some View {
        VStack(spacing: 12) {
            Text("Parent Monitoring")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !pairingService.isPaired() {
                // Not Paired - Show pairing option
                VStack(spacing: 16) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.largeTitle)
                        .foregroundColor(.blue)

                    Text("Connect to Parent Device")
                        .font(.title3)
                        .multilineTextAlignment(.center)

                    Text("Scan your parent's QR code to enable monitoring")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Scan Parent's QR Code") {
                        showingPairingView = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            } else {
                // Paired - Show status and disconnect
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        Text("Connected to Parent")
                            .font(.headline)
                    }

                    if let parentID = pairingService.getParentDeviceID() {
                        Text("Parent Device ID: \(parentID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Disconnect from Parent") {
                        pairingService.unpairDevice()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    var deviceSettingsSection: some View {
        VStack(spacing: 12) {
            Text("Device Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                showResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Device Mode")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red, lineWidth: 1)
                )
            }
            .confirmationDialog("Reset Device Mode?",
                              isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    modeManager.resetDeviceMode()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will reset your device mode selection. App configurations will be preserved.")
            }
        }
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
    }
}
```

**Result:** New dedicated Settings view with all administrative controls.

---

## Task 4: Add Settings Tab to MainTabView 🔧 (5 minutes)

### File
`ScreenTimeRewards/Views/MainTabView.swift`

### Changes

**REMOVE Exit button from toolbar (lines 31-42):**
```swift
// DELETE THIS ENTIRE BLOCK:
.toolbar {
    // Conditionally show Exit Parent Mode button
    if isParentMode {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Exit Parent Mode") {
                sessionManager.exitToSelection()
            }
            .foregroundColor(.red)
            .font(.headline)
        }
    }
}
```

**ADD Settings tab after Learning tab (after line 26):**
```swift
LearningTabView()
    .tabItem {
        Label("Learning", systemImage: "book.fill")
    }
    .navigationTitle("Learning")

// ADD THIS - Settings Tab (Parent Mode only)
if isParentMode {
    SettingsTabView()
        .tabItem {
            Label("Settings", systemImage: "gearshape.fill")
        }
        .navigationTitle("Settings")
}
```

**Result:** Settings tab appears as 3rd tab when in Parent Mode. Exit button moved from toolbar to Settings tab.

---

## Task 5: Clean Up RewardsTabView 🧹 (5 minutes)

### File
`ScreenTimeRewards/Views/RewardsTabView.swift`

Now that we have a dedicated Settings tab, remove all administrative controls from Rewards tab.

### Changes

**DELETE state variables (lines 8-10):**
```swift
@State private var showingPairingView = false
@State private var showResetConfirmation: Bool = false
@StateObject private var pairingService = DevicePairingService.shared
```

**DELETE Parent Monitoring section (lines 92-151):**
```swift
// DELETE ENTIRE SECTION:
// PARENT MODE: Device Pairing Management
VStack(spacing: 12) {
    // ... entire pairing section
}
.padding(.vertical)
```

**DELETE Device Settings section (lines 153-188):**
```swift
// DELETE ENTIRE SECTION:
// PARENT MODE: Reset Device Mode
VStack(spacing: 12) {
    // ... entire reset section
}
.padding(.vertical)
```

**DELETE pairing sheet (lines 207-209):**
```swift
// DELETE THIS:
.sheet(isPresented: $showingPairingView) {
    ChildPairingView()
}
```

**Result:** RewardsTabView now focuses only on reward app management.

---

## Task 6: Remove from Child Mode 🧹 (3 minutes)

### File
`ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift`

**DELETE lines 6-7:**
```swift
@State private var showingPairingView = false
@StateObject private var pairingService = DevicePairingService.shared
```

**DELETE lines 25-30:**
```swift
// Pairing section (only when not paired)
if !pairingService.isPaired() {
    pairingSection
} else {
    pairedStatusSection
}
```

**DELETE lines 49-51:**
```swift
.sheet(isPresented: $showingPairingView) {
    ChildPairingView()
}
```

**DELETE lines 220-244 (pairingSection):**
```swift
var pairingSection: some View {
    // ... entire section
}
```

**DELETE lines 246-270 (pairedStatusSection):**
```swift
var pairedStatusSection: some View {
    // ... entire section
}
```

**Result:** Child dashboard has no pairing controls.

---

## Task 7: Remove Reset from ModeSelectionView 🧹 (3 minutes)

### File
`ScreenTimeRewards/Views/ModeSelectionView.swift`

**DELETE line 10:**
```swift
@State private var showResetConfirmation: Bool = false
```

**DELETE lines 111-137:**
```swift
// Reset Device Mode button
Button(action: {
    showResetConfirmation = true
}) {
    // ... entire button
}
.confirmationDialog("Reset Device Mode?",
                  isPresented: $showResetConfirmation) {
    // ... dialog
}
```

**Result:** Reset only accessible through Settings tab (Parent Mode).

---

## Implementation Order

1. Task 1: Delete "Show Authentication Debug" (2 min)
2. Task 2: Delete "Debug Actions" section (3 min)
3. **Task 3: Create SettingsTabView.swift (15 min)**
4. **Task 4: Add Settings tab to MainTabView (5 min)**
5. **Task 5: Clean up RewardsTabView (5 min)**
6. **Task 6: Remove pairing from ChildDashboardView (3 min)**
7. **Task 7: Remove reset from ModeSelectionView (3 min)**

**Total:** ~40 minutes

---

## Testing Checklist

### Build Verification
- [ ] Build succeeds with no errors
- [ ] No compiler warnings

### Child Mode (Security Tests)
- [ ] Mode selection screen has no debug button
- [ ] Mode selection screen has no reset button
- [ ] Child dashboard has no debug actions
- [ ] Child dashboard has no pairing section
- [ ] Child cannot access any administrative functions

### Parent Mode (Functionality Tests)
- [ ] Settings tab appears as 3rd tab in Parent Mode
- [ ] Settings tab NOT visible in Child Mode
- [ ] Exit Parent Mode button in Settings tab works
- [ ] Reset button in Settings tab shows confirmation dialog
- [ ] Reset works correctly
- [ ] Pairing section in Settings tab works
- [ ] Can scan QR code from Settings tab
- [ ] Can disconnect from parent
- [ ] All controls require authentication

### Navigation Flow
- [ ] Child Mode → 2 tabs (Rewards, Learning) - simple interface
- [ ] Parent Mode → 3 tabs (Rewards, Learning, Settings)
- [ ] Settings tab shows all admin controls
- [ ] Authentication required to access Parent Mode
- [ ] Exit Parent Mode button in Settings works
- [ ] No Exit button in toolbar

---

## Expected File Changes

| File | Lines Removed | Lines Added | Net |
|------|---------------|-------------|-----|
| `ModeSelectionView.swift` | ~35 | 0 | -35 |
| `ChildDashboardView.swift` | ~80 | 0 | -80 |
| `RewardsTabView.swift` | ~100 | 0 | -100 |
| `MainTabView.swift` | ~12 | ~10 | -2 |
| **`SettingsTabView.swift`** | **0** | **~200** | **+200** |
| **Total** | **227** | **210** | **-17** |

---

## Visual Summary

### Before
```
Mode Selection:
- [Parent Mode]
- [Child Mode]
- [Reset Device Mode]  ❌ Child can access
- [Show Auth Debug]     ❌ Debug visible

Child Dashboard:
- Points & Apps
- [Scan QR Code]        ❌ Child can pair
- [Unpair]              ❌ Child can disconnect
- [Debug Actions]       ❌ Child can fake data
```

### After
```
Mode Selection:
- [Parent Mode]
- [Child Mode]
                        ✅ Clean interface

Child Dashboard:
- Points & Apps
                        ✅ Simple, secure

Parent Mode (Auth Required):
Tabs: Rewards | Learning | Settings ✅

Settings Tab:
- [Exit Parent Mode]    ✅ Easy to find
- [Scan QR Code]        ✅ Parent controls pairing
- [Disconnect]          ✅ Parent controls connection
- [Reset Device Mode]   ✅ Parent controls reset
```

---

## Build Command

```bash
xcodebuild -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -sdk iphoneos \
  -configuration Debug \
  build
```

---

## Reference Documentation

See: `docs/UX_UI_IMPROVEMENTS_PHASE_2_CHILD_DEVICE.md` for complete specification.

---

**Start with Task 1, proceed sequentially through Task 4.**
