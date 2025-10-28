//
//  SetupFlowView.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Orchestrates the one-time setup flow
//

import SwiftUI
import UIKit

struct SetupFlowView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var currentStep: SetupStep = .welcome

    enum SetupStep {
        case welcome
        case authorization
        case pinSetup
        case complete
    }

    var body: some View {
        Group {
            switch currentStep {
            case .welcome:
                WelcomeScreen(onContinue: {
                    #if DEBUG
                    print("[SetupFlow] Moving to authorization step")
                    #endif
                    currentStep = .authorization
                })

            case .authorization:
                AuthorizationRequestScreen(onAuthorized: {
                    #if DEBUG
                    print("[SetupFlow] Authorization granted, moving to PIN setup")
                    #endif
                    currentStep = .pinSetup
                })

            case .pinSetup:
                SetupPINScreen(onComplete: {
                    #if DEBUG
                    print("[SetupFlow] PIN setup complete, moving to completion")
                    #endif
                    currentStep = .complete
                })

            case .complete:
                SetupCompleteScreen(onComplete: {
                    #if DEBUG
                    print("[SetupFlow] Setup complete, marking as done")
                    #endif

                    // Mark setup as complete
                    hasCompletedSetup = true

                    // App will automatically navigate to main flow
                    // because hasCompletedSetup is now true
                })
            }
        }
        .animation(.easeInOut, value: currentStep)
    }
}

// MARK: - PIN Setup Screen (Part of Setup Flow)

struct SetupPINScreen: View {
    let onComplete: () -> Void

    @State private var pin: String = ""
    @State private var confirmPIN: String = ""
    @State private var errorMessage: String? = nil
    @State private var isConfirming: Bool = false
    @State private var isProcessing: Bool = false

    private let authService = AuthenticationService()

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                // Title
                Text(isConfirming ? "Confirm Your PIN" : "Create Parent PIN")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Description
                Text(isConfirming ?
                    "Enter your PIN again to confirm" :
                    "This PIN will protect Parent Mode settings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                // PIN dots
                HStack(spacing: 20) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < currentPIN.count ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 20, height: 20)
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Keypad
                PINKeypadView(
                    pin: Binding(
                        get: { currentPIN },
                        set: { newValue in
                            if isConfirming {
                                confirmPIN = newValue
                            } else {
                                pin = newValue
                            }
                        }
                    ),
                    onPINEntered: {
                        handlePINComplete(currentPIN)
                    }
                )
                .disabled(isProcessing)

                Spacer()
            }
        }
    }

    private var currentPIN: String {
        isConfirming ? confirmPIN : pin
    }

    private func handlePINComplete(_ enteredPIN: String) {
        if isConfirming {
            // Confirming PIN
            if enteredPIN == pin {
                // PINs match - save it
                isProcessing = true
                savePIN(enteredPIN)
            } else {
                // PINs don't match
                errorMessage = "PINs don't match. Please try again."
                pin = ""
                confirmPIN = ""
                isConfirming = false

                // Haptic feedback
                DispatchQueue.main.async {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }

            }
        } else {
            // First PIN entry - move to confirmation
            errorMessage = nil
            isConfirming = true
        }
    }

    private func savePIN(_ pinToSave: String) {
        #if DEBUG
        print("[SetupPINScreen] Saving PIN...")
        #endif

        authService.setupParentPIN(pinToSave) { result in
            isProcessing = false

            switch result {
            case .success:
                #if DEBUG
                print("[SetupPINScreen] ✅ PIN saved successfully")
                #endif

                // Success - move to next step
                onComplete()

            case .failure(let error):
                #if DEBUG
                print("[SetupPINScreen] ❌ PIN save failed: \(error)")
                #endif

                errorMessage = error.localizedDescription
                pin = ""
                confirmPIN = ""
                isConfirming = false

                // Haptic feedback
                DispatchQueue.main.async {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}

struct SetupFlowView_Previews: PreviewProvider {
    static var previews: some View {
        SetupFlowView()
    }
}
