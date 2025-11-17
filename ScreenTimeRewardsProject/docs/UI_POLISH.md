# UI Polish: Usage Time Display Consistency Fix

## Problem Analysis

### Issue Summary
The app displays **inconsistent usage times** across different views. Each view (Child Mode, Parent Mode, App Detail View, Challenge Cards) shows different numbers when they should all display the same data.

### Root Causes Identified

1. **Time Period Mismatch**
   - Labels say "Today's Activity" but display all-time cumulative data
   - `AppUsage.totalTime` (all-time) used instead of `AppUsage.todayUsage` (today only)

2. **Inconsistent Data Sources**
   - Child Mode: Calculates from `viewModel.learningSnapshots.reduce { $0 + $1.totalSeconds }`
   - Parent Mode: Uses `viewModel.learningTime` and `viewModel.rewardTime`
   - Both read different properties from AppUsage model

3. **Unused Model Properties**
   - `AppUsage.todayUsage` property exists (correctly filters sessions by today's date)
   - Never called by any view in the codebase

4. **Desynchronized Updates**
   - Extension writes to `persistedApps_v3` UserDefaults
   - AppUsageViewModel reads on `refreshData()`
   - Challenge progress updates separately via `ChallengeService`
   - No guarantee all three stay synchronized

### Current Data Flow

```
Extension (DeviceActivityMonitorExtension)
  ↓ writes usage
UsagePersistence (App Group UserDefaults: persistedApps_v3)
  ↓ loads on refresh
ScreenTimeService.loadPersistedAssignments()
  ↓ converts to
AppUsageViewModel.appUsages: [String: AppUsage]
  ↓ splits into
  ├─ updateSnapshots() → learningSnapshots, rewardSnapshots
  └─ updateCategoryTotals() → learningTime, rewardTime
       ↓ displayed by
       ├─ Child Mode (uses snapshots - CORRECT pattern)
       └─ Parent Mode (uses totals - WRONG, shows all-time as "today")
```

### Affected Files & Line Numbers

| File | Lines | What It Displays | Current Source | Issue |
|------|-------|------------------|----------------|-------|
| `ChildChallengesTabView.swift` | 273-277, 285-289 | Learning/Reward time totals | `snapshots.reduce { $0 + $1.totalSeconds }` | Uses `totalSeconds` from snapshots which pull from `totalTime` (all-time) |
| `ChildChallengeDetailView.swift` | 150, 158, 234 | Challenge progress, per-app usage | `snapshot.totalSeconds` | Same as above |
| `ParentDashboardView.swift` | 97-99, 127-129 | "Today's Activity" learning/reward time | `viewModel.learningTime`, `viewModel.rewardTime` | **CRITICAL**: Shows all-time data with "Today" label |
| `ChallengeDetailView.swift` | 167, 512, 365-376 | Challenge progress, daily usage | `appUsageViewModel.learningSnapshots` | Uses snapshots (all-time) |
| `AppUsageDetailViews.swift` | 94, 100, 106 | 24h, 7d, 30d usage | `usage?.last24HoursUsage` etc. | Different time windows (correct for detail view) |
| `AppUsageViewModel.swift` | 1019-1024 | Category totals calculation | `appUsages.reduce { $0 + $1.totalTime }` | **ROOT CAUSE**: Uses `totalTime` instead of `todayUsage` |
| `AppUsageViewModel.swift` | 1033-1065 | Snapshot creation | `totalSeconds: appUsage.totalTime` | **ROOT CAUSE**: Uses `totalTime` instead of `todayUsage` |

---

## User Requirements

Based on user confirmation:
- ✅ **"Today's Activity"** must show usage from midnight to now (resets daily)
- ✅ **Challenge progress** tracks today's usage only (daily goals)
- ✅ **All views** showing "current usage" must display **identical numbers** (unified source)

---

## Implementation Plan

### Phase 1: Fix AppUsage Model Foundation
**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Models/AppUsage.swift`

**Current State** (lines 199-206):
```swift
var todayUsage: TimeInterval {
    let today = Calendar.current.startOfDay(for: Date())
    return sessions.filter { session in
        guard let sessionDate = session.endTime ?? session.startTime as Date? else { return false }
        return Calendar.current.isDate(sessionDate, inSameDayAs: today)
    }.reduce(0) { $0 + $1.duration }
}
```

**Tasks**:
1. **Verify** `todayUsage` correctly filters sessions (appears correct)
2. **Add** `todayPoints` property to match pattern:
   ```swift
   var todayPoints: Int {
       let today = Calendar.current.startOfDay(for: Date())
       return sessions.filter { session in
           guard let sessionDate = session.endTime ?? session.startTime as Date? else { return false }
           return Calendar.current.isDate(sessionDate, inSameDayAs: today)
       }.reduce(0) { $0 + $1.points }
   }
   ```
3. **Test** timezone handling (ensure midnight cutoff uses device timezone)

---

### Phase 2: Fix AppUsageViewModel Data Layer
**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

#### 2A. Fix `updateCategoryTotals()` (lines ~1019-1024)

**Current Code**:
```swift
learningTime = appUsages
    .filter { $0.category == AppUsage.AppCategory.learning }
    .reduce(0) { $0 + $1.totalTime }  // ← WRONG: all-time

rewardTime = appUsages
    .filter { $0.category == AppUsage.AppCategory.reward }
    .reduce(0) { $0 + $1.totalTime }  // ← WRONG: all-time
```

**Fix To**:
```swift
learningTime = appUsages
    .filter { $0.category == AppUsage.AppCategory.learning }
    .reduce(0) { $0 + $1.todayUsage }  // ← CORRECT: today only

rewardTime = appUsages
    .filter { $0.category == AppUsage.AppCategory.reward }
    .reduce(0) { $0 + $1.todayUsage }  // ← CORRECT: today only
```

#### 2B. Fix `updateSnapshots()` (lines ~1033-1065)

**Current Code** (example for learning):
```swift
let snapshot = LearningAppSnapshot(
    token: appUsage.deviceActivityToken,
    tokenHash: hashToken(appUsage.deviceActivityToken),
    name: appUsage.name ?? "Unknown App",
    totalSeconds: appUsage.totalTime,  // ← WRONG: all-time
    earnedPoints: appUsage.totalPoints, // ← WRONG: all-time
    iconData: appUsage.iconData
)
```

**Fix To**:
```swift
let snapshot = LearningAppSnapshot(
    token: appUsage.deviceActivityToken,
    tokenHash: hashToken(appUsage.deviceActivityToken),
    name: appUsage.name ?? "Unknown App",
    totalSeconds: appUsage.todayUsage,  // ← CORRECT: today only
    earnedPoints: appUsage.todayPoints, // ← CORRECT: today only (new property)
    iconData: appUsage.iconData
)
```

**Repeat for** `RewardAppSnapshot` creation in the same function.

---

### Phase 3: Verify Parent Dashboard View
**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/ParentMode/ParentDashboardView.swift`

**Current Code** (lines 97-99, 127-129):
```swift
// Learning Time
Text("\(Int(viewModel.learningTime / 60))")  // Now shows today only ✓

// Reward Time
Text("\(Int(viewModel.rewardTime / 60))")    // Now shows today only ✓
```

**Tasks**:
1. **Verify** displays use `viewModel.learningTime` and `viewModel.rewardTime`
2. **No changes needed** - will automatically show today's data after Phase 2 fixes
3. **Keep** "Today's Activity" labels (now accurate)
4. **Test** real-time updates when data refreshes

---

### Phase 4: Verify Child Mode Views
**Files**:
- `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/ChildMode/ChildChallengesTabView.swift`
- `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/ChildMode/ChildChallengeDetailView.swift`

**Current Code** (ChildChallengesTabView lines 273-277):
```swift
private var learningTimeMinutes: Int {
    let totalSeconds = viewModel.learningSnapshots.reduce(0) { $0 + $1.totalSeconds }
    return Int(totalSeconds / 60)
}
```

**Tasks**:
1. **No code changes needed** - snapshots already use correct aggregation pattern
2. **Automatic fix** after Phase 2 updates snapshots to use `todayUsage`
3. **Verify** totals match Parent Dashboard after implementation
4. **Test** real-time updates

---

### Phase 5: Fix Challenge System

#### 5A. Update Challenge Progress Calculation
**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Services/ChallengeService.swift`

**Current Approach**:
- `updateProgressForUsage()` called manually when usage changes
- Updates `ChallengeProgress.currentValue` incrementally

**Required Changes**:
1. **Option A - Incremental Updates (Current Pattern)**:
   - Keep `updateProgressForUsage()` mechanism
   - Add daily reset at midnight for all active challenges
   - Sync challenge progress with `AppUsage.todayUsage` on app launch

2. **Option B - Calculated Progress (Recommended)**:
   - Remove incremental updates
   - Calculate progress on-demand from `AppUsage.todayUsage`
   - Example:
     ```swift
     func getCurrentProgress(for challenge: Challenge) -> Int {
         let relevantApps = getAppsForChallenge(challenge)
         let todayTotal = relevantApps.reduce(0) { total, app in
             return total + Int(app.todayUsage / 60)  // Convert to minutes
         }
         return todayTotal
     }
     ```

**Recommendation**: Use **Option B** for consistency. Challenge progress becomes a view of the underlying usage data, not a separate data store.

#### 5B. Update Challenge Views
**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/ParentMode/ChallengeDetailView.swift`

**Tasks**:
1. If using Option B, update progress calculation to query `AppUsage.todayUsage`
2. Ensure per-app usage display (lines 365-376) uses snapshots (already correct)
3. Verify progress percentages match snapshot totals

---

### Phase 6: Update Extension Recording (If Needed)
**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`

**Current State**:
- Records incremental usage to `persistedApps_v3`
- Stores `totalSeconds` and `earnedPoints`

**Tasks**:
1. **Verify** extension correctly appends new `UsageSession` records with timestamps
2. **No changes needed** if sessions include proper timestamps (main app filters by date)
3. **Test** session recording includes `startTime` and `endTime`

---

### Phase 7: Add Midnight Reset Mechanism

**File**: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

**Current State**:
- No automatic refresh at midnight
- Data only refreshes on manual `refreshData()` call

**Required Addition**:
```swift
// In AppUsageViewModel
private var midnightTimer: Timer?

func setupMidnightRefresh() {
    // Calculate seconds until next midnight
    let now = Date()
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    let secondsUntilMidnight = tomorrow.timeIntervalSince(now)

    // Schedule refresh at midnight
    midnightTimer = Timer.scheduledTimer(withTimeInterval: secondsUntilMidnight, repeats: false) { [weak self] _ in
        self?.refreshData()
        self?.setupMidnightRefresh()  // Reschedule for next day
    }
}

deinit {
    midnightTimer?.invalidate()
}
```

**Call** `setupMidnightRefresh()` in ViewModel initialization.

---

### Phase 8: Verification & Testing

**Create Test Checklist**:

1. **Data Consistency Test**:
   - [ ] Parent Dashboard learning time == Child Mode learning time
   - [ ] Parent Dashboard reward time == Child Mode reward time
   - [ ] Challenge progress == Sum of relevant app snapshots
   - [ ] App detail view "today" == Snapshot total for that app

2. **Midnight Rollover Test**:
   - [ ] Change device time to 11:59 PM
   - [ ] Record some usage
   - [ ] Wait until midnight (or change to 12:01 AM)
   - [ ] Verify all "today" displays reset to 0 or reflect new day only

3. **Real-time Update Test**:
   - [ ] Open Parent Dashboard
   - [ ] Use a learning app for 5 minutes
   - [ ] Return to Parent Dashboard
   - [ ] Verify learning time increased by ~5 minutes
   - [ ] Check Child Mode shows same increase
   - [ ] Check Challenge progress updated identically

4. **Debug Logging Test**:
   Add temporary logging to compare sources:
   ```swift
   // In AppUsageViewModel.refreshData()
   print("=== USAGE CONSISTENCY CHECK ===")
   print("ViewModel learningTime: \(learningTime / 60) min")
   print("Snapshots total: \(learningSnapshots.reduce(0) { $0 + $1.totalSeconds } / 60) min")
   print("AppUsage.todayUsage total: \(appUsages.filter { $0.category == .learning }.reduce(0) { $0 + $1.todayUsage } / 60) min")
   // All three should be IDENTICAL
   ```

---

## Expected Outcome

After implementation:
- ✅ All views displaying "Today's Activity" show **identical values**
- ✅ Values represent usage from **midnight to now** (today only)
- ✅ Challenge progress matches **today's usage** for relevant apps
- ✅ Data **resets at midnight** automatically
- ✅ **Real-time updates** sync across all views

---

## Files Requiring Changes

### Must Edit:
1. `AppUsage.swift` - Add `todayPoints` property
2. `AppUsageViewModel.swift` - Fix `updateCategoryTotals()` and `updateSnapshots()`, add midnight refresh
3. `ChallengeService.swift` - Implement calculated progress (Option B)

### Verify Only (No Changes):
4. `ParentDashboardView.swift` - Already uses correct properties
5. `ChildChallengesTabView.swift` - Already uses correct pattern
6. `ChildChallengeDetailView.swift` - Already uses snapshots
7. `ChallengeDetailView.swift` - May need progress calc update

### Test:
8. `DeviceActivityMonitorExtension.swift` - Verify session timestamps

---

## Implementation Priority

**Critical Path**:
1. Phase 1 (AppUsage model) → Phase 2 (ViewModel) → Phase 3-4 (Verify views)
2. These three phases fix the immediate inconsistency issue

**Follow-up**:
3. Phase 5 (Challenges) → Required for full consistency
4. Phase 7 (Midnight reset) → Required for correct daily behavior
5. Phase 8 (Testing) → Required for validation

**Start with**: Phase 1 + 2 for immediate 90% fix.

---

## MIGRATION STRATEGY (Added 2025-11-16)

### Problem Discovered During Implementation

After implementing daily usage tracking, existing apps in UserDefaults had:
- `totalSeconds`: 600 (cumulative all-time usage)
- `todaySeconds`: 0 (newly added field, defaulted to 0 by decoder)
- `lastResetDate`: today (newly added field, defaulted to today)

**Result**: When creating `AppUsage` objects, if `todaySeconds=0`, no sessions were created, causing `todayUsage` to return 0 seconds even though the app had actual usage.

### Migration Solution

**File**: `ScreenTimeService.swift:682-725` (function `appUsage(from:)`)

**Strategy**: Treat all existing usage as "today's usage" during migration to maintain backward compatibility.

```swift
// Migration logic:
let usageSecondsToday = persisted.todaySeconds > 0 
    ? persisted.todaySeconds      // New data with daily tracking
    : persisted.totalSeconds       // Old data - assume all is from today
```

**Why This Works**:
1. **Old Data**: When app first loads after update, `todaySeconds=0` but `totalSeconds>0`
   - Creates sessions using `totalSeconds` as today's usage
   - User sees their existing usage instead of 0
   - Tomorrow at midnight, `recordUsage()` will detect new day and reset `todaySeconds=0`

2. **New Data**: After first usage event with new extension code
   - Extension records to both `totalSeconds` AND `todaySeconds`
   - Migration check sees `todaySeconds>0` and uses it
   - Normal daily tracking from this point forward

### Debugging Migration

**Look for this log**:
```
[ScreenTimeService] 📦 Migration: Treating 600s as today's usage for YouTube
```

This confirms old data is being migrated correctly.

**Extension Not Updated Issue**:
If you don't see `[ExtensionPersistence]` logs in console output, the extension binary hasn't been updated with new code. The extension runs in a separate process and iOS may cache the old binary.

**Solution**:
1. Delete app completely from device
2. Clean build folder in Xcode (⇧⌘K)
3. Rebuild and reinstall

### Expected Behavior After Migration

**First Launch After Update**:
- Old usage displays correctly (treated as "today")
- Console shows migration logs
- UI shows consistent values across all views

**After First New Usage Event**:
- Extension writes to both `todaySeconds` and `totalSeconds`
- Migration no longer triggers (todaySeconds > 0)
- Daily tracking works normally

**Next Day (After Midnight)**:
- Extension detects new day via `lastResetDate` check
- Resets `todaySeconds=0` and `todayPoints=0`
- UI shows 0 for "today's" usage
- `totalSeconds` continues accumulating

---

## Implementation Timeline

1. ✅ **Phase 1**: Added `todaySeconds`, `todayPoints`, `lastResetDate` to `PersistedApp`
2. ✅ **Phase 2**: Updated `recordUsage()` in both main app and extension to track daily usage
3. ✅ **Phase 3**: Updated `AppUsageViewModel` to use `todayUsage` instead of `totalTime`
4. ✅ **Phase 4**: Fixed `ScreenTimeService.appUsage(from:)` to handle migration
5. ⏳ **Phase 5**: Testing - requires full app reinstall to update extension binary

---

## Files Modified (Final Summary)

1. **UsagePersistence.swift** 
   - Added 3 new fields to `PersistedApp`: `todaySeconds`, `todayPoints`, `lastResetDate`
   - Added custom decoder for backward compatibility
   - Updated `recordUsage()` to track daily usage and auto-reset at midnight

2. **DeviceActivityMonitorExtension.swift**
   - Updated duplicate `PersistedApp` struct with same 3 fields
   - Updated extension's `recordUsage()` with midnight detection and reset

3. **ScreenTimeService.swift**
   - Updated `appUsage(from:)` with migration logic for old data
   - Updated 3 locations creating `PersistedApp` to include new fields

4. **AppUsageViewModel.swift** 
   - Updated `updateCategoryTotals()`: use `todayUsage` instead of `totalTime`
   - Updated `updateSnapshots()`: use `todayUsage` and `todayPoints` instead of cumulative values

---

## Verification Checklist

- [ ] Delete app from device
- [ ] Clean build folder (⇧⌘K)
- [ ] Rebuild and install
- [ ] Check console for `[ExtensionPersistence]` logs when using apps
- [ ] Verify all views show identical usage times
- [ ] Check migration log appears for existing apps
- [ ] Test midnight rollover (change device time to 11:59 PM, wait, verify reset)

---

# NEW UI ISSUES (2025-11-17)

## Issue 3: Challenge Detail View Shows "0 min today" Despite Actual Usage

**Date Discovered**: 2025-11-17
**Severity**: HIGH - Critical user-facing data inconsistency
**Status**: 🔴 OPEN - Needs Fix

### Problem Description

The Child Challenge Detail View displays "0 min today" for learning/reward apps even when the challenge shows significant usage (e.g., 20/10 min = 20 minutes tracked).

**User Report**:
- Challenge progress card: Shows "20 / 10 min" (200% complete)
- Learning Apps section: Shows "YouTube - 0 min today"
- **Expected**: Should show "YouTube - 20 min today"

### Root Cause Analysis

**File**: `ChildChallengeDetailView.swift` line 234

```swift
Text("\(formatTime(Int(snapshot.totalSeconds))) today")
    .font(.system(size: 12))
    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
```

**Data Flow**:
1. `snapshot.totalSeconds` comes from `LearningAppSnapshot` (AppUsageViewModel.swift:598)
2. Snapshot creation calls: `let appUsage = service.getUsage(for: token)`
3. `ScreenTimeService.getUsage(for:)` looks up usage by:
   - Convert token → tokenHash
   - Look up logicalID from tokenHash
   - Return `appUsages[logicalID]`
4. **If token-to-logicalID mapping is missing/broken → returns `nil`**
5. When `nil`, defaults to `todayUsage = 0`

**The Data Disconnect**:
- **Challenge Progress** (20 min tracked): Stored in Core Data via `ChallengeService.recordUsage()`
- **Per-App Usage Display** (0 min shown): Reads from `ScreenTimeService.appUsages` dictionary via `getUsage(for:)`
- These two systems use different data sources and don't sync properly

**Why the Mapping Breaks**:
1. Token is available: `snapshot.token` is a valid `ApplicationToken`
2. But `ScreenTimeService.tokenToLogicalID[tokenHash]` lookup returns `nil`
3. This happens when:
   - Extension writes usage with a different token hash
   - Token-to-logicalID mapping was never created for this app
   - Mapping was cleared but usage data persists

### Evidence from Code

**AppUsageViewModel.swift:598-600** (creates snapshot):
```swift
let appUsage = service.getUsage(for: token)
let totalSeconds = appUsage?.todayUsage ?? 0  // ← Returns 0 when appUsage is nil
```

**ScreenTimeService.swift:getUsage(for:)** (lookup logic):
```swift
func getUsage(for token: ApplicationToken) -> AppUsage? {
    let tokenHash = hashToken(token)
    guard let logicalID = tokenToLogicalID[tokenHash] else {
        return nil  // ← Mapping missing, returns nil
    }
    return appUsages[logicalID]
}
```

### Alternative Data Source Available

**UsagePersistence** has the actual usage data:
- Extension writes directly to `UsagePersistence.app(for: logicalID).todaySeconds`
- This data IS present and correct (20 minutes)
- Challenge service reads from this correctly
- But `AppUsageViewModel` doesn't use this source

### Proposed Solutions

#### Option A: Fix Token-to-LogicalID Mapping (Root Cause Fix)

**File**: `ScreenTimeService.swift`

1. **Ensure mapping is created** when apps are assigned to categories:
   ```swift
   func assignApp(_ token: ApplicationToken, to category: AppUsage.AppCategory) {
       let tokenHash = hashToken(token)
       let logicalID = // ... determine or create logicalID
       tokenToLogicalID[tokenHash] = logicalID  // ✅ Ensure this happens
       // ... rest of assignment
   }
   ```

2. **Rebuild mappings on load** from persisted apps:
   ```swift
   private func loadPersistedAssignments() {
       // ... existing code ...
       for app in usagePersistence.apps {
           if let token = app.token {
               let tokenHash = hashToken(token)
               tokenToLogicalID[tokenHash] = app.logicalID  // ✅ Rebuild mapping
           }
       }
   }
   ```

3. **Validate mapping exists** before recording usage

#### Option B: Direct UsagePersistence Lookup (Simpler, More Reliable)

**File**: `AppUsageViewModel.swift` lines 598-600

**Current**:
```swift
let appUsage = service.getUsage(for: token)
let totalSeconds = appUsage?.todayUsage ?? 0
```

**Replace with**:
```swift
// Try getting from service first (preserves existing functionality)
let appUsage = service.getUsage(for: token)
var totalSeconds = appUsage?.todayUsage ?? 0

// Fallback: Read directly from UsagePersistence
if totalSeconds == 0 {
    let tokenHash = service.hashToken(token)
    if let logicalID = service.tokenToLogicalID[tokenHash],
       let persistedApp = service.usagePersistence.app(for: logicalID) {
        totalSeconds = TimeInterval(persistedApp.todaySeconds)
    }
}
```

**Benefits**:
- Fixes the immediate display issue
- Provides fallback when mapping is broken
- Doesn't break existing functionality
- Uses the same data source as ChallengeService

#### Option C: Unified Data Source (Architectural Fix)

Make `AppUsageViewModel` read directly from `UsagePersistence` instead of maintaining a separate `appUsages` dictionary:

**File**: `AppUsageViewModel.swift`

```swift
// Remove: var appUsages: [AppUsage] = []
// Replace with: Direct reads from service.usagePersistence

private func updateSnapshots() {
    let persistedApps = service.usagePersistence.apps

    learningSnapshots = persistedApps
        .filter { $0.category == "learning" }
        .map { persistedApp in
            LearningAppSnapshot(
                token: persistedApp.token ?? ApplicationToken(),
                tokenHash: persistedApp.logicalID,
                displayName: persistedApp.displayName,
                totalSeconds: TimeInterval(persistedApp.todaySeconds),  // ✅ Direct read
                earnedPoints: persistedApp.todayPoints,
                pointsPerMinute: persistedApp.pointsPerMinute
            )
        }
}
```

**Benefits**:
- Single source of truth (UsagePersistence)
- No sync issues between multiple data stores
- Simpler architecture
- Matches ChallengeService pattern

**Drawbacks**:
- Larger refactor
- Need to ensure all AppUsageViewModel consumers still work

### Recommended Implementation: Option B (Quick Fix) + Option A (Proper Fix)

**Immediate (today)**:
1. Implement Option B fallback in `AppUsageViewModel.swift`
2. Test that "0 min today" is now showing correct values

**Follow-up (next sprint)**:
3. Implement Option A to fix token mapping persistence
4. Remove Option B fallback once mapping is reliable

**Long-term (consider for refactor)**:
5. Evaluate Option C for architectural simplification

---

## Issue 4: App Detail View Shows "Unknown App" Text Instead of Icon

**Date Discovered**: 2025-11-17
**Severity**: MEDIUM - Poor UX, confusing navigation
**Status**: 🔴 OPEN - Needs Fix

### Problem Description

When tapping on an app in the challenge detail view to see its usage breakdown, the detail view shows:
- **Navigation title**: "Unknown App" (text)
- **Expected**: App icon (visual)

**User Report**:
- App detail view header shows text "Unknown App"
- Want: Replace text with the app's icon (same icon shown in the list)

### Root Cause Analysis

**File**: `AppUsageDetailViews.swift` lines 3-29

```swift
struct LearningAppDetailView: View {
    let snapshot: LearningAppSnapshot
    @State private var usage: AppUsage?
    @Environment(\.dismiss) private var dismiss
    private let service = ScreenTimeService.shared

    var body: some View {
        NavigationStack {
            AppUsageDetailContent(...)
            .navigationTitle(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)  // ← LINE 18
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

**The Limitation**:
- SwiftUI's `.navigationTitle()` only accepts `String`, `Text`, or `LocalizedStringKey`
- Cannot pass a `View` (like `Label`) to `.navigationTitle()`
- iOS renders navigation titles as text only

**Available Data**:
- `snapshot.token` - The `ApplicationToken` from FamilyControls framework
- `snapshot.displayName` - App name as String
- `Label(token)` API can display the app's icon

### How Other Views Display App Icons

**ChildChallengeDetailView.swift** lines 211-216 (list item):
```swift
if #available(iOS 15.2, *) {
    Label(snapshot.token)
        .labelStyle(.iconOnly)
        .scaleEffect(1.35)
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}
```

This works because it's in the view body, not in a navigation title modifier.

### Proposed Solutions

#### Option A: Custom Toolbar Title (Recommended)

Replace `.navigationTitle()` with a custom toolbar item using `.principal` placement.

**File**: `AppUsageDetailViews.swift` lines 13-27

**Current**:
```swift
var body: some View {
    NavigationStack {
        AppUsageDetailContent(...)
        .navigationTitle(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)  // ← Remove
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
```

**Replace with**:
```swift
var body: some View {
    NavigationStack {
        AppUsageDetailContent(...)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Custom title with app icon
            ToolbarItem(placement: .principal) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.5)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.headline)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
```

**Apply same fix to** `RewardAppDetailView` (lines 34-58 in same file).

#### Option B: Icon + Text Combination

Show both icon and app name in the navigation bar.

```swift
ToolbarItem(placement: .principal) {
    HStack(spacing: 8) {
        if #available(iOS 15.2, *) {
            Label(snapshot.token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.2)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }

        Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
            .font(.headline)
            .lineLimit(1)
    }
}
```

#### Option C: Keep Text, Add Large Icon Below Nav Bar

Keep `.navigationTitle()` as-is, but add a large hero icon at the top of the content area.

**File**: `AppUsageDetailViews.swift` lines 62-113 (AppUsageDetailContent)

Add icon as first element:
```swift
ScrollView {
    VStack(spacing: 24) {
        // Hero app icon
        if #available(iOS 15.2, *), let token = snapshot?.token {
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(3.0)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(radius: 8)
        }

        // Usage Breakdown section (existing)
        VStack(alignment: .leading, spacing: 16) {
            // ... existing code
        }
    }
}
```

**Drawback**: Takes up screen space, but provides strong visual identity.

### Recommended Implementation: Option A

**Reasoning**:
1. Clean, minimal design
2. Matches iOS design patterns (app icons often appear in nav bars)
3. Doesn't waste content space
4. Consistent with how app icons appear in lists
5. Provides instant visual recognition

**Fallback**:
- For iOS < 15.2 (pre-FamilyControls Label API), show text title
- Graceful degradation

### Implementation Details

**Files to modify**:
1. `AppUsageDetailViews.swift`:
   - Line 18: Remove/replace `.navigationTitle()` in `LearningAppDetailView`
   - Line 49: Remove/replace `.navigationTitle()` in `RewardAppDetailView`
   - Add `.principal` toolbar items with app icons

**Testing**:
- Verify icon displays correctly at appropriate size
- Test with different app icons (learning and reward apps)
- Verify "Done" button still appears on right
- Test on iOS 15.2+ (icon) and iOS < 15.2 (text fallback)
- Verify icon scales appropriately on different device sizes

### Expected Result

**Before**:
```
[ < Back ]     Unknown App          [ Done ]
```

**After**:
```
[ < Back ]     [App Icon]           [ Done ]
```

Where `[App Icon]` is the actual app icon (e.g., YouTube logo, TikTok logo, etc.)

---

## Implementation Plan: UI Issues 3 & 4

### Phase 1: Fix Challenge Detail View "0 min" Display (Issue 3)

**Priority**: CRITICAL - User cannot see their progress

**Implementation Steps**:

1. **File**: `AppUsageViewModel.swift` (lines ~598-600)

   **Current code**:
   ```swift
   let appUsage = service.getUsage(for: token)
   let totalSeconds = appUsage?.todayUsage ?? 0
   ```

   **Add fallback**:
   ```swift
   let appUsage = service.getUsage(for: token)
   var totalSeconds = appUsage?.todayUsage ?? 0
   var earnedPoints = appUsage?.todayPoints ?? 0

   // Fallback: Read directly from UsagePersistence if primary lookup fails
   if totalSeconds == 0 {
       let tokenHash = service.hashToken(token)
       if let logicalID = service.tokenToLogicalID[tokenHash],
          let persistedApp = service.usagePersistence.app(for: logicalID) {
           totalSeconds = TimeInterval(persistedApp.todaySeconds)
           earnedPoints = persistedApp.todayPoints

           NSLog("[AppUsageViewModel] 🔄 Fallback: Using persisted data for \(persistedApp.displayName) - \(persistedApp.todaySeconds)s, \(persistedApp.todayPoints)pts")
       }
   }
   ```

2. **Apply same pattern** for `RewardAppSnapshot` creation (~line 620)

3. **Add logging** to identify when fallback is triggered

4. **Test**:
   - Create challenge with 10 min target
   - Use learning app for 5 minutes
   - Open child challenge detail view
   - Verify app shows "5 min today" (not "0 min today")

**Follow-up Investigation** (separate task):
- Investigate why `tokenToLogicalID` mapping is missing
- Fix token mapping persistence in `ScreenTimeService.loadPersistedAssignments()`
- Once mapping is reliable, can remove fallback

---

### Phase 2: Replace "Unknown App" Text with Icon (Issue 4)

**Priority**: MEDIUM - Improves UX but not blocking

**Implementation Steps**:

1. **File**: `AppUsageDetailViews.swift`

2. **Update `LearningAppDetailView`** (lines 13-27):

   **Remove**:
   ```swift
   .navigationTitle(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
   ```

   **Add to existing toolbar**:
   ```swift
   .toolbar {
       // App icon in center (principal position)
       ToolbarItem(placement: .principal) {
           if #available(iOS 15.2, *) {
               Label(snapshot.token)
                   .labelStyle(.iconOnly)
                   .scaleEffect(1.5)
                   .frame(width: 40, height: 40)
                   .clipShape(RoundedRectangle(cornerRadius: 10))
           } else {
               // Fallback for iOS < 15.2
               Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                   .font(.headline)
           }
       }

       // Keep existing Done button
       ToolbarItem(placement: .topBarTrailing) {
           Button("Done") { dismiss() }
       }
   }
   ```

3. **Update `RewardAppDetailView`** (lines 44-58):
   - Apply identical changes
   - Replace "Learning App" with "Reward App" in fallback text

4. **Test**:
   - Tap on learning app in challenge detail → Verify icon appears in nav bar
   - Tap on reward app in parent dashboard → Verify icon appears in nav bar
   - Test with multiple different apps
   - Verify "Done" button still works
   - Test on iOS 15.2+ and verify fallback on older versions (simulator)

---

### Testing Checklist (Both Issues)

**Issue 3 - "0 min" Fix**:
- [ ] Challenge shows "20 / 10 min" progress
- [ ] Challenge detail app list shows "20 min today" (not "0 min")
- [ ] Values match between progress card and app list
- [ ] Multiple apps all show correct individual usage
- [ ] Reward apps also show correct usage

**Issue 4 - Icon in Nav Bar**:
- [ ] Learning app detail shows app icon (not text)
- [ ] Reward app detail shows app icon (not text)
- [ ] Icon is recognizable and properly sized
- [ ] "Done" button still appears on right
- [ ] Works on iPhone and iPad
- [ ] Graceful fallback on iOS < 15.2

**Integration**:
- [ ] Tapping app in challenge detail → Opens detail → Shows icon + correct usage
- [ ] Usage times in detail view match the "X min today" shown in list
- [ ] Points earned match usage (todayPoints calculation)

---

## Files to Modify

### Issue 3 (0 min display):
1. `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`
   - Lines ~598-600: Add fallback for `LearningAppSnapshot` creation
   - Lines ~620-622: Add fallback for `RewardAppSnapshot` creation

### Issue 4 (Unknown App → Icon):
2. `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/ParentMode/AppUsageDetailViews.swift`
   - Lines 13-27: Update `LearningAppDetailView` toolbar
   - Lines 44-58: Update `RewardAppDetailView` toolbar

---

## Implementation Order

**Suggested sequence**:
1. **Issue 3 first** (critical user-facing bug)
2. **Test Issue 3** thoroughly
3. **Issue 4 second** (UX improvement)
4. **Final integration test** (both fixes together)

**Estimated effort**:
- Issue 3: 30 minutes (code + test)
- Issue 4: 20 minutes (code + test)
- **Total**: ~1 hour

---

**Last Updated**: 2025-11-17
**Status**: Ready for implementation

