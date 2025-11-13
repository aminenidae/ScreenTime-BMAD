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

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 0) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24))
                        .foregroundColor(PINColors.primary)
                        .frame(width: 48, height: 48)
                }

                Spacer()

                // Empty space for symmetry
                Color.clear
                    .frame(width: 48, height: 48)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Main content
            VStack(spacing: 0) {
                // Top section with title, subtitle, error, and PIN dots
                VStack(spacing: 0) {
                    // Title
                    Text(isConfirming ? "Confirm your PIN" : "Create a Parent PIN")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? PINColors.textDark : PINColors.textLight)
                        .tracking(-0.5)

                    // Subtitle
                    Text(isConfirming ? "Re-enter your PIN to confirm." : "Create a 4-digit PIN to protect Parent Mode")
                        .font(.system(size: 16))
                        .foregroundColor(colorScheme == .dark ? PINColors.textMutedDark : PINColors.textMutedLight)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    // Error message (fixed height to prevent layout shift)
                    Group {
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(PINColors.error)
                        } else {
                            Text(" ")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .frame(height: 20)
                    .padding(.top, 8)

                    // PIN dots display
                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { index in
                            PINDotView(
                                isFilled: index < (isConfirming ? confirmPIN.count : pin.count),
                                colorScheme: colorScheme
                            )
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.top, 24)

                    // Progress indicators
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 999)
                            .fill((colorScheme == .dark ? PINColors.textMutedDark : PINColors.textMutedLight).opacity(isConfirming ? 0.3 : 1.0))
                            .frame(width: 32, height: 6)

                        RoundedRectangle(cornerRadius: 999)
                            .fill(isConfirming ? PINColors.primary : (colorScheme == .dark ? PINColors.textMutedDark : PINColors.textMutedLight).opacity(0.3))
                            .frame(width: 32, height: 6)
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()

                // Keypad at bottom
                PINKeypadGrid(
                    pin: isConfirming ? $confirmPIN : $pin,
                    colorScheme: colorScheme,
                    onPINEntered: {
                        if isConfirming {
                            confirmPINSetup()
                        } else {
                            proceedToConfirmation()
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? PINColors.backgroundDark : PINColors.backgroundLight)
        .disabled(isSettingUp)
        .overlay {
            if isSettingUp {
                ProgressView("Setting up PIN...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.8))
                    )
            }
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
                        print("[ParentPINSetupView] ✅ PIN saved successfully")
                        #endif
                        onPINSetup()

                    case .failure(let error):
                        #if DEBUG
                        print("[ParentPINSetupView] ❌ PIN save failed: \(error)")
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

// MARK: - PIN Dot View Component
struct PINDotView: View {
    let isFilled: Bool
    let colorScheme: ColorScheme

    var body: some View {
        Circle()
            .fill(isFilled ? ParentPINSetupView.PINColors.primary : Color.clear)
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(
                        isFilled ? ParentPINSetupView.PINColors.primary :
                            (colorScheme == .dark ? ParentPINSetupView.PINColors.textMutedDark : ParentPINSetupView.PINColors.textMutedLight),
                        lineWidth: 2
                    )
            )
    }
}

// MARK: - PIN Keypad Grid Component
struct PINKeypadGrid: View {
    @Binding var pin: String
    let colorScheme: ColorScheme
    var onPINEntered: (() -> Void)?

    private let maxDigits = 4

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3),
                spacing: 16
            ) {
                // Numbers 1-9
                ForEach(1...9, id: \.self) { number in
                    PINKeypadButtonView(
                        title: "\(number)",
                        colorScheme: colorScheme,
                        action: {
                            appendDigit("\(number)")
                        }
                    )
                }

                // Bottom row: empty, 0, backspace
                Color.clear
                    .frame(width: 80, height: 80)

                PINKeypadButtonView(
                    title: "0",
                    colorScheme: colorScheme,
                    action: {
                        appendDigit("0")
                    }
                )

                Button(action: deleteDigit) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 32))
                        .foregroundColor(colorScheme == .dark ? ParentPINSetupView.PINColors.textDark : ParentPINSetupView.PINColors.textLight)
                        .frame(width: 80, height: 80)
                }
                .buttonStyle(PINBackspaceButtonStyle(colorScheme: colorScheme))
            }
        }
        .frame(maxWidth: 384)
        .onChange(of: pin) { _ in
            if pin.count == maxDigits {
                // Small delay to show the last digit before calling completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onPINEntered?()
                }
            }
        }
    }

    private func appendDigit(_ digit: String) {
        guard pin.count < maxDigits else { return }
        pin.append(digit)
    }

    private func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }
}

// MARK: - PIN Keypad Button Component
struct PINKeypadButtonView: View {
    let title: String
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(colorScheme == .dark ? ParentPINSetupView.PINColors.textDark : ParentPINSetupView.PINColors.textLight)
                .frame(width: 80, height: 80)
        }
        .buttonStyle(PINKeypadButtonStyle(colorScheme: colorScheme))
    }
}

// MARK: - PIN Keypad Button Style
struct PINKeypadButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(
                        configuration.isPressed ?
                            (colorScheme == .dark ? ParentPINSetupView.PINColors.keypadActiveDark : ParentPINSetupView.PINColors.keypadActiveLight) :
                            (colorScheme == .dark ? ParentPINSetupView.PINColors.keypadDark : ParentPINSetupView.PINColors.keypadLight)
                    )
            )
    }
}

// MARK: - PIN Backspace Button Style
struct PINBackspaceButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(
                        configuration.isPressed ?
                            (colorScheme == .dark ? ParentPINSetupView.PINColors.keypadDark.opacity(0.5) : ParentPINSetupView.PINColors.keypadLight.opacity(0.5)) :
                            Color.clear
                    )
            )
    }
}

// MARK: - Design Tokens
extension ParentPINSetupView {
    struct PINColors {
        static let primary = Color(hex: "#4A90E2")
        static let backgroundLight = Color(hex: "#FFFFFF")
        static let backgroundDark = Color(hex: "#121212")
        static let textLight = Color(hex: "#333333")
        static let textDark = Color(hex: "#E0E0E0")
        static let textMutedLight = Color(hex: "#8A8A8E")
        static let textMutedDark = Color(hex: "#8E8E93")
        static let keypadLight = Color(hex: "#EFEFF4")
        static let keypadDark = Color(hex: "#2C2C2E")
        static let keypadActiveLight = Color(hex: "#D1D1D6")
        static let keypadActiveDark = Color(hex: "#48484A")
        static let error = Color(hex: "#FF3B30")
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