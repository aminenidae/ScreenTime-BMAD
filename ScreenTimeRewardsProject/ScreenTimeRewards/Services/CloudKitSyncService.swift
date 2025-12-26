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
    func registerDevice(mode: DeviceMode, childName: String? = nil, parentDeviceID: String? = nil) async throws -> RegisteredDevice {
        let context = persistenceController.container.viewContext

        let device = RegisteredDevice(context: context)
        device.deviceID = DeviceModeManager.shared.deviceID
        device.deviceName = DeviceModeManager.shared.deviceName
        device.deviceType = mode == .parentDevice ? "parent" : "child"
        device.childName = childName
        device.parentDeviceID = parentDeviceID
        device.registrationDate = Date()
        device.lastSyncDate = Date()
        device.isActive = true

        #if DEBUG
        print("[CloudKit] ===== Registering Device =====")
        print("[CloudKit] Device ID: \(device.deviceID ?? "nil")")
        print("[CloudKit] Device Name: \(device.deviceName ?? "nil")")
        print("[CloudKit] Device Type: \(device.deviceType ?? "nil")")
        print("[CloudKit] Child Name: \(device.childName ?? "nil")")
        print("[CloudKit] Parent Device ID: \(device.parentDeviceID ?? "nil")")
        #endif

        try context.save()

        #if DEBUG
        print("[CloudKit] ✅ Device saved to Core Data")
        print("[CloudKit] Waiting for NSPersistentCloudKitContainer to sync to CloudKit...")
        print("[CloudKit] Check CloudKit Dashboard in 30-60 seconds for CD_RegisteredDevice record")
        #endif

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

    /// Fetch linked child devices from private database (including shared zones)
    func fetchLinkedChildDevices() async throws -> [RegisteredDevice] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Linked Child Devices (CloudKit Sharing) =====")
        print("[CloudKitSyncService] Parent Device ID: \(DeviceModeManager.shared.deviceID)")
        #endif

        // Query parent's PRIVATE database (shared zones are stored there)
        let privateDatabase = container.privateCloudDatabase
        let parentDeviceID = DeviceModeManager.shared.deviceID

        // Query for child devices across all shared zones
        let predicate = NSPredicate(
            format: "CD_deviceType == %@ AND CD_parentDeviceID == %@",
            "child", parentDeviceID
        )
        let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "CD_registrationDate", ascending: false)]

        #if DEBUG
        print("[CloudKitSyncService] Querying private database for child devices...")
        #endif

        // Query all zones (including shared zones)
        let (matchResults, _): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)
        do {
            (matchResults, _) = try await privateDatabase.records(matching: query)
            #if DEBUG
            print("[CloudKitSyncService] ✅ Query completed successfully. Processing \(matchResults.count) results...")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ❌ CRITICAL ERROR querying CloudKit:")
            print("[CloudKitSyncService] Error type: \(type(of: error))")
            print("[CloudKitSyncService] Error description: \(error.localizedDescription)")
            print("[CloudKitSyncService] Full error: \(error)")
            #endif
            throw error
        }

        var devices: [RegisteredDevice] = []

        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                // Convert CKRecord to RegisteredDevice
                let device = convertToRegisteredDevice(record)
                devices.append(device)
            case .failure(let error):
                #if DEBUG
                print("[CloudKitSyncService] Error fetching record: \(error)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(devices.count) child device(s) in shared zones")
        for device in devices {
            print("[CloudKitSyncService] Child device:")
            print("  - Device ID: \(device.deviceID ?? "nil")")
            print("  - Device Name: \(device.deviceName ?? "nil")")
            print("  - Registration Date: \(device.registrationDate ?? Date())")
        }
        #endif

        return devices
    }

    private func convertToRegisteredDevice(_ record: CKRecord) -> RegisteredDevice {
        // Create a transient RegisteredDevice not inserted into any context
        let context = persistenceController.container.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "RegisteredDevice", in: context)!
        let device = RegisteredDevice(entity: entity, insertInto: nil)

        device.deviceID = record["CD_deviceID"] as? String
        device.deviceName = record["CD_deviceName"] as? String
        device.deviceType = record["CD_deviceType"] as? String
        device.parentDeviceID = record["CD_parentDeviceID"] as? String
        device.registrationDate = record["CD_registrationDate"] as? Date
        if let active = record["CD_isActive"] as? Int { device.isActive = active != 0 } else { device.isActive = false }

        return device
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

    // === TASK 7 IMPLEMENTATION ===
    /// Upload usage records to parent's shared zone
    /// This function is called by the child device to upload usage data to the parent's shared zone
    func uploadUsageRecordsToParent(_ records: [UsageRecord]) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Usage Records To Parent's Zone =====")
        print("[CloudKitSyncService] Records to upload: \(records.count)")
        #endif

        let container = CKContainer(identifier: "iCloud.com.screentimerewards")
        let sharedDB = container.sharedCloudDatabase

        // Get share context from UserDefaults (persisted during pairing - Task 6)
        guard
            let zoneName = UserDefaults.standard.string(forKey: "parentSharedZoneID"),
            let zoneOwner = UserDefaults.standard.string(forKey: "parentSharedZoneOwner"),  // 🔧 FIX: Get zone owner!
            let rootName = UserDefaults.standard.string(forKey: "parentSharedRootRecordName")
        else {
            let error = NSError(domain: "UsageUpload", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing share context - device may not be paired"])
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            print("[CloudKitSyncService]   parentSharedZoneID: \(UserDefaults.standard.string(forKey: "parentSharedZoneID") ?? "nil")")
            print("[CloudKitSyncService]   parentSharedZoneOwner: \(UserDefaults.standard.string(forKey: "parentSharedZoneOwner") ?? "nil")")
            print("[CloudKitSyncService]   parentSharedRootRecordName: \(UserDefaults.standard.string(forKey: "parentSharedRootRecordName") ?? "nil")")
            #endif
            throw error
        }

        #if DEBUG
        print("[CloudKitSyncService] Share context found:")
        print("  - Zone Name: \(zoneName)")
        print("  - Zone Owner: \(zoneOwner)")
        print("  - Root Record Name: \(rootName)")
        #endif

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)  // 🔧 FIX: Use parent's owner!
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)

        var toSave: [CKRecord] = []
        for item in records {
            let recID = CKRecord.ID(recordName: "UR-\(UUID().uuidString)", zoneID: zoneID)
            let rec = CKRecord(recordType: "CD_UsageRecord", recordID: recID)
            
            // IMPORTANT: Link the new record to the shared root so it belongs to the share
            rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
            
            // Map UsageRecord fields to CloudKit record fields (using CD_ prefix to match Core Data schema)
            rec["CD_deviceID"] = item.deviceID as? CKRecordValue
            rec["CD_logicalID"] = item.logicalID as? CKRecordValue
            rec["CD_displayName"] = item.displayName as? CKRecordValue
            rec["CD_sessionStart"] = item.sessionStart as? CKRecordValue
            rec["CD_sessionEnd"] = item.sessionEnd as? CKRecordValue
            rec["CD_totalSeconds"] = Int(item.totalSeconds) as CKRecordValue
            rec["CD_earnedPoints"] = Int(item.earnedPoints) as CKRecordValue
            rec["CD_category"] = item.category as? CKRecordValue
            rec["CD_syncTimestamp"] = Date() as CKRecordValue

            toSave.append(rec)
            
            #if DEBUG
            print("[CloudKitSyncService] Preparing to upload usage record:")
            print("  - Record ID: \(recID.recordName)")
            print("  - Device ID: \(item.deviceID ?? "nil")")
            print("  - App: \(item.displayName ?? "nil")")
            print("  - Duration: \(item.totalSeconds)s")
            print("  - Points: \(item.earnedPoints)")
            #endif
        }

        if toSave.isEmpty {
            #if DEBUG
            print("[CloudKitSyncService] No records to upload")
            #endif
            return
        }

        // Save all records to shared database
        let (savedRecords, _) = try await sharedDB.modifyRecords(saving: toSave, deleting: [])
        
        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedRecords.count) usage records to parent's zone")
        #endif
        
        // Update local records as synced
        let context = persistenceController.container.viewContext
        for item in records {
            item.isSynced = true
            item.syncTimestamp = Date()
        }
        try context.save()
    }
    // === END TASK 7 IMPLEMENTATION ===

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

    // === TASK 8 IMPLEMENTATION ===
    /// Fetch child usage data from parent's shared zones using CloudKit
    /// This function is called by the parent device to fetch usage records directly from CloudKit shared zones
    func fetchChildUsageDataFromCloudKit(deviceID: String, dateRange: DateInterval) async throws -> [UsageRecord] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Usage Data From CloudKit =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        print("[CloudKitSyncService] Date Range: \(dateRange.start) to \(dateRange.end)")
        #endif

        let db = container.privateCloudDatabase
        let schemaPredicate = NSPredicate(
            format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart <= %@",
            deviceID, dateRange.start as NSDate, dateRange.end as NSDate
        )
        let schemaQuery = CKQuery(recordType: "CD_UsageRecord", predicate: schemaPredicate)

        do {
            #if DEBUG
            print("[CloudKitSyncService] Querying private database for usage records...")
            #endif

            let (matches, _) = try await db.records(matching: schemaQuery)
            let records = mapUsageMatchResults(matches)

#if DEBUG
print("[CloudKitSyncService] ✅ Found \(records.count) usage records")
for record in records {
    print("[CloudKitSyncService]   Record: \(record.logicalID ?? "nil") | Category: \(record.category ?? "nil") | Time: \(record.totalSeconds)s | Points: \(record.earnedPoints)")
}
#endif

return records

        } catch let ckErr as CKError {
            // Fallback for schema not ready or non-queryable fields (e.g., creationDate not indexed)
            let msg = ckErr.localizedDescription
            if ckErr.code == .invalidArguments ||
               msg.localizedCaseInsensitiveContains("Unknown field") ||
               msg.localizedCaseInsensitiveContains("not marked queryable") {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Schema not ready for field-based query (\(ckErr)). Falling back to date-only query + client filter.")
                #endif

                // Conservative fallback: fetch all usage records (no field predicate) and filter client-side
                let fallbackPredicate = NSPredicate(value: true)
                let fallbackQuery = CKQuery(recordType: "CD_UsageRecord", predicate: fallbackPredicate)
                let (matches, _) = try await db.records(matching: fallbackQuery)
                let all = mapUsageMatchResults(matches)
                let filtered = all.filter { rec in
                    guard let did = rec.deviceID,
                          let start = rec.sessionStart
                    else { return false }
                    // filter by device and date range
                    return did == deviceID && start >= dateRange.start && start <= dateRange.end
                }
                #if DEBUG
                print("[CloudKitSyncService] ✅ Fallback returned \(filtered.count) usage records for device \(deviceID)")
                #endif
                return filtered
            }
            throw ckErr
        }
    }
    
    private func mapUsageMatchResults<S>(_ matches: S) -> [UsageRecord]
    where S: Sequence, S.Element == (CKRecord.ID, Result<CKRecord, any Error>) {
        var results: [UsageRecord] = []
        for (_, res) in matches {
            if case .success(let r) = res {
                let entity = NSEntityDescription.entity(forEntityName: "UsageRecord", in: persistenceController.container.viewContext)!
                let u = UsageRecord(entity: entity, insertInto: nil)
                u.recordID = r.recordID.recordName
                u.deviceID = r["CD_deviceID"] as? String
                u.logicalID = r["CD_logicalID"] as? String
                u.displayName = r["CD_displayName"] as? String
                u.sessionStart = r["CD_sessionStart"] as? Date
                u.sessionEnd = r["CD_sessionEnd"] as? Date
                if let secs = r["CD_totalSeconds"] as? Int { u.totalSeconds = Int32(secs) }
                if let pts = r["CD_earnedPoints"] as? Int { u.earnedPoints = Int32(pts) }
                u.category = r["CD_category"] as? String
                u.syncTimestamp = r["CD_syncTimestamp"] as? Date
                results.append(u)
            }
        }
        return results
    }
    // === END TASK 8 IMPLEMENTATION ===

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
