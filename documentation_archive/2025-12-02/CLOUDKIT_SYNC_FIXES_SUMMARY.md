# CloudKit Sync Fixes - Summary

## Problem Identified

The RegisteredDevice records (and other CloudKit entities) were not showing up in CloudKit Dashboard because **the Core Data model was missing fetch indexes**. CloudKit requires fields to be explicitly marked as "queryable" through indexes for any queries to work.

When you tried to query CloudKit Dashboard for `CD_RegisteredDevice` records, you got the error:
> "Field 'recordName' is not marked queryable"

This confirms that the schema didn't have the necessary indexes defined.

## Changes Made

### 1. Added Fetch Indexes to Core Data Model
Location: `ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`

Added fetch indexes to all CloudKit-synced entities:

#### RegisteredDevice Entity
- `byDeviceID` - index on `deviceID`
- `byParentDeviceID` - index on `parentDeviceID`
- `byDeviceType` - index on `deviceType`
- `byParentAndType` - composite index on `parentDeviceID` + `deviceType`

These indexes enable queries like:
```swift
fetchRequest.predicate = NSPredicate(format: "parentDeviceID == %@ AND deviceType == %@",
                                   parentDeviceID, "child")
```

#### AppConfiguration Entity
- `byLogicalID` - index on `logicalID`
- `byDeviceID` - index on `deviceID`

#### UsageRecord Entity
- `byDeviceID` - index on `deviceID`
- `bySessionStart` - index on `sessionStart`
- `byDeviceAndDate` - composite index on `deviceID` + `sessionStart`

#### DailySummary Entity
- `byDeviceID` - index on `deviceID`
- `byDate` - index on `date`
- `byDeviceAndDate` - composite index on `deviceID` + `date`

#### ConfigurationCommand Entity
- `byCommandID` - index on `commandID`
- `byTargetDeviceID` - index on `targetDeviceID`
- `byStatus` - index on `status`
- `byTargetAndStatus` - composite index on `targetDeviceID` + `status`

#### SyncQueueItem Entity
- `byQueueID` - index on `queueID`
- `byStatus` - index on `status`

### 2. Enhanced CloudKit Debug Service
Location: `ScreenTimeRewards/Services/CloudKitDebugService.swift`

Added functionality to check:
- Local Core Data devices
- Device count
- Device details (ID, name, type, parentID)

This helps diagnose whether devices are being saved locally but not syncing to CloudKit.

## Why This Matters

### Without Indexes
- Core Data saves records locally ✅
- NSPersistentCloudKitContainer might upload records to CloudKit ✅
- **BUT CloudKit queries fail** ❌ (because fields aren't queryable)
- Parent dashboard can't find child devices ❌

### With Indexes
- Core Data saves records locally ✅
- NSPersistentCloudKitContainer uploads records to CloudKit ✅
- CloudKit fields are queryable ✅
- Queries work properly ✅
- Parent dashboard finds child devices ✅

## What Happens Next

### Automatic Schema Push
NSPersistentCloudKitContainer will automatically:
1. Detect the schema changes (new indexes)
2. Push the updated schema to CloudKit
3. Create indexes in CloudKit for all marked fields

This happens **when the app runs** and creates/accesses the persistent store.

### Timeline
- **First run**: Schema is pushed to CloudKit (may take a few seconds)
- **Subsequent runs**: Schema is already in sync
- **Existing records**: May need to be re-indexed by CloudKit (automatic, may take time)

## Testing Instructions

### Step 1: Clean Install (Recommended)
To ensure fresh schema push:

1. **Delete app from both devices** (parent and child)
2. **Rebuild and install** from Xcode
3. **First launch** will push new schema to CloudKit

### Step 2: Test Pairing Again

#### On Parent Device:
1. Set up as Parent Device
2. Go to Parent Remote Dashboard
3. Tap "Learn How to Pair Devices" → Generate QR code
4. Check console logs for:
   - `[DevicePairingService] Parent device registered successfully`
   - `[CloudKit] Device registered: <parent-device-id>`

#### On Child Device:
1. Set up as Child Device
2. Scan QR code from parent
3. Check console logs for:
   - `[DevicePairingService] Child device registered with parent ID: <parent-id>`
   - `[CloudKit] Device registered: <child-device-id>`

### Step 3: Use Debug View (Optional)

Add CloudKitDebugView to your app navigation to check:
```swift
NavigationLink("Debug CloudKit") {
    CloudKitDebugView()
}
```

This shows:
- CloudKit account status
- Number of local devices in Core Data
- Device details (ID, type, parent linkage)

### Step 4: Check CloudKit Dashboard

After pairing (wait 30-60 seconds for sync):

1. Go to CloudKit Dashboard
2. Select "iCloud.com.screentimerewards" container
3. Go to "Development" environment
4. Click "Records" → "Private Database"
5. Look for `CD_RegisteredDevice` record type
6. Query should now work with indexed fields

Expected records:
- **1 parent device**: `deviceType = "parent"`, `parentDeviceID = null`
- **1 child device**: `deviceType = "child"`, `parentDeviceID = <parent's deviceID>`

## Troubleshooting

### If parent dashboard still shows "No devices":

1. **Check local Core Data** using CloudKitDebugView
   - Are devices saved locally?
   - Do both parent and child exist?
   - Does child have correct `parentDeviceID`?

2. **Check CloudKit sync status**
   - Console logs: Look for CloudKit errors
   - Settings → iCloud: Ensure signed in
   - CloudKit Dashboard: Check if records exist

3. **Force sync**
   - Pull down to refresh on Parent Remote Dashboard
   - Tap refresh button in toolbar

4. **Wait for sync**
   - Initial sync can take 30-60 seconds
   - Check CloudKit Dashboard after waiting

### Common Issues

**Issue**: "CloudKit account not signed in"
- **Solution**: Sign into iCloud in Settings

**Issue**: "Network unavailable"
- **Solution**: Check internet connection

**Issue**: Devices saved locally but not in CloudKit
- **Solution**: Wait for sync, or check CloudKit entitlements

**Issue**: Query still fails in CloudKit Dashboard
- **Solution**: Schema might not have pushed yet, restart app and wait

## Key Files Modified

1. **ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents**
   - Added fetch indexes to 6 entities
   - Enables CloudKit queries on indexed fields

2. **CloudKitDebugService.swift**
   - Added local device checking
   - Enhanced debug UI

## Next Steps After Successful Pairing

Once pairing works and devices appear in parent dashboard:

1. **Test usage data sync**: Check if child's app usage appears on parent
2. **Test configuration sync**: Try updating app settings from parent
3. **Test real-time updates**: Verify parent dashboard updates automatically
4. **Test offline queue**: Disconnect child, use apps, reconnect, verify sync

## Technical Notes

### Why NSPersistentCloudKitContainer?

NSPersistentCloudKitContainer automatically:
- Mirrors Core Data schema to CloudKit
- Syncs record changes bidirectionally
- Handles conflicts and merges
- Manages change tracking

### Schema Changes

When you add indexes to Core Data model:
1. Core Data generates new model hash
2. NSPersistentCloudKitContainer detects difference
3. CloudKit schema is updated on next launch
4. New indexes become queryable

### Query Requirements

For CloudKit queries to work:
- Fields must have fetch indexes in Core Data model
- Indexes must be pushed to CloudKit schema
- Records must be indexed (automatic after schema push)

---

**Status**: ✅ Build successful, schema changes ready to push on next app launch

**Action Required**: Test pairing with fresh install on both devices
