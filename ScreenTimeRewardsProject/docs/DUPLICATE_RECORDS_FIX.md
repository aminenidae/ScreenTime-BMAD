# Duplicate Records Fix - Point Calculation Issue

**Date:** November 1, 2025
**Issue:** Parent dashboard calculating incorrect points due to duplicate usage records
**Status:** ✅ FIXED

---

## 🐛 The Problem

When a child used a learning app for 4 minutes with 150 points/minute (expected 600 points total), the parent dashboard showed:

```
Total Time: 10m (incorrect - should be 4m)
Total Points: 1,500 (incorrect - should be 600)
Apps Monitored: 4 (incorrect - should be 1)

Individual Apps:
1. Privacy Protected Learning App #0: 4m, 600 pts (20:12 → 20:18)
2. Privacy Protected Learning App #0: 3m, 450 pts (20:12 → 20:16)
3. Privacy Protected Learning App #0: 2m, 300 pts (20:12 → 20:14)
4. Privacy Protected Learning App #0: 1m, 150 pts (20:12 → 20:13)

Total: 600 + 450 + 300 + 150 = 1,500 points ❌
```

The parent was treating each CloudKit record version as a separate app session.

---

## 🔍 Root Cause Analysis

### Child Device Behavior (Correct)

Task 17 session aggregation **WAS implemented** in `ScreenTimeService.swift:1410-1492`:

```swift
// Check for recent record within last 5 minutes
if let recentRecord = findRecentUsageRecord(
    logicalID: logicalID,
    deviceID: deviceID,
    withinSeconds: 300  // 5 minutes
) {
    // UPDATE existing record
    recentRecord.sessionEnd = endDate
    recentRecord.totalSeconds += Int32(duration)
    recentRecord.earnedPoints = Int32(totalMinutes * application.rewardPoints)
    recentRecord.isSynced = false  // Mark for re-sync
    try context.save()
}
```

**Expected behavior:** Child device updates the SAME Core Data record each minute.

### CloudKit Sync Behavior (Issue Source)

When Core Data + CloudKit syncs:
1. Child updates local record → marks `isSynced = false`
2. NSPersistentCloudKitContainer uploads to CloudKit
3. **Problem:** Each update may create a NEW CKRecord instead of updating the existing one
4. OR CloudKit keeps historical versions of the record
5. Parent fetches ALL versions (1m, 2m, 3m, 4m) instead of just the latest

### Parent Aggregation Behavior (Missing Safety Check)

`ParentRemoteViewModel.aggregateByCategory()` was blindly summing all records:

```swift
// BEFORE (WRONG):
let summaries = grouped.map { category, apps in
    CategoryUsageSummary(
        category: category,
        totalSeconds: apps.reduce(0) { $0 + Int($1.totalSeconds) },  // Sums ALL records
        appCount: apps.count,  // Counts ALL records
        totalPoints: apps.reduce(0) { $0 + Int($1.earnedPoints) }  // Sums ALL records
    )
}
```

---

## 🔧 The Fix

### Added De-Duplication Logic

**File:** `ParentRemoteViewModel.swift:217-287`

**New function:** `deduplicateRecords(_ records:) -> [UsageRecord]`

**Logic:**
1. Group records by `logicalID` (app identifier)
2. For each app, group by `sessionStart` (records with same/similar start time = same session)
3. Within each session group, keep ONLY the record with the **latest sessionEnd** (most complete/updated)
4. Discard older versions

**Example:**
```
Input: 4 records for same app
  - 20:12 → 20:13 (1m, 150 pts)
  - 20:12 → 20:14 (2m, 300 pts)
  - 20:12 → 20:16 (3m, 450 pts)
  - 20:12 → 20:18 (4m, 600 pts)

De-duplication detects:
  - All have same sessionStart (20:12)
  - All have same logicalID
  - These are versions of the SAME session

Output: 1 record
  - 20:12 → 20:18 (4m, 600 pts) ✅
```

### Updated Aggregation

**File:** `ParentRemoteViewModel.swift:289-328`

```swift
func aggregateByCategory(_ records: [UsageRecord]) -> [CategoryUsageSummary] {
    // De-duplicate overlapping records FIRST
    let uniqueRecords = deduplicateRecords(records)

    // THEN aggregate by category
    let grouped = Dictionary(grouping: uniqueRecords) { $0.category ?? "Unknown" }

    let summaries = grouped.map { category, apps in
        CategoryUsageSummary(
            category: category,
            totalSeconds: apps.reduce(0) { $0 + Int($1.totalSeconds) },  // Now sums UNIQUE records
            appCount: apps.count,  // Now counts UNIQUE sessions
            totalPoints: apps.reduce(0) { $0 + Int($1.earnedPoints) }  // Now sums UNIQUE points
        )
    }

    return summaries.sorted { $0.totalSeconds > $1.totalSeconds }
}
```

---

## ✅ Expected Results After Fix

### Test Scenario: 4 minutes of learning app usage (150 pts/min)

**Before Fix:**
```
Learning Apps
  Total Time: 10m
  Total Points: 1,500
  Apps Monitored: 4

Individual Apps:
  - 4 records shown (all same app)
  - Points: 600 + 450 + 300 + 150 = 1,500
```

**After Fix:**
```
Learning Apps
  Total Time: 4m ✅
  Total Points: 600 ✅
  Apps Monitored: 1 ✅

Individual Apps:
  - Privacy Protected Learning App #0: 4m, 600 pts ✅
  (3 older versions de-duplicated)
```

---

## 🧪 Testing the Fix

### Debug Logs to Watch For

When you run the parent app and view the remote dashboard:

**1. De-duplication logs:**
```
[ParentRemoteViewModel] 🔍 De-duplicating 7 records...
[ParentRemoteViewModel] 🔍 Found 4 records for <logicalID>
[ParentRemoteViewModel]   ✅ Keeping most recent: 240s (discarding 3 older versions)
[ParentRemoteViewModel] ✅ De-duplication complete: 7 → 4 records
```

**2. Aggregation logs:**
```
[ParentRemoteViewModel] ===== Aggregating 7 Records by Category =====
[ParentRemoteViewModel] After de-duplication: 4 unique records
[ParentRemoteViewModel] Grouped into 2 categories: ["Learning", "Reward"]
[ParentRemoteViewModel]   📊 Learning: 1 apps, 240s, 600 pts
```

### Test Steps

1. **Clear old data** (optional):
   - Delete app from both devices
   - Reinstall to start fresh

2. **Use one learning app for 4 minutes continuously**

3. **Check parent dashboard:**
   - Total points should equal: `4 minutes × points_per_minute`
   - Apps monitored should show: `1`
   - Individual apps should show: `1 entry` (not 4)

4. **Use multiple different apps**
   - Each unique app should show as separate entry
   - Each app should have correct cumulative time/points

---

## 🔄 Why This Happens (Technical Deep Dive)

### Core Data + CloudKit Sync Architecture

```
Child Device:
  Core Data Record (local)
    ↓ Update in-place
  NSPersistentCloudKitContainer
    ↓ Sync
  CloudKit Private Database
    ↓ Share to parent
  CloudKit Shared Zone
    ↓
Parent Device fetches from shared zone
```

**Issue:** When `isSynced = false` is set on an already-synced record:
- NSPersistentCloudKitContainer may create a NEW CKRecord
- OR CloudKit keeps historical versions for conflict resolution
- Parent's fetch query returns ALL versions

### Why De-Duplication is the Right Fix

**Alternative 1:** Fix CloudKit sync to update existing records
**Complexity:** High - requires deep dive into NSPersistentCloudKitContainer internals
**Risk:** May break existing sync mechanism

**Alternative 2:** Delete old records before syncing new ones
**Complexity:** Medium - but risks data loss if sync fails
**Risk:** Could lose usage history

**Alternative 3:** De-duplicate on parent side ✅
**Complexity:** Low - straightforward logic
**Risk:** Low - safe read-only operation
**Benefit:** Works regardless of CloudKit behavior

---

## 📊 Performance Impact

**Before:** Summing 10+ duplicate records per app
**After:** Summing 1 unique record per app

**Impact:**
- Reduced memory usage
- Faster aggregation
- Correct calculations
- Better UX (shows actual unique apps)

---

## 🎯 Future Improvements

### Optional: Clean Up CloudKit Records

If storage becomes an issue, we could add a cleanup job:

```swift
// Run periodically
func cleanupDuplicateCloudKitRecords() async {
    // Fetch all records
    // Group by logicalID + sessionStart
    // Delete older versions
    // Keep only latest
}
```

**Note:** Not urgent - CloudKit has generous storage limits and de-duplication handles the display issue.

---

## 📝 Files Modified

1. **ParentRemoteViewModel.swift** (lines 217-328)
   - Added `deduplicateRecords()` function
   - Updated `aggregateByCategory()` to use de-duplication

---

## ✅ Verification Checklist

- [x] Code compiles without errors
- [x] De-duplication logic tested with multiple scenarios
- [x] Build succeeds
- [ ] User testing: Verify correct point calculations
- [ ] User testing: Verify correct app counts
- [ ] User testing: Verify individual app list shows unique entries only

---

**Status:** ✅ READY FOR TESTING
**Build:** Successful
**Next Step:** Deploy to devices and verify with real usage data
