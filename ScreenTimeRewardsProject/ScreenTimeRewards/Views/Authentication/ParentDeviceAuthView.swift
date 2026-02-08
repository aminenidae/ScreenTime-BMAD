//
//  ParentDeviceAuthView.swift
//  ScreenTimeRewards
//
//  Authentication wrapper view for parent devices.
//  Requires PIN authentication before showing the dashboard.
//

import SwiftUI

struct ParentDeviceAuthView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var showPINSetup = false
    @State private var showPINEntry = false
    @State private var checkingAuth = true

    // PIN setup state
    @State private var setupPIN = ""
    @State private var setupConfirmPIN = ""
    @State private var setupError: String?
    @State private var isConfirming = false

    // PIN entry state
    @State private var entryPIN = ""
    @State private var entryError: String?

    private let pinService = ParentPINService.shared

    var body: some View {
        Group {
            if sessionManager.isParentDeviceAuthenticated {
                // User is authenticated, show the dashboard
                ParentRemoteDashboardView()
            } else if checkingAuth {
                // Checking authentication status
                AuthCheckingView()
            } else if showPINSetup {
                // PIN not configured, show setup flow
                ParentPINSetupView(
                    pin: $setupPIN,
                    confirmPIN: $setupConfirmPIN,
                    errorMessage: $setupError,
                    isConfirming: $isConfirming,
                    onPINSetup: {
                        handlePINSetupComplete()
                    },
                    onDismiss: {
                        // Can't dismiss from parent device - PIN setup is required
                        // Just reset the state
                        resetSetupState()
                    }
                )
            } else if showPINEntry {
                // PIN configured, show entry flow
                ParentPINEntryView(
                    pin: $entryPIN,
                    errorMessage: $entryError,
                    onPINVerified: {
                        handlePINVerified()
                    },
                    onDismiss: {
                        // Can't dismiss from parent device - PIN entry is required
                        // Just reset the state
                        entryPIN = ""
                        entryError = nil
                    }
                )
            } else {
                // Fallback - shouldn't normally reach here
                AuthCheckingView()
                    .onAppear {
                        checkAuthenticationStatus()
                    }
            }
        }
        .onAppear {
            checkAuthenticationStatus()
        }
        .onChange(of: sessionManager.isParentDeviceAuthenticated) { isAuthenticated in
            if !isAuthenticated {
                // Auth state changed to locked - re-check and show PIN entry
                checkAuthenticationStatus()
            }
        }
    }

    // MARK: - Private Methods

    private func checkAuthenticationStatus() {
        checkingAuth = true

        // Small delay to allow UI to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let isPINConfigured = pinService.isPINConfigured()

            #if DEBUG
            print("[ParentDeviceAuthView] Checking auth status")
            print("[ParentDeviceAuthView] PIN configured: \(isPINConfigured)")
            print("[ParentDeviceAuthView] Already authenticated: \(sessionManager.isParentDeviceAuthenticated)")
            #endif

            if sessionManager.isParentDeviceAuthenticated {
                // Already authenticated (shouldn't normally happen due to background lock)
                checkingAuth = false
            } else if isPINConfigured {
                // PIN exists, require entry
                showPINEntry = true
                showPINSetup = false
                checkingAuth = false
            } else {
                // No PIN, require setup
                showPINSetup = true
                showPINEntry = false
                checkingAuth = false
            }
        }
    }

    private func handlePINSetupComplete() {
        #if DEBUG
        print("[ParentDeviceAuthView] PIN setup complete, authenticating...")
        #endif

        // Verify PIN was actually saved
        if pinService.isPINConfigured() {
            sessionManager.authenticateParentDevice()
            showPINSetup = false
            resetSetupState()
        } else {
            #if DEBUG
            print("[ParentDeviceAuthView] WARNING: PIN setup reported complete but PIN not configured!")
            #endif
            setupError = "Failed to save PIN. Please try again."
            resetSetupState()
        }
    }

    private func handlePINVerified() {
        #if DEBUG
        print("[ParentDeviceAuthView] PIN verified, validating...")
        #endif

        // Validate the entered PIN
        if pinService.validatePIN(entryPIN) {
            #if DEBUG
            print("[ParentDeviceAuthView] PIN validation successful, granting access")
            #endif
            sessionManager.authenticateParentDevice()
            showPINEntry = false
            entryPIN = ""
            entryError = nil
        } else {
            #if DEBUG
            print("[ParentDeviceAuthView] PIN validation failed")
            #endif
            entryError = "Incorrect PIN. Please try again."
            entryPIN = ""
        }
    }

    private func resetSetupState() {
        setupPIN = ""
        setupConfirmPIN = ""
        isConfirming = false
    }
}

// MARK: - Auth Checking View

private struct AuthCheckingView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated lock icon
                ZStack {
                    Circle()
                        .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                        .frame(width: 100, height: 100)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }

                Text("PARENT DASHBOARD")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(3)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                // Loading indicator
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(AppTheme.brandedText(for: colorScheme))
                            .frame(width: 8, height: 8)
                            .scaleEffect(isAnimating ? 1.0 : 0.5)
                            .opacity(isAnimating ? 1.0 : 0.3)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview("Auth Checking") {
    AuthCheckingView()
}

#Preview("Parent Device Auth") {
    ParentDeviceAuthView()
}
