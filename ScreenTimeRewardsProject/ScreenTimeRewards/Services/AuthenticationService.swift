//
//  AuthenticationService.swift
//  ScreenTimeRewards
//
//  Created by Ameen on 26/10/2025.
//

import Foundation
import LocalAuthentication

enum BiometricType {
    case none
    case touchID
    case faceID
}

class AuthenticationService {
    func authenticate(reason: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        let context = LAContext()
        var authError: NSError?

        // Check if we can evaluate the policy
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            completion(.failure(.notAvailable))
            return
        }

        // Check what type of biometric authentication is available
        let biometricType = self.biometricType()
        
        #if DEBUG
        print("[AuthenticationService] Available biometric type: \(biometricType)")
        #endif

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    // Handle specific error cases
                    if let laError = error as? LAError {
                        switch laError.code {
                        case .userCancel:
                            completion(.failure(.userCancel))
                        case .biometryNotAvailable:
                            completion(.failure(.biometryNotAvailable))
                        case .biometryNotEnrolled:
                            completion(.failure(.biometryNotEnrolled))
                        default:
                            completion(.failure(.authenticationFailed))
                        }
                    } else {
                        completion(.failure(.authenticationFailed))
                    }
                }
            }
        }
    }
    
    func canAuthenticateWithBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .none
        }
        
        if #available(iOS 11.0, *) {
            switch context.biometryType {
            case .none:
                return .none
            case .touchID:
                return .touchID
            case .faceID:
                return .faceID
            case .opticID:
                return .faceID  // Treat optic ID similar to face ID
            @unknown default:
                return .none
            }
        } else {
            // Fallback on earlier versions
            return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) ? .touchID : .none
        }
    }
}