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
        VStack(spacing: 20) {
            // PIN display
            HStack(spacing: 10) {
                ForEach(0..<maxDigits, id: \.self) { index in
                    PinDigitView(isFilled: index < pin.count)
                }
            }
            .padding(.bottom, 20)
            
            // Keypad grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                ForEach(1...9, id: \.self) { number in
                    PINKeypadButton(title: "\(number)") {
                        appendDigit("\(number)")
                    }
                }
                
                // Empty space for 0 button alignment
                Color.clear
                
                PINKeypadButton(title: "0") {
                    appendDigit("0")
                }
                
                PINKeypadButton(title: "⌫", isDelete: true) {
                    deleteDigit()
                }
            }
            .padding(.horizontal, 20)
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

// MARK: - PIN Keypad Button
struct PINKeypadButton: View {
    let title: String
    var isDelete: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isDelete ? .red : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    Circle()
                        .fill(Color(UIColor.systemGray6))
                )
        }
    }
}

// MARK: - PIN Digit View
struct PinDigitView: View {
    let isFilled: Bool
    
    var body: some View {
        Circle()
            .fill(isFilled ? Color.blue : Color(UIColor.systemGray4))
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .stroke(Color.blue, lineWidth: isFilled ? 0 : 1)
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