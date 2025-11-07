//
//  AuthorizationRequestScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Requests FamilyControls authorization
//

import SwiftUI
import FamilyControls

// MARK: - Design Tokens
fileprivate struct AuthColors {
    static let primary = Color(hex: "#4F46E5")
    static let secondary = Color(hex: "#6366F1")
    static let success = Color(hex: "#10B981")
    static let background = Color(hex: "#F9FAFB")
    static let text = Color(hex: "#1F2937")
    static let subtext = Color(hex: "#1F2937").opacity(0.7)
    static let featureDesc = Color(hex: "#1F2937").opacity(0.6)
    static let privacyText = Color(hex: "#1F2937").opacity(0.5)
}

struct AuthorizationRequestScreen: View {
    let onAuthorized: () -> Void

    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Content area - grows to fill available space
            VStack(spacing: 0) {
                // Max width container for centered content
                VStack(spacing: 0) {
                    // Icon container
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AuthColors.primary.opacity(0.1))
                            .frame(width: 64, height: 64)

                        Image(systemName: "figure.2.and.child.holdinghands")
                            .font(.system(size: 36))
                            .foregroundColor(AuthColors.primary)
                    }
                    .padding(.bottom, 24)

                    // Title
                    Text("Enable Family Controls")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AuthColors.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1.25)
                        .padding(.bottom, 12)

                    // Description
                    Text("To create a healthy and rewarding screen time experience, we need your permission to manage app access.")
                        .font(.system(size: 16))
                        .foregroundColor(AuthColors.subtext)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 32)

                    // Features list
                    VStack(spacing: 16) {
                        FeatureItem(
                            title: "Set Learning Apps",
                            description: "Designate educational apps for your child to focus on."
                        )

                        FeatureItem(
                            title: "Unlock Reward Apps",
                            description: "Time spent on learning unlocks access to their favorite games and apps."
                        )

                        FeatureItem(
                            title: "Ensure Focus",
                            description: "We'll gently guide your child back to learning apps if they get distracted."
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .frame(maxWidth: 448) // max-w-md
            }

            Spacer()

            // Footer section - sticky to bottom
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    // Grant Permission Button
                    Button(action: requestAuthorization) {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Grant Permission")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isRequesting ? AuthColors.primary.opacity(0.6) : AuthColors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: AuthColors.primary.opacity(0.3), radius: 12, x: 0, y: 4)
                    }
                    .disabled(isRequesting)

                    // Privacy text
                    Text("Your data is private and secure. Learn more.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AuthColors.privacyText)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 448) // max-w-md
            }
            .background(
                AuthColors.background.opacity(0.8)
                    .background(.ultraThinMaterial)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuthColors.background)
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

// MARK: - Feature Item Component
struct FeatureItem: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Checkmark icon container
            ZStack {
                Circle()
                    .fill(AuthColors.success.opacity(0.1))
                    .frame(width: 24, height: 24)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AuthColors.success)
            }
            .frame(width: 24, height: 24)
            .padding(.top, 2)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AuthColors.text)
                    .lineSpacing(1.2)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(AuthColors.featureDesc)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AuthorizationRequestScreen_Previews: PreviewProvider {
    static var previews: some View {
        AuthorizationRequestScreen(onAuthorized: {})
    }
}
