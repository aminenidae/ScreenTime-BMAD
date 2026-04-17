//
//  RatingPromptService.swift
//  ScreenTimeRewards
//
//  Single-shot system rating prompt at the first proven delight moment.
//  Rating VOLUME (not stars) is the primary App Store ranking lever for the
//  first 30 days — prompt early, once, at a moment of real payoff.
//

import Foundation
import StoreKit
import UIKit

enum RatingPromptTrigger: String {
    case firstUnlock           // child: learning-goal complete → shield drops
    case firstParentSuccess    // parent: dashboard shows earned minutes > 0
}

final class RatingPromptService {
    static let shared = RatingPromptService()
    private init() {}

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let firedFlagKey = "rating_prompt_fired_v1"
    private let pendingFlagKey = "rating_prompt_pending_v1"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Request a system review prompt if this device hasn't shown one yet.
    /// Apple's own 3-per-365-day rate limiting applies on top of our flag.
    func requestReviewIfEligible(trigger: RatingPromptTrigger) {
        guard let defaults = sharedDefaults else { return }

        if defaults.bool(forKey: firedFlagKey) {
            print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: already_fired (trigger=\(trigger.rawValue))")
            return
        }

        Task { @MainActor in
            if let scene = activeForegroundScene() {
                fire(in: scene, trigger: trigger, defaults: defaults)
            } else {
                // Triggered from a background context (e.g., extension-driven shield drop).
                // Queue for next foreground — drained by drainPendingIfNeeded().
                defaults.set(true, forKey: pendingFlagKey)
                print("[RatingPromptService] DEBUG_LOG_RATING_PROMPT_SKIPPED: no_active_scene (trigger=\(trigger.rawValue)) — queued for next foreground")
            }
        }
    }

    /// Call on every transition to scenePhase == .active.
    @MainActor
    func drainPendingIfNeeded() {
        guard let defaults = sharedDefaults,
              defaults.bool(forKey: pendingFlagKey),
              !defaults.bool(forKey: firedFlagKey),
              let scene = activeForegroundScene() else {
            return
        }
        fire(in: scene, trigger: .firstUnlock, defaults: defaults)
        defaults.removeObject(forKey: pendingFlagKey)
    }

    @MainActor
    private func fire(in scene: UIWindowScene, trigger: RatingPromptTrigger, defaults: UserDefaults) {
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
