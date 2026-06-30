//
//  AppAnalytics.swift
//  ScreenTimeRewards
//
//  Single source of truth for Firebase Analytics. All custom events flow through
//  here so naming, parameter conventions, and user-property segmentation stay
//  consistent across paywalls, subscription lifecycle, pairing, rewards, and errors.
//

import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

// MARK: - Event taxonomy

/// All custom analytics events the app emits. Names are snake_case and stable —
/// renaming breaks Firebase dashboards. Add new cases; do not rename existing ones.
enum AnalyticsEvent: String {
    // Onboarding flow (screen views + interactions)
    // Front-of-funnel: the welcome + device-selection screens that precede the
    // child/parent flows. Without these, installs that drop before choosing a
    // device type are invisible.
    case onboardingWelcomeViewed        = "onboarding_welcome_viewed"
    case onboardingWelcomeCtaTapped     = "onboarding_welcome_cta_tapped"
    case onboardingDeviceSelectionViewed = "onboarding_device_selection_viewed"
    case onboardingDeviceTypeSelected   = "onboarding_device_type_selected"
    case onboardingScreenViewed     = "onboarding_screen_viewed"
    case onboardingCtaTapped        = "onboarding_cta_tapped"
    case onboardingPathSelected     = "onboarding_path_selected"
    case onboardingSkipTapped       = "onboarding_skip_tapped"
    case onboardingSkipConfirmed    = "onboarding_skip_confirmed"
    case onboardingTutorialStep     = "onboarding_tutorial_step"
    case onboardingTutorialDropped  = "onboarding_tutorial_dropped"
    case tutorialCompleted          = "tutorial_completed"
    case onboardingCompleted        = "onboarding_completed"
    case onboardingAttemptStarted   = "onboarding_attempt_started"

    // Authorization (Screen 4)
    case authorizationRequested     = "authorization_requested"
    case authorizationGranted       = "authorization_granted"
    case authorizationDenied        = "authorization_denied"

    // Paywall (outside onboarding)
    case paywallViewed              = "paywall_viewed"
    case paywallPlanSelected        = "paywall_plan_selected"
    case paywallPurchaseStarted     = "paywall_purchase_started"
    case paywallPurchaseCompleted   = "paywall_purchase_completed"
    case paywallPurchaseFailed      = "paywall_purchase_failed"
    case paywallRestoreTapped       = "paywall_restore_tapped"
    case paywallRestoreSucceeded    = "paywall_restore_succeeded"
    case paywallRestoreNoPurchases  = "paywall_restore_no_purchases"
    case paywallDismissed           = "paywall_dismissed"
    case paywallUserCancelled       = "paywall_user_cancelled"
    case paywallPlanSwitched        = "paywall_plan_switched"

    // Subscription lifecycle
    case subscriptionStarted        = "subscription_started"
    case subscriptionRenewed        = "subscription_renewed"
    case subscriptionTierChanged    = "subscription_tier_changed"
    case subscriptionEnteredGrace   = "subscription_entered_grace"
    case subscriptionExpired        = "subscription_expired"
    case subscriptionCancelled      = "subscription_cancelled"

    // Pairing
    case pairingCodeGenerated       = "pairing_code_generated"
    case pairingCodeEntered         = "pairing_code_entered"
    case pairingCompleted           = "pairing_completed"
    case pairingFailed              = "pairing_failed"
    case pairingUnpaired            = "pairing_unpaired"

    // App Store review prompt — Apple never reports whether the system dialog
    // actually appeared or what the user did with it, so this only covers the ask.
    case reviewPromptRequested      = "review_prompt_requested"
    case reviewPromptSkipped        = "review_prompt_skipped"

    // Reward redemption
    case rewardUnlocked             = "reward_unlocked"
    case rewardAppBlockedAgain      = "reward_app_blocked_again"
    case learningMilestone          = "learning_milestone"

    // Daily active
    case dailyActive                = "daily_active"

    // Errors
    case errorFamilyControlsDenied  = "error_familycontrols_denied"
    case errorCloudKitSyncFailed    = "error_cloudkit_sync_failed"
    case errorStoreKitFailed        = "error_storekit_failed"
    case errorGeneric               = "error_generic"
}

// MARK: - User property keys

/// Keys for Firebase user properties — persistent attributes Firebase attaches to
/// every event from this install. Set on launch and whenever the underlying state
/// changes (subscription tier, device mode, pairing).
enum AnalyticsUserProperty: String {
    case deviceMode          = "device_mode"           // parent | child | unset
    case subscriptionTier    = "subscription_tier"     // trial | solo | individual | family
    case subscriptionStatus  = "subscription_status"   // trial | active | grace | expired | cancelled
    case pairedStatus        = "paired_status"         // unpaired | paired_parent | paired_child
    case appVersion          = "app_version"
    case cohortInstallWeek   = "cohort_install_week"   // ISO yyyy-Www
    case learningAppsCount   = "learning_apps_count"   // numeric, attached as user prop for segmentation
    case rewardAppsCount     = "reward_apps_count"
}

// MARK: - Service

@MainActor
final class AppAnalytics {
    static let shared = AppAnalytics()

    private let cohortKey = "appAnalytics.cohortInstallWeek"
    private let lastDailyActiveKey = "appAnalytics.lastDailyActiveDate"
    private let learningMilestoneKey = "appAnalytics.learningMilestonesFiredToday"
    private let learningMilestoneDateKey = "appAnalytics.learningMilestonesFiredDate"

    private init() {}

    // MARK: - Public API

    /// Track a custom event. Pass plain Swift values in `parameters`; Firebase
    /// accepts String, Int, Double, Bool. Nil values are stripped.
    func track(_ event: AnalyticsEvent, parameters: [String: Any] = [:]) {
        let cleaned = sanitize(parameters)

        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(event.rawValue, parameters: cleaned.isEmpty ? nil : cleaned)
        #endif

        #if DEBUG
        print("📊 [AppAnalytics] \(event.rawValue) \(cleaned)")
        #endif
    }

    /// Report a screen view using Firebase's native screen_view event, with a stable
    /// friendly name. Without this, Firebase's automatic tracking logs the raw
    /// SwiftUI/UIHostingController class name instead of a readable screen name.
    func trackScreenView(_ screenName: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenName
        ])
        #endif

        #if DEBUG
        print("📊 [AppAnalytics] screen_view \(screenName)")
        #endif
    }

    /// Set a persistent user property. Firebase attaches the latest value to every
    /// future event from this install. Pass `nil` to clear.
    func setUserProperty(_ key: AnalyticsUserProperty, value: String?) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserProperty(value, forName: key.rawValue)
        #endif

        #if DEBUG
        print("📊 [AppAnalytics] user_property \(key.rawValue) = \(value ?? "<nil>")")
        #endif
    }

    /// Set the user identifier — used to correlate events across devices for the
    /// same user. Safe to pass the device-scoped UUID we already generate.
    func setUserId(_ id: String?) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserID(id)
        #endif
    }

    /// Convenience for error events — keeps category/code naming consistent.
    func trackError(_ event: AnalyticsEvent, code: String?, context: String? = nil, isUserCancelled: Bool = false) {
        var params: [String: Any] = [:]
        if let code { params["error_code"] = code }
        if let context { params["context"] = context }
        params["is_user_cancelled"] = isUserCancelled
        track(event, parameters: params)
    }

    // MARK: - Bootstrap (called from AppDelegate after FirebaseApp.configure)

    /// Initial user-property bootstrap. Run once after Firebase is configured.
    /// Reads current state from DeviceModeManager + SubscriptionManager + DevicePairingService.
    func bootstrapUserProperties() {
        // Stable cohort: ISO yyyy-Www, captured once on first launch.
        let cohort: String
        if let existing = UserDefaults.standard.string(forKey: cohortKey) {
            cohort = existing
        } else {
            cohort = Self.isoWeek(from: Date())
            UserDefaults.standard.set(cohort, forKey: cohortKey)
        }
        setUserProperty(.cohortInstallWeek, value: cohort)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        setUserProperty(.appVersion, value: version)

        refreshDeviceModeUserProperty()
        refreshSubscriptionUserProperties()
        refreshPairedStatusUserProperty()

        // Stable cross-device user id — DeviceModeManager already mints a UUID.
        setUserId(DeviceModeManager.shared.deviceID)
    }

    /// Re-read DeviceModeManager.currentMode and update the device_mode property.
    func refreshDeviceModeUserProperty() {
        let mode: String
        switch DeviceModeManager.shared.currentMode {
        case .parentDevice: mode = "parent"
        case .childDevice:  mode = "child"
        case .none:         mode = "unset"
        }
        setUserProperty(.deviceMode, value: mode)
    }

    /// Re-read SubscriptionManager and update tier + status user properties.
    func refreshSubscriptionUserProperties() {
        setUserProperty(.subscriptionTier, value: SubscriptionManager.shared.currentTier.rawValue)
        setUserProperty(.subscriptionStatus, value: SubscriptionManager.shared.currentStatus.rawValue)
    }

    /// Re-read DevicePairingService and update paired_status. Call after pairing
    /// completes / unpairs.
    func refreshPairedStatusUserProperty() {
        let mode = DeviceModeManager.shared.currentMode
        let value: String
        if mode == .parentDevice {
            // Parent has no synchronous paired-children list — Firebase family id
            // is the cheapest proxy (created on first successful pairing).
            value = FirebaseValidationService.shared.currentFamilyId == nil ? "unpaired" : "paired_parent"
        } else if mode == .childDevice {
            value = DevicePairingService.shared.isPaired() ? "paired_child" : "unpaired"
        } else {
            value = "unpaired"
        }
        setUserProperty(.pairedStatus, value: value)
    }

    /// Update the app-count user properties. Called when configuration changes
    /// (onboarding completion, settings selection updates).
    func refreshAppCountUserProperties(learning: Int, reward: Int) {
        setUserProperty(.learningAppsCount, value: String(learning))
        setUserProperty(.rewardAppsCount, value: String(reward))
    }

    // MARK: - Daily-active gate

    /// Fire `daily_active` at most once per calendar day. Idempotent — safe to call
    /// from every scenePhase=.active transition.
    func trackDailyActiveIfNeeded(
        learningMinutesToday: Int,
        rewardMinutesToday: Int,
        learningAppsCount: Int,
        rewardAppsCount: Int
    ) {
        let today = Self.dayString(Date())
        let last = UserDefaults.standard.string(forKey: lastDailyActiveKey)
        guard last != today else { return }

        let mode = DeviceModeManager.shared.currentMode
        let modeStr: String
        switch mode {
        case .parentDevice: modeStr = "parent"
        case .childDevice:  modeStr = "child"
        case .none:         modeStr = "unset"
        }

        track(.dailyActive, parameters: [
            "device_mode": modeStr,
            "learning_minutes_today": learningMinutesToday,
            "reward_minutes_today": rewardMinutesToday,
            "learning_apps_count": learningAppsCount,
            "reward_apps_count": rewardAppsCount,
            "subscription_tier": SubscriptionManager.shared.currentTier.rawValue,
            "subscription_status": SubscriptionManager.shared.currentStatus.rawValue
        ])

        UserDefaults.standard.set(today, forKey: lastDailyActiveKey)
    }

    // MARK: - Learning milestone (one-shot per day per minute-bucket)

    /// Fire `learning_milestone` the first time learning crosses 10/30/60 minutes
    /// in a day. Resets on day boundary.
    func trackLearningMilestoneIfCrossed(totalMinutes: Int) {
        let buckets = [10, 30, 60]
        let today = Self.dayString(Date())
        let storedDate = UserDefaults.standard.string(forKey: learningMilestoneDateKey)
        var fired: [Int]
        if storedDate != today {
            fired = []
            UserDefaults.standard.set(today, forKey: learningMilestoneDateKey)
            UserDefaults.standard.set(fired, forKey: learningMilestoneKey)
        } else {
            fired = (UserDefaults.standard.array(forKey: learningMilestoneKey) as? [Int]) ?? []
        }

        for bucket in buckets where totalMinutes >= bucket && !fired.contains(bucket) {
            track(.learningMilestone, parameters: ["minutes": bucket])
            fired.append(bucket)
        }
        UserDefaults.standard.set(fired, forKey: learningMilestoneKey)
    }

    // MARK: - Helpers

    private func sanitize(_ params: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in params {
            // Firebase rejects nil and unsupported types — coerce / drop.
            if v is NSNull { continue }
            if let s = v as? String { out[k] = s }
            else if let i = v as? Int { out[k] = i }
            else if let d = v as? Double { out[k] = d }
            else if let b = v as? Bool { out[k] = b }
            else if let date = v as? Date { out[k] = date.timeIntervalSince1970 }
            else { out[k] = String(describing: v) }
        }
        return out
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static func isoWeek(from date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0
        let week = comps.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }
}
