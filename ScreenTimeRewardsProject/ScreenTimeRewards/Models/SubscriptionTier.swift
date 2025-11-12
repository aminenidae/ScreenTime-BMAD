import Foundation

enum SubscriptionTier: String, Codable, CaseIterable {
    case free = "free"
    case individual = "individual"
    case family = "family"

    var displayName: String {
        switch self {
        case .free: return "Free Trial"
        case .individual: return "Individual"
        case .family: return "Family"
        }
    }

    var productID: String? {
        switch self {
        case .free: return nil
        case .individual: return "com.screentimerewards.individual.monthly"
        case .family: return "com.screentimerewards.family.monthly"
        }
    }

    var childDeviceLimit: Int {
        switch self {
        case .free: return 5
        case .individual: return 1
        case .family: return 5
        }
    }

    var features: [String] {
        switch self {
        case .free:
            return [
                "30-day free trial",
                "Full access to all features",
                "Up to 5 child devices",
                "Unlimited challenges"
            ]
        case .individual:
            return [
                "1 child device",
                "Unlimited challenges",
                "Learning & reward tracking",
                "Basic analytics"
            ]
        case .family:
            return [
                "Up to 5 child devices",
                "Unlimited challenges",
                "Advanced family analytics",
                "Multi-child dashboard",
                "Priority support"
            ]
        }
    }

    var monthlyPrice: Decimal {
        switch self {
        case .free: return 0.00
        case .individual: return 7.99
        case .family: return 12.99
        }
    }
}

enum SubscriptionStatus: String, Codable {
    case trial = "trial"
    case active = "active"
    case grace = "grace"
    case expired = "expired"
    case cancelled = "cancelled"

    var isAccessGranted: Bool {
        switch self {
        case .trial, .active, .grace:
            return true
        case .expired, .cancelled:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .trial: return "Free Trial Active"
        case .active: return "Active"
        case .grace: return "Grace Period"
        case .expired: return "Expired"
        case .cancelled: return "Cancelled"
        }
    }
}
