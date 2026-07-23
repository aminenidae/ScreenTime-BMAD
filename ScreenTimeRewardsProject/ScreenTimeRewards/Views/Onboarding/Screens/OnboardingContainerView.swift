import SwiftUI

/// The child-flow tail of onboarding. After the shared front (merged welcome → value
/// slides → device question), the child path enters here directly at the finish line:
/// the no-card 14-day trial auto-starts, then setup is optional — "Personalize" launches
/// the config in a full-screen cover; "Explore" drops into the app.
struct OnboardingContainerView: View {
    @StateObject private var onboarding = OnboardingStateManager()
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    /// Presents the optional config (tutorial) on demand from the finish line.
    @State private var showConfig = false

    let onComplete: (OnboardingDestination) -> Void

    enum OnboardingDestination {
        case childDashboard
        case parentDashboard
    }

    var body: some View {
        Screen7_ActivationView(
            onStartTrial: { startFamilyTrial() },
            onPersonalize: {
                AppAnalytics.shared.trackOnboarding(.configStarted, parameters: ["source": "finish_line"])
                showConfig = true
            },
            onExplore: { enterChildDashboard() }
        )
        .environmentObject(onboarding)
        .environmentObject(subscriptionManager)
        // Optional config, launched on demand from the finish line ("Personalize").
        // The app picker inside requests Screen Time permission in-context.
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

    /// Finish onboarding and drop into the child app. Notification permission is asked
    /// here — at app entry — now that the dedicated permission screen is gone (it used
    /// to piggyback the Screen Time ask). Non-blocking; iOS de-dupes the system prompt.
    private func enterChildDashboard() {
        Task { _ = await NotificationService.shared.requestAuthorization() }
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
