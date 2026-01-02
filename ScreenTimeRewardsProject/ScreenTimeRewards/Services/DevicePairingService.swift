import Foundation
import CoreImage
import CloudKit
import Combine
import CoreData

enum PairingError: LocalizedError {
    case maxParentsReached
    case deviceLimitReached
    case shareNotFound
    case invalidQRCode
    case networkError(Error)
    case sameAccountPairing

    var errorDescription: String? {
        switch self {
        case .maxParentsReached:
            return "This child device is already paired with the maximum number of parent devices (2). Please unpair from one parent before adding another."
        case .deviceLimitReached:
            return "Device limit reached. Upgrade to the Family plan to add more child devices."
        case .shareNotFound:
            return "Pairing invitation not found or expired."
        case .invalidQRCode:
            return "Invalid QR code. Please scan a valid pairing QR code."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .sameAccountPairing:
            return "Cannot pair devices using the same iCloud account. The parent and child devices must use different Apple IDs for data sync to work properly."
        }
    }
}

@MainActor
class DevicePairingService: ObservableObject {
    static let shared = DevicePairingService()

    @Published private(set) var isPairing: Bool = false

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let customZoneID = CKRecordZone.ID(zoneName: "PairingZone", ownerName: CKCurrentUserDefaultName)
    private let cloudKitSync = CloudKitSyncService.shared

    /// Check if CloudKit is available and configured
    func checkCloudKitAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    /// Get current CloudKit user's account identifier
    private func getCurrentUserRecordID() async throws -> CKRecord.ID {
        return try await container.userRecordID()
    }

    /// Ensure the custom zone exists for sharing
    private func ensureCustomZoneExists() async throws {
        let database = container.privateCloudDatabase
        let customZone = CKRecordZone(zoneID: customZoneID)

        do {
            let _ = try await database.save(customZone)
        } catch let error as CKError {
            // Zone already exists error is okay
            if error.code != .serverRecordChanged && error.code != .zoneNotFound {
                throw error
            }
        }
    }

    struct PairingPayload: Codable {
        let shareURL: String
        let parentDeviceID: String
        let verificationToken: String
        let sharedZoneID: String?  // Make optional to maintain backward compatibility
        let commandsShareURL: String?  // Share URL for parent's command zone
        let timestamp: Date
    }

    private init() {}

    /// Create parent commands zone with share for sending commands to children
    /// This zone is owned by parent and shared with all children
    func createParentCommandsZone() async throws -> (zoneID: CKRecordZone.ID, share: CKShare) {
        let database = container.privateCloudDatabase
        let parentDeviceID = DeviceModeManager.shared.deviceID

        // Zone name is deterministic based on parent device ID
        let zoneName = "ParentCommands-\(parentDeviceID)"
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        // Check if zone already exists
        let existingZones = try await database.allRecordZones()
        if let existing = existingZones.first(where: { $0.zoneID.zoneName == zoneName }) {
            // Zone exists, try to find existing share
            #if DEBUG
            print("[DevicePairingService] ParentCommands zone already exists: \(zoneName)")
            #endif

            // Query for existing share root record
            let rootRecordID = CKRecord.ID(recordName: "CommandsRoot-\(parentDeviceID)", zoneID: existing.zoneID)
            do {
                let rootRecord = try await database.record(for: rootRecordID)
                // Try to fetch the share for this record
                if let shareRef = rootRecord.share {
                    let share = try await database.record(for: shareRef.recordID) as! CKShare
                    return (zoneID: existing.zoneID, share: share)
                }
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Existing zone but no share, will create new share")
                #endif
            }
        }

        // Create new zone
        let zone = CKRecordZone(zoneID: zoneID)
        let savedZone = try await database.save(zone)

        #if DEBUG
        print("[DevicePairingService] Created ParentCommands zone: \(savedZone.zoneID.zoneName)")
        #endif

        // Create root record for sharing
        let rootRecordID = CKRecord.ID(recordName: "CommandsRoot-\(parentDeviceID)", zoneID: savedZone.zoneID)
        let rootRecord = CKRecord(recordType: "CommandsRoot", recordID: rootRecordID)
        rootRecord["parentDeviceID"] = parentDeviceID as CKRecordValue
        rootRecord["createdAt"] = Date() as CKRecordValue

        // Create share with readWrite permission
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Parent Commands" as CKRecordValue
        share.publicPermission = .readWrite

        // Save root record and share together
        let (saveResults, _) = try await database.modifyRecords(saving: [rootRecord, share], deleting: [])

        // Extract saved share
        var savedShare = share
        if let result = saveResults[share.recordID], case .success(let record) = result, let s = record as? CKShare {
            savedShare = s
        }

        #if DEBUG
        print("[DevicePairingService] ✅ ParentCommands zone shared")
        print("[DevicePairingService] Share URL: \(savedShare.url?.absoluteString ?? "nil")")
        #endif

        return (zoneID: savedZone.zoneID, share: savedShare)
    }

    /// Create monitoring zone with share for cross-account pairing
    /// Now checks for existing zones and cleans them up to prevent zone accumulation
    func createMonitoringZoneForChild() async throws -> (zoneID: CKRecordZone.ID, share: CKShare) {
        let database = container.privateCloudDatabase

        // 1. Clean up any orphaned zones from previous pairings
        // This prevents zone accumulation when re-pairing the same device
        #if DEBUG
        print("[DevicePairingService] Checking for orphaned zones before creating new pairing zone...")
        #endif

        do {
            let cleanedCount = try await cloudKitSync.cleanupOrphanedZones()
            #if DEBUG
            if cleanedCount > 0 {
                print("[DevicePairingService] ✅ Cleaned up \(cleanedCount) orphaned zone(s)")
            }
            #endif
        } catch {
            #if DEBUG
            print("[DevicePairingService] ⚠️ Zone cleanup failed (non-critical): \(error.localizedDescription)")
            #endif
            // Continue with pairing even if cleanup fails
        }

        // 2. Create unique zone for this pairing session
        let zoneID = CKRecordZone.ID(zoneName: "ChildMonitoring-\(UUID().uuidString)")
        let zone = CKRecordZone(zoneID: zoneID)

        // 3. Save the zone
        let savedZone = try await database.save(zone)

        // 4. Create root record for sharing
        let rootRecordID = CKRecord.ID(recordName: "MonitoringSession-\(UUID().uuidString)", zoneID: savedZone.zoneID)
        let rootRecord = CKRecord(recordType: "MonitoringSession", recordID: rootRecordID)
        rootRecord["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        rootRecord["createdAt"] = Date() as CKRecordValue

        // 4. Create share from root record
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Child Device Monitoring" as CKRecordValue

        // 5. Configure share permissions for write access
        share.publicPermission = .readWrite

        // 6. Save root record and share TOGETHER to avoid reference violations
        let (saveResults, _) = try await database.modifyRecords(saving: [rootRecord, share], deleting: [])

        // Extract saved share
        let savedShare: CKShare
        if let result = saveResults[share.recordID] {
            switch result {
            case .success(let record):
                savedShare = (record as? CKShare) ?? share
            case .failure(let error):
                throw error
            }
        } else {
            // Fallback: try to find any CKShare returned
            if let anyShare = saveResults.values.compactMap({ res -> CKShare? in
                if case .success(let rec) = res { return rec as? CKShare }
                return nil
            }).first {
                savedShare = anyShare
            } else {
                // As a last resort, use the local share (URL may be nil until server processes)
                savedShare = share
            }
        }

        return (zoneID: savedZone.zoneID, share: savedShare)
    }

    /// Generate QR code for pairing with session ID and token
    func generatePairingQRCode(sessionID: String, verificationToken: String, share: CKShare, zoneID: CKRecordZone.ID) -> CIImage? {
        // Read the commands share URL from the stored session data
        var commandsShareURL: String? = nil
        if let sessionData = UserDefaults.standard.dictionary(forKey: "pairingSession_\(sessionID)") {
            commandsShareURL = sessionData["commandsShareURL"] as? String
            if commandsShareURL?.isEmpty == true {
                commandsShareURL = nil
            }
        }

        let payload = PairingPayload(
            shareURL: share.url?.absoluteString ?? "local://screentimerewards.com/pair/\(sessionID)",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: verificationToken,
            sharedZoneID: zoneID.zoneName,
            commandsShareURL: commandsShareURL,
            timestamp: Date()
        )

        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(jsonString.data(using: .utf8), forKey: "inputMessage")
        qrFilter?.setValue("Q", forKey: "inputCorrectionLevel")

        return qrFilter?.outputImage
    }

    /// Create pairing session with CloudKit sharing (REQUIRES CloudKit)
    func createPairingSession() async throws -> (sessionID: String, verificationToken: String, share: CKShare, zoneID: CKRecordZone.ID) {
        #if DEBUG
        print("[DevicePairingService] 🔵 Starting createPairingSession...")
        #endif

        // Check subscription limit - this also verifies CloudKit availability
        #if DEBUG
        print("[DevicePairingService] 🔵 Fetching linked child devices to check limit...")
        #endif

        let currentChildCount: Int
        do {
            currentChildCount = try await cloudKitSync.fetchLinkedChildDevices().count
            #if DEBUG
            print("[DevicePairingService] ✅ CloudKit available. Current child count: \(currentChildCount)")
            #endif
        } catch let error as CKError where error.code == .notAuthenticated {
            #if DEBUG
            print("[DevicePairingService] ❌ CloudKit not authenticated")
            #endif
            throw PairingError.networkError(error)
        } catch {
            #if DEBUG
            print("[DevicePairingService] ❌ CloudKit error: \(error)")
            #endif
            throw PairingError.networkError(error)
        }

        guard SubscriptionManager.shared.canPairChildDevice(currentCount: currentChildCount) else {
            #if DEBUG
            print("[DevicePairingService] ❌ Device limit reached!")
            #endif
            throw PairingError.deviceLimitReached
        }

        isPairing = true
        defer { isPairing = false }

        // Generate unique session ID and verification token
        let sessionID = UUID().uuidString
        let verificationToken = UUID().uuidString

        #if DEBUG
        print("[DevicePairingService] 🔵 Creating CloudKit monitoring zone for child...")
        #endif

        // Create monitoring zone with share
        let (zoneID, share) = try await createMonitoringZoneForChild()

        #if DEBUG
        print("[DevicePairingService] ✅ CloudKit zone created: \(zoneID.zoneName)")
        print("[DevicePairingService] Share URL: \(share.url?.absoluteString ?? "nil")")
        #endif

        // Also create/get the parent commands zone for sending commands to children
        #if DEBUG
        print("[DevicePairingService] 🔵 Creating ParentCommands zone for remote control...")
        #endif

        var commandsShareURL: String? = nil
        do {
            let (_, commandsShare) = try await createParentCommandsZone()
            commandsShareURL = commandsShare.url?.absoluteString
            #if DEBUG
            print("[DevicePairingService] ✅ ParentCommands zone ready")
            print("[DevicePairingService] Commands Share URL: \(commandsShareURL ?? "nil")")
            #endif
        } catch {
            #if DEBUG
            print("[DevicePairingService] ⚠️ Failed to create ParentCommands zone (non-critical): \(error)")
            #endif
            // Non-critical - pairing can still proceed, commands may need manual sharing later
        }

        // Store session locally with expiration
        let sessionData: [String: Any] = [
            "sessionID": sessionID,
            "verificationToken": verificationToken,
            "parentDeviceID": DeviceModeManager.shared.deviceID,
            "parentDeviceName": DeviceModeManager.shared.deviceName,
            "sharedZoneID": zoneID.zoneName,
            "shareURL": share.url?.absoluteString ?? "",
            "commandsShareURL": commandsShareURL ?? "",
            "createdAt": Date(),
            "expiresAt": Date().addingTimeInterval(600) // 10 minutes
        ]

        UserDefaults.standard.set(sessionData, forKey: "pairingSession_\(sessionID)")

        #if DEBUG
        print("[DevicePairingService] ✅ Pairing session created successfully!")
        #endif

        // Register this parent device in CloudKit (private database)
        Task {
            do {
                let _ = try await self.cloudKitSync.registerDevice(mode: DeviceMode.parentDevice, childName: nil)
            } catch {
                // Silent failure - non-critical
                #if DEBUG
                print("[DevicePairingService] ⚠️ Failed to register parent device (non-critical): \(error)")
                #endif
            }
        }

        return (sessionID, verificationToken, share, zoneID)
    }

    /// Generate a fallback QR code for pairing when CloudKit is not available
    func generateFallbackPairingQRCode() -> CIImage? {
        let payload = PairingPayload(
            shareURL: "fallback://screentimerewards.com/pair",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: UUID().uuidString,
            sharedZoneID: nil,
            commandsShareURL: nil,
            timestamp: Date()
        )

        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(jsonString.data(using: .utf8), forKey: "inputMessage")
        qrFilter?.setValue("Q", forKey: "inputCorrectionLevel")

        return qrFilter?.outputImage
    }

    /// Parse scanned QR code
    func parsePairingQRCode(_ jsonString: String) -> PairingPayload? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(PairingPayload.self, from: data)
    }

    /// Create local pairing session (no CloudKit required)
    func createLocalPairingSession() -> (sessionID: String, verificationToken: String) {
        isPairing = true
        defer { isPairing = false }

        // Generate unique session ID and verification token
        let sessionID = UUID().uuidString
        let verificationToken = UUID().uuidString

        // Store session locally with expiration
        let sessionData: [String: Any] = [
            "sessionID": sessionID,
            "verificationToken": verificationToken,
            "parentDeviceID": DeviceModeManager.shared.deviceID,
            "parentDeviceName": DeviceModeManager.shared.deviceName,
            "createdAt": Date(),
            "expiresAt": Date().addingTimeInterval(600) // 10 minutes
        ]

        UserDefaults.standard.set(sessionData, forKey: "pairingSession_\(sessionID)")

        // Register this parent device in CloudKit (private database)
        Task {
            do {
                let _ = try await self.cloudKitSync.registerDevice(mode: DeviceMode.parentDevice, childName: nil)
            } catch {
                // Silent failure - non-critical
            }
        }

        return (sessionID, verificationToken)
    }

    /// Accept parent share and register in parent's shared zone (REQUIRES CloudKit)
    func acceptParentShareAndRegister(from payload: PairingPayload) async throws {
        #if DEBUG
        print("[DevicePairingService] 🔵 Child: Starting CloudKit pairing process...")
        print("[DevicePairingService] Share URL: \(payload.shareURL)")
        #endif

        // Check how many parents this child is already paired with
        let currentParentCount = try await getParentPairingCount()

        guard currentParentCount < 2 else {
            throw PairingError.maxParentsReached
        }

        isPairing = true
        defer { isPairing = false }

        // 1. Parse share URL from payload
        guard let shareURL = URL(string: payload.shareURL) else {
            throw NSError(domain: "PairingError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid pairing QR code. The share URL is malformed."])
        }

        #if DEBUG
        print("[DevicePairingService] 🔵 Fetching CloudKit share metadata...")
        #endif

        // 2. Fetch share metadata
        let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
            container.fetchShareMetadata(with: shareURL) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(domain: "PairingError", code: -1,
                                                        userInfo: [NSLocalizedDescriptionKey: "Unable to fetch pairing information from iCloud."]))
                }
            }
        }

        // CRITICAL: Validate that parent and child use different iCloud accounts.
        // CloudKit sharing allows same-account share acceptance, but this causes
        // data corruption issues in our app architecture where:
        // - Parent queries both private and shared zones
        // - Child writes to shared zone
        // - Same account would see duplicate/conflicting data
        // Therefore, we explicitly reject same-account pairing.
        #if DEBUG
        print("[DevicePairingService] 🔵 Validating share owner is different account...")
        #endif

        // Check if trying to pair with same iCloud account
        let currentUserID = try await getCurrentUserRecordID()
        let shareOwnerID = metadata.rootRecordID.zoneID.ownerName

        #if DEBUG
        print("[DevicePairingService] Current user: \(currentUserID.recordName)")
        print("[DevicePairingService] Share owner: \(shareOwnerID)")
        #endif

        if currentUserID.recordName == shareOwnerID {
            #if DEBUG
            print("[DevicePairingService] ❌ Same-account pairing detected!")
            #endif
            throw PairingError.sameAccountPairing
        }

        #if DEBUG
        print("[DevicePairingService] ✅ Different accounts confirmed")
        #endif

        #if DEBUG
        print("[DevicePairingService] 🔵 Accepting CloudKit share...")
        #endif

        // 3. Accept the share
        try await container.accept(metadata)

        // 3b. Also accept the commands share if provided (for receiving parent commands)
        if let commandsShareURLString = payload.commandsShareURL,
           let commandsShareURL = URL(string: commandsShareURLString) {
            #if DEBUG
            print("[DevicePairingService] 🔵 Also accepting parent commands share...")
            #endif

            do {
                let commandsMetadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
                    container.fetchShareMetadata(with: commandsShareURL) { metadata, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let metadata = metadata {
                            continuation.resume(returning: metadata)
                        } else {
                            continuation.resume(throwing: NSError(domain: "PairingError", code: -1,
                                                                userInfo: [NSLocalizedDescriptionKey: "Unable to fetch commands share metadata."]))
                        }
                    }
                }
                try await container.accept(commandsMetadata)
                UserDefaults.standard.set(commandsMetadata.rootRecordID.zoneID.zoneName, forKey: "parentCommandsZoneID")
                #if DEBUG
                print("[DevicePairingService] ✅ Parent commands share accepted")
                #endif
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Failed to accept commands share (non-critical): \(error.localizedDescription)")
                #endif
                // Non-critical - can be accepted later when receiving first command
            }
        }

        // 4. Save parent device ID and shared zone ID locally
        UserDefaults.standard.set(payload.parentDeviceID, forKey: "parentDeviceID")
        if let sharedZoneID = payload.sharedZoneID {
            UserDefaults.standard.set(sharedZoneID, forKey: "parentSharedZoneID")
        }

        // Persist share context for sync (root record name needed for parent reference)
        let rootID = metadata.rootRecordID
        let zoneID = metadata.rootRecordID.zoneID

        UserDefaults.standard.set(rootID.recordName, forKey: "parentSharedRootRecordName")
        UserDefaults.standard.set(zoneID.zoneName, forKey: "parentSharedZoneID")
        UserDefaults.standard.set(zoneID.ownerName, forKey: "parentSharedZoneOwner")

        #if DEBUG
        print("[DevicePairingService] 🔵 Registering child in parent's shared zone...")
        #endif

        // 5. Register in parent's shared zone
        try await registerInParentSharedZone(
            zoneID: metadata.rootRecordID.zoneID,
            rootRecordID: metadata.rootRecordID,
            parentDeviceID: payload.parentDeviceID
        )

        #if DEBUG
        print("[DevicePairingService] ✅ CloudKit pairing completed successfully!")
        #endif
    }

    // Get count of parent devices child is currently paired with
    private func getParentPairingCount() async throws -> Int {
        let container = CKContainer(identifier: "iCloud.com.screentimerewards")
        let sharedDatabase = container.sharedCloudDatabase

        // Query all shared zones this child device has access to
        let query = CKQuery(
            recordType: "CD_SharedZoneRoot",
            predicate: NSPredicate(value: true)
        )

        do {
            let (results, _) = try await sharedDatabase.records(matching: query)
            return results.count
        } catch {
            // If we can't determine, allow the pairing (fail open)
            return 0
        }
    }

    /// Register child device in parent's shared zone
    func registerInParentSharedZone(zoneID: CKRecordZone.ID, rootRecordID: CKRecord.ID, parentDeviceID: String) async throws {
        // Use sharedCloudDatabase (child's view of parent's zone)
        let sharedDatabase = container.sharedCloudDatabase

        // Create device record in PARENT'S shared zone
        let deviceRecordID = CKRecord.ID(
            recordName: "device-\(DeviceModeManager.shared.deviceID)",
            zoneID: zoneID  // Parent's zone!
        )

        let deviceRecord = CKRecord(recordType: "CD_RegisteredDevice", recordID: deviceRecordID)
        // Link the new record to the shared root so it belongs to the share
        deviceRecord.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)
        deviceRecord["CD_deviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        deviceRecord["CD_deviceName"] = DeviceModeManager.shared.deviceName as CKRecordValue
        deviceRecord["CD_deviceType"] = "child" as CKRecordValue
        deviceRecord["CD_parentDeviceID"] = parentDeviceID as CKRecordValue
        deviceRecord["CD_registrationDate"] = Date() as CKRecordValue
        deviceRecord["CD_isActive"] = 1 as CKRecordValue

        // Save to SHARED database
        let _ = try await sharedDatabase.save(deviceRecord)
    }

    /// Accept pairing from parent (local-only, no CloudKit writes)
    func acceptParentPairing(from payload: PairingPayload) async throws {
        #if DEBUG
        print("[DevicePairingService] 🔵 Child: Accepting local-only pairing...")
        #endif

        // Check if already paired with a parent
        if let existingParentID = UserDefaults.standard.string(forKey: "parentDeviceID"),
           existingParentID != payload.parentDeviceID {
            #if DEBUG
            print("[DevicePairingService] ⚠️ Already paired with another parent. Local pairing only supports 1 parent.")
            #endif
            throw PairingError.maxParentsReached
        }

        isPairing = true
        defer { isPairing = false }

        // Save parent device ID
        UserDefaults.standard.set(payload.parentDeviceID, forKey: "parentDeviceID")

        #if DEBUG
        print("[DevicePairingService] ✅ Saved parent device ID: \(payload.parentDeviceID)")
        #endif

        // Store pairing info locally
        let pairingInfo: [String: Any] = [
            "parentDeviceID": payload.parentDeviceID,
            "verificationToken": payload.verificationToken,
            "pairedAt": Date(),
            "childDeviceID": DeviceModeManager.shared.deviceID,
            "childDeviceName": DeviceModeManager.shared.deviceName
        ]
        UserDefaults.standard.set(pairingInfo, forKey: "childPairingInfo")

        // Register this child device in its OWN CloudKit private database (best effort)
        do {
            let _ = try await self.cloudKitSync.registerDevice(
                mode: DeviceMode.childDevice,
                childName: nil,
                parentDeviceID: payload.parentDeviceID
            )
            #if DEBUG
            print("[DevicePairingService] ✅ Registered child device in CloudKit (optional)")
            #endif
        } catch {
            // Don't throw - local pairing succeeded even if CloudKit registration fails
            #if DEBUG
            print("[DevicePairingService] ⚠️ CloudKit registration failed (non-critical): \(error)")
            #endif
        }
    }

    /// Get parent device ID for child device
    func getParentDeviceID() -> String? {
        return UserDefaults.standard.string(forKey: "parentDeviceID")
    }

    /// Check if device is already paired
    func isPaired() -> Bool {
        return getParentDeviceID() != nil
    }

    /// Get all pairing info for display/debugging
    func getPairingInfo() -> [String: Any]? {
        return UserDefaults.standard.dictionary(forKey: "childPairingInfo")
    }

    /// Unpair child device from parent - clears all pairing data
    /// Call this on the child device to disconnect from parent
    func unpairDevice() {
        #if DEBUG
        print("[DevicePairingService] ===== Child Unpairing from Parent =====")
        #endif

        // Clear parent device ID
        UserDefaults.standard.removeObject(forKey: "parentDeviceID")

        // Clear zone/share info
        UserDefaults.standard.removeObject(forKey: "parentSharedZoneID")
        UserDefaults.standard.removeObject(forKey: "parentSharedZoneOwner")
        UserDefaults.standard.removeObject(forKey: "parentSharedRootRecordName")
        UserDefaults.standard.removeObject(forKey: "parentCommandsZoneID")

        // Clear pairing info
        UserDefaults.standard.removeObject(forKey: "childPairingInfo")

        // Note: We don't reset the device mode - child can re-pair with a different parent
        // and doesn't need to go through mode selection again

        #if DEBUG
        print("[DevicePairingService] ✅ All pairing data cleared")
        #endif
    }

    /// Check if child has valid pairing with zone info
    func hasValidPairing() -> Bool {
        guard let _ = getParentDeviceID() else { return false }
        guard let _ = UserDefaults.standard.string(forKey: "parentSharedZoneID") else { return false }
        return true
    }

}

