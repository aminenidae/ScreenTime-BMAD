import Foundation
import SwiftUI
import Combine
import StoreKit
import CoreData

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Published State
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var currentTier: SubscriptionTier = .free
    @Published private(set) var currentStatus: SubscriptionStatus = .trial
    @Published private(set) var subscription: UserSubscription?

    // MARK: - Constants
    private let trialDuration: TimeInterval = 30 * 24 * 60 * 60
    private let gracePeriodDuration: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Dependencies
    private let persistenceController = PersistenceController.shared
    private let deviceManager = DeviceModeManager.shared

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await loadSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading
    func loadProducts() async {
        let productIDs = SubscriptionTier
            .allCases
            .compactMap { $0.productID }

        guard !productIDs.isEmpty else { return }

        do {
            products = try await Product.products(for: productIDs)
            #if DEBUG
            print("[SubscriptionManager] Loaded \(products.count) products")
            #endif
        } catch {
            print("[SubscriptionManager] Failed to load products: \(error)")
        }
    }

    // MARK: - Subscription Lifecycle
    func loadSubscriptionStatus() async {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<UserSubscription>(entityName: "UserSubscription")
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "userDeviceID == %@", deviceManager.deviceID)

        do {
            let results = try context.fetch(fetchRequest)

            if let existingSubscription = results.first {
                subscription = existingSubscription
                updateSubscriptionState()
            } else {
                await createTrialSubscription()
            }

            await checkStoreKitSubscriptions()
        } catch {
            print("[SubscriptionManager] Failed to load subscription: \(error)")
        }
    }

    private func createTrialSubscription() async {
        let context = persistenceController.container.viewContext

        let newSubscription = UserSubscription(context: context)
        newSubscription.subscriptionID = UUID().uuidString
        newSubscription.userDeviceID = deviceManager.deviceID
        newSubscription.tierEnum = .free
        newSubscription.statusEnum = .trial

        let now = Date()
        newSubscription.trialStartDate = now
        newSubscription.trialEndDate = now.addingTimeInterval(trialDuration)
        newSubscription.graceEndDate = now.addingTimeInterval(trialDuration + gracePeriodDuration)

        do {
            try context.save()
            subscription = newSubscription
            updateSubscriptionState()
            print("[SubscriptionManager] Created trial subscription")
        } catch {
            print("[SubscriptionManager] Failed to create trial subscription: \(error)")
        }
    }

    private func updateSubscriptionState() {
        guard let subscription else {
            currentTier = .free
            currentStatus = .trial
            return
        }

        var needsSave = false
        let now = Date()

        // Transition out of trial when needed
        if subscription.statusEnum == .trial,
           let trialEnd = subscription.trialEndDate,
           now > trialEnd {
            if let graceEnd = subscription.graceEndDate,
               now < graceEnd {
                subscription.statusEnum = .grace
            } else {
                subscription.statusEnum = .expired
            }
            needsSave = true
        }

        // Transition from active to grace/expired if subscription expired
        if subscription.statusEnum == .active,
           let expiryDate = subscription.expiryDate,
           now > expiryDate {
            if let graceEnd = subscription.graceEndDate,
               now < graceEnd {
                subscription.statusEnum = .grace
            } else {
                subscription.statusEnum = .expired
            }
            needsSave = true
        }

        currentTier = subscription.tierEnum
        currentStatus = subscription.statusEnum

        if needsSave {
            do {
                try subscription.managedObjectContext?.save()
            } catch {
                print("[SubscriptionManager] Failed to persist subscription state update: \(error)")
            }
        }
    }

    private func checkStoreKitSubscriptions() async {
        do {
            var updatedProductIDs: Set<String> = []

            for await result in StoreKit.Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                updatedProductIDs.insert(transaction.productID)
                await updateSubscription(with: transaction)
            }

            purchasedProductIDs = updatedProductIDs
        } catch {
            print("[SubscriptionManager] Failed to check StoreKit entitlements: \(error)")
        }
    }

    private func updateSubscription(with transaction: StoreKit.Transaction) async {
        let context = persistenceController.container.viewContext
        let subscription = subscription ?? UserSubscription(context: context)

        if self.subscription == nil {
            subscription.subscriptionID = UUID().uuidString
            subscription.userDeviceID = deviceManager.deviceID
            self.subscription = subscription
        }

        if let tier = SubscriptionTier.allCases.first(where: { $0.productID == transaction.productID }) {
            subscription.tierEnum = tier
        }

        subscription.statusEnum = .active
        subscription.purchaseDate = transaction.purchaseDate
        subscription.expiryDate = transaction.expirationDate
        subscription.transactionID = String(transaction.id)
        subscription.originalTransactionID = String(transaction.originalID)
        subscription.autoRenewEnabled = true
        subscription.lastValidatedDate = Date()

        if subscription.graceEndDate == nil, let expiryDate = transaction.expirationDate {
            subscription.graceEndDate = expiryDate.addingTimeInterval(gracePeriodDuration)
        }

        do {
            try context.save()
            purchasedProductIDs.insert(transaction.productID)
            updateSubscriptionState()
            #if DEBUG
            print("[SubscriptionManager] Updated subscription with transaction \(transaction.id)")
            #endif
        } catch {
            print("[SubscriptionManager] Failed to save subscription update: \(error)")
        }
    }

    // MARK: - Purchasing
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscription(with: transaction)
            await transaction.finish()
        case .userCancelled:
            throw SubscriptionError.userCancelled
        case .pending:
            throw SubscriptionError.pending
        @unknown default:
            throw SubscriptionError.unknown
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await checkStoreKitSubscriptions()
    }

    // MARK: - Transaction Listener
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { continue }
                guard case .verified(let transaction) = result else { continue }

                await self.updateSubscription(with: transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Entitlement Helpers
    var hasAccess: Bool {
        currentStatus.isAccessGranted
    }

    var canCreateChallenge: Bool {
        hasAccess
    }

    var childDeviceLimit: Int {
        currentTier.childDeviceLimit
    }

    func canPairChildDevice(currentCount: Int) -> Bool {
        currentCount < childDeviceLimit
    }

    var isInTrial: Bool {
        currentStatus == .trial
    }

    var isInGracePeriod: Bool {
        currentStatus == .grace
    }

    var trialDaysRemaining: Int? {
        subscription?.daysRemainingInTrial
    }

    var graceDaysRemaining: Int? {
        subscription?.daysRemainingInGrace
    }

    var currentTierName: String {
        currentTier.displayName
    }

    func product(for tier: SubscriptionTier) -> Product? {
        guard let productID = tier.productID else { return nil }
        return products.first { $0.id == productID }
    }

    // MARK: - Helpers
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
}

// MARK: - Errors
enum SubscriptionError: LocalizedError {
    case verificationFailed
    case userCancelled
    case pending
    case unknown

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
        }
    }
}
