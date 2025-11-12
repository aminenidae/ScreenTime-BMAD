import SwiftUI

/// Coordinates the parent device onboarding flow.
struct ParentOnboardingCoordinator: View {
    enum ParentStep {
        case welcome
        case installationGuide
        case pairing
    }

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
                    onContinue: { currentStep = .installationGuide }
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
                    onSkip: completeParentOnboarding,
                    onPaired: completeParentOnboarding
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    private func completeParentOnboarding() {
        parentComplete = true
        onComplete()
    }
}
