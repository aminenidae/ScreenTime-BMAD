//
//  ParentPINService.swift
//  ScreenTimeRewards
//
//  Manages parent PIN setup and validation
//  PINs are stored securely in Keychain with SHA-256 hashing
//

import Foundation
import CryptoKit
import Security

class ParentPINService {
    static let shared = ParentPINService()

    private let keychainService = "com.screentime.rewards"
    private let keychainAccount = "parentpin"

    private init() {}

    // MARK: - Public Methods

    /// Check if parent PIN is configured
    /// - Returns: True if PIN is set up, false otherwise
    func isPINConfigured() -> Bool {
        return retrieveStoredPINHash() != nil
    }

    /// Set up a new parent PIN
    /// - Parameter pin: PIN to set up (must be 4 digits)
    /// - Returns: Result indicating success or error
    func setParentPIN(_ pin: String) -> Result<Void, PINError> {
        // Validate PIN format
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else {
            return .failure(.invalidLength)
        }

        // Check if PIN is weak
        if isWeakPIN(pin) {
            return .failure(.weakPIN)
        }

        // Hash and store PIN
        let hashedPIN = hashPIN(pin)
        if storeHashedPIN(hashedPIN) {
            return .success(())
        } else {
            return .failure(.storageFailed)
        }
    }

    /// Validate a PIN entry
    /// - Parameter pin: PIN to validate
    /// - Returns: True if PIN matches stored PIN, false otherwise
    func validatePIN(_ pin: String) -> Bool {
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else {
            return false
        }

        guard let storedHash = retrieveStoredPINHash() else {
            return false
        }

        let enteredHash = hashPIN(pin)
        return enteredHash == storedHash
    }

    /// Check if a PIN is weak (based on common patterns)
    /// - Parameter pin: PIN to check
    /// - Returns: True if PIN is weak, false if strong
    func isWeakPIN(_ pin: String) -> Bool {
        // Must be 4 digits
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else {
            return true
        }

        // Check for all same digit (0000, 1111, etc)
        if Set(pin).count == 1 {
            return true
        }

        // Check for sequential patterns (1234, 2345, etc)
        let digits = pin.map { Int(String($0)) ?? 0 }
        var isSequential = true
        for i in 0..<(digits.count - 1) {
            if digits[i+1] - digits[i] != 1 {
                isSequential = false
                break
            }
        }
        if isSequential {
            return true
        }

        // Check for reverse sequential (4321, 3210, etc)
        var isReverseSequential = true
        for i in 0..<(digits.count - 1) {
            if digits[i] - digits[i+1] != 1 {
                isReverseSequential = false
                break
            }
        }
        if isReverseSequential {
            return true
        }

        // Additional weak pattern: 1357, 2468, etc (too predictable)
        // This is already somewhat covered by common keyboard patterns
        // but we could expand this if needed

        return false
    }

    // MARK: - Private Methods

    /// Hash a PIN using SHA-256
    /// - Parameter pin: PIN to hash
    /// - Returns: Hexadecimal string representation of hash
    private func hashPIN(_ pin: String) -> String {
        let data = pin.data(using: .utf8)!
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Store hashed PIN in Keychain
    /// - Parameter hash: Hashed PIN to store
    /// - Returns: True if storage successful, false otherwise
    private func storeHashedPIN(_ hash: String) -> Bool {
        guard let data = hash.data(using: .utf8) else {
            #if DEBUG
            print("[ParentPINService] ❌ Failed to convert hash to data")
            #endif
            return false
        }

        #if DEBUG
        print("[ParentPINService] Storing PIN hash in Keychain: \(hash.prefix(10))...")
        print("[ParentPINService] Service: \(keychainService), Account: \(keychainAccount)")
        #endif

        // First, try to delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        #if DEBUG
        if status == errSecSuccess {
            print("[ParentPINService] ✅ PIN hash stored successfully in Keychain")

            // Immediate verification
            if let retrieved = retrieveStoredPINHash() {
                print("[ParentPINService] ✅ Immediate verification successful: \(retrieved.prefix(10))...")
            } else {
                print("[ParentPINService] ⚠️ Immediate verification failed!")
            }
        } else {
            print("[ParentPINService] ❌ Failed to store PIN in Keychain, status: \(status)")
        }
        #endif

        return status == errSecSuccess
    }

    /// Retrieve hashed PIN from Keychain
    /// - Returns: Hashed PIN if configured, nil otherwise
    private func retrieveStoredPINHash() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let hash = String(data: data, encoding: .utf8) else {
            #if DEBUG
            if status == errSecItemNotFound {
                print("[ParentPINService] ⚠️ No PIN hash found in Keychain (item not found)")
            } else {
                print("[ParentPINService] ⚠️ Failed to retrieve PIN from Keychain, status: \(status)")
            }
            print("[ParentPINService] Service: \(keychainService), Account: \(keychainAccount)")
            #endif
            return nil
        }

        #if DEBUG
        print("[ParentPINService] ✅ Retrieved PIN hash from Keychain: \(hash.prefix(10))...")
        #endif

        return hash
    }
}
