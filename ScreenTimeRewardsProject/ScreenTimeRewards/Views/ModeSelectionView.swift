import SwiftUI

struct ModeSelectionView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @StateObject private var modeManager = DeviceModeManager.shared
    @State private var authService = AuthenticationService()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAuthenticating: Bool = false

    // PIN-related state
    @State private var showPINEntry: Bool = false
    @State private var showPINSetup: Bool = false
    @State private var pin: String = ""
    @State private var confirmPIN: String = ""
    @State private var pinErrorMessage: String? = nil
    @State private var isConfirmingPIN: Bool = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 48)

                // Logo/Icon section
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.sunnyYellow.opacity(0.3), AppTheme.vibrantTeal.opacity(0.3), AppTheme.playfulCoral.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)

                        Image(systemName: "star.fill")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.sunnyYellow)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)

                // Headline Text
                Text("Ready for Fun & Learning?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .tracking(-0.3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Spacer()

                // Button Group
                VStack(spacing: 16) {
                    // Parent Mode button
                    Button(action: handleParentModeSelection) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.playfulCoral.opacity(0.2))
                                    .frame(width: 32, height: 32)

                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.playfulCoral)
                            }

                            Text("Parent Mode")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(0.24)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.card(for: colorScheme))
                                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(isAuthenticating)

                    // Child Mode button
                    Button(action: handleChildModeSelection) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.25))
                                    .frame(width: 32, height: 32)

                                Image(systemName: "rocket.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text("Alex's Space")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(0.24)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isAuthenticating)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Spacer()

                // Support link
                Button(action: {
                    // Handle support action
                }) {
                    Text("Need help? Contact Support")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .underline()
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }

            // Loading overlay
            if isAuthenticating {
                AppTheme.background(for: colorScheme)
                    .opacity(0.8)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.vibrantTeal))
                        .scaleEffect(2)
                        .frame(width: 64, height: 64)

                    Text("Getting your world ready...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }
            }
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showPINEntry) {
            ParentPINEntryView(
                pin: $pin,
                errorMessage: $pinErrorMessage,
                onPINVerified: {
                    // PIN verified successfully
                    showPINEntry = false
                    sessionManager.enterParentMode(authenticated: true)
                },
                onDismiss: {
                    showPINEntry = false
                    pin = ""
                }
            )
            .onDisappear {
                // Clear PIN when sheet is dismissed
                pin = ""
                pinErrorMessage = nil
            }
        }
        .sheet(isPresented: $showPINSetup) {
            ParentPINSetupView(
                pin: $pin,
                confirmPIN: $confirmPIN,
                errorMessage: $pinErrorMessage,
                isConfirming: $isConfirmingPIN,
                onPINSetup: {
                    // PIN setup successfully
                    showPINSetup = false
                    sessionManager.enterParentMode(authenticated: true)
                },
                onDismiss: {
                    showPINSetup = false
                    pin = ""
                    confirmPIN = ""
                    isConfirmingPIN = false
                }
            )
            .onDisappear {
                // Clear PINs when sheet is dismissed
                pin = ""
                confirmPIN = ""
                isConfirmingPIN = false
                pinErrorMessage = nil
            }
        }
    }

    private func handleParentModeSelection() {
        isAuthenticating = true

        authService.authenticate(reason: "Access Parent Mode to manage app settings") { result in
            isAuthenticating = false

            switch result {
            case .success:
                sessionManager.enterParentMode(authenticated: true)

            case .failure(let error):
                switch error {
                case .pinRequired:
                    // Show PIN entry view
                    showPINEntry = true
                    pin = ""
                    pinErrorMessage = nil
                    
                case .pinNotConfigured:
                    // Show PIN setup view
                    showPINSetup = true
                    pin = ""
                    confirmPIN = ""
                    isConfirmingPIN = false
                    pinErrorMessage = nil
                    
                default:
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func handleChildModeSelection() {
        sessionManager.enterChildMode()
    }
    
    // MARK: - PIN Validation Methods
    
    private func validatePIN() {
        authService.validateParentPIN(pin) { result in
            switch result {
            case .success:
                showPINEntry = false
                sessionManager.enterParentMode(authenticated: true)
                
            case .failure(let error):
                pinErrorMessage = error.localizedDescription
                pin = ""  // Clear the PIN field
            }
        }
    }
    
    private func setupPIN() {
        authService.setupParentPIN(pin) { result in
            switch result {
            case .success:
                showPINSetup = false
                sessionManager.enterParentMode(authenticated: true)
                
            case .failure(let error):
                pinErrorMessage = error.localizedDescription
                pin = ""  // Clear the PIN field
                confirmPIN = ""
                isConfirmingPIN = false
            }
        }
    }
}


struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ModeSelectionView()
    }
}