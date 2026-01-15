# UI Polish Workstream

## Plan
- Normalize default points/minute so every new learning or reward app enters the system at 10 pts.
- Simplify the learning and reward tabs by removing per-row controls (delete, lock, toggle, point adjusters) in favor of cleaner summaries.
- Retire the CategoryAssignment modal in favor of auto-applying picker selections with the standardized 10 pts/min rate.
- Polish onboarding flow for clarity, better UX, and stronger value proposition.
- Document the UI changes so future polishing efforts can reference the rationale and affected surfaces.

## Actions (Main App)
- Updated `AppUsageViewModel`, `ScreenTimeService`, and `CategoryAssignmentView` to seed new selections with a 10 pts/min default so snapshots, persistence, and manual assignment all agree.
- Trimmed `LearningTabView` rows down to icon + copy, dropping the delete icon and point stepper while keeping the smaller icon sizing introduced earlier.
- Simplified `RewardsTabView` cards to mirror the learning layout by removing the lock/toggle UI and the point adjuster, including cleanup of unused helpers/styles.
- Disabled the CategoryAssignment sheet hookups in `MainTabView`/`AppUsageView`, then taught `AppUsageViewModel` to auto-assign picker selections (learning/reward) at 10 pts/min and immediately block+monitor without any modal handoff.
- Implemented a shared `TabTopBar` to give the Learning and Reward tabs the same header styling as Settings, removed the Settings "Done" button, and wired every chevron (including the new ones on both challenge tabs) to `SessionManager.exitToSelection()` so parents can jump straight back to the profile selector from any tab.

## Onboarding Polish (Phase 1)

### Issues Identified
1. **Welcome Screen Lacks Impact** - Generic messaging doesn't explain what the app does or hook the parent ✅ FIXED
2. **Device Selection Layout Broken** - "Get Started" button addition broke layout; cards are truncated, requires scrolling ✅ FIXED
3. **Unnecessary Confirmation Dialog** - User already selected and named device, confirmation is redundant ✅ FIXED
4. **Redundant Pro Tips** - Learning/Reward selection screens have redundant tip cards that repeat header info ✅ FIXED
5. **App Display Layout** - 2-column grid wastes space, should match Learning tab's single-row horizontal scroll ✅ FIXED

### Changes Implemented

#### 1. OnboardingFlowView.swift (OnboardingWelcomeStep)
- ✅ Replaced generic copy with strong value proposition
- ✅ New headline: "Turn Screen Time Into Learning Time"
- ✅ Added gradient icon and clear benefit statements
- ✅ Three feature rows explaining smart app management, progress tracking, and secure pairing

#### 2. DeviceSelectionView.swift
- ✅ Removed unnecessary confirmation dialog
- ✅ "Get Started" button now directly proceeds to onboarding
- ✅ Layout already fixed in previous session (wrapped in ScrollView)

#### 3. QuickLearningSetupScreen.swift & QuickRewardSetupScreen.swift
- ✅ Removed tip card sections (redundant with header subtitle)
- ✅ Replaced 2-column LazyVGrid with horizontal ScrollView
- ✅ Matched Learning tab styling: 34pt icon size, 1.35 scale, 12pt font
- ✅ Added "Selected Apps" header with checkmark icon
- ✅ Cards show app icon, name, and "+10 pts/min" with star icon

### Results
- Onboarding flow is now more streamlined with direct navigation
- Visual consistency between onboarding and main app
- Horizontal scrolling provides better space utilization
- Reduced friction by removing unnecessary confirmation step

### Rationale
- First impression matters - welcome screen is the hook
- Reduce friction - every extra tap/confirmation is a conversion killer
- Visual consistency - onboarding should feel like the main app
- Respect screen real estate - horizontal scrolling works better for apps

## Onboarding Polish (Phase 2) - Based on User Feedback

### Issues Identified
1. **Welcome screen starts negatively** - "Lock game and social apps..." is negative framing ✅ FIXED
2. **DeviceSelectionView layout issues** - Wasted blank space at top, unnecessary page indicators ✅ FIXED
3. **Path selection unnecessary** - Remove Quick Start vs Full Setup, keep only full flow ✅ FIXED
4. **App layout misunderstood** - User wanted vertical column, not horizontal scroll ✅ FIXED
5. **Redundant instruction text** - "Pick 3-5 learning apps..." is redundant ✅ FIXED
6. **Grey text usage** - Should use app color scheme instead of generic grey ✅ FIXED

### Changes Implemented

#### 1. OnboardingFlowView.swift (Welcome Screen)
- ✅ Changed messaging to positive framing: "Your child earns screen time by learning. The more they learn, the more they unlock."
- ✅ Updated feature icons and copy to focus on value:
  - "Earn by learning" - Educational apps earn points automatically
  - "Unlock rewards" - Points unlock games and fun apps
  - "Monitor progress" - Track learning time from any device

#### 2. DeviceSelectionView.swift
- ✅ Reduced top padding from 48pt to 16pt (eliminated wasted blank space)
- ✅ Removed page indicator dots above "Get Started" button
- ✅ Maintained ScrollView for proper content display

#### 3. ChildOnboardingCoordinator.swift
- ✅ Removed pathSelection step from enum
- ✅ Changed initial step from .pathSelection to .authorization
- ✅ Removed handlePathSelection, handleAuthorizationComplete, handlePaywallBack functions
- ✅ Simplified flow: Authorization → Learning → Rewards → Challenge Builder → Paywall → Completion

#### 4. QuickLearningSetupScreen.swift
- ✅ Removed instruction card "Pick 3-5 learning apps..."
- ✅ Changed from horizontal scroll to vertical column layout (ScrollView with VStack)
- ✅ Updated empty state to use AppTheme.vibrantTeal instead of grey/secondary
- ✅ Changed checkmark icon color to AppTheme.vibrantTeal
- ✅ Updated app rows with vertical layout matching Learning tab style
- ✅ Used AppTheme.sunnyYellow for points display

#### 5. QuickRewardSetupScreen.swift
- ✅ Removed instruction card "Pick 2-3 fun apps..."
- ✅ Changed from horizontal scroll to vertical column layout
- ✅ Updated empty state to use AppTheme.playfulCoral instead of grey/secondary
- ✅ Changed checkmark icon color to AppTheme.playfulCoral
- ✅ Updated app rows with vertical layout
- ✅ Changed points text from "+10 pts/min" to "Costs 10 pts/min" for clarity

### Technical Details
- App rows use 34pt icons with 1.35 scale matching Learning tab
- Vertical ScrollView with VStack(spacing: 8) for app list
- RoundedRectangle with subtle shadow for each app row
- HStack layout: Icon (34pt) → App name + Points → Spacer

### Files Modified
- OnboardingFlowView.swift
- DeviceSelectionView.swift
- ChildOnboardingCoordinator.swift
- QuickLearningSetupScreen.swift
- QuickRewardSetupScreen.swift

### Files No Longer Used
- OnboardingPathSelectionScreen.swift (can be deleted - no longer referenced)

---

## Time Display Consistency Fix (2025-11-18)

### Issue Description
App usage cards in both Parent Mode and Child Mode displayed time usage inconsistently:
- Different formats across views: "HH:MM:SS" vs "Xh Ym" vs "Xm"
- Poor edge case handling (<1 minute showing as "0m")
- Multiple duplicate format functions (6+ different implementations)
- Confusing user experience with different formats in different screens

### Root Cause
**Multiple disconnected time formatting implementations** scattered across the codebase:

1. **AppUsageViewModel.formatTime()**: Returned "HH:MM:SS" format (e.g., "00:15:30")
2. **CategoryUsageSummary.formattedTime**: Returned "Xh Ym" or "Xm" format (e.g., "15m")
3. **ChildDeviceSummaryCard.formatSeconds()**: Custom implementation with "<1m" handling
4. **RewardsTabView.formatTime()**: Another duplicate implementation
5. **ChildChallengeDetailView.formatTime()**: Yet another duplicate
6. **HistoricalReportsView.formatTime()** (2 instances): Two nearly identical implementations in same file
7. **ChildFullPageView.formattedTime**: Computed property with custom logic

### Solution Implemented

#### 1. Created Unified Time Formatting Utility

**File:** `ScreenTimeRewards/Shared/TimeFormatting.swift` (NEW)

Created a centralized enum with three formatting methods:

```swift
enum TimeFormatting {
    /// Human-readable format: "X hours", "X minutes", "<1 minute", "0 minutes"
    static func formatSeconds(_ seconds: TimeInterval) -> String

    /// Compact format: "Xh Ym", "Xm", "<1m", "0m"
    static func formatSecondsCompact(_ seconds: TimeInterval) -> String

    /// Technical format: "HH:MM:SS"
    static func formatSecondsAsTime(_ seconds: TimeInterval) -> String

    /// Overloads for Int32 and Int types
    static func formatSeconds(_ seconds: Int32) -> String
    static func formatSeconds(_ seconds: Int) -> String
}
```

#### 2. Updated All Models and ViewModels

**CategoryUsageSummary.swift** - Simplified from 4 lines to 1 line
**AppUsageViewModel.swift** - Changed from "HH:MM:SS" to compact format

#### 3. Updated All Views

- ✅ ChildDeviceSummaryCard.swift - Removed local `formatSeconds()` function
- ✅ RewardsTabView.swift - Removed local `formatTime()` function
- ✅ ChildChallengeDetailView.swift - Removed local `formatTime()` function
- ✅ HistoricalReportsView.swift - Removed both duplicate `formatTime()` functions
- ✅ ChildFullPageView.swift - Simplified computed property

### Impact Analysis

**Code Reduction:**
- **Removed:** ~80 lines of duplicate code across 6 different implementations
- **Added:** 1 centralized utility (~100 lines with documentation)
- **Net result:** Centralized, maintainable, consistent implementation

**Consistency Achieved:**
All views now display time consistently:
- **0 seconds:** "0m"
- **30 seconds:** "<1m" (was "0m" before)
- **60 seconds:** "1m"
- **15 minutes:** "15m"
- **90 minutes:** "1h 30m"

**Views Affected:**
- ✅ Child Dashboard (learning and reward app cards)
- ✅ Child Challenge Detail View
- ✅ Rewards Tab View
- ✅ Category Usage Cards (Parent Mode)
- ✅ Child Device Summary Cards (Parent Mode)
- ✅ Child Full Page View (Parent Mode)
- ✅ Historical Reports View (Parent Mode)

### Files Modified

**New Files (1):**
1. `/ScreenTimeRewards/Shared/TimeFormatting.swift` - NEW unified utility

**Modified Files (7):**
1. `/ScreenTimeRewards/Models/CategoryUsageSummary.swift`
2. `/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`
3. `/ScreenTimeRewards/Views/ParentRemote/ChildDeviceSummaryCard.swift`
4. `/ScreenTimeRewards/Views/RewardsTabView.swift`
5. `/ScreenTimeRewards/Views/ChildMode/ChildChallengeDetailView.swift`
6. `/ScreenTimeRewards/Views/ParentRemote/HistoricalReportsView.swift`
7. `/ScreenTimeRewards/Views/ParentRemote/ChildFullPageView.swift`

### Compatibility Notes

**Not Affected by Changes:**
- ✅ **Usage tracking logic** - No changes (UI only)
- ✅ **Data persistence** - No changes
- ✅ **ScreenTimeService** - No changes
- ✅ **UsagePersistence** - No changes
- ✅ **Threshold events** - No changes
- ✅ **Option A implementation** - No changes

**Fully compatible with USAGE_TRACKING_ACCURACY.md fixes**

### Migration Notes

For future development, when adding new views that display time duration:

**Do:**
```swift
Text(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds))
```

**Don't:**
```swift
// Don't create custom formatters!
func formatTime(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    return "\(minutes)m"
}
```

### Build Status

✅ **BUILD SUCCEEDED** (2025-11-18 23:58)

### Summary

**What was fixed:**
- ❌ **Before:** 6+ different time formatting implementations, inconsistent display
- ✅ **After:** 1 unified utility, consistent display across all views

**Benefits:**
1. **Consistency:** All views show time in the same format
2. **Maintainability:** Single source of truth for time formatting
3. **Edge cases:** Proper handling of <1 minute, 0 minutes, etc.
4. **Code quality:** Removed ~80 lines of duplicate code
5. **User experience:** Clear, consistent time display everywhere

---

# UI Data Consistency Fix - Single Source of Truth

**Date:** 2025-11-19  
**Priority:** High (UX Critical)  
**Status:** Analysis Complete, Implementation Pending

---

## Problem Statement

**User Report:** UI cards/views showing inconsistent usage data:
- Some showing 0 minutes
- Different values across different views
- Inconsistent data presentation ruins UX

**Root Cause:** Multiple data sources for usage information across the UI.

---

## Current Data Flow Analysis

### Data Sources Identified

#### ✅ **Source 1: UsagePersistence (CORRECT - Single Source of Truth)**
**Location:** `UsagePersistence.app(for: logicalID).todaySeconds`

**Properties:**
- `todaySeconds: Int` - Today's usage in seconds
- `todayPoints: Int` - Today's earned points
- `totalSeconds: Int` - All-time usage
- `earnedPoints: Int` - All-time points
- `dailyHistory: [DailyUsageSummary]` - Historical data

**Updated by:** ScreenTimeService when threshold events fire  
**Accuracy:** ✅ Direct source from threshold events  
**Persistence:** ✅ Saved to UserDefaults/CoreData immediately

---

####  ❌ **Source 2: AppUsage Computed Properties (INCORRECT - Stale Sessions)**
**Location:** `AppUsage.last24HoursUsage`, `AppUsage.todayUsage`, etc.

**Properties:**
```swift
var todayUsage: TimeInterval {
    // Computes from sessions array
    sessions.filter { ... }.reduce(0) { $0 + $1.duration }
}

var last24HoursUsage: TimeInterval {
    usage(since: Date().addingTimeInterval(-86_400))
}
```

**Updated by:** AppUsage session tracking (old system)  
**Accuracy:** ❌ May be stale, doesn't reflect threshold events  
**Issue:** Sessions array may have mega-sessions or be out of sync

---

### Where Each Source Is Used

| UI Component | Current Data Source | Status | Result |
|--------------|---------------------|--------|--------|
| **LearningTabView** (snapshot cards) | `UsagePersistence.todaySeconds` | ✅ CORRECT | Shows accurate data |
| **RewardsTabView** (snapshot cards) | `UsagePersistence.todaySeconds` | ✅ CORRECT | Shows accurate data |
| **LearningAppDetailView** (Daily pill) | `AppUsage.last24HoursUsage` | ❌ WRONG | May show 0 or wrong value |
| **RewardAppDetailView** (Daily pill) | `AppUsage.last24HoursUsage` | ❌ WRONG | May show 0 or wrong value |
| **Detail View - Weekly pill** | `AppUsage.weeklyUsage()` | ❌ WRONG | Computed from dailyHistory |
| **Detail View - Monthly pill** | `AppUsage.monthlyUsage()` | ❌ WRONG | Computed from dailyHistory |
| **Detail View - Insights** | `AppUsage` computed properties | ❌ WRONG | Session-based calculations |
| **ChildDashboardView** (points) | `viewModel.learningRewardPoints` | ✅ CORRECT | Aggregated from snapshots |

---

## The Discrepancy Explained

### Snapshot Creation (✅ CORRECT)
**File:** `AppUsageViewModel.swift:613-616`

```swift
if let persistedApp = service.usagePersistence.app(for: logicalID) {
    totalSeconds = TimeInterval(persistedApp.todaySeconds)  // ✅ Direct from persistence
    earnedPoints = persistedApp.todayPoints
}
```

**Result:** Snapshots show **accurate** usage data from threshold events.

---

### Detail View Data Loading (❌ WRONG)
**File:** `AppUsageDetailViews.swift:45-46, 92-93`

```swift
.onAppear {
    usage = service.getUsage(for: snapshot.token)  // ❌ Returns AppUsage model
    history = service.getDailyHistory(for: snapshot.token)
}
```

Then displays:
```swift
UsagePill(
    title: "Daily",
    minutes: minutesText(for: usage?.last24HoursUsage ?? 0),  // ❌ Computed from sessions
    ...
)
```

**Result:** Detail views show **stale** or **zero** usage because `AppUsage.last24HoursUsage` computes from old sessions array instead of `todaySeconds`.

---

## Identified Issues

### Issue 1: Detail Views Show 0 Minutes
**Why:** `AppUsage.last24HoursUsage` computes from `sessions` array which may be empty or not updated

**Example:**
```
Snapshot shows: 4260 seconds (71 minutes) ✅
Detail view shows: 0 minutes ❌

Reason: AppUsage.sessions is empty but UsagePersistence.todaySeconds = 4260
```

---

### Issue 2: Inconsistent Values Across Views
**Why:** Tab view pulls from persistence, detail view pulls from computed properties

**Example:**
```
Learning Tab: "71 minutes" (from UsagePersistence.todaySeconds)
Detail View Daily: "0 minutes" (from AppUsage.last24HoursUsage)
```

---

### Issue 3: Weekly/Monthly May Be Wrong
**Why:** Computed from `dailyHistory` via AppUsage methods instead of direct persistence

**Code:**
```swift
let weeklyUsage = usage?.weeklyUsage(dailyHistory: dailyHistory) ?? 0
```

**Should be:**
```swift
// Calculate directly from dailyHistory (which comes from persistence)
let weeklyUsage = calculateWeeklyUsage(from: dailyHistory)
```

---

## Solution: Single Source of Truth

### Core Principle
**ALL UI components must pull usage data from `UsagePersistence` only.**

Never use:
- ❌ `AppUsage.todayUsage`
- ❌ `AppUsage.last24HoursUsage`
- ❌ `AppUsage.weeklyUsage()`
- ❌ `AppUsage.monthlyUsage()`

Always use:
- ✅ `UsagePersistence.app(for:).todaySeconds`
- ✅ `UsagePersistence.app(for:).todayPoints`
- ✅ `UsagePersistence.app(for:).dailyHistory`

---

## Implementation Plan

### Phase 1: Fix Detail Views (HIGHEST PRIORITY)

**File:** `AppUsageDetailViews.swift`

#### Step 1.1: Update State Variables
```swift
// BEFORE:
@State private var usage: AppUsage?

// AFTER:
@State private var persistedUsage: UsagePersistence.AppUsageData?
```

#### Step 1.2: Load from Persistence Directly
```swift
// BEFORE:
.onAppear {
    usage = service.getUsage(for: snapshot.token)
    history = service.getDailyHistory(for: snapshot.token)
}

// AFTER:
.onAppear {
    let tokenHash = service.usagePersistence.tokenHash(for: snapshot.token)
    if let logicalID = service.usagePersistence.logicalID(for: tokenHash) {
        persistedUsage = service.usagePersistence.app(for: logicalID)
        history = persistedUsage?.dailyHistory ?? []
    }
}
```

#### Step 1.3: Fix Daily Pill
```swift
// BEFORE:
UsagePill(
    title: "Daily",
    minutes: minutesText(for: usage?.last24HoursUsage ?? 0),  // ❌
    annotation: "\(pointsEarned(for: usage?.last24HoursUsage ?? 0)) pts",
    accent: accentColor
)

// AFTER:
UsagePill(
    title: "Daily",
    minutes: minutesText(for: TimeInterval(persistedUsage?.todaySeconds ?? 0)),  // ✅
    annotation: "\(persistedUsage?.todayPoints ?? 0) pts",  // ✅ Direct value
    accent: accentColor
)
```

#### Step 1.4: Add Weekly/Monthly Helpers
```swift
private func calculateWeeklyUsage(from history: [UsagePersistence.DailyUsageSummary]) -> TimeInterval {
    let calendar = Calendar.current
    let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

    return TimeInterval(history
        .filter { $0.date >= sevenDaysAgo }
        .reduce(0) { $0 + $1.seconds })
}

private func calculateMonthlyUsage(from history: [UsagePersistence.DailyUsageSummary]) -> TimeInterval {
    let calendar = Calendar.current
    let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!

    return TimeInterval(history
        .filter { $0.date >= thirtyDaysAgo }
        .reduce(0) { $0 + $1.seconds })
}
```

#### Step 1.5: Update Weekly/Monthly Pills
```swift
// BEFORE:
let weeklyUsage = usage?.weeklyUsage(dailyHistory: dailyHistory) ?? 0
let monthlyUsage = usage?.monthlyUsage(dailyHistory: dailyHistory) ?? 0

// AFTER:
let weeklyUsage = calculateWeeklyUsage(from: history)
let monthlyUsage = calculateMonthlyUsage(from: history)
```

#### Step 1.6: Simplify Insights Section
Since we no longer have AppUsage with session data, update insights to show only what's available from persistence:

```swift
// KEEP: These use persisted data
insightRow(
    icon: "star.circle.fill",
    title: "Total Points",
    value: "\(persistedUsage?.earnedPoints ?? 0) pts"  // ✅ From persistence
)

insightRow(
    icon: "clock.fill",
    title: "Total Time",
    value: TimeFormatting.formatSecondsCompact(persistedUsage?.totalSeconds ?? 0)  // ✅ From persistence
)

insightRow(
    icon: "calendar",
    title: "First Used",
    value: persistedUsage?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "No data"  // ✅ From persistence
)

// REMOVE: These computed from sessions (not available)
// - Average Session
// - Longest Session
// - Sessions Today Count
```

---

### Phase 2: Verify Snapshot Consistency

**File:** `AppUsageViewModel.swift:613-616`

**Status:** ✅ Already correct - no changes needed

---

### Phase 3: Audit All Other Views

Search for any AppUsage usage in these files:

```bash
# Find all files using AppUsage computed properties
grep -r "\.todayUsage\|\.last24HoursUsage\|\.weeklyUsage\|\.monthlyUsage" \
  ScreenTimeRewardsProject/ScreenTimeRewards/Views/
```

**Files to check:**
1. ✅ `ChildDashboardView.swift` - Uses snapshots (correct)
2. ⚠️ `ParentDashboardView.swift` - Need to audit
3. ⚠️ `CategoryDetailView.swift` - Need to audit
4. ⚠️ `ChildDeviceSummaryCard.swift` - Need to audit
5. ⚠️ `AppUsageView.swift` - Need to audit

---

### Phase 4: Deprecate Old Properties (Optional)

**File:** `AppUsage.swift`

```swift
@available(*, deprecated, message: "Use UsagePersistence.app(for:).todaySeconds instead")
var todayUsage: TimeInterval {
    ...
}

@available(*, deprecated, message: "Use UsagePersistence.app(for:).todaySeconds instead")
var last24HoursUsage: TimeInterval {
    ...
}
```

---

## Expected Results

### Before Fix
```
Learning Tab:
  Unknown App 1: 71 minutes ✅

Detail View (click app):
  Daily: 0 minutes ❌
  Weekly: 0 minutes ❌
  Points Today: 0 pts ❌
```

### After Fix
```
Learning Tab:
  Unknown App 1: 71 minutes ✅

Detail View (click app):
  Daily: 71 minutes ✅
  Weekly: 142 minutes ✅
  Points Today: 710 pts ✅
```

---

## Testing Checklist

- [ ] Learning tab shows usage (e.g., 71 minutes)
- [ ] Click app → Detail view shows SAME usage (71 minutes)
- [ ] Daily pill matches tab view
- [ ] Weekly/Monthly values are non-zero
- [ ] Points match across all views
- [ ] Reward apps show consistent data
- [ ] No "0 minutes" when usage exists
- [ ] Pull-to-refresh updates all views

---

## Success Metrics

| Metric | Before | After |
|--------|--------|-------|
| Data sources | 2 | 1 |
| Consistency | 0% | 100% |
| Zero-value bugs | Frequent | None |
| User trust | Low | High |

---

## Priority

**HIGH** - This directly affects user trust in tracking accuracy.

**Estimated Time:** 2-3 hours for complete fix.

**Next Steps:**
1. Review this plan ✅
2. Implement Phase 1 (Fix Detail Views)
3. Test thoroughly
4. Audit other views (Phase 3)
5. Deploy


---

## Child Mode UI Data Consistency Fix (2025-11-19)

### Issues Identified

**Problem:** Child Mode shows 0 minutes in multiple views despite challenge progress showing 70 minutes.

**Affected Views:**
1. Quest Central → "Today's Progress" → Learning Goal: **0/10m** ❌ (should be 70/10m)
2. Quest Central → "Today's Progress" → Reward Earned: **0/10m** ❌  
3. Challenge Detail → "Learning Apps" → YouTube: **0m today** ❌ (should be 70m)
4. Challenge Detail → "Your Progress": **700% (70/10m)** ✅ CORRECT

**Observation:** Challenge progress is correct (70 minutes), but individual app usage shows 0.

### Root Cause Analysis

**Investigation Steps:**
1. ✅ Checked AppUsageDetailViews.swift - Already using UsagePersistence (fixed in Phase 1)
2. ✅ Checked AppUsageViewModel.swift lines 606-616 - Snapshots ARE reading from `persistedApp.todaySeconds`
3. ✅ Checked ChildChallengesTabView.swift lines 274-289 - Progress circles sum `snapshot.totalSeconds`  
4. ✅ Checked ChildChallengeDetailView.swift line 234 - App rows show `snapshot.totalSeconds`
5. ❌ **FOUND BUG:** ScreenTimeService.swift lines 1605-1617

**The Bug:**

```swift
// In ScreenTimeService.recordUsage() - Lines 1605-1617
let persistedApp = UsagePersistence.PersistedApp(
    logicalID: logicalID,
    displayName: appUsage.appName,
    category: appUsage.category.rawValue,
    rewardPoints: appUsage.rewardPoints,
    totalSeconds: Int(appUsage.totalTime),  // ✅ All-time total
    earnedPoints: appUsage.earnedRewardPoints,  // ✅ All-time total
    createdAt: appUsage.firstAccess,
    lastUpdated: appUsage.lastAccess
    // ❌ BUG: todaySeconds NOT PASSED - defaults to 0!
    // ❌ BUG: todayPoints NOT PASSED - defaults to 0!
)
usagePersistence.saveApp(persistedApp)
```

**PersistedApp Initializer (UsagePersistence.swift:66-90):**
```swift
init(logicalID: LogicalAppID,
     displayName: String,
     category: String,
     rewardPoints: Int,
     totalSeconds: Int,
     earnedPoints: Int,
     createdAt: Date,
     lastUpdated: Date,
     todaySeconds: Int = 0,  // ⚠️ Defaults to 0
     todayPoints: Int = 0,  // ⚠️ Defaults to 0
     lastResetDate: Date? = nil,
     dailyHistory: [DailyUsageSummary] = [])
```

**Impact:**
- Threshold events fire every minute ✅
- `recordUsage()` updates `totalSeconds` (all-time) ✅
- `recordUsage()` updates `earnedPoints` (all-time) ✅
- `recordUsage()` does NOT update `todaySeconds` ❌
- `recordUsage()` does NOT update `todayPoints` ❌
- UsagePersistence saves with `todaySeconds=0, todayPoints=0` ❌
- UI reads from `todaySeconds` and shows **0 minutes** ❌
- Challenge progress reads from CoreData (separate system) and shows **70 minutes** ✅

**Why Challenge Progress Works:**
- Challenge progress is stored in CoreData (`ChallengeProgress` entity)
- Updated separately in `ScreenTimeService` (different code path)
- Not affected by UsagePersistence bug

### Fix Plan

**Strategy:** Make `recordUsage()` properly update today's values in UsagePersistence.

**Implementation:**

1. **Modify ScreenTimeService.swift lines 1605-1617:**
   - Load existing PersistedApp (if it exists)
   - Calculate today's new values by adding duration
   - Pass `todaySeconds` and `todayPoints` to PersistedApp init
   - Save updated PersistedApp

**Code Changes Needed:**

```swift
// Before (lines 1605-1617):
let persistedApp = UsagePersistence.PersistedApp(
    logicalID: logicalID,
    displayName: appUsage.appName,
    category: appUsage.category.rawValue,
    rewardPoints: appUsage.rewardPoints,
    totalSeconds: Int(appUsage.totalTime),
    earnedPoints: appUsage.earnedRewardPoints,
    createdAt: appUsage.firstAccess,
    lastUpdated: appUsage.lastAccess
)
usagePersistence.saveApp(persistedApp)

// After (with fix):
// Load existing persisted data (if any)
let existingApp = usagePersistence.app(for: logicalID)

// Calculate today's incremental values
let newTodaySeconds: Int
let newTodayPoints: Int

if let existing = existingApp {
    // Add to existing today's values
    newTodaySeconds = existing.todaySeconds + Int(duration)
    newTodayPoints = existing.todayPoints + (Int(duration) / 60 * appUsage.rewardPoints)
} else {
    // First recording today
    newTodaySeconds = Int(duration)
    newTodayPoints = Int(duration) / 60 * appUsage.rewardPoints
}

let persistedApp = UsagePersistence.PersistedApp(
    logicalID: logicalID,
    displayName: appUsage.appName,
    category: appUsage.category.rawValue,
    rewardPoints: appUsage.rewardPoints,
    totalSeconds: Int(appUsage.totalTime),
    earnedPoints: appUsage.earnedRewardPoints,
    createdAt: appUsage.firstAccess,
    lastUpdated: appUsage.lastAccess,
    todaySeconds: newTodaySeconds,  // ✅ NOW UPDATED!
    todayPoints: newTodayPoints,  // ✅ NOW UPDATED!
    lastResetDate: existingApp?.lastResetDate,
    dailyHistory: existingApp?.dailyHistory ?? []
)
usagePersistence.saveApp(persistedApp)
```

**Testing Checklist:**
- [ ] Use learning app for 5 minutes
- [ ] Check Quest Central → Today's Progress → Learning Goal shows 5m (not 0m)
- [ ] Check Challenge Detail → Learning Apps → shows 5m (not 0m)
- [ ] Use learning app for another 5 minutes
- [ ] Verify values increment to 10m
- [ ] Verify challenge progress also shows 10m (consistency check)

**Expected Results:**
- Quest Central "Learning Goal" shows actual usage ✅
- Quest Central "Reward Earned" shows actual reward time ✅
- Challenge Detail "Learning Apps" shows actual usage per app ✅
- All values match challenge progress ✅

---

## Daily Usage Persistence Fix (2025-11-19)

### Problem Discovered

**Issue:** Usage data would reset to 0 on every app restart, despite logs showing data persisted.

**User Report:**
> "the circle on the dashboard reverted to 0 minutes again. the usage time in 'Your Rewards' card shows 0 minutes as well. The log however is still showing 2 minutes usage of the reward app!"

**Logs Showed:**
```
[ScreenTimeService]   - Unknown App 0 (Reward):
[ScreenTimeService]       Total: 120.0s, 20pts
[ScreenTimeService]       Today: 0s, 0pts ← Used by snapshots
```

**Analysis:** `totalSeconds` persisted correctly (120s), but `todaySeconds` was always 0 after app restart.

---

### Root Cause: Missing Field Preservation

**ScreenTimeService.swift** had **3 locations** where it created `PersistedApp` instances without preserving daily tracking fields.

#### Location 1: `configureMonitoring()` (Line 608)
**When:** Called every time the app launches to reconfigure Screen Time monitoring

**Bug:**
```swift
// BEFORE (Missing todaySeconds preservation):
let existingApp = usagePersistence.app(for: logicalID)
let persistedApp = UsagePersistence.PersistedApp(
    logicalID: logicalID,
    displayName: displayName,
    category: category.rawValue,
    rewardPoints: points,
    totalSeconds: existingApp?.totalSeconds ?? 0,  // ✅ Preserved
    earnedPoints: existingApp?.earnedPoints ?? 0,  // ✅ Preserved
    createdAt: existingApp?.createdAt ?? now,
    lastUpdated: existingApp?.lastUpdated ?? now
    // todaySeconds NOT passed!  ❌ Defaults to 0
    // todayPoints NOT passed!   ❌ Defaults to 0
    // lastResetDate NOT passed! ❌ Defaults to nil
    // dailyHistory NOT passed!  ❌ Defaults to []
)
usagePersistence.saveApp(persistedApp)
```

**Impact:** Every app launch overwrote `todaySeconds` with 0, causing UI to show no usage.

**Fix Applied:**
```swift
let persistedApp = UsagePersistence.PersistedApp(
    logicalID: logicalID,
    displayName: displayName,
    category: category.rawValue,
    rewardPoints: points,
    totalSeconds: existingApp?.totalSeconds ?? 0,
    earnedPoints: existingApp?.earnedPoints ?? 0,
    createdAt: existingApp?.createdAt ?? now,
    lastUpdated: existingApp?.lastUpdated ?? now,
    todaySeconds: existingApp?.todaySeconds ?? 0,      // ✅ NOW PRESERVED
    todayPoints: existingApp?.todayPoints ?? 0,        // ✅ NOW PRESERVED
    lastResetDate: existingApp?.lastResetDate,         // ✅ NOW PRESERVED
    dailyHistory: existingApp?.dailyHistory ?? []      // ✅ NOW PRESERVED
)
```

**Debug Logging Added:**
```swift
print("[ScreenTimeService]   💾 Updated app configuration (preserved total: \(existingApp.totalSeconds)s, \(existingApp.earnedPoints)pts, today: \(existingApp.todaySeconds)s, \(existingApp.todayPoints)pts)")
```

#### Location 2: Internal `recordUsage()` (Line 1660)
**When:** Called from threshold event handler
**Status:** ✅ Already correct from previous fixes (lines 1669-1672 pass todaySeconds/todayPoints)

#### Location 3: Public `recordUsage()` (Line 2255)
**When:** Alternative entry point for recording usage
**Bug:** Same as Location 1 - missing field preservation

**Fix Applied:**
```swift
// Persist to shared storage immediately
if let appUsage = appUsages[logicalID] {
    let existingApp = usagePersistence.app(for: logicalID)  // ✅ Load existing
    let persistedApp = UsagePersistence.PersistedApp(
        logicalID: logicalID,
        displayName: appUsage.appName,
        category: appUsage.category.rawValue,
        rewardPoints: appUsage.rewardPoints,
        totalSeconds: Int(appUsage.totalTime),
        earnedPoints: appUsage.earnedRewardPoints,
        createdAt: appUsage.firstAccess,
        lastUpdated: appUsage.lastAccess,
        todaySeconds: existingApp?.todaySeconds ?? 0,      // ✅ NOW PRESERVED
        todayPoints: existingApp?.todayPoints ?? 0,        // ✅ NOW PRESERVED
        lastResetDate: existingApp?.lastResetDate,         // ✅ NOW PRESERVED
        dailyHistory: existingApp?.dailyHistory ?? []      // ✅ NOW PRESERVED
    )
    usagePersistence.saveApp(persistedApp)
}
```

---

### Data Architecture Clarification

#### Total vs Daily Usage

| Field | Purpose | Resets? | Use Case |
|-------|---------|---------|----------|
| `totalSeconds` | Lifetime cumulative usage | **Never** | Historical stats, all-time progress |
| `todaySeconds` | Current day usage only | **At midnight** | **Daily challenges, Child Mode UI** |
| `earnedPoints` | Lifetime points | **Never** | All-time achievements |
| `todayPoints` | Current day points | **At midnight** | **Today's progress** |
| `dailyHistory` | Archive of past 30 days | Keeps 30 days | Weekly/monthly reports |
| `lastResetDate` | When daily counters last reset | Updated at midnight | Determines when to reset |

**Example Timeline:**
```
Day 1 (11/19): Child uses reward app 2 minutes
  → totalSeconds = 120s
  → todaySeconds = 120s
  → todayPoints = 20pts

App Restart (same day):
  → totalSeconds = 120s (preserved)
  → todaySeconds = 120s (NOW PRESERVED - was 0 before fix)
  → todayPoints = 20pts (NOW PRESERVED - was 0 before fix)

Midnight (11/20):
  → dailyHistory[11/19] = {seconds: 120, points: 20} (archived)
  → todaySeconds = 0s (reset by daily logic)
  → todayPoints = 0pts (reset by daily logic)
  → totalSeconds = 120s (preserved)

Day 2 (11/20): Child uses reward app 1 minute
  → totalSeconds = 180s (120 + 60)
  → todaySeconds = 60s
  → todayPoints = 10pts
```

---

### UI Data Flow

All Child Mode UI components read from `todaySeconds`:

```
1. Threshold event fires (e.g., 1 minute of usage)
   ↓
2. ScreenTimeService.handleEventThresholdReached()
   ↓
3. recordUsage() updates UsagePersistence
   - todaySeconds += 60
   - todayPoints += 10
   ↓
4. AppUsageViewModel.buildSnapshots()
   - Reads persistedApp.todaySeconds
   - Creates snapshots with this value
   ↓
5. UI displays snapshot data
   - Quest Central circles
   - Challenge Detail cards
   - "Your Rewards" summary
```

**Note:** Variable naming is misleading - `snapshot.totalSeconds` actually contains `todaySeconds` from persistence.

---

### Testing Results

#### Before Fix
```
Launch app:
[ScreenTimeService]   - Unknown App 0:
[ScreenTimeService]       Total: 120.0s, 20pts
[ScreenTimeService]       Today: 0s, 0pts ← BUG

UI Display:
- Quest Central "Reward Earned": 0/74m ❌
- Challenge Detail "Your Rewards": 0m used ❌
```

#### After Fix
```
Launch app:
[ScreenTimeService]   💾 Updated app configuration (preserved total: 120s, 20pts, today: 120s, 20pts)

UI Display:
- Quest Central "Reward Earned": 2/74m ✅
- Challenge Detail "Your Rewards": 2m used of 74m unlocked ✅

User Confirmation:
> "the today usage persisted this time. I think it's fixed."
```

#### Persistence Across Restart
```
Test Flow:
1. Use reward app for 1 minute
2. Check UI shows 1m ✅
3. Close app completely
4. Relaunch app
5. Check UI STILL shows 1m ✅ (was 0m before)

Logs confirm preservation:
[ScreenTimeService]   💾 Updated app configuration (preserved total: 60s, 10pts, today: 60s, 10pts)
```

---

### Files Modified

**ScreenTimeRewards/Services/ScreenTimeService.swift**
- Lines 608-621: Added preservation in `configureMonitoring()`
- Line 626: Updated debug log to show today values
- Lines 2254-2269: Added preservation in public `recordUsage()`
- Lines 284-295: Added diagnostic logging at app launch

**Changes:**
```diff
+ todaySeconds: existingApp?.todaySeconds ?? 0,
+ todayPoints: existingApp?.todayPoints ?? 0,
+ lastResetDate: existingApp?.lastResetDate,
+ dailyHistory: existingApp?.dailyHistory ?? []
```

---

### Daily Reset Mechanism (Working Correctly)

**UsagePersistence.swift** handles midnight transitions properly:

1. **Notification-based Reset:**
   - `NSCalendarDayChanged` triggers `AppDelegate.setupMidnightResetObserver()`
   - Calls `ScreenTimeService.handleMidnightTransition()`
   - Calls `UsagePersistence.resetDailyCounters()`

2. **Archive Before Reset:**
   ```swift
   if app.todaySeconds > 0 || app.todayPoints > 0 {
       let summary = DailyUsageSummary(date: previousDay,
                                      seconds: app.todaySeconds,
                                      points: app.todayPoints)
       app.dailyHistory.append(summary)
   }
   ```

3. **Reset Counters:**
   ```swift
   app.todaySeconds = 0
   app.todayPoints = 0
   app.lastResetDate = today
   ```

4. **Inline Reset Check:**
   - `UsagePersistence.recordUsage()` checks if `lastResetDate` is from previous day
   - Archives and resets automatically if needed
   - Ensures data integrity even if notification missed

---

### Key Insights

1. **Preserve vs Reset:** Critical distinction
   - **Preserve:** On app launch (same day)
   - **Reset:** At midnight transition (new day)

2. **Multiple Entry Points:** All `PersistedApp` creation locations must preserve fields:
   - ✅ `configureMonitoring()` - App launch
   - ✅ `recordUsage()` (internal) - Threshold events
   - ✅ `recordUsage()` (public) - Manual recording

3. **Data Consistency:** All views now show same data:
   - Quest Central circles → `todaySeconds`
   - Challenge Detail cards → `todaySeconds`
   - Challenge Progress → Aggregates `todaySeconds` via CoreData

4. **Variable Naming Confusion:**
   - `AppUsageViewModel` uses local var named `totalSeconds`
   - But it actually reads from `persistedApp.todaySeconds`
   - Could be refactored for clarity (optional)

---

### Completed Fixes Summary

| View | Card/Component | Data Source | Status |
|------|----------------|-------------|--------|
| **Quest Central** | Learning Goal circle | `ChallengeProgress.currentValue` (from todaySeconds) | ✅ Fixed |
| **Quest Central** | Reward Earned circle | `rewardSnapshots.totalSeconds` (from todaySeconds) | ✅ Fixed |
| **Challenge Detail** | Your Progress | `ChallengeProgress.currentValue` | ✅ Always worked |
| **Challenge Detail** | Learning Apps total | `ChallengeProgress.currentValue` | ✅ Fixed |
| **Challenge Detail** | Learning Apps per-app | `learningSnapshots.totalSeconds` (todaySeconds) | ✅ Fixed |
| **Challenge Detail** | Your Rewards total | `rewardSnapshots.totalSeconds` (todaySeconds) | ✅ Fixed |
| **Challenge Detail** | Your Rewards per-app | `rewardSnapshots.totalSeconds` (todaySeconds) | ✅ Fixed |

**All Child Mode UI:** ✅ Shows correct, consistent usage data
**Daily Usage Persistence:** ✅ Persists across app restarts
**Midnight Reset:** ✅ Correctly archives and resets
**Data Integrity:** ✅ Single source of truth maintained

---

**Fix Complete:** 2025-11-19
**Build Status:** ✅ BUILD SUCCEEDED
**User Confirmation:** ✅ "the today usage persisted this time. I think it's fixed."

