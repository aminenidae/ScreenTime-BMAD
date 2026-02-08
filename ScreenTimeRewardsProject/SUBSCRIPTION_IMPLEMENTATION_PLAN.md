# Subscription Implementation Plan
## ScreenTime Rewards App

**Version:** 1.0
**Date:** November 11, 2025
**Status:** Ready for Implementation
**Role:** Planning & Review Document for Dev Agent

---

## ✅ Implementation Progress (December 2025)

| Phase | Key Deliverables | Status |
|-------|------------------|--------|
| Phase 1 | Subscription models, Core Data schema, StoreKit config, entitlement clarification | **Completed** |
| Phase 2 | `SubscriptionManager` service + StoreKit flows wired into app startup | **Completed** |
| Phase 3 | Paywall, management view, banner, lockout, Settings/MainTab wiring | **Completed** |
| Phase 4 | Challenge gating and device pairing limits tied to subscription tier | **Completed** |

**Highlights**
- `SubscriptionTier`/`SubscriptionStatus` enums, `UserSubscription` entity/helpers, and StoreKit configuration are live in the repo.
- `SubscriptionManager` drives trials, purchases/restores, and entitlement checks; Root/Main/Settings views now respond to subscription state.
- Paywall & management surfaces ship with trial/grace messaging, lockout UX, and Settings entry point.
- Challenge creation and child device pairing respect plan limits and display the paywall when necessary.

---

## 📋 Executive Summary

### Business Model
- **Model Type:** Free trial then paid subscription
- **Trial Period:** 30 days (full access, no payment required)
- **Pricing Tiers:** Two tiers (Individual & Family)
- **Post-Trial Behavior:** Grace period (7 days) then complete lockout
- **Backend:** Server-side receipt validation (to be built)

### Implementation Timeline
- **Total Estimated Time:** 20 days
- **Phases:** 6 phases from foundation to App Store submission
- **Implementation Approach:** Dev agent executes, Planner reviews

---

## 🎯 Business Requirements

### Subscription Tiers

#### Individual Tier
- **Price:** $7.99/month (recommended)
- **Features:**
  - Full app access after trial
  - Support for 1 child device
  - Unlimited challenges
  - All learning & reward features
  - Basic analytics

#### Family Tier
- **Price:** $12.99/month (recommended)
- **Features:**
  - Everything in Individual
  - Support for up to 5 child devices
  - Advanced family analytics
  - Multi-child management dashboard
  - Priority support

### Trial & Expiration Logic

#### Trial Period (30 Days)
- Starts automatically on first app launch
- Full access to all features
- No payment information required
- User sees countdown in UI (e.g., "23 days left in trial")

#### Grace Period (7 Days)
- Begins immediately after trial or subscription expiration
- App still functional but shows persistent warning banners
- Daily reminders to subscribe
- "Subscribe Now" prompts on key actions

#### Post-Grace Period
- **Complete lockout** - app becomes read-only
- Users can view existing data but cannot:
  - Create new challenges
  - Track screen time
  - Access child devices
  - Modify any settings
- Clear "Subscribe to Continue" screen
- Access to subscription management only

### Feature Access Matrix

| Feature | Free Trial | Expired (Grace) | Expired (Lockout) | Individual | Family |
|---------|-----------|-----------------|-------------------|-----------|--------|
| Challenge Creation | ✅ | ⚠️ Warning | ❌ | ✅ | ✅ |
| Screen Time Tracking | ✅ | ⚠️ Warning | ❌ | ✅ | ✅ |
| Child Devices | 5 max | 1 max | ❌ | 1 max | 5 max |
| Analytics | ✅ | ⚠️ Warning | ❌ | ✅ | ✅ Advanced |
| View Historical Data | ✅ | ✅ | ✅ | ✅ | ✅ |
| Subscription Management | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 🏗️ Technical Architecture

### Current App Architecture

```
ScreenTimeRewardsApp (@main)
├── RootView
│   ├── DeviceSelectionView (first launch)
│   ├── ParentRemoteDashboardView (parent device)
│   └── Child Device Flow
│       ├── SetupFlowView (onboarding)
│       └── Mode Selection
│           ├── ParentModeContainer → MainTabView
│           └── ChildModeView
│
├── Services (Singletons, @MainActor)
│   ├── DeviceModeManager
│   ├── SessionManager
│   ├── AuthenticationService
│   ├── ChallengeService
│   ├── CloudKitSyncService
│   └── **NEW: SubscriptionManager**
│
├── CoreData Models
│   ├── Challenge, ChallengeProgress
│   ├── AppProgress (new from UX polish)
│   ├── Badge, StreakRecord
│   ├── RegisteredDevice
│   └── **NEW: UserSubscription**
│
└── UI Structure
    ├── MainTabView (4 tabs: Rewards, Learning, Settings, Challenges)
    ├── ChildModeView (2 tabs: Dashboard, Challenges)
    └── **NEW: Subscription Views**
```

### Subscription Integration Points

#### 1. App Launch (ScreenTimeRewardsApp.swift)
```swift
@StateObject private var subscriptionManager = SubscriptionManager.shared
```
- Initialize subscription manager
- Check subscription status on launch
- Route to appropriate view based on status

#### 2. Feature Gates
**Challenge Creation** (`ParentChallengesTabView.swift` line 99)
```swift
Button("Create Custom Challenge") {
    if subscriptionManager.canCreateChallenge {
        showingChallengeBuilder = true
    } else {
        showSubscriptionPaywall = true
    }
}
```

**Child Device Pairing** (`CloudKitSyncService.swift`)
```swift
func canPairChildDevice() -> Bool {
    let currentCount = linkedChildDevices.count
    let limit = subscriptionManager.childDeviceLimit
    return currentCount < limit
}
```

#### 3. Subscription UI
**Settings Tab** (`SettingsTabView.swift` after line 28)
```swift
Section(header: Text("Subscription")) {
    NavigationLink(destination: SubscriptionManagementView()) {
        HStack {
            Label("Manage Subscription", systemImage: "crown.fill")
            Spacer()
            Text(subscriptionManager.currentTierName)
                .foregroundColor(.secondary)
        }
    }
}
```

---

## 📦 Phase 1: Foundation & Infrastructure (Days 1-3)

### Overview
Set up core subscription infrastructure, models, and StoreKit 2 integration.

---

### Task 1.1: Create SubscriptionTier Model

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Models/SubscriptionTier.swift`

**Purpose:** Define subscription tier types and their properties

**Implementation:**
```swift
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
        case .free: return 5  // Generous during trial
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
```

**Testing:**
- Verify all tier cases compile
- Test productID generation
- Verify childDeviceLimit values match requirements

---

### Task 1.2: Update CoreData Schema

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ScreenTimeRewards.xcdatamodeld/ScreenTimeRewards.xcdatamodel/contents`

**Purpose:** Add UserSubscription entity for tracking subscription data

**Implementation:**

Add new entity `UserSubscription` with attributes:

```xml
<entity name="UserSubscription" representedClassName="UserSubscription" syncable="YES">
    <attribute name="subscriptionID" optional="YES" attributeType="String"/>
    <attribute name="userDeviceID" optional="YES" attributeType="String"/>
    <attribute name="subscriptionTier" optional="YES" attributeType="String" defaultValueString="free"/>
    <attribute name="subscriptionStatus" optional="YES" attributeType="String" defaultValueString="trial"/>
    <attribute name="purchaseDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
    <attribute name="expiryDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
    <attribute name="trialStartDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
    <attribute name="trialEndDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
    <attribute name="graceEndDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
    <attribute name="autoRenewEnabled" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
    <attribute name="transactionID" optional="YES" attributeType="String"/>
    <attribute name="originalTransactionID" optional="YES" attributeType="String"/>
    <attribute name="lastValidatedDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

    <fetchIndex name="byUserDeviceID">
        <fetchIndexElement property="userDeviceID" type="Binary" order="ascending"/>
    </fetchIndex>
    <fetchIndex name="byOriginalTransactionID">
        <fetchIndexElement property="originalTransactionID" type="Binary" order="ascending"/>
    </fetchIndex>
</entity>
```

Modify existing `RegisteredDevice` entity:
```xml
<!-- Add this attribute to RegisteredDevice entity -->
<attribute name="subscriptionTier" optional="YES" attributeType="String" defaultValueString="free"/>
```

**After Xcode generates classes, create helpers:**

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/CoreData/UserSubscription+Helpers.swift`

```swift
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
```

**Testing:**
- Build project to generate CoreData classes
- Verify entity creation in Xcode data model editor
- Test helper methods with sample data

---

### Task 1.3: Create StoreKit Configuration File

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Configuration.storekit`

**Purpose:** Enable local StoreKit testing without App Store Connect

**Implementation:**
1. In Xcode: File → New → File → StoreKit Configuration File
2. Name it `Configuration.storekit`
3. Add two subscription products:

```json
{
  "identifier" : "Configuration",
  "nonRenewingSubscriptions" : [],
  "products" : [],
  "settings" : {
    "applicationName" : "ScreenTime Rewards",
    "bundle" : "com.screentimerewards",
    "_storefront" : "USA",
    "_storeKitErrors" : []
  },
  "subscriptionGroups" : [
    {
      "id" : "20776E67",
      "localizations" : [],
      "name" : "ScreenTime Premium",
      "subscriptions" : [
        {
          "adHocOffers" : [],
          "codeOffers" : [],
          "displayPrice" : "7.99",
          "familyShareable" : false,
          "groupNumber" : 1,
          "internalID" : "6469881401",
          "introductoryOffer" : {
            "internalID" : "70B78597",
            "numberOfPeriods" : 1,
            "paymentMode" : "free",
            "subscriptionPeriod" : "P1M"
          },
          "localizations" : [
            {
              "description" : "Individual plan for 1 child device",
              "displayName" : "Individual Plan",
              "locale" : "en_US"
            }
          ],
          "productID" : "com.screentimerewards.individual.monthly",
          "recurringSubscriptionPeriod" : "P1M",
          "referenceName" : "Individual Monthly",
          "subscriptionGroupID" : "20776E67",
          "type" : "RecurringSubscription"
        },
        {
          "adHocOffers" : [],
          "codeOffers" : [],
          "displayPrice" : "12.99",
          "familyShareable" : true,
          "groupNumber" : 2,
          "internalID" : "6469881402",
          "introductoryOffer" : {
            "internalID" : "70B78598",
            "numberOfPeriods" : 1,
            "paymentMode" : "free",
            "subscriptionPeriod" : "P1M"
          },
          "localizations" : [
            {
              "description" : "Family plan for up to 5 child devices",
              "displayName" : "Family Plan",
              "locale" : "en_US"
            }
          ],
          "productID" : "com.screentimerewards.family.monthly",
          "recurringSubscriptionPeriod" : "P1M",
          "referenceName" : "Family Monthly",
          "subscriptionGroupID" : "20776E67",
          "type" : "RecurringSubscription"
        }
      ]
    }
  ],
  "version" : {
    "major" : 3,
    "minor" : 0
  }
}
```

**Configuration in Xcode:**
1. Product → Scheme → Edit Scheme
2. Run → Options tab
3. StoreKit Configuration: Select "Configuration.storekit"

**Testing:**
- Build and run app
- Verify products load in console
- Test purchase flow (uses sandbox)

---

### Task 1.4: StoreKit Entitlements (Clarification)

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ScreenTimeRewards.entitlements`

**Purpose:** Document that StoreKit 2 does not require additional entitlements

**Implementation:**

StoreKit 2 purchases work automatically with the default app sandbox. Do **not** add Apple Pay / in-app payment entitlements—those are only for Apple Pay merchant processing. Keep the entitlements file limited to:
- `aps-environment`
- `com.apple.developer.family-controls`
- `com.apple.developer.icloud-*`
- `com.apple.security.application-groups`

**Xcode Setup:**
1. Select the ScreenTimeRewards target.
2. Under Signing & Capabilities, ensure the "In-App Purchase" capability is enabled (this does not modify the entitlements plist).

**Testing:**
- Build succeeds without signing errors
- StoreKit configuration works in local testing

---

## 📦 Phase 2: Core Subscription Logic (Days 4-6)

### Overview
Implement SubscriptionManager service with StoreKit 2, trial management, and feature entitlements.

---

### Task 2.1: Create SubscriptionManager Service

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Services/SubscriptionManager.swift`

**Purpose:** Central service for subscription management, purchase flow, and entitlement checks

**Dependencies:**
- StoreKit 2
- CoreData (UserSubscription entity)
- DeviceModeManager (for device ID)

**Implementation:**

```swift
import Foundation
import StoreKit
import CoreData

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Published Properties
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var currentTier: SubscriptionTier = .free
    @Published private(set) var currentStatus: SubscriptionStatus = .trial
    @Published private(set) var subscription: UserSubscription?

    // MARK: - Constants
    private let trialDuration: TimeInterval = 30 * 24 * 60 * 60  // 30 days
    private let gracePeriodDuration: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    private var updateListenerTask: Task<Void, Error>?
    private let persistenceController = PersistenceController.shared

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
        do {
            let productIDs = [
                SubscriptionTier.individual.productID!,
                SubscriptionTier.family.productID!
            ]

            products = try await Product.products(for: productIDs)
            print("[SubscriptionManager] ✅ Loaded \(products.count) products")
        } catch {
            print("[SubscriptionManager] ❌ Failed to load products: \(error)")
        }
    }

    // MARK: - Subscription Status
    func loadSubscriptionStatus() async {
        let context = persistenceController.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        // Check for existing subscription in CoreData
        let fetchRequest: NSFetchRequest<UserSubscription> = UserSubscription.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userDeviceID == %@", deviceID)
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)

            if let existingSubscription = results.first {
                subscription = existingSubscription
                updateSubscriptionState()
            } else {
                // First launch - create trial subscription
                await createTrialSubscription()
            }

            // Check StoreKit for active subscriptions
            await checkStoreKitSubscriptions()
        } catch {
            print("[SubscriptionManager] ❌ Failed to load subscription: \(error)")
        }
    }

    private func createTrialSubscription() async {
        let context = persistenceController.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        let newSubscription = UserSubscription(context: context)
        newSubscription.subscriptionID = UUID().uuidString
        newSubscription.userDeviceID = deviceID
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
            print("[SubscriptionManager] ✅ Created trial subscription")
        } catch {
            print("[SubscriptionManager] ❌ Failed to create trial: \(error)")
        }
    }

    private func updateSubscriptionState() {
        guard let sub = subscription else { return }

        // Update local state
        currentTier = sub.tierEnum
        currentStatus = sub.statusEnum

        // Check if trial or grace period expired
        if sub.isTrialActive {
            currentStatus = .trial
        } else if sub.isInGracePeriod {
            currentStatus = .grace
        } else if sub.statusEnum == .trial || sub.statusEnum == .grace {
            currentStatus = .expired
        }

        // Update in CoreData if status changed
        if currentStatus != sub.statusEnum {
            sub.statusEnum = currentStatus
            try? persistenceController.container.viewContext.save()
        }
    }

    // MARK: - StoreKit Integration
    private func checkStoreKitSubscriptions() async {
        var validProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.revocationDate == nil {
                validProductIDs.insert(transaction.productID)
                await updateSubscription(with: transaction)
            }
        }

        purchasedProductIDs = validProductIDs
    }

    private func updateSubscription(with transaction: Transaction) async {
        guard let sub = subscription else { return }

        // Determine tier from product ID
        if transaction.productID == SubscriptionTier.individual.productID {
            sub.tierEnum = .individual
        } else if transaction.productID == SubscriptionTier.family.productID {
            sub.tierEnum = .family
        }

        sub.statusEnum = .active
        sub.transactionID = String(transaction.id)
        sub.originalTransactionID = String(transaction.originalID)
        sub.purchaseDate = transaction.purchaseDate
        sub.expiryDate = transaction.expirationDate
        sub.autoRenewEnabled = true

        try? persistenceController.container.viewContext.save()
        updateSubscriptionState()
    }

    // MARK: - Purchase Flow
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await updateSubscription(with: transaction)
                await transaction.finish()
                print("[SubscriptionManager] ✅ Purchase successful")
            case .unverified:
                throw SubscriptionError.verificationFailed
            }
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
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await self.updateSubscription(with: transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Entitlement Checks
    var hasAccess: Bool {
        return currentStatus.isAccessGranted
    }

    var canCreateChallenge: Bool {
        return hasAccess
    }

    var childDeviceLimit: Int {
        return currentTier.childDeviceLimit
    }

    func canPairChildDevice(currentCount: Int) -> Bool {
        return currentCount < childDeviceLimit
    }

    var isInTrial: Bool {
        return currentStatus == .trial
    }

    var isInGracePeriod: Bool {
        return currentStatus == .grace
    }

    var trialDaysRemaining: Int? {
        return subscription?.daysRemainingInTrial
    }

    var graceDaysRemaining: Int? {
        return subscription?.daysRemainingInGrace
    }

    var currentTierName: String {
        return currentTier.displayName
    }

    // MARK: - Helper Methods
    func product(for tier: SubscriptionTier) -> Product? {
        guard let productID = tier.productID else { return nil }
        return products.first { $0.id == productID }
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
        case .verificationFailed: return "Failed to verify purchase"
        case .userCancelled: return "Purchase was cancelled"
        case .pending: return "Purchase is pending approval"
        case .unknown: return "An unknown error occurred"
        }
    }
}
```

**Testing:**
- Initialize SubscriptionManager in test
- Verify trial creation on first launch
- Test product loading
- Simulate purchase flow

---

### Task 2.2: Integrate SubscriptionManager into App

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/ScreenTimeRewardsApp.swift`

**Purpose:** Initialize subscription manager on app launch

**Modification:**

```swift
@main
struct ScreenTimeRewardsApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appUsageViewModel = AppUsageViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager.shared  // ADD THIS

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appUsageViewModel)
                .environmentObject(subscriptionManager)  // ADD THIS
        }
    }
}
```

**Testing:**
- App launches without errors
- SubscriptionManager initializes
- Trial created on first launch

---

## 📦 Phase 3: UI Implementation (Days 7-10)

### Overview
Create subscription paywall, management screens, and integrate into existing UI.

---

### Task 3.1: Create Subscription Paywall View

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionPaywallView.swift`

**Purpose:** Full-screen subscription purchase interface

**Dependencies:**
- SubscriptionManager
- AppTheme

**Implementation:**

```swift
import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTier: SubscriptionTier = .individual
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    trialBanner
                    tierSelector
                    featureList
                    purchaseButton
                    restoreButton
                    legalText
                }
                .padding(24)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !subscriptionManager.hasAccess {
                // No close button during lockout
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("Unlock Premium")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppTheme.vibrantTeal)

            Text("Give your family the tools to balance screen time and learning")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var trialBanner: some View {
        VStack(spacing: 8) {
            Text("30-DAY FREE TRIAL")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("Full access, cancel anytime")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.sunnyYellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var tierSelector: some View {
        VStack(spacing: 12) {
            tierCard(.individual)
            tierCard(.family)
        }
    }

    private func tierCard(_ tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        let product = subscriptionManager.product(for: tier)

        return Button {
            selectedTier = tier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tier.displayName)
                            .font(.system(size: 20, weight: .bold))

                        if tier == .family {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.playfulCoral)
                                .cornerRadius(4)
                        }
                    }

                    Text(tier == .individual ? "For 1 child" : "For up to 5 children")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    if let product = product {
                        Text(product.displayPrice + "/month")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? AppTheme.vibrantTeal : .secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? AppTheme.vibrantTeal : Color.secondary.opacity(0.2),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's Included")
                .font(.system(size: 18, weight: .bold))

            ForEach(selectedTier.features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                    Text(feature)
                        .font(.system(size: 15))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchaseButton: some View {
        Button {
            Task {
                await purchase()
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Start Free Trial")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.vibrantTeal)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isPurchasing)
    }

    private var restoreButton: some View {
        Button {
            Task {
                await restore()
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var legalText: some View {
        VStack(spacing: 8) {
            Text("Cancel anytime. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://screentimerewards.com/terms")!)
                Text("•")
                Link("Privacy Policy", destination: URL(string: "https://screentimerewards.com/privacy")!)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions
    private func purchase() async {
        guard let product = subscriptionManager.product(for: selectedTier) else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await subscriptionManager.purchase(product)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func restore() async {
        do {
            try await subscriptionManager.restorePurchases()
            if subscriptionManager.hasAccess {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
```

**Testing:**
- Present paywall as sheet
- Verify tier selection works
- Test purchase flow (StoreKit testing)
- Test restore purchases

---

### Task 3.2: Create Subscription Management View

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionManagementView.swift`

**Purpose:** View current subscription details and manage

**Implementation:**

```swift
import SwiftUI

struct SubscriptionManagementView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    var body: some View {
        List {
            currentStatusSection

            if subscriptionManager.isInTrial {
                trialSection
            }

            if subscriptionManager.isInGracePeriod {
                graceSection
            }

            if subscriptionManager.hasAccess {
                benefitsSection
            }

            upgradeSection

            managementSection
        }
        .navigationTitle("Subscription")
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }

    private var currentStatusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionManager.currentTierName)
                        .font(.system(size: 18, weight: .bold))
                    Text(subscriptionManager.currentStatus.displayText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: tierIcon)
                    .font(.system(size: 40))
                    .foregroundColor(tierColor)
            }
            .padding(.vertical, 8)
        }
    }

    private var trialSection: some View {
        Section {
            if let daysRemaining = subscriptionManager.trialDaysRemaining {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(daysRemaining) days remaining")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Free trial ends on \(formattedTrialEndDate)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock.fill")
                        .foregroundColor(AppTheme.sunnyYellow)
                }
            }
        } header: {
            Text("Free Trial")
        }
    }

    private var graceSection: some View {
        Section {
            if let daysRemaining = subscriptionManager.graceDaysRemaining {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(daysRemaining) days to renew")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.playfulCoral)
                        Text("Subscribe now to continue using the app")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.playfulCoral)
                }
            }
        } header: {
            Text("Grace Period")
        }
    }

    private var benefitsSection: some View {
        Section {
            ForEach(subscriptionManager.currentTier.features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
            }
        } header: {
            Text("Your Benefits")
        }
    }

    private var upgradeSection: some View {
        Section {
            if subscriptionManager.currentTier == .individual {
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to Family", systemImage: "arrow.up.circle.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            } else if subscriptionManager.currentTier == .free {
                Button {
                    showPaywall = true
                } label: {
                    Label("Subscribe Now", systemImage: "crown.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
    }

    private var managementSection: some View {
        Section {
            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                Label("Manage in App Store", systemImage: "arrow.up.forward.app")
            }

            Button {
                Task {
                    try? await subscriptionManager.restorePurchases()
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Management")
        }
    }

    private var tierIcon: String {
        switch subscriptionManager.currentTier {
        case .free: return "hourglass"
        case .individual: return "person.fill"
        case .family: return "person.3.fill"
        }
    }

    private var tierColor: Color {
        switch subscriptionManager.currentTier {
        case .free: return .secondary
        case .individual: return AppTheme.vibrantTeal
        case .family: return AppTheme.sunnyYellow
        }
    }

    private var formattedTrialEndDate: String {
        guard let trialEnd = subscriptionManager.subscription?.trialEndDate else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: trialEnd)
    }
}
```

**Testing:**
- Navigate to management view
- Verify status displays correctly
- Test upgrade button
- Test restore purchases

---

### Task 3.3: Add Subscription to Settings Tab

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/SettingsTabView.swift`

**Modification:** Add subscription section after line 28

**Implementation:**

```swift
// Add after "Account" section, before "Devices" section

Section(header: Text("Subscription")) {
    NavigationLink(destination: SubscriptionManagementView()) {
        HStack {
            Label("Manage Subscription", systemImage: "crown.fill")
                .foregroundColor(AppTheme.vibrantTeal)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(subscriptionManager.currentTierName)
                    .font(.system(size: 14, weight: .semibold))

                if subscriptionManager.isInTrial, let days = subscriptionManager.trialDaysRemaining {
                    Text("\(days) days left")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if subscriptionManager.isInGracePeriod {
                    Text("Grace Period")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.playfulCoral)
                }
            }
        }
    }
}
```

**Also add @EnvironmentObject:**
```swift
struct SettingsTabView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager  // ADD THIS
    // ... rest of the code
```

**Testing:**
- Navigate to Settings
- Verify subscription section appears
- Tap to navigate to management view

---

### Task 3.4: Create Trial Banner Component

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/TrialBannerView.swift`

**Purpose:** Persistent banner showing trial/grace status

**Implementation:**

```swift
import SwiftUI

struct TrialBannerView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showPaywall = false

    var body: some View {
        if subscriptionManager.isInTrial {
            trialBanner
        } else if subscriptionManager.isInGracePeriod {
            graceBanner
        }
    }

    private var trialBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .foregroundColor(AppTheme.sunnyYellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Trial Active")
                        .font(.system(size: 14, weight: .semibold))
                    if let days = subscriptionManager.trialDaysRemaining {
                        Text("\(days) days remaining")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("Subscribe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
            }
            .padding(12)
            .background(AppTheme.sunnyYellow.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }

    private var graceBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.playfulCoral)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription Expired")
                        .font(.system(size: 14, weight: .semibold))
                    if let days = subscriptionManager.graceDaysRemaining {
                        Text("\(days) days to renew")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("Renew Now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.playfulCoral)
                    .cornerRadius(8)
            }
            .padding(12)
            .background(AppTheme.playfulCoral.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }
}
```

**Usage:** Add to MainTabView:

```swift
struct MainTabView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        VStack(spacing: 0) {
            TrialBannerView()  // ADD THIS at top

            TabView {
                // ... existing tabs
            }
        }
    }
}
```

**Testing:**
- Verify banner shows during trial
- Verify banner shows during grace
- Test tap to show paywall

---

### Task 3.5: Create Subscription Lockout View

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionLockoutView.swift`

**Purpose:** Full-screen lockout when subscription expired

**Implementation:**

```swift
import SwiftUI

struct SubscriptionLockoutView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.secondary)

                VStack(spacing: 16) {
                    Text("Subscription Required")
                        .font(.system(size: 28, weight: .bold))

                    Text("Your free trial has ended. Subscribe to continue using ScreenTime Rewards.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    showPaywall = true
                } label: {
                    Text("View Plans")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Text("You can still view your data in Settings")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }
}
```

**Integration:** Update `RootView` in ScreenTimeRewardsApp.swift:

```swift
struct RootView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        Group {
            if !subscriptionManager.hasAccess {
                SubscriptionLockoutView()  // ADD THIS
            } else if needsDeviceSelection {
                DeviceSelectionView()
            } else {
                // ... existing routing logic
            }
        }
    }
}
```

**Testing:**
- Set subscription status to expired
- Verify lockout screen appears
- Test "View Plans" button

---

## 📦 Phase 4: Feature Gating (Days 11-12)

### Overview
Add subscription checks to key features.

---

### Task 4.1: Gate Challenge Creation

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Views/ParentMode/ParentChallengesTabView.swift`

**Modification:** Around line 99-113

**Implementation:**

```swift
// Add state variable at top of struct
@EnvironmentObject var subscriptionManager: SubscriptionManager
@State private var showSubscriptionPaywall = false

// Modify "Create Custom Challenge" button
Button(action: {
    if subscriptionManager.canCreateChallenge {
        showingChallengeBuilder = true
    } else {
        showSubscriptionPaywall = true
    }
}) {
    Label("Create Custom Challenge", systemImage: "plus.circle.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                colors: [AppTheme.vibrantTeal, AppTheme.playfulCoral],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(14)
}
.sheet(isPresented: $showSubscriptionPaywall) {
    SubscriptionPaywallView()
}
```

**Testing:**
- Try creating challenge during trial (should work)
- Try creating challenge when expired (should show paywall)

---

### Task 4.2: Gate Child Device Pairing

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Services/CloudKitSyncService.swift`

**Modification:** Add check to `pairChildDevice()` method

**Implementation:**

```swift
func pairChildDevice(pairingCode: String) async throws {
    let subscriptionManager = SubscriptionManager.shared

    // Check subscription limit
    let currentCount = try await fetchLinkedChildDevices().count
    guard subscriptionManager.canPairChildDevice(currentCount: currentCount) else {
        throw PairingError.deviceLimitReached
    }

    // ... existing pairing logic
}

enum PairingError: LocalizedError {
    case deviceLimitReached
    case invalidCode
    case codeExpired

    var errorDescription: String? {
        switch self {
        case .deviceLimitReached:
            return "Device limit reached. Upgrade to Family plan to add more devices."
        case .invalidCode:
            return "Invalid pairing code"
        case .codeExpired:
            return "Pairing code has expired"
        }
    }
}
```

**Testing:**
- Pair 1 device with Individual tier (should work)
- Try pairing 2nd device (should show error)
- Upgrade to Family tier, retry (should work)

---

### Task 4.3: Add Subscription Checks to ChallengeService

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Services/ChallengeService.swift`

**Modification:** Add validation to `createChallenge()` method (line 40)

**Implementation:**

```swift
func createChallenge(
    title: String,
    description: String,
    // ... other parameters
) async throws {
    // Add subscription check at the beginning
    let subscriptionManager = SubscriptionManager.shared
    guard subscriptionManager.canCreateChallenge else {
        throw ChallengeError.subscriptionRequired
    }

    // ... existing challenge creation logic
}

enum ChallengeError: LocalizedError {
    case subscriptionRequired
    case invalidData
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return "Active subscription required to create challenges"
        case .invalidData:
            return "Invalid challenge data"
        case .saveFailed:
            return "Failed to save challenge"
        }
    }
}
```

**Testing:**
- Create challenge with active subscription
- Create challenge when expired (should throw error)

---

## 📦 Phase 5: Backend Setup (Days 13-16)

### Overview
Build backend server for receipt validation and subscription management.

**Note:** This is a high-level guide. Dev agent should choose tech stack (Node.js/Express, Python/Flask, or Firebase Cloud Functions).

---

### Task 5.1: Backend Architecture

**Purpose:** Server-side receipt validation with Apple App Store Server API

**Components:**
1. **Receipt Validation Endpoint** - Validates transactions with Apple
2. **Webhook Handler** - Processes App Store Server Notifications
3. **Database** - Stores subscription records
4. **Sync Service** - Updates CloudKit with subscription status

**Recommended Stack:**
- **Backend:** Node.js + Express (fast, simple)
- **Database:** PostgreSQL (reliable, good for subscriptions)
- **Hosting:** Heroku, Railway, or DigitalOcean
- **Alternative:** Firebase Cloud Functions + Firestore

---

### Task 5.2: Receipt Validation Endpoint

**Endpoint:** `POST /api/v1/subscriptions/validate`

**Request Body:**
```json
{
  "transactionID": "2000000123456789",
  "deviceID": "ABC123-DEF456"
}
```

**Response:**
```json
{
  "success": true,
  "subscription": {
    "tier": "family",
    "status": "active",
    "expiryDate": "2025-12-11T00:00:00Z",
    "autoRenewEnabled": true
  }
}
```

**Implementation (Node.js/Express):**

```javascript
const express = require('express');
const axios = require('axios');

const router = express.Router();

const APPLE_VERIFY_URL = process.env.PRODUCTION
  ? 'https://buy.itunes.apple.com/verifyReceipt'
  : 'https://sandbox.itunes.apple.com/verifyReceipt';

router.post('/validate', async (req, res) => {
  const { transactionID, deviceID } = req.body;

  try {
    // Validate with Apple
    const response = await axios.post(APPLE_VERIFY_URL, {
      'receipt-data': transactionID,
      'password': process.env.APPLE_SHARED_SECRET,
      'exclude-old-transactions': true
    });

    const { status, latest_receipt_info } = response.data;

    if (status !== 0) {
      return res.status(400).json({ success: false, error: 'Invalid receipt' });
    }

    // Parse subscription info
    const latestReceipt = latest_receipt_info[0];
    const subscription = {
      tier: getTierFromProductID(latestReceipt.product_id),
      status: getStatus(latestReceipt),
      expiryDate: new Date(parseInt(latestReceipt.expires_date_ms)),
      autoRenewEnabled: latestReceipt.auto_renew_status === '1'
    };

    // Save to database
    await saveSubscription(deviceID, subscription);

    // Sync to CloudKit (optional)
    await syncToCloudKit(deviceID, subscription);

    res.json({ success: true, subscription });
  } catch (error) {
    console.error('Validation error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

function getTierFromProductID(productID) {
  if (productID.includes('individual')) return 'individual';
  if (productID.includes('family')) return 'family';
  return 'free';
}

function getStatus(receipt) {
  const expiryDate = new Date(parseInt(receipt.expires_date_ms));
  const now = new Date();

  if (expiryDate > now) return 'active';

  const gracePeriodEnd = new Date(expiryDate.getTime() + 7 * 24 * 60 * 60 * 1000);
  if (now < gracePeriodEnd) return 'grace';

  return 'expired';
}

module.exports = router;
```

---

### Task 5.3: App Store Server Notifications Webhook

**Endpoint:** `POST /api/v1/subscriptions/webhook`

**Purpose:** Receive real-time subscription events from Apple

**Events to Handle:**
- `DID_RENEW` - Subscription renewed
- `DID_FAIL_TO_RENEW` - Renewal failed
- `DID_CHANGE_RENEWAL_STATUS` - Auto-renew toggled
- `EXPIRED` - Subscription expired
- `REFUND` - Subscription refunded

**Implementation:**

```javascript
router.post('/webhook', async (req, res) => {
  const { notification_type, latest_receipt_info, unified_receipt } = req.body;

  try {
    const receipt = latest_receipt_info || unified_receipt?.latest_receipt_info[0];
    const deviceID = receipt.original_transaction_id; // or your mapping

    switch (notification_type) {
      case 'DID_RENEW':
        await handleRenewal(deviceID, receipt);
        break;
      case 'DID_FAIL_TO_RENEW':
        await handleRenewalFailure(deviceID, receipt);
        break;
      case 'EXPIRED':
        await handleExpiration(deviceID, receipt);
        break;
      case 'REFUND':
        await handleRefund(deviceID, receipt);
        break;
    }

    res.status(200).send('OK');
  } catch (error) {
    console.error('Webhook error:', error);
    res.status(500).send('Error');
  }
});
```

---

### Task 5.4: Database Schema

**Table:** `subscriptions`

```sql
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) NOT NULL,
  original_transaction_id VARCHAR(255) UNIQUE NOT NULL,
  transaction_id VARCHAR(255) NOT NULL,
  product_id VARCHAR(255) NOT NULL,
  tier VARCHAR(50) NOT NULL,
  status VARCHAR(50) NOT NULL,
  purchase_date TIMESTAMP NOT NULL,
  expiry_date TIMESTAMP,
  auto_renew_enabled BOOLEAN DEFAULT true,
  last_validated_at TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_device_id ON subscriptions(device_id);
CREATE INDEX idx_original_transaction_id ON subscriptions(original_transaction_id);
CREATE INDEX idx_status ON subscriptions(status);
```

---

### Task 5.5: iOS Integration with Backend

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Services/SubscriptionManager.swift`

**Add Method:** Validate receipt with backend

**Implementation:**

```swift
// Add to SubscriptionManager
private let backendURL = "https://your-backend.com/api/v1"

func validateWithBackend(transaction: Transaction) async throws {
    guard let transactionData = try? JSONEncoder().encode(transaction) else {
        throw SubscriptionError.validationFailed
    }

    let url = URL(string: "\(backendURL)/subscriptions/validate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let requestBody: [String: Any] = [
        "transactionID": String(transaction.id),
        "deviceID": DeviceModeManager.shared.deviceID
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw SubscriptionError.validationFailed
    }

    // Parse response and update local state
    let validationResponse = try JSONDecoder().decode(ValidationResponse.self, from: data)
    print("[SubscriptionManager] ✅ Backend validation successful: \(validationResponse)")
}

struct ValidationResponse: Codable {
    let success: Bool
    let subscription: BackendSubscription?
}

struct BackendSubscription: Codable {
    let tier: String
    let status: String
    let expiryDate: String
    let autoRenewEnabled: Bool
}
```

**Call from updateSubscription():**

```swift
private func updateSubscription(with transaction: Transaction) async {
    // ... existing local update logic

    // Validate with backend
    do {
        try await validateWithBackend(transaction: transaction)
    } catch {
        print("[SubscriptionManager] ⚠️ Backend validation failed: \(error)")
        // Continue with local-only validation
    }
}
```

---

### Task 5.6: Environment Configuration

**File:** Create `.env` for backend

```env
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://user:password@host:5432/dbname
APPLE_SHARED_SECRET=your_shared_secret_from_app_store_connect
CLOUDKIT_CONTAINER_ID=iCloud.com.screentimerewards
CLOUDKIT_API_TOKEN=your_cloudkit_token
```

**iOS Configuration:**

**File:** `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Configuration/Config.swift`

```swift
import Foundation

enum Config {
    static var backendURL: String {
        #if DEBUG
        return "http://localhost:3000/api/v1"
        #else
        return "https://api.screentimerewards.com/api/v1"
        #endif
    }
}
```

---

## 📦 Phase 6: Testing & Polish (Days 17-19)

### Overview
Comprehensive testing and final polish before submission.

---

### Task 6.1: StoreKit Testing Scenarios

**Setup:**
1. Xcode → Product → Scheme → Edit Scheme
2. Run → Options → StoreKit Configuration: Configuration.storekit
3. Debug → StoreKit → Enable/Disable Features

**Test Cases:**

#### TC1: Free Trial Flow
1. Launch app first time
2. Verify trial starts automatically
3. Check TrialBannerView shows "30 days remaining"
4. Create challenges (should work)
5. Use StoreKit time acceleration to advance 31 days
6. Verify grace period begins
7. Advance 8 more days
8. Verify lockout screen appears

#### TC2: Purchase Flow
1. During trial, tap "Subscribe Now"
2. Select Individual tier
3. Tap "Start Free Trial"
4. Complete purchase (StoreKit sandbox)
5. Verify subscription status = "Active"
6. Verify banner disappears

#### TC3: Restore Purchases
1. Delete app
2. Reinstall
3. Launch app (trial starts)
4. Go to Settings → Subscription
5. Tap "Restore Purchases"
6. Verify subscription restored
7. Verify access granted

#### TC4: Upgrade Flow
1. Subscribe to Individual tier
2. Pair 1 child device (should work)
3. Try pairing 2nd device (should fail)
4. Upgrade to Family tier
5. Retry pairing 2nd device (should work)

#### TC5: Expiration & Renewal
1. Subscribe to Individual tier
2. Use StoreKit time acceleration to advance 31 days
3. Verify subscription expires
4. Verify grace period begins
5. Renew subscription
6. Verify status returns to "Active"

#### TC6: Offline Behavior
1. Subscribe to Individual tier
2. Enable Airplane Mode
3. Force quit app
4. Launch app
5. Verify cached subscription allows access
6. Disable Airplane Mode
7. Verify subscription validates with backend

---

### Task 6.2: Feature Gating Tests

**Test Matrix:**

| Feature | Trial | Individual | Family | Expired |
|---------|-------|-----------|--------|---------|
| Create Challenge | ✅ | ✅ | ✅ | ❌ |
| Pair 1 Child | ✅ | ✅ | ✅ | ❌ |
| Pair 2+ Children | ✅ | ❌ | ✅ | ❌ |
| View Analytics | ✅ | ✅ | ✅ | ❌ |
| View History | ✅ | ✅ | ✅ | ✅ |
| Settings Access | ✅ | ✅ | ✅ | ✅ |

**Validation:**
- Test each cell in matrix
- Verify paywall shows when ❌
- Verify feature works when ✅

---

### Task 6.3: UI/UX Polish

**Checklist:**

- [ ] Paywall animations smooth
- [ ] Trial banner not intrusive
- [ ] Grace period warnings clear
- [ ] Lockout screen user-friendly
- [ ] Subscription management easy to find
- [ ] All text reviewed for clarity
- [ ] Dark mode support verified
- [ ] iPad layout tested
- [ ] Accessibility labels added
- [ ] VoiceOver tested

---

### Task 6.4: Edge Cases

**Test Scenarios:**

1. **App Store Outage**
   - Disable network during purchase
   - Verify graceful error handling
   - Verify retry mechanism

2. **Multiple Devices**
   - Subscribe on Device A
   - Launch Device B with same Apple ID
   - Verify subscription syncs via CloudKit

3. **Family Sharing**
   - Enable Family Sharing for Family tier
   - Add family member
   - Verify they get access

4. **Refund**
   - Purchase subscription
   - Request refund via App Store
   - Verify app handles refund notification
   - Verify access revoked

5. **Downgrade**
   - Subscribe to Family tier
   - Downgrade to Individual tier
   - Verify child device limit enforced
   - Verify excess devices paused

---

## 📦 Phase 7: App Store Submission (Days 20-21)

### Overview
Configure App Store Connect and prepare for submission.

---

### Task 7.1: App Store Connect Configuration

**Subscriptions Setup:**

1. **Go to:** App Store Connect → Your App → Monetization → Subscriptions
2. **Create Subscription Group:** "ScreenTime Premium"
3. **Add Individual Tier:**
   - Product ID: `com.screentimerewards.individual.monthly`
   - Reference Name: Individual Monthly
   - Subscription Duration: 1 Month
   - Price: $7.99 (Tier 8)
   - Free Trial: 30 days
   - Introductory Offer: Free for 1 month

4. **Add Family Tier:**
   - Product ID: `com.screentimerewards.family.monthly`
   - Reference Name: Family Monthly
   - Subscription Duration: 1 Month
   - Price: $12.99 (Tier 14)
   - Free Trial: 30 days
   - Introductory Offer: Free for 1 month
   - Family Sharing: Enabled

5. **App Store Server Notifications:**
   - Version: Version 2
   - URL: `https://your-backend.com/api/v1/subscriptions/webhook`
   - Shared Secret: Generate and save to `.env`

---

### Task 7.2: App Privacy & Metadata

**Privacy Details:**

Add to App Privacy section:
- **Purchases** - Used for subscription management
- **Device ID** - Used for account syncing
- **Usage Data** - Used for learning analytics
- **Linked to User:** Yes (via Apple ID)

**App Description:**

```
ScreenTime Rewards helps families balance screen time and learning.

Create daily quests, reward learning with screen time, and watch your children develop healthy digital habits.

FEATURES:
• Daily Quest challenges with customizable goals
• Learning app tracking and rewards
• Family dashboard for multiple children
• Streak bonuses for consistency
• Detailed learning analytics

SUBSCRIPTION:
• 30-day free trial with full access
• Individual plan: $7.99/month (1 child)
• Family plan: $12.99/month (up to 5 children)
• Cancel anytime

Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings.

Terms: https://screentimerewards.com/terms
Privacy: https://screentimerewards.com/privacy
```

**Keywords:**
screen time, parental controls, learning rewards, family app, kids education, digital wellness, child device management, screen time limits

---

### Task 7.3: App Review Preparation

**Test Account:**

Create test account in App Store Connect:
- Email: test@screentimerewards.com
- Password: TestAccount123!
- Notes: Pre-configured with Family tier subscription for review

**App Review Notes:**

```
SUBSCRIPTION TESTING:

1. Launch app - 30-day trial starts automatically
2. No payment required during trial
3. Test accounts provided with active subscriptions

FAMILY CONTROLS PERMISSION:

This app requires FamilyControls framework permission to:
- Monitor screen time usage
- Track learning app activity
- Enable reward app access

Permission requested during onboarding (Step 2).

SUBSCRIPTION TIERS:

Individual ($7.99/mo):
- 1 child device supported
- Unlimited challenges

Family ($12.99/mo):
- Up to 5 child devices
- All Individual features
- Advanced analytics

Both tiers include 30-day free trial.

DEMO FLOW:

1. Complete onboarding (4 steps)
2. Select Parent Mode
3. Create a Daily Quest challenge
4. View subscription status in Settings
5. Test child mode on paired device (optional)

Test account has Family tier active for full testing.
```

**Screenshots:**

Prepare for App Store:
1. Onboarding screens (4 steps)
2. Parent mode dashboard
3. Challenge creation
4. Child mode dashboard
5. Subscription paywall
6. Analytics view

Sizes: iPad Pro 12.9", iPhone 16 Pro Max

---

### Task 7.4: Final Checklist

**Pre-Submission:**

- [ ] All features tested on physical devices
- [ ] Subscription flow tested in sandbox
- [ ] Backend deployed and operational
- [ ] Webhook receiving notifications
- [ ] Database configured and accessible
- [ ] CloudKit sync verified
- [ ] Crash reports reviewed (no critical issues)
- [ ] Performance tested (no memory leaks)
- [ ] Battery usage optimized
- [ ] App size under 200MB
- [ ] Privacy policy updated
- [ ] Terms of service updated
- [ ] Support email configured
- [ ] App Store screenshots prepared
- [ ] App preview videos created (optional)
- [ ] Release notes written
- [ ] Version number updated
- [ ] Build number incremented

---

## 📊 Success Metrics & Monitoring

### Key Performance Indicators

**Trial Conversion:**
- Trial Start Rate: Target 80%+
- Trial to Paid Conversion: Target 15-25%
- Free to Individual: Target 60%
- Free to Family: Target 40%

**Retention:**
- Month 1 Churn: <10%
- Month 3 Churn: <20%
- Month 6 Churn: <30%

**Revenue:**
- ARPU (Average Revenue Per User): $8-10/month
- LTV (Lifetime Value): $100-150
- CAC (Customer Acquisition Cost): <$30

### Analytics Events

**Track in Firebase/Analytics:**

```swift
// Trial events
Analytics.logEvent("trial_started", parameters: nil)
Analytics.logEvent("trial_converted", parameters: [
    "tier": tier.rawValue,
    "days_into_trial": daysElapsed
])

// Purchase events
Analytics.logEvent("purchase_initiated", parameters: ["tier": tier])
Analytics.logEvent("purchase_completed", parameters: ["tier": tier, "price": price])
Analytics.logEvent("purchase_failed", parameters: ["error": error])

// Feature usage
Analytics.logEvent("challenge_created", parameters: ["has_subscription": hasAccess])
Analytics.logEvent("child_device_paired", parameters: ["device_count": count])

// Churn signals
Analytics.logEvent("subscription_cancelled", parameters: ["tier": tier, "reason": reason])
Analytics.logEvent("grace_period_entered", parameters: nil)
Analytics.logEvent("subscription_expired", parameters: ["tier": tier])
```

### Monitoring & Alerts

**Set Up Alerts For:**

1. **High Error Rate**
   - StoreKit errors >5%
   - Backend validation failures >10%
   - CloudKit sync failures >5%

2. **Low Conversion**
   - Trial conversion <10%
   - Paywall bounce rate >70%

3. **Technical Issues**
   - App crashes >0.1%
   - ANR (Application Not Responding) >0.05%
   - Receipt validation latency >5s

4. **Revenue**
   - Daily revenue drop >20%
   - Refund rate >5%
   - Subscription renewals <90%

---

## 🚨 Rollback Plan

**If Issues Arise Post-Launch:**

### Minor Issues (UI bugs, analytics)
- Fix and submit update
- 1-3 day turnaround

### Major Issues (subscription not working)
1. Disable subscription requirement server-side
2. Grant free access to all users temporarily
3. Fix issue
4. Re-enable subscriptions
5. Honor free period for affected users

### Critical Issues (app crashes)
1. Immediately disable new user signups
2. Emergency patch release
3. Coordinate with Apple for expedited review

---

## 📞 Support Strategy

### Common User Issues

**"I can't restore my subscription"**
- Solution: Verify same Apple ID used for purchase
- Check if subscription active in App Store
- Clear app cache and retry

**"I was charged but don't have access"**
- Solution: Check backend validation logs
- Manually validate receipt
- Grant temporary access while investigating

**"My trial ended but I didn't get notified"**
- Solution: Verify notification settings
- Check grace period status
- Offer extension if first offense

**"I want to cancel"**
- Solution: Direct to App Store → Subscriptions
- Explain cancellation takes effect at end of period
- Offer to address concerns

### Support Channels

1. **In-App:** Help section with FAQs
2. **Email:** support@screentimerewards.com
3. **Twitter:** @ScreenTimeApp
4. **Priority:** Family tier subscribers

---

## 📝 Documentation Deliverables

**For User:**
1. Subscription FAQ page
2. Terms of Service
3. Privacy Policy
4. Help center articles

**For Dev Team:**
1. This implementation plan
2. Backend API documentation
3. Database schema documentation
4. Monitoring playbook
5. Incident response guide

---

## ✅ Implementation Sign-Off

**Dev Agent Responsibilities:**
- [ ] Complete Phases 1-6 implementation
- [ ] All tests passing
- [ ] Code reviewed and documented
- [ ] Performance benchmarks met
- [ ] Security audit passed
- [ ] Backend deployed
- [ ] Monitoring configured

**Planner Review Checkpoints:**
- [x] Phase 1 complete (Review foundation)
- [x] Phase 2 complete (Review subscription logic)
- [x] Phase 3 complete (Review UI/UX)
- [x] Phase 4 complete (Review feature gates)
- [ ] Phase 5 complete (Review backend)
- [ ] Phase 6 complete (Review testing)
- [ ] Final approval for App Store submission

---

## 🎉 Next Steps After Implementation

1. **Soft Launch** - Release to small user segment (10%)
2. **Monitor Metrics** - Watch conversion, churn, errors
3. **Iterate** - Adjust pricing, trial length based on data
4. **Marketing** - Promote subscription benefits
5. **Support** - Handle user questions promptly
6. **Optimize** - A/B test paywall designs
7. **Scale** - Increase user segment to 100%

---

**End of Implementation Plan**

*This document is a living specification. Update as implementation progresses and requirements evolve.*

---

**Questions or Issues?**
Contact the Planning Agent for clarifications or adjustments to this plan.
