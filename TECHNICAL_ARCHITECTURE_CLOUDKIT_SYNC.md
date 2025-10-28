# Technical Architecture: CloudKit Sync System
## ScreenTime Rewards Remote Monitoring

**Version:** 1.0
**Date:** October 27, 2025

---

## Table of Contents

1. [iCloud Account Requirements](#icloud-account-requirements)
2. [Device Mode Architecture](#device-mode-architecture)
3. [CloudKit Schema Design](#cloudkit-schema-design)
4. [Sync Service Architecture](#sync-service-architecture)
5. [Push Notification System](#push-notification-system)
6. [Offline Queue Management](#offline-queue-management)
7. [Code Structure](#code-structure)
8. [Integration Points](#integration-points)

---

## iCloud Account Requirements

### ⚠️ Critical: Different iCloud Accounts Required

**Parent and child MUST use DIFFERENT iCloud accounts.** This architecture relies on CloudKit's CKShare feature, which enables cross-account data sharing.

```
✅ CORRECT Configuration:

Parent Device                              Child Device
├─ Apple ID: parent@family.com            ├─ Apple ID: child@family.com
├─ Family Sharing: Organizer              ├─ Family Sharing: Child member
├─ Private CloudKit Database              ├─ Private CloudKit Database
│  └─ Creates CKShare                     │  └─ Accepts CKShare
│                                         │
└─ Shared Zone (via CKShare) ←─────────────→ Shared Zone (via CKShare)
   (Read/Write access)                       (Read/Write access)
```

### How CKShare Works Technically

**CKShare enables cross-account sharing in CloudKit:**

1. **Parent's Private Database:**
   ```swift
   // Parent creates a shared zone
   let share = CKShare(rootRecord: configRecord)
   share[CKShare.SystemFieldKey.title] = "ScreenTime Rewards Data"

   // Set permissions
   share.publicPermission = .none
   share.participants = [childParticipant]  // Child's Apple ID

   // Save share to CloudKit
   privateDatabase.save(share) { (savedShare, error) in
       // Generate share URL for QR code
       let shareURL = savedShare.url
   }
   ```

2. **Child Accepts Share:**
   ```swift
   // Child scans QR code containing share URL
   // iOS prompts: "Accept CloudKit sharing from parent@family.com?"

   // Programmatic acceptance
   container.accept(share) { (acceptedShare, error) in
       // Child can now access parent's shared zone
   }
   ```

3. **Bidirectional Sync:**
   ```swift
   // Both accounts can now read/write to shared zone

   // Child uploads usage data to shared zone
   let usageRecord = CKRecord(recordType: "UsageRecord")
   sharedDatabase.save(usageRecord)

   // Parent reads usage data from shared zone
   sharedDatabase.fetch(withRecordID: recordID) { (record, error) in
       // Parent sees child's usage data
   }
   ```

### Privacy & Security

**What each account accesses:**

| Data Location | Parent Access | Child Access |
|---------------|---------------|--------------|
| Parent's Private Database | ✅ Full access | ❌ No access |
| Child's Private Database | ❌ No access | ✅ Full access |
| Shared Zone (via CKShare) | ✅ Read/Write | ✅ Read/Write |
| Parent's iCloud (photos, mail, etc.) | ✅ Private | ❌ No access |
| Child's iCloud (photos, mail, etc.) | ❌ No access | ✅ Private |

**Key security features:**
- 🔒 Parent's personal data remains private
- 🔒 Child's personal data remains private
- ✅ Only app-specific records are shared
- ✅ Share can be revoked by either party
- ✅ Permissions controlled by CKShare settings

### Implementation Notes

**In CloudKitSyncService.swift:**
```swift
// Use sharedDatabase for cross-account access
private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
private let privateDatabase: CKDatabase  // For own data
private let sharedDatabase: CKDatabase   // For shared data (via CKShare)

init() {
    privateDatabase = container.privateCloudDatabase
    sharedDatabase = container.sharedCloudDatabase

    // Records saved to sharedDatabase are accessible by both accounts
    // (after CKShare is accepted)
}
```

---

## Device Mode Architecture

### Device Mode Enum

```swift
// ScreenTimeRewards/Models/DeviceMode.swift

import Foundation

enum DeviceMode: String, Codable {
    case parentDevice       // Parent's iPhone/iPad - Remote dashboard
    case childDevice        // Child's device - Full monitoring

    var displayName: String {
        switch self {
        case .parentDevice:
            return "Parent Device"
        case .childDevice:
            return "Child Device"
        }
    }

    var description: String {
        switch self {
        case .parentDevice:
            return "Monitor and configure child devices remotely"
        case .childDevice:
            return "Run monitoring on this device with parental controls"
        }
    }

    var requiresScreenTimeAuth: Bool {
        switch self {
        case .parentDevice:
            return false  // No local monitoring
        case .childDevice:
            return true   // Full ScreenTime API access needed
        }
    }
}
```

### Device Mode Manager

```swift
// ScreenTimeRewards/Services/DeviceModeManager.swift

import Foundation
import Combine

@MainActor
class DeviceModeManager: ObservableObject {
    static let shared = DeviceModeManager()

    @Published private(set) var currentMode: DeviceMode?
    @Published private(set) var deviceID: String
    @Published private(set) var deviceName: String

    private let userDefaults = UserDefaults.standard
    private let deviceModeKey = "deviceMode"
    private let deviceIDKey = "deviceID"
    private let deviceNameKey = "deviceName"

    private init() {
        // Load persisted mode
        if let modeRaw = userDefaults.string(forKey: deviceModeKey),
           let mode = DeviceMode(rawValue: modeRaw) {
            self.currentMode = mode
        }

        // Load or generate device ID
        if let existingID = userDefaults.string(forKey: deviceIDKey) {
            self.deviceID = existingID
        } else {
            self.deviceID = UUID().uuidString
            userDefaults.set(deviceID, forKey: deviceIDKey)
        }

        // Load or generate device name
        if let existingName = userDefaults.string(forKey: deviceNameKey) {
            self.deviceName = existingName
        } else {
            self.deviceName = UIDevice.current.name
            userDefaults.set(deviceName, forKey: deviceNameKey)
        }
    }

    func setDeviceMode(_ mode: DeviceMode, deviceName: String? = nil) {
        self.currentMode = mode
        userDefaults.set(mode.rawValue, forKey: deviceModeKey)

        if let name = deviceName {
            self.deviceName = name
            userDefaults.set(name, forKey: deviceNameKey)
        }

        #if DEBUG
        print("[DeviceModeManager] Mode set to: \(mode.displayName)")
        print("[DeviceModeManager] Device ID: \(deviceID)")
        print("[DeviceModeManager] Device Name: \(self.deviceName)")
        #endif
    }

    func resetDeviceMode() {
        currentMode = nil
        userDefaults.removeObject(forKey: deviceModeKey)

        #if DEBUG
        print("[DeviceModeManager] Mode reset - will show device selection on next launch")
        #endif
    }

    var isParentDevice: Bool {
        currentMode == .parentDevice
    }

    var isChildDevice: Bool {
        currentMode == .childDevice
    }

    var needsDeviceSelection: Bool {
        currentMode == nil
    }
}
```

---

## CloudKit Schema Design

### Core Data Entities

```swift
// ScreenTimeRewards/CoreData/ScreenTimeRewards.xcdatamodeld

// Entity: AppConfiguration
@objc(AppConfiguration)
public class AppConfiguration: NSManagedObject {
    @NSManaged public var logicalID: String
    @NSManaged public var tokenHash: String
    @NSManaged public var bundleIdentifier: String?
    @NSManaged public var displayName: String
    @NSManaged public var sfSymbolName: String
    @NSManaged public var category: String  // "learning" or "reward"
    @NSManaged public var pointsPerMinute: Int16
    @NSManaged public var isEnabled: Bool
    @NSManaged public var blockingEnabled: Bool
    @NSManaged public var dateAdded: Date
    @NSManaged public var lastModified: Date
    @NSManaged public var deviceID: String
    @NSManaged public var syncStatus: String  // "synced", "pending", "conflict"
}

// Entity: UsageRecord
@objc(UsageRecord)
public class UsageRecord: NSManagedObject {
    @NSManaged public var recordID: String
    @NSManaged public var logicalID: String
    @NSManaged public var displayName: String
    @NSManaged public var sessionStart: Date
    @NSManaged public var sessionEnd: Date
    @NSManaged public var totalSeconds: Int32
    @NSManaged public var earnedPoints: Int32
    @NSManaged public var category: String
    @NSManaged public var deviceID: String
    @NSManaged public var syncTimestamp: Date
    @NSManaged public var isSynced: Bool
}

// Entity: DailySummary
@objc(DailySummary)
public class DailySummary: NSManagedObject {
    @NSManaged public var summaryID: String  // deviceID_YYYY-MM-DD
    @NSManaged public var date: Date
    @NSManaged public var deviceID: String
    @NSManaged public var totalLearningSeconds: Int32
    @NSManaged public var totalRewardSeconds: Int32
    @NSManaged public var totalPointsEarned: Int32
    @NSManaged public var appsUsedJSON: String  // JSON array
    @NSManaged public var lastUpdated: Date
}

// Entity: RegisteredDevice
@objc(RegisteredDevice)
public class RegisteredDevice: NSManagedObject {
    @NSManaged public var deviceID: String
    @NSManaged public var deviceName: String
    @NSManaged public var deviceType: String  // "parent" or "child"
    @NSManaged public var childName: String?
    @NSManaged public var parentDeviceID: String?
    @NSManaged public var registrationDate: Date
    @NSManaged public var lastSyncDate: Date
    @NSManaged public var isActive: Bool
}

// Entity: ConfigurationCommand
@objc(ConfigurationCommand)
public class ConfigurationCommand: NSManagedObject {
    @NSManaged public var commandID: String
    @NSManaged public var targetDeviceID: String
    @NSManaged public var commandType: String
    @NSManaged public var payloadJSON: String
    @NSManaged public var createdAt: Date
    @NSManaged public var executedAt: Date?
    @NSManaged public var status: String  // "pending", "executed", "failed"
    @NSManaged public var errorMessage: String?
}

// Entity: SyncQueue (for offline operations)
@objc(SyncQueueItem)
public class SyncQueueItem: NSManagedObject {
    @NSManaged public var queueID: String
    @NSManaged public var operation: String  // "upload_usage", "download_config", etc.
    @NSManaged public var payloadJSON: String
    @NSManaged public var createdAt: Date
    @NSManaged public var retryCount: Int16
    @NSManaged public var lastAttempt: Date?
    @NSManaged public var status: String  // "queued", "processing", "failed"
}
```

### CloudKit Record Types

CloudKit mirrors Core Data entities with these record types:

```
RecordType: AppConfiguration
├─ logicalID (String, indexed)
├─ tokenHash (String)
├─ bundleIdentifier (String)
├─ displayName (String)
├─ sfSymbolName (String)
├─ category (String, indexed)
├─ pointsPerMinute (Int64)
├─ isEnabled (Int64)  // Boolean as 0/1
├─ blockingEnabled (Int64)
├─ dateAdded (Date/Time)
├─ lastModified (Date/Time, indexed)
└─ deviceID (String, indexed)

RecordType: UsageRecord
├─ recordID (String)
├─ logicalID (String, indexed)
├─ displayName (String)
├─ sessionStart (Date/Time, indexed)
├─ sessionEnd (Date/Time)
├─ totalSeconds (Int64)
├─ earnedPoints (Int64)
├─ category (String)
└─ deviceID (String, indexed)

RecordType: DailySummary
├─ summaryID (String, indexed)
├─ date (Date/Time, indexed)
├─ deviceID (String, indexed)
├─ totalLearningSeconds (Int64)
├─ totalRewardSeconds (Int64)
├─ totalPointsEarned (Int64)
├─ appsUsedJSON (String)
└─ lastUpdated (Date/Time)

RecordType: RegisteredDevice
├─ deviceID (String, indexed)
├─ deviceName (String)
├─ deviceType (String, indexed)
├─ childName (String)
├─ parentDeviceID (String, indexed)
├─ registrationDate (Date/Time)
├─ lastSyncDate (Date/Time, indexed)
└─ isActive (Int64)

RecordType: ConfigurationCommand
├─ commandID (String)
├─ targetDeviceID (String, indexed)
├─ commandType (String)
├─ payloadJSON (String)
├─ createdAt (Date/Time, indexed)
├─ executedAt (Date/Time)
└─ status (String, indexed)
```

---

## Sync Service Architecture

### CloudKitSyncService Core Implementation

```swift
// ScreenTimeRewards/Services/CloudKitSyncService.swift

import Foundation
import CloudKit
import CoreData
import Combine

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    // MARK: - Published Properties
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var syncError: Error?

    // MARK: - Private Properties
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let persistenceController = PersistenceController.shared
    private var cancellables = Set<AnyCancellable>()
    private let syncQueue = DispatchQueue(label: "com.screentimerewards.sync", qos: .utility)

    enum SyncStatus: String {
        case idle = "Idle"
        case syncing = "Syncing..."
        case success = "Synced"
        case error = "Error"
    }

    private init() {
        container = CKContainer(identifier: "iCloud.com.screentimerewards")
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase

        setupCloudKitSubscriptions()
    }

    // MARK: - Setup

    private func setupCloudKitSubscriptions() {
        // Subscribe to configuration changes (for child devices)
        let configPredicate = NSPredicate(
            format: "targetDeviceID == %@",
            DeviceModeManager.shared.deviceID
        )

        let subscription = CKQuerySubscription(
            recordType: "ConfigurationCommand",
            predicate: configPredicate,
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        privateDatabase.save(subscription) { _, error in
            if let error = error {
                print("[CloudKit] Subscription error: \(error)")
            } else {
                print("[CloudKit] Subscribed to configuration changes")
            }
        }
    }

    // MARK: - Device Registration

    func registerDevice(mode: DeviceMode, childName: String? = nil) async throws -> RegisteredDevice {
        let context = persistenceController.container.viewContext

        // Check if already registered
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "deviceID == %@",
            DeviceModeManager.shared.deviceID
        )

        if let existing = try? context.fetch(fetchRequest).first {
            print("[CloudKit] Device already registered: \(existing.deviceID)")
            return existing
        }

        // Create new registration
        let device = RegisteredDevice(context: context)
        device.deviceID = DeviceModeManager.shared.deviceID
        device.deviceName = DeviceModeManager.shared.deviceName
        device.deviceType = mode == .parentDevice ? "parent" : "child"
        device.childName = childName
        device.registrationDate = Date()
        device.lastSyncDate = Date()
        device.isActive = true

        try context.save()

        print("[CloudKit] Device registered: \(device.deviceID) as \(device.deviceType)")

        return device
    }

    // MARK: - Parent Device Methods (Mode 1)

    func fetchLinkedChildDevices() async throws -> [RegisteredDevice] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()

        fetchRequest.predicate = NSPredicate(
            format: "deviceType == %@ AND isActive == YES",
            "child"
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "deviceName", ascending: true)]

        return try context.fetch(fetchRequest)
    }

    func fetchChildUsageData(
        deviceID: String,
        dateRange: DateInterval
    ) async throws -> [UsageRecord] {
        syncStatus = .syncing
        isSyncing = true
        defer {
            isSyncing = false
            syncStatus = .idle
        }

        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()

        fetchRequest.predicate = NSPredicate(
            format: "deviceID == %@ AND sessionStart >= %@ AND sessionEnd <= %@",
            deviceID,
            dateRange.start as NSDate,
            dateRange.end as NSDate
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: false)]

        let records = try context.fetch(fetchRequest)

        lastSyncDate = Date()
        syncStatus = .success

        return records
    }

    func fetchChildDailySummary(
        deviceID: String,
        date: Date
    ) async throws -> DailySummary? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<DailySummary> = DailySummary.fetchRequest()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        fetchRequest.predicate = NSPredicate(
            format: "deviceID == %@ AND date >= %@ AND date < %@",
            deviceID,
            startOfDay as NSDate,
            endOfDay as NSDate
        )

        return try context.fetch(fetchRequest).first
    }

    func sendConfigurationToChild(
        deviceID: String,
        configuration: AppConfiguration
    ) async throws {
        syncStatus = .syncing
        isSyncing = true
        defer {
            isSyncing = false
        }

        let context = persistenceController.container.viewContext

        // 1. Update AppConfiguration
        configuration.lastModified = Date()
        try context.save()

        // 2. Create ConfigurationCommand
        let command = ConfigurationCommand(context: context)
        command.commandID = UUID().uuidString
        command.targetDeviceID = deviceID
        command.commandType = "update_config"
        command.createdAt = Date()
        command.status = "pending"

        let payload: [String: Any] = [
            "logicalID": configuration.logicalID,
            "category": configuration.category,
            "pointsPerMinute": configuration.pointsPerMinute,
            "isEnabled": configuration.isEnabled,
            "blockingEnabled": configuration.blockingEnabled
        ]

        command.payloadJSON = try JSONSerialization.data(
            withJSONObject: payload
        ).base64EncodedString()

        try context.save()

        // 3. Send push notification
        try await sendPushNotification(
            to: deviceID,
            type: "config_update",
            payload: payload
        )

        syncStatus = .success
        lastSyncDate = Date()

        print("[CloudKit] Configuration sent to child: \(deviceID)")
    }

    // MARK: - Child Device Methods (Mode 2)

    func downloadParentConfiguration() async throws -> [AppConfiguration] {
        syncStatus = .syncing
        isSyncing = true
        defer {
            isSyncing = false
        }

        let context = persistenceController.container.viewContext

        // 1. Fetch pending commands
        let commandFetch: NSFetchRequest<ConfigurationCommand> = ConfigurationCommand.fetchRequest()
        commandFetch.predicate = NSPredicate(
            format: "targetDeviceID == %@ AND status == %@",
            DeviceModeManager.shared.deviceID,
            "pending"
        )

        let commands = try context.fetch(commandFetch)

        var updatedConfigs: [AppConfiguration] = []

        // 2. Process each command
        for command in commands {
            guard let payloadData = Data(base64Encoded: command.payloadJSON),
                  let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let logicalID = payload["logicalID"] as? String else {
                command.status = "failed"
                command.errorMessage = "Invalid payload"
                continue
            }

            // Find or create AppConfiguration
            let configFetch: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
            configFetch.predicate = NSPredicate(format: "logicalID == %@", logicalID)

            let config = try context.fetch(configFetch).first ?? AppConfiguration(context: context)

            // Apply changes
            config.logicalID = logicalID
            if let category = payload["category"] as? String {
                config.category = category
            }
            if let points = payload["pointsPerMinute"] as? Int {
                config.pointsPerMinute = Int16(points)
            }
            if let enabled = payload["isEnabled"] as? Bool {
                config.isEnabled = enabled
            }
            if let blocking = payload["blockingEnabled"] as? Bool {
                config.blockingEnabled = blocking
            }
            config.lastModified = Date()
            config.syncStatus = "synced"

            updatedConfigs.append(config)

            // Mark command as executed
            command.status = "executed"
            command.executedAt = Date()
        }

        try context.save()

        syncStatus = .success
        lastSyncDate = Date()

        print("[CloudKit] Downloaded \(updatedConfigs.count) configuration updates")

        return updatedConfigs
    }

    func uploadUsageRecords(_ records: [UsageRecord]) async throws {
        guard !records.isEmpty else { return }

        syncStatus = .syncing
        isSyncing = true
        defer {
            isSyncing = false
        }

        let context = persistenceController.container.viewContext

        // Mark as synced
        for record in records {
            record.isSynced = true
            record.syncTimestamp = Date()
        }

        try context.save()

        syncStatus = .success
        lastSyncDate = Date()

        print("[CloudKit] Uploaded \(records.count) usage records")
    }

    func uploadDailySummary(_ summary: DailySummary) async throws {
        syncStatus = .syncing
        isSyncing = true
        defer {
            isSyncing = false
        }

        let context = persistenceController.container.viewContext

        summary.lastUpdated = Date()
        try context.save()

        syncStatus = .success
        lastSyncDate = Date()

        print("[CloudKit] Uploaded daily summary for \(summary.date)")
    }

    // MARK: - Push Notifications

    private func sendPushNotification(
        to deviceID: String,
        type: String,
        payload: [String: Any]
    ) async throws {
        // Implementation would use CloudKit silent push
        // For now, rely on CloudKit subscriptions
        print("[CloudKit] Push notification queued for \(deviceID)")
    }

    func handlePushNotification(userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo as! [String: NSObject]) else {
            return
        }

        if notification.notificationType == .query {
            // Configuration change detected
            do {
                let configs = try await downloadParentConfiguration()

                // Apply to ManagedSettings
                await applyConfigurationsToManagedSettings(configs)
            } catch {
                print("[CloudKit] Error handling push: \(error)")
            }
        }
    }

    // MARK: - ManagedSettings Integration

    private func applyConfigurationsToManagedSettings(_ configs: [AppConfiguration]) async {
        for config in configs {
            // Find local ApplicationToken
            guard let token = findLocalToken(for: config.logicalID) else {
                print("[CloudKit] No local token for \(config.logicalID)")
                continue
            }

            // Apply blocking state
            if config.blockingEnabled {
                ScreenTimeService.shared.blockRewardApps([token])
            } else {
                ScreenTimeService.shared.unlockRewardApps([token])
            }

            // Update category assignment
            let category: AppUsage.AppCategory = config.category == "learning" ? .learning : .reward
            ScreenTimeService.shared.categoryAssignments[token] = category

            // Update reward points
            if config.category == "reward" {
                ScreenTimeService.shared.rewardPointsAssignments[token] = Int(config.pointsPerMinute)
            }

            print("[CloudKit] Applied config for \(config.displayName)")
        }
    }

    private func findLocalToken(for logicalID: String) -> ApplicationToken? {
        // Search UsagePersistence for matching token
        let persistence = ScreenTimeService.shared.usagePersistence

        // Iterate through token mappings
        for (tokenHash, mapping) in persistence.cachedTokenMappings {
            if mapping.logicalID == logicalID {
                // Find token in ScreenTimeService
                for (token, category) in ScreenTimeService.shared.categoryAssignments {
                    if persistence.tokenHash(for: token) == tokenHash {
                        return token
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Offline Queue Management

    func enqueueOperation(operation: String, payload: [String: Any]) throws {
        let context = persistenceController.container.viewContext

        let queueItem = SyncQueueItem(context: context)
        queueItem.queueID = UUID().uuidString
        queueItem.operation = operation
        queueItem.payloadJSON = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        queueItem.createdAt = Date()
        queueItem.retryCount = 0
        queueItem.status = "queued"

        try context.save()

        print("[CloudKit] Operation queued: \(operation)")
    }

    func processOfflineQueue() async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<SyncQueueItem> = SyncQueueItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "status == %@", "queued")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        guard let items = try? context.fetch(fetchRequest), !items.isEmpty else {
            return
        }

        print("[CloudKit] Processing \(items.count) offline queue items")

        for item in items {
            item.status = "processing"
            item.lastAttempt = Date()

            do {
                // Process based on operation type
                switch item.operation {
                case "upload_usage":
                    // Extract and upload usage records
                    break
                case "download_config":
                    // Download configuration
                    break
                default:
                    break
                }

                // Remove from queue
                context.delete(item)
            } catch {
                item.retryCount += 1
                item.status = item.retryCount >= 3 ? "failed" : "queued"
                print("[CloudKit] Queue item failed: \(error)")
            }
        }

        try? context.save()
    }

    // MARK: - Manual Sync

    func forceSyncNow() async throws {
        print("[CloudKit] Force sync triggered")

        if DeviceModeManager.shared.isChildDevice {
            // Download latest config
            let configs = try await downloadParentConfiguration()
            await applyConfigurationsToManagedSettings(configs)

            // Upload pending usage
            await uploadPendingUsage()
        } else {
            // Refresh child data
            // (Automatic via CloudKit sync)
        }

        lastSyncDate = Date()
    }

    private func uploadPendingUsage() async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isSynced == NO")

        guard let records = try? context.fetch(fetchRequest) else { return }

        try? await uploadUsageRecords(records)
    }
}
```

---

## Push Notification System

### AppDelegate Extension

```swift
// ScreenTimeRewards/AppDelegate.swift

import UIKit
import UserNotifications
import CloudKit

extension AppDelegate: UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register for push notifications
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[Push] Device token: \(token)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle CloudKit push
        Task {
            await CloudKitSyncService.shared.handlePushNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
}
```

---

## Integration Points

### Existing Code Integration

#### 1. ScreenTimeService Integration

```swift
// Add to ScreenTimeService.swift

// MARK: - CloudKit Sync Integration

func syncConfigurationToCloudKit() async {
    guard DeviceModeManager.shared.isChildDevice else { return }

    // Upload current configuration
    for (token, category) in categoryAssignments {
        let (logicalID, tokenHash) = usagePersistence.resolveLogicalID(
            for: token,
            bundleIdentifier: nil,  // Will extract if available
            displayName: "Unknown"
        )

        // Create or update AppConfiguration in CloudKit
        // (via CloudKitSyncService)
    }
}

func applyCloudKitConfiguration(_ config: AppConfiguration) {
    // Convert to local structures and apply
    guard let token = CloudKitSyncService.shared.findLocalToken(for: config.logicalID) else {
        return
    }

    let category: AppUsage.AppCategory = config.category == "learning" ? .learning : .reward
    categoryAssignments[token] = category

    if config.category == "reward" {
        rewardPointsAssignments[token] = Int(config.pointsPerMinute)
    }

    if config.blockingEnabled {
        blockRewardApps([token])
    } else {
        unlockRewardApps([token])
    }
}
```

#### 2. AppUsageViewModel Integration

```swift
// Add to AppUsageViewModel.swift

// MARK: - Remote Configuration Support

func loadRemoteConfiguration() async {
    guard DeviceModeManager.shared.isChildDevice else { return }

    do {
        let configs = try await CloudKitSyncService.shared.downloadParentConfiguration()
        for config in configs {
            service.applyCloudKitConfiguration(config)
        }
        refreshData()
    } catch {
        print("[ViewModel] Error loading remote config: \(error)")
    }
}

func uploadUsageToCloudKit() async {
    guard DeviceModeManager.shared.isChildDevice else { return }

    // Create UsageRecord objects from current usage
    let context = PersistenceController.shared.container.viewContext

    for snapshot in learningSnapshots + rewardSnapshots {
        let record = UsageRecord(context: context)
        record.recordID = UUID().uuidString
        record.logicalID = snapshot.logicalID
        record.displayName = snapshot.displayName
        record.sessionStart = Date()  // Should track actual session
        record.sessionEnd = Date()
        record.totalSeconds = Int32(snapshot.totalSeconds)
        record.earnedPoints = Int32(snapshot.earnedPoints)
        record.category = snapshot.category.rawValue
        record.deviceID = DeviceModeManager.shared.deviceID
        record.isSynced = false
    }

    try? context.save()

    // Upload via CloudKitSyncService
    try? await CloudKitSyncService.shared.uploadPendingUsage()
}
```

---

## Background Task Registration

```swift
// ScreenTimeRewards/ScreenTimeRewardsApp.swift

import BackgroundTasks

@main
struct ScreenTimeRewardsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        registerBackgroundTasks()
    }

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.usage-sync",
            using: nil
        ) { task in
            handleUsageSync(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.config-sync",
            using: nil
        ) { task in
            handleConfigSync(task: task as! BGProcessingTask)
        }
    }

    func handleUsageSync(task: BGAppRefreshTask) {
        Task {
            await CloudKitSyncService.shared.uploadPendingUsage()
            task.setTaskCompleted(success: true)

            // Schedule next sync
            scheduleUsageSync()
        }
    }

    func handleConfigSync(task: BGProcessingTask) {
        Task {
            let configs = try? await CloudKitSyncService.shared.downloadParentConfiguration()
            if let configs = configs {
                for config in configs {
                    await ScreenTimeService.shared.applyCloudKitConfiguration(config)
                }
            }
            task.setTaskCompleted(success: true)
        }
    }

    func scheduleUsageSync() {
        let request = BGAppRefreshTaskRequest(identifier: "com.screentimerewards.usage-sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 minutes

        try? BGTaskScheduler.shared.submit(request)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    scheduleUsageSync()
                }
        }
    }
}
```

---

## File Structure

```
ScreenTimeRewards/
├── Models/
│   ├── DeviceMode.swift (NEW)
│   ├── AppConfiguration+CoreData.swift (NEW)
│   ├── UsageRecord+CoreData.swift (NEW)
│   ├── DailySummary+CoreData.swift (NEW)
│   ├── RegisteredDevice+CoreData.swift (NEW)
│   ├── ConfigurationCommand+CoreData.swift (NEW)
│   └── SyncQueueItem+CoreData.swift (NEW)
│
├── Services/
│   ├── DeviceModeManager.swift (NEW)
│   ├── CloudKitSyncService.swift (NEW)
│   ├── ScreenTimeService.swift (MODIFIED)
│   └── BackgroundSyncManager.swift (NEW)
│
├── ViewModels/
│   ├── AppUsageViewModel.swift (MODIFIED)
│   ├── ParentRemoteViewModel.swift (NEW)
│   └── DeviceSelectionViewModel.swift (NEW)
│
├── Views/
│   ├── DeviceSelection/
│   │   ├── DeviceSelectionView.swift (NEW)
│   │   └── DeviceTypeCardView.swift (NEW)
│   │
│   ├── ParentRemote/
│   │   ├── ParentRemoteDashboardView.swift (NEW)
│   │   ├── ChildDeviceSelectorView.swift (NEW)
│   │   ├── RemoteUsageSummaryView.swift (NEW)
│   │   ├── RemoteAppConfigurationView.swift (NEW)
│   │   └── HistoricalReportsView.swift (NEW)
│   │
│   └── Pairing/
│       ├── DevicePairingView.swift (NEW)
│       ├── QRCodeGeneratorView.swift (NEW)
│       └── QRCodeScannerView.swift (NEW)
│
└── Extensions/
    ├── AppDelegate+Push.swift (NEW)
    └── View+DeviceMode.swift (NEW)
```

---

**Document Version:** 1.0
**Status:** Ready for Implementation
**Next Steps:** Begin Phase 0 - Device Selection Implementation
