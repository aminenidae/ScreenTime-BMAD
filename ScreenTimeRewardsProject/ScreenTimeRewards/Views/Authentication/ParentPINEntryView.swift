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
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                Text("Enter Parent PIN")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your 4-digit parent PIN to access Parent Mode")
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
            PINKeypadView(pin: $pin, onPINEntered: {
                verifyPIN()
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
                errorMessage = "Invalid PIN. Please try again."
            }
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