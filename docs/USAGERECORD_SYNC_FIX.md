# UsageRecord CloudKit Sync Fix - Implementation Plan (Option 1: Safest)

**Date:** 2025-12-29
**Status:** READY FOR IMPLEMENTATION
**Risk Level:** LOW (with safeguards)

---

## Executive Summary

Child device usage data is not syncing to parent device because UsageRecord Core Data entities are never created. Diagnostic testing confirmed that iOS DeviceActivity threshold events are not being delivered to the main app, which is the only existing code path for creating UsageRecords.

**Solution:** Create UsageRecords directly from extension data with safeguards to prevent conflicts and allow safe rollback.

---

## Root Cause Analysis

### Diagnostic Results ✅

| Component | Status | Evidence |
|-----------|--------|----------|
| DeviceActivity monitoring | ✅ Working | `🔔 DeviceActivity monitoring started successfully` |
| Threshold events | ❌ NOT firing | No `🔔 ===== THRESHOLD EVENT RECEIVED =====` logs |
| UsageRecord creation | ❌ Never happens | `📊 [DEBUG] Unsynced UsageRecords: 0` |
| Extension tracking | ✅ Working | Usage data visible in UI |
| UserDefaults sync | ✅ Working | ext_usage_* keys populated |
| CloudKit pairing | ✅ Working | Zone ID, owner, root record all present |

### Current Data Flow

```
┌─────────────┐
│  Extension  │ Tracks app usage
└──────┬──────┘
       │ Writes to UserDefaults (ext_usage_* keys)
       ▼
┌─────────────┐
│ Main App    │ Reads extension data via Darwin notification
└──────┬──────┘
       │ Updates in-memory state (appUsages)
       │ Syncs to UsagePersistence
       │ Updates UI ✅
       │
       ▼
    ❌ NO Core Data entity created
    ❌ NO CloudKit upload
    ❌ Parent device sees nothing
```

### Why Threshold Events Aren't Firing

iOS DeviceActivity threshold events are **unreliable** by design:
- May not fire when app is backgrounded
- Delayed or lost during system resource constraints
- Framework-level issues outside our control
- Not guaranteed delivery per Apple documentation

**Attempting to fix threshold events = fighting Apple's frameworks**

---

## Solution Architecture

### New Data Flow (Safest Approach)

```
┌─────────────┐
│  Extension  │ Tracks app usage
└──────┬──────┘
       │ Writes to UserDefaults (ext_usage_* keys)
       ▼
┌─────────────┐
│ Main App    │ Reads extension data
└──────┬──────┘
       │ Updates in-memory state
       │ Syncs to UsagePersistence
       │ Updates UI ✅
       │
       │ ✨ NEW: Create/update Core Data UsageRecord
       │        (with feature flag & deduplication)
       ▼
┌─────────────┐
│ Core Data   │ UsageRecord entities (isSynced = false)
└──────┬──────┘
       │ Background sync every 30 min
       ▼
┌─────────────┐
│  CloudKit   │ CD_UsageRecord records in shared zone
└──────┬──────┘
       │ Parent queries
       ▼
┌─────────────┐
│Parent Device│ Displays child usage ✅
└─────────────┘
```

### Key Safeguards (Option 1)

1. **Feature Flag Control**
   - Disabled by default
   - Enable per-device for testing
   - Instant rollback capability
   - No code changes needed to disable

2. **Deduplication via Date Range**
   - Finds ANY record for app on given day
   - Prevents conflicts with threshold-based records
   - Updates existing instead of creating duplicates

3. **Conditional Execution**
   - Only runs if device is paired
   - Checks for parentSharedZoneID
   - No overhead for unpaired devices

4. **Idempotent Design**
   - Safe to call multiple times
   - Find-or-create pattern
   - Updates only when values change

---

## Implementation Details

### File to Modify
`Services/ScreenTimeService.swift`

### Change 1: Add Feature Flag Check Function

**Location:** After `readExtensionUsageData()` function (~line 1158)

```swift
// MARK: - UsageRecord Sync from Extension Data

/// Check if extension-based UsageRecord creation is enabled
/// This is a safety feature to allow gradual rollout and instant rollback
private var isExtensionRecordSyncEnabled: Bool {
    UserDefaults.standard.bool(forKey: "enableExtensionBasedRecordCreation")
}

/// Enable extension-based record creation (call once during testing)
func enableExtensionRecordSync() {
    UserDefaults.standard.set(true, forKey: "enableExtensionBasedRecordCreation")
    #if DEBUG
    print("[ScreenTimeService] ✅ Extension-based UsageRecord sync ENABLED")
    #endif
}

/// Disable extension-based record creation (instant rollback)
func disableExtensionRecordSync() {
    UserDefaults.standard.set(false, forKey: "enableExtensionBasedRecordCreation")
    #if DEBUG
    print("[ScreenTimeService] 🛑 Extension-based UsageRecord sync DISABLED")
    #endif
}
```

### Change 2: Add UsageRecord Creation Function

**Location:** After the feature flag functions

```swift
/// Create or update UsageRecord Core Data entity from extension usage data
/// Called by readExtensionUsageData() to ensure usage data is persisted for CloudKit sync
///
/// SAFEGUARDS:
/// - Feature flag controlled (disabled by default)
/// - Only runs if device is paired with parent
/// - Finds ANY record for app on given day (prevents duplicates)
/// - Updates existing record instead of creating duplicates
/// - Only saves if values actually changed (minimizes Core Data writes)
private func syncUsageRecordFromExtensionData(
    logicalID: String,
    displayName: String,
    category: AppCategory,
    todaySeconds: Int,
    todayPoints: Int
) {
    // SAFEGUARD 1: Feature flag check
    guard isExtensionRecordSyncEnabled else {
        return  // Feature disabled, skip
    }

    // SAFEGUARD 2: Only create records if device is paired with parent
    guard UserDefaults.standard.string(forKey: "parentSharedZoneID") != nil else {
        return  // Not paired, skip record creation
    }

    // SAFEGUARD 3: Only create records for apps with actual usage
    guard todaySeconds > 0 else {
        return  // No usage to record
    }

    let context = persistenceController.container.viewContext
    let deviceID = DeviceModeManager.shared.deviceID

    // SAFEGUARD 4: Find ANY existing record for this app TODAY
    // Uses date range to catch records created by BOTH code paths:
    // - Extension-based: sessionStart = start of day (00:00)
    // - Threshold-based: sessionStart = actual usage time (e.g., 14:32)
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
    fetchRequest.predicate = NSPredicate(
        format: "logicalID == %@ AND deviceID == %@ AND sessionStart >= %@ AND sessionStart < %@",
        logicalID,
        deviceID,
        today as NSDate,
        tomorrow as NSDate
    )
    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: false)]
    fetchRequest.fetchLimit = 1

    do {
        let existing = try context.fetch(fetchRequest).first

        if let record = existing {
            // SAFEGUARD 5: Update existing record ONLY if values changed
            // Minimizes Core Data writes and CloudKit uploads
            if record.totalSeconds != Int32(todaySeconds) || record.earnedPoints != Int32(todayPoints) {
                let oldSeconds = record.totalSeconds
                let oldPoints = record.earnedPoints

                record.totalSeconds = Int32(todaySeconds)
                record.earnedPoints = Int32(todayPoints)
                record.sessionEnd = Date()
                record.isSynced = false  // Mark for re-upload to CloudKit

                try context.save()

                #if DEBUG
                print("[ScreenTimeService] 💾 Updated UsageRecord from extension:")
                print("   App: \(displayName)")
                print("   Old: \(oldSeconds)s, \(oldPoints)pts")
                print("   New: \(todaySeconds)s, \(todayPoints)pts")
                print("   Marked for CloudKit re-upload")
                #endif
            } else {
                #if DEBUG
                print("[ScreenTimeService] ⏭️ Skipped update (no change): \(displayName) - \(todaySeconds)s")
                #endif
            }
        } else {
            // Create new record for today
            let record = UsageRecord(context: context)
            record.recordID = UUID().uuidString
            record.deviceID = deviceID
            record.logicalID = logicalID
            record.displayName = displayName
            record.category = category.rawValue
            record.totalSeconds = Int32(todaySeconds)
            record.sessionStart = today  // Use start of day for consistency
            record.sessionEnd = Date()
            record.earnedPoints = Int32(todayPoints)
            record.isSynced = false  // Mark for CloudKit upload

            try context.save()

            #if DEBUG
            print("[ScreenTimeService] 💾 Created NEW UsageRecord from extension:")
            print("   App: \(displayName)")
            print("   Usage: \(todaySeconds)s (\(todaySeconds/60)min)")
            print("   Points: \(todayPoints)pts")
            print("   Category: \(category.rawValue)")
            print("   Ready for CloudKit upload")
            #endif
        }
    } catch {
        #if DEBUG
        print("[ScreenTimeService] ❌ Failed to sync UsageRecord from extension data:")
        print("   App: \(displayName)")
        print("   Error: \(error.localizedDescription)")
        #endif
    }
}
```

### Change 3: Call New Function from readExtensionUsageData()

**Location:** Inside `readExtensionUsageData()`, after line ~1146

**Find this block:**
```swift
if extTodaySeconds != persistedApp.todaySeconds {
    // ... existing sync logic ...
    usagePersistence.saveApp(persistedApp)
}
```

**Add AFTER `usagePersistence.saveApp(persistedApp)`:**
```swift
// Also create/update Core Data UsageRecord for CloudKit sync
// This ensures parent devices can see child usage data
syncUsageRecordFromExtensionData(
    logicalID: logicalID,
    displayName: persistedApp.displayName,
    category: usage.category,
    todaySeconds: extTodaySeconds,
    todayPoints: persistedApp.todayPoints
)
```

### Change 4: Add Debug UI Controls

**File:** `Views/SettingsTabView.swift`

**Add to DEBUG section after existing debug buttons:**

```swift
var debugToggleExtensionSyncRow: some View {
    @State var isEnabled = ScreenTimeService.shared.isExtensionRecordSyncEnabled

    return Button(action: {
        if isEnabled {
            ScreenTimeService.shared.disableExtensionRecordSync()
            isEnabled = false
        } else {
            ScreenTimeService.shared.enableExtensionRecordSync()
            isEnabled = true
        }
    }) {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill((isEnabled ? Color.green : Color.gray).opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isEnabled ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Extension Record Sync")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(isEnabled ? "Enabled (tap to disable)" : "Disabled (tap to enable)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke((isEnabled ? Color.green : Color.gray).opacity(0.2), lineWidth: 1)
                )
        )
    }
    .buttonStyle(PlainButtonStyle())
}
```

---

## Testing Protocol

### Phase 1: Enable and Monitor (Day 1)

1. **Build and Install**
   - Build app with changes
   - Install on child device

2. **Enable Feature**
   - Go to Settings > Debug
   - Tap "Extension Record Sync" button to enable
   - Verify log: `✅ Extension-based UsageRecord sync ENABLED`

3. **Use Apps**
   - Use 2-3 learning apps for 1-2 minutes each
   - Watch Xcode console for logs

4. **Expected Logs**
   ```
   💾 Created NEW UsageRecord from extension:
      App: Khan Academy
      Usage: 120s (2min)
      Points: 4pts
      Category: learning
      Ready for CloudKit upload
   ```

5. **Verify Core Data**
   - Tap "Manual Upload Test" button
   - Should see: `📊 [DEBUG] Unsynced UsageRecords: 3`

6. **Test Upload**
   - Tap "Manual Upload Test" again
   - Should see: `✅ [UPLOAD] Successfully uploaded 3 records`

7. **Verify CloudKit Dashboard**
   - Open CloudKit Dashboard
   - Navigate to ChildMonitoring zone
   - Query CD_UsageRecord
   - Should see records with correct data

### Phase 2: Parent Device Verification (Day 1)

1. **Check Parent App**
   - Open parent device
   - View child usage dashboard
   - Should see usage data appear

2. **Monitor Updates**
   - Continue using apps on child device
   - Check if parent data updates
   - Should see real-time or near-real-time sync

### Phase 3: Multi-Day Testing (Days 2-7)

1. **Daily Usage Pattern**
   - Use apps normally each day
   - Monitor for duplicates
   - Check CloudKit record count

2. **Expected Behavior**
   - One record per app per day
   - Records update throughout the day
   - No duplicates even if threshold events fire

3. **Edge Cases to Test**
   - App used multiple times per day
   - App used at midnight boundary
   - Child device offline then online
   - Background app usage

### Phase 4: Rollback Test (Day 3)

1. **Disable Feature**
   - Tap "Extension Record Sync" to disable
   - Verify log: `🛑 Extension-based UsageRecord sync DISABLED`

2. **Verify Behavior**
   - Use apps
   - Should NOT see new record creation logs
   - Existing records remain in Core Data
   - No new uploads to CloudKit

3. **Re-enable**
   - Tap button to enable again
   - Verify feature resumes working

---

## Rollback Plan

If issues arise, follow this procedure:

### Immediate Rollback (< 1 minute)

1. **On Child Device:**
   - Go to Settings > Debug
   - Tap "Extension Record Sync" to disable
   - Feature stops immediately

2. **Verify Disabled:**
   - Look for log: `🛑 Extension-based UsageRecord sync DISABLED`
   - Use apps - should NOT see new record creation

### Data Cleanup (if needed)

If duplicate records were created:

```swift
// Add this to ScreenTimeService for cleanup
func cleanupDuplicateUsageRecords() async {
    let context = persistenceController.container.viewContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Fetch all records for today
    let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
    fetchRequest.predicate = NSPredicate(
        format: "deviceID == %@ AND sessionStart >= %@",
        DeviceModeManager.shared.deviceID,
        today as NSDate
    )

    do {
        let records = try context.fetch(fetchRequest)

        // Group by logicalID
        let grouped = Dictionary(grouping: records, by: { $0.logicalID ?? "" })

        for (logicalID, duplicates) in grouped where duplicates.count > 1 {
            // Keep the record with highest totalSeconds
            let sorted = duplicates.sorted { $0.totalSeconds > $1.totalSeconds }
            let toKeep = sorted.first!
            let toDelete = sorted.dropFirst()

            for record in toDelete {
                context.delete(record)
            }

            print("[CLEANUP] Kept 1 of \(duplicates.count) records for \(logicalID)")
        }

        try context.save()
        print("[CLEANUP] ✅ Cleanup complete")
    } catch {
        print("[CLEANUP] ❌ Failed: \(error)")
    }
}
```

---

## Risk Assessment

### Risks Identified

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Duplicate records | Low | Medium | Date range predicate prevents duplicates |
| Existing tracking breaks | Very Low | High | No modification to existing code paths |
| Core Data corruption | Very Low | High | Standard Core Data error handling |
| Feature can't be disabled | Very Low | Medium | Feature flag with instant toggle |
| CloudKit quota exceeded | Low | Low | One record per app per day (same as original design) |

### Why This Is Safe

1. **Additive Only** - Zero changes to existing tracking logic
2. **Feature Flag** - Can disable instantly without code deployment
3. **Deduplication** - Prevents conflicts even if threshold events resume
4. **Tested Code** - Uses proven Core Data and CloudKit patterns
5. **Gradual Rollout** - Can test on one device before enabling for all
6. **Instant Rollback** - One button tap to disable

---

## Success Criteria

- ✅ UsageRecord entities created in Core Data
- ✅ Records visible via "Manual Upload Test" button
- ✅ Records uploaded to CloudKit successfully
- ✅ Records visible in CloudKit Dashboard
- ✅ Parent device displays child usage
- ✅ Updates continue throughout the day
- ✅ No duplicate records created
- ✅ Existing usage tracking remains stable
- ✅ Feature can be toggled on/off reliably

---

## Implementation Checklist

- [ ] Add feature flag check functions to ScreenTimeService
- [ ] Add `syncUsageRecordFromExtensionData()` function
- [ ] Call function from `readExtensionUsageData()`
- [ ] Add debug toggle button to SettingsTabView
- [ ] Build and install on test device
- [ ] Enable feature via debug button
- [ ] Test basic record creation
- [ ] Test upload to CloudKit
- [ ] Verify on parent device
- [ ] Test multi-day usage
- [ ] Test disable/enable toggle
- [ ] Monitor for 7 days
- [ ] Roll out to production if stable

---

## Maintenance Notes

### Monitoring

After deployment, monitor these metrics:

1. **Core Data record count** - Should match number of apps used per day
2. **CloudKit usage** - Should not exceed expected quota
3. **Parent sync latency** - Should update within 30 minutes
4. **Duplicate count** - Should remain at zero

### Future Improvements

Once stable, consider:

1. **Remove Threshold Event Code** - If truly never fires, clean up unused code
2. **Optimize Sync Frequency** - Tune background upload intervals
3. **Add Record Expiration** - Auto-delete records older than 30 days
4. **Batch Updates** - Combine multiple updates into single Core Data save

---

## Document History

| Date | Author | Changes |
|------|--------|---------|
| 2025-12-29 | Claude | Initial draft - Option 1 (safest approach) |

---

## References

- Plan file: `/Users/ameen/.claude/plans/validated-honking-boole.md`
- Diagnostic logs: See conversation history for full diagnostic output
- Related issues: Usage tracking stabilization (weeks of work)
