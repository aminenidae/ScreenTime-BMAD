# CloudKit Schema Initialization Guide

## The Problem

You're seeing "Field 'recordName' is not marked queryable" in CloudKit Dashboard because the schema hasn't been pushed to CloudKit yet. While we added fetch indexes to the Core Data model, NSPersistentCloudKitContainer needs to explicitly export the schema to CloudKit to make fields queryable.

## The Solution

I've added a **CloudKit Schema Initializer** tool that you can access directly from the app. This tool will force the schema to be exported to CloudKit.

---

## Step-by-Step Instructions

### Step 1: Build and Install the App

1. **Build the updated app** in Xcode (already done - build succeeded ✅)
2. **Install on your parent device** (iPad)

### Step 2: Access the CloudKit Debug Tool

1. **Open the app** on your parent device
2. **Set up as Parent Device** (if not already done)
3. **Navigate to Parent Remote Dashboard**
4. **Look for the gear icon (⚙️)** in the top-left of the navigation bar
5. **Tap the gear icon** to open "CloudKit Debug"

### Step 3: Initialize CloudKit Schema

In the CloudKit Debug screen, you'll see several sections:

#### Section 1: CloudKit Status
- Shows your iCloud account status
- Should say "Available" (green) if signed in

#### Section 2: Local Core Data
- Shows how many RegisteredDevice records exist locally
- Lists device details (ID, name, type, parentID)

#### Section 3: Schema Initialization
This is where you'll **initialize the schema**:

1. **Click "Initialize CloudKit Schema"** button
2. **Wait for confirmation** - status will change to:
   - "Starting schema initialization..."
   - "Exporting schema to CloudKit..."
   - "✅ Schema exported successfully!"
3. **Wait 30-60 seconds** for CloudKit to process the schema

If the schema initialization fails, try the alternative method:
1. **Click "Create Dummy Records (Alternative)"**
2. This creates sample records to trigger automatic schema export
3. **Wait 30-60 seconds** for sync
4. **Click "Cleanup Dummy Records"** to remove the test data

### Step 4: Verify Schema in CloudKit Dashboard

After waiting 30-60 seconds:

1. **Go to CloudKit Dashboard** (https://icloud.developer.apple.com/dashboard/)
2. **Select "iCloud.com.screentimerewards"** container
3. **Select "Development"** environment
4. **Click "Records"** → **"Private Database"**
5. **Select "CD_RegisteredDevice"** record type
6. **Try to query records**

**Expected result**: Queries should now work without the "not queryable" error ✅

### Step 5: Test Device Pairing Again

Once schema is initialized:

1. **Generate QR code** on parent device (Parent Remote Dashboard → "Learn How to Pair Devices")
2. **Scan QR code** on child device
3. **Wait for pairing** to complete
4. **Pull down to refresh** on Parent Remote Dashboard
5. **Child device should appear** in the list

---

## What the Schema Initializer Does

The `initializeCloudKitSchema()` method:
- Exports the Core Data model to CloudKit
- Creates record types in CloudKit (CD_RegisteredDevice, CD_AppConfiguration, etc.)
- Makes indexed fields **queryable** in CloudKit
- This is a one-time operation per schema version

### Alternative Method (Dummy Records)

If `initializeCloudKitSchema()` fails, the dummy records method:
- Creates sample records in Core Data
- Triggers NSPersistentCloudKitContainer to sync
- Schema is automatically exported during first sync
- Dummy records can be safely deleted afterward

---

## Troubleshooting

### Issue: Schema initialization fails
**Error**: "❌ Schema initialization failed"

**Solutions**:
1. Check iCloud is signed in (Settings → iCloud)
2. Check internet connection
3. Try the "Create Dummy Records" alternative method
4. Restart the app and try again

### Issue: Still shows "not queryable" after 60 seconds
**Possible causes**:
- CloudKit is still processing the schema (wait longer)
- Wrong environment selected (use "Development", not "Production")
- Browser cache issue (refresh CloudKit Dashboard)

**Solutions**:
1. Wait 2-3 minutes total
2. Hard refresh CloudKit Dashboard (Cmd+Shift+R on Mac)
3. Check console logs for "Schema initialization complete" message
4. Try querying a different field first (like `CD_deviceType`)

### Issue: CloudKit account status shows "No iCloud Account"
**Solution**: Sign into iCloud in Settings → [Your Name] → iCloud

### Issue: Parent dashboard still shows no devices
**After schema initialization**:
1. Delete app from both devices
2. Reinstall from Xcode
3. Pair devices again
4. Check CloudKit Debug to verify devices are in local Core Data
5. Check CloudKit Dashboard to verify records synced

---

## Understanding CloudKit Schema

### Core Data → CloudKit Mapping

| Core Data | CloudKit |
|-----------|----------|
| Entity | Record Type (prefixed with "CD_") |
| Attribute | Field |
| Fetch Index | Queryable Index |

### Example: RegisteredDevice

**Core Data Entity**: `RegisteredDevice`
- Attributes: `deviceID`, `deviceName`, `deviceType`, `parentDeviceID`
- Fetch Indexes: `byDeviceID`, `byParentDeviceID`, `byDeviceType`

**CloudKit Record Type**: `CD_RegisteredDevice`
- Fields: `CD_deviceID`, `CD_deviceName`, `CD_deviceType`, `CD_parentDeviceID`
- Queryable: ✅ (after schema initialization)

### Why Indexes Matter

Without indexes:
```
Query: recordType = "CD_RegisteredDevice" AND CD_parentDeviceID = "12345"
Result: ❌ Error "Field 'CD_parentDeviceID' is not marked queryable"
```

With indexes:
```
Query: recordType = "CD_RegisteredDevice" AND CD_parentDeviceID = "12345"
Result: ✅ Returns matching records
```

---

## Console Log Reference

### Successful Schema Initialization
```
[Schema] ===== CloudKit Schema Initialization =====
[Schema] Calling initializeCloudKitSchema()...
[Schema] ✅ Schema initialization complete
[Schema] CloudKit should now have queryable indexes
[Schema] Wait 30-60 seconds, then check CloudKit Dashboard
```

### Successful Pairing (After Schema Init)
```
[DevicePairingService] Parent device registered successfully
[CloudKit] Device registered: Optional("C2DB8158-5E58-4385-AD73-76CA0FF9D79B")

[DevicePairingService] Child device registered with parent ID: C2DB8158-5E58-4385-AD73-76CA0FF9D79B
[CloudKit] Device registered: Optional("442798CD-27D8-4EEF-81F6-B56B5CF9AFB5")
```

### Successful Query (In Parent Dashboard)
```
[CloudKitSyncService] Fetching linked child devices...
[CloudKitSyncService] Parent Device ID: C2DB8158-5E58-4385-AD73-76CA0FF9D79B
[CloudKitSyncService] Found 1 linked child devices
[CloudKitSyncService]   - Device ID: 442798CD-27D8-4EEF-81F6-B56B5CF9AFB5, Parent ID: C2DB8158-5E58-4385-AD73-76CA0FF9D79B
```

---

## Key Files Modified

1. **CloudKitSchemaInitializer.swift** (NEW)
   - `initializeSchema()` - Force schema export to CloudKit
   - `createDummyRecords()` - Alternative schema initialization method
   - `cleanupDummyRecords()` - Remove test data

2. **CloudKitDebugService.swift** (UPDATED)
   - Enhanced CloudKitDebugView with schema initialization section
   - Added step-by-step instructions in the UI

3. **ParentRemoteDashboardView.swift** (UPDATED)
   - Added gear icon (⚙️) in toolbar to access CloudKit Debug
   - Debug mode only (#if DEBUG)

4. **Persistence.swift** (UPDATED)
   - Added detailed logging for CloudKit configuration
   - Logs container identifier and database scope

---

## Next Steps After Schema Initialization

Once schema is successfully initialized and queries work:

### 1. Test Pairing
- Pair parent and child devices
- Verify child appears in parent dashboard

### 2. Test Data Sync
- Use apps on child device
- Check if usage data appears on parent dashboard

### 3. Test Configuration Sync
- Update app settings from parent dashboard
- Verify changes sync to child device

### 4. Test Real-time Updates
- Make changes on child device
- Pull down to refresh on parent dashboard
- Verify updates appear

---

## Important Notes

### Schema Initialization is One-Time
- Only needs to be done once per container/environment
- Schema persists in CloudKit after initialization
- New devices don't need to reinitialize

### Development vs Production
- Always initialize in **Development** environment first
- Test thoroughly before pushing to Production
- Production requires separate schema initialization

### Schema Changes
If you modify the Core Data model (add fields, change indexes):
1. Schema initialization needs to be run again
2. CloudKit will merge changes with existing schema
3. Existing records remain intact

---

## Debug Checklist

Use this checklist to verify everything is working:

- [ ] CloudKit account status: Available (green)
- [ ] Local devices showing in Core Data (count > 0)
- [ ] Schema initialization completed successfully (✅)
- [ ] Waited 60+ seconds after schema initialization
- [ ] CloudKit Dashboard queries work (no "not queryable" error)
- [ ] Devices paired successfully (QR code scan)
- [ ] Parent dashboard shows linked child devices
- [ ] Console logs show device registration with correct IDs
- [ ] Child device has correct parentDeviceID

---

**Status**: ✅ Build successful, ready to test

**Action Required**:
1. Install app on parent device
2. Navigate to Parent Remote Dashboard → Tap gear icon (⚙️)
3. Click "Initialize CloudKit Schema"
4. Wait 60 seconds
5. Check CloudKit Dashboard
