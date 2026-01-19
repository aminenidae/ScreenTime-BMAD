//
//  SessionManager.swift
//  ScreenTimeRewards
//
//  Created by Ameen on 26/10/2025.
//

import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    enum UserMode: String {
        case none
        case parent
        case child
    }

    @Published var currentMode: UserMode = .none
    @Published var isParentAuthenticated: Bool = false

    // Parent device authentication state (separate from child device's parent mode)
    @Published var isParentDeviceAuthenticated: Bool = false

    private var lastAuthenticationTime: Date?
    private var lastParentDeviceAuthTime: Date?
    private let authenticationTimeout: TimeInterval = 1800 // 30 minutes

    static let shared = SessionManager()

    private init() {}

    func enterParentMode(authenticated: Bool) {
        guard authenticated else { return }

        currentMode = .parent
        isParentAuthenticated = true
        lastAuthenticationTime = Date()

        #if DEBUG
        print("[SessionManager] Entered Parent Mode")
        #endif
    }

    func enterChildMode() {
        currentMode = .child
        isParentAuthenticated = false

        #if DEBUG
        print("[SessionManager] Entered Child Mode")
        #endif
    }

    func exitToSelection() {
        currentMode = .none
        isParentAuthenticated = false
        lastAuthenticationTime = nil

        #if DEBUG
        print("[SessionManager] Exited to Mode Selection")
        #endif
    }

    /// Lock the parent session (keeps mode but requires re-auth)
    /// Used when app goes to background on child device
    func lockParentSession() {
        guard currentMode == .parent else { return }
        isParentAuthenticated = false
        lastAuthenticationTime = nil

        #if DEBUG
        print("[SessionManager] Parent session locked - PIN required on next access")
        #endif
    }

    func requiresReAuthentication() -> Bool {
        guard let lastAuth = lastAuthenticationTime else { return true }
        return Date().timeIntervalSince(lastAuth) > authenticationTimeout
    }

    // MARK: - Parent Device Authentication (for parent device mode)

    /// Authenticate the parent device dashboard
    /// Called after successful PIN entry on parent device
    func authenticateParentDevice() {
        isParentDeviceAuthenticated = true
        lastParentDeviceAuthTime = Date()

        #if DEBUG
        print("[SessionManager] Parent device authenticated")
        #endif
    }

    /// Lock the parent device dashboard
    /// Forces PIN re-entry on next access
    func lockParentDevice() {
        isParentDeviceAuthenticated = false
        lastParentDeviceAuthTime = nil

        #if DEBUG
        print("[SessionManager] Parent device locked - PIN required on next access")
        #endif
    }

    /// Check if parent device requires re-authentication
    func parentDeviceRequiresReAuthentication() -> Bool {
        guard let lastAuth = lastParentDeviceAuthTime else { return true }
        return Date().timeIntervalSince(lastAuth) > authenticationTimeout
    }
}