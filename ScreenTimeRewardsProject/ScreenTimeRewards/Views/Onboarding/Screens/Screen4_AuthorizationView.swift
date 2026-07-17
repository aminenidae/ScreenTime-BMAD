import SwiftUI
import FamilyControls
import UIKit

/// Screen 4: FamilyControls Authorization
/// Primes the user before the iOS Screen Time permission prompt, then requests it.
struct Screen4_AuthorizationView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false
    @State private var showError = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Headline + expectation (incl. passcode heads-up)
                VStack(spacing: 12) {
                    Text("ONE TAP TO TURN IT ON")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .tracking(1)

                    Text("Apple will ask for your permission next. Tap Allow — you may need to enter your passcode. That's the switch that lets the app lock and unlock apps for your child.")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                // Caption over the preview
                Text("Here's the screen you'll see")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(1)

                // Annotated preview of Apple's system prompt
                SystemPromptPreview()
                    .frame(maxWidth: 250)
                    .padding(.horizontal, 24)

                // Reassurance — answers the fears
                VStack(alignment: .leading, spacing: 12) {
                    AuthReassuranceRow(
                        icon: "lock.fill",
                        text: String(localized: "Private by design. We never see messages, photos, location, or browsing.")
                    )
                    AuthReassuranceRow(
                        icon: "arrow.uturn.backward",
                        text: "You're in control — turn it off anytime in Settings."
                    )
                }
                .padding(.horizontal, 32)

                // CTA Button
                Button(action: requestAuthorization) {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Turn On Controls")
                    }
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .textCase(.uppercase)
                }
                .disabled(isRequesting)
                .padding(.horizontal, 24)

                // Back button
                Button(action: { onboarding.goBack() }) {
                    Text("Back")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.vibrantTeal.opacity(0.1))
                        .cornerRadius(AppTheme.CornerRadius.medium)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .alert("The app can't work without this", isPresented: $showError) {
            Button("Try Again") { requestAuthorization() }
            Button("Open Settings") { openSettings() }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Screen Time permission is the on/off switch for locking and rewarding apps. Without it, nothing can be blocked or unlocked. Turn it on now, or enable it later in Settings › Screen Time.")
        }
        .onAppear {
            checkExistingAuthorization()
            onboarding.logScreenView(screenNumber: 4)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func checkExistingAuthorization() {
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            onboarding.advanceScreen()
        }
    }

    private func requestAuthorization() {
        isRequesting = true
        AppAnalytics.shared.track(.authorizationRequested)
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

                // Also request notification permissions (non-blocking)
                _ = await NotificationService.shared.requestAuthorization()

                await MainActor.run {
                    isRequesting = false
                    AppAnalytics.shared.track(.authorizationGranted)
                    onboarding.advanceScreen()
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    showError = true
                    AppAnalytics.shared.track(.authorizationDenied, parameters: [
                        "error_code": String(describing: error)
                    ])
                }
            }
        }
    }
}

// MARK: - System Prompt Preview

/// Shows a real screenshot of Apple's Screen Time permission dialog with a teal
/// highlight + "Tap Allow" callout over the Allow button, so the user knows
/// exactly what's coming and which button to tap.
private struct SystemPromptPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    // Image is cropped to 1206×2210. Fractional position of the
    // "Allow with Passcode" button within that crop (measured from the asset).
    private let imageAspect: CGFloat = 1206.0 / 2210.0
    private let allowCenterY: CGFloat = 0.897
    private let allowWidthFrac: CGFloat = 0.86
    private let allowHeightFrac: CGFloat = 0.078

    var body: some View {
        ZStack {
            Image("system_permission_preview")
                .resizable()
                .scaledToFit()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Highlight ring around the Allow button
                RoundedRectangle(cornerRadius: h * allowHeightFrac / 2)
                    .stroke(AppTheme.vibrantTeal, lineWidth: 3)
                    .frame(width: w * allowWidthFrac, height: h * allowHeightFrac)
                    .position(x: w * 0.5, y: h * allowCenterY)

                // "Tap Allow" callout floating just above the button
                Text("👆 Tap Allow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(8)
                    .position(x: w * 0.5, y: h * (allowCenterY - allowHeightFrac - 0.035))
            }
        }
        .aspectRatio(imageAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Reassurance Row

private struct AuthReassuranceRow: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.vibrantTeal)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    Screen4_AuthorizationView()
        .environmentObject(OnboardingStateManager())
}
