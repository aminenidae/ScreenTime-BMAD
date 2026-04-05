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

    /// Whether paired children exceed the current tier limit (parent device only)
    @Published private(set) var hasExcessChildren: Bool = false

    /// Details about excess children (current count, limit, excess count)
    @Published private(set) var excessChildInfo: (current: Int, limit: Int, excess: Int)?

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
        if RevenueCatConfig.shouldEnableDebugLogging {
            Purchases.logLevel = .info
        }

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
            // Active subscription (whether renewing or not)
            return .active
        } else if entitlement.billingIssueDetectedAt != nil {
            // Billing issue - RevenueCat grace period
            return .grace
        } else if let expiryDate = entitlement.expirationDate {
            // Check if within our app's grace period after expiration
            let gracePeriodEnd = expiryDate.addingTimeInterval(gracePeriodDuration)
            if Date() < gracePeriodEnd {
                return .grace
            }
        }
        return .expired
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

        guard !result.userCancelled else {
            throw SubscriptionError.userCancelled
        }

        customerInfo = result.customerInfo
        updateTierFromCustomerInfo()

        // If entitlement not yet reflected (e.g. StoreKit timing lag), try restore once
        if !hasAccess {
            customerInfo = try await Purchases.shared.restorePurchases()
            updateTierFromCustomerInfo()
        }

        await updateLocalSubscription(from: customerInfo)

        print("[SubscriptionManager] Purchase complete: \(package.storeProduct.productIdentifier), hasAccess: \(hasAccess)")
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

    /// Get a specific package, searching the current offering first then all offerings.
    /// Needed because RevenueCat has separate offerings per tier (Solo/Individual/Family)
    /// with only one set as default at a time.
    func package(for productID: String) -> Package? {
        if let found = currentOffering?.availablePackages.first(where: {
            $0.storeProduct.productIdentifier == productID
        }) {
            return found
        }
        return offerings?.all.values
            .flatMap { $0.availablePackages }
            .first { $0.storeProduct.productIdentifier == productID }
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

    /// Create or update Firebase family for pairing tiers (Individual/Family)
    /// Handles upgrades from Solo (which has no family) to pairing tiers
    func createFirebaseFamilyIfNeeded() async {
        // Only for tiers that require parent device (pairing tiers)
        guard currentTier.requiresParentDevice else { return }
        guard deviceManager.currentMode == .parentDevice else { return }

        // Check if family already exists (e.g., re-subscribing or upgrading from Individual to Family)
        if let familyId = FirebaseValidationService.shared.currentFamilyId {
            // Family exists - update tier (in case of upgrade/downgrade)
            do {
                try await FirebaseValidationService.shared.updateFamilySubscription(
                    familyId: familyId,
                    subscriptionTier: currentTier
                )
                #if DEBUG
                print("[SubscriptionManager] Updated existing Firebase family: \(familyId)")
                #endif
            } catch {
                print("[SubscriptionManager] Failed to update Firebase family: \(error)")
            }
            return
        }

        // No family exists - create one (upgrading from Solo or Trial)
        do {
            let familyId = try await FirebaseValidationService.shared.createFamily(subscriptionTier: currentTier)

            #if DEBUG
            print("[SubscriptionManager] Created Firebase family: \(familyId)")
            #endif
        } catch {
            print("[SubscriptionManager] Failed to create Firebase family: \(error)")
        }
    }

    /// Whether the subscription allows pairing with child devices
    /// Trial users CAN pair (to set up before subscribing)
    /// Solo users CANNOT pair (no children allowed)
    var allowsParentPairing: Bool {
        // Solo subscribers cannot pair - no children allowed
        guard currentTier != .solo else { return false }
        // Everyone else (trial, individual, family) can pair if they have access
        return hasAccess
    }

    /// Whether the subscription is Solo (single device, no pairing)
    var isSoloSubscription: Bool {
        currentTier == .solo
    }

    /// Whether this is a child device receiving subscription access from a parent
    /// True when child device has Individual/Family tier (which can only come from parent pairing)
    var isParentPairedSubscription: Bool {
        deviceManager.currentMode == .childDevice &&
        (currentTier == .individual || currentTier == .family)
    }

    // MARK: - Excess Children Detection

    /// Check if current paired children exceed tier limit (async - requires CloudKit query)
    /// Returns (hasExcess, currentCount, limit, excessCount)
    func checkExcessPairedChildren() async -> (hasExcess: Bool, currentCount: Int, limit: Int, excessCount: Int) {
        guard deviceManager.currentMode == .parentDevice else {
            return (false, 0, 0, 0)
        }

        let limit = currentTier.childDeviceLimit

        do {
            let devices = try await CloudKitSyncService.shared.fetchLinkedChildDevices()
            let currentCount = devices.count
            let excessCount = max(0, currentCount - limit)
            let hasExcess = currentCount > limit

            return (hasExcess, currentCount, limit, excessCount)
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Failed to fetch paired children: \(error)")
            #endif
            return (false, 0, limit, 0)
        }
    }

    /// Update published excess children state (called after tier changes)
    /// Updates hasExcessChildren and excessChildInfo for UI binding
    private func checkForExcessChildren() async {
        guard deviceManager.currentMode == .parentDevice else {
            hasExcessChildren = false
            excessChildInfo = nil
            return
        }

        let (hasExcess, current, limit, excess) = await checkExcessPairedChildren()
        hasExcessChildren = hasExcess
        if hasExcess {
            excessChildInfo = (current, limit, excess)
            #if DEBUG
            print("[SubscriptionManager] ⚠️ Excess children detected: \(current)/\(limit) (\(excess) over limit)")
            #endif
        } else {
            excessChildInfo = nil
        }
    }

    /// Whether child's inherited subscription has expired
    var isParentSubscriptionExpired: Bool {
        guard isParentPairedSubscription else { return false }
        guard let expiryDate = subscription?.expiryDate else { return false }
        return Date() > expiryDate
    }

    /// Whether child is paired with parent but parent doesn't have active subscription
    /// This happens when: child paired during trial, but parent never subscribed, or parent subscription expired
    var isPairedButParentNotSubscribed: Bool {
        guard deviceManager.currentMode == .childDevice else { return false }

        // Check if child has any paired parents
        let hasPairedParent = DevicePairingService.shared.getPairedParentCount() > 0

        guard hasPairedParent else { return false }

        // Child is paired but still on trial tier or expired status
        // (If parent had valid subscription, child would have Individual/Family tier)
        return currentTier == .trial && (currentStatus == .expired || currentStatus == .trial)
    }

    // MARK: - Child Device Subscription Refresh

    /// Refresh parent subscription status (child device only)
    /// Called on app foreground to detect parent tier changes/expiration
    func refreshParentSubscriptionIfNeeded() async {
        guard deviceManager.currentMode == .childDevice else { return }

        // Get paired parent device ID
        let pairedParents = DevicePairingService.shared.getPairedParents()
        guard let primaryParent = pairedParents.first else {
            #if DEBUG
            print("[SubscriptionManager] No paired parent - skipping refresh")
            #endif
            return
        }

        do {
            let (tier, status, isValid) = try await CloudKitSyncService.shared.fetchParentSubscriptionStatus(
                parentDeviceID: primaryParent.id
            )

            if isValid {
                // Update tier if parent subscription is valid
                if tier == .individual || tier == .family {
                    if currentTier != tier {
                        currentTier = tier
                        #if DEBUG
                        print("[SubscriptionManager] Updated child tier from parent: \(tier.rawValue)")
                        #endif
                    }
                    currentStatus = status
                } else {
                    // Parent downgraded to Solo or Trial (can't have children)
                    currentTier = .trial
                    currentStatus = .expired
                    #if DEBUG
                    print("[SubscriptionManager] Parent downgraded - child access revoked")
                    #endif
                }
            } else {
                // Parent subscription expired/invalid
                currentTier = .trial
                currentStatus = .expired
                #if DEBUG
                print("[SubscriptionManager] Parent subscription invalid - child access revoked")
                #endif
            }

            // Update local subscription record
            if let sub = subscription {
                sub.tierEnum = currentTier
                sub.statusEnum = currentStatus
                try? sub.managedObjectContext?.save()
            }
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Failed to refresh parent status: \(error)")
            #endif
        }
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

    // MARK: - Testing Helper (REMOVE BEFORE RELEASE)
    /// Completely resets trial for testing - clears ALL storage layers
    func resetTrialForTesting() {
        let now = Date()
        let nowString = ISO8601DateFormatter().string(from: now)

        // 1. Reset Keychain trial start date to NOW
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainTrialStartKey
        ]
        SecItemDelete(keychainQuery as CFDictionary)

        var addQuery = keychainQuery
        addQuery[kSecValueData as String] = nowString.data(using: .utf8)!
        SecItemAdd(addQuery as CFDictionary, nil)

        // 2. Reset CoreData UserSubscription
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<UserSubscription> = UserSubscription.fetchRequest()
        if let subscriptions = try? context.fetch(fetchRequest) {
            for sub in subscriptions {
                sub.trialStartDate = now
                sub.trialEndDate = Calendar.current.date(byAdding: .day, value: 14, to: now)
                sub.statusEnum = .trial
            }
            try? context.save()
        }

        // 3. Reset in-memory state
        currentTier = .trial
        currentStatus = .trial

        // 4. Reset ChildBackgroundSyncService cache
        ChildBackgroundSyncService.resetTrialForTesting()

        // 5. Clear Firebase cache
        UserDefaults.standard.removeObject(forKey: "firebase_subscription_valid")

        print("[SubscriptionManager] 🔓 FULL trial reset - all storage layers cleared")
    }

    // MARK: - Service Restart (Subscription Reactivation)

    /// Restart monitoring services after subscription becomes active (from expired state)
    /// Called when user subscribes after trial expires
    private func restartMonitoringServices() async {
        // Only for child devices - parent devices don't have monitoring
        guard deviceManager.currentMode == .childDevice else { return }

        #if DEBUG
        print("[SubscriptionManager] 🔄 Subscription activated - restarting monitoring services")
        #endif

        // Restart DeviceActivity monitoring with fresh thresholds
        await ScreenTimeService.shared.restartMonitoring(reason: "subscription reactivated", force: true)

        // Restart BlockingCoordinator periodic refresh and shield sync
        BlockingCoordinator.shared.startPeriodicRefresh()

        // Re-sync reward app shields with current tokens
        let currentTokens = BlockingCoordinator.shared.currentRewardTokens
        if !currentTokens.isEmpty {
            ScreenTimeService.shared.syncRewardAppShields(currentRewardTokens: currentTokens)
        }

        // Reschedule background tasks
        ChildBackgroundSyncService.shared.scheduleNextUsageUpload()
        ChildBackgroundSyncService.shared.scheduleNextConfigCheck()

        #if DEBUG
        print("[SubscriptionManager] ✅ Monitoring services restarted")
        #endif
    }
}

// MARK: - PurchasesDelegate

extension SubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            let previousTier = self.currentTier
            let previousHadAccess = self.hasAccess

            self.customerInfo = customerInfo
            self.updateTierFromCustomerInfo()

            // If transitioning from expired to active, restart monitoring services
            if !previousHadAccess && self.hasAccess {
                await self.restartMonitoringServices()
            }

            // Sync to CloudKit when subscription status changes
            await self.syncSubscriptionToCloudKit()

            // Update Firebase family if tier changed and this is a parent device
            // Important: Update for ALL tier changes, including downgrades to Solo/Trial
            if previousTier != self.currentTier,
               self.deviceManager.currentMode == .parentDevice,
               let familyId = FirebaseValidationService.shared.currentFamilyId {
                do {
                    if self.currentTier.requiresParentDevice {
                        // Upgrading or staying on pairing tier - update subscription
                        try await FirebaseValidationService.shared.updateFamilySubscription(
                            familyId: familyId,
                            subscriptionTier: self.currentTier
                        )
                    } else {
                        // Downgrading to Solo or expired - mark family as expired
                        try await FirebaseValidationService.shared.markFamilyExpired(familyId: familyId)
                    }
                    #if DEBUG
                    print("[SubscriptionManager] Updated Firebase family for tier change: \(previousTier.rawValue) → \(self.currentTier.rawValue)")
                    #endif

                    // Check for excess children after downgrade
                    await self.checkForExcessChildren()
                } catch {
                    print("[SubscriptionManager] Failed to update Firebase family: \(error)")
                }
            }

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
