import SwiftUI

/// Coordinates the parent device onboarding flow.
/// Trial-first: no hard-gate paywall. Every parent enters on the no-card 14-day trial
/// that SubscriptionManager auto-starts on first launch; pricing is deferred to the
/// in-app conversion surfaces (trial banner + Settings). Flow: welcome → install guide
/// → pairing → finish line. See docs/ONBOARDING_TRIAL_FIRST_REDESIGN_2026-07-22.md.
struct ParentOnboardingCoordinator: View {
    enum ParentStep {
        case welcome
        case installationGuide
        case pairing
        case finishLine
    }

    @State private var currentStep: ParentStep = .welcome
    @State private var trialEntryLogged = false
    @AppStorage("hasCompletedParentOnboarding") private var parentComplete = false

    let deviceName: String
    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Group {
            switch currentStep {
            case .welcome:
                ParentWelcomeScreen(
                    deviceName: deviceName,
                    onBack: onBack,
                    onContinue: {
                        // Trial-first: no paywall gate. Proceed straight into setup on the
                        // no-card trial (SubscriptionManager already started it on launch).
                        logTrialEntryIfNeeded()
                        currentStep = .installationGuide
                    }
                )

            case .installationGuide:
                ParentDeviceSetupScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .welcome },
                    onContinue: { currentStep = .pairing }
                )

            case .pairing:
                ParentPairingScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .installationGuide },
                    onSkip: { currentStep = .finishLine },
                    onPaired: { currentStep = .finishLine }
                )

            case .finishLine:
                ParentFinishLineScreen(onContinue: completeParentOnboarding)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
        .onAppear { trackStepViewed(currentStep) }
        .onChange(of: currentStep) { step in trackStepViewed(step) }
    }

    /// Log the parent's trial entry once (funnel parity with the child path's trial_started).
    private func logTrialEntryIfNeeded() {
        guard !trialEntryLogged else { return }
        trialEntryLogged = true
        AppAnalytics.shared.trackOnboarding(.trialStarted, parameters: [
            "tier": "family",
            "status": "trial",
            "device_flow": "parent"
        ])
    }

    private func completeParentOnboarding() {
        parentComplete = true
        AppAnalytics.shared.trackOnboarding(.onboardingCompleted, parameters: ["flow": "parent"])
        onComplete()
    }

    private func trackStepViewed(_ step: ParentStep) {
        AppAnalytics.shared.trackOnboarding(.onboardingScreenViewed, parameters: [
            "flow": "parent",
            "screen_name": screenName(for: step)
        ])
    }

    private func screenName(for step: ParentStep) -> String {
        switch step {
        case .welcome:           return "parent_welcome"
        case .installationGuide: return "parent_setup_guide"
        case .pairing:           return "parent_pairing"
        case .finishLine:        return "parent_finish_line"
        }
    }
}

// MARK: - Parent finish line

/// The parent path's "finish line": celebrates entry and confirms the trial has
/// started, then hands off to the dashboard. Pairing is reachable again later, so
/// this shows whether or not the parent paired during onboarding.
private struct ParentFinishLineScreen: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.accentText(for: colorScheme))

                Text("You're all set")
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("Your 14-day free trial has started. Manage everything from your dashboard — you can pair another device anytime.")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: 520)

            Spacer()

            Button(action: onContinue) {
                Text("Go to My Dashboard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 400)
                    .frame(height: 56)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(AppTheme.CornerRadius.medium)
            }
            .padding(.bottom, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            AppAnalytics.shared.trackOnboarding(.onboardingFinishLineShown, parameters: ["flow": "parent"])
        }
    }
}
