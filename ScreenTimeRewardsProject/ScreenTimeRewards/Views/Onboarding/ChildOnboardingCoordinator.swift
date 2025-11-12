import SwiftUI

/// Coordinates the child device onboarding flow.
struct ChildOnboardingCoordinator: View {
    enum ChildStep {
        case pathSelection
        case authorization
        case learningSetup
        case rewardSetup
        case challengeBuilder
        case paywall
        case completion
    }

    @State private var currentStep: ChildStep = .pathSelection
    @State private var selectedPath: OnboardingPath?
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false

    let deviceName: String
    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Group {
            switch currentStep {
            case .pathSelection:
                OnboardingPathSelectionScreen(
                    deviceName: deviceName,
                    onBack: onBack,
                    onPathSelected: handlePathSelection
                )

            case .authorization:
                AuthorizationRequestScreen(
                    title: "Grant Device Permissions",
                    message: "ScreenTime Rewards needs FamilyControls access to track learning time and unlock rewards.",
                    buttonTitle: "Allow Access",
                    onBack: { currentStep = .pathSelection },
                    onAuthorized: handleAuthorizationComplete
                )

            case .learningSetup:
                QuickLearningSetupScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .authorization },
                    onContinue: { currentStep = .rewardSetup }
                )

            case .rewardSetup:
                QuickRewardSetupScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .learningSetup },
                    onContinue: { currentStep = .challengeBuilder }
                )

            case .challengeBuilder:
                OnboardingChallengeBuilderScreen(
                    onBack: { currentStep = .rewardSetup },
                    onContinue: { currentStep = .paywall }
                )

            case .paywall:
                ChildPaywallStepView(
                    onBack: handlePaywallBack,
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

    private func handlePathSelection(_ path: OnboardingPath) {
        selectedPath = path
        currentStep = .authorization
    }

    private func handleAuthorizationComplete() {
        switch selectedPath {
        case .quickStart:
            currentStep = .paywall
        case .fullSetup:
            currentStep = .learningSetup
        case .none:
            currentStep = .paywall
        }
    }

    private func handlePaywallBack() {
        switch selectedPath {
        case .quickStart:
            currentStep = .authorization
        case .fullSetup:
            currentStep = .challengeBuilder
        case .none:
            currentStep = .authorization
        }
    }

    private func completeChildOnboarding() {
        childComplete = true
        onComplete()
    }
}
