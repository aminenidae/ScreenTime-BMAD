//
//  AuthorizationRequestScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Requests FamilyControls authorization
//
//

import SwiftUI
import FamilyControls

struct AuthorizationRequestScreen: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onAuthorized: () -> Void
    let onBack: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String = "Enable Family Controls",
        message: String = "To create a healthy and rewarding screen time experience, we need your permission to manage app access.",
        buttonTitle: String = "Grant Permission",
        onBack: (() -> Void)? = nil,
        onAuthorized: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.onBack = onBack
        self.onAuthorized = onAuthorized
    }

    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Content area - grows to fill available space
            VStack(spacing: 0) {
                // Max width container for centered content
                VStack(spacing: 0) {
                    if let onBack {
                        HStack {
                            Button(action: onBack) {
                                Label("Back", systemImage: "chevron.left")
                                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                            }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.bottom, 24)
                    }

                    // Icon container
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.vibrantTeal.opacity(0.1))
                            .frame(width: 64, height: 64)

                        Image(systemName: "figure.2.and.child.holdinghands")
                            .font(.system(size: 36))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                    .padding(.bottom, 24)

                    // Title
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1.25)
                        .padding(.bottom, 12)

                    // Description
                    Text(message)
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 32)

                    // Features list
                    VStack(spacing: 16) {
                        FeatureItem(
                            title: "Set Learning Apps",
                            description: "Designate educational apps for your child to focus on.",
                            colorScheme: colorScheme
                        )

                        FeatureItem(
                            title: "Unlock Reward Apps",
                            description: "Time spent on learning unlocks access to their favorite games and apps.",
                            colorScheme: colorScheme
                        )

                        FeatureItem(
                            title: "Ensure Focus",
                            description: "We'll gently guide your child back to learning apps if they get distracted.",
                            colorScheme: colorScheme
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
                                Text(buttonTitle)
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isRequesting ? AppTheme.vibrantTeal.opacity(0.6) : AppTheme.vibrantTeal)
                        .foregroundColor(AppTheme.lightCream)
                        .cornerRadius(12)
                        .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 12, x: 0, y: 4)
                    }
                    .disabled(isRequesting)

                    // Privacy text
                    Text("Your data is private and secure. Learn more.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 448) // max-w-md
            }
            .background(
                AppTheme.background(for: colorScheme).opacity(0.8)
                    .background(.ultraThinMaterial)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme))
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
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Checkmark icon container
            ZStack {
                Circle()
                    .fill(AppTheme.sunnyYellow.opacity(0.1))
                    .frame(width: 24, height: 24)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.sunnyYellow)
            }
            .frame(width: 24, height: 24)
            .padding(.top, 2)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .lineSpacing(1.2)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
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
