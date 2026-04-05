//
//  RevenueCatConfig.swift
//  ScreenTimeRewards
//
//  Configuration for RevenueCat subscription management
//

import Foundation

/// RevenueCat configuration constants
enum RevenueCatConfig {

    // MARK: - API Keys

    /// Production API key for App Store builds
    static let productionAPIKey = "appl_PczAwhOyMcvGQynjpbVCKSwAhAZ"

    /// Sandbox API key for development/testing
    static let sandboxAPIKey = "test_OHMkOgzEzvRFQukDbFFlzBTYbhR"

    /// Returns the appropriate API key.
    /// Note: RevenueCat uses the same `appl_` API key for both Sandbox and Production!
    /// The SDK automatically detects the environment based on the Apple receipt.
    /// Using a `test_` API key completely blocks Apple StoreKit fetching.
    static var apiKey: String {
        return productionAPIKey
    }

    /// Whether to enable RevenueCat logging.
    /// True in DEBUG (Xcode) and in TestFlight (sandbox receipt), false in production App Store builds.
    static var shouldEnableDebugLogging: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    // MARK: - Entitlements

    /// Entitlement identifiers configured in RevenueCat dashboard
    enum Entitlement {
        /// Solo tier entitlement (single device, no remote monitoring)
        static let premiumSolo = "Solo"

        /// Individual tier entitlement (1 child, 2 parents)
        static let premiumIndividual = "Individual"

        /// Family tier entitlement (5 children, 2 parents per child)
        static let premiumFamily = "Family"
    }

    // MARK: - Product IDs

    /// Product identifiers matching App Store Connect
    enum ProductID {
        // Solo Plan (single device, no remote monitoring)
        static let soloMonthly = "com.subscription.solo.monthly"
        static let soloAnnual = "com.subscription.solo.annual"

        // Individual Plan (1 child + 2 parents, remote monitoring)
        static let individualMonthly = "com.subscription.individual.monthly"
        static let individualAnnual = "com.subscription.individual.annual"

        // Family Plan (5 children + 2 parents each, remote monitoring)
        static let familyMonthly = "com.subscription.family.monthly"
        static let familyAnnual = "com.subscription.family.annual"

        /// All product IDs for reference
        static let all: [String] = [
            soloMonthly,
            soloAnnual,
            individualMonthly,
            individualAnnual,
            familyMonthly,
            familyAnnual
        ]
    }

    // MARK: - Trial Configuration

    /// Trial duration in days
    static let trialDurationDays = 14

    /// Grace period duration in days after subscription expires
    static let gracePeriodDays = 7

    // MARK: - Development Mode

    /// Whether to bypass subscription checks in development mode.
    /// When enabled, grants full Family tier access without requiring a real subscription.
    static var devModeEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
