import CloudKit
import CoreData
import Combine
import UIKit

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

        // === UPSERT LOGIC: Query existing records to avoid duplicates ===
        // Get deviceID for the query (all records should have same deviceID)
        guard let deviceID = records.first?.deviceID else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ No deviceID found in records")
            #endif
            return
        }

        // Query existing CloudKit records for today for this device
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        var existingRecordsByLogicalID: [String: CKRecord] = [:]

        do {
            let predicate = NSPredicate(
                format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart < %@",
                deviceID, today as NSDate, tomorrow as NSDate
            )
            let query = CKQuery(recordType: "CD_UsageRecord", predicate: predicate)
            let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)

            for (_, result) in matches {
                if case .success(let record) = result,
                   let logicalID = record["CD_logicalID"] as? String {
                    existingRecordsByLogicalID[logicalID] = record
                }
            }

            #if DEBUG
            print("[CloudKitSyncService] Found \(existingRecordsByLogicalID.count) existing records in CloudKit for today")
            #endif
        } catch {
            // If query fails (e.g., schema not ready), log and continue with creating new records
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Could not query existing records: \(error.localizedDescription)")
            print("[CloudKitSyncService] Will create new records instead of upserting")
            #endif
        }

        var toSave: [CKRecord] = []
        var updatedCount = 0
        var createdCount = 0

        for item in records {
            let rec: CKRecord

            // Check if record already exists in CloudKit for this app
            if let existingRecord = existingRecordsByLogicalID[item.logicalID ?? ""] {
                // UPDATE existing record
                rec = existingRecord
                updatedCount += 1
                #if DEBUG
                print("[CloudKitSyncService] 🔄 Updating existing record: \(existingRecord.recordID.recordName) for \(item.logicalID ?? "unknown")")
                #endif
            } else {
                // CREATE new record
                let recID = CKRecord.ID(recordName: "UR-\(UUID().uuidString)", zoneID: zoneID)
                rec = CKRecord(recordType: "CD_UsageRecord", recordID: recID)
                // Link new record to the shared root so it belongs to the share
                rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                createdCount += 1
                #if DEBUG
                print("[CloudKitSyncService] ➕ Creating new record for \(item.logicalID ?? "unknown")")
                #endif
            }

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
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) records: \(createdCount) new, \(updatedCount) updates")
        #endif

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

    // === APP CONFIGURATION SYNC ===
    /// Upload app configurations to parent's shared zone with full schedule data
    /// This allows parent to see all configured apps with schedules, goals, and streaks
    func uploadAppConfigurationsToParent() async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Full App Configurations To Parent's Zone =====")
        #endif

        let context = persistenceController.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID  // Use consistent ID from registration

        // Fetch all AppConfigurations for this device
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@", deviceID)

        let configs = try context.fetch(fetchRequest)
        guard !configs.isEmpty else {
            #if DEBUG
            print("[CloudKitSyncService] No AppConfigurations to upload")
            #endif
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(configs.count) AppConfigurations to sync")
        #endif

        // Get share context (same as UsageRecords)
        guard
            let zoneName = UserDefaults.standard.string(forKey: "parentSharedZoneID"),
            let zoneOwner = UserDefaults.standard.string(forKey: "parentSharedZoneOwner"),
            let rootName = UserDefaults.standard.string(forKey: "parentSharedRootRecordName")
        else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)
        let sharedDB = container.sharedCloudDatabase

        // Query existing records for upsert
        var existingByLogicalID: [String: CKRecord] = [:]
        do {
            let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
            let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
            let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)
            for (_, result) in matches {
                if case .success(let record) = result,
                   let logicalID = record["CD_logicalID"] as? String {
                    existingByLogicalID[logicalID] = record
                }
            }
            #if DEBUG
            print("[CloudKitSyncService] Found \(existingByLogicalID.count) existing AppConfigurations in CloudKit")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Could not query existing AppConfigurations: \(error.localizedDescription)")
            #endif
        }

        var toSave: [CKRecord] = []
        var updatedCount = 0
        var createdCount = 0

        for config in configs {
            let rec: CKRecord
            if let existing = existingByLogicalID[config.logicalID ?? ""] {
                rec = existing
                updatedCount += 1
            } else {
                let recID = CKRecord.ID(recordName: "AC-\(UUID().uuidString)", zoneID: zoneID)
                rec = CKRecord(recordType: "CD_AppConfiguration", recordID: recID)
                rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                createdCount += 1
            }

            // Basic fields
            rec["CD_logicalID"] = config.logicalID as CKRecordValue?
            rec["CD_deviceID"] = config.deviceID as CKRecordValue?
            rec["CD_displayName"] = config.displayName as CKRecordValue?
            rec["CD_category"] = config.category as CKRecordValue?
            rec["CD_pointsPerMinute"] = Int(config.pointsPerMinute) as CKRecordValue
            rec["CD_isEnabled"] = config.isEnabled as CKRecordValue
            rec["CD_blockingEnabled"] = config.blockingEnabled as CKRecordValue
            rec["CD_lastModified"] = (config.lastModified ?? Date()) as CKRecordValue
            rec["CD_tokenHash"] = config.tokenHash as CKRecordValue?

            // Fetch full schedule configuration for this app
            if let logicalID = config.logicalID,
               let scheduleConfig = AppScheduleService.shared.getSchedule(for: logicalID) {

                // Encode full schedule config as JSON
                if let scheduleJSON = encodeToJSON(scheduleConfig) {
                    rec["CD_scheduleConfigJSON"] = scheduleJSON as CKRecordValue
                    #if DEBUG
                    print("[CloudKitSyncService]   \(config.displayName ?? "?") - added schedule config")
                    #endif
                }

                // Encode linked learning apps with display names for parent dashboard
                if !scheduleConfig.linkedLearningApps.isEmpty {
                    // Enrich linked apps with display names
                    var enrichedLinkedApps = scheduleConfig.linkedLearningApps
                    for i in enrichedLinkedApps.indices {
                        if enrichedLinkedApps[i].displayName == nil {
                            // Look up display name from ScreenTimeService
                            let linkedLogicalID = enrichedLinkedApps[i].logicalID
                            if let name = ScreenTimeService.shared.getDisplayName(for: linkedLogicalID) {
                                enrichedLinkedApps[i].displayName = name
                            }
                        }
                    }

                    if let linkedJSON = encodeToJSON(enrichedLinkedApps) {
                        rec["CD_linkedAppsJSON"] = linkedJSON as CKRecordValue
                    }
                    rec["CD_unlockMode"] = scheduleConfig.unlockMode.rawValue as CKRecordValue
                    #if DEBUG
                    let names = enrichedLinkedApps.compactMap { $0.displayName }.joined(separator: ", ")
                    print("[CloudKitSyncService]   \(config.displayName ?? "?") - added \(enrichedLinkedApps.count) linked apps: \(names) (\(scheduleConfig.unlockMode.rawValue))")
                    #endif
                }

                // Encode streak settings if enabled
                if let streakSettings = scheduleConfig.streakSettings {
                    if let streakJSON = encodeToJSON(streakSettings) {
                        rec["CD_streakSettingsJSON"] = streakJSON as CKRecordValue
                        #if DEBUG
                        print("[CloudKitSyncService]   \(config.displayName ?? "?") - added streak settings (enabled: \(streakSettings.isEnabled))")
                        #endif
                    }
                }

                // Add quick-access display fields for parent dashboard
                rec["CD_dailyLimitSummary"] = scheduleConfig.dailyLimits.displaySummary as CKRecordValue
                rec["CD_timeWindowSummary"] = scheduleConfig.todayTimeWindow.displayString as CKRecordValue
            }

            toSave.append(rec)
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) AppConfigurations: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty { return }

        let (savedRecords, _) = try await sharedDB.modifyRecords(saving: toSave, deleting: [])

        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedRecords.count) full AppConfigurations to parent's zone")
        #endif
    }

    // MARK: - Shield State Sync

    /// Upload shield states to parent's shared zone
    /// This allows parent to see which reward apps are currently blocked/unlocked
    func uploadShieldStatesToParent() async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Shield States To Parent's Zone =====")
        #endif

        let deviceID = DeviceModeManager.shared.deviceID

        // Read shield states from app group UserDefaults
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared"),
              let data = defaults.data(forKey: ExtensionShieldStates.userDefaultsKey),
              let shieldStates = try? JSONDecoder().decode(ExtensionShieldStates.self, from: data) else {
            #if DEBUG
            print("[CloudKitSyncService] No shield states found in app group")
            #endif
            return
        }

        guard !shieldStates.states.isEmpty else {
            #if DEBUG
            print("[CloudKitSyncService] Shield states dictionary is empty")
            #endif
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(shieldStates.states.count) shield states to sync")
        #endif

        // Get share context
        guard
            let zoneName = UserDefaults.standard.string(forKey: "parentSharedZoneID"),
            let zoneOwner = UserDefaults.standard.string(forKey: "parentSharedZoneOwner"),
            let rootName = UserDefaults.standard.string(forKey: "parentSharedRootRecordName")
        else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)
        let sharedDB = container.sharedCloudDatabase

        // Query existing shield state records for upsert
        var existingByLogicalID: [String: CKRecord] = [:]
        do {
            let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
            let query = CKQuery(recordType: "CD_ShieldState", predicate: predicate)
            let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)
            for (_, result) in matches {
                if case .success(let record) = result,
                   let logicalID = record["CD_rewardAppLogicalID"] as? String {
                    existingByLogicalID[logicalID] = record
                }
            }
            #if DEBUG
            print("[CloudKitSyncService] Found \(existingByLogicalID.count) existing shield states in CloudKit")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Could not query existing shield states: \(error.localizedDescription)")
            #endif
        }

        var toSave: [CKRecord] = []
        var updatedCount = 0
        var createdCount = 0

        for (logicalID, state) in shieldStates.states {
            let rec: CKRecord
            if let existing = existingByLogicalID[logicalID] {
                rec = existing
                updatedCount += 1
            } else {
                let recID = CKRecord.ID(recordName: "SS-\(UUID().uuidString)", zoneID: zoneID)
                rec = CKRecord(recordType: "CD_ShieldState", recordID: recID)
                rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                createdCount += 1
            }

            rec["CD_rewardAppLogicalID"] = logicalID as CKRecordValue
            rec["CD_deviceID"] = deviceID as CKRecordValue
            rec["CD_isUnlocked"] = state.isUnlocked as CKRecordValue
            rec["CD_unlockedAt"] = state.unlockedAt as CKRecordValue?
            rec["CD_reason"] = state.reason as CKRecordValue
            rec["CD_syncTimestamp"] = Date() as CKRecordValue

            // Look up display name for the reward app
            if let displayName = ScreenTimeService.shared.getDisplayName(for: logicalID) {
                rec["CD_rewardAppDisplayName"] = displayName as CKRecordValue
            }

            toSave.append(rec)
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) shield states: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty { return }

        let (savedRecords, _) = try await sharedDB.modifyRecords(saving: toSave, deleting: [])

        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedRecords.count) shield states to parent's zone")
        #endif
    }

    /// Fetch child's shield states from CloudKit
    /// Returns a dictionary of logicalID -> ShieldStateDTO
    func fetchChildShieldStates(deviceID: String) async throws -> [String: ShieldStateDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Shield States =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        #endif

        let db = container.privateCloudDatabase
        var results: [String: ShieldStateDTO] = [:]

        // Enumerate all zones
        let zones = try await db.allRecordZones()

        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_ShieldState", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) shield state records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = ShieldStateDTO(from: record)
                        results[dto.rewardAppLogicalID] = dto

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.rewardAppDisplayName ?? dto.rewardAppLogicalID): \(dto.isUnlocked ? "UNLOCKED" : "BLOCKED")")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(results.count) shield states")
        #endif

        return results
    }

    // MARK: - JSON Encoding Helpers

    /// Encode any Encodable type to JSON string
    private func encodeToJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode JSON string to any Decodable type
    private func decodeFromJSON<T: Decodable>(_ json: String, as type: T.Type) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Fetch child's app configurations from CloudKit
    /// Enumerates all zones (including shared zones) to find child's records
    func fetchChildAppConfigurations(deviceID: String) async throws -> [AppConfiguration] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child App Configurations =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        #endif

        let db = container.privateCloudDatabase
        var results: [AppConfiguration] = []
        let context = persistenceController.container.viewContext

        // Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Found \(zones.count) zones to search")
        for zone in zones {
            print("[CloudKitSyncService]   Zone: \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
        }
        #endif

        for zone in zones {
            // Skip the default zone - shared records are in custom zones
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                #if DEBUG
                print("[CloudKitSyncService] Skipping default zone")
                #endif
                continue
            }

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) records")
                #endif

                for (_, res) in matches {
                    if case .success(let r) = res {
                        let entity = NSEntityDescription.entity(forEntityName: "AppConfiguration", in: context)!
                        let config = AppConfiguration(entity: entity, insertInto: nil)
                        config.logicalID = r["CD_logicalID"] as? String
                        config.deviceID = r["CD_deviceID"] as? String
                        config.displayName = r["CD_displayName"] as? String
                        config.category = r["CD_category"] as? String
                        config.pointsPerMinute = Int16(r["CD_pointsPerMinute"] as? Int ?? 1)
                        config.isEnabled = r["CD_isEnabled"] as? Bool ?? true
                        config.tokenHash = r["CD_tokenHash"] as? String
                        config.lastModified = r["CD_lastModified"] as? Date
                        results.append(config)
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue to next zone on error
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(results.count) AppConfigurations for device \(deviceID)")
        for config in results {
            print("[CloudKitSyncService]   - \(config.displayName ?? "?") (\(config.category ?? "?"))")
        }
        #endif

        return results
    }

    /// Fetch child's app configurations with full schedule/goals/streaks data
    /// Returns FullAppConfigDTO objects that include decoded JSON fields
    func fetchChildAppConfigurationsFullDTO(deviceID: String) async throws -> [FullAppConfigDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Full App Configurations (DTO) =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        #endif

        let db = container.privateCloudDatabase
        var results: [FullAppConfigDTO] = []

        // Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Found \(zones.count) zones to search")
        #endif

        for zone in zones {
            // Skip the default zone - shared records are in custom zones
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) app config records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = FullAppConfigDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) (\(dto.category))")
                        if let schedule = dto.scheduleConfig {
                            print("[CloudKitSyncService]       Limits: \(schedule.dailyLimits.displaySummary)")
                            print("[CloudKitSyncService]       Window: \(schedule.todayTimeWindow.displayString)")
                        }
                        if !dto.linkedLearningApps.isEmpty {
                            print("[CloudKitSyncService]       Linked apps: \(dto.linkedLearningApps.count) (\(dto.unlockMode.displayName))")
                        }
                        if let streak = dto.streakSettings, streak.isEnabled {
                            print("[CloudKitSyncService]       Streak: \(streak.bonusValue)% bonus")
                        }
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue to next zone on error
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(results.count) full AppConfiguration DTOs")
        #endif

        return results
    }
    // === END APP CONFIGURATION SYNC ===

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
    /// Enumerates all zones (including shared zones) to find child's records
    func fetchChildUsageDataFromCloudKit(deviceID: String, dateRange: DateInterval) async throws -> [UsageRecord] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Usage Data From CloudKit =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        print("[CloudKitSyncService] Date Range: \(dateRange.start) to \(dateRange.end)")
        #endif

        let db = container.privateCloudDatabase
        var results: [UsageRecord] = []

        // Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Found \(zones.count) zones to search for usage records")
        #endif

        for zone in zones {
            // Skip the default zone - shared records are in custom zones
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart <= %@",
                    deviceID, dateRange.start as NSDate, dateRange.end as NSDate
                )
                let query = CKQuery(recordType: "CD_UsageRecord", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) usage records")
                #endif

                let zoneRecords = mapUsageMatchResults(matches)
                results.append(contentsOf: zoneRecords)
            } catch let ckErr as CKError {
                // Fallback for schema not ready or non-queryable fields
                let msg = ckErr.localizedDescription
                if ckErr.code == .invalidArguments ||
                   msg.localizedCaseInsensitiveContains("Unknown field") ||
                   msg.localizedCaseInsensitiveContains("not marked queryable") {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Schema not ready for zone \(zone.zoneID.zoneName). Trying fallback...")
                    #endif

                    // Fallback: fetch all records in zone and filter client-side
                    let fallbackPredicate = NSPredicate(value: true)
                    let fallbackQuery = CKQuery(recordType: "CD_UsageRecord", predicate: fallbackPredicate)
                    let (matches, _) = try await db.records(matching: fallbackQuery, inZoneWith: zone.zoneID)
                    let all = mapUsageMatchResults(matches)
                    let filtered = all.filter { rec in
                        guard let did = rec.deviceID,
                              let start = rec.sessionStart
                        else { return false }
                        return did == deviceID && start >= dateRange.start && start <= dateRange.end
                    }
                    results.append(contentsOf: filtered)
                } else {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(ckErr.localizedDescription)")
                    #endif
                    // Continue to next zone on non-schema errors
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue to next zone on error
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(results.count) total usage records")
        for record in results {
            print("[CloudKitSyncService]   Record: \(record.logicalID ?? "nil") | Category: \(record.category ?? "nil") | Time: \(record.totalSeconds)s | Points: \(record.earnedPoints)")
        }
        #endif

        return results
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
