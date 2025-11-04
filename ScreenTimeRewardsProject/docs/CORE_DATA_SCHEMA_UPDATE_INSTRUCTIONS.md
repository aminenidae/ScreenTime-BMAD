# Core Data Schema Update Instructions

This document outlines the changes needed for Task 1.2: Update Core Data Schema in the Challenge System implementation.

## Entities to Add

### 1. Challenge Entity
**Attributes:**
- challengeID (String, indexed)
- title (String)
- challengeDescription (String)
- goalType (String)
- targetValue (Integer 32)
- bonusPercentage (Integer 16, default: 10)
- targetAppsJSON (String, optional)
- startDate (Date)
- endDate (Date, optional)
- isActive (Boolean, default: YES)
- createdBy (String, indexed)
- assignedTo (String, indexed)

### 2. ChallengeProgress Entity
**Attributes:**
- progressID (String, indexed)
- challengeID (String, indexed)
- childDeviceID (String, indexed)
- currentValue (Integer 32, default: 0)
- targetValue (Integer 32, default: 0)
- isCompleted (Boolean, default: NO)
- completedDate (Date, optional)
- bonusPointsEarned (Integer 32, default: 0)
- lastUpdated (Date)

### 3. Badge Entity
**Attributes:**
- badgeID (String, indexed)
- badgeName (String)
- badgeDescription (String)
- iconName (String)
- unlockedAt (Date, optional)
- criteriaJSON (String)
- childDeviceID (String, indexed)

### 4. StreakRecord Entity
**Attributes:**
- streakID (String, indexed)
- childDeviceID (String, indexed)
- streakType (String)
- currentStreak (Integer 16, default: 0)
- longestStreak (Integer 16, default: 0)
- lastActivityDate (Date)

## CloudKit Sync Configuration

For all entities:
- Check "Used with CloudKit"
- Set all entities to syncable = YES

## Instructions

1. Open the project in Xcode
2. Navigate to the .xcdatamodeld file
3. Add the entities and attributes as described above
4. Configure CloudKit sync for each entity
5. Generate new Core Data classes if needed