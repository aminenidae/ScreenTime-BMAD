//
//  PINError.swift
//  ScreenTimeRewards
//
//  PIN validation and storage error types
//

import Foundation

enum PINError: LocalizedError {
    case invalidLength
    case weakPIN
    case storageFailed
    case retrievalFailed
    case validationFailed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            return "PIN must be exactly 4 digits"
        case .weakPIN:
            return "PIN is too weak. Avoid sequences and repeated digits"
        case .storageFailed:
            return "Failed to save PIN to Keychain"
        case .retrievalFailed:
            return "Failed to retrieve PIN from Keychain"
        case .validationFailed:
            return "PIN validation failed"
        case .notConfigured:
            return "PIN is not configured"
        }
    }
}
