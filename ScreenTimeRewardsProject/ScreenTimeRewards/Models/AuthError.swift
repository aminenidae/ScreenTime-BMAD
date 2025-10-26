//
//  AuthError.swift
//  ScreenTimeRewards
//
//  Created by Ameen on 26/10/2025.
//

import Foundation

enum AuthError: Error, LocalizedError {
    case notAvailable
    case authenticationFailed
    case userCancel
    case biometryNotAvailable
    case biometryNotEnrolled
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Authentication is not available on this device."
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        case .userCancel:
            return "Authentication was cancelled."
        case .biometryNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometryNotEnrolled:
            return "No biometric authentication is enrolled. Please set up Face ID or Touch ID in Settings."
        }
    }
}