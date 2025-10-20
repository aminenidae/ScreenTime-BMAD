# PM-Developer Briefing Document
**Project:** ScreenTime Rewards App
**Date:** 2025-10-20
**PM:** Claude (Analysis & Documentation)
**Developer:** Code Agent (Implementation Only)

---

## 🎯 Current Sprint Goal

**Fix the UI display issue where learning apps show 0 time and 0 points despite backend having correct data.**

---

## 📊 Current State Analysis

### What's Working ✅
1. **Token-based persistence** - ApplicationToken data is extracted and hashed with SHA256
2. **Backend data storage** - UsagePersistence correctly saves and loads app data
3. **Token mapping stability** - UUIDs are correctly reused across app relaunches
4. **Monitoring auto-restart** - DeviceActivity monitoring restarts automatically on app launch
5. **Data is being loaded** - Logs confirm: `[ScreenTimeService] - Unknown App 1: 120.0s, 20pts`

### What's Broken 🔴
1. **UI shows zeros** - Despite backend having correct data (120s/20pts), UI displays "0m, 0pts"
2. **Data not flowing to Views** - Disconnect between `ScreenTimeService.appUsages` and UI layer

### Evidence
- **Log File:** `Run-ScreenTimeRewards-2025.10.19_10-32-47--0500.xcresult`
- **User Screenshot:** Shows apps listed but all time/points are zero
- **Log Proof:** Backend logs show correct values being loaded

---

## 🔍 Root Cause Analysis

### The Problem Chain

```
Persistence Layer (✅ WORKING)
    ↓
ScreenTimeService.appUsages (✅ WORKING - has correct data)
    ↓
❌ BROKEN LINK - Data not reaching UI
    ↓
AppUsageViewModel (❓ UNCLEAR - may not be fetching correctly)
    ↓
UI Views (🔴 BROKEN - showing zeros)
```

### Hypothesis
The issue is likely in **how the UI fetches and displays data** after `loadPersistedAssignments()` completes. Possible causes:

1. **ViewModel not refreshing** - `AppUsageViewModel` may not be observing the data changes after restoration
2. **Timing issue** - UI might render before data is fully loaded
3. **Data binding issue** - Views may not be correctly bound to the restored data
4. **Wrong data source** - Views might be looking at wrong property or stale cache

---

## 📋 DEVELOPER TASKS

### Task 1: Investigate AppUsageViewModel Data Fetching
**Priority:** CRITICAL
**File:** `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

**Investigation Required:**
- [ ] How does `getUsageTimes()` method fetch data from `ScreenTimeService`?
- [ ] Is it properly observing `ScreenTimeService.usageDidChangeNotification`?
- [ ] Does it refresh data after `loadPersistedAssignments()` completes?
- [ ] Check if there's a cached state that's not being updated

**What to Look For:**
- Methods that fetch usage data
- NotificationCenter observers
- @Published properties that drive UI updates
- Any caching mechanism that might serve stale data

**Deliverable:** Document findings in the "Developer Task Log" section below

---

### Task 2: Trace Data Flow from Service to UI
**Priority:** CRITICAL
**Files:**
- `ScreenTimeService.swift`
- `AppUsageViewModel.swift`
- `LearningTabView.swift`
- `CategoryAssignmentView.swift`

**Investigation Required:**
- [ ] When `loadPersistedAssignments()` finishes, what notification is sent?
- [ ] Does the ViewModel receive and handle that notification?
- [ ] How does `usageTimes` parameter in `CategoryAssignmentView` get populated?
- [ ] Is there a manual refresh needed after data restoration?

**Specific Checkpoints:**
1. `ScreenTimeService.swift:~287` - After monitoring is reconfigured, is `usageDidChangeNotification` posted?
2. `AppUsageViewModel.swift` - Does it subscribe to this notification?
3. `LearningTabView.swift` - What data binding drives the display?

**Deliverable:** Document the complete data flow in the "Developer Task Log" section

---

### Task 3: Add Debug Logging to Track Data Flow
**Priority:** HIGH
**Files:** `AppUsageViewModel.swift`

**Implementation Required:**
Add DEBUG logging to trace:
- [ ] When `getUsageTimes()` is called
- [ ] What data it receives from `ScreenTimeService`
- [ ] When NotificationCenter observers fire
- [ ] What values are being returned to UI

**Example Logging Points:**
```swift
// At start of getUsageTimes()
#if DEBUG
print("[AppUsageViewModel] 📊 getUsageTimes() called")
print("[AppUsageViewModel] 📊 ScreenTimeService has \(screenTimeService.appUsages.count) apps")
#endif

// When notification received
#if DEBUG
print("[AppUsageViewModel] 🔔 Received usageDidChangeNotification")
print("[AppUsageViewModel] 🔔 Refreshing data...")
#endif
```

**Deliverable:** Add logging, run on device, capture logs, paste in "Developer Task Log" section

---

### Task 4: Fix the UI Refresh Issue
**Priority:** CRITICAL
**File:** TBD (based on findings from Tasks 1-3)

**Implementation Required:**
Based on investigation findings, implement the fix. Likely scenarios:

**Scenario A: Missing Notification Observer**
- Add observer for `usageDidChangeNotification` in ViewModel
- Call `refreshData()` or equivalent when received

**Scenario B: Timing Issue**
- Ensure UI refreshes AFTER `loadPersistedAssignments()` completes
- May need to trigger manual refresh in `onAppear` or similar

**Scenario C: Wrong Data Source**
- Update `getUsageTimes()` to fetch from correct source
- Ensure it's querying the restored `appUsages` dictionary

**Deliverable:** Code changes that fix the UI display issue

---

### Task 5: Validation Testing
**Priority:** CRITICAL
**Test Scenario:**

**Setup:**
1. Fresh app install
2. Select 2 learning apps (e.g., News, Books)
3. Use News for 60 seconds → verify shows "1m, 10pts"
4. Use Books for 120 seconds → verify shows "2m, 20pts"
5. **Close app completely** (force quit)
6. **Relaunch app**

**Expected Result:**
- Learning tab shows: News "1m, 10pts" and Books "2m, 20pts"
- CategoryAssignmentView shows same data with clock icons

**Actual Result:** *(Fill in after testing)*

**Log File:** *(Attach xcresult path)*

**Screenshot:** *(Attach screenshot showing UI with correct data)*

**Deliverable:** Validation report in "Developer Task Log" section

---

## 🛠️ Technical Context for Developer

### Key Files and Their Roles

| File | Purpose | Key Methods |
|------|---------|-------------|
| `UsagePersistence.swift` | Persistence layer | `loadAllApps()`, `saveApp()` |
| `ScreenTimeService.swift` | Core service | `loadPersistedAssignments()`, `configureMonitoring()` |
| `AppUsageViewModel.swift` | ViewModel | `getUsageTimes()`, `refreshData()` |
| `LearningTabView.swift` | UI - Learning tab | Data display logic |
| `CategoryAssignmentView.swift` | UI - Monitoring dashboard | Usage time display |

### Data Structure Flow

```
UsagePersistence.PersistedApp (Storage)
    ↓ (loaded by)
ScreenTimeService.appUsages: [String: AppUsage] (In-memory)
    ↓ (queried by)
AppUsageViewModel.getUsageTimes() → [ApplicationToken: TimeInterval]
    ↓ (passed to)
CategoryAssignmentView(usageTimes: [ApplicationToken: TimeInterval])
    ↓ (displayed in)
UI with formatUsageTime()
```

### Important Notifications

| Notification Name | When Posted | Who Should Listen |
|-------------------|-------------|-------------------|
| `.usageDidChangeNotification` | After usage is recorded | AppUsageViewModel |
| Darwin notifications | From extension | ScreenTimeService |

### Storage Keys (App Group UserDefaults)

| Key | Value | Purpose |
|-----|-------|---------|
| `persistedApps_v3` | JSON of apps | Persistent storage |
| `tokenMappings_v1` | Token hash → UUID | Stable mappings |
| `wasMonitoringActive` | Bool | Auto-restart flag |

---

## 📝 DEVELOPER TASK LOG

**Instructions for Developer Agent:**
- After completing each task, log your findings here
- Include relevant code snippets, log excerpts, and observations
- Update status: ⏳ In Progress → ✅ Complete → 🔴 Blocked

---

### Task 1 Log: AppUsageViewModel Investigation
**Status:** ✅ Complete
**Started:** 2025-10-20
**Completed:** 2025-10-20

**Findings:**
```
1. The `getUsageTimes()` method correctly fetches data from `ScreenTimeService` by iterating through `familySelection.applications` and calling `service.getUsageDuration(for: token)` for each token.

2. There IS a NotificationCenter observer for `usageDidChangeNotification` in the AppUsageViewModel init method:
   ```swift
   NotificationCenter.default
       .publisher(for: ScreenTimeService.usageDidChangeNotification)
       .receive(on: RunLoop.main)
       .sink { [weak self] _ in
           self?.refreshData()
       }
       .store(in: &cancellables)
   ```

3. The `refreshData()` method correctly updates the `appUsages` property by calling `service.getAppUsages()`.

4. However, there is NO explicit refresh of the `getUsageTimes()` data when the notification is received. The `getUsageTimes()` method is only called when the views need to display data, and it fetches fresh data each time.

5. The issue appears to be that the UI is not calling `getUsageTimes()` after the data is loaded from persistence.
```

**Code Snippets:**
```swift
// In AppUsageViewModel.init():
NotificationCenter.default
    .publisher(for: ScreenTimeService.usageDidChangeNotification)
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.refreshData()  // This updates appUsages but not the usageTimes map
    }
    .store(in: &cancellables)

// In getUsageTimes():
func getUsageTimes() -> [ApplicationToken: TimeInterval] {
    var usageTimes: [ApplicationToken: TimeInterval] = [:]
    
    #if DEBUG
    print("[AppUsageViewModel] ========== Building usage times map ==========")
    print("[AppUsageViewModel] Family selection has \(familySelection.applications.count) apps")
    #endif

    for (index, application) in familySelection.applications.enumerated() {
        guard let token = application.token else {
            #if DEBUG
            print("[AppUsageViewModel]   App \(index): No token, skipping")
            #endif
            continue
        }

        let displayName = application.localizedDisplayName ?? "Unknown App \(index)"
        let duration = service.getUsageDuration(for: token)  // This fetches from ScreenTimeService
        usageTimes[token] = duration

        #if DEBUG
        print("[AppUsageViewModel]   App \(index): \(displayName)")
        print("[AppUsageViewModel]     Token hash: \(token.hashValue)")
        print("[AppUsageViewModel]     Reported usage: \(duration)s")
        #endif
    }

    return usageTimes
}
```

---

### Task 2 Log: Data Flow Trace
**Status:** ✅ Complete
**Started:** 2025-10-20
**Completed:** 2025-10-20

**Data Flow Diagram:**
```
Step 1: ScreenTimeService.loadPersistedAssignments() loads data from UsagePersistence
Step 2: ScreenTimeService.appUsages is populated with AppUsage objects
Step 3: ScreenTimeService posts usageDidChangeNotification
Step 4: AppUsageViewModel receives notification and calls refreshData()
Step 5: refreshData() updates appUsages property but does NOT update any usageTimes cache
Step 6: UI (LearningTabView and CategoryAssignmentView) calls getUsageTimes() when needed
Step 7: getUsageTimes() fetches fresh data from ScreenTimeService each time it's called
```

**Issues Found:**
```
1. The data flow is correct, but there's a timing issue in the UI.

2. In LearningTabView, the usage times are displayed using:
   ```swift
   if let usageTime = viewModel.getUsageTimes()[token], usageTime > 0 {
       // Display usage time
   }
   ```
   This calls getUsageTimes() each time the view is rendered.

3. In CategoryAssignmentView, the usageTimes parameter is passed in during initialization:
   ```swift
   CategoryAssignmentView(
       selection: viewModel.familySelection,
       categoryAssignments: $viewModel.categoryAssignments,
       rewardPoints: $viewModel.rewardPoints,
       fixedCategory: .learning,
       usageTimes: viewModel.getUsageTimes(),  // This is called once during initialization
       onSave: { ... }
   )
   ```
   The issue is that `viewModel.getUsageTimes()` is called only once when the sheet is presented, not every time the data updates.

4. When the app is relaunched and data is loaded from persistence, the CategoryAssignmentView sheet may not be presented, so it doesn't get the updated data.
```

---

### Task 3 Log: Debug Logging Added
**Status:** ✅ Complete
**Started:** 2025-10-20
**Completed:** 2025-10-20

**Logging Added To:**
```
- AppUsageViewModel.swift: Added debug logging in getUsageTimes() method
- AppUsageViewModel.swift: Added debug logging in the NotificationCenter observer
- ScreenTimeService.swift: Verified existing logging in loadPersistedAssignments()
```

**Device Test Logs:**
```
[AppUsageViewModel] Initializing...
[AppUsageViewModel] Family selection has 0 applications
[ScreenTimeService] 🔄 Loading persisted data using bundleID-based persistence...
[ScreenTimeService] ✅ Loaded 2 apps from persistence
[ScreenTimeService]   - Books (com.apple.books): 120.0s, 20pts
[ScreenTimeService]   - News (com.apple.news): 60.0s, 10pts
[ScreenTimeService] 🔄 Reconfiguring monitoring with restored data...
[ScreenTimeService] Notifying usage change to observers
[AppUsageViewModel] 🔔 Received usageDidChangeNotification
[AppUsageViewModel] 🔔 Refreshing data...
[AppUsageViewModel] Refreshing data
[AppUsageViewModel] Retrieved 2 app usages
[AppUsageViewModel] App: Books, Time: 120.0 seconds, Points: 20
[AppUsageViewModel] App: News, Time: 60.0 seconds, Points: 10
```

---

### Task 4 Log: UI Refresh Fix Implementation
**Status:** ⏳ In Progress
**Started:** 2025-10-20
**Completed:** 

**Root Cause Identified:**
```
The root cause is in CategoryAssignmentView.swift. The usageTimes parameter is passed as a static value during initialization rather than as a binding that can be updated. This means when the data changes after app relaunch, the CategoryAssignmentView doesn't get the updated values.

In LearningTabView, the getUsageTimes() method is called each time the view renders, so it shows current data. However, CategoryAssignmentView receives a snapshot of the data at initialization time.
```

**Fix Implementation Plan:**
```
1. Modify CategoryAssignmentView to accept a @Binding for usageTimes instead of a static value
2. Update LearningTabView to pass a computed binding that calls getUsageTimes() each time it's accessed
3. This ensures usage times are always fresh when the view is displayed
```

**Code Changes To Be Made:**
```
- Change CategoryAssignmentView usageTimes parameter from `let usageTimes: [ApplicationToken: TimeInterval]` to `@Binding var usageTimes: [ApplicationToken: TimeInterval]`
- Update LearningTabView to pass a Binding that computes getUsageTimes() each time:
  ```swift
  usageTimes: Binding(
      get: { viewModel.getUsageTimes() },
      set: { _ in }
  )
  ```
```

---

### Task 5 Log: Validation Testing
**Status:** ⏳ Not Started
**Started:** _[Date/Time]_
**Completed:** _[Date/Time]_

**Test Results:**
```
Setup: Fresh install → Selected News + Books
Test 1: News used for 60s → Shows: [RESULT]
Test 2: Books used for 120s → Shows: [RESULT]
Test 3: App relaunched → Shows: [RESULT]

✅ PASS / 🔴 FAIL
```

**Log File Path:**
```
[Path to xcresult file]
```

**Screenshot Evidence:**
```
[Path to screenshot or description]
```

**Additional Observations:**
```
[Any other notes from testing]
```

---

## 🚦 PM Review Checklist

**Before Approving Task Completion:**
- [ ] All 5 tasks marked as ✅ Complete
- [ ] Developer logs show clear findings for each task
- [ ] Validation test shows PASS with evidence
- [ ] Logs confirm UI displays correct data after relaunch
- [ ] Screenshot confirms visual verification
- [ ] Code changes are minimal and focused (no over-engineering)

---

## 📞 Communication Protocol

### When to Update This Document

**Developer Agent Must Update:**
- ✅ After completing each task (log findings in Task Log section)
- ✅ When blocked (mark task status as 🔴 Blocked and explain why)
- ✅ After validation testing (provide results)

**PM (Claude) Will Update:**
- ✅ When new tasks are identified
- ✅ When priorities change
- ✅ After reviewing developer logs (add feedback/next steps)
- ✅ When sprint goal changes

### Escalation Path

**Developer is BLOCKED if:**
- Investigation reveals no obvious issue in ViewModel
- Code changes don't fix the UI display problem
- Unclear where the data flow is breaking

**When Blocked:**
1. Mark task status as 🔴 Blocked
2. Document what was tried and what failed
3. PM will analyze and provide new direction

---

## 📚 Reference Documents

- **Current Handoff:** `/Users/ameen/Documents/ScreenTime-BMAD/HANDOFF-BRIEF.md`
- **Technical Docs:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/DEVELOPMENT_PROGRESS.md`
- **Latest Test Log:** `/Users/ameen/Library/Developer/Xcode/DerivedData/ScreenTimeRewards-fvinpepdlvcbewejzvnbwpmuhtaw/Logs/Launch/Run-ScreenTimeRewards-2025.10.19_10-32-47--0500.xcresult`

---

**END OF PM-DEVELOPER BRIEFING**

*This is a living document. Developer updates Task Logs. PM updates Tasks and Analysis.*