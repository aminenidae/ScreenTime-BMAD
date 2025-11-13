import SwiftUI

/// Coordinates the child device onboarding flow.
struct ChildOnboardingCoordinator: View {
    enum ChildStep {
        case authorization
        case learningSetup
        case rewardSetup
        case challengeBuilder
        case paywall
        case completion
    }

    @State private var currentStep: ChildStep = .authorization
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false
    @StateObject private var challengeViewModel = ChallengeViewModel()
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel

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
                    onAuthorized: { currentStep = .learningSetup }
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
                ChallengeBuilderFlowView(
                    viewModel: challengeViewModel,
                    isOnboarding: true,
                    onBack: { currentStep = .rewardSetup },
                    onComplete: { currentStep = .paywall },
                    onSkip: { currentStep = .paywall }
                )

            case .paywall:
                ChildPaywallStepView(
                    onBack: { currentStep = .challengeBuilder },
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

        // CRITICAL: Ensure reward apps are shielded when onboarding completes
        // This applies shields when user:
        // - Subscribes
        // - Accepts free trial
        // - Skips (30-day trial)
        // Only after they complete onboarding (not if they abandon)
        appUsageViewModel.blockRewardApps()

        onComplete()
    }
}
