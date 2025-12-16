import SwiftUI

/// Container view that manages the 7-screen onboarding flow
struct OnboardingContainerView: View {
    @StateObject private var onboarding = OnboardingStateManager()
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    let onComplete: (OnboardingDestination) -> Void

    enum OnboardingDestination {
        case childDashboard
        case parentDashboard
    }

    var body: some View {
        ZStack {
            switch onboarding.currentScreen {
            case 1:
                Screen1_ProblemView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 2:
                Screen2_SolutionView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 3:
                Screen3_SetupPreviewView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 4:
                Screen4_LearningAppsView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 5:
                Screen5_RewardAppsView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 6:
                Screen6_TrialPaywallView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 7:
                Screen7_ActivationView(
                    onShowChildDashboard: { onComplete(.childDashboard) },
                    onShowParentDashboard: { onComplete(.parentDashboard) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            default:
                // Fallback - should not happen
                Screen1_ProblemView()
            }
        }
        .environmentObject(onboarding)
        .environmentObject(subscriptionManager)
        .onAppear {
            // Connect the onboarding manager to AppUsageViewModel
            onboarding.appUsageViewModel = appUsageViewModel
        }
        .onChange(of: onboarding.onboardingComplete) { completed in
            if completed {
                // Mark child onboarding as complete in UserDefaults
                UserDefaults.standard.set(true, forKey: "hasCompletedChildOnboarding")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView { destination in
        print("Onboarding completed with destination: \(destination)")
    }
    .environmentObject(AppUsageViewModel())
    .environmentObject(SubscriptionManager.shared)
}
