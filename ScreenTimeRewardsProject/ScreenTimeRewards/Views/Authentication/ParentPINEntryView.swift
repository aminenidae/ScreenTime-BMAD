//
//  ParentPINEntryView.swift
//  ScreenTimeRewards
//
//  Created by Ameen on 26/10/2025.
//

import SwiftUI

struct ParentPINEntryView: View {
    @Binding var pin: String
    @Binding var errorMessage: String?
    var onPINVerified: () -> Void
    var onDismiss: () -> Void

    @State private var isVerifying = false
    @State private var attemptCount = 0
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Enter Your PIN")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Colors.textColor(for: colorScheme))
                .tracking(-0.5)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Error message with fixed height
            Group {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Colors.error)
                } else {
                    Text(" ")
                        .font(.system(size: 14, weight: .regular))
                }
            }
            .frame(height: 20)
            .padding(.bottom, 16)

            // PIN Display
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ?
                              Colors.primary :
                              Colors.primaryDim(for: colorScheme))
                        .frame(width: 16, height: 16)
                        .overlay(
                            errorMessage != nil && index >= pin.count ?
                            Circle()
                                .stroke(Colors.error, lineWidth: 2) :
                            nil
                        )
                }
            }
            .padding(.vertical, 16)

            // Keypad
            VStack(spacing: 16) {
                ForEach(0..<3) { row in
                    HStack(spacing: 16) {
                        ForEach(1...3, id: \.self) { col in
                            let number = row * 3 + col
                            KeypadButton(text: "\(number)") {
                                appendDigit("\(number)")
                            }
                        }
                    }
                }

                // Bottom row with 0 and delete
                HStack(spacing: 16) {
                    // Empty spacer for layout balance
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)

                    // 0 button
                    KeypadButton(text: "0") {
                        appendDigit("0")
                    }

                    // Delete button
                    Button(action: deleteDigit) {
                        Image(systemName: "delete.left")
                            .font(.system(size: 32))
                            .foregroundColor(Colors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 320)

            // Cancel button
            Button("Cancel") {
                onDismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Colors.primary)
            .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: 400)
        .background(Colors.modalBackground(for: colorScheme))
        .cornerRadius(24)
        .disabled(isVerifying)
        .overlay {
            if isVerifying {
                ProgressView("Verifying PIN...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10)
            }
        }
    }

    private func appendDigit(_ digit: String) {
        guard pin.count < 4 else { return }
        pin.append(digit)

        if pin.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                verifyPIN()
            }
        }
    }

    private func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func verifyPIN() {
        isVerifying = true
        errorMessage = nil

        // In a real implementation, this would call the AuthenticationService
        // to validate the PIN. For now, we'll simulate the verification.

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isVerifying = false

            // For demonstration, we'll assume the PIN is correct
            // In a real app, you would check the result from AuthenticationService
            if pin.count == 4 {
                onPINVerified()
            } else {
                attemptCount += 1
                let remaining = max(0, 3 - attemptCount)
                errorMessage = "Incorrect PIN. \(remaining) attempts remaining."
            }
        }
    }
}

// MARK: - Keypad Button
extension ParentPINEntryView {
    struct KeypadButton: View {
        let text: String
        let action: () -> Void
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            Button(action: action) {
                Text(text)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(Colors.textColor(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        Circle()
                            .fill(Colors.keypadBackground(for: colorScheme))
                    )
            }
        }
    }
}

// MARK: - Design Tokens
extension ParentPINEntryView {
    struct Colors {
        static let primary = Color(red: 0.0, green: 0.48, blue: 1.0) // #007AFF
        static let error = Color(red: 1.0, green: 0.23, blue: 0.19) // #FF3B30

        static func primaryDim(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ?
                primary.opacity(0.3) :
                primary.opacity(0.2)
        }

        static func textColor(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ?
                Color(red: 0.898, green: 0.898, blue: 0.898) : // #e5e5e5
                Color(red: 0.067, green: 0.094, blue: 0.067) // #111811
        }

        static func modalBackground(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ?
                Color(red: 0.11, green: 0.11, blue: 0.118) : // #1c1c1e
                Color.white
        }

        static func keypadBackground(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ?
                primary.opacity(0.2) :
                primary.opacity(0.1)
        }
    }
}

// MARK: - Preview
struct ParentPINEntryView_Previews: PreviewProvider {
    @State static var previewPIN = ""
    @State static var previewError: String? = nil
    
    static var previews: some View {
        ParentPINEntryView(
            pin: $previewPIN,
            errorMessage: $previewError,
            onPINVerified: {},
            onDismiss: {}
        )
        .padding()
    }
}