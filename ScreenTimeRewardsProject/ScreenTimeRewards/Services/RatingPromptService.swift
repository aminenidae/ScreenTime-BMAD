//
//  RatingPromptService.swift
//  ScreenTimeRewards
//
//  Single-shot system rating prompt at the first proven delight moment.
//  Rating VOLUME (not stars) is the primary App Store ranking lever for the
//  first 30 days — prompt early, once, at a moment of real payoff.
//
//  Gated behind active parent-mode authentication so the prompt never
//  surfaces to a child (kid-retaliation 1-stars + child-account submit
//  failures would both burn the single slot).
//

import Foundation
import StoreKit
import UIKit

enum RatingPromptTrigger: String {
    case firstParentSuccess    // parent: dashboard shows earned minutes > 0
}

final class RatingPromptService {
    static let shared = RatingPromptService()
    private init() {}

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let firedFlagKey = "rating_prompt_fired_v1"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Request a system review prompt if:
    /// - device hasn't shown one yet (App Group flag)
    /// - parent mode is actively authenticated (adult-only context)
    /// - main app is foregrounded
    /// Apple's own 3-per-365-day rate limit applies on top.
    @MainActor
    func requestReviewIfEligible(trigger: RatingPromptTrigger) {
        guard let defaults = sharedDefaults else { return }

        if defaults.bool(forKey: firedFlagKey) {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: already_fired (trigger=\(trigger.rawValue))")
            return
        }

        guard SessionManager.shared.isParentAuthenticated else {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: parent_not_authenticated (trigger=\(trigger.rawValue))")
            return
        }

        guard let scene = activeForegroundScene() else {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: no_active_scene (trigger=\(trigger.rawValue))")
            return
        }

        if #available(iOS 16.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
        defaults.set(true, forKey: firedFlagKey)
        print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_FIRED: trigger=\(trigger.rawValue)")
    }

    @MainActor
    private func activeForegroundScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }
}
