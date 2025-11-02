import Foundation
import CoreImage
import CloudKit
import Combine
import CoreData

@MainActor
class DevicePairingService: ObservableObject {
    static let shared = DevicePairingService()

    @Published private(set) var isPairing: Bool = false

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let customZoneID = CKRecordZone.ID(zoneName: "PairingZone", ownerName: CKCurrentUserDefaultName)
    private let cloudKitSync = CloudKitSyncService.shared

    /// Check if CloudKit is available and configured
    func checkCloudKitAvailability() async -> Bool {
        #if DEBUG
        print("[DevicePairingService] ===== Checking CloudKit Availability =====")
        print("[DevicePairingService] Container ID: iCloud.com.screentimerewards")
        #endif

        do {
            let status = try await container.accountStatus()
            #if DEBUG
            let statusString: String
            switch status {
            case .available: statusString = "Available"
            case .couldNotDetermine: statusString = "Could Not Determine"
            case .restricted: statusString = "Restricted"
            case .noAccount: statusString = "No Account"
            case .temporarilyUnavailable: statusString = "Temporarily Unavailable"
            @unknown default: statusString = "Unknown (\(status.rawValue))"
            }
            print("[DevicePairingService] CloudKit account status: \(statusString)")
            #endif
            return status == .available
        } catch {
            #if DEBUG
            print("[DevicePairingService] CloudKit availability check failed: \(error)")
            print("[DevicePairingService] Error details: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Ensure the custom zone exists for sharing
    private func ensureCustomZoneExists() async throws {
        #if DEBUG
        print("[DevicePairingService] Ensuring custom zone exists: \(customZoneID.zoneName)")
        #endif

        let database = container.privateCloudDatabase
        let customZone = CKRecordZone(zoneID: customZoneID)

        do {
            let _ = try await database.save(customZone)
            #if DEBUG
            print("[DevicePairingService] Custom zone created or already exists")
            #endif
        } catch let error as CKError {
            // Zone already exists error is okay
            if error.code == .serverRecordChanged || error.code == .zoneNotFound {
                #if DEBUG
                print("[DevicePairingService] Zone may already exist, continuing...")
                #endif
            } else {
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
        #if DEBUG
        print("[DevicePairingService] ===== Creating Monitoring Zone with Share =====")
        #endif

        let database = container.privateCloudDatabase
        
        // 1. Create unique zone for this pairing session
        let zoneID = CKRecordZone.ID(zoneName: "ChildMonitoring-\(UUID().uuidString)")
        let zone = CKRecordZone(zoneID: zoneID)
        
        #if DEBUG
        print("[DevicePairingService] Creating zone: \(zoneID.zoneName)")
        #endif

        // 2. Save the zone
        let savedZone = try await database.save(zone)
        
        // 3. Create root record for sharing
        let rootRecordID = CKRecord.ID(recordName: "MonitoringSession-\(UUID().uuidString)", zoneID: savedZone.zoneID)
        let rootRecord = CKRecord(recordType: "MonitoringSession", recordID: rootRecordID)
        rootRecord["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        rootRecord["createdAt"] = Date() as CKRecordValue
        
        #if DEBUG
        print("[DevicePairingService] Creating root record: \(rootRecordID.recordName)")
        #endif

        // 4. Create share from root record
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Child Device Monitoring" as CKRecordValue
        
        // 5. Configure share permissions for write access
        // Research indicates we need to set publicPermission for write access
        share.publicPermission = .readWrite
        
        #if DEBUG
        print("[DevicePairingService] Creating share with write permissions")
        #endif

        // 6. Save root record and share TOGETHER to avoid reference violations
        // Saving separately can cause "Reference Violation" if one references the other.
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
        
        #if DEBUG
        print("[DevicePairingService] ✅ Zone and share created successfully")
        print("[DevicePairingService] Zone ID: \(savedZone.zoneID.zoneName)")
        print("[DevicePairingService] Share URL: \(savedShare.url?.absoluteString ?? "nil")")
        #endif

        return (zoneID: savedZone.zoneID, share: savedShare)
    }
    
    /// Generate QR code for pairing with session ID and token
    func generatePairingQRCode(sessionID: String, verificationToken: String, share: CKShare, zoneID: CKRecordZone.ID) -> CIImage? {
        let payload = PairingPayload(
            shareURL: share.url?.absoluteString ?? "local://screentimerewards.com/pair/\(sessionID)",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: verificationToken,
            sharedZoneID: zoneID.zoneName,  // NEW: Include zone ID
            timestamp: Date()
        )

        #if DEBUG
        print("[DevicePairingService] Generating QR code for CloudKit sharing")
        print("  - Share URL: \(share.url?.absoluteString ?? "nil")")
        print("  - Parent Device ID: \(DeviceModeManager.shared.deviceID)")
        print("  - Shared Zone ID: \(zoneID.zoneName)")
        #endif

        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[DevicePairingService] ERROR: Failed to encode payload")
            #endif
            return nil
        }

        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(jsonString.data(using: .utf8), forKey: "inputMessage")
        qrFilter?.setValue("Q", forKey: "inputCorrectionLevel")

        if let outputImage = qrFilter?.outputImage {
            #if DEBUG
            print("[DevicePairingService] ✅ QR code generated successfully for CloudKit sharing")
            #endif
            return outputImage
        } else {
            #if DEBUG
            print("[DevicePairingService] ERROR: Failed to generate QR code")
            #endif
            return nil
        }
    }
    
    /// Create pairing session with CloudKit sharing
    func createPairingSession() async throws -> (sessionID: String, verificationToken: String, share: CKShare, zoneID: CKRecordZone.ID) {
        #if DEBUG
        print("[DevicePairingService] ===== Creating Pairing Session with CloudKit Sharing =====")
        #endif

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

        #if DEBUG
        print("[DevicePairingService] ✅ Pairing session created with CloudKit sharing:")
        print("  - Session ID: \(sessionID)")
        print("  - Parent Device ID: \(DeviceModeManager.shared.deviceID)")
        print("  - Parent Device Name: \(DeviceModeManager.shared.deviceName)")
        print("  - Verification Token: \(verificationToken)")
        print("  - Shared Zone ID: \(zoneID.zoneName)")
        print("  - Share URL: \(share.url?.absoluteString ?? "nil")")
        print("  - Expires in: 10 minutes")
        #endif

        // Register this parent device in CloudKit (private database)
        Task {
            do {
                let _ = try await self.cloudKitSync.registerDevice(mode: DeviceMode.parentDevice, childName: nil)
                #if DEBUG
                print("[DevicePairingService] Parent device registered in private database")
                #endif
            } catch {
                #if DEBUG
                print("[DevicePairingService] Failed to register parent device: \(error)")
                #endif
            }
        }

        return (sessionID, verificationToken, share, zoneID)
    }

    /// Generate a fallback QR code for pairing when CloudKit is not available
    func generateFallbackPairingQRCode() -> CIImage? {
        #if DEBUG
        print("[DevicePairingService] ===== Generating Fallback QR Code =====")
        #endif

        let payload = PairingPayload(
            shareURL: "fallback://screentimerewards.com/pair",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: UUID().uuidString,
            sharedZoneID: nil,  // nil for fallback
            timestamp: Date()
        )

        #if DEBUG
        print("[DevicePairingService] Payload created: \(payload)")
        #endif

        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[DevicePairingService] ERROR: Failed to encode payload to JSON")
            #endif
            return nil
        }

        #if DEBUG
        print("[DevicePairingService] JSON string: \(jsonString)")
        print("[DevicePairingService] JSON length: \(jsonString.count) characters")
        #endif

        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(jsonString.data(using: .utf8), forKey: "inputMessage")
        qrFilter?.setValue("Q", forKey: "inputCorrectionLevel")

        if let outputImage = qrFilter?.outputImage {
            #if DEBUG
            print("[DevicePairingService] QR code generated successfully")
            print("[DevicePairingService] QR code extent: \(outputImage.extent)")
            #endif
            return outputImage
        } else {
            #if DEBUG
            print("[DevicePairingService] ERROR: CIFilter failed to generate QR code")
            #endif
            return nil
        }
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
        #if DEBUG
        print("[DevicePairingService] ===== Creating Local Pairing Session (No CloudKit) =====")
        #endif

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

        #if DEBUG
        print("[DevicePairingService] ✅ Local pairing session created:")
        print("  - Session ID: \(sessionID)")
        print("  - Parent Device ID: \(DeviceModeManager.shared.deviceID)")
        print("  - Parent Device Name: \(DeviceModeManager.shared.deviceName)")
        print("  - Verification Token: \(verificationToken)")
        print("  - Expires in: 10 minutes")
        #endif

        // Register this parent device in CloudKit (private database)
        Task {
            do {
                let _ = try await self.cloudKitSync.registerDevice(mode: DeviceMode.parentDevice, childName: nil)
                #if DEBUG
                print("[DevicePairingService] Parent device registered in private database")
                #endif
            } catch {
                #if DEBUG
                print("[DevicePairingService] Failed to register parent device: \(error)")
                #endif
            }
        }

        return (sessionID, verificationToken)
    }
    
    /// Accept parent share and register in parent's shared zone
    func acceptParentShareAndRegister(from payload: PairingPayload) async throws {
        #if DEBUG
        print("[DevicePairingService] ===== Accepting Parent Share and Registering =====")
        print("[DevicePairingService] Parent Device ID: \(payload.parentDeviceID)")
        print("[DevicePairingService] Share URL: \(payload.shareURL)")
        print("[DevicePairingService] Shared Zone ID: \(payload.sharedZoneID ?? "nil")")
        #endif

        isPairing = true
        defer { isPairing = false }

        // 1. Parse share URL from payload
        guard let shareURL = URL(string: payload.shareURL) else {
            let error = NSError(domain: "PairingError", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid share URL in payload"])
            #if DEBUG
            print("[DevicePairingService] ❌ Invalid share URL: \(payload.shareURL)")
            #endif
            throw error
        }

        // 2. Fetch share metadata
        #if DEBUG
        print("[DevicePairingService] Fetching share metadata...")
        #endif
        
        // Use the completion handler version and convert to async
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
        #if DEBUG
        print("[DevicePairingService] Accepting share...")
        #endif
        try await container.accept(metadata)

        // 4. Save parent device ID and shared zone ID locally
        UserDefaults.standard.set(payload.parentDeviceID, forKey: "parentDeviceID")
        if let sharedZoneID = payload.sharedZoneID {
            UserDefaults.standard.set(sharedZoneID, forKey: "parentSharedZoneID")
        }

        // === TASK 6 IMPLEMENTATION ===
        // Persist share context for sync (root record name needed for parent reference)
        let rootID = metadata.rootRecordID
        let zoneID = metadata.rootRecordID.zoneID

        UserDefaults.standard.set(rootID.recordName, forKey: "parentSharedRootRecordName")
        UserDefaults.standard.set(zoneID.zoneName, forKey: "parentSharedZoneID")
        UserDefaults.standard.set(zoneID.ownerName, forKey: "parentSharedZoneOwner")  // 🔧 FIX: Save zone owner!
        // === END TASK 6 IMPLEMENTATION ===

        #if DEBUG
        print("[DevicePairingService] ✅ Share accepted successfully")
        print("[DevicePairingService] Parent device ID saved: \(payload.parentDeviceID)")
        print("[DevicePairingService] Shared zone name saved: \(zoneID.zoneName)")
        print("[DevicePairingService] Shared zone owner saved: \(zoneID.ownerName)")
        print("[DevicePairingService] Root record name saved: \(rootID.recordName)")
        #endif

        // 5. Register in parent's shared zone
        try await registerInParentSharedZone(
            zoneID: metadata.rootRecordID.zoneID,
            rootRecordID: metadata.rootRecordID,
            parentDeviceID: payload.parentDeviceID
        )
    }

    /// Register child device in parent's shared zone
    func registerInParentSharedZone(zoneID: CKRecordZone.ID, rootRecordID: CKRecord.ID, parentDeviceID: String) async throws {
        #if DEBUG
        print("[DevicePairingService] ===== Registering in Parent's Shared Zone =====")
        print("[DevicePairingService] Zone ID: \(zoneID.zoneName)")
        print("[DevicePairingService] Parent Device ID: \(parentDeviceID)")
        #endif

        // CRITICAL: Use sharedCloudDatabase (child's view of parent's zone)
        let sharedDatabase = container.sharedCloudDatabase

        // Create device record in PARENT'S shared zone
        let deviceRecordID = CKRecord.ID(
            recordName: "device-\(DeviceModeManager.shared.deviceID)",
            zoneID: zoneID  // Parent's zone!
        )

        let deviceRecord = CKRecord(recordType: "CD_RegisteredDevice", recordID: deviceRecordID)
        // IMPORTANT: Link the new record to the shared root so it belongs to the share
        deviceRecord.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)
        deviceRecord["CD_deviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        deviceRecord["CD_deviceName"] = DeviceModeManager.shared.deviceName as CKRecordValue
        deviceRecord["CD_deviceType"] = "child" as CKRecordValue
        deviceRecord["CD_parentDeviceID"] = parentDeviceID as CKRecordValue
        deviceRecord["CD_registrationDate"] = Date() as CKRecordValue
        deviceRecord["CD_isActive"] = 1 as CKRecordValue

        // Save to SHARED database
        let savedRecord = try await sharedDatabase.save(deviceRecord)

        #if DEBUG
        print("✅ Child registered in parent's zone: \(savedRecord.recordID)")
        #endif
    }

    /// Accept pairing from parent (local-only, no CloudKit writes)
    func acceptParentPairing(from payload: PairingPayload) async throws {
        #if DEBUG
        print("[DevicePairingService] ===== Accepting Local Pairing from Parent =====")
        print("[DevicePairingService] Parent Device ID: \(payload.parentDeviceID)")
        print("[DevicePairingService] Verification Token: \(payload.verificationToken)")
        #endif

        isPairing = true
        defer { isPairing = false }

        // Simple local-only pairing - save parent device ID and register in private database
        #if DEBUG
        print("[DevicePairingService] Using local-only pairing (no public database writes)")
        print("[DevicePairingService] Saving parent device ID locally...")
        #endif

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

        #if DEBUG
        print("[DevicePairingService] ✅ Parent device ID saved: \(payload.parentDeviceID)")
        print("[DevicePairingService] Now registering child device in OWN private database...")
        #endif

        // Register this child device in its OWN CloudKit private database
        do {
            let _ = try await self.cloudKitSync.registerDevice(
                mode: DeviceMode.childDevice,
                childName: nil,
                parentDeviceID: payload.parentDeviceID
            )

            #if DEBUG
            print("[DevicePairingService] ✅ Child device registered in private database")
            print("[DevicePairingService] ✅✅✅ Pairing completed successfully!")
            print("[DevicePairingService] Note: Parent will see child's data when usage syncing begins")
            #endif
        } catch {
            #if DEBUG
            print("[DevicePairingService] Warning: Failed to register in private database: \(error)")
            print("[DevicePairingService] This is OK - pairing still succeeded locally")
            #endif
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
