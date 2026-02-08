import SwiftUI

/// Container view that manages the onboarding flow
/// Flow varies based on path selection:
/// - Solo: Screen 1-2-3-4-5-6(paywall)-7
/// - Family: Screen 1-2-3-4-5-7 (skip paywall, 14-day trial)
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
                // Path selection: Solo vs Family
                SetupPathSelectionView { path in
                    onboarding.selectPath(path)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            case 4:
                Screen4_AuthorizationView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

            case 5:
                Screen5_GuidedTutorialView(
                    onTutorialComplete: {
                        // After tutorial, go to paywall for Solo or skip to activation for Family
                        if onboarding.shouldShowPaywall {
                            onboarding.advanceScreen() // Go to screen 6 (paywall)
                        } else {
                            // Family path: skip paywall, start 14-day trial
                            startFamilyTrial()
                            onboarding.currentScreen = 7 // Skip to activation
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            case 6:
                // Paywall - only shown for Solo path
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

                // Store the selected path
                if let path = onboarding.selectedPath {
                    UserDefaults.standard.set(path.rawValue, forKey: "onboardingSetupPath")
                }
            }
        }
    }

    /// Start 14-day trial for Family path (no paywall shown to child)
    private func startFamilyTrial() {
        onboarding.trialStartDate = Date()

        // Start trial via ChildBackgroundSyncService (handles caching and status)
        ChildBackgroundSyncService.shared.startFamilyTrial()

        #if DEBUG
        print("[Onboarding] Family path - starting 14-day trial (paywall on parent device)")
        #endif

        // The child will need to pair with a subscribed parent before trial ends
        // NotificationService can schedule reminders for this
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
