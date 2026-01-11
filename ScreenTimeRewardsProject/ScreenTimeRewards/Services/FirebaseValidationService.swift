//
//  FirebaseValidationService.swift
//  ScreenTimeRewards
//
//  Server-side validation for subscription abuse prevention via Firebase.
//  Handles pairing token creation, validation, and family management.
//

import Foundation
import Combine
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

// MARK: - Models

/// Pairing token types
enum PairingTokenType: String, Codable {
    case child = "child"
    case coparent = "coparent"
}

/// Device roles in the family
enum DeviceRole: String, Codable {
    case subscriber = "subscriber"
    case coparent = "coparent"
    case child = "child"
    case solo = "solo"
}

/// Family record from Firestore
struct FirebaseFamily: Codable {
    let familyId: String
    let subscriberDeviceId: String
    let subscriptionTier: String
    let subscriptionStatus: String
    let parents: [String]
    let maxChildren: Int
    let createdAt: Date

    var tier: SubscriptionTier {
        SubscriptionTier(rawValue: subscriptionTier) ?? .trial
    }

    var status: SubscriptionStatus {
        SubscriptionStatus(rawValue: subscriptionStatus) ?? .expired
    }
}

/// Child pairing QR payload (v2 - with Firebase validation)
struct SecureChildPairingPayload: Codable {
    let version: Int
    let tokenId: String
    let validationToken: String
    let shareURL: String
    let parentDeviceID: String
    let familyId: String
    let expiresAt: Date

    init(tokenId: String, validationToken: String, shareURL: String, parentDeviceID: String, familyId: String, expiresAt: Date) {
        self.version = 2
        self.tokenId = tokenId
        self.validationToken = validationToken
        self.shareURL = shareURL
        self.parentDeviceID = parentDeviceID
        self.familyId = familyId
        self.expiresAt = expiresAt
    }

    /// Check if the payload is expired
    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Co-parent QR payload
struct CoParentPayload: Codable {
    let version: Int
    let tokenId: String
    let validationToken: String
    let familyId: String
    let familyName: String
    let expiresAt: Date

    init(tokenId: String, validationToken: String, familyId: String, familyName: String, expiresAt: Date) {
        self.version = 1
        self.tokenId = tokenId
        self.validationToken = validationToken
        self.familyId = familyId
        self.familyName = familyName
        self.expiresAt = expiresAt
    }

    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Result of token validation
struct TokenValidationResult {
    let success: Bool
    let familyId: String?
    let error: FirebaseValidationError?
}

// MARK: - Errors

enum FirebaseValidationError: LocalizedError {
    case notConfigured
    case invalidToken
    case tokenExpired
    case tokenAlreadyUsed
    case subscriptionExpired
    case deviceLimitReached
    case parentLimitReached
    case networkError(Error)
    case serverError(String)
    case invalidPayload
    case sameAccountPairing

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase validation is not configured"
        case .invalidToken:
            return "The pairing code is invalid or has already been used"
        case .tokenExpired:
            return "The pairing code has expired. Ask for a new code."
        case .tokenAlreadyUsed:
            return "This pairing code has already been used"
        case .subscriptionExpired:
            return "The parent's subscription has expired"
        case .deviceLimitReached:
            return "Maximum number of child devices reached for this subscription"
        case .parentLimitReached:
            return "Maximum number of parent devices reached for this family"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidPayload:
            return "Invalid QR code format"
        case .sameAccountPairing:
            return "Cannot pair with your own account"
        }
    }
}

// MARK: - Service

@MainActor
final class FirebaseValidationService: ObservableObject {
    static let shared = FirebaseValidationService()

    // MARK: - Published State

    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var currentFamily: FirebaseFamily?
    @Published private(set) var deviceRole: DeviceRole?

    // MARK: - Dependencies

    #if canImport(FirebaseFirestore)
    private var db: Firestore?
    #endif
    #if canImport(FirebaseFunctions)
    private var functions: Functions?
    #endif

    private let deviceManager = DeviceModeManager.shared

    // MARK: - Constants

    private let tokenExpirationMinutes: Int = 10

    // MARK: - Initialization

    private init() {
        configure()
    }

    private func configure() {
        #if canImport(FirebaseFirestore) && canImport(FirebaseFunctions)
        db = Firestore.firestore()
        functions = Functions.functions()
        isConfigured = true

        #if DEBUG
        // Use emulator in debug mode if available
        // functions?.useEmulator(withHost: "localhost", port: 5001)
        // db?.useEmulator(withHost: "localhost", port: 8080)
        #endif

        print("[FirebaseValidation] Configured successfully")
        #else
        print("[FirebaseValidation] Firebase not available - validation disabled")
        isConfigured = false
        #endif
    }

    // MARK: - Family Management (Parent Device)

    /// Create a new family when parent subscribes
    /// Called after successful subscription purchase
    func createFamily(subscriptionTier: SubscriptionTier) async throws -> String {
        #if canImport(FirebaseFunctions)
        guard let functions else {
            throw FirebaseValidationError.notConfigured
        }

        let data: [String: Any] = [
            "deviceId": deviceManager.deviceID,
            "deviceName": deviceManager.deviceName,
            "subscriptionTier": subscriptionTier.rawValue,
            "subscriptionStatus": "active"
        ]

        do {
            let result = try await functions.httpsCallable("createFamily").call(data)

            guard let response = result.data as? [String: Any],
                  let familyId = response["familyId"] as? String else {
                throw FirebaseValidationError.serverError("Invalid response")
            }

            // Cache family info locally
            await loadFamilyInfo(familyId: familyId)
            deviceRole = .subscriber

            #if DEBUG
            print("[FirebaseValidation] Created family: \(familyId)")
            #endif

            return familyId
        } catch {
            throw FirebaseValidationError.networkError(error)
        }
        #else
        throw FirebaseValidationError.notConfigured
        #endif
    }

    /// Create a pairing token for child or co-parent
    func createPairingToken(
        familyId: String,
        tokenType: PairingTokenType,
        cloudKitShareURL: String? = nil
    ) async throws -> (tokenId: String, validationToken: String, expiresAt: Date) {
        #if canImport(FirebaseFunctions)
        guard let functions else {
            throw FirebaseValidationError.notConfigured
        }

        var data: [String: Any] = [
            "familyId": familyId,
            "tokenType": tokenType.rawValue,
            "deviceId": deviceManager.deviceID
        ]

        if let shareURL = cloudKitShareURL {
            data["cloudKitShareURL"] = shareURL
        }

        do {
            let result = try await functions.httpsCallable("createPairingToken").call(data)

            guard let response = result.data as? [String: Any],
                  let tokenId = response["tokenId"] as? String,
                  let validationToken = response["validationToken"] as? String,
                  let expiresAtTimestamp = response["expiresAt"] as? Double else {
                throw FirebaseValidationError.serverError("Invalid response")
            }

            let expiresAt = Date(timeIntervalSince1970: expiresAtTimestamp / 1000)

            #if DEBUG
            print("[FirebaseValidation] Created \(tokenType.rawValue) token: \(tokenId)")
            #endif

            return (tokenId, validationToken, expiresAt)
        } catch {
            throw FirebaseValidationError.networkError(error)
        }
        #else
        throw FirebaseValidationError.notConfigured
        #endif
    }

    // MARK: - Token Validation (Child Device)

    /// Validate a child pairing token before accepting CloudKit share
    func validateChildPairingToken(payload: SecureChildPairingPayload) async throws -> TokenValidationResult {
        // Check expiration locally first
        if payload.isExpired {
            return TokenValidationResult(success: false, familyId: nil, error: .tokenExpired)
        }

        #if canImport(FirebaseFunctions)
        guard let functions else {
            throw FirebaseValidationError.notConfigured
        }

        let data: [String: Any] = [
            "tokenId": payload.tokenId,
            "validationToken": payload.validationToken,
            "childDeviceId": deviceManager.deviceID,
            "deviceName": deviceManager.deviceName
        ]

        do {
            let result = try await functions.httpsCallable("validateChildPairing").call(data)

            guard let response = result.data as? [String: Any],
                  let success = response["success"] as? Bool else {
                throw FirebaseValidationError.serverError("Invalid response")
            }

            if success {
                let familyId = response["familyId"] as? String
                deviceRole = .child

                // Cache the family ID locally
                if let familyId {
                    UserDefaults.standard.set(familyId, forKey: "firebase_family_id")
                }

                #if DEBUG
                print("[FirebaseValidation] Child pairing validated successfully")
                #endif

                return TokenValidationResult(success: true, familyId: familyId, error: nil)
            } else {
                let errorCode = response["errorCode"] as? String ?? "unknown"
                let error = mapErrorCode(errorCode)
                return TokenValidationResult(success: false, familyId: nil, error: error)
            }
        } catch let error as NSError {
            // Handle Firebase Functions errors
            if let errorCode = error.userInfo["FIRFunctionsErrorCode"] as? Int {
                let mappedError = mapFunctionsError(code: errorCode, message: error.localizedDescription)
                return TokenValidationResult(success: false, familyId: nil, error: mappedError)
            }
            throw FirebaseValidationError.networkError(error)
        }
        #else
        throw FirebaseValidationError.notConfigured
        #endif
    }

    /// Validate a co-parent token to join an existing family
    func validateCoParentToken(payload: CoParentPayload) async throws -> TokenValidationResult {
        if payload.isExpired {
            return TokenValidationResult(success: false, familyId: nil, error: .tokenExpired)
        }

        #if canImport(FirebaseFunctions)
        guard let functions else {
            throw FirebaseValidationError.notConfigured
        }

        let data: [String: Any] = [
            "tokenId": payload.tokenId,
            "validationToken": payload.validationToken,
            "parentDeviceId": deviceManager.deviceID,
            "deviceName": deviceManager.deviceName
        ]

        do {
            let result = try await functions.httpsCallable("validateCoParentJoin").call(data)

            guard let response = result.data as? [String: Any],
                  let success = response["success"] as? Bool else {
                throw FirebaseValidationError.serverError("Invalid response")
            }

            if success {
                let familyId = response["familyId"] as? String
                deviceRole = .coparent

                if let familyId {
                    UserDefaults.standard.set(familyId, forKey: "firebase_family_id")
                    await loadFamilyInfo(familyId: familyId)
                }

                #if DEBUG
                print("[FirebaseValidation] Co-parent joined family successfully")
                #endif

                return TokenValidationResult(success: true, familyId: familyId, error: nil)
            } else {
                let errorCode = response["errorCode"] as? String ?? "unknown"
                let error = mapErrorCode(errorCode)
                return TokenValidationResult(success: false, familyId: nil, error: error)
            }
        } catch let error as NSError {
            if let errorCode = error.userInfo["FIRFunctionsErrorCode"] as? Int {
                let mappedError = mapFunctionsError(code: errorCode, message: error.localizedDescription)
                return TokenValidationResult(success: false, familyId: nil, error: mappedError)
            }
            throw FirebaseValidationError.networkError(error)
        }
        #else
        throw FirebaseValidationError.notConfigured
        #endif
    }

    // MARK: - Subscription Verification

    /// Verify parent's subscription is still valid (called periodically by child)
    func verifyFamilySubscription() async throws -> Bool {
        #if canImport(FirebaseFunctions)
        guard let functions else {
            throw FirebaseValidationError.notConfigured
        }

        guard let familyId = UserDefaults.standard.string(forKey: "firebase_family_id") else {
            #if DEBUG
            print("[FirebaseValidation] No family ID stored - skipping verification")
            #endif
            return true // No family to verify - allow access
        }

        let data: [String: Any] = [
            "familyId": familyId,
            "deviceId": deviceManager.deviceID
        ]

        do {
            let result = try await functions.httpsCallable("verifyFamilySubscription").call(data)

            guard let response = result.data as? [String: Any],
                  let isValid = response["isValid"] as? Bool else {
                throw FirebaseValidationError.serverError("Invalid response")
            }

            // Cache the result locally
            UserDefaults.standard.set(isValid, forKey: "firebase_subscription_valid")
            UserDefaults.standard.set(Date(), forKey: "firebase_last_verification")

            #if DEBUG
            print("[FirebaseValidation] Subscription verification: \(isValid ? "valid" : "invalid")")
            #endif

            return isValid
        } catch {
            // On network error, use cached value with grace period
            if let lastVerification = UserDefaults.standard.object(forKey: "firebase_last_verification") as? Date {
                let daysSinceVerification = Calendar.current.dateComponents([.day], from: lastVerification, to: Date()).day ?? 0
                if daysSinceVerification <= 7 {
                    // Within grace period - use cached value
                    return UserDefaults.standard.bool(forKey: "firebase_subscription_valid")
                }
            }
            throw FirebaseValidationError.networkError(error)
        }
        #else
        // If Firebase not configured, allow access (legacy mode)
        return true
        #endif
    }

    // MARK: - QR Payload Helpers

    /// Generate QR code JSON for child pairing
    func generateChildPairingQRData(
        familyId: String,
        cloudKitShareURL: String
    ) async throws -> String {
        let (tokenId, validationToken, expiresAt) = try await createPairingToken(
            familyId: familyId,
            tokenType: .child,
            cloudKitShareURL: cloudKitShareURL
        )

        let payload = SecureChildPairingPayload(
            tokenId: tokenId,
            validationToken: validationToken,
            shareURL: cloudKitShareURL,
            parentDeviceID: deviceManager.deviceID,
            familyId: familyId,
            expiresAt: expiresAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw FirebaseValidationError.invalidPayload
        }

        return jsonString
    }

    /// Generate QR code JSON for co-parent invitation
    func generateCoParentQRData(
        familyId: String,
        familyName: String
    ) async throws -> String {
        let (tokenId, validationToken, expiresAt) = try await createPairingToken(
            familyId: familyId,
            tokenType: .coparent
        )

        let payload = CoParentPayload(
            tokenId: tokenId,
            validationToken: validationToken,
            familyId: familyId,
            familyName: familyName,
            expiresAt: expiresAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw FirebaseValidationError.invalidPayload
        }

        return jsonString
    }

    /// Parse a scanned QR code to determine type
    func parseQRCode(_ jsonString: String) -> QRCodeType? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try child pairing payload first (v2)
        if let payload = try? decoder.decode(SecureChildPairingPayload.self, from: data),
           payload.version == 2 {
            return .childPairing(payload)
        }

        // Try co-parent payload
        if let payload = try? decoder.decode(CoParentPayload.self, from: data),
           payload.version == 1 {
            return .coParent(payload)
        }

        return nil
    }

    enum QRCodeType {
        case childPairing(SecureChildPairingPayload)
        case coParent(CoParentPayload)
    }

    // MARK: - Family Info

    /// Load family info from Firestore
    func loadFamilyInfo(familyId: String) async {
        #if canImport(FirebaseFirestore)
        guard let db else { return }

        do {
            let document = try await db.collection("families").document(familyId).getDocument()

            guard let data = document.data() else { return }

            currentFamily = FirebaseFamily(
                familyId: familyId,
                subscriberDeviceId: data["subscriberDeviceId"] as? String ?? "",
                subscriptionTier: data["subscriptionTier"] as? String ?? "trial",
                subscriptionStatus: data["subscriptionStatus"] as? String ?? "expired",
                parents: data["parents"] as? [String] ?? [],
                maxChildren: data["maxChildren"] as? Int ?? 1,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            )

            #if DEBUG
            print("[FirebaseValidation] Loaded family: \(familyId)")
            #endif
        } catch {
            print("[FirebaseValidation] Failed to load family: \(error)")
        }
        #endif
    }

    /// Get the count of children in a family
    func getChildCount(familyId: String) async -> Int {
        #if canImport(FirebaseFirestore)
        guard let db else { return 0 }

        do {
            let snapshot = try await db.collection("families/\(familyId)/children").getDocuments()
            return snapshot.documents.count
        } catch {
            print("[FirebaseValidation] Failed to get child count: \(error)")
            return 0
        }
        #else
        return 0
        #endif
    }

    // MARK: - Helpers

    private func mapErrorCode(_ code: String) -> FirebaseValidationError {
        switch code {
        case "invalid_token": return .invalidToken
        case "token_expired": return .tokenExpired
        case "token_used": return .tokenAlreadyUsed
        case "subscription_expired": return .subscriptionExpired
        case "device_limit": return .deviceLimitReached
        case "parent_limit": return .parentLimitReached
        case "same_account": return .sameAccountPairing
        default: return .serverError(code)
        }
    }

    private func mapFunctionsError(code: Int, message: String) -> FirebaseValidationError {
        // Firebase Functions error codes
        switch code {
        case 3: return .invalidToken // INVALID_ARGUMENT
        case 5: return .tokenAlreadyUsed // NOT_FOUND
        case 7: return .subscriptionExpired // PERMISSION_DENIED
        case 8: return .deviceLimitReached // RESOURCE_EXHAUSTED
        default: return .serverError(message)
        }
    }

    // MARK: - Cached Family ID

    var cachedFamilyId: String? {
        UserDefaults.standard.string(forKey: "firebase_family_id")
    }

    func clearCachedFamily() {
        UserDefaults.standard.removeObject(forKey: "firebase_family_id")
        UserDefaults.standard.removeObject(forKey: "firebase_subscription_valid")
        UserDefaults.standard.removeObject(forKey: "firebase_last_verification")
        currentFamily = nil
        deviceRole = nil
    }
}
