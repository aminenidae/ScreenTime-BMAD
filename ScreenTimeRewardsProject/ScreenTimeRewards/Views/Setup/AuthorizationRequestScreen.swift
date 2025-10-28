//
//  AuthorizationRequestScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Requests FamilyControls authorization
//

import SwiftUI
import FamilyControls

struct AuthorizationRequestScreen: View {
    let onAuthorized: () -> Void

    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""

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
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                // Title
                Text("Permission Required")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Explanation
                VStack(spacing: 16) {
                    Text("ScreenTime Rewards needs permission to:")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        PermissionItem(text: "Monitor app usage time")
                        PermissionItem(text: "Apply screen time restrictions")
                        PermissionItem(text: "Manage learning and reward apps")
                    }
                    .padding(.horizontal, 40)
                }

                Text("On child accounts, this will require parental approval.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                // Request Authorization button
                Button(action: requestAuthorization) {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Grant Permission")
                                .font(.headline)
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRequesting ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(radius: 5)
                }
                .disabled(isRequesting)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .alert("Authorization Error", isPresented: $showError) {
            Button("Try Again", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func requestAuthorization() {
        isRequesting = true

        #if DEBUG
        print("[AuthorizationRequestScreen] Requesting FamilyControls authorization...")
        #endif

        Task {
            do {
                // Request authorization from FamilyControls
                // On child devices: Shows Apple ID password dialog
                // On regular devices: Shows permission dialog
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

                #if DEBUG
                print("[AuthorizationRequestScreen] ✅ Authorization granted")
                #endif

                await MainActor.run {
                    isRequesting = false

                    // Save authorization flag
                    UserDefaults.standard.set(true, forKey: "authorizationGranted")

                    // Continue to next step
                    onAuthorized()
                }

            } catch {
                #if DEBUG
                print("[AuthorizationRequestScreen] ❌ Authorization failed: \(error)")
                #endif

                await MainActor.run {
                    isRequesting = false
                    errorMessage = "Failed to get authorization. Please try again.\n\nError: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

struct PermissionItem: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            Text(text)
                .font(.body)
        }
    }
}

struct AuthorizationRequestScreen_Previews: PreviewProvider {
    static var previews: some View {
        AuthorizationRequestScreen(onAuthorized: {})
    }
}
