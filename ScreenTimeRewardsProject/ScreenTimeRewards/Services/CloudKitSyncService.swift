import CloudKit
import CoreData
import Combine

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?

    enum SyncStatus {
        case idle, syncing, success, error
    }

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let persistenceController = PersistenceController.shared
    private let offlineQueue = OfflineQueueManager.shared

    // MARK: - Device Registration
    // Test: Register device
    func registerDevice(mode: DeviceMode, childName: String? = nil) async throws -> RegisteredDevice {
        let context = persistenceController.container.viewContext

        let device = RegisteredDevice(context: context)
        device.deviceID = DeviceModeManager.shared.deviceID
        device.deviceName = DeviceModeManager.shared.deviceName
        device.deviceType = mode == .parentDevice ? "parent" : "child"
        device.childName = childName
        device.registrationDate = Date()
        device.lastSyncDate = Date()
        device.isActive = true

        try context.save()

        // CloudKit will sync automatically via NSPersistentCloudKitContainer

        print("[CloudKit] Device registered: \(device.deviceID)")

        return device
    }

    // Test: Fetch registered devices
    func fetchRegisteredDevices() async throws -> [RegisteredDevice] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()

        return try context.fetch(fetchRequest)
    }

    // MARK: - Parent Device Methods
    func fetchLinkedChildDevices() async throws -> [RegisteredDevice] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "parentDeviceID == %@ AND deviceType == %@", 
                                           DeviceModeManager.shared.deviceID, "child")
        
        return try context.fetch(fetchRequest)
    }

    func fetchChildUsageData(deviceID: String, dateRange: DateInterval) async throws -> [UsageRecord] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@ AND sessionStart >= %@ AND sessionStart <= %@", 
                                           deviceID, dateRange.start as NSDate, dateRange.end as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: true)]
        
        return try context.fetch(fetchRequest)
    }

    func fetchChildDailySummary(deviceID: String, date: Date) async throws -> DailySummary? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<DailySummary> = DailySummary.fetchRequest()
        // Assuming we're looking for a summary for the specific date and device
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@ AND date >= %@ AND date < %@", 
                                           deviceID, startOfDay as NSDate, endOfDay as NSDate)
        
        let results = try context.fetch(fetchRequest)
        return results.first
    }

    func sendConfigurationToChild(deviceID: String, configuration: AppConfiguration) async throws {
        let context = persistenceController.container.viewContext
        
        // Create a configuration command for the child device
        let command = ConfigurationCommand(context: context)
        command.commandID = UUID().uuidString
        command.targetDeviceID = deviceID
        command.commandType = "update_configuration"
        
        // Serialize the configuration to JSON
        let configDict: [String: Any] = [
            "logicalID": configuration.logicalID ?? "",
            "tokenHash": configuration.tokenHash ?? "",
            "displayName": configuration.displayName ?? "",
            "category": configuration.category ?? "",
            "pointsPerMinute": Int(configuration.pointsPerMinute),
            "isEnabled": configuration.isEnabled,
            "blockingEnabled": configuration.blockingEnabled
        ]
        
        command.payloadJSON = try JSONSerialization.data(withJSONObject: configDict).base64EncodedString()
        command.createdAt = Date()
        command.status = "pending"
        
        try context.save()
        
        print("[CloudKit] Configuration command sent to device: \(deviceID)")
    }

    func requestChildSync(deviceID: String) async throws {
        let context = persistenceController.container.viewContext
        
        // Create a sync request command for the child device
        let command = ConfigurationCommand(context: context)
        command.commandID = UUID().uuidString
        command.targetDeviceID = deviceID
        command.commandType = "request_sync"
        command.payloadJSON = Data().base64EncodedString() // Empty payload
        command.createdAt = Date()
        command.status = "pending"
        
        try context.save()
        
        print("[CloudKit] Sync request sent to device: \(deviceID)")
    }

    // MARK: - Child Device Methods
    func downloadParentConfiguration() async throws -> [AppConfiguration] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@", DeviceModeManager.shared.deviceID)
        
        let configurations = try context.fetch(fetchRequest)
        
        // Apply each configuration to the local ScreenTimeService
        let screenTimeService = ScreenTimeService.shared
        for config in configurations {
            screenTimeService.applyCloudKitConfiguration(config)
        }
        
        return configurations
    }

    func uploadUsageRecords(_ records: [UsageRecord]) async throws {
        // In a real implementation, we would ensure these are saved to Core Data
        // Since we're using NSPersistentCloudKitContainer, they will automatically sync
        print("[CloudKit] Usage records uploaded: \(records.count)")
    }

    func uploadDailySummary(_ summary: DailySummary) async throws {
        // In a real implementation, we would ensure this is saved to Core Data
        // Since we're using NSPersistentCloudKitContainer, it will automatically sync
        print("[CloudKit] Daily summary uploaded for date: \(summary.date ?? Date())")
    }

    func markConfigurationCommandExecuted(_ commandID: String) async throws {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ConfigurationCommand> = ConfigurationCommand.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "commandID == %@", commandID)
        
        if let command = try context.fetch(fetchRequest).first {
            command.executedAt = Date()
            command.status = "executed"
            try context.save()
            print("[CloudKit] Command marked as executed: \(commandID)")
        }
    }

    // MARK: - Common Methods
    func handlePushNotification(userInfo: [AnyHashable: Any]) async {
        print("[CloudKit] Received push notification: \(userInfo)")
        
        // Process the notification and trigger any necessary sync operations
        await processOfflineQueue()
    }

    func forceSyncNow() async throws {
        // Force a sync operation
        print("[CloudKit] Forcing sync now")
        // In a real implementation, we might trigger a CloudKit sync
        // For now, we'll just process the offline queue
        await processOfflineQueue()
    }

    func processOfflineQueue() async {
        print("[CloudKit] Processing offline queue")
        await offlineQueue.processQueue()
    }

    // MARK: - Conflict Resolution
    func resolveConflict(
        local: AppConfiguration,
        remote: AppConfiguration
    ) -> AppConfiguration {
        // Strategy: Last-write-wins with parent priority

        // 1. Parent device changes always win
        if DeviceModeManager.shared.isParentDevice {
            return local
        }

        // 2. Newer timestamp wins
        if let remoteModified = remote.lastModified,
           let localModified = local.lastModified,
           remoteModified > localModified {
            return remote
        }

        // 3. Default to local if same timestamp
        return local
    }

    func mergeConfigurations(
        local: [AppConfiguration],
        remote: [AppConfiguration]
    ) -> [AppConfiguration] {
        var merged: [String: AppConfiguration] = [:]

        // Add all local first
        for config in local {
            if let logicalID = config.logicalID {
                merged[logicalID] = config
            }
        }

        // Merge remote (resolving conflicts)
        for remoteConfig in remote {
            if let logicalID = remoteConfig.logicalID,
               let localConfig = merged[logicalID] {
                merged[logicalID] = resolveConflict(
                    local: localConfig,
                    remote: remoteConfig
                )
            } else if let logicalID = remoteConfig.logicalID {
                merged[logicalID] = remoteConfig
            }
        }

        return Array(merged.values)
    }
}