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
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                Text(isConfirming ? "Confirm Parent PIN" : "Set Up Parent PIN")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(isConfirming ? "Re-enter your 4-digit PIN to confirm" : "Create a 4-digit PIN to protect Parent Mode")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // PIN Keypad
            PINKeypadView(pin: isConfirming ? $confirmPIN : $pin, isConfirmation: isConfirming, onPINEntered: {
                if isConfirming {
                    confirmPINSetup()
                } else {
                    proceedToConfirmation()
                }
            })
            
            // Cancel button
            Button("Cancel") {
                onDismiss()
            }
            .font(.headline)
            .foregroundColor(.blue)
            .padding()
        }
        .padding()
        .disabled(isSettingUp)
        .overlay {
            if isSettingUp {
                ProgressView("Setting up PIN...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10)
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
            // In a real implementation, this would call the AuthenticationService
            // to store the PIN. For now, we'll simulate the setup.
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isSettingUp = false
                onPINSetup()
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
        .padding()
    }
}