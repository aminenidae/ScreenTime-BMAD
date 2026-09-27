import SwiftUI
import FamilyControls

/// Screen 4: FamilyControls Authorization.
/// Primes the user before the iOS Screen Time prompt, then requests it.
///
/// This screen is a gate, not a step: nothing downstream works without access — the
/// app picker refuses to open, and the tutorial (which is built around picking apps)
/// can neither be completed nor exited.
///
/// Deliberately sized to fit one screen without scrolling. A parent deciding whether
/// to hand over an Apple permission should be able to see the reassurance and the
/// button at the same time; making them scroll to find the CTA reads as something
/// being buried. Three short safety lines do more work here than paragraphs.
///
/// It only handles the first ask. A refusal hands off to
/// Screen4bPermissionRecoveryView, which asks again.
struct Screen4_AuthorizationView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme

    /// Called once Screen Time access is approved.
    let onGranted: () -> Void
    /// Called when access has been refused.
    let onDenied: () -> Void

    @State private var isRequesting = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header
                promptPreview
                safetyLines
                callToAction
            }
            .padding(.bottom, 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            routeIfAlreadyAnswered()
            onboarding.logScreenView(screenNumber: 4)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("ONE TAP TO TURN IT ON")
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .tracking(1)

            Text("Apple will ask next. Tap Allow — you may need your passcode.")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    // MARK: - Annotated preview of Apple's prompt

    private var promptPreview: some View {
        SystemPromptPreview()
            .frame(maxWidth: 155)
            .padding(.horizontal, 24)
    }

    // MARK: - Safety

    private var safetyLines: some View {
        PermissionSafetyLines()
            .padding(.horizontal, 30)
    }

    // MARK: - CTA

    private var callToAction: some View {
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
        .padding(.top, 2)
    }

    // MARK: - Actions

    /// A re-entry (relaunch mid-onboarding) may arrive with the question already
    /// answered — skip the ask rather than showing a prompt that won't appear.
    private func routeIfAlreadyAnswered() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: onGranted()
        case .denied:   onDenied()
        default:        break
        }
    }

    private func requestAuthorization() {
        isRequesting = true
        AppAnalytics.shared.track(.authorizationRequested, parameters: ["source": "onboarding_permission"])
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

                // Also request notification permissions (non-blocking)
                _ = await NotificationService.shared.requestAuthorization()

                await MainActor.run {
                    isRequesting = false
                    AppAnalytics.shared.track(.authorizationGranted, parameters: ["source": "onboarding_permission"])
                    onGranted()
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    AppAnalytics.shared.track(.authorizationDenied, parameters: [
                        "source": "onboarding_permission",
                        "error_code": String(describing: error)
                    ])
                    // Hand off to the recovery screen, which asks again.
                    onDenied()
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(6)
                    .position(x: w * 0.5, y: h * (allowCenterY - allowHeightFrac - 0.035))
            }
        }
        .aspectRatio(imageAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Preview

#Preview {
    Screen4_AuthorizationView(onGranted: {}, onDenied: {})
        .environmentObject(OnboardingStateManager())
}
