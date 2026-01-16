//
//  SubscriptionManager.swift
//  ScreenTimeRewards
//
//  Manages subscriptions using RevenueCat SDK
//

import Foundation
import SwiftUI
import Combine
import RevenueCat
import CoreData
import Security
import StoreKit

@MainActor
final class SubscriptionManager: NSObject, ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Published State

    /// Available offerings from RevenueCat (contains packages with dynamic pricing)
    @Published private(set) var offerings: Offerings?

    /// The current offering (usually "default")
    @Published private(set) var currentOffering: Offering?

    /// RevenueCat customer info with entitlement status
    @Published private(set) var customerInfo: CustomerInfo?

    /// Current subscription tier
    @Published private(set) var currentTier: SubscriptionTier = .trial

    /// Current subscription status
    @Published private(set) var currentStatus: SubscriptionStatus = .trial

    /// Local CoreData subscription record
    @Published private(set) var subscription: UserSubscription?

    /// Whether RevenueCat has been configured
    @Published private(set) var isConfigured: Bool = false

    /// StoreKit products fallback (when RevenueCat offerings unavailable)
    @Published private(set) var storeKitProducts: [String: Product] = [:]

    // MARK: - Constants

    private let trialDuration: TimeInterval = TimeInterval(RevenueCatConfig.trialDurationDays * 24 * 60 * 60)
    private let gracePeriodDuration: TimeInterval = TimeInterval(RevenueCatConfig.gracePeriodDays * 24 * 60 * 60)

    // Keychain constants for trial protection (persists across reinstall)
    private let keychainService = "com.screentimerewards"
    private let keychainTrialStartKey = "trialStartDate"

    // MARK: - Dependencies

    private let persistenceController = PersistenceController.shared
    private let deviceManager = DeviceModeManager.shared

    // MARK: - Initialization

    private override init() {
        super.init()
        configureRevenueCat()
    }

    private func configureRevenueCat() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)

        // Use device ID for cross-device identification
        Task {
            do {
                let (customerInfo, _) = try await Purchases.shared.logIn(deviceManager.deviceID)
                self.customerInfo = customerInfo
                self.isConfigured = true
                await loadSubscriptionStatus()

                #if DEBUG
                print("[SubscriptionManager] RevenueCat configured with user: \(deviceManager.deviceID)")
                #endif
            } catch {
                print("[SubscriptionManager] RevenueCat login error: \(error)")
                // Continue without login - will use anonymous ID
                self.isConfigured = true
                await loadSubscriptionStatus()
            }
        }

        // Set delegate for customer info updates
        Purchases.shared.delegate = self
    }

    // MARK: - Offerings (Dynamic Pricing)

    /// Load available offerings from RevenueCat
    func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
            currentOffering = offerings?.current

            #if DEBUG
            print("[SubscriptionManager] Loaded offerings: \(offerings?.all.keys.joined(separator: ", ") ?? "none")")
            if let current = currentOffering {
                print("[SubscriptionManager] Current offering: \(current.identifier)")
                for package in current.availablePackages {
                    print("[SubscriptionManager]   - \(package.identifier): \(package.localizedPriceString)")
                }
            }
            #endif
        } catch {
            print("[SubscriptionManager] Failed to load offerings: \(error)")
        }

        // Fallback to StoreKit if no offerings available
        if currentOffering == nil || currentOffering?.availablePackages.isEmpty == true {
            await loadStoreKitProductsFallback()
        }
    }

    /// Fallback: Load products directly from StoreKit when RevenueCat offerings unavailable
    private func loadStoreKitProductsFallback() async {
        let productIDs: Set<String> = [
            RevenueCatConfig.ProductID.soloMonthly,
            RevenueCatConfig.ProductID.soloAnnual,
            RevenueCatConfig.ProductID.individualMonthly,
            RevenueCatConfig.ProductID.individualAnnual,
            RevenueCatConfig.ProductID.familyMonthly,
            RevenueCatConfig.ProductID.familyAnnual
        ]

        do {
            let products = try await Product.products(for: productIDs)
            for product in products {
                storeKitProducts[product.id] = product
            }
            #if DEBUG
            print("[SubscriptionManager] Loaded \(products.count) StoreKit products as fallback")
            for product in products {
                print("[SubscriptionManager]   - \(product.id): \(product.displayPrice)")
            }
            #endif
        } catch {
            print("[SubscriptionManager] StoreKit fallback failed: \(error)")
        }
    }

    // MARK: - Subscription Status

    /// Load subscription status from RevenueCat and local storage
    func loadSubscriptionStatus() async {
        // 1. Get RevenueCat customer info
        do {
            customerInfo = try await Purchases.shared.customerInfo()
            updateTierFromCustomerInfo()
        } catch {
            print("[SubscriptionManager] Failed to get customer info: \(error)")
        }

        // 2. Load/create local CoreData subscription
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<UserSubscription>(entityName: "UserSubscription")
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "userDeviceID == %@", deviceManager.deviceID)

        do {
            let results = try context.fetch(fetchRequest)
            if let existing = results.first {
                subscription = existing
                syncLocalWithRevenueCat()
            } else {
                await createTrialSubscription()
            }
        } catch {
            print("[SubscriptionManager] Failed to load subscription: \(error)")
        }

        // 3. Load offerings for dynamic pricing
        await loadOfferings()
    }

    /// Update tier and status based on RevenueCat customer info
    private func updateTierFromCustomerInfo() {
        guard let info = customerInfo else {
            // No RevenueCat info - check local trial
            if let sub = subscription, sub.isTrialActive {
                currentTier = .trial
                currentStatus = .trial
            } else if let sub = subscription, sub.isInGracePeriod {
                currentTier = .trial
                currentStatus = .grace
            } else {
                currentTier = .trial
                currentStatus = .expired
            }
            return
        }

        // Check Family entitlement first (highest tier)
        if let familyEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumFamily],
           familyEntitlement.isActive {
            currentTier = .family
            currentStatus = mapEntitlementToStatus(familyEntitlement)
            return
        }

        // Then check Individual
        if let individualEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumIndividual],
           individualEntitlement.isActive {
            currentTier = .individual
            currentStatus = mapEntitlementToStatus(individualEntitlement)
            return
        }

        // Then check Solo
        if let soloEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumSolo],
           soloEntitlement.isActive {
            currentTier = .solo
            currentStatus = mapEntitlementToStatus(soloEntitlement)
            return
        }

        // No active entitlements - check if in local trial
        if let sub = subscription, sub.isTrialActive {
            currentTier = .trial
            currentStatus = .trial
        } else if let sub = subscription, sub.isInGracePeriod {
            currentTier = .trial
            currentStatus = .grace
        } else {
            currentTier = .trial
            currentStatus = .expired
        }
    }

    private func mapEntitlementToStatus(_ entitlement: EntitlementInfo) -> SubscriptionStatus {
        if entitlement.periodType == .trial {
            return .trial
        } else if entitlement.isActive {
            if entitlement.willRenew {
                return .active
            } else {
                // Active but won't renew - still has access until expiry
                return .active
            }
        } else if entitlement.billingIssueDetectedAt != nil {
            return .grace
        } else {
            return .expired
        }
    }

    /// Sync local CoreData with RevenueCat status
    private func syncLocalWithRevenueCat() {
        guard let subscription else { return }

        if let info = customerInfo {
            // If RevenueCat shows active subscription, update local record
            if let familyEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumFamily],
               familyEntitlement.isActive {
                subscription.tierEnum = .family
                subscription.statusEnum = mapEntitlementToStatus(familyEntitlement)
                subscription.expiryDate = familyEntitlement.expirationDate
            } else if let individualEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumIndividual],
                      individualEntitlement.isActive {
                subscription.tierEnum = .individual
                subscription.statusEnum = mapEntitlementToStatus(individualEntitlement)
                subscription.expiryDate = individualEntitlement.expirationDate
            } else if let soloEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumSolo],
                      soloEntitlement.isActive {
                subscription.tierEnum = .solo
                subscription.statusEnum = mapEntitlementToStatus(soloEntitlement)
                subscription.expiryDate = soloEntitlement.expirationDate
            }

            try? subscription.managedObjectContext?.save()
        }

        updateTierFromCustomerInfo()
    }

    /// Create a new trial subscription for first-time users
    /// Uses Keychain to persist trial start date across reinstalls (abuse prevention)
    private func createTrialSubscription() async {
        let context = persistenceController.container.viewContext

        let newSubscription = UserSubscription(context: context)
        newSubscription.subscriptionID = UUID().uuidString
        newSubscription.userDeviceID = deviceManager.deviceID
        newSubscription.tierEnum = .trial

        // Check Keychain for existing trial (reinstall protection)
        if let existingTrialStart = loadTrialStartFromKeychain() {
            // User reinstalled - restore original trial dates
            let trialEnd = existingTrialStart.addingTimeInterval(trialDuration)
            let graceEnd = trialEnd.addingTimeInterval(gracePeriodDuration)

            newSubscription.trialStartDate = existingTrialStart
            newSubscription.trialEndDate = trialEnd
            newSubscription.graceEndDate = graceEnd

            // Check if trial/grace already expired
            let now = Date()
            if now >= graceEnd {
                newSubscription.statusEnum = .expired
                #if DEBUG
                print("[SubscriptionManager] Restored EXPIRED trial from Keychain (started: \(existingTrialStart))")
                #endif
            } else if now >= trialEnd {
                newSubscription.statusEnum = .grace
                #if DEBUG
                print("[SubscriptionManager] Restored GRACE PERIOD trial from Keychain (started: \(existingTrialStart))")
                #endif
            } else {
                newSubscription.statusEnum = .trial
                #if DEBUG
                print("[SubscriptionManager] Restored ACTIVE trial from Keychain (started: \(existingTrialStart))")
                #endif
            }
        } else {
            // First install - create new trial and save to Keychain
            let now = Date()
            newSubscription.trialStartDate = now
            newSubscription.trialEndDate = now.addingTimeInterval(trialDuration)
            newSubscription.graceEndDate = now.addingTimeInterval(trialDuration + gracePeriodDuration)
            newSubscription.statusEnum = .trial

            // Save to Keychain for reinstall protection
            saveTrialStartToKeychain(now)

            #if DEBUG
            print("[SubscriptionManager] Created NEW \(RevenueCatConfig.trialDurationDays)-day trial subscription")
            #endif
        }

        do {
            try context.save()
            subscription = newSubscription
            updateTierFromCustomerInfo()

            // Schedule trial expiration reminders (only if trial is still active)
            if newSubscription.statusEnum == .trial, let trialEnd = newSubscription.trialEndDate {
                NotificationService.shared.scheduleSubscriptionReminders(
                    expirationDate: trialEnd,
                    isTrial: true,
                    remindDays: [7, 3, 0]
                )
            }
        } catch {
            print("[SubscriptionManager] Failed to create trial subscription: \(error)")
        }
    }

    // MARK: - Purchasing

    /// Purchase a package from RevenueCat
    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        customerInfo = result.customerInfo
        updateTierFromCustomerInfo()
        await updateLocalSubscription(from: result.customerInfo)

        #if DEBUG
        print("[SubscriptionManager] Purchase successful: \(package.storeProduct.productIdentifier)")
        #endif
    }

    /// Restore purchases from the App Store
    func restorePurchases() async throws {
        customerInfo = try await Purchases.shared.restorePurchases()
        updateTierFromCustomerInfo()
        await updateLocalSubscription(from: customerInfo)

        #if DEBUG
        print("[SubscriptionManager] Purchases restored")
        #endif
    }

    /// Update local CoreData subscription from RevenueCat customer info
    private func updateLocalSubscription(from info: CustomerInfo?) async {
        guard let info, let subscription else { return }

        let context = persistenceController.container.viewContext

        // Find the active entitlement
        if let familyEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumFamily],
           familyEntitlement.isActive {
            subscription.tierEnum = .family
            subscription.statusEnum = mapEntitlementToStatus(familyEntitlement)
            subscription.purchaseDate = familyEntitlement.originalPurchaseDate
            subscription.expiryDate = familyEntitlement.expirationDate
            if let expiry = familyEntitlement.expirationDate {
                subscription.graceEndDate = expiry.addingTimeInterval(gracePeriodDuration)
            }
        } else if let individualEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumIndividual],
                  individualEntitlement.isActive {
            subscription.tierEnum = .individual
            subscription.statusEnum = mapEntitlementToStatus(individualEntitlement)
            subscription.purchaseDate = individualEntitlement.originalPurchaseDate
            subscription.expiryDate = individualEntitlement.expirationDate
            if let expiry = individualEntitlement.expirationDate {
                subscription.graceEndDate = expiry.addingTimeInterval(gracePeriodDuration)
            }
        } else if let soloEntitlement = info.entitlements[RevenueCatConfig.Entitlement.premiumSolo],
                  soloEntitlement.isActive {
            subscription.tierEnum = .solo
            subscription.statusEnum = mapEntitlementToStatus(soloEntitlement)
            subscription.purchaseDate = soloEntitlement.originalPurchaseDate
            subscription.expiryDate = soloEntitlement.expirationDate
            if let expiry = soloEntitlement.expirationDate {
                subscription.graceEndDate = expiry.addingTimeInterval(gracePeriodDuration)
            }
        }

        subscription.lastValidatedDate = Date()

        do {
            try context.save()

            // Schedule subscription expiration reminders
            if let expiryDate = subscription.expiryDate {
                NotificationService.shared.scheduleSubscriptionReminders(
                    expirationDate: expiryDate,
                    isTrial: false,
                    remindDays: [7, 3, 0]
                )
            }

            // Sync subscription status to CloudKit for child device verification
            await syncSubscriptionToCloudKit()
        } catch {
            print("[SubscriptionManager] Failed to update local subscription: \(error)")
        }
    }

    /// Sync subscription status to CloudKit so child devices can verify parent's subscription
    private func syncSubscriptionToCloudKit() async {
        // Only sync if this is a parent device
        guard deviceManager.currentMode == .parentDevice else { return }

        do {
            try await CloudKitSyncService.shared.updateParentSubscriptionStatus(
                tier: currentTier,
                status: currentStatus,
                expiryDate: subscription?.expiryDate
            )

            #if DEBUG
            print("[SubscriptionManager] Synced subscription to CloudKit: \(currentTier.rawValue), \(currentStatus.rawValue)")
            #endif
        } catch {
            // Log but don't fail - child will use cached data
            print("[SubscriptionManager] Failed to sync subscription to CloudKit: \(error)")
        }
    }

    // MARK: - Entitlement Helpers

    /// Whether the user has access to premium features
    var hasAccess: Bool {
        currentStatus.isAccessGranted
    }

    /// Whether the user can create challenges
    var canCreateChallenge: Bool {
        hasAccess
    }

    /// Maximum number of child devices for current tier
    var childDeviceLimit: Int {
        currentTier.childDeviceLimit
    }

    /// Maximum number of parent devices per child for current tier
    var parentDeviceLimitPerChild: Int {
        currentTier.parentDeviceLimitPerChild
    }

    /// Check if user can pair another child device
    func canPairChildDevice(currentCount: Int) -> Bool {
        currentCount < childDeviceLimit
    }

    /// Check if another parent can pair with a child (2 parent limit)
    func canPairParentDevice(currentCount: Int) -> Bool {
        currentCount < parentDeviceLimitPerChild
    }

    /// Whether user is in trial period
    var isInTrial: Bool {
        currentStatus == .trial
    }

    /// Whether user is in grace period
    var isInGracePeriod: Bool {
        currentStatus == .grace
    }

    /// Days remaining in trial
    var trialDaysRemaining: Int? {
        subscription?.daysRemainingInTrial
    }

    /// Days remaining in grace period
    var graceDaysRemaining: Int? {
        subscription?.daysRemainingInGrace
    }

    /// Display name for current tier
    var currentTierName: String {
        currentTier.displayName
    }

    // MARK: - Package Helpers

    /// Get a specific package from the current offering
    func package(for productID: String) -> Package? {
        currentOffering?.availablePackages.first {
            $0.storeProduct.productIdentifier == productID
        }
    }

    /// Get the monthly package for a tier
    func monthlyPackage(for tier: SubscriptionTier) -> Package? {
        guard let productID = tier.monthlyProductID else { return nil }
        return package(for: productID)
    }

    /// Get the annual package for a tier
    func annualPackage(for tier: SubscriptionTier) -> Package? {
        guard let productID = tier.annualProductID else { return nil }
        return package(for: productID)
    }

    /// All available packages grouped by tier
    var packagesByTier: [SubscriptionTier: [Package]] {
        guard let offering = currentOffering else { return [:] }

        var result: [SubscriptionTier: [Package]] = [:]

        for tier in [SubscriptionTier.solo, .individual, .family] {
            var packages: [Package] = []
            if let monthly = monthlyPackage(for: tier) {
                packages.append(monthly)
            }
            if let annual = annualPackage(for: tier) {
                packages.append(annual)
            }
            if !packages.isEmpty {
                result[tier] = packages
            }
        }

        return result
    }

    // MARK: - StoreKit Fallback Helpers

    /// Get StoreKit product (fallback when RevenueCat unavailable)
    func storeKitProduct(for productID: String) -> Product? {
        storeKitProducts[productID]
    }

    /// Get StoreKit product price string (fallback)
    func storeKitPrice(for productID: String) -> String? {
        storeKitProducts[productID]?.displayPrice
    }

    /// Get monthly price for a tier (StoreKit fallback)
    func storeKitMonthlyPrice(for tier: SubscriptionTier) -> String? {
        guard let productID = tier.monthlyProductID else { return nil }
        return storeKitPrice(for: productID)
    }

    /// Get annual price for a tier (StoreKit fallback)
    func storeKitAnnualPrice(for tier: SubscriptionTier) -> String? {
        guard let productID = tier.annualProductID else { return nil }
        return storeKitPrice(for: productID)
    }

    /// Get StoreKit product for a tier's monthly subscription
    func storeKitMonthlyProduct(for tier: SubscriptionTier) -> Product? {
        guard let productID = tier.monthlyProductID else { return nil }
        return storeKitProduct(for: productID)
    }

    /// Get StoreKit product for a tier's annual subscription
    func storeKitAnnualProduct(for tier: SubscriptionTier) -> Product? {
        guard let productID = tier.annualProductID else { return nil }
        return storeKitProduct(for: productID)
    }

    // MARK: - Firebase Family Management

    /// Create a Firebase family after subscription purchase (for Individual/Family tiers)
    func createFirebaseFamilyIfNeeded() async {
        // Only create Firebase family for tiers that require parent device
        guard currentTier.requiresParentDevice else { return }

        do {
            let familyId = try await FirebaseValidationService.shared.createFamily(subscriptionTier: currentTier)

            #if DEBUG
            print("[SubscriptionManager] Created Firebase family: \(familyId)")
            #endif
        } catch {
            print("[SubscriptionManager] Failed to create Firebase family: \(error)")
        }
    }

    /// Whether the subscription allows pairing with parent devices
    var allowsParentPairing: Bool {
        currentTier.requiresParentDevice && hasAccess
    }

    /// Whether the subscription is Solo (single device, no pairing)
    var isSoloSubscription: Bool {
        currentTier == .solo
    }

    // MARK: - Keychain Helpers (Trial Protection)

    /// Save trial start date to Keychain (persists across reinstalls)
    private func saveTrialStartToKeychain(_ date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date)
        let data = dateString.data(using: .utf8)!

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainTrialStartKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainTrialStartKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)

        #if DEBUG
        if status == errSecSuccess {
            print("[SubscriptionManager] Trial start date saved to Keychain: \(dateString)")
        } else {
            print("[SubscriptionManager] Keychain save failed with status: \(status)")
        }
        #endif
    }

    /// Load trial start date from Keychain (nil if never started trial)
    private func loadTrialStartFromKeychain() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainTrialStartKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dateString = String(data: data, encoding: .utf8),
              let date = ISO8601DateFormatter().date(from: dateString) else {
            return nil
        }

        #if DEBUG
        print("[SubscriptionManager] Trial start date loaded from Keychain: \(dateString)")
        #endif

        return date
    }

    // MARK: - Development Mode

    #if DEBUG
    /// Activate a development subscription for testing (DEBUG only).
    /// This allows testing subscription features without a real purchase.
    func activateDevSubscription(tier: SubscriptionTier) {
        currentTier = tier
        currentStatus = .active

        // Also update local CoreData subscription for consistency
        if let subscription = subscription {
            subscription.tierEnum = tier
            subscription.statusEnum = .active
            try? subscription.managedObjectContext?.save()
        }

        print("[SubscriptionManager] 🔓 Dev subscription activated: \(tier.displayName)")
    }
    #endif
}

// MARK: - PurchasesDelegate

extension SubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.customerInfo = customerInfo
            self.updateTierFromCustomerInfo()

            // Sync to CloudKit when subscription status changes
            await self.syncSubscriptionToCloudKit()

            #if DEBUG
            print("[SubscriptionManager] Customer info updated via delegate")
            #endif
        }
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case verificationFailed
    case userCancelled
    case pending
    case unknown
    case noOfferings

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Failed to verify purchase"
        case .userCancelled:
            return "Purchase was cancelled"
        case .pending:
            return "Purchase is pending approval"
        case .unknown:
            return "An unknown error occurred"
        case .noOfferings:
            return "No subscription options available"
        }
    }
}
