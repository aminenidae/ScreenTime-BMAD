import Foundation
import CoreData
import CloudKit

/// Processes configuration commands sent from parent device.
/// This runs on the child device when commands are received via CloudKit.
@MainActor
class ChildConfigCommandProcessor {
    static let shared = ChildConfigCommandProcessor()

    private let scheduleService = AppScheduleService.shared
    private let cloudKitService = CloudKitSyncService.shared
    private let persistenceController = PersistenceController.shared

    private init() {}

    // MARK: - Main Processing

    /// Process a full configuration update command from parent
    func processFullConfigCommand(_ command: ConfigurationCommand) async throws {
        guard command.commandType == "update_full_config",
              let payloadString = command.payloadJSON,
              !payloadString.isEmpty
        else {
            #if DEBUG
            print("[ChildConfigCommandProcessor] Invalid command or empty payload")
            #endif
            throw ProcessingError.invalidPayload
        }

        // Decode the payload
        let payload: FullConfigUpdatePayload
        do {
            payload = try FullConfigUpdatePayload.fromBase64String(payloadString)
        } catch {
            #if DEBUG
            print("[ChildConfigCommandProcessor] Failed to decode payload: \(error)")
            #endif
            throw ProcessingError.decodingFailed(error)
        }

        #if DEBUG
        print("[ChildConfigCommandProcessor] ===== Processing Full Config Command =====")
        print("[ChildConfigCommandProcessor] Command ID: \(payload.commandID)")
        print("[ChildConfigCommandProcessor] App: \(payload.logicalID)")
        print("[ChildConfigCommandProcessor] Category: \(payload.category)")
        print("[ChildConfigCommandProcessor] Parent modified at: \(payload.parentModifiedAt)")
        #endif

        // Check for conflicts with local changes
        let conflictResult = checkForConflicts(payload)
        if conflictResult.hasConflict {
            if !conflictResult.parentWins {
                #if DEBUG
                print("[ChildConfigCommandProcessor] Conflict detected - local changes are newer, skipping")
                #endif
                // Mark command as executed but note the conflict
                try await markCommandWithConflict(command, reason: "Local changes newer")
                return
            }
            #if DEBUG
            print("[ChildConfigCommandProcessor] Conflict detected - parent wins, applying changes")
            #endif
        }

        // Apply the configuration
        try await applyConfiguration(payload)

        // Mark command as executed
        try await cloudKitService.markConfigurationCommandExecuted(payload.commandID)

        // Sync updated config to CloudKit so parent can see the changes
        try await cloudKitService.uploadAppConfigurationsToParent()

        #if DEBUG
        print("[ChildConfigCommandProcessor] ✅ Command processed successfully: \(payload.commandID)")
        #endif
    }

    /// Process all pending commands for this device
    /// Fetches commands from CloudKit shared zone (not Core Data)
    func processPendingCommands() async throws -> Int {
        // Fetch commands from CloudKit shared zone
        let commandRecords = try await cloudKitService.fetchPendingCommandsFromSharedZone()

        #if DEBUG
        print("[ChildConfigCommandProcessor] Found \(commandRecords.count) pending command(s) in shared zone")
        #endif

        var processedCount = 0
        for record in commandRecords {
            do {
                guard let commandType = record["commandType"] as? String,
                      commandType == "update_full_config" else {
                    continue
                }

                try await processFullConfigCommandFromSharedZone(record)
                processedCount += 1
            } catch {
                let cmdID = record["commandID"] as? String ?? "?"
                #if DEBUG
                print("[ChildConfigCommandProcessor] Error processing command \(cmdID): \(error)")
                #endif
                // Mark command as failed in CloudKit
                try await markCommandFailedInSharedZone(record, error: error)
            }
        }

        return processedCount
    }

    /// Process a configuration command from CloudKit shared zone (CKRecord)
    private func processFullConfigCommandFromSharedZone(_ record: CKRecord) async throws {
        guard let payloadString = record["payloadJSON"] as? String,
              !payloadString.isEmpty else {
            #if DEBUG
            print("[ChildConfigCommandProcessor] Invalid command or empty payload")
            #endif
            throw ProcessingError.invalidPayload
        }

        // Decode the payload
        let payload: FullConfigUpdatePayload
        do {
            payload = try FullConfigUpdatePayload.fromBase64String(payloadString)
        } catch {
            #if DEBUG
            print("[ChildConfigCommandProcessor] Failed to decode payload: \(error)")
            #endif
            throw ProcessingError.decodingFailed(error)
        }

        #if DEBUG
        print("[ChildConfigCommandProcessor] ===== Processing Full Config Command (Shared Zone) =====")
        print("[ChildConfigCommandProcessor] Command ID: \(payload.commandID)")
        print("[ChildConfigCommandProcessor] App: \(payload.logicalID)")
        print("[ChildConfigCommandProcessor] Category: \(payload.category)")
        print("[ChildConfigCommandProcessor] Linked apps: \(payload.linkedLearningApps.count)")
        #endif

        // Check for conflicts with local changes
        let conflictResult = checkForConflicts(payload)
        if conflictResult.hasConflict {
            if !conflictResult.parentWins {
                #if DEBUG
                print("[ChildConfigCommandProcessor] Conflict detected - local changes are newer, skipping")
                #endif
                // Mark command as conflict in CloudKit
                try await markCommandConflictInSharedZone(record, reason: "Local changes newer")
                return
            }
            #if DEBUG
            print("[ChildConfigCommandProcessor] Conflict detected - parent wins, applying changes")
            #endif
        }

        // Apply the configuration
        try await applyConfiguration(payload)

        // Mark command as executed in CloudKit shared zone
        try await cloudKitService.markCommandExecutedInSharedZone(record)

        // Sync updated config to CloudKit so parent can see the changes
        try await cloudKitService.uploadAppConfigurationsToParent()

        #if DEBUG
        print("[ChildConfigCommandProcessor] ✅ Command processed successfully: \(payload.commandID)")
        #endif
    }

    /// Mark a command as failed in CloudKit shared zone
    private func markCommandFailedInSharedZone(_ record: CKRecord, error: Error) async throws {
        let sharedDB = CKContainer(identifier: "iCloud.com.screentimerewards").sharedCloudDatabase

        record["status"] = "failed" as CKRecordValue
        record["errorMessage"] = error.localizedDescription as CKRecordValue
        record["executedAt"] = Date() as CKRecordValue

        try await sharedDB.save(record)

        #if DEBUG
        let cmdID = record["commandID"] as? String ?? "?"
        print("[ChildConfigCommandProcessor] Command marked as failed: \(cmdID)")
        #endif
    }

    /// Mark a command as conflict in CloudKit shared zone
    private func markCommandConflictInSharedZone(_ record: CKRecord, reason: String) async throws {
        let sharedDB = CKContainer(identifier: "iCloud.com.screentimerewards").sharedCloudDatabase

        record["status"] = "conflict" as CKRecordValue
        record["errorMessage"] = reason as CKRecordValue
        record["executedAt"] = Date() as CKRecordValue

        try await sharedDB.save(record)

        #if DEBUG
        let cmdID = record["commandID"] as? String ?? "?"
        print("[ChildConfigCommandProcessor] Command marked with conflict: \(cmdID)")
        #endif
    }

    // MARK: - Configuration Application

    private func applyConfiguration(_ payload: FullConfigUpdatePayload) async throws {
        #if DEBUG
        print("[ChildConfigCommandProcessor] Applying configuration for: \(payload.logicalID)")
        print("[ChildConfigCommandProcessor] Linked apps in payload: \(payload.linkedLearningApps.count)")
        #endif

        // 1. Prepare schedule config - use existing or create new
        var scheduleConfig: AppScheduleConfiguration
        if let existingConfig = payload.scheduleConfig {
            scheduleConfig = existingConfig
            #if DEBUG
            print("[ChildConfigCommandProcessor] Using existing schedule config")
            #endif
        } else {
            // Create a new schedule config from payload
            scheduleConfig = AppScheduleConfiguration(
                logicalID: payload.logicalID,
                allowedTimeWindow: .fullDay,
                dailyLimits: payload.category == "Reward" ? .defaultReward : .unlimited,
                isEnabled: payload.isEnabled
            )
            #if DEBUG
            print("[ChildConfigCommandProcessor] Created new schedule config")
            #endif
        }

        // 2. CRITICAL: Always use top-level payload values for these fields
        // The top-level values are the UPDATED values from parent editing
        // The scheduleConfig may have STALE values due to data duplication
        scheduleConfig.linkedLearningApps = payload.linkedLearningApps
        scheduleConfig.unlockMode = payload.unlockMode
        scheduleConfig.streakSettings = payload.streakSettings
        scheduleConfig.isEnabled = payload.isEnabled

        #if DEBUG
        print("[ChildConfigCommandProcessor] Merged linkedLearningApps: \(scheduleConfig.linkedLearningApps.count)")
        print("[ChildConfigCommandProcessor] Unlock mode: \(scheduleConfig.unlockMode.rawValue)")
        #endif

        // 3. Save the merged config
        try scheduleService.saveSchedule(scheduleConfig)

        // 2. Update Core Data AppConfiguration
        try await updateAppConfiguration(payload)

        // 3. Sync goal configs to extension for shield control
        ScreenTimeService.shared.syncGoalConfigsToExtension()

        #if DEBUG
        print("[ChildConfigCommandProcessor] Configuration applied successfully")
        #endif
    }

    private func updateAppConfiguration(_ payload: FullConfigUpdatePayload) async throws {
        let context = persistenceController.container.viewContext

        // Find existing AppConfiguration or create new one
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "logicalID == %@ AND deviceID == %@",
            payload.logicalID,
            payload.targetDeviceID
        )

        let existingConfigs = try context.fetch(fetchRequest)
        let appConfig: AppConfiguration

        if let existing = existingConfigs.first {
            appConfig = existing
            #if DEBUG
            print("[ChildConfigCommandProcessor] Updating existing AppConfiguration")
            #endif
        } else {
            appConfig = AppConfiguration(context: context)
            appConfig.logicalID = payload.logicalID
            appConfig.deviceID = payload.targetDeviceID
            appConfig.dateAdded = Date()
            #if DEBUG
            print("[ChildConfigCommandProcessor] Creating new AppConfiguration")
            #endif
        }

        // Update fields
        appConfig.category = payload.category
        appConfig.pointsPerMinute = Int16(payload.pointsPerMinute)
        appConfig.isEnabled = payload.isEnabled
        appConfig.blockingEnabled = payload.blockingEnabled
        appConfig.lastModified = Date()
        appConfig.syncStatus = "synced"

        try context.save()
    }

    // MARK: - Conflict Resolution

    struct ConflictResult {
        let hasConflict: Bool
        let parentWins: Bool
    }

    private func checkForConflicts(_ payload: FullConfigUpdatePayload) -> ConflictResult {
        // Get local config's last modified date
        guard scheduleService.getSchedule(for: payload.logicalID) != nil else {
            // No local config = no conflict
            return ConflictResult(hasConflict: false, parentWins: true)
        }

        // For now, parent always wins (simplest conflict resolution)
        // In a more sophisticated implementation, we'd compare timestamps
        // and potentially show a conflict resolution UI

        #if DEBUG
        print("[ChildConfigCommandProcessor] Conflict check:")
        print("  Local config exists: true")
        print("  Parent modified at: \(payload.parentModifiedAt)")
        print("  Resolution: Parent wins")
        #endif

        return ConflictResult(hasConflict: true, parentWins: true)
    }

    // MARK: - Command Status Updates

    private func markCommandFailed(_ command: ConfigurationCommand, error: Error) async throws {
        let context = persistenceController.container.viewContext

        command.status = "failed"
        command.errorMessage = error.localizedDescription
        command.executedAt = Date()

        try context.save()

        #if DEBUG
        print("[ChildConfigCommandProcessor] Command marked as failed: \(command.commandID ?? "?")")
        #endif
    }

    private func markCommandWithConflict(_ command: ConfigurationCommand, reason: String) async throws {
        let context = persistenceController.container.viewContext

        command.status = "conflict"
        command.errorMessage = reason
        command.executedAt = Date()

        try context.save()

        #if DEBUG
        print("[ChildConfigCommandProcessor] Command marked with conflict: \(command.commandID ?? "?")")
        #endif
    }

    // MARK: - Error Types

    enum ProcessingError: LocalizedError {
        case invalidPayload
        case decodingFailed(Error)
        case applicationFailed(Error)
        case configNotFound

        var errorDescription: String? {
            switch self {
            case .invalidPayload:
                return "Invalid command payload"
            case .decodingFailed(let error):
                return "Failed to decode payload: \(error.localizedDescription)"
            case .applicationFailed(let error):
                return "Failed to apply configuration: \(error.localizedDescription)"
            case .configNotFound:
                return "Configuration not found on device"
            }
        }
    }
}
