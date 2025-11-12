import Foundation
import CoreData

extension UserSubscription {
    var tierEnum: SubscriptionTier {
        get {
            guard let tierString = subscriptionTier else { return .free }
            return SubscriptionTier(rawValue: tierString) ?? .free
        }
        set {
            subscriptionTier = newValue.rawValue
        }
    }

    var statusEnum: SubscriptionStatus {
        get {
            guard let statusString = subscriptionStatus else { return .trial }
            return SubscriptionStatus(rawValue: statusString) ?? .trial
        }
        set {
            subscriptionStatus = newValue.rawValue
        }
    }

    var isTrialActive: Bool {
        guard let trialEnd = trialEndDate else { return false }
        return Date() < trialEnd && statusEnum == .trial
    }

    var isInGracePeriod: Bool {
        guard let graceEnd = graceEndDate else { return false }
        return Date() < graceEnd && statusEnum == .grace
    }

    var hasAccess: Bool {
        return statusEnum.isAccessGranted
    }

    var daysRemainingInTrial: Int? {
        guard isTrialActive, let trialEnd = trialEndDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day
        return max(0, days ?? 0)
    }

    var daysRemainingInGrace: Int? {
        guard isInGracePeriod, let graceEnd = graceEndDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: graceEnd).day
        return max(0, days ?? 0)
    }
}
