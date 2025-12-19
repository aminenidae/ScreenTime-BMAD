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

    // Colors matching the design
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)

    /// Gets the child's name for display in "Child's Space" button
    /// Uses the device name if it's a child device, otherwise falls back to "Child"
    private var childSpaceName: String {
        let name = modeManager.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Child's"
        }
        // Add possessive form
        if name.lowercased().hasSuffix("s") {
            return "\(name)'"
        } else {
            return "\(name)'s"
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Parent Space Section
                Button(action: handleParentModeSelection) {
                    VStack(spacing: 0) {
                        Spacer()

                        // Lock Icon
                        Image(systemName: "lock.fill")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundColor(tealColor)
                            .padding(.bottom, 20)

                        // Title
                        Text("PARENT SPACE")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(3)
                            .foregroundColor(tealColor)
                            .padding(.bottom, 8)

                        // Subtitle
                        Text("ACCESS CONTROLS")
                            .font(.system(size: 14, weight: .medium))
                            .tracking(2)
                            .foregroundColor(tealColor.opacity(0.8))
                            .padding(.bottom, 24)

                        // Arrow
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(tealColor)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(creamBackground)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isAuthenticating)

                // Child Space Section
                Button(action: handleChildModeSelection) {
                    VStack(spacing: 0) {
                        Spacer()

                        // Person Icon
                        Image(systemName: "person.fill")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundColor(creamBackground.opacity(0.9))
                            .padding(.bottom, 20)

                        // Title - Dynamic name
                        Text("\(childSpaceName.uppercased()) SPACE")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(3)
                            .foregroundColor(creamBackground)
                            .padding(.bottom, 8)

                        // Subtitle
                        Text("USER INTERFACE")
                            .font(.system(size: 14, weight: .medium))
                            .tracking(2)
                            .foregroundColor(creamBackground.opacity(0.8))
                            .padding(.bottom, 24)

                        // Arrow
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(creamBackground)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(lightCoral)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isAuthenticating)

                // Support Bar
                Button(action: {
                    // Handle support action
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))

                        Text("NEED SUPPORT")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(2)
                    }
                    .foregroundColor(lightCoral)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(tealColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .ignoresSafeArea()

            // Loading overlay
            if isAuthenticating {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                        .frame(width: 64, height: 64)

                    Text("Getting your world ready...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tealColor)
                )
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