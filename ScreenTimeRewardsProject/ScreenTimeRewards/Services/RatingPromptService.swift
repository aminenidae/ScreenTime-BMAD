//
//  RatingPromptService.swift
//  ScreenTimeRewards
//
//  Single-shot-per-trigger system rating prompt at parent-mode delight moments.
//  Rating VOLUME (not stars) is the primary App Store ranking lever for the
//  first 30 days — prompt early and at multiple delight points, let Apple's
//  3-per-365-day rate limit be the ultimate guardrail.
//
//  Gated behind active parent-authenticated context (either child-device
//  parent mode via PIN, or parent-device authenticated session) so the
//  prompt never surfaces to a child (kid-retaliation 1-stars + child-account
//  submit failures would both burn the slot).
//

import Foundation
import StoreKit
import UIKit

enum RatingPromptTrigger: String {
    case firstParentSuccess    // parent: dashboard shows earned minutes > 0
    case firstWeeklyWin        // parent: dashboard shows a 3+ day streak (behavior-pattern proof)
}

final class RatingPromptService {
    static let shared = RatingPromptService()
    private init() {}

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let legacyFiredFlagKey = "rating_prompt_fired_v1"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func firedFlagKey(for trigger: RatingPromptTrigger) -> String {
        "rating_prompt_fired_\(trigger.rawValue)_v1"
    }

    func hasFired(trigger: RatingPromptTrigger) -> Bool {
        sharedDefaults?.bool(forKey: firedFlagKey(for: trigger)) ?? false
    }

    /// Request a system review prompt if:
    /// - this trigger hasn't fired yet on this device (per-trigger App Group flag)
    /// - parent mode is actively authenticated (adult-only context)
    /// - main app is foregrounded
    /// Apple's own 3-per-365-day rate limit applies on top and is the ultimate cap.
    @MainActor
    func requestReviewIfEligible(trigger: RatingPromptTrigger) {
        guard let defaults = sharedDefaults else { return }

        migrateLegacyFlagIfNeeded(defaults: defaults)

        let flagKey = firedFlagKey(for: trigger)
        if defaults.bool(forKey: flagKey) {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: already_fired (trigger=\(trigger.rawValue))")
            AppAnalytics.shared.track(.reviewPromptSkipped, parameters: ["trigger": trigger.rawValue, "reason": "already_fired"])
            return
        }

        let session = SessionManager.shared
        guard session.isParentAuthenticated || session.isParentDeviceAuthenticated else {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: parent_not_authenticated (trigger=\(trigger.rawValue))")
            AppAnalytics.shared.track(.reviewPromptSkipped, parameters: ["trigger": trigger.rawValue, "reason": "parent_not_authenticated"])
            return
        }

        guard let scene = activeForegroundScene() else {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: no_active_scene (trigger=\(trigger.rawValue))")
            AppAnalytics.shared.track(.reviewPromptSkipped, parameters: ["trigger": trigger.rawValue, "reason": "no_active_scene"])
            return
        }

        if #available(iOS 16.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
        defaults.set(true, forKey: flagKey)
        print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_FIRED: trigger=\(trigger.rawValue)")
        AppAnalytics.shared.track(.reviewPromptRequested, parameters: ["trigger": trigger.rawValue])
    }

    /// One-time migration from the legacy single-flag scheme (pre-Option-B).
    /// Users who already saw a prompt under the old scheme are treated as having
    /// consumed `firstParentSuccess` so they aren't re-prompted for it.
    private func migrateLegacyFlagIfNeeded(defaults: UserDefaults) {
        guard defaults.bool(forKey: legacyFiredFlagKey) else { return }
        defaults.set(true, forKey: firedFlagKey(for: .firstParentSuccess))
        defaults.removeObject(forKey: legacyFiredFlagKey)
        print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_MIGRATED: legacy_flag → firstParentSuccess")
    }

    @MainActor
    private func activeForegroundScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }
}
