import Foundation
import CoreData
import Combine
import CloudKit

@MainActor
class PairingCodeService: ObservableObject {
    static let shared = PairingCodeService()

    @Published var currentPairingCode: String?
    @Published var isGeneratingCode = false

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let codeLength = 6
    private let codeExpirationMinutes = 10

    private init() {}

    // MARK: - Parent Functions

    /// Generate a new pairing code for the parent device
    func generatePairingCode() async throws -> String {
        isGeneratingCode = true
        defer { isGeneratingCode = false }

        // Generate a random 6-digit code
        let code = String(format: "%06d", Int.random(in: 0...999999))

        // Create CloudKit record in PUBLIC database
        let recordID = CKRecord.ID(recordName: "pairing-\(code)")
        let record = CKRecord(recordType: "PairingCode", recordID: recordID)
        record["code"] = code as CKRecordValue
        record["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        record["parentDeviceName"] = DeviceModeManager.shared.deviceName as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["expiresAt"] = Date().addingTimeInterval(TimeInterval(codeExpirationMinutes * 60)) as CKRecordValue

        let publicDatabase = container.publicCloudDatabase

        #if DEBUG
        print("[PairingCodeService] ===== Generating Pairing Code =====")
        print("[PairingCodeService] Code: \(code)")
        print("[PairingCodeService] Parent Device ID: \(DeviceModeManager.shared.deviceID)")
        print("[PairingCodeService] Saving to PUBLIC CloudKit database...")
        #endif

        _ = try await publicDatabase.save(record)

        currentPairingCode = code

        #if DEBUG
        print("[PairingCodeService] ✅ Pairing code saved to CloudKit")
        print("[PairingCodeService] Expires at: \(Date().addingTimeInterval(TimeInterval(codeExpirationMinutes * 60)))")
        #endif

        return code
    }

    /// Invalidate the current pairing code
    func invalidatePairingCode() async throws {
        guard let code = currentPairingCode else { return }

        let context = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PairingCode")
        fetchRequest.predicate = NSPredicate(format: "code == %@", code)

        let results = try context.fetch(fetchRequest)
        for object in results {
            context.delete(object)
        }

        try context.save()
        currentPairingCode = nil

        #if DEBUG
        print("[PairingCodeService] Invalidated pairing code: \(code)")
        #endif
    }

    // MARK: - Child Functions

    /// Validate and use a pairing code
    func validateAndUsePairingCode(_ code: String) async throws -> String {
        let context = PersistenceController.shared.container.viewContext

        #if DEBUG
        print("[PairingCodeService] ===== Validating Pairing Code =====")
        print("[PairingCodeService] Code entered: \(code)")
        #endif

        // Fetch the pairing code
        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PairingCode")
        fetchRequest.predicate = NSPredicate(format: "code == %@", code)

        let results = try context.fetch(fetchRequest)

        guard let pairingCodeObject = results.first else {
            #if DEBUG
            print("[PairingCodeService] ❌ Code not found")
            #endif
            throw PairingCodeError.invalidCode
        }

        // Check if already used
        if let isUsed = pairingCodeObject.value(forKey: "isUsed") as? Bool, isUsed {
            #if DEBUG
            print("[PairingCodeService] ❌ Code already used")
            #endif
            throw PairingCodeError.codeAlreadyUsed
        }

        // Check if expired
        if let expiresAt = pairingCodeObject.value(forKey: "expiresAt") as? Date,
           expiresAt < Date() {
            #if DEBUG
            print("[PairingCodeService] ❌ Code expired at \(expiresAt)")
            #endif
            throw PairingCodeError.codeExpired
        }

        // Get parent device ID
        guard let parentDeviceID = pairingCodeObject.value(forKey: "parentDeviceID") as? String else {
            #if DEBUG
            print("[PairingCodeService] ❌ No parent device ID found")
            #endif
            throw PairingCodeError.invalidCode
        }

        // Mark as used
        pairingCodeObject.setValue(true, forKey: "isUsed")
        pairingCodeObject.setValue(Date(), forKey: "usedAt")
        pairingCodeObject.setValue(DeviceModeManager.shared.deviceID, forKey: "childDeviceID")

        try context.save()

        #if DEBUG
        print("[PairingCodeService] ✅ Code validated successfully")
        print("[PairingCodeService] Parent Device ID: \(parentDeviceID)")
        #endif

        return parentDeviceID
    }

    /// Clean up expired pairing codes
    func cleanupExpiredCodes() async throws {
        let context = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PairingCode")
        fetchRequest.predicate = NSPredicate(format: "expiresAt < %@", Date() as NSDate)

        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try context.execute(deleteRequest)
        try context.save()

        #if DEBUG
        print("[PairingCodeService] Cleaned up expired pairing codes")
        #endif
    }
}

enum PairingCodeError: LocalizedError {
    case invalidCode
    case codeExpired
    case codeAlreadyUsed

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Invalid pairing code. Please check the code and try again."
        case .codeExpired:
            return "This pairing code has expired. Please generate a new one."
        case .codeAlreadyUsed:
            return "This pairing code has already been used."
        }
    }
}
