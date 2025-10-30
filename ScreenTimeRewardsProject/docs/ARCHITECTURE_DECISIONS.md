# Architecture Decision Record: Cross-Account Device Pairing

**Date:** October 29, 2025
**Status:** APPROVED
**Decision Makers:** PM, Dev Team
**Impact:** HIGH - Core feature architecture

---

## Decision Summary

**We will use CloudKit Private Database Sharing for cross-account device pairing and data synchronization.**

This decision replaces earlier approaches that attempted to use:
1. ❌ Public CloudKit database (permission errors)
2. ❌ Local-only pairing (no visibility)

---

## Context and Problem Statement

### The Challenge
We need parent and child devices to:
- Pair securely using QR codes
- Work with **different iCloud accounts** (cross-account)
- Allow child device to send usage data to parent
- Allow parent to see child device and data immediately
- Maintain security and privacy

### Why Previous Solutions Failed

**Attempt 1: CloudKit Public Database**
- Problem: Public database is READ-ONLY for non-developer users
- Error: "WRITE operation not permitted" (Error 10/2007)
- Why: Apple restricts public database writes for security reasons
- Conclusion: Cannot use for pairing records or device data

**Attempt 2: Local-Only Pairing**
- Problem: Each device has isolated private CloudKit database
- Result: Child pairs successfully but parent can't see child device
- Why: Parent queries own database, child's data is in different account's database
- Conclusion: Works for pairing handshake, fails for visibility

### Requirements

**Must Have:**
- Cross-account support (different iCloud IDs)
- Secure pairing (QR code + verification)
- Immediate visibility (no delays >10 seconds)
- Write permissions for child (send usage data)
- Read permissions for parent (view child data)

**Must Not:**
- Require same iCloud account (defeats purpose)
- Use public database (permission issues)
- Require manual iCloud ID entry (UX issue)
- Need server infrastructure (cost/complexity)

---

## Decision

### Selected Solution: CloudKit Private Sharing

Use CloudKit's **private database sharing** feature with the following architecture:

```
Parent Device (iCloud Account A)
├─ Private CloudKit Database
│  ├─ Custom Zone: "ChildMonitoring-{UUID}"
│  ├─ Root Record: MonitoringSession
│  ├─ CKShare: Provides write access to child
│  └─ Child's Records: RegisteredDevice, UsageRecords
│     └─ Written by child via share permissions
│
└─ Parent queries OWN database → sees child's data

Child Device (iCloud Account B)
├─ Accepts CKShare from parent
├─ Gains WRITE access to parent's shared zone
└─ Writes to sharedCloudDatabase
   └─ Data appears in parent's private database
```

### How It Works

**Step 1: Pairing Initiation**
- Parent creates custom CloudKit zone in private database
- Parent creates MonitoringSession root record
- Parent creates CKShare with write permissions
- Parent generates QR code with share URL

**Step 2: Pairing Acceptance**
- Child scans QR code containing share URL
- Child accepts share using `CKContainer.accept(shareMetadata)`
- Child gains write access to parent's shared zone

**Step 3: Device Registration**
- Child creates RegisteredDevice record in parent's shared zone
- Uses `sharedCloudDatabase` (child's view of parent's zone)
- Record appears in parent's private database immediately

**Step 4: Data Synchronization**
- Child creates UsageRecords in parent's shared zone
- Parent queries own private database
- Sees child's data without cross-account queries
- NSPersistentCloudKitContainer handles sync automatically

---

## Rationale

### Why This Solution

**✅ Solves Cross-Account Problem**
- All data lives in parent's private database
- Child writes via share permissions
- Parent reads from own database (no cross-account access needed)

**✅ Proper Permissions Model**
- CKShare provides controlled write access
- Only authorized children can write
- Parent maintains full control (can revoke share)

**✅ Immediate Visibility**
- No sync delays between databases
- Child writes directly to parent's zone
- Parent queries own database for instant access

**✅ Secure by Design**
- Share URL in QR code expires after use
- Verification token prevents unauthorized pairing
- Each child has separate isolated zone

**✅ Apple Ecosystem Native**
- Uses official CloudKit sharing APIs
- Supported by NSPersistentCloudKitContainer
- No workarounds or hacks required

**✅ Scalable Architecture**
- Multiple children: Create separate zone per child
- Efficient queries: Parent queries own database
- Offline support: Queue writes when offline

### Why Not Alternatives

**Alternative 1: Custom Backend Server**
- ❌ Additional cost and maintenance
- ❌ Privacy concerns (data on third-party server)
- ❌ Not leveraging Apple's infrastructure
- ❌ Slower than direct CloudKit sync

**Alternative 2: iCloud Drive File Sharing**
- ❌ Not designed for structured data
- ❌ Slower sync (file-based, not record-based)
- ❌ No query capabilities
- ❌ More complex conflict resolution

**Alternative 3: Same iCloud Account Requirement**
- ❌ Not practical for families
- ❌ Privacy concerns (sharing Apple ID)
- ❌ Against Apple guidelines
- ❌ Major UX limitation

**Alternative 4: Local Network Sync (Multipeer)**
- ❌ Requires devices on same WiFi
- ❌ No remote monitoring capability
- ❌ Complex to implement reliably
- ❌ Doesn't meet product requirements

---

## Implementation Details

### Key Components

**1. DevicePairingService**
- Creates monitoring zone and share (parent)
- Accepts share and registers device (child)
- Handles share URL generation and parsing

**2. CloudKitSyncService**
- Queries shared zones for child devices
- Fetches usage data from child's records
- Handles sync operations and conflicts

**3. ScreenTimeService**
- Creates usage records in shared zone
- Tags records with proper zone ID
- Works with NSPersistentCloudKitContainer

### Technical Specifications

**CloudKit Zone Structure:**
```
Private Database (Parent)
└─ Custom Zone: "ChildMonitoring-{childDeviceID}"
   ├─ MonitoringSession (Root Record)
   │  └─ CKShare (provides access)
   ├─ CD_RegisteredDevice
   │  ├─ deviceID
   │  ├─ deviceName
   │  ├─ deviceType
   │  └─ parentDeviceID
   └─ CD_UsageRecord (many)
      ├─ deviceID
      ├─ appIdentifier
      ├─ duration
      └─ timestamp
```

**Share Configuration:**
```swift
let share = CKShare(rootRecord: monitoringSession)
share[CKShare.SystemFieldKey.title] = "Child Device Monitoring"
// Configure for write access (research required)
```

**Child Write Operation:**
```swift
// Child uses sharedCloudDatabase
let sharedDB = CKContainer.default().sharedCloudDatabase

// Create record in parent's zone
let recordID = CKRecord.ID(recordName: "...", zoneID: parentZoneID)
let record = CKRecord(recordType: "CD_RegisteredDevice", recordID: recordID)

// Save to shared database
try await sharedDB.save(record)
```

**Parent Query Operation:**
```swift
// Parent queries own private database
let privateDB = CKContainer.default().privateCloudDatabase

// Query across all zones (including shared zones)
let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
let results = try await privateDB.records(matching: query)
```

---

## Consequences

### Positive

✅ **Cross-Account Support**
- Works with different iCloud accounts
- No restrictions on family setup

✅ **Immediate Visibility**
- Parent sees child device instantly
- Real-time usage data updates

✅ **Proper Security Model**
- Fine-grained permissions via CKShare
- Parent controls access (can revoke)

✅ **Scalability**
- Multiple children supported
- Efficient data model

✅ **Maintainability**
- Uses standard CloudKit APIs
- Well-documented by Apple
- Future-proof architecture

### Negative

⚠️ **Initial Complexity**
- Requires understanding CloudKit sharing
- More complex than local-only approach
- Dev team learning curve

⚠️ **Share Management**
- Need to handle share revocation
- Expired shares need cleanup
- Re-pairing flow if share deleted

⚠️ **Zone Proliferation**
- One zone per child device
- Need zone cleanup mechanism
- Monitor zone count limits

### Risks and Mitigations

**Risk 1: CKShare Permission Configuration**
- Risk: Incorrect permissions block child writes
- Mitigation: Study Apple docs, test thoroughly
- Fallback: Add explicit participants if needed

**Risk 2: NSPersistentCloudKitContainer Compatibility**
- Risk: May not fully support shared zones
- Mitigation: Test with Core Data sync
- Fallback: Use direct CloudKit APIs

**Risk 3: Query Performance with Multiple Children**
- Risk: Queries slow with 10+ children
- Mitigation: Cache zone IDs, optimize queries
- Acceptable: Family likely <5 children

---

## Success Metrics

### Technical Metrics
- [ ] Share creation success rate > 99%
- [ ] Share acceptance success rate > 95%
- [ ] Device registration latency < 5 seconds
- [ ] Query response time < 2 seconds
- [ ] Zero "permission denied" errors

### Business Metrics
- [ ] Cross-account pairing works 100% of time
- [ ] Parent sees child within 10 seconds
- [ ] Usage data appears within 1 minute
- [ ] Zero pairing support tickets

### User Experience Metrics
- [ ] Pairing flow < 30 seconds
- [ ] Zero confusing error messages
- [ ] Child device always visible after pairing
- [ ] Real-time updates feel instantaneous

---

## Open Questions

### Question 1: CKShare Participant Permissions
**Q:** How to configure CKShare for anonymous participant write access?
**Options:**
- A) Use `publicPermission = .readWrite` (may not work for private shares)
- B) Add explicit participant with write permission (requires iCloud ID)
- C) Configure share.publicPermission differently

**Action:** Dev agent to research and test
**Priority:** HIGH - Blocking implementation

### Question 2: NSPersistentCloudKitContainer Support
**Q:** Does NSPersistentCloudKitContainer automatically sync to shared zones?
**Answer Needed:** Yes/No + documentation reference
**Impact:** May need to use direct CloudKit APIs for writes
**Action:** Test with simple record creation

### Question 3: Zone Count Limits
**Q:** Is there a limit on number of zones per user?
**Expected:** Likely high limit (1000s)
**Impact:** Design zone cleanup strategy
**Action:** Check Apple documentation

---

## References

### Apple Documentation
- [CloudKit Sharing and Collaboration](https://developer.apple.com/documentation/cloudkit/shared_records)
- [CKShare Class Reference](https://developer.apple.com/documentation/cloudkit/ckshare)
- [Managing Shared Records](https://developer.apple.com/documentation/cloudkit/managing_shared_records)
- [NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)

### WWDC Sessions
- WWDC 2021: "What's new in CloudKit"
- WWDC 2019: "Using Core Data with CloudKit"
- WWDC 2016: "CloudKit Best Practices"

### Related Documents
- `docs/CROSS_ACCOUNT_PAIRING_STATUS.md` - Current status
- `docs/DEV_AGENT_TASKS.md` - Implementation tasks
- `docs/IMPLEMENTATION_SUMMARY_FOR_DEV.md` - Project overview

---

## Review and Approval

**Decision Date:** October 29, 2025
**Review Date:** TBD (after implementation)
**Approved By:** PM
**Implementation Owner:** Dev Agent
**Status:** APPROVED - Ready for Implementation

---

**Document Version:** 1.0
**Last Updated:** October 29, 2025
**Next Review:** After dev agent completes implementation
