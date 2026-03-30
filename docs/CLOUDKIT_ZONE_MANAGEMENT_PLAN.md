# CloudKit Zone Lifecycle Management

**Date:** January 1, 2026
**Status:** COMPLETE
**Related Files:** DevicePairingService.swift, CloudKitSyncService.swift, DeviceModeManager.swift, RegisteredDevice.swift, ParentRemoteViewModel.swift, ChildPairingView.swift

---

## Summary

This document covers the complete implementation of CloudKit zone lifecycle management for the ScreenTime Rewards app, including zone cleanup, re-pairing, stale detection, and zone-specific queries.

---

## Architecture: Privacy-First Data Model

```
┌─────────────────────────────────────────────────────────────────┐
│ CHILD DEVICE (Source of Truth)                                  │
│ ├─ Core Data: Local usage data, app configs, etc.              │
│ ├─ deviceID: Stored in KEYCHAIN (persists across reinstall)    │
│ └─ Data persists regardless of pairing status                   │
└─────────────────────────────────────────────────────────────────┘
           │
           │ PAIRED → Push to CloudKit
           │ UNPAIRED → Stop syncing
           ▼
┌─────────────────────────────────────────────────────────────────┐
│ CLOUDKIT (Sync Channel)                                         │
│ ├─ ChildMonitoring-{parentDeviceID} zones                       │
│ ├─ ParentCommands-{parentDeviceID} zones                        │
│ ├─ Exists while paired                                          │
│ └─ Deleted on EXPLICIT unpair only                              │
└─────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│ PARENT DEVICE (Viewer)                                          │
│ ├─ Views child's data via CloudKit                              │
│ ├─ deviceID: Stored in USERDEFAULTS (fresh start on reinstall) │
│ ├─ Reinstall = new deviceID, must re-pair children              │
│ └─ Stale detection shows orphaned pairings                      │
└─────────────────────────────────────────────────────────────────┘
```

**CloudKit Data Cleanup Policy: Explicit Unpair Only**
- Parent uninstall → CloudKit data orphaned (acceptable)
- Explicit unpair → CloudKit zone deleted (via unpairChildDevice/unpairDevice)
- Stale detection → Shows orphaned pairings for manual cleanup

---

## Implementation Status

| Case | Description | Status | Commit |
|------|-------------|--------|--------|
| 1 | Re-pairing Same Device | ✅ Complete | `deleteAllChildMonitoringZones` |
| 2 | Child Reinstall (Keychain) | ✅ Complete | `DeviceModeManager` Keychain storage |
| 3 | Parent Unpairs Child | ✅ Complete | `unpairChildDevice` method |
| 4 | Child Unpairs from Parent | ✅ Complete | `unpairDevice` + `hasValidPairing` |
| 5 | Zone-Specific Fetching | ✅ Complete | `sharedZoneID/Owner` fields |
| 6 | Stale Pairing Detection | ✅ Complete | `isStale` property + UI indicators |
| 7 | Parent Uses UserDefaults Only | ✅ Complete | `DeviceModeManager` mode-based storage |
| 8 | Zone-Specific Query Fix | ✅ Complete | All fetch functions updated |
| 9 | Child Pairing View Fix | ✅ Complete | `loadPairedParent()` implementation |

---

## Detailed Implementation

### Case 1: Re-pairing Same Device

**Problem:** When parent creates a new pairing session, old zones remain with stale data.

**Solution:** `deleteAllChildMonitoringZones()` in `CloudKitSyncService.swift`
- Called before creating new pairing session
- Deletes ALL `ChildMonitoring-*` zones owned by the parent
- Ensures fresh start for new pairing

```swift
// DevicePairingService.swift - createPairingSession()
print("[DevicePairingService] Deleting all old ChildMonitoring zones before creating new pairing...")
let deletedCount = try await cloudKitService.deleteAllChildMonitoringZones()
```

### Case 2: Child Reinstall (Keychain Persistence)

**Problem:** Child reinstall would lose deviceID, causing orphaned zones.

**Solution:** Child deviceID stored in Keychain (persists across reinstall)

```swift
// DeviceModeManager.swift
if mode == .childDevice {
    // CHILD: Use Keychain (persists across reinstall)
    Self.saveToKeychain(value: deviceID, service: keychainService, key: keychainDeviceIDKey)
}
```

### Case 3 & 4: Unpairing

**Parent unpairs child:**
```swift
// ParentRemoteViewModel.swift
func unpairChildDevice(_ device: RegisteredDevice) async {
    // Delete zone and records
    await cloudKitService.cleanupZone(zoneID)
    // Remove from local Core Data
}
```

**Child unpairs from parent:**
```swift
// DevicePairingService.swift
func unpairDevice() {
    // Clear pairing data from UserDefaults
    UserDefaults.standard.removeObject(forKey: "parentDeviceID")
    UserDefaults.standard.removeObject(forKey: "parentDeviceName")
    // ... other cleanup
}
```

### Case 5 & 8: Zone-Specific Fetching

**Problem:** After parent reinstalls and re-pairs, fetch functions were querying ALL zones (including stale/orphaned ones), causing:
- 64 duplicate app configs (4 copies from old zones)
- Stale usage records
- Unnecessary CloudKit queries

**Solution:** Added `zoneID` and `zoneOwner` parameters to all fetch functions:

```swift
// CloudKitSyncService.swift - Updated functions:
func fetchChildUsageDataFromCloudKit(deviceID: String, dateRange: DateInterval,
                                      zoneID: String? = nil, zoneOwner: String? = nil)
func fetchChildAppConfigurations(deviceID: String,
                                  zoneID: String? = nil, zoneOwner: String? = nil)
func fetchChildAppConfigurationsFullDTO(deviceID: String,
                                         zoneID: String? = nil, zoneOwner: String? = nil)
func fetchChildShieldStates(deviceID: String,
                             zoneID: String? = nil, zoneOwner: String? = nil)
func fetchChildDailyUsageHistory(deviceID: String, daysToFetch: Int = 30,
                                  zoneID: String? = nil, zoneOwner: String? = nil)
```

**Callers updated in ParentRemoteViewModel.swift:**
```swift
// loadChildData(for:)
usageRecords = try await cloudKitService.fetchChildUsageDataFromCloudKit(
    deviceID: device.deviceID ?? "",
    dateRange: dateRange,
    zoneID: device.sharedZoneID,
    zoneOwner: device.sharedZoneOwner
)

// loadChildAppConfigurations(for:)
let configs = try await cloudKitService.fetchChildAppConfigurations(
    deviceID: deviceID,
    zoneID: device.sharedZoneID,
    zoneOwner: device.sharedZoneOwner
)
```

### Case 6: Stale Pairing Detection

**Implementation:**
- Added transient `isStale` property to `RegisteredDevice` (ObjC associated objects)
- `validateChildPairings()` checks if each child's zone still exists
- UI shows warning indicators for stale devices

```swift
// RegisteredDevice.swift
public var isStale: Bool {
    get { objc_getAssociatedObject(self, &isStaleKey) as? Bool ?? false }
    set { objc_setAssociatedObject(self, &isStaleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
}

// DeviceCardCarousel.swift - Visual indicators
if device.isStale {
    Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.orange)
}
```

### Case 7: Parent DeviceID Storage

**Problem:** Parent deviceID in Keychain means reinstall doesn't give fresh start.

**Solution:** Mode-based storage strategy in `DeviceModeManager.swift`:
- **Child:** Keychain (persists across reinstall to prevent orphaned zones)
- **Parent:** UserDefaults only (reinstall = fresh start, must re-pair)

```swift
if storedMode == .childDevice {
    // CHILD: Use Keychain
    if let keychainID = Self.loadFromKeychain(...)
} else {
    // PARENT: Use UserDefaults only
    Self.deleteFromKeychain(...)  // Clear any stale Keychain entry
    if let existingID = userDefaults.string(forKey: deviceIDKey)
}
```

### Case 9: Child Pairing View Fix

**Problem:** After successful pairing, child's pairing view still showed "No devices connected."

**Root Cause:**
1. `loadPairedParents()` was a placeholder that did nothing
2. `PairingPayload` didn't include `parentDeviceName`
3. Parent device name wasn't being stored during pairing

**Solution:**

```swift
// DevicePairingService.swift - PairingPayload
struct PairingPayload: Codable {
    let shareURL: String
    let parentDeviceID: String
    let parentDeviceName: String?  // Added
    // ...
}

func getParentDeviceName() -> String? {
    return UserDefaults.standard.string(forKey: "parentDeviceName")
}

// ChildPairingView.swift
struct PairedParentInfo: Identifiable {
    let id: String  // parentDeviceID
    let deviceName: String
}

func loadPairedParent() {
    if let parentID = pairingService.getParentDeviceID() {
        let parentName = pairingService.getParentDeviceName() ?? "Parent Device"
        pairedParent = PairedParentInfo(id: parentID, deviceName: parentName)
    } else {
        pairedParent = nil
    }
}
```

---

## Files Modified

### CloudKitSyncService.swift
- `deleteAllChildMonitoringZones()` - Zone cleanup before re-pairing
- `zoneExists()` - Zone validation
- `validateChildZone()` - Stale detection
- `fetchChildUsageDataFromCloudKit()` - Zone-specific query support
- `fetchChildAppConfigurations()` - Zone-specific query support
- `fetchChildAppConfigurationsFullDTO()` - Zone-specific query support
- `fetchChildShieldStates()` - Zone-specific query support
- `fetchChildDailyUsageHistory()` - Zone-specific query support

### DeviceModeManager.swift
- Mode-based deviceID storage (Keychain for child, UserDefaults for parent)
- Keychain helpers: `saveToKeychain()`, `loadFromKeychain()`, `deleteFromKeychain()`

### DevicePairingService.swift
- `PairingPayload` includes `parentDeviceName`
- `getParentDeviceName()` method
- `unpairDevice()` clears parent name

### RegisteredDevice.swift
- `isStale` transient property (ObjC associated objects)
- `ConnectionStatus` enum
- `sharedZoneID` and `sharedZoneOwner` properties

### ParentRemoteViewModel.swift
- All fetch calls pass `device.sharedZoneID` and `device.sharedZoneOwner`
- `validateChildPairings()` for stale detection
- `unpairChildDevice()` for explicit unpair

### ChildPairingView.swift
- `PairedParentInfo` struct
- `loadPairedParent()` implementation
- Display paired parent with unpair option

### DeviceCardCarousel.swift
- Stale device visual indicators (warning icon, grayed out)

---

## Testing Scenarios

### Parent Reinstall and Re-pair
1. Parent uninstalls app
2. Parent reinstalls → gets new deviceID
3. Parent creates pairing session → old zones deleted
4. Child scans QR → pairs to new zone
5. Parent sees child data only from new zone ✅

### Child Reconnect After Parent Reinstall
1. Child still has old pairing in UserDefaults
2. Child syncs fail (zone no longer shared)
3. Child shows stale/disconnected status
4. Child re-scans parent QR → new pairing established ✅

### Stale Detection
1. Parent reinstalls with new deviceID
2. Old RegisteredDevice records show as stale
3. UI shows warning indicators
4. Parent can manually remove stale entries ✅

---

## Related Documentation

- [APP_CONFIGURATION_SYNC.md](./APP_CONFIGURATION_SYNC.md) - App configuration sync details
- [USAGERECORD_SYNC_FIX.md](./USAGERECORD_SYNC_FIX.md) - UsageRecord CloudKit sync
- [PARENT_DATA_SYNC_FIX.md](./PARENT_DATA_SYNC_FIX.md) - Parent device data synchronization
