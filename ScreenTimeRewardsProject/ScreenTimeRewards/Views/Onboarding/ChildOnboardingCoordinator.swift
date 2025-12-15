import SwiftUI

/// Coordinates the child device onboarding flow - 7-step marketing journey
struct ChildOnboardingCoordinator: View {
    enum ChildStep {
        case welcome              // Screen 1: Welcome
        case solution             // Screen 2: Solution Visualization
        case interactiveDemo      // Screen 3: Interactive Demo (most critical)
        case socialProof          // Screen 4: Social Proof
        case learningSetup        // Screen 5: Learning Apps Setup
        case rewardSetup          // Screen 6: Reward Apps Setup
        case paywall              // Screen 7: Paywall
        case completion           // Screen 8: Completion
    }

    @State private var currentStep: ChildStep = .welcome
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false

    let deviceName: String
    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Group {
            switch currentStep {
            case .welcome:
                ChildOnboardingWelcomeScreen {
                    currentStep = .solution
                }

            case .solution:
                ChildOnboardingSolutionScreen(
                    onContinue: { currentStep = .interactiveDemo },
                    onBack: { currentStep = .welcome }
                )

            case .interactiveDemo:
                ChildOnboardingInteractiveDemoScreen(
                    onContinue: { currentStep = .socialProof },
                    onBack: { currentStep = .solution }
                )

            case .socialProof:
                ChildOnboardingSocialProofScreen(
                    onContinue: { currentStep = .learningSetup },
                    onBack: { currentStep = .interactiveDemo }
                )

            case .learningSetup:
                QuickLearningSetupScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .socialProof },
                    onContinue: { currentStep = .rewardSetup }
                )

            case .rewardSetup:
                QuickRewardSetupScreen(
                    deviceName: deviceName,
                    onBack: { currentStep = .learningSetup },
                    onContinue: { currentStep = .paywall }
                )

            case .paywall:
                ChildPaywallStepView(
                    onBack: { currentStep = .rewardSetup },
                    onComplete: { currentStep = .completion }
                )

            case .completion:
                ChildOnboardingCompletionScreen {
                    completeChildOnboarding()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private func completeChildOnboarding() {
        childComplete = true
        onComplete()
    }
}
