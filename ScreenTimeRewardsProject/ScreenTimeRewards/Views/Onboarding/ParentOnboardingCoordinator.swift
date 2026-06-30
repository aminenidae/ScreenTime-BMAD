import SwiftUI

/// Coordinates the parent device onboarding flow.
struct ParentOnboardingCoordinator: View {
    enum ParentStep {
        case welcome
        case paywall
        case installationGuide
        case pairing
    }

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var currentStep: ParentStep = .welcome
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
                        // Parent device requires actual paid subscription, not trial
                        // Trial is for child devices only
                        if subscriptionManager.currentStatus == .active {
                            currentStep = .installationGuide
                        } else {
                            currentStep = .paywall
                        }
                    }
                )

            case .paywall:
                ParentPaywallView(
                    onSubscribed: { currentStep = .installationGuide },
                    onSkip: nil  // No skip - subscription required on parent device
                )

            case .installationGuide:
                ParentDeviceSetupScreen(
                    deviceName: deviceName,
                    onBack: {
                        // Go back to paywall if not subscribed, otherwise welcome
                        if subscriptionManager.currentStatus == .active {
                            currentStep = .welcome
                        } else {
                            currentStep = .paywall
                        }
                    },
                    onContinue: { currentStep = .pairing }
                )

            case .pairing:
                ParentPairingScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .installationGuide },
                    onSkip: completeParentOnboarding,
                    onPaired: completeParentOnboarding
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
        .onAppear { trackStepViewed(currentStep) }
        .onChange(of: currentStep) { step in trackStepViewed(step) }
    }

    private func completeParentOnboarding() {
        parentComplete = true
        AppAnalytics.shared.track(.onboardingCompleted, parameters: ["flow": "parent"])
        onComplete()
    }

    private func trackStepViewed(_ step: ParentStep) {
        AppAnalytics.shared.track(.onboardingScreenViewed, parameters: [
            "flow": "parent",
            "screen_name": screenName(for: step)
        ])
    }

    private func screenName(for step: ParentStep) -> String {
        switch step {
        case .welcome:           return "parent_welcome"
        case .paywall:           return "parent_paywall"
        case .installationGuide: return "parent_setup_guide"
        case .pairing:           return "parent_pairing"
        }
    }
}
