# Core Data CloudKit and Indexes Configuration Guide

## Overview
This guide shows how to configure CloudKit sync and add indexes to your Core Data model in Xcode 15.0+.

## Part 1: Adding Indexes to Entities

### For Challenge Entity

1. **Open the Data Model**:
   - Navigate to `ScreenTimeRewards.xcdatamodeld`

2. **Select the Challenge Entity**:
   - Click on "Challenge" in the ENTITIES list

3. **Add Indexes** (via Editor menu):
   - Go to `Editor` → `Add Fetch Index`
   - This will create a new fetch index entry

4. **Configure Each Index**:

   **Index 1: assignedTo**
   - Click the "+" to add an index element
   - Set the property to `assignedTo`
   - This optimizes queries filtering challenges by child

   **Index 2: isActive + assignedTo (Compound Index)**
   - Click "+" to add another fetch index
   - Add element 1: `isActive`
   - Add element 2: `assignedTo`
   - This optimizes queries like "get all active challenges for a specific child"

   **Index 3: endDate**
   - Add another fetch index
   - Set property to `endDate`
   - This optimizes queries sorting or filtering by challenge end date

### For DailySummary Entity

1. **Select the DailySummary Entity**

2. **Add Indexes**:

   **Index 1: byDeviceID**
   - Editor → Add Fetch Index
   - Set property to `byDeviceID`

   **Index 2: byDate + byDeviceID (Compound Index)**
   - Add fetch index
   - Element 1: `byDate`
   - Element 2: `byDeviceID`
   - This optimizes queries for "get summaries for a device on a specific date"

### For RegisteredDevice Entity

1. **Select the RegisteredDevice Entity**

2. **Add Indexes**:

   **Index 1: byDeviceID**
   - Editor → Add Fetch Index
   - Set property to `byDeviceID`

   **Index 2: byParentDeviceID**
   - Add fetch index
   - Set property to `byParentDeviceID`
   - This optimizes parent-child device lookups

## Part 2: CloudKit Configuration

### Enable CloudKit for the Data Model

1. **Select the Data Model (not an entity)**:
   - Click on `ScreenTimeRewards` in the file navigator (the .xcdatamodeld file)
   - Or click in empty space in the entities panel

2. **Open Data Model Inspector**:
   - Press `Cmd + Option + 3`
   - Or go to View → Inspectors → Data Model Inspector

3. **Look for CloudKit Settings**:
   - In the inspector panel, look for "Used with CloudKit" checkbox
   - **Check the box** to enable CloudKit sync

4. **Alternative Method** (if checkbox not visible):
   - The CloudKit configuration might be in the project capabilities
   - Go to Project Settings → Target → Signing & Capabilities
   - Ensure "iCloud" capability is added with CloudKit enabled

### Configure Entity for CloudKit Sync

For each entity that needs to sync (Challenge, DailySummary, RegisteredDevice, etc.):

1. **Select the entity**
2. **In the inspector panel**, ensure:
   - The entity is not marked as "Abstract"
   - The entity has appropriate attributes marked for sync

## Part 3: Verify Configuration

### Check the .xcdatamodeld File

After adding indexes, you can verify by:

1. **Right-click** on `ScreenTimeRewards.xcdatamodeld`
2. **Select** "Show in Finder"
3. **Right-click** the file → "Show Package Contents"
4. **Open** `contents` file in a text editor
5. **Look for** `<fetchIndex>` elements in the XML

Example:
```xml
<fetchIndex name="byAssignedToIndex">
    <fetchIndexElement property="assignedTo" type="Binary" order="ascending"/>
</fetchIndex>
```

## Part 4: Testing

After configuration:

1. **Clean Build Folder**: `Product` → `Clean Build Folder` (Shift + Cmd + K)
2. **Build the project**: `Cmd + B`
3. **Test on device** to ensure CloudKit sync works
4. **Monitor** Console for any Core Data or CloudKit errors

## Notes

- Indexes improve query performance but add overhead to write operations
- Compound indexes should list the most selective property first
- CloudKit sync requires proper iCloud entitlements and configuration
- Test thoroughly after adding indexes to ensure no migration issues

## Troubleshooting

If you don't see "Used with CloudKit" option:
- Your Xcode version might require CloudKit configuration via project capabilities
- Check Project → Target → Signing & Capabilities → iCloud
- Ensure CloudKit container is properly configured

## References

- Apple Core Data Documentation: Fetch Indexes
- CloudKit with Core Data: WWDC Sessions
- Core Data Model Editor Guide
