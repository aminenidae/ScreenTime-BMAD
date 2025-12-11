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
        let timestamp: Date
    }

    private init() {}

    /// Create monitoring zone with share for cross-account pairing
    func createMonitoringZoneForChild() async throws -> (zoneID: CKRecordZone.ID, share: CKShare) {
        let database = container.privateCloudDatabase

        // 1. Create unique zone for this pairing session
        let zoneID = CKRecordZone.ID(zoneName: "ChildMonitoring-\(UUID().uuidString)")
        let zone = CKRecordZone(zoneID: zoneID)

        // 2. Save the zone
        let savedZone = try await database.save(zone)

        // 3. Create root record for sharing
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
        let payload = PairingPayload(
            shareURL: share.url?.absoluteString ?? "local://screentimerewards.com/pair/\(sessionID)",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: verificationToken,
            sharedZoneID: zoneID.zoneName,
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

    /// Create pairing session with CloudKit sharing
    func createPairingSession() async throws -> (sessionID: String, verificationToken: String, share: CKShare, zoneID: CKRecordZone.ID) {
        // Enforce subscription child-device limit before allowing another pairing
        let currentChildCount = try await cloudKitSync.fetchLinkedChildDevices().count
        guard SubscriptionManager.shared.canPairChildDevice(currentCount: currentChildCount) else {
            throw PairingError.deviceLimitReached
        }

        isPairing = true
        defer { isPairing = false }

        // Generate unique session ID and verification token
        let sessionID = UUID().uuidString
        let verificationToken = UUID().uuidString

        // Create monitoring zone with share
        let (zoneID, share) = try await createMonitoringZoneForChild()

        // Store session locally with expiration
        let sessionData: [String: Any] = [
            "sessionID": sessionID,
            "verificationToken": verificationToken,
            "parentDeviceID": DeviceModeManager.shared.deviceID,
            "parentDeviceName": DeviceModeManager.shared.deviceName,
            "sharedZoneID": zoneID.zoneName,
            "shareURL": share.url?.absoluteString ?? "",
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

        return (sessionID, verificationToken, share, zoneID)
    }

    /// Generate a fallback QR code for pairing when CloudKit is not available
    func generateFallbackPairingQRCode() -> CIImage? {
        let payload = PairingPayload(
            shareURL: "fallback://screentimerewards.com/pair",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: UUID().uuidString,
            sharedZoneID: nil,
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

    /// Accept parent share and register in parent's shared zone
    func acceptParentShareAndRegister(from payload: PairingPayload) async throws {
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
                          userInfo: [NSLocalizedDescriptionKey: "Invalid share URL in payload"])
        }

        // 2. Fetch share metadata
        let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
            container.fetchShareMetadata(with: shareURL) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(domain: "PairingError", code: -1,
                                                        userInfo: [NSLocalizedDescriptionKey: "Unknown error fetching share metadata"]))
                }
            }
        }

        // 3. Accept the share
        try await container.accept(metadata)

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

        // 5. Register in parent's shared zone
        try await registerInParentSharedZone(
            zoneID: metadata.rootRecordID.zoneID,
            rootRecordID: metadata.rootRecordID,
            parentDeviceID: payload.parentDeviceID
        )
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
        isPairing = true
        defer { isPairing = false }

        // Save parent device ID
        UserDefaults.standard.set(payload.parentDeviceID, forKey: "parentDeviceID")

        // Store pairing info locally
        let pairingInfo: [String: Any] = [
            "parentDeviceID": payload.parentDeviceID,
            "verificationToken": payload.verificationToken,
            "pairedAt": Date(),
            "childDeviceID": DeviceModeManager.shared.deviceID,
            "childDeviceName": DeviceModeManager.shared.deviceName
        ]
        UserDefaults.standard.set(pairingInfo, forKey: "childPairingInfo")

        // Register this child device in its OWN CloudKit private database
        do {
            let _ = try await self.cloudKitSync.registerDevice(
                mode: DeviceMode.childDevice,
                childName: nil,
                parentDeviceID: payload.parentDeviceID
            )
        } catch {
            // Don't throw - local pairing succeeded
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

    /// Unpair device
    func unpairDevice() {
        UserDefaults.standard.removeObject(forKey: "parentDeviceID")
        // Additional cleanup as needed
    }

}
