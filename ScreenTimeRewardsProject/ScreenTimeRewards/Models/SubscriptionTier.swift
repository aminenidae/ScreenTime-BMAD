//
//  SubscriptionTier.swift
//  ScreenTimeRewards
//

import Foundation

enum SubscriptionTier: String, Codable, CaseIterable {
    case trial = "trial"
    case solo = "solo"
    case individual = "individual"
    case family = "family"

    var displayName: String {
        switch self {
        case .trial: return String(localized: "Free Trial")
        case .solo: return String(localized: "Solo")
        case .individual: return String(localized: "Individual")
        case .family: return String(localized: "Family")
        }
    }

    /// Whether this tier requires a parent device (remote monitoring)
    var requiresParentDevice: Bool {
        switch self {
        case .trial, .solo:
            return false
        case .individual, .family:
            return true
        }
    }

    /// Whether subscription lives on parent device
    var subscriptionOnParentDevice: Bool {
        switch self {
        case .trial, .solo:
            return false
        case .individual, .family:
            return true
        }
    }

    // MARK: - Product IDs (matching App Store Connect)

    var monthlyProductID: String? {
        switch self {
        case .trial: return nil
        case .solo: return RevenueCatConfig.ProductID.soloMonthly
        case .individual: return RevenueCatConfig.ProductID.individualMonthly
        case .family: return RevenueCatConfig.ProductID.familyMonthly
        }
    }

    var annualProductID: String? {
        switch self {
        case .trial: return nil
        case .solo: return RevenueCatConfig.ProductID.soloAnnual
        case .individual: return RevenueCatConfig.ProductID.individualAnnual
        case .family: return RevenueCatConfig.ProductID.familyAnnual
        }
    }

    // MARK: - Device Limits

    /// Maximum number of child devices allowed for this tier
    var childDeviceLimit: Int {
        switch self {
        case .trial: return 5       // Full access during trial
        case .solo: return 1        // 1 child device (same device as parent)
        case .individual: return 1  // 1 child device
        case .family: return 5      // Up to 5 child devices
        }
    }

    /// Maximum number of parent devices per child
    var parentDeviceLimitPerChild: Int {
        switch self {
        case .trial: return 2
        case .solo: return 0        // No parent devices (solo is single-device)
        case .individual: return 2
        case .family: return 2
        }
    }

    // MARK: - Entitlements

    /// RevenueCat entitlement identifier for this tier
    var entitlementID: String? {
        switch self {
        case .trial: return nil
        case .solo: return RevenueCatConfig.Entitlement.premiumSolo
        case .individual: return RevenueCatConfig.Entitlement.premiumIndividual
        case .family: return RevenueCatConfig.Entitlement.premiumFamily
        }
    }

    // MARK: - Features

    var features: [String] {
        switch self {
        case .trial:
            return [
                String(localized: "14-day free trial"),
                String(localized: "Full access to all features"),
                String(localized: "Up to 5 child devices"),
                String(localized: "2 parent devices per child"),
                String(localized: "Unlimited challenges")
            ]
        case .solo:
            return [
                String(localized: "Single device setup"),
                String(localized: "Monitor on same device"),
                String(localized: "Unlimited challenges"),
                String(localized: "Learning & reward tracking"),
                String(localized: "Basic analytics")
            ]
        case .individual:
            return [
                String(localized: "1 child device"),
                String(localized: "2 parent devices"),
                String(localized: "Remote monitoring"),
                String(localized: "Unlimited challenges"),
                String(localized: "Learning & reward tracking")
            ]
        case .family:
            return [
                String(localized: "Up to 5 child devices"),
                String(localized: "2 parent devices per child"),
                String(localized: "Remote monitoring"),
                String(localized: "Unlimited challenges"),
                String(localized: "Multi-child dashboard"),
                String(localized: "Priority support")
            ]
        }
    }

    // MARK: - Legacy Support

    /// For backward compatibility with code expecting `productID`
    var productID: String? {
        return monthlyProductID
    }
}

// MARK: - Subscription Status

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
        case .trial: return String(localized: "Free Trial Active")
        case .active: return String(localized: "Active")
        case .grace: return String(localized: "Grace Period")
        case .expired: return String(localized: "Expired")
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}
