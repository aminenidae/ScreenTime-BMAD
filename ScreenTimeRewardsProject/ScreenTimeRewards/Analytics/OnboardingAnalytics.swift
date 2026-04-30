import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Analytics events for child onboarding flow tracking
enum OnboardingEvent: String {
    // MARK: - Screen Views
    case welcomeViewed = "onboarding_welcome_viewed"
    case solutionViewed = "onboarding_solution_viewed"
    case demoViewed = "onboarding_demo_viewed"
    case socialProofViewed = "onboarding_social_proof_viewed"
    case learningSetupViewed = "onboarding_learning_setup_viewed"
    case rewardSetupViewed = "onboarding_reward_setup_viewed"
    case paywallViewed = "onboarding_paywall_viewed"
    case completionViewed = "onboarding_completion_viewed"

    // MARK: - User Interactions
    case demoInteracted = "onboarding_demo_interacted"
    case learningAppsSelected = "onboarding_learning_apps_selected"
    case rewardAppsSelected = "onboarding_reward_apps_selected"
    case trialStarted = "onboarding_trial_started"
    case onboardingCompleted = "onboarding_completed"

    // MARK: - Drop-off Events
    case welcomeDropped = "onboarding_welcome_dropped"
    case solutionDropped = "onboarding_solution_dropped"
    case demoDropped = "onboarding_demo_dropped"
    case socialProofDropped = "onboarding_social_proof_dropped"
    case learningSetupDropped = "onboarding_learning_setup_dropped"
    case rewardSetupDropped = "onboarding_reward_setup_dropped"
    case paywallDropped = "onboarding_paywall_dropped"
}

/// Analytics service for onboarding flow
class OnboardingAnalytics {
    static let shared = OnboardingAnalytics()

    private init() {}

    /// Track an onboarding event. Routes through AppAnalytics so user properties
    /// (device_mode, subscription_tier, etc.) and DEBUG logging stay consistent
    /// with the rest of the app.
    func track(_ event: OnboardingEvent, parameters: [String: Any] = [:]) {
        let cleaned = parameters
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(event.rawValue, parameters: cleaned.isEmpty ? nil : cleaned)
        #endif

        #if DEBUG
        print("📊 [OnboardingAnalytics] \(event.rawValue) \(cleaned)")
        #endif
    }

    /// Track screen view with time spent
    func trackScreenView(_ event: OnboardingEvent, timeSpent: TimeInterval? = nil) {
        var params: [String: Any] = [:]
        if let timeSpent = timeSpent {
            params["time_spent_seconds"] = timeSpent
        }
        track(event, parameters: params)
    }

    /// Track user interaction
    func trackInteraction(_ event: OnboardingEvent, details: String? = nil) {
        var params: [String: Any] = [:]
        if let details = details {
            params["details"] = details
        }
        track(event, parameters: params)
    }

    /// Track demo interaction
    func trackDemoInteraction() {
        track(.demoInteracted, parameters: ["timestamp": Date().timeIntervalSince1970])
    }

    /// Track app selection. Also writes the count to AppAnalytics user properties
    /// so all subsequent events are segmented by selection size.
    func trackAppSelection(type: String, count: Int) {
        let event: OnboardingEvent = type == "learning" ? .learningAppsSelected : .rewardAppsSelected
        track(event, parameters: [
            "app_count": count,
            "app_type": type
        ])

        Task { @MainActor in
            if type == "learning" {
                AppAnalytics.shared.setUserProperty(.learningAppsCount, value: String(count))
            } else {
                AppAnalytics.shared.setUserProperty(.rewardAppsCount, value: String(count))
            }
        }
    }

    /// Track completion. Refreshes app-count user properties on the way out so
    /// post-onboarding events carry the final selection counts.
    func trackCompletion(learningApps: Int, rewardApps: Int, totalTime: TimeInterval) {
        track(.onboardingCompleted, parameters: [
            "learning_apps_count": learningApps,
            "reward_apps_count": rewardApps,
            "total_time_seconds": totalTime,
            "completion_date": Date().timeIntervalSince1970
        ])

        Task { @MainActor in
            AppAnalytics.shared.refreshAppCountUserProperties(learning: learningApps, reward: rewardApps)
        }
    }

    // MARK: - Private Helpers

    private func logEvent(_ event: OnboardingEvent, parameters: [String: Any]) {
        var paramString = ""
        if !parameters.isEmpty {
            paramString = " | Parameters: \(parameters)"
        }
        print("📊 [OnboardingAnalytics] \(event.rawValue)\(paramString)")
    }
}

// MARK: - SwiftUI View Extension

import SwiftUI

extension View {
    /// Track when a view appears
    func trackOnboardingView(_ event: OnboardingEvent) -> some View {
        self.onAppear {
            OnboardingAnalytics.shared.trackScreenView(event)
        }
    }
}
