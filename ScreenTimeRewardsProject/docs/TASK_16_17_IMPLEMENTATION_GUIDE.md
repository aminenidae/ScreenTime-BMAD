# Task 16 & 17 Implementation Guide for Dev Agent
**Date:** November 1, 2025
**Priority:** HIGH
**Total Estimated Time:** 6-9 hours

---

## Quick Summary

**Task 16:** Implement Category-Based Reporting (Parent Dashboard)
**Task 17:** Implement Session Aggregation (Child Device)

Both tasks are independent and can be implemented in parallel or sequentially.

---

## Task 16: Category-Based Reporting

### Objective
Replace "Unknown App X" display on parent dashboard with category-based aggregation (Learning Apps, Reward Apps, etc.)

### Why We're Doing This
- Bundle IDs and app names are NOT available (Apple privacy limitation)
- Category data IS available and syncs via CloudKit
- Provides better UX than "Unknown App 0, 1, 2..."
- Gives parents actionable insights

### Files to Create

```
ScreenTimeRewards/Views/ParentRemote/
├── CategoryUsageCard.swift          (NEW - card component)
└── CategoryDetailView.swift         (NEW - detail view)

ScreenTimeRewards/Models/
└── CategoryUsageSummary.swift      (OPTIONAL - can go in ViewModel)
```

### Files to Modify

```
ScreenTimeRewards/ViewModels/
└── ParentRemoteViewModel.swift     (ADD aggregation logic)

ScreenTimeRewards/Views/ParentRemote/
└── RemoteUsageSummaryView.swift    (UPDATE to use category cards)
```

---

## Implementation Steps for Task 16

### Step 1: Add Data Model (5 minutes)

**Option A:** Create `CategoryUsageSummary.swift`
**Option B:** Add to `ParentRemoteViewModel.swift` (recommended)

```swift
struct CategoryUsageSummary: Identifiable {
    let id = UUID()
    let category: String
    let totalSeconds: Int
    let appCount: Int
    let totalPoints: Int
    let apps: [UsageRecord]

    var formattedTime: String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
```

### Step 2: Add Aggregation Logic (15 minutes)

**File:** `ParentRemoteViewModel.swift`

```swift
// ADD THIS PUBLISHED PROPERTY
@Published private(set) var categorySummaries: [CategoryUsageSummary] = []

// ADD THIS FUNCTION
func aggregateByCategory(_ records: [UsageRecord]) -> [CategoryUsageSummary] {
    let grouped = Dictionary(grouping: records) { $0.category ?? "Unknown" }

    return grouped.map { category, apps in
        CategoryUsageSummary(
            category: category,
            totalSeconds: apps.reduce(0) { $0 + Int($1.totalSeconds) },
            appCount: apps.count,
            totalPoints: apps.reduce(0) { $0 + Int($1.earnedPoints) },
            apps: apps
        )
    }.sorted { $0.totalSeconds > $1.totalSeconds }
}

// MODIFY EXISTING FETCH FUNCTION
// After fetching records, add this:
await MainActor.run {
    self.categorySummaries = aggregateByCategory(fetchedRecords)
}
```

### Step 3: Create Category Card Component (30 minutes)

**File:** `CategoryUsageCard.swift`

Full implementation provided in main fix plan document. Key features:
- Category icon (📚, 🎮, 💬, 🎨)
- Category color (blue, purple, green, orange)
- Time and points display
- App count
- Chevron for navigation

### Step 4: Create Detail View (45 minutes)

**File:** `CategoryDetailView.swift`

Full implementation provided in main fix plan document. Key features:
- Category overview (total time, points, app count)
- Individual app list (privacy-protected names)
- Session times
- Info footer about privacy

**Privacy-Protected Naming:**
```swift
private func enhancedAppName(for record: UsageRecord) -> String {
    let category = record.category ?? "Unknown"
    let appNumber = abs(record.logicalID?.hashValue ?? 0) % 100
    return "Privacy Protected \(category) App #\(appNumber)"
}
```

### Step 5: Update Dashboard View (1 hour)

**File:** `RemoteUsageSummaryView.swift`

Replace current app list with category cards:
```swift
ForEach(viewModel.categorySummaries) { summary in
    NavigationLink(destination: CategoryDetailView(summary: summary)) {
        CategoryUsageCard(summary: summary)
    }
    .buttonStyle(PlainButtonStyle())
}
.padding(.horizontal)
```

Add total summary at bottom (optional but recommended):
- Total screen time across all categories
- Total points across all categories

### Step 6: Test (30 minutes)

**Test Cases:**
1. Empty state (no usage data)
2. Single category
3. Multiple categories
4. Tap navigation to detail view
5. Verify totals match child device
6. Test with real CloudKit data

---

## Task 17: Session Aggregation

### Objective
Stop creating new UsageRecord every minute. Instead, update existing record if usage is continuous.

### Why We're Doing This
- Current: 60 minutes usage = 60 separate records
- After fix: 60 minutes continuous usage = 1 aggregated record
- Reduces database bloat by 80-90%
- Reduces CloudKit sync load by 80-90%

### Files to Modify

```
ScreenTimeRewards/Services/
└── ScreenTimeService.swift         (MODIFY recordUsage function)
```

---

## Implementation Steps for Task 17

### Step 1: Add Helper Function (10 minutes)

**File:** `ScreenTimeService.swift`

Add this private function to the class:

```swift
/// Find the most recent UsageRecord for a given app within a time window
private func findRecentUsageRecord(
    logicalID: String,
    deviceID: String,
    withinSeconds timeWindow: TimeInterval = 300  // 5 minutes
) -> UsageRecord? {
    let context = PersistenceController.shared.container.viewContext
    let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()

    let now = Date()
    let cutoffTime = now.addingTimeInterval(-timeWindow)

    fetchRequest.predicate = NSPredicate(
        format: "logicalID == %@ AND deviceID == %@ AND sessionEnd >= %@",
        logicalID,
        deviceID,
        cutoffTime as NSDate
    )
    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionEnd", ascending: false)]
    fetchRequest.fetchLimit = 1

    do {
        let results = try context.fetch(fetchRequest)
        return results.first
    } catch {
        #if DEBUG
        print("[ScreenTimeService] ⚠️ Failed to fetch recent usage record: \(error)")
        #endif
        return nil
    }
}
```

### Step 2: Modify UsageRecord Creation (30 minutes)

**File:** `ScreenTimeService.swift`
**Location:** Lines 1338-1363 (approximately)

**Replace this entire section:**
```swift
// === TASK 7: Create Core Data UsageRecord for CloudKit Sync ===
let context = PersistenceController.shared.container.viewContext
let usageRecord = UsageRecord(context: context)
usageRecord.recordID = UUID().uuidString
// ... etc (all the current record creation)
```

**With this:**
```swift
// === TASK 7 + TASK 17: Create OR UPDATE Core Data UsageRecord for CloudKit Sync ===
let context = PersistenceController.shared.container.viewContext
let deviceID = DeviceModeManager.shared.deviceID

// Check for recent record within last 5 minutes
if let recentRecord = findRecentUsageRecord(
    logicalID: logicalID,
    deviceID: deviceID,
    withinSeconds: 300  // 5 minutes
) {
    // UPDATE existing record
    #if DEBUG
    print("[ScreenTimeService] 📝 Updating existing UsageRecord for \(logicalID)")
    #endif

    recentRecord.sessionEnd = endDate
    recentRecord.totalSeconds += Int32(duration)

    let totalMinutes = Int(recentRecord.totalSeconds / 60)
    recentRecord.earnedPoints = Int32(totalMinutes * application.rewardPoints)
    recentRecord.isSynced = false

    do {
        try context.save()
        #if DEBUG
        print("[ScreenTimeService] ✅ Updated UsageRecord: \(recentRecord.totalSeconds)s total")
        #endif
    } catch {
        #if DEBUG
        print("[ScreenTimeService] ⚠️ Failed to update UsageRecord: \(error)")
        #endif
    }
} else {
    // CREATE new record (no recent session found)
    #if DEBUG
    print("[ScreenTimeService] 💾 Creating NEW UsageRecord for \(logicalID)")
    #endif

    let usageRecord = UsageRecord(context: context)
    usageRecord.recordID = UUID().uuidString
    usageRecord.deviceID = deviceID
    usageRecord.logicalID = logicalID
    usageRecord.displayName = application.displayName
    usageRecord.category = application.category.rawValue
    usageRecord.totalSeconds = Int32(duration)
    usageRecord.sessionStart = endDate.addingTimeInterval(-duration)
    usageRecord.sessionEnd = endDate
    let recordMinutes = Int(duration / 60)
    usageRecord.earnedPoints = Int32(recordMinutes * application.rewardPoints)
    usageRecord.isSynced = false

    do {
        try context.save()
        #if DEBUG
        print("[ScreenTimeService] ✅ Created NEW UsageRecord for CloudKit sync: \(logicalID)")
        #endif
    } catch {
        #if DEBUG
        print("[ScreenTimeService] ⚠️ Failed to save UsageRecord: \(error)")
        #endif
    }
}
```

### Step 3: Add Configuration Constant (2 minutes)

**File:** `ScreenTimeService.swift`
**Location:** Top of class (with other constants)

```swift
private let sessionAggregationWindowSeconds: TimeInterval = 300  // 5 minutes
```

Then update the function call:
```swift
withinSeconds: sessionAggregationWindowSeconds
```

### Step 4: Test (30 minutes)

**Test Cases:**

1. **Continuous Usage:**
   - Use an app for 10 minutes straight
   - Check Core Data: Should have 1 record with ~600 seconds
   - Not 10 separate records

2. **Interrupted Usage:**
   - Use app for 3 minutes
   - Stop for 10 minutes (exceeds 5-minute window)
   - Use app again for 3 minutes
   - Check: Should have 2 separate records

3. **Multiple Apps:**
   - Switch between App A and App B
   - Each should have its own aggregated record

4. **Sync Verification:**
   - Verify updated records have `isSynced = false`
   - Parent should receive updated totals
   - No duplicates on parent

---

## Testing Checklist

### Task 16 Testing

- [ ] Build succeeds without errors
- [ ] Empty state shows correctly (no usage)
- [ ] Category cards display with correct data
- [ ] Colors match category types
- [ ] Icons display correctly
- [ ] Tap navigation works to detail view
- [ ] Detail view shows individual apps
- [ ] Privacy-protected names are consistent
- [ ] Totals match child device data
- [ ] Works with real CloudKit sync
- [ ] Dark mode looks good
- [ ] iPad layout works (if applicable)

### Task 17 Testing

- [ ] Build succeeds without errors
- [ ] Helper function compiles correctly
- [ ] Continuous usage creates single record
- [ ] Record updates with correct total time
- [ ] Interrupted usage creates separate records
- [ ] Multiple apps tracked independently
- [ ] Debug logs show UPDATE vs CREATE
- [ ] Updated records marked as unsynced
- [ ] Parent receives updated data
- [ ] No data loss during aggregation
- [ ] Points calculated correctly

---

## Common Issues & Solutions

### Issue: "Cannot find 'CategoryUsageSummary' in scope"
**Solution:** Make sure struct is defined before use. Add to ViewModel or create separate file.

### Issue: Category cards not showing
**Solution:** Check that `categorySummaries` is populated. Add debug print after aggregation.

### Issue: "Value of type 'UsageRecord' has no member 'recordID'"
**Solution:** Check Core Data model. Field might be named differently. Use correct property name.

### Issue: Session aggregation not working
**Solution:** Check:
- `deviceID` matches between records
- `sessionEnd` is within 5-minute window
- Fetch request predicate is correct
- Core Data context is same

### Issue: Existing records not updating
**Solution:**
- Verify `findRecentUsageRecord` returns non-nil
- Check `isSynced` is set to `false` after update
- Ensure `context.save()` is called

---

## Debugging Tips

### For Task 16:

```swift
// Add to aggregation function
print("📊 Categories found: \(grouped.keys)")
print("📊 Total summaries: \(summaries.count)")

// Add to view
.onAppear {
    print("🖼️ Displaying \(viewModel.categorySummaries.count) categories")
}
```

### For Task 17:

```swift
// Already included in implementation
print("[ScreenTimeService] 📝 Updating existing UsageRecord...")
print("[ScreenTimeService] 💾 Creating NEW UsageRecord...")
print("[ScreenTimeService] ✅ Updated UsageRecord: \(totalSeconds)s total")
```

Check logs for:
- UPDATE vs CREATE messages
- Total seconds increasing
- No excessive CREATE messages for continuous usage

---

## Time Estimates

### Task 16 Breakdown:
- Data model: 5 min
- Aggregation logic: 15 min
- Category card: 30 min
- Detail view: 45 min
- Dashboard update: 1 hour
- Testing: 30 min
- **Total: 3-4 hours**

### Task 17 Breakdown:
- Helper function: 10 min
- Modify creation logic: 30 min
- Configuration constant: 2 min
- Testing: 30 min
- Debugging/fixes: 30 min
- **Total: 2-3 hours**

### Combined Total: 5-7 hours
(Plus buffer for unexpected issues: 6-9 hours total)

---

## Success Criteria

### Task 16 Success:
✅ Parent sees category cards instead of "Unknown App X"
✅ Category totals are accurate
✅ Tap opens detail view with individual apps
✅ UI is polished and professional
✅ Works with real CloudKit data

### Task 17 Success:
✅ Continuous usage = 1 aggregated record
✅ Database record count reduced by 80-90%
✅ Updated records sync to parent
✅ No data loss or corruption
✅ Points calculated correctly

---

## Next Steps After Implementation

1. **Code Review:** Have another developer review the changes
2. **User Testing:** Test with real parent/child devices
3. **Documentation:** Update user-facing docs if needed
4. **Monitoring:** Watch CloudKit usage metrics (should decrease)
5. **Iteration:** Gather feedback and refine UI

---

## Questions or Issues?

If you encounter problems:
1. Check the main fix plan document for detailed code examples
2. Review the research report for Apple API limitations
3. Check debug logs for specific error messages
4. Verify Core Data schema matches code expectations

---

**Ready to implement? Start with whichever task you prefer - they're independent!**

Good luck! 🚀
