# Dev Agent Task List: CloudKit Cross-Account Pairing

**Sprint Goal:** Implement CloudKit private database sharing to enable parent visibility of child devices across different iCloud accounts.

**Estimated Time:** 4-6 hours
**Priority:** HIGH - Blocking feature
**Dependencies:** Current local pairing implementation (complete)

---

## Task Breakdown

### 🔴 TASK 1: Create Monitoring Zone with Share (2 hours)

**File:** `DevicePairingService.swift`

**What to Build:**
A function that creates a dedicated CloudKit zone in the parent's private database and generates a CKShare for cross-account access.

**Requirements:**
```swift
func createMonitoringZoneForChild() async throws -> (zoneID: CKRecordZone.ID, share: CKShare) {
    // 1. Create unique zone for this pairing session
    // 2. Create MonitoringSession root record in that zone
    // 3. Create CKShare from root record
    // 4. Configure share permissions for write access
    // 5. Save zone, root record, and share to private database
    // 6. Return zone ID and share for QR code generation
}
```

**Success Criteria:**
- [ ] Function runs without errors
- [ ] Zone appears in CloudKit Dashboard
- [ ] Share has valid URL
- [ ] Share allows write permissions (verify in Dashboard)

**Key Questions to Research:**
1. How to set CKShare permissions for anonymous participants?
2. Does `share.publicPermission = .readWrite` work for private shares?
3. Or do we need to add explicit participants?

**Testing:**
```swift
// Run on parent device
let (zoneID, share) = try await createMonitoringZoneForChild()
print("Zone: \(zoneID.zoneName)")
print("Share URL: \(share.url?.absoluteString ?? "nil")")
// Check CloudKit Dashboard for zone + share
```

---

### 🟡 TASK 2: Update QR Code Generation (30 min)

**Files:**
- `DevicePairingService.swift` (PairingPayload struct)
- `ParentPairingView.swift` (call new function)

**What to Change:**

**2.1: Update PairingPayload**
```swift
struct PairingPayload: Codable {
    let shareURL: String              // Now contains real CKShare URL
    let parentDeviceID: String
    let verificationToken: String
    let sharedZoneID: String          // NEW: Zone name for child to use
    let timestamp: Date
}
```

**2.2: Update createLocalPairingSession**
```swift
// OLD:
func createLocalPairingSession() -> (sessionID: String, verificationToken: String)

// NEW:
func createPairingSession() async throws -> (sessionID: String, verificationToken: String, share: CKShare, zoneID: CKRecordZone.ID)
```

**2.3: Update ParentPairingView**
```swift
// In generateQRCode():
Task {
    do {
        let (sessionID, token, share, zoneID) = try await pairingService.createPairingSession()
        let qrImage = pairingService.generatePairingQRCode(
            share: share,
            zoneID: zoneID,
            verificationToken: token
        )
        // Display QR code
    } catch {
        // Show error
    }
}
```

**Success Criteria:**
- [ ] QR code contains valid share URL
- [ ] Payload includes sharedZoneID
- [ ] Parent can generate QR code without errors

---

### 🟡 TASK 3: Implement Share Acceptance (1.5 hours)

**File:** `DevicePairingService.swift`

**What to Build:**

**3.1: Accept Share Function**
```swift
func acceptParentShareAndRegister(from payload: PairingPayload) async throws {
    // 1. Parse share URL from payload
    guard let shareURL = URL(string: payload.shareURL) else { throw ... }

    // 2. Fetch share metadata
    let metadata = try await container.fetchShareMetadata(with: shareURL)

    // 3. Accept the share
    try await container.accept(metadata)

    // 4. Save parent device ID locally
    UserDefaults.standard.set(payload.parentDeviceID, forKey: "parentDeviceID")
    UserDefaults.standard.set(payload.sharedZoneID, forKey: "parentSharedZoneID")

    // 5. Register in parent's shared zone
    try await registerInParentSharedZone(
        zoneID: metadata.rootRecordID.zoneID,
        parentDeviceID: payload.parentDeviceID
    )
}
```

**3.2: Register in Shared Zone**
```swift
func registerInParentSharedZone(zoneID: CKRecordZone.ID, parentDeviceID: String) async throws {
    // CRITICAL: Use sharedCloudDatabase (not privateCloudDatabase)
    let sharedDatabase = container.sharedCloudDatabase

    // Create device record in PARENT'S shared zone
    let deviceRecordID = CKRecord.ID(
        recordName: "device-\(DeviceModeManager.shared.deviceID)",
        zoneID: zoneID  // Parent's zone!
    )

    let deviceRecord = CKRecord(recordType: "CD_RegisteredDevice", recordID: deviceRecordID)
    deviceRecord["CD_deviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
    deviceRecord["CD_deviceName"] = DeviceModeManager.shared.deviceName as CKRecordValue
    deviceRecord["CD_deviceType"] = "child" as CKRecordValue
    deviceRecord["CD_parentDeviceID"] = parentDeviceID as CKRecordValue
    deviceRecord["CD_registrationDate"] = Date() as CKRecordValue
    deviceRecord["CD_isActive"] = 1 as CKRecordValue

    // Save to SHARED database
    let savedRecord = try await sharedDatabase.save(deviceRecord)

    print("✅ Child registered in parent's zone: \(savedRecord.recordID)")
}
```

**Success Criteria:**
- [ ] Share acceptance succeeds (no permission errors)
- [ ] Child can write to shared zone
- [ ] Device record appears in parent's CloudKit zone (check Dashboard)
- [ ] No "WRITE operation not permitted" errors

**Testing:**
1. Child scans QR code
2. Check console for "✅ Child registered"
3. Open CloudKit Dashboard (parent's account)
4. Navigate to parent's zone
5. Verify CD_RegisteredDevice record exists

---

### 🟡 TASK 4: Update Parent Query (1 hour)

**File:** `CloudKitSyncService.swift`

**What to Change:**

```swift
func fetchLinkedChildDevices() async throws -> [RegisteredDevice] {
    // Query parent's PRIVATE database (shared zones are stored there)
    let privateDatabase = container.privateCloudDatabase
    let parentDeviceID = DeviceModeManager.shared.deviceID

    // Query for child devices across all shared zones
    let predicate = NSPredicate(
        format: "CD_deviceType == %@ AND CD_parentDeviceID == %@",
        "child", parentDeviceID
    )
    let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
    query.sortDescriptors = [NSSortDescriptor(key: "CD_registrationDate", ascending: false)]

    // Query all zones (including shared zones)
    let (matchResults, _) = try await privateDatabase.records(matching: query)

    var devices: [RegisteredDevice] = []

    for (_, result) in matchResults {
        switch result {
        case .success(let record):
            // Convert CKRecord to RegisteredDevice
            let device = convertToRegisteredDevice(record)
            devices.append(device)
        case .failure(let error):
            print("Error fetching record: \(error)")
        }
    }

    print("✅ Found \(devices.count) child device(s)")
    return devices
}
```

**Helper Function:**
```swift
private func convertToRegisteredDevice(_ record: CKRecord) -> RegisteredDevice {
    let context = persistenceController.container.viewContext
    let device = RegisteredDevice(context: context)

    device.deviceID = record["CD_deviceID"] as? String
    device.deviceName = record["CD_deviceName"] as? String
    device.deviceType = record["CD_deviceType"] as? String
    device.parentDeviceID = record["CD_parentDeviceID"] as? String
    device.registrationDate = record["CD_registrationDate"] as? Date
    device.isActive = (record["CD_isActive"] as? Int) != 0

    // Don't save to context - temporary objects for display
    context.rollback()

    return device
}
```

**Success Criteria:**
- [ ] Parent queries own private database
- [ ] Query returns child devices from shared zones
- [ ] Dashboard displays child device info
- [ ] No query errors

**Testing:**
1. Complete pairing (Tasks 1-3)
2. Parent refreshes dashboard
3. Verify child device appears
4. Verify device name, ID, status shown correctly

---

### 🟢 TASK 5: Update ChildPairingView (15 min)

**File:** `ChildPairingView.swift`

**What to Change:**

```swift
// In pairWithParent() function:
private func pairWithParent(jsonString: String) {
    isPairing = true
    errorMessage = nil

    Task {
        do {
            guard let payload = pairingService.parsePairingQRCode(jsonString) else {
                throw NSError(domain: "PairingError", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid QR code"])
            }

            // Call NEW function (not acceptParentPairing)
            try await pairingService.acceptParentShareAndRegister(from: payload)

            await MainActor.run {
                self.isPairing = false
                self.showSuccessAlert = true
            }
        } catch {
            await MainActor.run {
                self.isPairing = false
                self.errorMessage = "Failed to pair: \(error.localizedDescription)"
            }
        }
    }
}
```

**Success Criteria:**
- [ ] Calls new share acceptance function
- [ ] Shows success alert on completion
- [ ] Shows error message on failure

---

## Testing Checklist

### Unit Tests
- [ ] Test zone creation (Task 1)
- [ ] Test share creation (Task 1)
- [ ] Test share acceptance (Task 3)
- [ ] Test device registration (Task 3)
- [ ] Test parent query (Task 4)

### Integration Tests
- [ ] End-to-end pairing flow
- [ ] Parent generates QR → Child scans → Parent sees device
- [ ] Test with 2 child devices
- [ ] Test error handling (invalid QR, expired share)

### Manual Tests
- [ ] Pairing works on different iCloud accounts
- [ ] Child device appears on parent dashboard
- [ ] Device info accurate (name, ID, date)
- [ ] CloudKit Dashboard shows correct records

---

## Common Issues & Solutions

### Issue 1: "WRITE operation not permitted" (Error 10)
**Cause:** Share doesn't have write permissions
**Solution:** Check CKShare configuration in Task 1
```swift
// Ensure this is set:
share.publicPermission = .readWrite  // For private shares?
// OR
// Add explicit participant with write permission
```

### Issue 2: Query returns 0 devices
**Cause:** Querying wrong database or zone
**Solution:**
- Parent should query `privateCloudDatabase` (not shared)
- Shared zones are stored in private database
- Don't specify zone in query (queries all zones)

### Issue 3: "Unknown Item" (Error 11)
**Cause:** Querying wrong database
**Solution:** Child writes to `sharedCloudDatabase`, parent reads from `privateCloudDatabase`

### Issue 4: Share URL is nil
**Cause:** Share not saved to CloudKit yet
**Solution:** Ensure share is saved before generating QR code
```swift
let share = try await database.save(share)
// Now share.url is available
```

---

## Definition of Done

✅ **Task Complete When:**
1. All 5 tasks implemented
2. All tests passing
3. End-to-end pairing works
4. Parent sees child device immediately
5. No console errors during pairing
6. Code reviewed and committed

✅ **Feature Complete When:**
1. Parent generates QR code with share
2. Child scans and accepts share
3. Child registers in parent's shared zone
4. Parent dashboard shows child device
5. Device info accurate and complete
6. Works reliably across different iCloud accounts

---

## Handoff Notes

### Current State
- Local pairing implemented (QR code generation works)
- Child device registration works (in child's own DB)
- Parent query works (queries own DB, finds nothing)
- All infrastructure in place (CloudKit, Core Data, etc.)

### What Needs to Change
- Parent creates CKShare (Task 1)
- QR contains share URL (Task 2)
- Child accepts share (Task 3)
- Child writes to parent's zone (Task 3)
- Parent queries shared zones (Task 4)

### Files to Modify
1. `DevicePairingService.swift` - Main changes (Tasks 1, 2, 3)
2. `CloudKitSyncService.swift` - Query changes (Task 4)
3. `ParentPairingView.swift` - UI update (Task 2)
4. `ChildPairingView.swift` - Function call update (Task 5)

### Key Concepts to Understand
- CloudKit zones (private database)
- CKShare (private sharing, not public)
- sharedCloudDatabase (child's view of shared zones)
- privateCloudDatabase (parent's view, includes shared zones)
- Cross-account access (different iCloud IDs)

---

## Support Resources

**Documentation:**
- `CROSS_ACCOUNT_PAIRING_STATUS.md` - Full technical spec
- [Apple CloudKit Sharing](https://developer.apple.com/documentation/cloudkit/shared_records)

**Ask for Help If:**
- CKShare permissions unclear after 1 hour research
- Write errors persist after following docs
- Query returns unexpected results
- Any blocker lasting >2 hours

**Report Progress:**
- Complete each task checkbox
- Update this document with findings
- Note any deviations from plan
- Document new issues discovered

---

**Start with Task 1 and work sequentially. Good luck! 🚀**

---

**Document Owner:** PM
**Assignee:** Dev Agent
**Status:** Ready for Implementation
**Last Updated:** October 29, 2025
