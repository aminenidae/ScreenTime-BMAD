# Migration Crash Fix

**Date:** 2025-11-19
**Status:** ✅ FIXED - Build Succeeded

---

## Crash Details

**Error:**
```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
    reason: 'keypath isActive not found in entity ChallengeProgress'
```

**Location:** ScreenTimeService.swift:1879
**Migration Function:** `migrateTodaySecondsFromChallengeProgress()`

---

## Root Cause

The migration function was trying to fetch `ChallengeProgress` entities using an incorrect predicate:

```swift
// WRONG:
fetchRequest.predicate = NSPredicate(format: "isActive == YES")
```

**Problem:** The `ChallengeProgress` entity doesn't have an `isActive` attribute.

**Actual Schema:**
```swift
@NSManaged public var progressID: String?
@NSManaged public var challengeID: String?
@NSManaged public var childDeviceID: String?
@NSManaged public var currentValue: Int32
@NSManaged public var targetValue: Int32
@NSManaged public var isCompleted: Bool  // ← THIS is the boolean field
@NSManaged public var completedDate: Date?
@NSManaged public var bonusPointsEarned: Int32
@NSManaged public var lastUpdated: Date?
```

---

## Fix Applied

**Changed Line 1879:**

```swift
// BEFORE (CRASH):
fetchRequest.predicate = NSPredicate(format: "isActive == YES")

// AFTER (FIXED):
fetchRequest.predicate = NSPredicate(format: "isCompleted == NO")
```

**Logic:** Query for challenges that are **not completed** (i.e., active/in-progress challenges).

---

## Build Status

✅ **BUILD SUCCEEDED**

No errors, only pre-existing warnings (unrelated to this fix).

---

## Next Steps

1. Deploy to device
2. Test migration runs without crashing
3. Verify existing 70 minutes shows in Child Mode UI
4. Test new usage recording continues to work

---

**Fix Complete:** 2025-11-19
**Ready for Testing:** ✅ Yes
