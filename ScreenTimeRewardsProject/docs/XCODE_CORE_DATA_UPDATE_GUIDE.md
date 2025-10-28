# Xcode Core Data Model Update Guide

This guide provides step-by-step instructions for manually updating the Core Data model in Xcode to add the required entities for CloudKit synchronization.

## Prerequisites

- Xcode 12.0 or later
- ScreenTimeRewards project opened in Xcode
- Backup of the current project state

## Steps

### 1. Open the Core Data Model

1. In Xcode, navigate to the Project Navigator
2. Expand the `ScreenTimeRewards` folder
3. Double-click on `ScreenTimeRewards.xcdatamodeld` to open the Core Data model editor

### 2. Create the AppConfiguration Entity

1. In the Core Data model editor, click the "+" button at the bottom to add a new entity
2. Name the entity `AppConfiguration`
3. Add the following attributes:
   - `logicalID` (String) - Check "Indexed"
   - `tokenHash` (String)
   - `bundleIdentifier` (String) - Check "Optional"
   - `displayName` (String)
   - `sfSymbolName` (String)
   - `category` (String) - Check "Indexed"
   - `pointsPerMinute` (Integer 16)
   - `isEnabled` (Boolean)
   - `blockingEnabled` (Boolean)
   - `dateAdded` (Date)
   - `lastModified` (Date) - Check "Indexed"
   - `deviceID` (String) - Check "Indexed"
   - `syncStatus` (String)

4. In the Data Model Inspector (right panel):
   - Set "Code Generation" to "Class"
   - Set "Module" to "Current Product Module"
   - Check "Syncable" for CloudKit compatibility

### 3. Create the UsageRecord Entity

1. Click the "+" button to add a new entity
2. Name the entity `UsageRecord`
3. Add the following attributes:
   - `recordID` (String)
   - `logicalID` (String) - Check "Indexed"
   - `displayName` (String)
   - `sessionStart` (Date) - Check "Indexed"
   - `sessionEnd` (Date)
   - `totalSeconds` (Integer 32)
   - `earnedPoints` (Integer 32)
   - `category` (String)
   - `deviceID` (String) - Check "Indexed"
   - `syncTimestamp` (Date)
   - `isSynced` (Boolean)

4. In the Data Model Inspector:
   - Set "Code Generation" to "Class"
   - Set "Module" to "Current Product Module"
   - Check "Syncable" for CloudKit compatibility

### 4. Create the DailySummary Entity

1. Click the "+" button to add a new entity
2. Name the entity `DailySummary`
3. Add the following attributes:
   - `summaryID` (String) - Check "Indexed"
   - `date` (Date) - Check "Indexed"
   - `deviceID` (String) - Check "Indexed"
   - `totalLearningSeconds` (Integer 32)
   - `totalRewardSeconds` (Integer 32)
   - `totalPointsEarned` (Integer 32)
   - `appsUsedJSON` (String)
   - `lastUpdated` (Date)

4. In the Data Model Inspector:
   - Set "Code Generation" to "Class"
   - Set "Module" to "Current Product Module"
   - Check "Syncable" for CloudKit compatibility

### 5. Create the RegisteredDevice Entity

1. Click the "+" button to add a new entity
2. Name the entity `RegisteredDevice`
3. Add the following attributes:
   - `deviceID` (String) - Check "Indexed"
   - `deviceName` (String)
   - `deviceType` (String) - Check "Indexed"
   - `childName` (String) - Check "Optional"
   - `parentDeviceID` (String) - Check "Indexed" and "Optional"
   - `registrationDate` (Date)
   - `lastSyncDate` (Date) - Check "Indexed"
   - `isActive` (Boolean)

4. In the Data Model Inspector:
   - Set "Code Generation" to "Class"
   - Set "Module" to "Current Product Module"
   - Check "Syncable" for CloudKit compatibility

### 6. Create the ConfigurationCommand Entity

1. Click the "+" button to add a new entity
2. Name the entity `ConfigurationCommand`
3. Add the following attributes:
   - `commandID` (String)
   - `targetDeviceID` (String) - Check "Indexed"
   - `commandType` (String)
   - `payloadJSON` (String)
   - `createdAt` (Date) - Check "Indexed"
   - `executedAt` (Date) - Check "Optional"
   - `status` (String) - Check "Indexed"
   - `errorMessage` (String) - Check "Optional"

4. In the Data Model Inspector:
   - Set "Code Generation" to "Class"
   - Set "Module" to "Current Product Module"
   - Check "Syncable" for CloudKit compatibility

### 7. Create the SyncQueueItem Entity

1. Click the "+" button to add a new entity
2. Name the entity `SyncQueueItem`
3. Add the following attributes:
   - `queueID` (String)
   - `operation` (String)
   - `payloadJSON` (String)
   - `createdAt` (Date)
   - `retryCount` (Integer 16)
   - `lastAttempt` (Date) - Check "Optional"
   - `status` (String)

4. In the Data Model Inspector:
   - Set "Code Generation" to "Class"
   - Set "Module" to "Current Product Module"
   - Check "Syncable" for CloudKit compatibility

### 8. Generate NSManagedObject Subclasses

1. With the data model selected, go to Editor > Create NSManagedObject Subclass...
2. Select the current model version
3. Select all entities
4. Choose the location: `ScreenTimeRewards/Models/CoreData/`
5. Click "Create"

### 9. Verify CloudKit Compatibility

1. Ensure all entities have "Syncable" checked
2. Verify all indexed attributes are properly marked
3. Confirm code generation settings are correct

## Common Issues and Solutions

### Issue: "Syncable" option not available
**Solution:** Ensure you're using Xcode 12.0 or later and that the project has CloudKit capability enabled.

### Issue: Generated files not in correct location
**Solution:** Move the generated files to `ScreenTimeRewards/Models/CoreData/` manually.

### Issue: Build errors after generation
**Solution:** 
1. Clean the build folder (Cmd+Shift+K)
2. Check that all imports are correct
3. Verify that the module settings are correct in the data model inspector

## Verification

After completing these steps:
1. Build the project to ensure no errors
2. Run the app to verify the Core Data stack loads correctly
3. Test creating and saving objects of each entity type
4. Check the console for any CloudKit-related messages

## Next Steps

Once the Core Data model is updated:
1. Implement the full CloudKitSyncService functionality
2. Add push notification handling
3. Implement the offline queue system
4. Add conflict resolution strategies
5. Conduct thorough integration testing