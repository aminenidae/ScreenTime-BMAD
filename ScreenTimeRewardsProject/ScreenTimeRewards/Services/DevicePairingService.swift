import Foundation
import CoreImage
import CloudKit
import Combine
import CoreData

enum PairingError: LocalizedError {
    case maxParentsReached(limit: Int)
    case deviceLimitReached
    case shareNotFound
    case invalidQRCode
    case networkError(Error)
    case sameAccountPairing
    case firebaseValidationFailed(FirebaseValidationError)
    case tokenExpired
    case tokenAlreadyUsed
    case subscriptionExpired
    case soloCannotPair
    case parentInTrial
    case parentNotSubscribed

    var errorDescription: String? {
        switch self {
        case .maxParentsReached(let limit):
            return "This child device is already paired with the maximum number of parent devices (\(limit)). Please unpair from one parent before adding another."
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
        case .firebaseValidationFailed(let error):
            return error.errorDescription
        case .tokenExpired:
            return "The pairing code has expired. Please ask the parent to generate a new code."
        case .tokenAlreadyUsed:
            return "This pairing code has already been used. Please ask the parent to generate a new code."
        case .subscriptionExpired:
            return "The parent's subscription has expired. Please ask the parent to renew their subscription."
        case .soloCannotPair:
            return "Solo subscription does not support device pairing. Upgrade to Individual or Family plan for remote monitoring."
        case .parentInTrial:
            return "The parent is still in their free trial. Please ask the parent to subscribe before connecting."
        case .parentNotSubscribed:
            return "The parent doesn't have an active subscription. Please ask the parent to subscribe first."
        }
    }
}

/// Returns true if the error is any flavor of CloudKit quota-exceeded.
/// Per-record failures from `modifyRecords` often surface as NSError in
/// CKErrorDomain without bridging cleanly to `CKError`, so the Swift cast
/// alone isn't enough.
func isCloudKitQuotaExceeded(_ error: Error) -> Bool {
    if let ck = error as? CKError {
        if ck.code == .quotaExceeded { return true }
        if ck.code == .partialFailure,
           let partials = ck.partialErrorsByItemID?.values {
            return partials.contains { isCloudKitQuotaExceeded($0) }
        }
    }
    let ns = error as NSError
    if ns.domain == CKErrorDomain,
       ns.code == CKError.Code.quotaExceeded.rawValue {
        return true
    }
    return false
}

@MainActor
class DevicePairingService: ObservableObject {
    static let shared = DevicePairingService()

    @Published private(set) var isPairing: Bool = false

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let customZoneID = CKRecordZone.ID(zoneName: "PairingZone", ownerName: CKCurrentUserDefaultName)
    private let cloudKitSync = CloudKitSyncService.shared

    /// Synchronously read the current paired-child count from local Core Data.
    /// NSPersistentCloudKitContainer mirrors CD_RegisteredDevice records into
    /// Core Data, so the local count tracks CloudKit truth without requiring a
    /// fresh CK fetch. Used for the pairing-limit gate — calling
    /// `fetchLinkedChildDevices()` there would await any in-flight refresh
    /// (e.g. a slow pull-refresh still running) and could leave the
    /// "Generating QR code…" spinner stuck indefinitely.
    private func localPairedChildCount() -> Int {
        let parentDeviceID = DeviceModeManager.shared.deviceID
        guard !parentDeviceID.isEmpty else { return 0 }
        let context = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        req.predicate = NSPredicate(format: "deviceType == %@ AND parentDeviceID == %@", "child", parentDeviceID)
        // Dedupe by deviceID — NSPersistentCloudKitContainer can mirror the
        // same record into multiple rows after pair/unpair/repair cycles.
        let rows = (try? context.fetch(req)) ?? []
        return Set(rows.compactMap { $0.deviceID }).count
    }

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
        let parentDeviceName: String?  // Parent's device name for display
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
    /// Each child gets their own zone - existing zones are preserved to support multiple children
    func createMonitoringZoneForChild() async throws -> (zoneID: CKRecordZone.ID, share: CKShare) {
        let database = container.privateCloudDatabase

        // NOTE: We intentionally do NOT delete existing zones here.
        // Each child gets their own zone, allowing multiple children per parent.
        // Zone cleanup should only happen during explicit unpair operations.

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
            parentDeviceName: DeviceModeManager.shared.deviceName,
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

        // Check if subscription allows pairing (Solo cannot pair)
        guard SubscriptionManager.shared.allowsParentPairing else {
            #if DEBUG
            print("[DevicePairingService] ❌ Subscription doesn't allow pairing (Solo or no access)")
            #endif
            throw PairingError.soloCannotPair
        }

        // Limit check uses local Core Data (mirrored from CloudKit) instead of
        // a fresh CK fetch — see `localPairedChildCount()` doc.
        let currentChildCount = localPairedChildCount()
        #if DEBUG
        print("[DevicePairingService] ✅ Current child count (local): \(currentChildCount)")
        #endif

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
            parentDeviceName: DeviceModeManager.shared.deviceName,
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

        // Check if this child can pair with another parent (based on subscription tier)
        guard canAnotherParentPair() else {
            throw PairingError.maxParentsReached(limit: SubscriptionManager.shared.parentDeviceLimitPerChild)
        }

        // Verify parent has active subscription BEFORE accepting CloudKit share
        #if DEBUG
        print("[DevicePairingService] 🔵 Verifying parent subscription status...")
        #endif

        do {
            let (isValid, reason, _) = try await FirebaseValidationService.shared.checkParentSubscription(
                parentDeviceId: payload.parentDeviceID
            )

            if !isValid {
                #if DEBUG
                print("[DevicePairingService] ❌ Parent subscription check failed: \(reason ?? "unknown")")
                #endif

                // Note: Trial parents ARE allowed to pair (trial_subscription is not a rejection reason)
                // Only Solo and expired subscriptions are blocked
                switch reason {
                case "solo_subscription":
                    throw PairingError.soloCannotPair
                case "subscription_expired":
                    throw PairingError.subscriptionExpired
                case "child_limit_reached":
                    throw PairingError.deviceLimitReached
                case "parent_not_found", "no_family":
                    throw PairingError.parentNotSubscribed
                default:
                    throw PairingError.parentNotSubscribed
                }
            }

            #if DEBUG
            print("[DevicePairingService] ✅ Parent subscription verified")
            #endif
        } catch let error as PairingError {
            throw error
        } catch {
            #if DEBUG
            print("[DevicePairingService] ⚠️ Firebase validation unavailable, allowing pairing (legacy mode)")
            #endif
            // Allow pairing if Firebase is unavailable (legacy mode/offline)
        }

        // Check QR code expiration (10 minutes)
        let expirationTime = payload.timestamp.addingTimeInterval(600)
        if Date() > expirationTime {
            #if DEBUG
            print("[DevicePairingService] ❌ QR code expired (older than 10 minutes)")
            #endif
            throw PairingError.tokenExpired
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

        // 4. Save parent device info using new multi-parent storage
        let rootID = metadata.rootRecordID
        let zoneID = metadata.rootRecordID.zoneID
        let commandsZoneID = UserDefaults.standard.string(forKey: "parentCommandsZoneID")

        let newParent = PairedParentInfo(
            id: payload.parentDeviceID,
            deviceName: payload.parentDeviceName ?? "Parent Device",
            sharedZoneID: zoneID.zoneName,
            sharedZoneOwner: zoneID.ownerName,
            rootRecordName: rootID.recordName,
            commandsZoneID: commandsZoneID,
            pairedDate: Date()
        )

        addPairedParent(newParent)

        #if DEBUG
        print("[DevicePairingService] ✅ Saved parent: \(newParent.deviceName)")
        print("[DevicePairingService] Zone: \(zoneID.zoneName), Owner: \(zoneID.ownerName)")
        #endif

        #if DEBUG
        print("[DevicePairingService] 🔵 Registering child in parent's shared zone...")
        #endif

        // 5. Register in parent's shared zone
        try await registerInParentSharedZone(
            zoneID: metadata.rootRecordID.zoneID,
            rootRecordID: metadata.rootRecordID,
            parentDeviceID: payload.parentDeviceID
        )

        // 6. Refresh subscription status to inherit parent's tier
        await SubscriptionManager.shared.refreshParentSubscriptionIfNeeded()

        #if DEBUG
        print("[DevicePairingService] ✅ CloudKit pairing completed successfully!")
        #endif
    }

    // Get count of parent devices child is currently paired with (uses local storage)
    private func getParentPairingCount() async throws -> Int {
        // Use local storage count - faster and more reliable than CloudKit query
        return getPairedParentCount()
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

    // MARK: - Firebase-Validated Secure Pairing (v2)

    /// Create a secure pairing session with Firebase validation
    /// This generates a single-use token that prevents QR code sharing abuse
    func createSecurePairingSession() async throws -> (sessionID: String, qrData: String, share: CKShare, zoneID: CKRecordZone.ID) {
        #if DEBUG
        print("[DevicePairingService] 🔵 Starting secure pairing session with Firebase validation...")
        #endif

        // Check if subscription allows pairing
        guard SubscriptionManager.shared.allowsParentPairing else {
            throw PairingError.soloCannotPair
        }

        // Ensure we have a Firebase family
        guard let familyId = FirebaseValidationService.shared.cachedFamilyId else {
            #if DEBUG
            print("[DevicePairingService] ❌ No Firebase family ID - need to create family first")
            #endif
            throw PairingError.networkError(NSError(domain: "PairingError", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Please complete subscription setup before pairing."]))
        }

        // Limit check uses local Core Data (mirrored from CloudKit) instead of
        // a fresh CK fetch — see `localPairedChildCount()` doc.
        let currentChildCount = localPairedChildCount()
        #if DEBUG
        print("[DevicePairingService] ✅ Current child count (local): \(currentChildCount)")
        #endif

        guard SubscriptionManager.shared.canPairChildDevice(currentCount: currentChildCount) else {
            throw PairingError.deviceLimitReached
        }

        isPairing = true
        defer { isPairing = false }

        // Create CloudKit share first
        let (zoneID, share) = try await createMonitoringZoneForChild()

        // ROLLBACK GUARD: every step below this point can fail (URL extraction,
        // Firebase token, etc.). Without rollback, every failed QR attempt
        // leaks a `ChildMonitoring-…` shared zone in the parent's private DB.
        // The Apr 30 repro saw the zone count climb 26 → 30 across 4 failed
        // QR attempts (one per attempt, never reclaimed). Track which zones
        // we created so the catch block can delete them on any throw.
        var createdZonesToCleanup: [CKRecordZone.ID] = [zoneID]

        do {
            guard let shareURL = share.url?.absoluteString else {
                throw PairingError.networkError(NSError(domain: "PairingError", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to generate sharing URL."]))
            }

            // Create the parent commands zone FIRST so its share URL is available
            // to embed in the QR payload below. Without this, the v2 (secure)
            // pairing flow only delivers the monitoring share URL to the child —
            // the child never gets an invite to the parent commands zone, and
            // parent→child config commands never reach a paired participant.
            //
            // CRITICAL: Do NOT add the ParentCommands zone to `createdZonesToCleanup`.
            // Unlike `ChildMonitoring-<UUID>` (per-session), `ParentCommands-<parentDeviceID>`
            // is a deterministic, parent-wide zone shared across ALL children
            // (createParentCommandsZone short-circuits and returns the existing zone
            // when one already exists). Rolling it back on a failed QR attempt
            // would delete the active commands zone for every previously-paired
            // child and break parent→child config sync. Only the per-session
            // monitoring zone is eligible for rollback.
            var commandsShareURL: String? = nil
            do {
                let (_, commandsShare) = try await createParentCommandsZone()
                commandsShareURL = commandsShare.url?.absoluteString
                #if DEBUG
                print("[DevicePairingService] Commands Share URL: \(commandsShareURL ?? "nil")")
                #endif
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Failed to create ParentCommands zone (non-critical): \(error)")
                #endif
            }

            // Generate Firebase-validated QR data with single-use token,
            // including the commands share URL so the child can accept it.
            let qrData: String
            do {
                qrData = try await FirebaseValidationService.shared.generateChildPairingQRData(
                    familyId: familyId,
                    cloudKitShareURL: shareURL,
                    commandsShareURL: commandsShareURL
                )
            } catch let error as FirebaseValidationError {
                throw PairingError.firebaseValidationFailed(error)
            }

            let sessionID = UUID().uuidString

            // Store session locally
            let sessionData: [String: Any] = [
                "sessionID": sessionID,
                "parentDeviceID": DeviceModeManager.shared.deviceID,
                "parentDeviceName": DeviceModeManager.shared.deviceName,
                "sharedZoneID": zoneID.zoneName,
                "shareURL": shareURL,
                "commandsShareURL": commandsShareURL ?? "",
                "createdAt": Date(),
                "expiresAt": Date().addingTimeInterval(600), // 10 minutes
                "isSecure": true
            ]

            UserDefaults.standard.set(sessionData, forKey: "pairingSession_\(sessionID)")

            #if DEBUG
            print("[DevicePairingService] ✅ Secure pairing session created with Firebase token")
            #endif

            return (sessionID, qrData, share, zoneID)
        } catch {
            // Pairing failed downstream of zone creation — best-effort cleanup
            // of every zone we just created so we don't leak orphans on every
            // failed attempt. Cleanup errors are non-fatal: if the delete itself
            // fails (offline, etc.), we still surface the original pairing error.
            await rollbackOrphanZones(createdZonesToCleanup, originalError: error)
            throw error
        }
    }

    /// Best-effort cleanup of zones created during a failed pairing session.
    /// Called from `createSecurePairingSession`'s rollback path. Logs but does
    /// not propagate cleanup errors — the caller wants the *original* pairing
    /// error surfaced to the UI, not the cleanup failure.
    private func rollbackOrphanZones(_ zoneIDs: [CKRecordZone.ID], originalError: Error) async {
        let privateDB = container.privateCloudDatabase
        for zoneID in zoneIDs {
            do {
                try await privateDB.deleteRecordZone(withID: zoneID)
                #if DEBUG
                print("[DevicePairingService] 🧹 Rolled back orphan zone \(zoneID.zoneName) after pairing error: \(originalError.localizedDescription)")
                #endif
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Failed to roll back zone \(zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Accept secure pairing from parent with Firebase validation
    /// Validates the token with Firebase before accepting CloudKit share
    func acceptSecureParentPairing(from payload: SecureChildPairingPayload) async throws {
        #if DEBUG
        print("[DevicePairingService] 🔵 Child: Starting secure pairing with Firebase validation...")
        print("[DevicePairingService] Token ID: \(payload.tokenId)")
        #endif

        // Check if this child can pair with another parent
        guard canAnotherParentPair() else {
            throw PairingError.maxParentsReached(limit: SubscriptionManager.shared.parentDeviceLimitPerChild)
        }

        // Check local expiration first
        if payload.isExpired {
            throw PairingError.tokenExpired
        }

        isPairing = true
        defer { isPairing = false }

        // Step 1: Validate with Firebase server (single-use token check)
        #if DEBUG
        print("[DevicePairingService] 🔵 Validating with Firebase...")
        #endif

        let validationResult: TokenValidationResult
        do {
            validationResult = try await FirebaseValidationService.shared.validateChildPairingToken(payload: payload)
        } catch let error as FirebaseValidationError {
            throw PairingError.firebaseValidationFailed(error)
        }

        guard validationResult.success else {
            if let error = validationResult.error {
                switch error {
                case .tokenExpired:
                    throw PairingError.tokenExpired
                case .tokenAlreadyUsed:
                    throw PairingError.tokenAlreadyUsed
                case .subscriptionExpired:
                    throw PairingError.subscriptionExpired
                case .deviceLimitReached:
                    throw PairingError.deviceLimitReached
                default:
                    throw PairingError.firebaseValidationFailed(error)
                }
            }
            throw PairingError.invalidQRCode
        }

        #if DEBUG
        print("[DevicePairingService] ✅ Firebase validation successful, proceeding with CloudKit...")
        #endif

        // Step 2: Accept CloudKit share (now that Firebase validated the token)
        guard let shareURL = URL(string: payload.shareURL) else {
            throw PairingError.invalidQRCode
        }

        let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
            container.fetchShareMetadata(with: shareURL) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: PairingError.shareNotFound)
                }
            }
        }

        // Validate different iCloud accounts
        let currentUserID = try await getCurrentUserRecordID()
        let shareOwnerID = metadata.rootRecordID.zoneID.ownerName

        if currentUserID.recordName == shareOwnerID {
            throw PairingError.sameAccountPairing
        }

        // Accept the monitoring share
        try await container.accept(metadata)

        // Also accept the parent commands share (so parent→child config
        // commands can reach this device). The legacy v1 flow did this; the
        // v2 flow originally omitted it, breaking parent→child sync entirely.
        var commandsZoneIDName: String? = nil
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
                commandsZoneIDName = commandsMetadata.rootRecordID.zoneID.zoneName
                UserDefaults.standard.set(commandsZoneIDName, forKey: "parentCommandsZoneID")
                #if DEBUG
                print("[DevicePairingService] ✅ Parent commands share accepted: \(commandsZoneIDName ?? "?")")
                #endif
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Failed to accept commands share (non-critical): \(error.localizedDescription)")
                #endif
                // Non-critical for monitoring path; commands will be unreachable
                // until the next pairing attempt resolves the share.
            }
        } else {
            #if DEBUG
            print("[DevicePairingService] ⚠️ No commandsShareURL in payload — parent→child commands won't reach this device")
            #endif
        }

        // Store parent info
        let zoneID = metadata.rootRecordID.zoneID
        let rootID = metadata.rootRecordID

        let newParent = PairedParentInfo(
            id: payload.parentDeviceID,
            deviceName: "Parent Device",
            sharedZoneID: zoneID.zoneName,
            sharedZoneOwner: zoneID.ownerName,
            rootRecordName: rootID.recordName,
            commandsZoneID: commandsZoneIDName,
            pairedDate: Date()
        )

        addPairedParent(newParent)

        // Register in parent's shared zone
        try await registerInParentSharedZone(
            zoneID: zoneID,
            rootRecordID: rootID,
            parentDeviceID: payload.parentDeviceID
        )

        // Refresh subscription status to inherit parent's tier
        await SubscriptionManager.shared.refreshParentSubscriptionIfNeeded()

        #if DEBUG
        print("[DevicePairingService] ✅ Secure pairing completed successfully!")
        #endif
    }

    /// Parse a scanned QR code and determine if it's v1 (legacy) or v2 (secure)
    enum ScannedQRType {
        case legacyChildPairing(PairingPayload)
        case secureChildPairing(SecureChildPairingPayload)
        case coParentInvitation(CoParentPayload)
        case invalid
    }

    func parseScannedQRCode(_ jsonString: String) -> ScannedQRType {
        guard let data = jsonString.data(using: .utf8) else {
            return .invalid
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try secure child pairing (v2) first
        if let payload = try? decoder.decode(SecureChildPairingPayload.self, from: data),
           payload.version == 2 {
            return .secureChildPairing(payload)
        }

        // Try co-parent payload
        if let payload = try? decoder.decode(CoParentPayload.self, from: data),
           payload.version == 1 {
            return .coParentInvitation(payload)
        }

        // Try legacy payload (no version field)
        if let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) {
            return .legacyChildPairing(payload)
        }

        return .invalid
    }

    /// Handle any scanned QR code (legacy or secure)
    func handleScannedQRCode(_ jsonString: String) async throws {
        let qrType = parseScannedQRCode(jsonString)

        switch qrType {
        case .secureChildPairing(let payload):
            try await acceptSecureParentPairing(from: payload)

        case .legacyChildPairing(let payload):
            // Legacy pairing - use CloudKit-only flow
            try await acceptParentShareAndRegister(from: payload)

        case .coParentInvitation:
            // Co-parent handling is done via JoinFamilyView, not here
            throw PairingError.invalidQRCode

        case .invalid:
            throw PairingError.invalidQRCode
        }
    }

    /// Generate QR code image from JSON string
    func generateQRCodeImage(from jsonString: String) -> CIImage? {
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(jsonString.data(using: .utf8), forKey: "inputMessage")
        qrFilter?.setValue("Q", forKey: "inputCorrectionLevel")
        return qrFilter?.outputImage
    }

    /// Generate co-parent invitation QR code
    func generateCoParentQRCode(familyName: String) async throws -> CIImage? {
        guard let familyId = FirebaseValidationService.shared.cachedFamilyId else {
            throw PairingError.networkError(NSError(domain: "PairingError", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No family found. Please complete subscription setup."]))
        }

        let qrData = try await FirebaseValidationService.shared.generateCoParentQRData(
            familyId: familyId,
            familyName: familyName
        )

        return generateQRCodeImage(from: qrData)
    }

    /// Check if using secure (Firebase-validated) pairing
    var isSecurePairingEnabled: Bool {
        FirebaseValidationService.shared.isConfigured &&
        FirebaseValidationService.shared.cachedFamilyId != nil
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
            throw PairingError.maxParentsReached(limit: 1)
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

    // MARK: - Multi-Parent Storage (New)

    /// Key for storing array of paired parents
    private let pairedParentsKey = "pairedParents"

    /// Get all paired parent devices
    func getPairedParents() -> [PairedParentInfo] {
        // First, try to load from new multi-parent storage
        if let data = UserDefaults.standard.data(forKey: pairedParentsKey),
           let parents = try? JSONDecoder().decode([PairedParentInfo].self, from: data) {
            return parents
        }

        // Fall back to legacy single-parent storage (migration)
        if let parentID = UserDefaults.standard.string(forKey: "parentDeviceID") {
            let parentName = UserDefaults.standard.string(forKey: "parentDeviceName") ?? "Parent Device"
            let sharedZoneID = UserDefaults.standard.string(forKey: "parentSharedZoneID")
            let sharedZoneOwner = UserDefaults.standard.string(forKey: "parentSharedZoneOwner")
            let rootRecordName = UserDefaults.standard.string(forKey: "parentSharedRootRecordName")
            let commandsZoneID = UserDefaults.standard.string(forKey: "parentCommandsZoneID")

            let legacyParent = PairedParentInfo(
                id: parentID,
                deviceName: parentName,
                sharedZoneID: sharedZoneID,
                sharedZoneOwner: sharedZoneOwner,
                rootRecordName: rootRecordName,
                commandsZoneID: commandsZoneID,
                pairedDate: Date()
            )

            // Migrate to new storage format
            savePairedParents([legacyParent])
            clearLegacyParentStorage()

            return [legacyParent]
        }

        return []
    }

    /// Save paired parents to storage
    private func savePairedParents(_ parents: [PairedParentInfo]) {
        if let data = try? JSONEncoder().encode(parents) {
            UserDefaults.standard.set(data, forKey: pairedParentsKey)
        }
    }

    /// Add a new paired parent, or refresh an existing entry with the same id.
    /// Replace-on-match handles the iCloud-swap re-pair case: the parent's deviceID
    /// (Keychain-stable) is unchanged, but their sharedZoneID/Owner/rootRecordName
    /// point to a new CloudKit zone in the new iCloud account. Skipping would leave
    /// the child reading from the dead zone.
    func addPairedParent(_ parent: PairedParentInfo) {
        var parents = getPairedParents()
        let isReplacement = parents.contains(where: { $0.id == parent.id })
        parents.removeAll { $0.id == parent.id }
        parents.append(parent)
        savePairedParents(parents)

        // Sync zone info to App Group for extension CloudKit access
        syncParentZoneInfoToAppGroup()

        // Analytics — only fire on first-time pair, not iCloud-swap refresh.
        if !isReplacement {
            AppAnalytics.shared.track(.pairingCompleted, parameters: [
                "role": "child",
                "paired_parent_count": parents.count
            ])
            AppAnalytics.shared.refreshPairedStatusUserProperty()
        }

        #if DEBUG
        let verb = isReplacement ? "🔁 Refreshed" : "✅ Added"
        print("[DevicePairingService] \(verb) parent: \(parent.deviceName) (\(parent.id))")
        print("[DevicePairingService] Total paired parents: \(parents.count)")
        #endif
    }

    /// Remove a paired parent and clean up CloudKit record
    func removePairedParent(_ parent: PairedParentInfo) async {
        // 1. Delete from CloudKit first (best effort)
        do {
            try await unregisterFromParentZone(parent: parent)
        } catch {
            #if DEBUG
            print("[DevicePairingService] ⚠️ CloudKit cleanup failed: \(error.localizedDescription)")
            #endif
            // Continue with local removal even if CloudKit fails
        }

        // 2. Decrement Firebase's child count for the parent's family.
        // The function looks up the family from this child's device record
        // since we don't store the parent's familyId in PairedParentInfo.
        // Without this, the parent will hit "Device limit reached" on next
        // re-pair even though CloudKit-side seats are open.
        do {
            try await FirebaseValidationService.shared.removeChildFromFamily(
                childDeviceId: DeviceModeManager.shared.deviceID,
                familyId: nil
            )
        } catch {
            #if DEBUG
            print("[DevicePairingService] ⚠️ Firebase child removal failed (non-critical): \(error.localizedDescription)")
            #endif
            // Non-critical — the local unpair still completes. The orphan
            // Firebase entry can be reaped on a future call (idempotent).
        }

        // 3. Remove from local storage
        var parents = getPairedParents()
        parents.removeAll { $0.id == parent.id }
        savePairedParents(parents)

        // 4. Re-sync App Group with remaining parents (or clear if none)
        syncParentZoneInfoToAppGroup()

        AppAnalytics.shared.track(.pairingUnpaired, parameters: [
            "role": "child",
            "remaining_paired_count": parents.count,
            "initiated_by": "child"
        ])
        AppAnalytics.shared.refreshPairedStatusUserProperty()

        #if DEBUG
        print("[DevicePairingService] ✅ Removed parent: \(parent.deviceName) (\(parent.id))")
        print("[DevicePairingService] Remaining paired parents: \(parents.count)")
        #endif
    }

    /// Unregister child device from parent's shared zone.
    ///
    /// Self-heals against stale `sharedZoneID`: a parent device that re-creates its
    /// shared zone (or the child holds a stale reference from an earlier pair cycle)
    /// would otherwise leave the unpair-delete pointed at a defunct zone. CloudKit
    /// returns `Zone does not exist` and the orphan record lives forever in the
    /// real zone, where the parent's `fetchLinkedChildDevices` keeps finding it.
    /// See "Apr 30 2026 — Alex stuck-paired" repro: child held E2DB7A60 reference
    /// while real record lived in D5F3A34C.
    ///
    /// Strategy: try the stored zone first. On any failure (zone gone, network,
    /// not-found), fall back to scanning every zone in the shared database for a
    /// record named `device-<childID>` whose `CD_parentDeviceID` matches the
    /// parent we're unpairing from, and delete from there.
    private func unregisterFromParentZone(parent: PairedParentInfo) async throws {
        let sharedDatabase = container.sharedCloudDatabase
        let childDeviceID = DeviceModeManager.shared.deviceID
        let recordName = "device-\(childDeviceID)"

        // Attempt 1: stored zone, if any.
        if let zoneName = parent.sharedZoneID,
           let zoneOwner = parent.sharedZoneOwner {
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)
            let deviceRecordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)

            #if DEBUG
            print("[DevicePairingService] 🗑️ Deleting device record from stored zone: \(zoneName)")
            #endif

            do {
                try await sharedDatabase.deleteRecord(withID: deviceRecordID)
                #if DEBUG
                print("[DevicePairingService] ✅ Deleted device record from stored zone")
                #endif
                return
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Stored-zone delete failed (\(error.localizedDescription)) — falling back to all-zone scan")
                #endif
                // Fall through to fallback scan.
            }
        } else {
            #if DEBUG
            print("[DevicePairingService] ⚠️ No stored zone info — falling back to all-zone scan")
            #endif
        }

        // Attempt 2: enumerate all zones in the shared database. If we find a
        // matching CD_RegisteredDevice owned by this parent, delete it.
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDatabase.allRecordZones()
        } catch {
            #if DEBUG
            print("[DevicePairingService] ❌ Could not enumerate shared zones: \(error.localizedDescription)")
            #endif
            throw error
        }

        var deletedCount = 0
        for zone in zones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            let candidateID = CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)
            do {
                let record = try await sharedDatabase.record(for: candidateID)
                // Only delete if this record really points at the parent we're unpairing.
                if (record["CD_parentDeviceID"] as? String) == parent.id {
                    try await sharedDatabase.deleteRecord(withID: candidateID)
                    deletedCount += 1
                    #if DEBUG
                    print("[DevicePairingService] ✅ Deleted orphan record from \(zone.zoneID.zoneName)")
                    #endif
                }
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue   // Record absent from this zone — expected for most.
            } catch {
                #if DEBUG
                print("[DevicePairingService] ⚠️ Scan: skipping \(zone.zoneID.zoneName) — \(error.localizedDescription)")
                #endif
                continue
            }
        }

        #if DEBUG
        if deletedCount == 0 {
            print("[DevicePairingService] ℹ️ All-zone scan found no record to delete (already gone or never existed)")
        } else {
            print("[DevicePairingService] ✅ All-zone scan deleted \(deletedCount) record(s)")
        }
        #endif
    }

    /// Get count of paired parents
    func getPairedParentCount() -> Int {
        return getPairedParents().count
    }

    /// Check if another parent can pair with this child device
    /// Uses subscription tier limits from SubscriptionManager.
    /// First pairing is always allowed — the child inherits a subscription via pairing.
    func canAnotherParentPair() -> Bool {
        let currentCount = getPairedParentCount()
        guard currentCount > 0 else { return true }
        let limit = SubscriptionManager.shared.parentDeviceLimitPerChild
        return currentCount < limit
    }

    /// Get the maximum number of parents allowed for current subscription
    func getParentDeviceLimit() -> Int {
        return SubscriptionManager.shared.parentDeviceLimitPerChild
    }

    /// Clear legacy single-parent storage keys
    private func clearLegacyParentStorage() {
        UserDefaults.standard.removeObject(forKey: "parentDeviceID")
        UserDefaults.standard.removeObject(forKey: "parentDeviceName")
        UserDefaults.standard.removeObject(forKey: "parentSharedZoneID")
        UserDefaults.standard.removeObject(forKey: "parentSharedZoneOwner")
        UserDefaults.standard.removeObject(forKey: "parentSharedRootRecordName")
        UserDefaults.standard.removeObject(forKey: "parentCommandsZoneID")
        UserDefaults.standard.removeObject(forKey: "childPairingInfo")

        #if DEBUG
        print("[DevicePairingService] Cleared legacy single-parent storage")
        #endif
    }

    // MARK: - Legacy Single-Parent Methods (Backward Compatibility)

    /// Get parent device ID for child device (legacy - returns first parent)
    func getParentDeviceID() -> String? {
        return getPairedParents().first?.id
    }

    /// Get parent device name for display (legacy - returns first parent)
    func getParentDeviceName() -> String? {
        return getPairedParents().first?.deviceName
    }

    /// Check if device is already paired (with at least one parent)
    func isPaired() -> Bool {
        return !getPairedParents().isEmpty
    }

    /// Get all pairing info for display/debugging
    func getPairingInfo() -> [String: Any]? {
        let parents = getPairedParents()
        guard !parents.isEmpty else { return nil }

        return [
            "pairedParentCount": parents.count,
            "parents": parents.map { [
                "id": $0.id,
                "deviceName": $0.deviceName,
                "pairedDate": $0.pairedDate
            ]}
        ]
    }

    /// Unpair child device from ALL parents - clears all pairing data
    /// Call this on the child device to disconnect from all parents
    func unpairDevice() {
        #if DEBUG
        print("[DevicePairingService] ===== Child Unpairing from ALL Parents =====")
        #endif

        // Clear new multi-parent storage
        UserDefaults.standard.removeObject(forKey: pairedParentsKey)

        // Clear legacy storage (in case migration didn't happen)
        clearLegacyParentStorage()

        // Clear App Group extension keys
        if let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") {
            clearExtensionParentZoneInfo(defaults: defaults)
        }

        #if DEBUG
        print("[DevicePairingService] ✅ All pairing data cleared")
        #endif
    }

    /// Check if child has valid pairing with zone info (with at least one parent)
    func hasValidPairing() -> Bool {
        let parents = getPairedParents()
        return parents.contains { $0.sharedZoneID != nil }
    }

    /// Get parent info for a specific parent ID
    func getParentInfo(deviceID: String) -> PairedParentInfo? {
        return getPairedParents().first { $0.id == deviceID }
    }

    // MARK: - Extension CloudKit Sync Support

    /// Sync primary parent zone info to App Group UserDefaults for extension access
    /// This enables the DeviceActivityMonitor extension to sync directly to CloudKit
    func syncParentZoneInfoToAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            #if DEBUG
            print("[DevicePairingService] ❌ Failed to access App Group defaults")
            #endif
            return
        }

        // Use first paired parent's zone info (primary parent)
        let parents = getPairedParents()
        guard let primary = parents.first,
              let zoneID = primary.sharedZoneID,
              let zoneOwner = primary.sharedZoneOwner,
              let rootName = primary.rootRecordName else {
            // Clear App Group keys if no valid parent
            clearExtensionParentZoneInfo(defaults: defaults)
            return
        }

        // Write zone info to App Group for extension access
        defaults.set(zoneID, forKey: "ext_parentZoneID")
        defaults.set(zoneOwner, forKey: "ext_parentZoneOwner")
        defaults.set(rootName, forKey: "ext_parentRootRecordName")
        defaults.set(true, forKey: "ext_parentSyncEnabled")

        #if DEBUG
        print("[DevicePairingService] ✅ Synced parent zone info to App Group")
        print("   Zone: \(zoneID), Owner: \(zoneOwner.prefix(12))...")
        #endif
    }

    /// Clear extension parent zone info from App Group
    private func clearExtensionParentZoneInfo(defaults: UserDefaults) {
        defaults.removeObject(forKey: "ext_parentZoneID")
        defaults.removeObject(forKey: "ext_parentZoneOwner")
        defaults.removeObject(forKey: "ext_parentRootRecordName")
        defaults.set(false, forKey: "ext_parentSyncEnabled")

        #if DEBUG
        print("[DevicePairingService] 🗑️ Cleared extension parent zone info from App Group")
        #endif
    }

    /// Migrate existing pairing to App Group if not already done
    /// This handles devices that were paired BEFORE the extension CloudKit sync feature was added
    /// Call this early in app lifecycle to ensure extension has zone info
    func migrateExistingPairingToAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            #if DEBUG
            print("[DevicePairingService] ❌ Migration: Failed to access App Group")
            #endif
            return
        }

        // Check if already migrated
        let alreadySynced = defaults.bool(forKey: "ext_parentSyncEnabled")
        if alreadySynced {
            #if DEBUG
            print("[DevicePairingService] ✓ Migration: Zone info already in App Group")
            #endif
            return
        }

        // Check if we have a valid pairing
        guard hasValidPairing() else {
            #if DEBUG
            print("[DevicePairingService] ✓ Migration: No valid pairing to migrate")
            #endif
            return
        }

        // Sync the zone info
        print("[DevicePairingService] 🔄 Migration: Syncing existing pairing zone info to App Group for extension")
        syncParentZoneInfoToAppGroup()
    }

}

