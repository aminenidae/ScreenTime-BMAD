import SwiftUI

/// Coordinates the child device onboarding flow.
struct ChildOnboardingCoordinator: View {
    enum ChildStep {
        case authorization
        case paywall
        case completion
    }

    @State private var currentStep: ChildStep = .authorization
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false

    let deviceName: String
    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Group {
            switch currentStep {
            case .authorization:
                AuthorizationRequestScreen(
                    title: "Grant Device Permissions",
                    message: "ScreenTime Rewards needs FamilyControls access to track learning time and unlock rewards.",
                    buttonTitle: "Allow Access",
                    onBack: onBack,
                    onAuthorized: { currentStep = .paywall }
                )

            case .paywall:
                ChildPaywallStepView(
                    onBack: { currentStep = .authorization },
                    onComplete: { currentStep = .completion }
                )

            case .completion:
                ChildOnboardingCompletionScreen {
                    completeChildOnboarding()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    private func completeChildOnboarding() {
        childComplete = true
        onComplete()
    }
}
