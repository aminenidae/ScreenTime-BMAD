# ManagedSettings Blocking Test Plan

**Purpose:** Validate Apple's ManagedSettings framework for dynamic app blocking/unlocking
**Date Created:** 2025-10-16
**Priority:** 🔴 CRITICAL - Core product feature, completely untested

---

## Executive Summary

This is the **HIGHEST PRIORITY** test for the technical feasibility study. The entire product value proposition depends on:
- **FR2:** "Automatically unlock reward apps after targets met"
- **FR13:** "Block all apps except learning apps and authorized apps"
- **FR14:** "Enable parents to set downtime schedules"

**If this doesn't work, the product is not viable.**

---

## Test Objectives

1. ✅ Verify we can block specific apps using ManagedSettings
2. ✅ Verify we can unblock apps dynamically based on criteria
3. ✅ Measure delay between setting change and enforcement
4. ✅ Test parental override functionality
5. ✅ Document shield staleness behavior (research finding)
6. ✅ Test system behavior during offline scenarios
7. ✅ Verify shield time counting (research finding)

---

## Prerequisites

### Required Knowledge
- [ ] Read Apple's ManagedSettings framework documentation
- [ ] Review ShieldConfiguration extension documentation
- [ ] Understand community research findings on shield behavior

### Required Setup
- [ ] Physical iOS device (iOS 15+)
- [ ] Screen Time enabled in Settings
- [ ] FamilyControls authorization granted
- [ ] Apps selected via FamilyActivityPicker
- [ ] Xcode console accessible

### Test Data Preparation
- [ ] Select 6 test apps:
  - 3 "Learning" apps (to keep accessible)
  - 3 "Reward" apps (to block initially)
- [ ] Note bundle IDs if visible (for logging)
- [ ] Document app categories assigned

---

## Implementation Phase

###  Step 1: Add ManagedSettings to ScreenTimeService

**File:** `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Add imports:**
```swift
import ManagedSettings
```

**Add properties:**
```swift
// ManagedSettings store for app blocking
private let managedSettingsStore = ManagedSettingsStore()

// Track currently shielded (blocked) apps
private var currentlyShielded: Set<ApplicationToken> = []

// Track apps that should always be accessible (learning apps)
private var alwaysAccessible: Set<ApplicationToken> = []
```

**Add methods:**
```swift
/// Block reward apps (shield them)
func blockRewardApps(tokens: Set<ApplicationToken>) {
    #if DEBUG
    print("[ScreenTimeService] Blocking \(tokens.count) reward apps")
    #endif

    currentlyShielded = tokens
    managedSettingsStore.shield.applications = tokens

    #if DEBUG
    print("[ScreenTimeService] ✅ Shield applied to \(tokens.count) apps")
    print("[ScreenTimeService] ⚠️ Note: If apps are already running, user must close and reopen")
    #endif

    // Post notification
    NotificationCenter.default.post(name: .rewardAppsBlocked, object: nil)
}

/// Unblock reward apps (remove shield)
func unblockRewardApps(tokens: Set<ApplicationToken>) {
    #if DEBUG
    print("[ScreenTimeService] Unblocking \(tokens.count) reward apps")
    #endif

    // Remove from currently shielded
    currentlyShielded.subtract(tokens)

    // Update ManagedSettings
    managedSettingsStore.shield.applications = currentlyShielded

    #if DEBUG
    print("[ScreenTimeService] ✅ Shield removed from \(tokens.count) apps")
    print("[ScreenTimeService] Currently shielded: \(currentlyShielded.count) apps")
    print("[ScreenTimeService] ⚠️ Note: Requires app relaunch to take effect (research finding)")
    #endif

    // Post notification
    NotificationCenter.default.post(
        name: .rewardAppsUnlocked,
        object: nil,
        userInfo: ["requiresRelaunch": true]
    )
}

/// Block ALL apps except learning and system apps
func blockAllExceptLearning(learningTokens: Set<ApplicationToken>) {
    #if DEBUG
    print("[ScreenTimeService] Blocking all apps except \(learningTokens.count) learning apps")
    #endif

    alwaysAccessible = learningTokens

    // Note: We'll need to implement this by blocking specific apps
    // ManagedSettings doesn't have a "block all except" mode
    // This is a limitation to document

    #if DEBUG
    print("[ScreenTimeService] ⚠️ LIMITATION: Cannot block 'all except' - must specify apps to block")
    print("[ScreenTimeService] Workaround: Block known reward apps explicitly")
    #endif
}

/// Get current shield status
func getShieldStatus() -> (blocked: Int, accessible: Int) {
    return (blocked: currentlyShielded.count, accessible: alwaysAccessible.count)
}

/// Clear all shields
func clearAllShields() {
    #if DEBUG
    print("[ScreenTimeService] Clearing all shields")
    #endif

    currentlyShielded.removeAll()
    managedSettingsStore.shield.applications = nil

    #if DEBUG
    print("[ScreenTimeService] ✅ All shields cleared")
    #endif
}
```

**Add notification names:**
```swift
// In ScreenTimeNotifications.swift or extension
extension Notification.Name {
    static let rewardAppsBlocked = Notification.Name("com.screentimerewards.rewardAppsBlocked")
    static let rewardAppsUnlocked = Notification.Name("com.screentimerewards.rewardAppsUnlocked")
}
```

---

### Step 2: Add UI Controls to AppUsageView

**Add to configurationSection:**
```swift
// ManagedSettings Test Controls
Section(header: Text("🧪 ManagedSettings Testing").foregroundColor(.orange)) {
    VStack(alignment: .leading, spacing: 8) {
        Text("Test app blocking/unlocking functionality")
            .font(.caption)
            .foregroundColor(.secondary)

        Button(action: {
            testBlockRewardApps()
        }) {
            HStack {
                Image(systemName: "lock.shield.fill")
                Text("Block Reward Apps")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
        }

        Button(action: {
            testUnblockRewardApps()
        }) {
            HStack {
                Image(systemName: "lock.open.fill")
                Text("Unblock Reward Apps")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
        }

        Button(action: {
            testClearAllShields()
        }) {
            HStack {
                Image(systemName: "shield.slash.fill")
                Text("Clear All Shields")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
        }

        // Shield status display
        let status = viewModel.getShieldStatus()
        HStack {
            VStack(alignment: .leading) {
                Text("Blocked: \(status.blocked)")
                Text("Accessible: \(status.accessible)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
    .padding()
}
```

**Add ViewModel methods:**
```swift
// In AppUsageViewModel.swift

func testBlockRewardApps() {
    #if DEBUG
    print("[AppUsageViewModel] TEST: Blocking reward apps")
    #endif

    // Get all tokens assigned to "Reward" category
    let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }

    if rewardTokens.isEmpty {
        errorMessage = "No reward apps assigned. Please assign some apps to 'Reward' category first."
        return
    }

    service.blockRewardApps(tokens: Set(rewardTokens))

    #if DEBUG
    print("[AppUsageViewModel] Blocked \(rewardTokens.count) reward apps")
    print("[AppUsageViewModel] Try opening a reward app now - you should see a shield screen")
    #endif
}

func testUnblockRewardApps() {
    #if DEBUG
    print("[AppUsageViewModel] TEST: Unblocking reward apps")
    #endif

    let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }

    if rewardTokens.isEmpty {
        errorMessage = "No reward apps assigned."
        return
    }

    service.unblockRewardApps(tokens: Set(rewardTokens))

    #if DEBUG
    print("[AppUsageViewModel] Unblocked \(rewardTokens.count) reward apps")
    print("[AppUsageViewModel] ⚠️ If app is running, close it completely and reopen")
    #endif
}

func testClearAllShields() {
    #if DEBUG
    print("[AppUsageViewModel] TEST: Clearing all shields")
    #endif

    service.clearAllShields()
}

func getShieldStatus() -> (blocked: Int, accessible: Int) {
    return service.getShieldStatus()
}
```

---

## Test Execution

### Phase 1: Basic Blocking (30 minutes)

#### Test 1.1: Block Single Reward App
**Steps:**
1. Build and run app
2. Select 3 learning apps + 3 reward apps
3. Assign categories correctly
4. Tap "Block Reward Apps"
5. **Exit app** (home button)
6. Try opening ONE reward app

**Expected:**
- [ ] App shows shield screen (blocking UI)
- [ ] Cannot access app content
- [ ] Shield screen has default text/color

**Console Logs:**
```
[ScreenTimeService] Blocking 3 reward apps
[ScreenTimeService] ✅ Shield applied to 3 apps
```

**Actual Result:**

**Screenshots:** (Take screenshot of shield screen)

**Status:** [ ] PASS / [ ] FAIL
**Delay from button press to shield active:** ____ seconds

---

#### Test 1.2: Learning Apps Still Accessible
**Steps:**
1. With reward apps blocked (from Test 1.1)
2. Try opening ONE learning app

**Expected:**
- [ ] Learning app opens normally
- [ ] NO shield screen shown
- [ ] Full app functionality available

**Status:** [ ] PASS / [ ] FAIL

---

#### Test 1.3: Unblock Reward Apps
**Steps:**
1. Return to ScreenTimeRewards app
2. Tap "Unblock Reward Apps"
3. **Close the reward app completely** (swipe up from multitasking)
4. Wait 5 seconds
5. Try opening reward app again

**Expected:**
- [ ] Shield screen is GONE
- [ ] App opens normally
- [ ] Full functionality restored

**Console Logs:**
```
[ScreenTimeService] Unblocking 3 reward apps
[ScreenTimeService] ✅ Shield removed from 3 apps
```

**Status:** [ ] PASS / [ ] FAIL
**Delay from button press to shield removed:** ____ seconds

**⚠️ CRITICAL:** Did you need to force-close the app? [ ] YES / [ ] NO
*(This confirms the "stale shield" research finding)*

---

### Phase 2: Dynamic Blocking (45 minutes)

#### Test 2.1: Block Then Immediately Unblock
**Steps:**
1. Tap "Block Reward Apps"
2. Wait 2 seconds
3. Tap "Unblock Reward Apps"
4. Try opening reward app

**Goal:** Test rapid shield changes

**Expected:**
- [ ] Final state (unblocked) applies correctly
- [ ] No stale shield from the brief blocking period

**Status:** [ ] PASS / [ ] FAIL

---

#### Test 2.2: Block While App Is Running
**Steps:**
1. Open a reward app (leave it running)
2. Switch to ScreenTimeRewards (don't close reward app)
3. Tap "Block Reward Apps"
4. Switch back to reward app (still in multitasking)

**Goal:** Test shield application to running apps

**Expected:**
- [ ] Shield MAY or MAY NOT appear immediately
- [ ] Force-closing and reopening shows shield

**Research Finding:** "Shields don't re-evaluate until app relaunch"

**Status:** [ ] PASS / [ ] FAIL
**Observed behavior:**

---

#### Test 2.3: Unblock While App Is Shielded and Running
**Steps:**
1. Block reward apps
2. Open reward app (see shield screen)
3. Leave shield screen visible
4. Switch to ScreenTimeRewards
5. Tap "Unblock Reward Apps"
6. Switch back to reward app shield screen

**Goal:** Test shield removal from running apps

**Expected:**
- [ ] Shield screen remains visible (stale)
- [ ] Force-closing and reopening shows normal app

**Status:** [ ] PASS / [ ] FAIL
**Shield remained after unblock:** [ ] YES (expected) / [ ] NO (unexpected)

---

### Phase 3: Multiple Apps and Categories (30 minutes)

#### Test 3.1: Block All Reward Apps, Unblock One
**Steps:**
1. Block all 3 reward apps
2. Verify all 3 show shields
3. Programmatically unblock ONLY 1 reward app
4. Test all 3 apps

**Code to add temporarily:**
```swift
func testUnblockSingleApp() {
    let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }
    if let firstToken = rewardTokens.first {
        service.unblockRewardApps(tokens: Set([firstToken]))
    }
}
```

**Expected:**
- [ ] 2 apps still shielded
- [ ] 1 app accessible

**Status:** [ ] PASS / [ ] FAIL

---

#### Test 3.2: Re-block Previously Unblocked App
**Steps:**
1. From Test 3.1 state (1 app unblocked, 2 blocked)
2. Block the previously unblocked app again

**Expected:**
- [ ] App gets reshielded
- [ ] All 3 reward apps now blocked

**Status:** [ ] PASS / [ ] FAIL

---

### Phase 4: Edge Cases and Limitations (45 minutes)

#### Test 4.1: Device Restart
**Steps:**
1. Block reward apps
2. Verify shields active
3. Restart device
4. Try opening reward app WITHOUT opening ScreenTimeRewards first

**Goal:** Test shield persistence

**Expected:**
- [ ] Shields remain active after restart
- [ ] OR shields clear after restart (document which)

**Status:** [ ] PASS / [ ] FAIL
**Shield state after restart:** [ ] Active / [ ] Cleared

---

#### Test 4.2: Offline Blocking
**Steps:**
1. Enable Airplane Mode
2. Block reward apps
3. Try opening reward app

**Goal:** Verify blocking works offline

**Expected:**
- [ ] Shield applies successfully offline
- [ ] ManagedSettings is local (no network needed)

**Status:** [ ] PASS / [ ] FAIL

---

#### Test 4.3: Shield Time Counting (Research Finding)
**Steps:**
1. Start monitoring (ensure tracking is active)
2. Block a reward app
3. Try opening reward app (see shield screen)
4. Leave shield screen visible for 5 minutes
5. Return to ScreenTimeRewards
6. Check if usage time increased

**Goal:** Verify if shield screen time counts as "usage"

**Research Finding:** "Shield time may count as usage time"

**Expected:**
- [ ] Shield time DOES count as usage (if research is correct)
- [ ] Shield time does NOT count as usage (ideal behavior)

**Actual Result:**
**Usage increased:** [ ] YES by ___ min / [ ] NO

**Status:** [ ] PASS / [ ] DOCUMENTED

---

#### Test 4.4: Maximum Shield Count
**Steps:**
1. Select 20+ apps (if possible)
2. Assign all to "Reward" category
3. Try blocking all 20+ apps

**Goal:** Test if there's a shield limit

**Expected:**
- [ ] All apps shield successfully
- [ ] OR encounter a limit (document it)

**Status:** [ ] PASS / [ ] LIMIT FOUND: ____ apps

---

### Phase 5: Performance and Delays (30 minutes)

#### Test 5.1: Blocking Delay Measurement
**Steps:**
1. Note exact time: ____
2. Tap "Block Reward Apps"
3. Immediately try opening reward app
4. Retry every 1 second until shield appears
5. Note exact time shield appears: ____

**Goal:** Measure enforcement delay

**Delay measured:** ____ seconds

**Status:** [ ] PASS (< 5 sec) / [ ] FAIL (> 5 sec)

---

#### Test 5.2: Unblocking Delay Measurement
**Steps:**
1. With apps blocked, note exact time: ____
2. Tap "Unblock Reward Apps"
3. Force-close reward app
4. Try opening every 1 second until it opens
5. Note exact time app opens: ____

**Delay measured:** ____ seconds

**Status:** [ ] PASS (< 5 sec) / [ ] FAIL (> 5 sec)

---

#### Test 5.3: Repeated Block/Unblock Cycles
**Steps:**
1. Block → Unblock → Block → Unblock (10 cycles)
2. Measure each cycle
3. Check for performance degradation

**Average delay:** ____ seconds
**Degradation observed:** [ ] YES / [ ] NO

**Status:** [ ] PASS / [ ] FAIL

---

## Critical Findings

### Blocking/Unlocking Works?
[ ] ✅ YES - ManagedSettings blocking works
[ ] ❌ NO - Cannot block apps
[ ] ⚠️ PARTIAL - Works with limitations

**Details:**

### Key Limitations Discovered
1. **Limitation:**
   **Impact:**
   **Workaround:**

2. **Limitation:**
   **Impact:**
   **Workaround:**

### Performance Metrics
- **Blocking delay:** ____ seconds
- **Unblocking delay:** ____ seconds
- **Shield staleness:** [ ] CONFIRMED / [ ] NOT OBSERVED
- **Time counting:** [ ] CONFIRMED / [ ] NOT OBSERVED

---

## Go/No-Go Decision

### Can We Build the Product?

**CRITICAL QUESTION:** Can we dynamically block and unblock apps based on usage criteria?

[ ] ✅ **GO** - Blocking/unlocking works acceptably
[ ] ❌ **NO-GO** - Blocking/unlocking doesn't work as needed
[ ] ⚠️ **CONDITIONAL** - Works with significant limitations

### Decision Factors

**If GO:**
- Blocking works with < 5 second delay
- Unlocking works reliably
- Shield staleness is manageable (user can relaunch)
- Time counting issue is minor or fixable

**If NO-GO:**
- Cannot block apps at all
- Cannot unblock dynamically
- Delays > 30 seconds
- Critical bugs or crashes

**If CONDITIONAL:**
- Shield staleness requires UX accommodation
- Time counting requires adjustment to point calculation
- Delays require user messaging
- Limitations require product redesign

---

## Next Steps

### If TEST PASSES:
1. ✅ Document all findings in feasibility report
2. ✅ Proceed to TestFlight distribution testing
3. ✅ Implement ShieldConfiguration extension (Path 2)
4. ✅ Begin CloudKit multi-device testing

### If TEST FAILS:
1. 🔴 Document failure mode
2. 🔴 Investigate root cause
3. 🔴 Consider alternative approaches:
   - Notification-only system (no enforcement)
   - Category-based blocking only
   - Different Apple framework
4. 🔴 Update stakeholders on findings

### If TEST CONDITIONAL:
1. ⚠️ Document all limitations
2. ⚠️ Design UX accommodations
3. ⚠️ Adjust product requirements
4. ⚠️ Prototype workarounds

---

## Test Sign-Off

**Tester:** __________________
**Date:** __________________
**iOS Version:** __________________
**Device:** __________________

**Result:** [ ] PASS / [ ] FAIL / [ ] CONDITIONAL

**Recommendation:**

**Blocker Issues:**

**Next Test:** [ ] TestFlight / [ ] CloudKit / [ ] Shield Extension / [ ] Stop feasibility study
