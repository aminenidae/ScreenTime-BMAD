//
//  ParentPINSetupView.swift
//  ScreenTimeRewards
//
//  Created by Ameen on 26/10/2025.
//

import SwiftUI

struct ParentPINSetupView: View {
    @Binding var pin: String
    @Binding var confirmPIN: String
    @Binding var errorMessage: String?
    @Binding var isConfirming: Bool
    var onPINSetup: () -> Void
    var onDismiss: () -> Void

    @State private var isSettingUp = false
    @Environment(\.colorScheme) var colorScheme

    // Design colors matching ModeSelectionView
    
    
    

    var body: some View {
        ZStack {
            // Full screen cream background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back button
                HStack {
                    Button(action: {
                        if isConfirming {
                            // Go back to first step
                            isConfirming = false
                            confirmPIN = ""
                            errorMessage = nil
                        } else {
                            onDismiss()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Lock Icon
                Image(systemName: isConfirming ? "lock.shield.fill" : "lock.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .padding(.bottom, 24)

                // Title
                Text(isConfirming ? "CONFIRM PIN" : "CREATE PIN")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(3)
                    .foregroundColor(AppTheme.vibrantTeal)
                    .padding(.bottom, 8)

                // Subtitle
                Text(isConfirming ? "RE-ENTER YOUR PIN" : "PROTECT PARENT MODE")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(2)
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.7))
                    .padding(.bottom, 8)

                // Error message with fixed height
                Group {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.errorRed)
                    } else {
                        Text(" ")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(height: 20)
                .padding(.bottom, 16)

                // Progress indicators
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.vibrantTeal.opacity(isConfirming ? 0.3 : 1.0))
                        .frame(width: 40, height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isConfirming ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.3))
                        .frame(width: 40, height: 6)
                }
                .padding(.bottom, 24)

                // PIN Display
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { index in
                        let currentPIN = isConfirming ? confirmPIN : pin
                        Circle()
                            .fill(index < currentPIN.count ? AppTheme.vibrantTeal : Color.clear)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(
                                        errorMessage != nil && index >= currentPIN.count ? AppTheme.errorRed : AppTheme.vibrantTeal,
                                        lineWidth: 2
                                    )
                            )
                    }
                }
                .padding(.bottom, 48)

                // Keypad
                VStack(spacing: 20) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 32) {
                            ForEach(1...3, id: \.self) { col in
                                let number = row * 3 + col
                                PINKeyButton(text: "\(number)", tealColor: AppTheme.vibrantTeal, creamColor: AppTheme.background(for: colorScheme)) {
                                    appendDigit("\(number)")
                                }
                            }
                        }
                    }

                    // Bottom row with 0 and delete
                    HStack(spacing: 32) {
                        // Empty spacer for layout balance
                        Color.clear
                            .frame(width: 72, height: 72)

                        // 0 button
                        PINKeyButton(text: "0", tealColor: AppTheme.vibrantTeal, creamColor: AppTheme.background(for: colorScheme)) {
                            appendDigit("0")
                        }

                        // Delete button
                        Button(action: deleteDigit) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(AppTheme.vibrantTeal)
                                .frame(width: 72, height: 72)
                        }
                    }
                }
                .frame(maxWidth: 320)

                Spacer()
            }

            // Loading overlay
            if isSettingUp {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.background(for: colorScheme)))
                        .scaleEffect(1.5)

                    Text("SETTING UP")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(AppTheme.background(for: colorScheme))
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.vibrantTeal)
                )
            }
        }
        .disabled(isSettingUp)
        .onChange(of: pin) { newValue in
            if !isConfirming && newValue.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proceedToConfirmation()
                }
            }
        }
        .onChange(of: confirmPIN) { newValue in
            if isConfirming && newValue.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    confirmPINSetup()
                }
            }
        }
    }

    private func appendDigit(_ digit: String) {
        if isConfirming {
            guard confirmPIN.count < 4 else { return }
            confirmPIN.append(digit)
        } else {
            guard pin.count < 4 else { return }
            pin.append(digit)
        }
    }

    private func deleteDigit() {
        if isConfirming {
            guard !confirmPIN.isEmpty else { return }
            confirmPIN.removeLast()
        } else {
            guard !pin.isEmpty else { return }
            pin.removeLast()
        }
    }

    private func proceedToConfirmation() {
        guard pin.count == 4 else { return }

        // Check for weak PINs
        if isWeakPIN(pin) {
            errorMessage = "Please choose a stronger PIN"
            return
        }

        isConfirming = true
        errorMessage = nil
    }

    private func confirmPINSetup() {
        guard confirmPIN.count == 4 else { return }

        isSettingUp = true
        errorMessage = nil

        // Check if PINs match
        if pin == confirmPIN {
            #if DEBUG
            print("[ParentPINSetupView] PINs match, saving to keychain...")
            #endif

            // Actually save the PIN to keychain via AuthenticationService
            let authService = AuthenticationService()
            authService.setupParentPIN(pin) { result in
                DispatchQueue.main.async {
                    isSettingUp = false

                    switch result {
                    case .success:
                        #if DEBUG
                        print("[ParentPINSetupView] PIN saved successfully")
                        #endif
                        onPINSetup()

                    case .failure(let error):
                        #if DEBUG
                        print("[ParentPINSetupView] PIN save failed: \(error)")
                        #endif
                        errorMessage = error.localizedDescription
                        confirmPIN = ""
                        isConfirming = false
                    }
                }
            }
        } else {
            isSettingUp = false
            errorMessage = "PINs do not match. Please try again."
            confirmPIN = ""
            isConfirming = false
        }
    }

    /// Check if a PIN is weak (common patterns, sequences, etc.)
    private func isWeakPIN(_ pin: String) -> Bool {
        // Check for common weak PINs
        let weakPINs = ["1234", "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999"]
        if weakPINs.contains(pin) {
            return true
        }

        // Check for sequences
        let digits = Array(pin)
        if digits.count == 4,
           let first = digits[0].wholeNumberValue,
           let second = digits[1].wholeNumberValue,
           let third = digits[2].wholeNumberValue,
           let fourth = digits[3].wholeNumberValue {
            if (second == first + 1 && third == second + 1 && fourth == third + 1) ||
                (second == first - 1 && third == second - 1 && fourth == third - 1) {
                return true
            }
        }

        return false
    }
}

// MARK: - Preview
struct ParentPINSetupView_Previews: PreviewProvider {
    @State static var previewPIN = ""
    @State static var previewConfirmPIN = ""
    @State static var previewError: String? = nil
    @State static var previewIsConfirming = false

    static var previews: some View {
        ParentPINSetupView(
            pin: $previewPIN,
            confirmPIN: $previewConfirmPIN,
            errorMessage: $previewError,
            isConfirming: $previewIsConfirming,
            onPINSetup: {},
            onDismiss: {}
        )
    }
}
