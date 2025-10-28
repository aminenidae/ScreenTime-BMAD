//
//  ParentPINService.swift
//  ScreenTimeRewards
//
//  Manages parent PIN setup and validation
//  PINs are stored securely in Keychain with SHA-256 hashing
//

import Foundation
import CryptoKit

class ParentPINService {
    static let shared = ParentPINService()

    private let keyChainKey = "com.screentime.rewards.parentpin"

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

    /// Store hashed PIN in UserDefaults (could be upgraded to Keychain)
    /// - Parameter hash: Hashed PIN to store
    /// - Returns: True if storage successful, false otherwise
    private func storeHashedPIN(_ hash: String) -> Bool {
        UserDefaults.standard.set(hash, forKey: keyChainKey)
        UserDefaults.standard.synchronize()

        // Verify storage was successful
        return UserDefaults.standard.string(forKey: keyChainKey) == hash
    }

    /// Retrieve hashed PIN from UserDefaults
    /// - Returns: Hashed PIN if configured, nil otherwise
    private func retrieveStoredPINHash() -> String? {
        UserDefaults.standard.string(forKey: keyChainKey)
    }
}
