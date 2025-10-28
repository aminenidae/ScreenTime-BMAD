# Core Data Model Update Instructions

This document describes the entities that need to be added to the Core Data model for CloudKit synchronization.

## Entities to Create

### 1. AppConfiguration
- **logicalID** (String, indexed)
- **tokenHash** (String)
- **bundleIdentifier** (String, optional)
- **displayName** (String)
- **sfSymbolName** (String)
- **category** (String, indexed)
- **pointsPerMinute** (Integer 16)
- **isEnabled** (Boolean)
- **blockingEnabled** (Boolean)
- **dateAdded** (Date)
- **lastModified** (Date, indexed)
- **deviceID** (String, indexed)
- **syncStatus** (String)

### 2. UsageRecord
- **recordID** (String)
- **logicalID** (String, indexed)
- **displayName** (String)
- **sessionStart** (Date, indexed)
- **sessionEnd** (Date)
- **totalSeconds** (Integer 32)
- **earnedPoints** (Integer 32)
- **category** (String)
- **deviceID** (String, indexed)
- **syncTimestamp** (Date)
- **isSynced** (Boolean)

### 3. DailySummary
- **summaryID** (String, indexed)
- **date** (Date, indexed)
- **deviceID** (String, indexed)
- **totalLearningSeconds** (Integer 32)
- **totalRewardSeconds** (Integer 32)
- **totalPointsEarned** (Integer 32)
- **appsUsedJSON** (String)
- **lastUpdated** (Date)

### 4. RegisteredDevice
- **deviceID** (String, indexed)
- **deviceName** (String)
- **deviceType** (String, indexed)
- **childName** (String, optional)
- **parentDeviceID** (String, indexed, optional)
- **registrationDate** (Date)
- **lastSyncDate** (Date, indexed)
- **isActive** (Boolean)

### 5. ConfigurationCommand
- **commandID** (String)
- **targetDeviceID** (String, indexed)
- **commandType** (String)
- **payloadJSON** (String)
- **createdAt** (Date, indexed)
- **executedAt** (Date, optional)
- **status** (String, indexed)
- **errorMessage** (String, optional)

### 6. SyncQueueItem
- **queueID** (String)
- **operation** (String)
- **payloadJSON** (String)
- **createdAt** (Date)
- **retryCount** (Integer 16)
- **lastAttempt** (Date, optional)
- **status** (String)

## Implementation Steps

1. Open the `.xcdatamodeld` file in Xcode
2. Create each entity listed above
3. Add all attributes with correct types
4. Mark the indexed attributes as indexed
5. Generate NSManagedObject subclasses
6. Move generated files to Models/CoreData/ directory
7. Verify CloudKit compatibility

## Notes

- All entities should have "Code Generation" set to "Class"
- All entities should have "Module" set to "Current Product Module"
- All entities should have "Syncable" checked for CloudKit compatibility