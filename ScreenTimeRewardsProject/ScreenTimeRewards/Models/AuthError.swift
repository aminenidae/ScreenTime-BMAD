//
//  AuthError.swift
//  ScreenTimeRewards
//
//  Phase 4B: Security Enhancement - CORRECTED VERSION
//  Removed biometric-related errors
//

import Foundation

enum AuthError: Error, LocalizedError {
    case authenticationFailed
    case userCancel
    case parentalApprovalRequired
    case pinRequired
    case pinValidationFailed
    case pinNotConfigured
    case pinInvalid(String)  // Added for weak PIN or invalid format errors

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        case .userCancel:
            return "Authentication was cancelled."
        case .parentalApprovalRequired:
            return "Parental approval is required to access Parent Mode."
        case .pinRequired:
            return "Parent PIN is required to access Parent Mode."
        case .pinValidationFailed:
            return "Incorrect PIN. Please try again."
        case .pinNotConfigured:
            return "Parent PIN has not been configured. Please set up a PIN."
        case .pinInvalid(let message):
            return message
        }
    }
}
