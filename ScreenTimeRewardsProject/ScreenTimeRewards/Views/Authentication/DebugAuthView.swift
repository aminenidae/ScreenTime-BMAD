//
//  DebugAuthView.swift
//  ScreenTimeRewards
//
//  Created for debugging Phase 4B authentication flow
//  Updated for Option D: Authorization at Launch + PIN for Access
//

import SwiftUI

struct DebugAuthView: View {
    @State private var authService = AuthenticationService()
    @State private var showPINEntry = false
    @State private var showPINSetup = false
    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var pinErrorMessage: String? = nil
    @State private var isConfirmingPIN = false
    @State private var isPINConfigured = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Phase 4B Authentication Debug")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("This view helps test the new authentication flows")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Authentication Status:")
                        .font(.headline)
                    
                    Text("PIN Configured: \(isPINConfigured ? "Yes" : "No")")
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                
                Divider()
                
                VStack(spacing: 15) {
                    Button("Check PIN Status") {
                        isPINConfigured = authService.isPINConfigured()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Force PIN Setup") {
                        showPINSetup = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Force PIN Entry") {
                        showPINEntry = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test Weak PIN Detection") {
                        testWeakPINDetection()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
            }
            .padding()
            .sheet(isPresented: $showPINEntry) {
                ParentPINEntryView(
                    pin: $pin,
                    errorMessage: $pinErrorMessage,
                    onPINVerified: {
                        showPINEntry = false
                        pin = ""
                    },
                    onDismiss: {
                        showPINEntry = false
                        pin = ""
                    }
                )
            }
            .sheet(isPresented: $showPINSetup) {
                ParentPINSetupView(
                    pin: $pin,
                    confirmPIN: $confirmPIN,
                    errorMessage: $pinErrorMessage,
                    isConfirming: $isConfirmingPIN,
                    onPINSetup: {
                        showPINSetup = false
                    },
                    onDismiss: {
                        showPINSetup = false
                        pin = ""
                        confirmPIN = ""
                        isConfirmingPIN = false
                    }
                )
            }
            .navigationTitle("Auth Debug")
        }
    }
    
    private func testWeakPINDetection() {
        let pinService = ParentPINService.shared
        let weakPINS = ["1234", "0000", "1111", "2345", "5432"]
        let strongPINS = ["1235", "5678", "1357"]
        
        print("Testing weak PINs:")
        for pin in weakPINS {
            let isWeak = pinService.isWeakPIN(pin)
            print("  \(pin): \(isWeak ? "WEAK" : "STRONG")")
        }
        
        print("Testing strong PINs:")
        for pin in strongPINS {
            let isWeak = pinService.isWeakPIN(pin)
            print("  \(pin): \(isWeak ? "WEAK" : "STRONG")")
        }
    }
}

struct DebugAuthView_Previews: PreviewProvider {
    static var previews: some View {
        DebugAuthView()
    }
}