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
            (colorScheme == .dark ? Colors.backgroundDark : Colors.backgroundLight)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 48)

                // Logo/Icon section
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Colors.primary.opacity(0.2))
                            .frame(width: 96, height: 96)

                        Image(systemName: "star.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Colors.primary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)

                // Headline Text
                Text("Ready for Fun & Learning?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.textLight : Colors.textDark)
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
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16, weight: .regular))

                            Text("Parent Mode")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(0.24)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundColor(colorScheme == .dark ? Colors.buttonTextDark : Colors.buttonTextLight)
                        .background(colorScheme == .dark ? Colors.buttonBackgroundDark : Colors.buttonBackgroundLight)
                        .cornerRadius(12)
                    }
                    .disabled(isAuthenticating)

                    // Child Mode button
                    Button(action: handleChildModeSelection) {
                        HStack(spacing: 8) {
                            Image(systemName: "rocket.fill")
                                .font(.system(size: 16, weight: .regular))

                            Text("Alex's Space")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(0.24)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundColor(Colors.primaryButtonText)
                        .background(Colors.primary)
                        .cornerRadius(12)
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
                        .foregroundColor(colorScheme == .dark ? Colors.supportTextDark : Colors.supportTextLight)
                        .underline()
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }

            // Loading overlay
            if isAuthenticating {
                (colorScheme == .dark ? Colors.backgroundDark : Colors.backgroundLight)
                    .opacity(0.8)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Colors.primary))
                        .scaleEffect(2)
                        .frame(width: 64, height: 64)

                    Text("Getting your world ready...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Colors.textLight : Colors.textDark)
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

// MARK: - Design Tokens
extension ModeSelectionView {
    struct Colors {
        // Primary color
        static let primary = Color(red: 0x13 / 255.0, green: 0xec / 255.0, blue: 0x13 / 255.0)

        // Background colors
        static let backgroundLight = Color(red: 0xf6 / 255.0, green: 0xf8 / 255.0, blue: 0xf6 / 255.0)
        static let backgroundDark = Color(red: 0x10 / 255.0, green: 0x22 / 255.0, blue: 0x10 / 255.0)

        // Text colors
        static let textDark = Color(red: 0x11 / 255.0, green: 0x18 / 255.0, blue: 0x27 / 255.0)
        static let textLight = Color(red: 0xf9 / 255.0, green: 0xfa / 255.0, blue: 0xfb / 255.0)

        // Button colors
        static let buttonBackgroundLight = Color(red: 0xe5 / 255.0, green: 0xe7 / 255.0, blue: 0xeb / 255.0)
        static let buttonBackgroundDark = Color(red: 0x37 / 255.0, green: 0x41 / 255.0, blue: 0x51 / 255.0)
        static let buttonTextLight = Color(red: 0x1f / 255.0, green: 0x29 / 255.0, blue: 0x37 / 255.0)
        static let buttonTextDark = Color(red: 0xe5 / 255.0, green: 0xe7 / 255.0, blue: 0xeb / 255.0)

        // Primary button text
        static let primaryButtonText = Color(red: 0x11 / 255.0, green: 0x18 / 255.0, blue: 0x27 / 255.0)

        // Support text colors
        static let supportTextLight = Color(red: 0x6b / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0)
        static let supportTextDark = Color(red: 0x9c / 255.0, green: 0xa3 / 255.0, blue: 0xaf / 255.0)
    }
}

struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ModeSelectionView()
    }
}