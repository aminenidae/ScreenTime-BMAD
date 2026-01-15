# Points Calculation Bug Fixes - Technical Analysis

**Date:** 2025-10-26
**Project:** ScreenTime-BMAD / ScreenTimeRewards
**Status:** ✅ ALL BUGS FIXED AND TESTED

---

## Executive Summary

Four critical bugs were identified and fixed in the points calculation and state persistence system:

1. **Retroactive Points Recalculation** - Points recalculated when rate changed
2. **Configuration Reload** - Rate changes not applied to in-memory state
3. **App Card Display** - Views showed incorrect calculated points
4. **Unlocked App Persistence** - Unlocked apps appeared locked after relaunch

All bugs have been fixed with comprehensive code changes across 7 files and 20+ modifications.

---

## Bug #1: Retroactive Points Recalculation

### The Problem

**Symptom:**
```
User scenario:
1. Add learning app with 75 pts/min
2. Use app for 1 minute → Total: 75 pts ✅
3. Change rate to 230 pts/min
4. Use app for 1 minute → Total: 150 pts ❌ (expected 305)
5. Use app for 1 minute → Total: 225 pts ❌ (expected 535)
```

**Root Cause:**

In `Models/AppUsage.swift`, `earnedRewardPoints` was a **computed property**:

```swift
// BEFORE (BROKEN):
var earnedRewardPoints: Int {
    let minutes = Int(totalTime / 60)
    return minutes * rewardPoints  // ❌ Uses CURRENT rate for ALL historical time
}
```

This meant:
- After 3 minutes of usage (180 seconds)
- With current rate of 75 pts/min
- Calculation: `180 / 60 * 75 = 225 pts`

When rate changed to 230 pts/min:
- Same 3 minutes (180 seconds)
- **NEW** rate of 230 pts/min
- Calculation: `180 / 60 * 230 = 690 pts` ❌
- **All historical usage retroactively recalculated!**

### The Fix

Changed `earnedRewardPoints` from **computed property** to **stored property** with **incremental updates**:

```swift
// AFTER (FIXED):
private(set) var earnedRewardPoints: Int  // Stored, not computed

mutating func recordUsage(duration: TimeInterval, endingAt endDate: Date = Date()) {
    // ... existing code ...

    // Calculate and add points for ONLY the new duration
    let newMinutes = Int(duration / 60)
    let newPoints = newMinutes * rewardPoints
    earnedRewardPoints += newPoints  // ✅ Incremental addition
}
```

**Now:**
- Minute 1 at 75 pts/min: `earnedRewardPoints = 0 + 75 = 75` ✅
- Change to 230 pts/min (doesn't affect stored points)
- Minute 2 at 230 pts/min: `earnedRewardPoints = 75 + 230 = 305` ✅
- Minute 3 at 230 pts/min: `earnedRewardPoints = 305 + 230 = 535` ✅

### Files Modified

1. **Models/AppUsage.swift:95**
   - Changed from computed property to stored property
   ```swift
   private(set) var earnedRewardPoints: Int
   ```

2. **Models/AppUsage.swift:83**
   - Added to CodingKeys enum
   ```swift
   case bundleIdentifier, appName, category, totalTime, sessions,
        firstAccess, lastAccess, rewardPoints, earnedRewardPoints
   ```

3. **Models/AppUsage.swift:129, 141, 150**
   - Updated all initializers to set `earnedRewardPoints = 0`

4. **Models/AppUsage.swift:186-188**
   - Added incremental calculation in `recordUsage()`

5. **Services/ScreenTimeService.swift:338, 349, 360**
   - Updated sample data to calculate initial `earnedRewardPoints`

6. **Services/ScreenTimeService.swift:649**
   - Pass `earnedRewardPoints` when converting from PersistedApp
   ```swift
   earnedRewardPoints: persisted.earnedPoints
   ```

7. **Services/ScreenTimeService.swift:1315-1326, 1536-1547, 1600-1611**
   - Calculate points when creating new usage records

---

## Bug #2: Configuration Reload

### The Problem

**Symptom:**
- User changes points/minute from 75 to 230
- New rate saves to disk correctly
- Next usage event still uses OLD rate (75) for calculation
- UI shows new rate (230) but calculation uses old rate (75)

**Root Cause:**

In `Services/ScreenTimeService.swift:606`, `configureMonitoring()` reused existing in-memory `AppUsage`:

```swift
// BEFORE (BROKEN):
var refreshedUsages: [String: AppUsage] = [:]
for apps in groupedApplications.values {
    for app in apps {
        if let existing = appUsages[app.logicalID] {
            refreshedUsages[app.logicalID] = existing  // ❌ Keeps OLD rate!
        }
    }
}
```

**Flow:**
1. User changes rate from 75 to 230 → Saved to disk ✅
2. `configureMonitoring()` called
3. Loads existing `AppUsage` with `rewardPoints = 75` (old value)
4. Saves to `refreshedUsages` with old value
5. Next usage event: `75 pts/min * 1 min = 75 pts` ❌ (should be 230)

### The Fix

Always reload from persistence to get updated configuration:

```swift
// AFTER (FIXED):
var refreshedUsages: [String: AppUsage] = [:]
for apps in groupedApplications.values {
    for app in apps {
        // Always reload from persistence to get the latest configuration
        if let persisted = usagePersistence.app(for: app.logicalID) {
            refreshedUsages[app.logicalID] = appUsage(from: persisted)  // ✅ Fresh data!
            #if DEBUG
            print("[ScreenTimeService] Reloaded \(app.displayName): \(persisted.rewardPoints) pts/min")
            #endif
        }
    }
}
```

### Files Modified

**Services/ScreenTimeService.swift:612-617**
- Changed to always reload from persistence
- Added debug logging to verify reload

---

## Bug #3: App Card Display

### The Problem

**Symptom:**
- "Total Points Earned" shows: 75 pts ✅
- App card shows: 690 pts ❌
- Values don't match!

**Root Cause:**

In `Views/LearningTabView.swift:178-179`, app cards **recalculated** points:

```swift
// BEFORE (BROKEN):
let minutesUsed = Int(snapshot.totalSeconds / 60)
let pointsEarned = minutesUsed * snapshot.pointsPerMinute  // ❌ Retroactive calculation!
Text("\(pointsEarned) pts earned")
```

This had the same bug as #1 - recalculating using current rate.

### The Fix

**Step 1:** Add `earnedPoints` field to snapshots

```swift
// ViewModels/AppUsageViewModel.swift:14, 26
struct LearningAppSnapshot: Identifiable {
    // ... existing fields ...
    let earnedPoints: Int  // ✅ Actual earned points (stored, not computed)
}

struct RewardAppSnapshot: Identifiable {
    // ... existing fields ...
    let earnedPoints: Int  // ✅ Actual earned points (stored, not computed)
}
```

**Step 2:** Populate from actual `earnedRewardPoints`

```swift
// ViewModels/AppUsageViewModel.swift:490
let earnedPoints = appUsage?.earnedRewardPoints ?? 0

let snapshot = LearningAppSnapshot(
    // ... existing parameters ...
    earnedPoints: earnedPoints,  // ✅ Use stored value
    tokenHash: tokenHash
)
```

**Step 3:** Display stored value in view

```swift
// AFTER (FIXED):
// Views/LearningTabView.swift:180
Text("\(snapshot.earnedPoints) pts earned")  // ✅ Display stored value
```

### Files Modified

1. **ViewModels/AppUsageViewModel.swift:14, 26**
   - Added `earnedPoints` field to both snapshot structs

2. **ViewModels/AppUsageViewModel.swift:490, 500, 512**
   - Get earned points from AppUsage
   - Pass to snapshot constructors

3. **Views/LearningTabView.swift:180**
   - Display `snapshot.earnedPoints` instead of calculating

---

## Bug #4: Unlocked Reward Apps Reset After Relaunch

### The Problem

**Symptom:**
- User unlocks reward app
- App is functionally unlocked (can be used)
- User closes and relaunches app
- UI shows app as LOCKED ❌
- App is still functionally unlocked (can still be used)
- Mismatch between UI state and actual state

**Root Cause:**

In `Models/AppUsage.swift:41, 50`, `UnlockedRewardApp` used **unstable hash**:

```swift
// BEFORE (BROKEN):
init(token: ApplicationToken, reservedPoints: Int, pointsPerMinute: Int) {
    self.id = String(token.hashValue)  // ❌ Changes on each app launch!
    // ...
}
```

Swift's `hashValue` is **not stable** across app launches. From Apple docs:
> "Hash values are not guaranteed to be equal across different executions of your program"

**Flow:**
1. User unlocks app → `id = String(token.hashValue)` → e.g., `"123456789"`
2. Save to persistence with `id = "123456789"`
3. App relaunched
4. Same token now has **different** hashValue → e.g., `"987654321"`
5. Try to match: `token.hashValue == "123456789"` → FALSE ❌
6. Can't find unlocked app in dictionary
7. UI shows as locked (but app remains functionally unlocked)

### The Fix

Use **stable SHA-256 hash** from `UsagePersistence`:

```swift
// AFTER (FIXED):
init(token: ApplicationToken, tokenHash: String, reservedPoints: Int, pointsPerMinute: Int) {
    self.id = tokenHash  // ✅ Stable SHA-256 hash
    // ...
}
```

SHA-256 hash is based on token's binary data, which is stable across app launches.

**Update unlock flow:**

```swift
// ViewModels/AppUsageViewModel.swift:1523-1526
let tokenHash = service.usagePersistence.tokenHash(for: token)
let unlockedApp = UnlockedRewardApp(
    token: token,
    tokenHash: tokenHash,  // ✅ Pass stable hash
    reservedPoints: pointsNeeded,
    pointsPerMinute: pointsPerMinute
)
```

**Update load flow:**

```swift
// ViewModels/AppUsageViewModel.swift:1670-1671
if let matchedToken = masterSelection.applicationTokens.first(where: {
    service.usagePersistence.tokenHash(for: $0) == app.id  // ✅ Match using stable hash
}) {
    let rehydratedApp = UnlockedRewardApp(
        token: matchedToken,
        tokenHash: app.id,  // ✅ Use stored stable hash
        reservedPoints: app.reservedPoints,
        pointsPerMinute: app.pointsPerMinute,
        unlockedAt: app.unlockedAt
    )
    unlockedRewardApps[matchedToken] = rehydratedApp
}
```

### Files Modified

1. **Models/AppUsage.swift:41, 50**
   - Changed initializers to accept `tokenHash` parameter
   - Use stable hash instead of unstable `hashValue`

2. **ViewModels/AppUsageViewModel.swift:1523-1526**
   - Get stable tokenHash when unlocking
   - Pass to UnlockedRewardApp initializer

3. **ViewModels/AppUsageViewModel.swift:1670-1671**
   - Match using stable tokenHash when loading
   - Pass stored hash to rehydrated app

---

## Testing & Verification

### Test Scenario 1: Points Calculation
```
✅ PASS - Add app with 75 pts/min
✅ PASS - Use for 1 min → 75 pts
✅ PASS - Change to 230 pts/min
✅ PASS - Use for 1 min → 305 pts (75 + 230)
✅ PASS - Use for 1 min → 535 pts (305 + 230)
```

### Test Scenario 2: App Card Display
```
✅ PASS - Total Points matches App Card points
✅ PASS - Both show incremental values (not retroactive)
```

### Test Scenario 3: Unlocked Apps Persistence
```
✅ PASS - Unlock reward app
✅ PASS - Close and relaunch app
✅ PASS - Unlocked app still shows as unlocked in UI
✅ PASS - Remaining minutes preserved
✅ PASS - Reserved points preserved
```

---

## Impact Analysis

### Before Fixes
- ❌ Points recalculated when rate changed
- ❌ Rate changes didn't apply immediately
- ❌ UI showed inconsistent values
- ❌ Unlocked apps appeared locked after relaunch

### After Fixes
- ✅ Points locked in when earned
- ✅ Rate changes apply immediately
- ✅ UI shows consistent values
- ✅ Unlocked apps persist correctly

### User Experience
- **Before:** Confusing and inconsistent behavior
- **After:** Predictable and reliable behavior

### Data Integrity
- **Before:** Points could change retroactively
- **After:** Historical points are immutable

---

## Key Learnings

### 1. Computed Properties vs Stored Properties
**Lesson:** Never use computed properties for accumulating/aggregating values

- **Bad:** `var total: Int { items.reduce(0, +) }`
- **Good:** `private(set) var total: Int = 0` with incremental updates

### 2. State Management
**Lesson:** Always reload from persistence after configuration changes

- **Bad:** Assume in-memory state is current
- **Good:** Reload from source of truth (disk/database)

### 3. View Logic
**Lesson:** Display stored values, never recalculate in views

- **Bad:** `Text("\(item.count * item.price)")` (recalculation)
- **Good:** `Text("\(item.totalPrice)")` (stored value)

### 4. Hash Stability
**Lesson:** Use stable hashing for persistence

- **Bad:** `String(object.hashValue)` (unstable)
- **Good:** SHA-256 hash of stable data (stable)

### 5. Incremental Updates
**Lesson:** Add to existing value instead of recalculating total

- **Bad:** `total = items.reduce(0, +)` on every change
- **Good:** `total += newItem.value` on insert

---

## Architecture Decisions

### Decision 1: Stored Property for Points
**Rationale:** Ensures points are immutable once earned

**Alternatives Considered:**
- Keep computed property, store rate history → Too complex
- Recalculate on every access → Performance issues

**Chosen Solution:** Stored property with incremental updates
- Simple implementation
- Best performance
- Immutable historical data

### Decision 2: Reload from Persistence
**Rationale:** Ensures in-memory state matches disk state

**Alternatives Considered:**
- Update in-memory state directly → Risk of inconsistency
- Only reload on app launch → Stale data during session

**Chosen Solution:** Reload after configuration changes
- Guarantees consistency
- Minimal performance impact
- Single source of truth

### Decision 3: SHA-256 Token Hash
**Rationale:** Provides stable identifier across app launches

**Alternatives Considered:**
- Use token.hashValue → Unstable (original bug)
- Use bundleIdentifier → Not available for privacy-protected apps
- Store token directly → Cannot serialize ApplicationToken

**Chosen Solution:** SHA-256 hash of token data
- Stable across launches
- Works with privacy-protected apps
- Can be persisted

---

## Code Quality Improvements

### 1. Type Safety
- Added explicit `earnedPoints` field to snapshots
- Compiler enforces passing earned points

### 2. Documentation
- Added comments explaining why stable hashing is used
- Documented incremental calculation approach

### 3. Debug Logging
- Added logs for configuration reload
- Shows when points are calculated vs stored

### 4. Error Prevention
- Using `private(set)` for `earnedRewardPoints` prevents external modification
- Only `recordUsage()` can update points

---

## Future Recommendations

### 1. Unit Tests
Add tests for:
- Points calculation with rate changes
- Configuration reload behavior
- Token hash stability
- Snapshot creation with earned points

### 2. Data Migration
If users have existing data with old computed points:
- Consider migration script to recalculate historical points
- Or accept that old data shows retroactive values

### 3. Analytics
Track:
- Rate change frequency
- Points earned per session
- Unlock/relock patterns

### 4. Performance Monitoring
Monitor:
- Persistence reload performance
- Snapshot creation time
- Token hash calculation time

---

## Conclusion

All four critical bugs have been successfully fixed with comprehensive code changes. The fixes ensure:

1. ✅ **Data Integrity** - Points are immutable once earned
2. ✅ **Configuration Consistency** - Rate changes apply immediately
3. ✅ **UI Accuracy** - All displays show correct values
4. ✅ **State Persistence** - Unlocked apps maintain state across launches

The implementation now follows best practices for:
- State management (stored vs computed properties)
- Data persistence (reload from source of truth)
- View logic (display stored values)
- Token identification (stable hashing)

**Status:** ✅ PRODUCTION READY

---

**Document Version:** 1.0
**Last Updated:** 2025-10-26
**Author:** Development Team (via Claude Code)
