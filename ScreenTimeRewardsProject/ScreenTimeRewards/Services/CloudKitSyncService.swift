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

    enum CloudKitSyncError: LocalizedError {
        case zoneNotFound(deviceID: String)
        case commandEncodingFailed
        case recordNotFound

        var errorDescription: String? {
            switch self {
            case .zoneNotFound(let deviceID):
                return "Could not find shared zone for device: \(deviceID)"
            case .commandEncodingFailed:
                return "Failed to encode command payload"
            case .recordNotFound:
                return "Record not found in CloudKit"
            }
        }
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

    // MARK: - Zone Management

    /// Find existing ChildMonitoring zones for a specific child device
    /// Returns zones that contain records for this deviceID
    func findExistingZonesForChild(deviceID: String) async throws -> [(zone: CKRecordZone, hasRecords: Bool)] {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()

        var matchingZones: [(zone: CKRecordZone, hasRecords: Bool)] = []

        for zone in allZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            // Check if this zone has records for the specified deviceID
            let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
            let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)

            do {
                let (matches, _) = try await database.records(matching: query, inZoneWith: zone.zoneID, resultsLimit: 1)
                let hasRecords = !matches.isEmpty
                matchingZones.append((zone: zone, hasRecords: hasRecords))

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): hasRecords=\(hasRecords) for device \(deviceID)")
                #endif
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error checking zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        return matchingZones
    }

    /// Delete all records in a zone and optionally delete the zone itself
    func cleanupZone(_ zoneID: CKRecordZone.ID, deleteZone: Bool = true) async throws {
        let database = container.privateCloudDatabase

        #if DEBUG
        print("[CloudKitSyncService] Cleaning up zone: \(zoneID.zoneName)")
        #endif

        // First, delete all records in the zone
        let recordTypes = ["CD_RegisteredDevice", "CD_AppConfiguration", "CD_UsageRecord", "MonitoringSession"]

        for recordType in recordTypes {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)

                let recordIDsToDelete = matches.compactMap { (recordID, result) -> CKRecord.ID? in
                    if case .success(_) = result { return recordID }
                    return nil
                }

                if !recordIDsToDelete.isEmpty {
                    let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDsToDelete)
                    #if DEBUG
                    print("[CloudKitSyncService] Deleted \(recordIDsToDelete.count) \(recordType) records")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error deleting \(recordType) records: \(error.localizedDescription)")
                #endif
            }
        }

        // Delete the zone itself if requested
        if deleteZone {
            do {
                try await database.deleteRecordZone(withID: zoneID)
                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone deleted: \(zoneID.zoneName)")
                #endif
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error deleting zone: \(error.localizedDescription)")
                #endif
                throw error
            }
        }
    }

    /// Get all ChildMonitoring zones (for diagnostic/cleanup purposes)
    func getAllChildMonitoringZones() async throws -> [CKRecordZone] {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()
        return allZones.filter { $0.zoneID.zoneName.hasPrefix("ChildMonitoring-") }
    }

    /// Delete orphaned zones that have no active child devices
    func cleanupOrphanedZones() async throws -> Int {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()
        var deletedCount = 0

        for zone in allZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            // Check if this zone has any registered devices
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)

            do {
                let (matches, _) = try await database.records(matching: query, inZoneWith: zone.zoneID, resultsLimit: 1)

                if matches.isEmpty {
                    // No devices in this zone - it's orphaned
                    #if DEBUG
                    print("[CloudKitSyncService] Found orphaned zone (no devices): \(zone.zoneID.zoneName)")
                    #endif

                    try await cleanupZone(zone.zoneID, deleteZone: true)
                    deletedCount += 1
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error checking zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Cleaned up \(deletedCount) orphaned zones")
        #endif

        return deletedCount
    }

    /// Unpair a child device from parent - deletes zone and all records
    /// Called from parent device to remove a child
    func unpairChildDevice(_ childDevice: RegisteredDevice) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Unpairing Child Device =====")
        print("[CloudKitSyncService] Child Device ID: \(childDevice.deviceID ?? "unknown")")
        print("[CloudKitSyncService] Zone: \(childDevice.sharedZoneID ?? "unknown")")
        #endif

        // 1. If we have zone info, delete that specific zone
        if let zoneName = childDevice.sharedZoneID,
           let zoneOwner = childDevice.sharedZoneOwner {
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)

            #if DEBUG
            print("[CloudKitSyncService] Deleting zone: \(zoneName)")
            #endif

            try await cleanupZone(zoneID, deleteZone: true)

            #if DEBUG
            print("[CloudKitSyncService] ✅ Zone deleted successfully")
            #endif
        } else if let deviceID = childDevice.deviceID {
            // Fallback: Find zones containing this device and clean them up
            #if DEBUG
            print("[CloudKitSyncService] No zone info, searching for zones with device \(deviceID)")
            #endif

            let matchingZones = try await findExistingZonesForChild(deviceID: deviceID)
            for (zone, hasRecords) in matchingZones where hasRecords {
                try await cleanupZone(zone.zoneID, deleteZone: true)
                #if DEBUG
                print("[CloudKitSyncService] ✅ Cleaned up zone: \(zone.zoneID.zoneName)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Child device unpaired successfully")
        #endif
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

        // Extract zone info from the CKRecord for zone-specific queries
        device.sharedZoneID = record.recordID.zoneID.zoneName
        device.sharedZoneOwner = record.recordID.zoneID.ownerName

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

    /// Send a full configuration update command to a child device.
    /// This includes all editable fields: schedule, daily limits, time windows,
    /// linked learning apps, unlock mode, and streak settings.
    ///
    /// - Parameters:
    ///   - deviceID: The target child device ID
    ///   - payload: The full configuration payload from parent
    func sendFullConfigurationCommand(deviceID: String, payload: FullConfigUpdatePayload) async throws {
        let context = persistenceController.container.viewContext

        let command = ConfigurationCommand(context: context)
        command.commandID = payload.commandID
        command.targetDeviceID = deviceID
        command.commandType = "update_full_config"
        command.payloadJSON = try payload.toBase64String()
        command.createdAt = Date()
        command.status = "pending"

        try context.save()

        #if DEBUG
        print("[CloudKit] ===== Full Config Command Sent =====")
        print("[CloudKit] Command ID: \(payload.commandID)")
        print("[CloudKit] Target Device: \(deviceID)")
        print("[CloudKit] App: \(payload.logicalID)")
        print("[CloudKit] Category: \(payload.category)")
        print("[CloudKit] Points/min: \(payload.pointsPerMinute)")
        print("[CloudKit] Enabled: \(payload.isEnabled)")
        print("[CloudKit] Blocking: \(payload.blockingEnabled)")
        print("[CloudKit] Linked apps: \(payload.linkedLearningApps.count)")
        print("[CloudKit] Unlock mode: \(payload.unlockMode.rawValue)")
        print("[CloudKit] Has schedule: \(payload.scheduleConfig != nil)")
        print("[CloudKit] Has streak: \(payload.streakSettings != nil)")
        #endif
    }

    // MARK: - Parent Command Zone Infrastructure

    /// Zone name prefix for parent commands - separate from Core Data managed zones
    private static let parentCommandsZonePrefix = "ParentCommands-"

    /// Check CloudKit account status and log details
    private func checkAndLogCloudKitAccountStatus() async -> CKAccountStatus {
        do {
            let status = try await container.accountStatus()
            #if DEBUG
            let statusString: String
            switch status {
            case .available:
                statusString = "✅ available"
            case .noAccount:
                statusString = "❌ noAccount - User not signed into iCloud"
            case .restricted:
                statusString = "⚠️ restricted - Parental controls or MDM"
            case .couldNotDetermine:
                statusString = "⚠️ couldNotDetermine"
            case .temporarilyUnavailable:
                statusString = "⚠️ temporarilyUnavailable"
            @unknown default:
                statusString = "❓ unknown status: \(status.rawValue)"
            }
            print("[CloudKitSyncService] 🔍 Account Status: \(statusString)")
            #endif
            return status
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Failed to check account status: \(error)")
            #endif
            return .couldNotDetermine
        }
    }

    /// Get or create the parent's command zone
    /// This zone is owned by the parent and shared with child devices
    private func getOrCreateParentCommandsZone() async throws -> CKRecordZone.ID {
        let db = container.privateCloudDatabase
        let parentDeviceID = DeviceModeManager.shared.deviceID
        let zoneName = Self.parentCommandsZonePrefix + parentDeviceID

        #if DEBUG
        print("[CloudKitSyncService] ===== Zone Creation Diagnostics =====")
        print("[CloudKitSyncService] Looking for parent commands zone: \(zoneName)")
        print("[CloudKitSyncService] Container ID: \(container.containerIdentifier ?? "nil")")
        #endif

        // Check account status first
        let accountStatus = await checkAndLogCloudKitAccountStatus()
        guard accountStatus == .available else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ CloudKit account not available, cannot create zone")
            #endif
            throw CloudKitSyncError.zoneNotFound(deviceID: parentDeviceID)
        }

        // Check if zone already exists
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Fetching all zones from privateCloudDatabase...")
        #endif

        let existingZones = try await db.allRecordZones()

        #if DEBUG
        print("[CloudKitSyncService] 🔍 Found \(existingZones.count) zones:")
        for zone in existingZones {
            print("[CloudKitSyncService]   - \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
        }
        #endif

        if let existing = existingZones.first(where: { $0.zoneID.zoneName == zoneName }) {
            #if DEBUG
            print("[CloudKitSyncService] ✅ Found existing parent commands zone")
            #endif
            return existing.zoneID
        }

        // Create new zone using explicit CKModifyRecordZonesOperation for better control
        #if DEBUG
        print("[CloudKitSyncService] 🔨 Creating new parent commands zone...")
        #endif

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        // Use CKModifyRecordZonesOperation for explicit server sync with high QoS
        let savedZoneID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecordZone.ID, Error>) in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.qualityOfService = .userInitiated

            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ CKModifyRecordZonesOperation completed successfully")
                    #endif
                    continuation.resume(returning: zoneID)
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] ❌ CKModifyRecordZonesOperation failed: \(error)")
                    if let ckError = error as? CKError {
                        print("[CloudKitSyncService] CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                            for (key, partialError) in partialErrors {
                                print("[CloudKitSyncService]   Partial error for \(key): \(partialError)")
                            }
                        }
                        if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
                            print("[CloudKitSyncService]   Retry after: \(retryAfter) seconds")
                        }
                    }
                    #endif
                    continuation.resume(throwing: error)
                }
            }

            db.add(operation)
        }

        // VERIFICATION: Immediately fetch zones again to confirm zone was actually created on server
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Verifying zone was created on server...")
        #endif

        // Small delay to allow server propagation
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let verifyZones = try await db.allRecordZones()
        let verified = verifyZones.contains(where: { $0.zoneID.zoneName == zoneName })

        #if DEBUG
        if verified {
            print("[CloudKitSyncService] ✅ VERIFIED: Zone exists on server after creation")
        } else {
            print("[CloudKitSyncService] ⚠️ WARNING: Zone NOT found on server after creation!")
            print("[CloudKitSyncService] ⚠️ This may indicate local caching without server sync")
            print("[CloudKitSyncService] Zones after verification: \(verifyZones.map { $0.zoneID.zoneName })")
        }
        #endif

        return savedZoneID
    }

    /// Share the parent commands zone with a specific child device
    /// Call this after pairing to ensure child can read commands
    func shareParentCommandsZoneWithChild(childShareURL: URL) async throws {
        let db = container.privateCloudDatabase
        let zoneID = try await getOrCreateParentCommandsZone()

        #if DEBUG
        print("[CloudKitSyncService] Sharing parent commands zone with child...")
        print("[CloudKitSyncService] Zone: \(zoneID.zoneName)")
        #endif

        // Create a root record for sharing (required by CKShare)
        let rootRecordID = CKRecord.ID(recordName: "CommandsRoot-\(DeviceModeManager.shared.deviceID)", zoneID: zoneID)

        // Check if root record already exists
        do {
            _ = try await db.record(for: rootRecordID)
            #if DEBUG
            print("[CloudKitSyncService] Root record already exists, zone already shareable")
            #endif
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, we'll create it
        }

        let rootRecord = CKRecord(recordType: "CommandsRoot", recordID: rootRecordID)
        rootRecord["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        rootRecord["createdAt"] = Date() as CKRecordValue

        // Create share with readWrite permission so child can mark commands as executed
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Parent Commands" as CKRecordValue
        share.publicPermission = .readWrite

        // Save root record and share together
        let (saveResults, _) = try await db.modifyRecords(saving: [rootRecord, share], deleting: [])

        for (recordID, result) in saveResults {
            switch result {
            case .success(let record):
                if let savedShare = record as? CKShare {
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ Parent commands zone shared")
                    print("[CloudKitSyncService] Share URL: \(savedShare.url?.absoluteString ?? "nil")")
                    #endif
                }
            case .failure(let error):
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error saving \(recordID): \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Parent → Child Configuration Commands (Parent-Owned Zone)

    /// Send a configuration command to the parent's own zone (which is shared with child)
    /// This is the correct approach: parent writes to their own zone, child reads from sharedCloudDatabase
    func sendConfigCommandToSharedZone(deviceID: String, payload: FullConfigUpdatePayload) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Sending Config Command to Parent's Zone =====")
        print("[CloudKitSyncService] Target Device: \(deviceID)")
        print("[CloudKitSyncService] Command ID: \(payload.commandID)")
        #endif

        // Check account status first
        let accountStatus = await checkAndLogCloudKitAccountStatus()
        guard accountStatus == .available else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ CloudKit account not available, cannot send command")
            #endif
            throw CloudKitSyncError.zoneNotFound(deviceID: deviceID)
        }

        // Get or create the parent's command zone
        let db = container.privateCloudDatabase
        let zoneID = try await getOrCreateParentCommandsZone()

        #if DEBUG
        print("[CloudKitSyncService] Using zone: \(zoneID.zoneName)")
        #endif

        // Create CKRecord for the command
        let recordID = CKRecord.ID(recordName: "ConfigCmd-\(payload.commandID)", zoneID: zoneID)
        let record = CKRecord(recordType: "ConfigurationCommand", recordID: recordID)

        // CRITICAL: Link record to the share's root record so it's visible to child
        // Without this parent reference, the record won't be shared with the child device!
        let parentDeviceID = DeviceModeManager.shared.deviceID
        let rootRecordID = CKRecord.ID(recordName: "CommandsRoot-\(parentDeviceID)", zoneID: zoneID)
        record.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)

        #if DEBUG
        print("[CloudKitSyncService] Setting parent reference to: \(rootRecordID.recordName)")
        #endif

        record["commandID"] = payload.commandID as CKRecordValue
        record["targetDeviceID"] = deviceID as CKRecordValue
        record["commandType"] = "update_full_config" as CKRecordValue
        record["payloadJSON"] = try payload.toBase64String() as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["status"] = "pending" as CKRecordValue
        record["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue

        // Use explicit CKModifyRecordsOperation for better server sync control
        let savedRecordName = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.qualityOfService = .userInitiated
            operation.savePolicy = .changedKeys

            // CRITICAL: Add per-record callback to catch individual record errors
            operation.perRecordSaveBlock = { recordID, result in
                #if DEBUG
                switch result {
                case .success(let savedRecord):
                    print("[CloudKitSyncService] [PER-RECORD] ✅ Record saved: \(recordID.recordName)")
                    print("[CloudKitSyncService] [PER-RECORD]   Type: \(savedRecord.recordType)")
                case .failure(let error):
                    print("[CloudKitSyncService] [PER-RECORD] ❌ Record FAILED: \(recordID.recordName)")
                    print("[CloudKitSyncService] [PER-RECORD]   Error: \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        print("[CloudKitSyncService] [PER-RECORD]   CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        // Check for specific errors
                        switch ckError.code {
                        case .serverRecordChanged:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Server record changed (conflict)")
                        case .unknownItem:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Unknown item (zone doesn't exist on server?)")
                        case .invalidArguments:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Invalid arguments")
                        case .permissionFailure:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ PERMISSION FAILURE - security roles blocking write!")
                        case .zoneNotFound:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Zone not found on server")
                        default:
                            break
                        }
                    }
                }
                #endif
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ CKModifyRecordsOperation completed successfully")
                    #endif
                    continuation.resume(returning: recordID.recordName)
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] ❌ CKModifyRecordsOperation failed: \(error)")
                    if let ckError = error as? CKError {
                        print("[CloudKitSyncService] CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                            for (key, partialError) in partialErrors {
                                print("[CloudKitSyncService]   Partial error for \(key): \(partialError)")
                            }
                        }
                        if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
                            print("[CloudKitSyncService]   Retry after: \(retryAfter) seconds")
                        }
                        // Check for specific error codes
                        switch ckError.code {
                        case .networkUnavailable:
                            print("[CloudKitSyncService] ⚠️ Network unavailable - record cached locally only")
                        case .networkFailure:
                            print("[CloudKitSyncService] ⚠️ Network failure - record cached locally only")
                        case .serverResponseLost:
                            print("[CloudKitSyncService] ⚠️ Server response lost")
                        case .zoneNotFound:
                            print("[CloudKitSyncService] ⚠️ Zone not found on server!")
                        default:
                            break
                        }
                    }
                    #endif
                    continuation.resume(throwing: error)
                }
            }

            db.add(operation)
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Command saved to parent's zone: \(zoneID.zoneName)")
        print("[CloudKitSyncService] Record ID: \(savedRecordName)")
        print("[CloudKitSyncService] App: \(payload.logicalID)")
        print("[CloudKitSyncService] Linked apps: \(payload.linkedLearningApps.count)")
        #endif

        // VERIFICATION: Immediately fetch the record to confirm it exists on server
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Verifying record was saved on server...")
        #endif

        // Small delay to allow server propagation
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        do {
            let fetchedRecord = try await db.record(for: recordID)
            #if DEBUG
            print("[CloudKitSyncService] ✅ VERIFIED: Record exists on server")
            print("[CloudKitSyncService]   Record type: \(fetchedRecord.recordType)")
            print("[CloudKitSyncService]   commandID: \(fetchedRecord["commandID"] as? String ?? "nil")")
            #endif
        } catch let error as CKError where error.code == .unknownItem {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ WARNING: Record NOT found on server after save!")
            print("[CloudKitSyncService] ⚠️ This indicates the save was cached locally but not synced")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Verification fetch failed: \(error)")
            #endif
        }
    }

    /// Fetch pending commands from the shared zone (child side)
    /// This is called by the child device to get commands from the parent
    ///
    /// The parent saves commands to their own ParentCommands-* zone and shares it with child.
    /// Child reads from sharedCloudDatabase where the ParentCommands-* zone appears.
    func fetchPendingCommandsFromSharedZone() async throws -> [CKRecord] {
        let myDeviceID = DeviceModeManager.shared.deviceID

        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Pending Commands from Shared Zone =====")
        print("[CloudKitSyncService] My Device ID: \(myDeviceID)")
        #endif

        var commands: [CKRecord] = []

        // PRIMARY: Check sharedCloudDatabase for ParentCommands-* zones (parent's command zone shared with us)
        let sharedDB = container.sharedCloudDatabase
        let sharedZones = try await sharedDB.allRecordZones()

        #if DEBUG
        print("[CloudKitSyncService] Shared DB zones: \(sharedZones.map { $0.zoneID.zoneName })")
        #endif

        // First, look for ParentCommands-* zones (new architecture)
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix(Self.parentCommandsZonePrefix) {
            #if DEBUG
            print("[CloudKitSyncService] Checking parent commands zone: \(zone.zoneID.zoneName)")
            #endif

            do {
                // DIAGNOSTIC: First query ALL ConfigurationCommand records (no filter)
                // This helps determine if records exist but the predicate filter doesn't match
                #if DEBUG
                let debugQuery = CKQuery(recordType: "ConfigurationCommand", predicate: NSPredicate(value: true))
                do {
                    let (allRecords, _) = try await sharedDB.records(matching: debugQuery, inZoneWith: zone.zoneID, resultsLimit: 100)
                    print("[CloudKitSyncService] [DIAG] ParentCommands zone \(zone.zoneID.zoneName): \(allRecords.count) total ConfigurationCommand record(s)")
                    if !allRecords.isEmpty {
                        for (recordID, result) in allRecords {
                            if case .success(let record) = result {
                                let cmdID = record["commandID"] as? String ?? "?"
                                let targetID = record["targetDeviceID"] as? String ?? "?"
                                let status = record["status"] as? String ?? "?"
                                print("[CloudKitSyncService] [DIAG]   Record: \(cmdID) -> target:\(targetID) status:\(status)")
                            } else if case .failure(let error) = result {
                                print("[CloudKitSyncService] [DIAG]   Failed to fetch \(recordID): \(error.localizedDescription)")
                            }
                        }
                    }
                } catch {
                    print("[CloudKitSyncService] [DIAG] Error querying all records: \(error.localizedDescription)")
                }
                #endif

                // Query for pending commands targeting this device
                let predicate = NSPredicate(
                    format: "targetDeviceID == %@ AND status == %@",
                    myDeviceID,
                    "pending"
                )
                let query = CKQuery(recordType: "ConfigurationCommand", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName) (ParentCommands): \(matches.count) pending command(s)")
                #endif

                for (_, result) in matches {
                    if case .success(let record) = result {
                        commands.append(record)
                        #if DEBUG
                        let cmdID = record["commandID"] as? String ?? "?"
                        print("[CloudKitSyncService] ✅ Found pending command from parent: \(cmdID)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying ParentCommands zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        // FALLBACK: Also check ChildMonitoring-* zones for backward compatibility
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            do {
                // DIAGNOSTIC: First, try to fetch ALL ConfigurationCommand records (no filter)
                // This helps determine if the record exists but query filtering fails due to missing indexes
                #if DEBUG
                let debugQuery = CKQuery(recordType: "ConfigurationCommand", predicate: NSPredicate(value: true))
                do {
                    let (allRecords, _) = try await sharedDB.records(matching: debugQuery, inZoneWith: zone.zoneID, resultsLimit: 100)
                    if !allRecords.isEmpty {
                        print("[CloudKitSyncService] [DIAG] Zone \(zone.zoneID.zoneName): \(allRecords.count) total ConfigurationCommand record(s)")
                        for (_, result) in allRecords {
                            if case .success(let record) = result {
                                let cmdID = record["commandID"] as? String ?? "?"
                                let targetID = record["targetDeviceID"] as? String ?? "?"
                                let status = record["status"] as? String ?? "?"
                                print("[CloudKitSyncService] [DIAG]   - \(cmdID): target=\(targetID), status=\(status)")
                            }
                        }
                    }
                } catch {
                    print("[CloudKitSyncService] [DIAG] Error fetching all commands: \(error.localizedDescription)")
                }
                #endif

                // Now try the filtered query
                let predicate = NSPredicate(
                    format: "targetDeviceID == %@ AND status == %@",
                    myDeviceID,
                    "pending"
                )
                let query = CKQuery(recordType: "ConfigurationCommand", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName) (shared): \(matches.count) result(s)")
                #endif

                for (_, result) in matches {
                    if case .success(let record) = result {
                        commands.append(record)
                        #if DEBUG
                        let cmdID = record["commandID"] as? String ?? "?"
                        print("[CloudKitSyncService] Found pending command: \(cmdID)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying shared zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        // Also check privateCloudDatabase (zones we own - parent may have saved there)
        let privateDB = container.privateCloudDatabase
        let privateZones = try await privateDB.allRecordZones()

        #if DEBUG
        print("[CloudKitSyncService] Private DB zones: \(privateZones.map { $0.zoneID.zoneName })")
        #endif

        for zone in privateZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            do {
                let predicate = NSPredicate(
                    format: "targetDeviceID == %@ AND status == %@",
                    myDeviceID,
                    "pending"
                )
                let query = CKQuery(recordType: "ConfigurationCommand", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                let (matches, _) = try await privateDB.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName) (private): \(matches.count) result(s)")
                #endif

                for (_, result) in matches {
                    if case .success(let record) = result {
                        // Avoid duplicates if somehow in both DBs
                        let cmdID = record["commandID"] as? String ?? ""
                        if !commands.contains(where: { ($0["commandID"] as? String) == cmdID }) {
                            commands.append(record)
                            #if DEBUG
                            print("[CloudKitSyncService] Found pending command (private): \(cmdID)")
                            #endif
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying private zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(commands.count) pending command(s)")
        #endif

        return commands
    }

    /// Mark a configuration command as executed in CloudKit shared zone
    func markCommandExecutedInSharedZone(_ record: CKRecord) async throws {
        let sharedDB = container.sharedCloudDatabase

        record["status"] = "executed" as CKRecordValue
        record["executedAt"] = Date() as CKRecordValue

        try await sharedDB.save(record)

        #if DEBUG
        let cmdID = record["commandID"] as? String ?? "?"
        print("[CloudKitSyncService] ✅ Command marked executed in shared zone: \(cmdID)")
        #endif
    }

    // MARK: - Legacy Core Data Command Methods (Deprecated)

    /// Mark a configuration command as executed
    func markConfigurationCommandExecuted(_ commandID: String) async throws {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ConfigurationCommand> = ConfigurationCommand.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "commandID == %@", commandID)

        let commands = try context.fetch(fetchRequest)
        guard let command = commands.first else {
            #if DEBUG
            print("[CloudKit] Command not found for marking executed: \(commandID)")
            #endif
            return
        }

        command.status = "executed"
        command.executedAt = Date()

        try context.save()

        #if DEBUG
        print("[CloudKit] Command marked as executed: \(commandID)")
        #endif
    }

    /// Fetch pending configuration commands for this device (child side)
    func fetchPendingCommands() async throws -> [ConfigurationCommand] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ConfigurationCommand> = ConfigurationCommand.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "targetDeviceID == %@ AND status == %@",
            DeviceModeManager.shared.deviceID,
            "pending"
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        return try context.fetch(fetchRequest)
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
    func fetchChildAppConfigurationsFullDTO(deviceID: String, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [FullAppConfigDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Full App Configurations (DTO) =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [FullAppConfigDTO] = []

        // If zone info provided, query ONLY that specific zone (optimization)
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: specificZoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) app config records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = FullAppConfigDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) (\(dto.category))")
                        #endif
                    }
                }

                // Zone-specific query successful - return directly (no dedup needed)
                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific fetch returned \(results.count) configs")
                #endif
                return results

            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(error.localizedDescription)")
                #endif
                // Fall through to all-zone search
            }
        }

        // Fallback: Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Falling back to all-zone search. Found \(zones.count) zones")
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
        print("[CloudKitSyncService] ✅ Fetched \(results.count) full AppConfiguration DTOs (before dedup)")
        #endif

        // CRITICAL: Deduplicate by logicalID, keeping the most recent record
        // Multiple zones may contain the same app from old pairings with stale data
        var deduped: [String: FullAppConfigDTO] = [:]
        for dto in results {
            let key = dto.logicalID
            if let existing = deduped[key] {
                // Keep the one with the more recent lastModified date
                let dtoDate = dto.lastModified ?? Date.distantPast
                let existingDate = existing.lastModified ?? Date.distantPast
                if dtoDate > existingDate {
                    deduped[key] = dto
                    #if DEBUG
                    print("[CloudKitSyncService] [DEDUP] Replaced \(dto.displayName) - newer: \(dtoDate) vs \(existingDate)")
                    #endif
                }
            } else {
                deduped[key] = dto
            }
        }

        let dedupedResults = Array(deduped.values)
        #if DEBUG
        print("[CloudKitSyncService] ✅ After dedup: \(dedupedResults.count) unique AppConfiguration DTOs")
        #endif

        return dedupedResults
    }
    // === END APP CONFIGURATION SYNC ===

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

    // MARK: - Daily Usage History Sync

    /// Upload daily usage history to parent's shared zone
    /// Syncs last N days of per-app dailyHistory from UsagePersistence
    func uploadDailyUsageHistoryToParent(daysToSync: Int = 30) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Daily Usage History To Parent's Zone =====")
        #endif

        let deviceID = DeviceModeManager.shared.deviceID

        // Load all apps from UsagePersistence
        let persistence = UsagePersistence()
        let allApps = persistence.loadAllApps()

        guard !allApps.isEmpty else {
            #if DEBUG
            print("[CloudKitSyncService] No apps found in UsagePersistence")
            #endif
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(allApps.count) apps with usage data")
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

        // Calculate date range
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoffDate = calendar.date(byAdding: .day, value: -daysToSync, to: today)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Query existing history records for upsert
        var existingByKey: [String: CKRecord] = [:]
        do {
            let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
            let query = CKQuery(recordType: "CD_DailyUsageHistory", predicate: predicate)
            let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)
            for (_, result) in matches {
                if case .success(let record) = result,
                   let logicalID = record["CD_logicalID"] as? String,
                   let date = record["CD_date"] as? Date {
                    let key = "\(logicalID)-\(dateFormatter.string(from: date))"
                    existingByKey[key] = record
                }
            }
            #if DEBUG
            print("[CloudKitSyncService] Found \(existingByKey.count) existing history records in CloudKit")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Could not query existing history records: \(error.localizedDescription)")
            #endif
        }

        var toSave: [CKRecord] = []
        var updatedCount = 0
        var createdCount = 0

        for (logicalID, app) in allApps {
            // Skip uncategorized apps
            guard app.category == "Learning" || app.category == "Reward" else { continue }

            // Upload historical days from dailyHistory
            for summary in app.dailyHistory where summary.date >= cutoffDate {
                let dateStr = dateFormatter.string(from: summary.date)
                let key = "\(logicalID)-\(dateStr)"

                let rec: CKRecord
                if let existing = existingByKey[key] {
                    rec = existing
                    updatedCount += 1
                } else {
                    // Use deterministic record ID for upsert
                    let recID = CKRecord.ID(recordName: "DUH-\(deviceID)-\(logicalID)-\(dateStr)", zoneID: zoneID)
                    rec = CKRecord(recordType: "CD_DailyUsageHistory", recordID: recID)
                    rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                    createdCount += 1
                }

                rec["CD_deviceID"] = deviceID as CKRecordValue
                rec["CD_logicalID"] = logicalID as CKRecordValue
                rec["CD_displayName"] = app.displayName as CKRecordValue
                rec["CD_date"] = summary.date as CKRecordValue
                rec["CD_seconds"] = summary.seconds as CKRecordValue
                rec["CD_category"] = app.category as CKRecordValue
                rec["CD_syncTimestamp"] = Date() as CKRecordValue

                toSave.append(rec)
            }

            // Also upload today's data if available
            if app.todaySeconds > 0 {
                let dateStr = dateFormatter.string(from: today)
                let key = "\(logicalID)-\(dateStr)"

                let rec: CKRecord
                if let existing = existingByKey[key] {
                    rec = existing
                    updatedCount += 1
                } else {
                    let recID = CKRecord.ID(recordName: "DUH-\(deviceID)-\(logicalID)-\(dateStr)", zoneID: zoneID)
                    rec = CKRecord(recordType: "CD_DailyUsageHistory", recordID: recID)
                    rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                    createdCount += 1
                }

                rec["CD_deviceID"] = deviceID as CKRecordValue
                rec["CD_logicalID"] = logicalID as CKRecordValue
                rec["CD_displayName"] = app.displayName as CKRecordValue
                rec["CD_date"] = today as CKRecordValue
                rec["CD_seconds"] = app.todaySeconds as CKRecordValue
                rec["CD_category"] = app.category as CKRecordValue
                rec["CD_syncTimestamp"] = Date() as CKRecordValue

                toSave.append(rec)
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) history records: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty { return }

        // CloudKit has a limit of 400 records per batch
        let batchSize = 400
        var savedTotal = 0

        for batch in stride(from: 0, to: toSave.count, by: batchSize) {
            let end = min(batch + batchSize, toSave.count)
            let batchRecords = Array(toSave[batch..<end])

            let (savedRecords, _) = try await sharedDB.modifyRecords(saving: batchRecords, deleting: [])
            savedTotal += savedRecords.count

            #if DEBUG
            print("[CloudKitSyncService] Saved batch \(batch/batchSize + 1): \(savedRecords.count) records")
            #endif
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedTotal) daily usage history records to parent's zone")
        #endif
    }

    /// Fetch child's daily usage history from CloudKit shared zones
    /// Returns array of DailyUsageHistoryDTO with per-app daily summaries
    func fetchChildDailyUsageHistory(deviceID: String, daysToFetch: Int = 30) async throws -> [DailyUsageHistoryDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Daily Usage History =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        #endif

        let db = container.privateCloudDatabase
        var results: [DailyUsageHistoryDTO] = []

        // Calculate date range
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -daysToFetch, to: today)!

        // Enumerate all zones (shared zones appear in parent's private database)
        let zones = try await db.allRecordZones()

        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_date >= %@",
                    deviceID, startDate as NSDate
                )
                let query = CKQuery(recordType: "CD_DailyUsageHistory", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) history records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = DailyUsageHistoryDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) on \(dto.date): \(dto.seconds)s (\(dto.category))")
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
        print("[CloudKitSyncService] ✅ Fetched \(results.count) daily usage history records")
        #endif

        return results
    }
}
