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

    private var lastAuthenticationTime: Date?
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

    func requiresReAuthentication() -> Bool {
        guard let lastAuth = lastAuthenticationTime else { return true }
        return Date().timeIntervalSince(lastAuth) > authenticationTimeout
    }
}