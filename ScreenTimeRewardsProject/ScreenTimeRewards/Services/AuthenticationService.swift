//
//  AuthenticationService.swift
//  ScreenTimeRewards
//
//  Option D: Simplified Authentication Service
//  FamilyControls authorization happens at setup
//  This service only handles PIN validation for ongoing access
//

import Foundation

class AuthenticationService {

    // MARK: - Private Properties

    private let parentPINService = ParentPINService.shared

    // MARK: - Public Methods

    /// Authenticate for Parent Mode access
    /// FamilyControls authorization already happened at setup
    /// This only checks/validates PIN
    /// - Parameters:
    ///   - reason: Reason for authentication (not used - kept for compatibility)
    ///   - completion: Completion handler with result
    func authenticate(reason: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        #if DEBUG
        print("[AuthenticationService] 🔵 Authenticate called for Parent Mode access")
        #endif

        // Check if PIN is configured
        let isPINConfigured = parentPINService.isPINConfigured()

        #if DEBUG
        print("[AuthenticationService] PIN configured: \(isPINConfigured)")
        #endif

        if isPINConfigured {
            // PIN is configured - require PIN entry
            #if DEBUG
            print("[AuthenticationService] → PIN entry required")
            #endif
            completion(.failure(.pinRequired))
        } else {
            // No PIN configured - this shouldn't happen after setup
            // But handle gracefully by requiring PIN setup
            #if DEBUG
            print("[AuthenticationService] ⚠️ WARNING: No PIN configured after setup!")
            print("[AuthenticationService] → PIN setup required")
            #endif
            completion(.failure(.pinNotConfigured))
        }
    }

    /// Validate a parent PIN entry
    /// - Parameters:
    ///   - pin: PIN to validate
    ///   - completion: Completion handler with result
    func validateParentPIN(_ pin: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        #if DEBUG
        print("[AuthenticationService] 🔵 Validating PIN...")
        print("[AuthenticationService] PIN length: \(pin.count)")
        #endif

        let isValid = parentPINService.validatePIN(pin)

        #if DEBUG
        print("[AuthenticationService] PIN valid: \(isValid)")
        #endif

        if isValid {
            #if DEBUG
            print("[AuthenticationService] ✅ PIN validation successful")
            #endif
            completion(.success(()))
        } else {
            #if DEBUG
            print("[AuthenticationService] ❌ PIN validation failed")
            #endif
            completion(.failure(.pinValidationFailed))
        }
    }

    /// Set up a new parent PIN (used during setup flow)
    /// - Parameters:
    ///   - pin: PIN to set up (must be 4 digits)
    ///   - completion: Completion handler with result
    func setupParentPIN(_ pin: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        #if DEBUG
        print("[AuthenticationService] 🔵 Setting up PIN...")
        print("[AuthenticationService] PIN: \(pin.count) digits")
        #endif

        let result = parentPINService.setParentPIN(pin)

        switch result {
        case .success:
            #if DEBUG
            print("[AuthenticationService] ✅ PIN setup successful")

            // Immediate verification
            let verified = parentPINService.isPINConfigured()
            print("[AuthenticationService] Immediate verification: \(verified)")

            if !verified {
                print("[AuthenticationService] ⚠️ WARNING: PIN saved but verification failed!")
            }
            #endif

            completion(.success(()))

        case .failure(let error):
            #if DEBUG
            print("[AuthenticationService] ❌ PIN setup failed: \(error)")
            #endif

            // Map PINError to AuthError
            switch error {
            case .invalidLength:
                completion(.failure(.pinInvalid("PIN must be exactly 4 digits")))
            case .weakPIN:
                completion(.failure(.pinInvalid("Please choose a stronger PIN. Avoid sequences like 1234 or repeated digits like 1111.")))
            case .storageFailed:
                #if DEBUG
                print("[AuthenticationService] ❌ KEYCHAIN STORAGE FAILED!")
                #endif
                completion(.failure(.authenticationFailed))
            case .retrievalFailed:
                completion(.failure(.authenticationFailed))
            case .validationFailed:
                completion(.failure(.pinValidationFailed))
            case .notConfigured:
                completion(.failure(.pinNotConfigured))
            }
        }
    }

    /// Check if parent PIN is configured
    /// - Returns: True if PIN is set up, false otherwise
    func isPINConfigured() -> Bool {
        let configured = parentPINService.isPINConfigured()

        #if DEBUG
        print("[AuthenticationService] isPINConfigured: \(configured)")
        #endif

        return configured
    }
}

// MARK: - Documentation

/*
 OPTION D: AUTHORIZATION AT LAUNCH + PIN FOR ACCESS
 ===================================================

 This authentication service is simplified because FamilyControls
 authorization happens during the one-time setup flow, not here.

 Setup Flow (First Launch):
 1. Welcome screen
 2. Request FamilyControls authorization
    - Child device: Parent enters Apple ID password
    - Regular device: User grants permission
 3. Set up 4-digit Parent PIN
 4. Setup complete

 Ongoing Access (This Service):
 1. Check if PIN configured
 2. Require PIN entry
 3. Validate PIN
 4. Grant access

 This ensures:
 - Parent approves app installation on child devices (Apple ID at setup)
 - PIN provides ongoing access control
 - Fast, simple access after initial setup
 - Works reliably on all device types

 Security:
 - PIN stored in Keychain with SHA-256 hashing
 - No plaintext PINs
 - Weak PIN detection
 - FamilyControls authorization obtained at setup
 */
