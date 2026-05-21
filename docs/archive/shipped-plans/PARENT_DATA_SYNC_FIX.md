# Parent Device Data Sync Issue - Investigation & Fix Plan

**Date**: December 28, 2025
**Issue**: Parent device not showing child usage data despite successful pairing
**Status**: Root cause identified, fix plan documented

---

## Table of Contents

1. [Issue Summary](#issue-summary)
2. [Investigation Findings](#investigation-findings)
3. [Root Cause Analysis](#root-cause-analysis)
4. [Fix Implementation Plan](#fix-implementation-plan)
5. [Migration Strategy](#migration-strategy)
6. [Testing Plan](#testing-plan)
7. [Risk Assessment](#risk-assessment)
8. [References](#references)

---

## Issue Summary

### Symptoms

**Parent Device**:
- ✅ Child device appears in device carousel (pairing successful)
- ❌ Dashboard shows no usage data (empty state)
- ❌ Historical reports empty (week/month/year)
- ❌ Manual refresh doesn't load data
- ❌ Error when querying: "SharedDB does not support Zone Wide queries"

**Child Device**:
- ✅ Tracking usage locally (dashboard shows data)
- ✅ Apps properly named via PairingConfigView
- ✅ Paired with parent device for over a week
- ❓ Unknown if data is uploading to CloudKit

---

## Investigation Findings

### Child Device Upload Flow (WORKING ✅)

**File**: `Services/CloudKitSyncService.swift:256-344`

The child device correctly implements CloudKit upload:

```swift
func uploadUsageRecordsToParent(_ records: [UsageRecord]) async throws {
    let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    let sharedDB = container.sharedCloudDatabase  // ✅ Correct database

    // Retrieve zone context from UserDefaults (set during pairing)
    guard
        let zoneName = UserDefaults.standard.string(forKey: "parentSharedZoneID"),
        let zoneOwner = UserDefaults.standard.string(forKey: "parentSharedZoneOwner"),
        let rootName = UserDefaults.standard.string(forKey: "parentSharedRootRecordName")
    else {
        throw NSError(domain: "Missing share context - device may not be paired")
    }

    // Construct zone ID for parent's monitoring zone
    let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)
    let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)

    // Create CloudKit records
    var toSave: [CKRecord] = []
    for item in records {
        let recID = CKRecord.ID(recordName: "UR-\(UUID().uuidString)", zoneID: zoneID)
        let rec = CKRecord(recordType: "CD_UsageRecord", recordID: recID)

        // Link to parent's root record (critical for share hierarchy)
        rec.parent = CKRecord.Reference(recordID: rootID, action: .none)

        // Map fields...
        rec["CD_deviceID"] = item.deviceID
        rec["CD_logicalID"] = item.logicalID
        rec["CD_displayName"] = item.displayName
        rec["CD_sessionStart"] = item.sessionStart
        rec["CD_sessionEnd"] = item.sessionEnd
        rec["CD_totalSeconds"] = Int(item.totalSeconds)
        rec["CD_earnedPoints"] = Int(item.earnedPoints)
        rec["CD_category"] = item.category
        rec["CD_syncTimestamp"] = Date()

        toSave.append(rec)
    }

    // Upload to parent's shared zone
    let (savedRecords, _) = try await sharedDB.modifyRecords(saving: toSave, deleting: [])

    // Mark local records as synced
    for item in records {
        item.isSynced = true
        item.syncTimestamp = Date()
    }
    try context.save()
}
```

**Upload Trigger**:
- **Background Task**: Every 30 minutes via `BGTaskScheduler`
- **Task ID**: `"com.screentimerewards.usage-upload"`
- **File**: `Services/ChildBackgroundSyncService.swift:82-114`

**Zone Context Storage** (during pairing):
- **File**: `Services/DevicePairingService.swift:388-400`
- Child stores in UserDefaults:
  - `parentSharedZoneID` - Zone name
  - `parentSharedZoneOwner` - Parent's iCloud account ID
  - `parentSharedRootRecordName` - Root record linking to share

### Parent Device Query Flow (BROKEN ❌)

**File**: `Services/CloudKitSyncService.swift:363-423`

The parent device attempts to query without zone specification:

```swift
func fetchChildUsageDataFromCloudKit(deviceID: String, dateRange: DateInterval)
    async throws -> [UsageRecord]
{
    let db = container.sharedCloudDatabase  // ✅ Correct database

    // Query predicate filters by deviceID and date
    let schemaPredicate = NSPredicate(
        format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart <= %@",
        deviceID, dateRange.start as NSDate, dateRange.end as NSDate
    )
    let schemaQuery = CKQuery(recordType: "CD_UsageRecord", predicate: schemaPredicate)

    // ❌ PROBLEM: Querying entire shared database without zone
    let (matches, _) = try await db.records(matching: schemaQuery)
    // ERROR: "SharedDB does not support Zone Wide queries"

    return mapUsageMatchResults(matches)
}
```

**CloudKit Error**: `"SharedDB does not support Zone Wide queries"`

This error confirms that:
1. CloudKit's `sharedCloudDatabase` **requires zone-specific queries**
2. You cannot query all shared zones at once
3. The parent must specify **which zone** to query

### Pairing Flow Analysis

**Parent Creates Zone** (`DevicePairingService.swift:84-133`):
```swift
func createMonitoringZoneForChild() async throws -> CKRecordZone.ID {
    let zoneID = CKRecordZone.ID(zoneName: "ChildMonitoring-\(UUID().uuidString)")
    let zone = CKRecordZone(zoneID: zoneID)
    let savedZone = try await privateDB.save(zone)
    return savedZone.zoneID
}
```

**Zone Stored in QR Code** (Line 218):
```swift
let sessionData: [String: Any] = [
    "sessionID": sessionID,
    "sharedZoneID": zoneID.zoneName,  // ✅ Temporarily stored
    // ...
]
```

**Child Receives Zone Info** (Lines 388-400):
```swift
// Child stores zone context in UserDefaults
UserDefaults.standard.set(zoneID.zoneName, forKey: "parentSharedZoneID")
UserDefaults.standard.set(zoneID.ownerName, forKey: "parentSharedZoneOwner")
UserDefaults.standard.set(rootID.recordName, forKey: "parentSharedRootRecordName")
```

**Parent Does NOT Store Zone Info** ❌:
- QR code session expires after 10 minutes
- Zone info NOT persisted to `RegisteredDevice` entity
- No mapping of `childDeviceID → zoneID`

---

## Root Cause Analysis

### The Missing Link

**Problem**: Parent has no persistent storage of which zone belongs to which child device.

**RegisteredDevice Entity** (`Models/RegisteredDevice.swift`):

**Current Fields**:
```swift
@NSManaged public var deviceID: String?
@NSManaged public var deviceName: String?
@NSManaged public var deviceType: String?  // "parent" or "child"
@NSManaged public var childName: String?
@NSManaged public var parentDeviceID: String?
@NSManaged public var registrationDate: Date?
@NSManaged public var lastSyncDate: Date?
@NSManaged public var isActive: Bool
@NSManaged public var subscriptionTier: String?
```

**Missing Fields** ❌:
```swift
// NOT PRESENT - This is the problem!
@NSManaged public var sharedZoneID: String?
@NSManaged public var sharedZoneOwner: String?
```

### Architecture Gap

**Child Device** → **CloudKit Zone** → **Parent Device**

```
┌─────────────┐    Upload to Zone     ┌──────────────────┐    Zone-Specific Query    ┌──────────────┐
│   Child     │ ───────────────────→  │  CloudKit Zone   │ ←────────────────────────  │   Parent     │
│   Device    │                        │ ChildMonitoring- │                            │   Device     │
│             │                        │      ABC123      │                            │              │
└─────────────┘                        └──────────────────┘                            └──────────────┘
     ✅                                        ✅                                              ❌
  Has zone info                         Data stored here                            No zone info!
  in UserDefaults                                                                   Can't query zone
```

**The Gap**:
1. Parent creates unique zone for each child: `"ChildMonitoring-{UUID}"`
2. Child receives zone info during pairing and stores in UserDefaults
3. Child uploads usage records to parent's zone ✅
4. **Parent has NO record of which zone belongs to which child** ❌
5. Parent cannot perform zone-specific queries
6. CloudKit rejects database-wide queries with error

### Why RegisteredDevice Query Works But UsageRecord Query Fails

**RegisteredDevice Query** (`CloudKitSyncService.swift:70-135`):
```swift
let privateDatabase = container.privateCloudDatabase  // Uses private database
let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
let (matches, _) = try await privateDatabase.records(matching: query)
```

**Works because**:
- Uses `privateCloudDatabase`, not `sharedCloudDatabase`
- NSPersistentCloudKitContainer automatically includes shared zones in private DB queries
- CloudKit merges private + shared zones when querying private database

**UsageRecord Query** (`CloudKitSyncService.swift:363-423`):
```swift
let db = container.sharedCloudDatabase  // Uses shared database
let query = CKQuery(recordType: "CD_UsageRecord", predicate: predicate)
let (matches, _) = try await db.records(matching: query)  // ❌ FAILS
```

**Fails because**:
- Queries `sharedCloudDatabase` directly
- SharedDB queries **require zone specification**
- Cannot search across all zones
- Parent doesn't have zone ID to specify

---

## Fix Implementation Plan

### Overview

The fix requires adding zone tracking to the parent device so it can perform zone-specific queries.

### Phase 1: Verify Child Upload (Diagnostic)

**Before implementing fix, confirm child is uploading data:**

1. **Check UserDefaults on child device**:
   - `parentSharedZoneID` - should contain zone name
   - `parentSharedZoneOwner` - should contain parent's account ID
   - `parentSharedRootRecordName` - should contain root record name

2. **Check debug logs** (build in DEBUG mode):
   ```
   [CloudKitSyncService] ===== Uploading Usage Records To Parent's Zone =====
   [CloudKitSyncService] Records to upload: X
   [CloudKitSyncService] Share context found:
     - Zone Name: ChildMonitoring-ABC123
     - Zone Owner: _abc123xyz456...
     - Root Record Name: MS-12345...
   [CloudKitSyncService] ✅ Successfully uploaded X usage records
   ```

3. **Query unsynced records**:
   ```swift
   let request: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
   request.predicate = NSPredicate(format: "isSynced == NO")
   let unsynced = try context.fetch(request)
   // If count > 0, uploads are failing
   ```

4. **Trigger manual upload**:
   ```swift
   await ChildBackgroundSyncService.shared.triggerImmediateUsageUpload()
   ```

### Phase 2: Modify Core Data Schema

**File**: `ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`

**Add attributes to RegisteredDevice entity**:
```xml
<entity name="RegisteredDevice">
    <!-- Existing attributes... -->
    <attribute name="deviceID" optional="YES" attributeType="String"/>
    <attribute name="deviceName" optional="YES" attributeType="String"/>
    <attribute name="deviceType" optional="YES" attributeType="String"/>
    <attribute name="parentDeviceID" optional="YES" attributeType="String"/>

    <!-- NEW: Add zone tracking fields -->
    <attribute name="sharedZoneID" optional="YES" attributeType="String"/>
    <attribute name="sharedZoneOwner" optional="YES" attributeType="String"/>

    <!-- Existing attributes... -->
</entity>
```

**Increment model version**:
- Create new model version in Xcode
- Set as current version
- Enable lightweight migration in Core Data stack

**Regenerate NSManagedObject subclass** or manually add to `RegisteredDevice+CoreDataProperties.swift`:
```swift
@NSManaged public var sharedZoneID: String?
@NSManaged public var sharedZoneOwner: String?
```

### Phase 3: Store Zone Info During Pairing (Parent Side)

**File**: `Services/DevicePairingService.swift`

**Modify `createPairingSession()` around line 240**:

After creating share, store zone info in session data (already partially done):
```swift
// After line 218 - Store zone owner too
let sessionData: [String: Any] = [
    "sessionID": sessionID,
    "verificationToken": verificationToken,
    "parentDeviceID": DeviceModeManager.shared.deviceID,
    "parentDeviceName": DeviceModeManager.shared.deviceName,
    "sharedZoneID": zoneID.zoneName,
    "sharedZoneOwner": zoneID.ownerName,  // ✅ ADD THIS
    "shareURL": share.url?.absoluteString ?? "",
    "createdAt": Date(),
    "expiresAt": Date().addingTimeInterval(600)
]
UserDefaults.standard.set(sessionData, forKey: "pairingSession_\(sessionID)")
```

Also store in QR payload so child can send back during registration:
```swift
// Modify PairingPayload encoding to include zoneOwner
let payload = PairingPayload(
    parentDeviceID: parentDeviceID,
    verificationToken: verificationToken,
    shareURL: shareURL,
    sharedZoneID: zoneID.zoneName,
    sharedZoneOwner: zoneID.ownerName,  // ✅ ADD THIS
    timestamp: Date()
)
```

### Phase 4: Send Zone Info During Child Registration

**File**: `Services/DevicePairingService.swift:439-461`

**Modify `registerInParentSharedZone()`**:

When child registers with parent, include zone information in the device record:
```swift
func registerInParentSharedZone(...) async throws {
    // Existing code creates deviceRecord...

    // After line 448, add zone fields to CloudKit record
    deviceRecord["CD_deviceID"] = deviceID as CKRecordValue
    deviceRecord["CD_deviceName"] = deviceName as CKRecordValue
    deviceRecord["CD_deviceType"] = "child" as CKRecordValue
    deviceRecord["CD_parentDeviceID"] = parentDeviceID as CKRecordValue

    // ✅ ADD THESE: Include zone info so parent receives it via sync
    deviceRecord["CD_sharedZoneID"] = zoneID.zoneName as CKRecordValue
    deviceRecord["CD_sharedZoneOwner"] = zoneID.ownerName as CKRecordValue

    // Save to parent's shared database
    let (savedRecords, _) = try await sharedDatabase.modifyRecords(saving: [deviceRecord], deleting: [])
}
```

This ensures the parent receives zone info via NSPersistentCloudKitContainer automatic sync.

### Phase 5: Extract Zone Info on Parent Side

**File**: `Services/CloudKitSyncService.swift:137-174`

**Modify `convertToRegisteredDevice()`**:

Extract zone fields from CloudKit record:
```swift
private func convertToRegisteredDevice(_ record: CKRecord) -> RegisteredDevice {
    let entity = NSEntityDescription.entity(forEntityName: "RegisteredDevice",
                                           in: persistenceController.container.viewContext)!
    let device = RegisteredDevice(entity: entity, insertInto: nil)

    // Existing field extraction...
    device.deviceID = record["CD_deviceID"] as? String
    device.deviceName = record["CD_deviceName"] as? String
    device.deviceType = record["CD_deviceType"] as? String
    device.parentDeviceID = record["CD_parentDeviceID"] as? String
    device.registrationDate = record["CD_registrationDate"] as? Date
    device.isActive = (record["CD_isActive"] as? Int == 1)

    // ✅ ADD THESE: Extract zone information
    device.sharedZoneID = record["CD_sharedZoneID"] as? String
    device.sharedZoneOwner = record["CD_sharedZoneOwner"] as? String

    #if DEBUG
    print("[CloudKitSyncService] Extracted zone info:")
    print("  - Zone ID: \(device.sharedZoneID ?? "nil")")
    print("  - Zone Owner: \(device.sharedZoneOwner ?? "nil")")
    #endif

    return device
}
```

### Phase 6: Update Query to Use Zone

**File**: `Services/CloudKitSyncService.swift:363-423`

**Rewrite `fetchChildUsageDataFromCloudKit()` with zone parameter**:

```swift
func fetchChildUsageDataFromCloudKit(
    deviceID: String,
    dateRange: DateInterval,
    zoneID: CKRecordZone.ID  // ✅ NEW PARAMETER
) async throws -> [UsageRecord] {
    #if DEBUG
    print("[CloudKitSyncService] ===== Fetching Child Usage Data From CloudKit =====")
    print("[CloudKitSyncService] Device ID: \(deviceID)")
    print("[CloudKitSyncService] Zone: \(zoneID.zoneName)")
    print("[CloudKitSyncService] Zone Owner: \(zoneID.ownerName)")
    print("[CloudKitSyncService] Date Range: \(dateRange.start) to \(dateRange.end)")
    #endif

    let db = container.sharedCloudDatabase

    let schemaPredicate = NSPredicate(
        format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart <= %@",
        deviceID, dateRange.start as NSDate, dateRange.end as NSDate
    )
    let schemaQuery = CKQuery(recordType: "CD_UsageRecord", predicate: schemaPredicate)

    do {
        #if DEBUG
        print("[CloudKitSyncService] Querying zone: \(zoneID.zoneName)...")
        #endif

        // ✅ CRITICAL FIX: Use zone-specific query
        let (matches, _) = try await db.records(
            matching: schemaQuery,
            inZoneWith: zoneID,  // Specify zone!
            desiredKeys: nil,
            resultsLimit: CKQueryOperation.maximumResults
        )

        let records = mapUsageMatchResults(matches)

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(records.count) usage records in zone")
        for record in records.prefix(5) {
            print("[CloudKitSyncService]   \(record.displayName ?? "nil") | \(record.totalSeconds)s | \(record.earnedPoints) pts")
        }
        #endif

        return records

    } catch let ckErr as CKError {
        #if DEBUG
        print("[CloudKitSyncService] ❌ CloudKit error: \(ckErr)")
        #endif

        // Handle zone-specific errors
        if ckErr.code == .zoneNotFound {
            print("[CloudKitSyncService] Zone not found: \(zoneID.zoneName)")
            return []  // Return empty, zone might not exist yet
        }

        throw ckErr
    }
}
```

### Phase 7: Update ViewModel to Pass Zone

**File**: `ViewModels/ParentRemoteViewModel.swift:92-143`

**Modify `loadChildData()` to construct and pass zone ID**:

```swift
func loadChildData(for device: RegisteredDevice) async {
    isLoading = true
    errorMessage = nil

    guard let deviceID = device.deviceID else {
        errorMessage = "Invalid device ID"
        isLoading = false
        return
    }

    // ✅ NEW: Construct zone ID from RegisteredDevice
    guard let zoneName = device.sharedZoneID,
          let zoneOwner = device.sharedZoneOwner else {
        #if DEBUG
        print("[ParentRemoteViewModel] ⚠️ Missing zone info for device: \(deviceID)")
        print("[ParentRemoteViewModel]   Zone ID: \(device.sharedZoneID ?? "nil")")
        print("[ParentRemoteViewModel]   Zone Owner: \(device.sharedZoneOwner ?? "nil")")
        #endif
        errorMessage = "Zone information missing. Please re-pair this device to enable data sync."
        isLoading = false
        return
    }

    let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)

    #if DEBUG
    print("[ParentRemoteViewModel] Loading data for device: \(deviceID)")
    print("[ParentRemoteViewModel] Using zone: \(zoneName)")
    #endif

    let dateRange = DateInterval(start: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
                                 end: Date())

    do {
        // ✅ Pass zone ID to query
        usageRecords = try await cloudKitService.fetchChildUsageDataFromCloudKit(
            deviceID: deviceID,
            dateRange: dateRange,
            zoneID: zoneID  // Zone-specific query
        )

        // Existing aggregation code...
        categoryUsage = cloudKitService.aggregateByCategory(usageRecords)

        // Load daily summaries...
        dailySummaries = try await cloudKitService.fetchDailySummariesFromCloudKit(
            deviceID: deviceID,
            dateRange: dateRange,
            zoneID: zoneID  // Also update daily summaries query
        )

        #if DEBUG
        print("[ParentRemoteViewModel] ✅ Loaded \(usageRecords.count) usage records")
        #endif

    } catch {
        #if DEBUG
        print("[ParentRemoteViewModel] ❌ Error loading child data: \(error)")
        #endif
        errorMessage = cloudKitService.handleCloudKitError(error)
    }

    isLoading = false
}
```

**Also update `fetchDailySummariesFromCloudKit()`** to accept `zoneID` parameter.

---

## Migration Strategy

### Problem: Existing Paired Devices

Devices paired before this fix won't have zone information in `RegisteredDevice`.

### Solution Options

#### Option 1: Force Re-Pairing (Recommended - Simplest)

**Implementation**:
```swift
func loadChildData(for device: RegisteredDevice) async {
    // Check if zone info exists
    guard device.sharedZoneID != nil, device.sharedZoneOwner != nil else {
        errorMessage = """
        This device was paired before zone tracking was implemented.

        Please unpair and re-pair this device to enable data sync.

        Steps:
        1. On child device, go to Settings → Unpair from Parent
        2. On parent device, generate new QR code
        3. On child device, scan QR code to re-pair
        """
        return
    }

    // Continue with query...
}
```

**Pros**:
- Simple to implement
- Guarantees correct zone info
- Clean state for users

**Cons**:
- Requires user action
- Temporary disruption

#### Option 2: Fetch Zones and Auto-Match (Complex)

**Implementation**:
```swift
func migrateExistingDevice(_ device: RegisteredDevice) async throws {
    guard device.sharedZoneID == nil else { return }  // Already has zone

    // Fetch all accessible zones
    let zones = try await container.sharedCloudDatabase.allRecordZones()

    // For each zone, query for RegisteredDevice with matching deviceID
    for zone in zones {
        let predicate = NSPredicate(format: "CD_deviceID == %@", device.deviceID!)
        let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)

        let (matches, _) = try await container.sharedCloudDatabase.records(
            matching: query,
            inZoneWith: zone.zoneID
        )

        if !matches.isEmpty {
            // Found the zone for this device
            device.sharedZoneID = zone.zoneID.zoneName
            device.sharedZoneOwner = zone.zoneID.ownerName
            try persistenceController.container.viewContext.save()
            break
        }
    }
}
```

**Pros**:
- No user action required
- Automatic migration

**Cons**:
- Complex implementation
- Requires querying all zones (slow)
- May hit CloudKit rate limits

#### Option 3: Hybrid Approach

**Implementation**:
1. Try to auto-migrate using Option 2
2. If fails or takes too long, fall back to Option 1 (re-pairing prompt)

**Recommended Approach**: Start with Option 1 (re-pairing) for simplicity and reliability.

---

## Testing Plan

### 1. Verify Child Upload

**Before implementing fix:**

- [ ] Build child device in DEBUG mode
- [ ] Check Xcode console for upload logs
- [ ] Verify `[CloudKitSyncService] ✅ Successfully uploaded X usage records`
- [ ] Check UserDefaults has `parentSharedZoneID`, `parentSharedZoneOwner`, `parentSharedRootRecordName`
- [ ] Query Core Data for unsynced records (should be 0)

### 2. Test Core Data Migration

**After schema change:**

- [ ] Build app with new schema version
- [ ] Verify lightweight migration succeeds
- [ ] Check existing RegisteredDevice records load correctly
- [ ] Verify new fields are `nil` for existing records
- [ ] Verify new fields populate for new pairings

### 3. Test New Pairing Flow

**With fix implemented:**

- [ ] Unpair devices
- [ ] Parent generates new QR code
- [ ] Child scans and accepts pairing
- [ ] Verify debug logs show zone info being stored
- [ ] Check RegisteredDevice has `sharedZoneID` and `sharedZoneOwner`
- [ ] Verify child can upload (check logs)
- [ ] Verify parent can query (check logs for "Querying zone: ChildMonitoring-XXX")

### 4. Test Parent Data Display

**After pairing with zone info:**

- [ ] Select child device from carousel
- [ ] Verify today's usage summary appears
- [ ] Check historical reports (week/month/year)
- [ ] Verify per-app usage details
- [ ] Test manual refresh
- [ ] Check all time period selectors

### 5. Test Multiple Children

**With 2+ child devices:**

- [ ] Pair second child device
- [ ] Verify each has different zone IDs
- [ ] Switch between devices in carousel
- [ ] Verify data isolation (no cross-contamination)
- [ ] Check each device queries correct zone

### 6. Test Error Handling

**Edge cases:**

- [ ] Device with missing zone info (show re-pair message)
- [ ] Zone not found error (graceful empty state)
- [ ] Network error during query (error message)
- [ ] CloudKit authentication failure (error message)

### 7. Performance Testing

**Load testing:**

- [ ] Test with 100+ usage records
- [ ] Measure query response time (should be < 3 seconds)
- [ ] Test with multiple child devices
- [ ] Verify no UI freezing during load

---

## Risk Assessment

### Risk Level: 🟡 MEDIUM

### Why Medium Risk

**Schema Changes**:
- Core Data model modification requires migration
- Potential for migration failures on user devices
- Need to handle both new and old data formats

**Multi-File Impact**:
- 5+ files being modified
- Changes span pairing, query, and display flows
- Increased testing surface area

**User Disruption**:
- Existing users may need to re-pair devices
- Temporary loss of access to historical data during re-pair
- User education required

### Mitigation Strategies

1. **Core Data Migration**:
   - Use lightweight migration (automatic)
   - Test migration thoroughly with existing data
   - Add migration validation in app startup

2. **Backward Compatibility**:
   - Gracefully handle missing zone info
   - Clear error messages for users
   - Provide re-pairing instructions

3. **Gradual Rollout**:
   - Beta test with small user group
   - Monitor CloudKit error logs
   - Prepare rollback plan

4. **User Communication**:
   - Release notes explaining re-pairing requirement
   - In-app guidance for migration
   - Support documentation

### Rollback Plan

If critical issues arise:

1. **Immediate Rollback**:
   - Revert to previous app version
   - Restore previous Core Data schema
   - Remove zone ID parameters from code

2. **Data Impact**:
   - Users who re-paired during fix version may need to re-pair again
   - No data loss (CloudKit records unchanged)
   - Historical data preserved

3. **Timeline**:
   - Rollback can be executed within 1 hour
   - App Store review for emergency update (24-48 hours)

---

## Success Criteria

### Technical Validation

- ✅ Child uploads data to CloudKit successfully
- ✅ RegisteredDevice entity has `sharedZoneID` and `sharedZoneOwner` fields
- ✅ Zone info persists across app restarts
- ✅ Parent queries specific zones without "Zone Wide" error
- ✅ Zone-specific queries return correct data
- ✅ Multiple child devices work independently

### User Experience

- ✅ Parent dashboard displays child usage data
- ✅ All historical reports show data (week/month/year)
- ✅ Per-app usage details render correctly
- ✅ Manual refresh works
- ✅ Switching between child devices works smoothly
- ✅ Clear error messages for missing zone info
- ✅ Re-pairing flow is smooth and well-documented

### Performance

- ✅ Query response time < 3 seconds (typical)
- ✅ No UI freezing during data load
- ✅ Smooth scrolling in usage lists
- ✅ Background sync completes within 30 minutes

---

## References

### Modified Files

1. **Core Data Schema**:
   - `ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`
   - Add `sharedZoneID` and `sharedZoneOwner` to RegisteredDevice entity

2. **Models**:
   - `Models/RegisteredDevice+CoreDataProperties.swift`
   - Add properties for new fields

3. **Services**:
   - `Services/DevicePairingService.swift`
     - Store zone owner in pairing session
     - Send zone info during child registration
   - `Services/CloudKitSyncService.swift`
     - Extract zone info in `convertToRegisteredDevice()`
     - Add zone parameter to `fetchChildUsageDataFromCloudKit()`
     - Use `db.records(matching:inZoneWith:)`
     - Add zone parameter to `fetchDailySummariesFromCloudKit()`

4. **ViewModels**:
   - `ViewModels/ParentRemoteViewModel.swift`
     - Construct zone ID from RegisteredDevice
     - Pass zone ID to CloudKitSyncService methods
     - Handle missing zone info with clear error

### CloudKit Documentation

- [CKDatabase.records(matching:inZoneWith:)](https://developer.apple.com/documentation/cloudkit/ckdatabase/3003358-records)
- [CKRecordZone.ID](https://developer.apple.com/documentation/cloudkit/ckrecordzone/id)
- [CloudKit Sharing](https://developer.apple.com/documentation/cloudkit/shared_records)

### Related Documentation

- `PARENT_DEVICE_IMPLEMENTATION_REVIEW.md` - Original implementation review
- `ScreenTimeRewards.xcdatamodeld` - Core Data schema
- User Guide (to be updated) - Re-pairing instructions

---

## Conclusion

The root cause of the parent device data sync issue is an **architectural gap**: the parent has no persistent storage of which CloudKit zone belongs to which child device.

CloudKit's shared database requires zone-specific queries via `db.records(matching:inZoneWith:)`, but the parent's `RegisteredDevice` entity lacks the `sharedZoneID` and `sharedZoneOwner` fields needed to construct zone identifiers.

The fix requires:
1. Adding zone tracking fields to Core Data schema
2. Storing zone information during pairing
3. Using zone-specific queries instead of database-wide queries

While not a simple one-line fix, this enhancement provides proper zone-aware architecture for CloudKit sharing and enables reliable parent-child data synchronization.

**Estimated Implementation Time**: 4-6 hours
**Testing Time**: 2-3 hours
**Total**: 6-9 hours

**Recommended Next Steps**:
1. Verify child upload is working (Phase 1)
2. Implement schema changes (Phase 2)
3. Update pairing flow (Phases 3-4)
4. Implement zone-specific queries (Phases 5-7)
5. Thorough testing with multiple devices
6. Beta test with users before full release
