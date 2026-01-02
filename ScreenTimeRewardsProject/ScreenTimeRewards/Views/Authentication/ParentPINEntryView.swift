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

    // Design colors matching ModeSelectionView
    
    
    

    var body: some View {
        ZStack {
            // Full screen cream background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back button
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Go back")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Lock Icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .padding(.bottom, 24)

                // Title
                Text("ENTER PIN")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(3)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .padding(.bottom, 8)

                // Subtitle
                Text("ACCESS PARENT CONTROLS")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(2)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
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
                .padding(.bottom, 24)

                // PIN Display
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < pin.count ? AppTheme.brandedText(for: colorScheme) : Color.clear)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(
                                        errorMessage != nil && index >= pin.count ? AppTheme.errorRed : AppTheme.brandedText(for: colorScheme),
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
                                PINKeyButton(text: "\(number)", tealColor: AppTheme.brandedText(for: colorScheme), creamColor: AppTheme.background(for: colorScheme)) {
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
                        PINKeyButton(text: "0", tealColor: AppTheme.brandedText(for: colorScheme), creamColor: AppTheme.background(for: colorScheme)) {
                            appendDigit("0")
                        }

                        // Delete button
                        Button(action: deleteDigit) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                                .frame(width: 72, height: 72)
                        }
                    }
                }
                .frame(maxWidth: 320)

                Spacer()
            }

            // Loading overlay
            if isVerifying {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.background(for: colorScheme)))
                        .scaleEffect(1.5)

                    Text("VERIFYING")
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
        .disabled(isVerifying)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isVerifying = false

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

// MARK: - PIN Key Button
struct PINKeyButton: View {
    let text: String
    let tealColor: Color
    let creamColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(tealColor)
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tealColor.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tealColor.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PINKeyButtonStyle(tealColor: tealColor))
    }
}

// MARK: - PIN Key Button Style
struct PINKeyButtonStyle: ButtonStyle {
    let tealColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
    }
}
