# Plan: Direct Extension-to-CloudKit Usage Sync

## Problem
The parent device doesn't receive usage data until the child opens the main app because:
1. Extension writes to App Group UserDefaults (`ext_*` keys)
2. Main app must be active to read this and sync to CloudKit
3. Parent zone info is stored in `UserDefaults.standard` (not accessible by extension)

## Solution
Add lightweight CloudKit sync directly in the extension, so usage data reaches the parent within ~30 seconds of each minute of use, even if the child never opens the main app.

---

## Implementation Steps

### 1. Store Parent Zone Info in App Group (so extension can read it)

**File: `ScreenTimeRewards/Services/DevicePairingService.swift`**

Add new method `syncParentZoneInfoToAppGroup()`:
- Read zone info from `UserDefaults.standard` (current location)
- Write to App Group: `ext_parentZoneID`, `ext_parentZoneOwner`, `ext_parentRootRecordName`, `ext_parentSyncEnabled`
- Call this in `addPairedParent()` and on unpair (to clear)

**File: `ScreenTimeRewards/ScreenTimeRewardsApp.swift`**

Call `syncParentZoneInfoToAppGroup()` when app becomes active (in case pairing happened while extension running).

---

### 2. Add CloudKit Entitlements to Extension

**File: `ScreenTimeActivityExtension/ScreenTimeActivityExtension.entitlements`**

Add CloudKit capability:
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.screentimerewards</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

---

### 3. Create Extension CloudKit Helper

**New File: `ScreenTimeActivityExtension/ExtensionCloudKitSync.swift`**

Lightweight CloudKit sync class:
- `syncUsageToParent(defaults:)` - main entry point
- Checks `ext_parentSyncEnabled` and reads zone info from App Group
- Collects usage data from `ext_usage_*` keys
- Creates/updates `CD_DailyUsageHistory` CKRecords in parent's shared zone
- Uses `savePolicy: .changedKeys` for conflict resolution
- **30-second throttle** to prevent excessive syncs
- **Fails silently** on network errors (main app is backup)
- Uses deterministic record IDs: `DUH-{deviceID}-{appID}-{date}` (matches main app format for upsert)

---

### 4. Integrate Sync into Extension

**File: `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`**

Add CloudKit import and call sync after recording usage (around line 150):
```swift
// After checkAndBlockIfRewardTimeExhausted(defaults: defaults)
ExtensionCloudKitSync.shared.syncUsageToParent(defaults: defaults)
```

---

### 5. Sync Device ID to App Group

**File: `ScreenTimeRewards/Models/DeviceModeManager.swift`**

When device ID is set, also write to App Group:
```swift
if let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") {
    defaults.set(deviceID, forKey: "ext_deviceID")
}
```

---

## Files to Modify

| File | Change |
|------|--------|
| `ScreenTimeActivityExtension/ScreenTimeActivityExtension.entitlements` | Add CloudKit capability |
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Import CloudKit, call sync |
| `ScreenTimeActivityExtension/ExtensionCloudKitSync.swift` | **NEW** - Lightweight CloudKit helper |
| `ScreenTimeRewards/Services/DevicePairingService.swift` | Add `syncParentZoneInfoToAppGroup()` |
| `ScreenTimeRewards/ScreenTimeRewardsApp.swift` | Call zone sync on app active |
| `ScreenTimeRewards/Models/DeviceModeManager.swift` | Sync device ID to App Group |

---

## Data Flow (After Implementation)

```
Extension records 1 minute of usage
        ↓
Writes to App Group (ext_usage_* keys)
        ↓
Calls ExtensionCloudKitSync.syncUsageToParent()
        ↓
Reads zone info from App Group (ext_parentZone*)
        ↓
Creates/Updates CKRecord in parent's sharedCloudDatabase
        ↓
Parent device sees update within ~30 seconds

BACKUP: Main app still syncs when opened
```

---

## Verification

1. **Pair devices** - verify App Group keys are written (check with debug log)
2. **Use learning app on child** - verify CloudKit record appears in parent's zone within 1 minute
3. **Force-quit child main app** - verify usage still syncs (extension-only sync working)
4. **Airplane mode test** - verify no crashes, main app syncs when back online
5. **Check parent dashboard** - verify hourly usage chart updates in real-time

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Extension memory pressure | Fire-and-forget async, no JSON encoding, primitives only |
| CloudKit rate limiting | 30-second throttle between syncs |
| Network unavailable | Fail silently, main app is backup |
| Zone info stale | Re-sync on every app foreground |
