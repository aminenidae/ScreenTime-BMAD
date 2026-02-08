//
//  PINKeypadView.swift
//  ScreenTimeRewards
//
//  Created by Ameen on 26/10/2025.
//

import SwiftUI

struct PINKeypadView: View {
    @Binding var pin: String
    var isConfirmation: Bool = false
    var onPINEntered: (() -> Void)?

    private let maxDigits = 4

    var body: some View {
        VStack(spacing: 0) {
            // PIN display (indicator dots)
            HStack(spacing: 16) {
                ForEach(0..<maxDigits, id: \.self) { index in
                    PinDigitView(isFilled: index < pin.count)
                }
            }
            .padding(.vertical, 12)
            .padding(.top, 48)

            Spacer()

            // Keypad grid
            VStack(spacing: 16) {
                // Rows 1-3: Numbers 1-9
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(1...9, id: \.self) { number in
                        PINKeypadButton(title: "\(number)") {
                            appendDigit("\(number)")
                        }
                    }
                }

                // Row 4: Empty space, 0, delete
                HStack(spacing: 16) {
                    // Empty space for alignment
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)

                    PINKeypadButton(title: "0") {
                        appendDigit("0")
                    }

                    PINKeypadButton(title: "delete.left", isDelete: true) {
                        deleteDigit()
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 320)

            Spacer()
                .frame(height: 32)
        }
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

// MARK: - Design Tokens
extension PINKeypadView {
    struct Colors {
        // Light mode colors
        static let backgroundLight = Color(hex: "F8F9FA")
        static let textLight = Color(hex: "212529")
        static let buttonLight = Color(hex: "E9ECEF")

        // Dark mode colors
        static let backgroundDark = Color(hex: "1C1C1E")
        static let textDark = Color(hex: "F2F2F7")
        static let buttonDark = Color(hex: "2C2C2E")

        // System colors
        static let primary = Color(hex: "007AFF") // System Blue
        static let error = Color(hex: "DC3545")
    }
}

// MARK: - PIN Keypad Button
struct PINKeypadButton: View {
    @Environment(\.colorScheme) var colorScheme

    let title: String
    var isDelete: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isDelete {
                    Image(systemName: title)
                        .font(.system(size: 30))
                        .foregroundColor(colorScheme == .dark ? PINKeypadView.Colors.textDark : PINKeypadView.Colors.textLight)
                } else {
                    Text(title)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? PINKeypadView.Colors.textDark : PINKeypadView.Colors.textLight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                Circle()
                    .fill(isDelete ? Color.clear : (colorScheme == .dark ? PINKeypadView.Colors.buttonDark : PINKeypadView.Colors.buttonLight))
            )
        }
    }
}

// MARK: - PIN Digit View
struct PinDigitView: View {
    @Environment(\.colorScheme) var colorScheme
    let isFilled: Bool

    var body: some View {
        Circle()
            .fill(isFilled ? PINKeypadView.Colors.primary : Color.clear)
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .strokeBorder(
                        isFilled ? Color.clear : PINKeypadView.Colors.primary.opacity(colorScheme == .dark ? 0.4 : 0.5),
                        lineWidth: 2
                    )
            )
    }
}

// MARK: - Preview
struct PINKeypadView_Previews: PreviewProvider {
    @State static var previewPIN = ""
    
    static var previews: some View {
        PINKeypadView(pin: $previewPIN)
            .padding()
    }
}