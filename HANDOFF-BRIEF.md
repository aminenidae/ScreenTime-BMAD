# Development Handoff Brief
**Date:** 2025-10-18
**Project:** ScreenTime-BMAD / ScreenTimeRewards
**Status:** In Progress - Compilation Error Needs Resolution

---

## Executive Summary

During technical feasibility testing (Story 0.1), we discovered a **CRITICAL blocker**: `ApplicationToken` persistence was broken - tokens disappeared on app restart, causing usage data to be attributed to wrong apps (e.g., Books usage showing up as News usage).

We implemented a fix using **index-based persistence with stable sorting**, but there's currently a compilation error that needs to be resolved before testing the fix on device.

---

## The Problem

### Root Cause
1. **`ApplicationToken.hashValue` is unstable** - changes every app restart
2. **`FamilyActivitySelection.applications` is a Set** - iteration order is non-deterministic
3. Combined effect: Usage data gets attributed to wrong apps after restart

### Evidence
```
// Session 1
token.hash.-7681097659728334467  → Books app

// Session 2 (after app restart)
token.hash.-8307535256005207221  → Books app (DIFFERENT HASH!)
```

User tested and confirmed: "Books 60s usage showed as News 60s after restart"

---

## The Solution

### Strategy: Index-Based Persistence + Stable Sorting

Since `ApplicationToken` can't be persisted directly (not Codable, NSKeyedArchiver unreliable), we:

1. **Store data by array index** instead of token
2. **Sort the Set into a stable array** before persisting/restoring
3. **Use same sort order** on both persist and restore operations

### Key Implementation

**File:** `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift`

```swift
// Helper function to create stable sorted array from Set
private func stablySortedApplications(from selection: FamilyActivitySelection) -> [FamilyActivitySelection.Application] {
    let applications = Array(selection.applications)

    // Sort by storageKey to ensure consistent ordering
    return applications.sorted { app1, app2 in
        guard let token1 = app1.token, let token2 = app2.token else {
            return false
        }

        let key1 = storageKey(for: token1)
        let key2 = storageKey(for: token2)

        return key1 < key2
    }
}
```

All 6 persistence methods updated to use stable sorting:
- `persistCategoryAssignments()`
- `persistRewardPoints()`
- `persistUsageData()`
- `restoreCategoryAssignments()`
- `restoreRewardPoints()`
- `restoreUsageData()`

**File:** `/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

Updated save methods to pass `selection` parameter:
```swift
func saveCategoryAssignments() {
    service.persistCategoryAssignments(categoryAssignments, selection: familySelection)
}
```

---

## Current Status

### ✅ Completed
- [x] Identified root cause (hash instability + Set ordering)
- [x] Designed index-based persistence solution
- [x] Implemented stable sorting helper
- [x] Updated all 6 persistence methods
- [x] Updated ViewModel save methods
- [x] Added FamilyActivitySelection persistence
- [x] Code written and saved to files

### ⚠️ **BLOCKED: Compilation Error**

**Error Location:** `ScreenTimeService.swift:111`

**Current Code:**
```swift
private func stablySortedApplications(from selection: FamilyActivitySelection) -> [FamilyActivitySelection.Application] {
```

**Issue:** Swift can't resolve the type `FamilyActivitySelection.Application`

**Attempts Made:**
1. `[FamilyControls.Application]` - doesn't exist
2. `[FamilyActivitySelection.Applications.Element]` - Applications not a member type
3. `[FamilyActivitySelection.Application]` - Application not a member type (CURRENT)
4. `Array<FamilyActivitySelection.applications.Element>` - applications is a property, not a type

### 🔍 Next Steps for Dev Team

**IMMEDIATE (HIGH PRIORITY):**

1. **Resolve Type Declaration**
   - Option A: Let Swift infer the type (remove explicit return type)
   - Option B: Find correct type from FamilyControls framework documentation
   - Option C: Use type inference with `some` keyword: `-> [some Any]`

2. **Build and Test on Device**
   ```bash
   cd ScreenTimeRewardsProject
   xcodebuild -project ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards \
     -destination 'platform=iOS Simulator,name=iPhone 16' clean build
   ```

3. **Verify Fix Works:**
   - Launch app
   - Select Books app, assign to Learning, use for 60s
   - Close and relaunch app
   - Verify Books still shows 60s (not attributed to different app)

4. **Update Story 0.1**
   - Document the fix in `/docs/stories/0.1.execute-technical-feasibility-tests.md`
   - Add to "Critical Constraints Discovered" section
   - Mark persistence as validated

---

## Technical Context

### Key Files Modified

| File | Lines | Changes |
|------|-------|---------|
| `ScreenTimeService.swift` | 111-459 | Added stable sort + 6 persistence methods |
| `AppUsageViewModel.swift` | Multiple | Updated save methods to pass selection |

### Storage Strategy

**UserDefaults Keys (App Group: `group.com.screentimerewards.shared`):**
- `categoryAssignments_byIndex` - Dictionary<Int, String>
- `rewardPoints_byIndex` - Dictionary<Int, Int>
- `appUsages_byIndex` - Dictionary<Int, AppUsage>
- `familySelection_persistent` - FamilyActivitySelection (Codable)

**Critical Insight:** `FamilyActivitySelection` IS Codable (validated), so we can persist/restore the entire selection.

### Debug Logs to Watch

```swift
[ScreenTimeService] ✅ Persisted 2 category assignments by index (stable sort)
[ScreenTimeService] Mapping app at index 0 (sorted key: token.xxx...) → learning
[ScreenTimeService] Mapping app at index 1 (sorted key: token.yyy...) → reward
```

On restore:
```swift
[ScreenTimeService] ✅ Restored index 0 (sorted key: token.xxx..., Books) → learning
[ScreenTimeService] ✅ Successfully restored 2/2 category assignments (stable sort)
```

---

## Known Constraints

From technical feasibility study (Story 0.1):

1. **ApplicationToken Instability** - Hash changes per session
2. **Set Iteration Non-Determinism** - Order varies between runs
3. **FamilyActivitySelection IS Codable** - Can persist selection ✓
4. **AppUsage IS Codable** - Can persist usage data ✓
5. **NSKeyedArchiver Unreliable** - Falls back to hash

---

## Testing Plan

Once compilation error is fixed:

### Test Case: Persistence Across Restart

**Setup:**
1. Clean install app
2. Request Screen Time permission
3. Select 2 apps: Books (Learning), News (Reward)
4. Set reward points: Books=20, News=10

**Test:**
1. Use Books for 60 seconds → should show 60s, 20pts
2. Close app completely
3. Relaunch app
4. **Verify:** Books still shows 60s, 20pts (NOT attributed to News)

**Pass Criteria:**
- Books usage stays with Books ✓
- Points stay with correct app ✓
- Total points correct ✓

---

## Project Scope Context

User chose **Option B (Full MVP)** for project scope. However, we must complete this persistence fix before updating project documentation (PRD, architecture, stories).

Once fix is validated:
- Mark Story 0.1 as COMPLETE
- Proceed with full project redraft (new PRD, architecture, epics/stories)

---

## Questions for Dev Team

If you encounter issues:

1. **Type resolution:** Check FamilyControls framework docs for `FamilyActivitySelection.applications` element type
2. **Compilation fails:** Try removing explicit return type and let Swift infer
3. **Runtime errors:** Check App Group entitlements are configured correctly
4. **Still mismatched after fix:** Verify stable sort is using same key on both persist/restore

---

## Git Status

**Branch:** main
**Last Commit:** b241cf1 (Update development progress and documentation files)

**Modified Files:**
- `ScreenTimeService.swift` - Persistence fix implemented
- `AppUsageViewModel.swift` - Save methods updated

**Not Committed:** Current changes are in working directory, not committed yet.

---

## Contact Information

**Original Dev:** Available via GitHub issues at https://github.com/anthropics/claude-code/issues

**Critical Files:**
- `/ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift:111` (COMPILE ERROR HERE)
- `/docs/stories/0.1.execute-technical-feasibility-tests.md` (Update after fix validated)

---

## Priority: HIGH

This is a CRITICAL blocker for Story 0.1 completion. The parent dashboard must track usage correctly - this is core value proposition of the app.

**Estimated Time to Fix:** 30-60 minutes (resolve type error + test on device)

---

## References

- Story 0.1: `/docs/stories/0.1.execute-technical-feasibility-tests.md`
- Debug Reports: `/Debug Reports/Build ScreenTimeRewards_2025-10-18T*.txt`
- FamilyControls Framework: https://developer.apple.com/documentation/familycontrols
