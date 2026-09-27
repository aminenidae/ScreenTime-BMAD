import SwiftUI

/// The child-flow tail of onboarding. After the shared front (merged welcome → value
/// slides → device question), the child path enters here at the finish line, where the
/// no-card 14-day trial auto-starts. From there setup is mandatory and runs in order:
///
///   finish line → permission ask → (if refused) Settings recovery → tutorial → dashboard
///
/// The gate sits before the tutorial on purpose. Without Screen Time access the app
/// picker will not open, and the tutorial is built around picking apps — it can neither
/// be completed nor exited, so a parent sent there unauthorized is stuck. The tutorial's
/// own startup code has always assumed permission was already granted.
struct OnboardingContainerView: View {
    @StateObject private var onboarding = OnboardingStateManager()
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    /// Where in the child tail we are. Both permission steps are gates: approval is
    /// the only way onward. A refusal moves to `permissionRecovery` rather than
    /// re-asking, because iOS will not show its sheet a second time.
    private enum Step {
        case finishLine
        case permission
        case permissionRecovery
    }

    @State private var step: Step = .finishLine
    /// Presents the tutorial once permission is granted.
    @State private var showConfig = false

    let onComplete: (OnboardingDestination) -> Void

    enum OnboardingDestination {
        case childDashboard
        case parentDashboard
    }

    var body: some View {
        Group {
            switch step {
            case .finishLine:
                Screen7_ActivationView(
                    onStartTrial: { startFamilyTrial() },
                    onPersonalize: {
                        AppAnalytics.shared.trackOnboarding(.configStarted, parameters: ["source": "finish_line"])
                        withAnimation { step = .permission }
                    }
                )

            case .permission:
                Screen4_AuthorizationView(
                    onGranted: { showConfig = true },
                    onDenied: { withAnimation { step = .permissionRecovery } }
                )

            case .permissionRecovery:
                Screen4bPermissionRecoveryView(onGranted: { showConfig = true })
            }
        }
        .environmentObject(onboarding)
        .environmentObject(subscriptionManager)
        // Tutorial: the last step, presented only once Screen Time access is granted.
        .fullScreenCover(isPresented: $showConfig) {
            Screen5_GuidedTutorialView(
                onTutorialComplete: {
                    showConfig = false
                    enterChildDashboard()
                }
            )
            .environmentObject(appUsageViewModel)
            .environmentObject(subscriptionManager)
        }
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

    /// Start the no-card 14-day Family trial. Idempotent — the finish line fires this
    /// on appear, and it must not reset the trial clock if entered more than once.
    private func startFamilyTrial() {
        guard onboarding.trialStartDate == nil else { return }
        onboarding.trialStartDate = Date()

        // Start trial via ChildBackgroundSyncService (handles caching and status)
        ChildBackgroundSyncService.shared.startFamilyTrial()

        AppAnalytics.shared.trackOnboarding(.trialStarted, parameters: [
            "tier": "family",
            "status": "trial",
            "device_flow": "child"
        ])

        #if DEBUG
        print("[Onboarding] Starting no-card 14-day Family trial (all child-flow users)")
        #endif

        // The child will need to pair with a subscribed parent before trial ends
        // NotificationService can schedule reminders for this
    }

    /// Finish onboarding and drop into the child app — reached only after the tutorial.
    /// Notification permission is re-requested here as a catch-all; the permission gate
    /// already asks for it on grant, and iOS de-dupes the system prompt.
    private func enterChildDashboard() {
        Task { _ = await NotificationService.shared.requestAuthorization() }
        // Onboarding genuinely ends here now — after the permission gate and the
        // tutorial — rather than at the finish line, which is mid-flow.
        AppAnalytics.shared.trackOnboarding(.onboardingCompleted, parameters: ["flow": "child"])
        onboarding.onboardingComplete = true
        onComplete(.childDashboard)
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
