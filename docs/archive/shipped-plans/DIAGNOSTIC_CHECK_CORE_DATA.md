# Diagnostic: Check Core Data for UsageRecords

## Issue
Child device shows "Found 0 unsynced usage records" despite dashboard displaying usage data.

## Hypothesis
Usage data might be tracked in-memory only (not persisted to Core Data), OR all records were already marked as synced.

## Diagnostic Steps

### Step 1: Add Temporary Debug Code

Add this diagnostic function to `ScreenTimeService.swift`:

```swift
// MARK: - DIAGNOSTIC: Check UsageRecord Status
func diagnosticCheckUsageRecords() {
    let context = PersistenceController.shared.container.viewContext

    // Query ALL UsageRecords (not just unsynced)
    let allRecordsRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
    allRecordsRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: false)]

    // Query unsynced records
    let unsyncedRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
    unsyncedRequest.predicate = NSPredicate(format: "isSynced == NO")

    do {
        let allRecords = try context.fetch(allRecordsRequest)
        let unsyncedRecords = try context.fetch(unsyncedRequest)

        print("=================================================")
        print("📊 DIAGNOSTIC: UsageRecord Status")
        print("=================================================")
        print("Total UsageRecords in Core Data: \(allRecords.count)")
        print("Unsynced records: \(unsyncedRecords.count)")
        print("Synced records: \(allRecords.count - unsyncedRecords.count)")

        if allRecords.isEmpty {
            print("❌ NO UsageRecords found in Core Data!")
            print("   This means usage is tracked in-memory only.")
        } else {
            print("\nMost recent 5 records:")
            for (index, record) in allRecords.prefix(5).enumerated() {
                print("  [\(index+1)] \(record.displayName ?? "Unknown")")
                print("      Session: \(record.sessionStart ?? Date()) - \(record.sessionEnd ?? Date())")
                print("      Duration: \(record.totalSeconds)s")
                print("      Points: \(record.earnedPoints)")
                print("      Category: \(record.category ?? "unknown")")
                print("      Synced: \(record.isSynced)")
                print("      Device ID: \(record.deviceID ?? "nil")")
            }
        }

        // Check in-memory tracking
        print("\n📱 In-Memory Tracking:")
        print("   childAppUsages count: \(childAppUsages.count)")
        print("   monitoredEvents count: \(monitoredEvents.count)")

        print("=================================================")

    } catch {
        print("❌ Error fetching UsageRecords: \(error)")
    }
}
```

### Step 2: Call Diagnostic Function

Add this call in `ChildBackgroundSyncService.uploadUsageRecordsToParent()` RIGHT BEFORE the existing query:

```swift
func uploadUsageRecordsToParent() async throws {
    #if DEBUG
    print("[ChildBackgroundSyncService] ===== Uploading Usage Records To Parent =====")

    // DIAGNOSTIC: Check what's actually in Core Data
    ScreenTimeService.shared.diagnosticCheckUsageRecords()
    #endif

    // ... existing code continues ...
}
```

### Step 3: Trigger Upload and Read Console

1. Build and run on child device
2. Use app for 1-2 minutes (learning or reward app)
3. Trigger manual upload (call `triggerImmediateUsageUpload()`)
4. Read Xcode console output

## Expected Outputs & Meanings

### Case A: Core Data is Empty
```
📊 DIAGNOSTIC: UsageRecord Status
Total UsageRecords in Core Data: 0
Unsynced records: 0
❌ NO UsageRecords found in Core Data!
   This means usage is tracked in-memory only.
```

**Problem**: UsageRecords aren't being persisted to Core Data
**Solution**: Check `recordUsage()` - line 2416 should call `context.save()`

### Case B: All Records Are Synced
```
📊 DIAGNOSTIC: UsageRecord Status
Total UsageRecords in Core Data: 47
Unsynced records: 0
Synced records: 47
```

**Problem**: All records were already uploaded, no NEW usage since last sync
**Solution**: Use child device for 1-2 minutes, then check again

### Case C: Some Unsynced Records
```
📊 DIAGNOSTIC: UsageRecord Status
Total UsageRecords in Core Data: 52
Unsynced records: 5
Synced records: 47
```

**Problem**: Unsynced records exist but aren't being fetched by upload query
**Solution**: Check if fetch predicate matches records correctly

### Case D: Mix of Data
```
📊 DIAGNOSTIC: UsageRecord Status
Total UsageRecords in Core Data: 15
Unsynced records: 3
Synced records: 12

Most recent 5 records:
  [1] Khan Academy
      Session: 2025-12-28 14:30:00 - 2025-12-28 14:32:00
      Duration: 120s
      Points: 2
      Category: learning
      Synced: false
      Device ID: ABC123
```

**Status**: ✅ Working correctly - records exist and some are unsynced

## Additional Checks

### Check if recordUsage() is Being Called

Add log at the start of `ScreenTimeService.recordUsage()`:

```swift
func recordUsage(for applications: Set<Application>, duration: TimeInterval, endingAt endDate: Date) {
    #if DEBUG
    print("🔄 [ScreenTimeService] recordUsage called:")
    print("   Apps: \(applications.count)")
    print("   Duration: \(duration)s")
    print("   End date: \(endDate)")
    #endif

    // ... existing code ...
}
```

### Check if Context.save() is Called

Verify line 2416 is reached:

```swift
// Line 2416
do {
    try context.save()
    #if DEBUG
    print("✅ [ScreenTimeService] Saved \(newRecordsCreated) new UsageRecords to Core Data")
    #endif
} catch {
    print("❌ [ScreenTimeService] Failed to save UsageRecords: \(error)")
}
```

## Root Cause Possibilities

Based on diagnostic output, the issue is likely:

1. **No Persistence**: Usage tracked in-memory, never saved to Core Data
   - Fix: Ensure `context.save()` is called (line 2416)
   - Check for Core Data errors during save

2. **All Already Synced**: Records exist but were uploaded already
   - Verify: New usage after sync should create new unsynced records
   - Check: Sync might be too aggressive (uploading immediately)

3. **Wrong Context**: Records saved to different Core Data context
   - Check: `PersistenceController.shared.container.viewContext` used everywhere
   - Verify: Background contexts properly merged

4. **Threshold Events Not Firing**: Apps used but events not triggered
   - Check: `handleEventThresholdReached()` logs
   - Verify: DeviceActivityCenter properly configured

5. **Records Being Deleted**: Created but then deleted before sync
   - Check: No cleanup/purge code running
   - Verify: No cascade deletes from related entities

## Next Steps

1. Add diagnostic code
2. Build and run on child device
3. Use app for 1-2 minutes
4. Trigger upload
5. Report console output

This will reveal exactly where the data flow breaks down.
