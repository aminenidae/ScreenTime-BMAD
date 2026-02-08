# Paywall Compliance Fix - Implementation Plan

## Overview
Fix 3 critical App Store compliance violations in subscription paywalls to avoid rejection. Estimated time: 2-3 days.

Full assessment document: `/Users/ameen/Documents/ScreenTime-BMAD/docs/paywall-compliance-assessment.md`

---

## Strategic Decision: Option B - Add Real Annual Products ✅

**Current State:** StoreKit has monthly-only products, but Screen6 UI shows annual pricing with hardcoded values.

**CHOSEN APPROACH: Option B - Both Monthly and Annual Plans**

We will offer users TWO subscription options:
1. **Monthly Plan** - $12.99/month (existing product)
2. **Annual Plan** - NEW product to be created

This requires:
- Create annual product in App Store Connect
- Add annual product to Configuration.storekit
- Update SubscriptionTier model to handle both billing periods
- Fix purchase logic to use correct products based on user selection
- ⏱️ 4-6 hours + App Store Connect setup

---

## Implementation Plan

### STEP 0: Add Annual Product to StoreKit Configuration

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Configuration.storekit`

#### Add Annual Subscription Product

Add this to the `subscriptions` array in the "ScreenTime Premium" subscription group (after the Family Monthly product):

```json
{
  "adHocOffers" : [],
  "codeOffers" : [],
  "displayPrice" : "59.99",
  "familyShareable" : true,
  "groupNumber" : 3,
  "internalID" : "6469881403",
  "introductoryOffer" : {
    "internalID" : "70B78599",
    "numberOfPeriods" : 1,
    "paymentMode" : "free",
    "subscriptionPeriod" : "P1M"
  },
  "localizations" : [
    {
      "description" : "Family plan for up to 5 child devices - billed annually",
      "displayName" : "Family Plan (Annual)",
      "locale" : "en_US"
    }
  ],
  "productID" : "com.screentimerewards.family.yearly",
  "recurringSubscriptionPeriod" : "P1Y",
  "referenceName" : "Family Annual",
  "subscriptionGroupID" : "20776E67",
  "type" : "RecurringSubscription"
}
```

**Key Points:**
- Product ID: `com.screentimerewards.family.yearly`
- Recurring period: `P1Y` (1 year)
- Display price: $59.99 (or adjust as needed)
- Same 1-month free trial as monthly product
- Family Shareable enabled
- Group number 3 (ranks after monthly plans)

**Note:** You'll also need to create this product in App Store Connect with matching details.

---

### STEP 0B: Update SubscriptionTier Model

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Models/SubscriptionTier.swift`

Currently, the model doesn't distinguish between monthly and annual billing. We need to add support for billing periods.

#### Option 1: Create New Enum for Billing Period (Recommended)

Add after SubscriptionTier enum:

```swift
enum BillingPeriod: String, Codable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Annual"
        }
    }
}

// Update SubscriptionTier to include billing period methods
extension SubscriptionTier {
    func productID(for period: BillingPeriod) -> String {
        switch self {
        case .free:
            return ""
        case .individual:
            return period == .monthly ? "com.screentimerewards.individual.monthly" : "com.screentimerewards.individual.yearly"
        case .family:
            return period == .monthly ? "com.screentimerewards.family.monthly" : "com.screentimerewards.family.yearly"
        }
    }

    var monthlyProductID: String {
        productID(for: .monthly)
    }

    var yearlyProductID: String {
        productID(for: .yearly)
    }
}
```

#### Option 2: Add Separate Product Plan Enum

Update the existing `SubscriptionPlanOption` enum (if it exists) or create:

```swift
enum SubscriptionPlanOption: String, Codable {
    case monthly = "com.screentimerewards.family.monthly"
    case annual = "com.screentimerewards.family.yearly"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }

    var billingPeriod: BillingPeriod {
        switch self {
        case .monthly: return .monthly
        case .annual: return .yearly
        }
    }
}
```

---

### STEP 1: Create Reusable Disclosure Component
**New File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/Components/SubscriptionDisclosureText.swift`

```swift
import SwiftUI

struct SubscriptionDisclosureText: View {
    let price: String
    let billingPeriod: String = "month"

    var body: some View {
        VStack(spacing: 8) {
            Text("Payment will be charged to your Apple Account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Your account will be charged \(price) for renewal within 24 hours prior to the end of the current period. Any unused portion of a free trial will be forfeited when you purchase a subscription.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text("Subscriptions may be managed and auto-renewal turned off in")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Link("Account Settings", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }
            .multilineTextAlignment(.center)
        }
    }
}
```

---

### STEP 2: Fix Screen6_TrialPaywallView.swift

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/Screens/Screen6_TrialPaywallView.swift`

#### Change 2.1: Update AnnualPlanCard to Use Real Annual Product (Lines 210-234)

**Replace AnnualPlanCard pricing section (lines 210-234) with:**

```swift
// Price from StoreKit - ANNUAL PRODUCT
VStack(alignment: .leading, spacing: 2) {
    if let annualProduct = subscriptionManager.annualProduct {
        // Monthly equivalent price
        let monthlyEquivalent = (annualProduct.price as NSDecimalNumber).doubleValue / 12.0
        Text(String(format: "$%.2f / month", monthlyEquivalent))
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            .textCase(.uppercase)

        Text("\(annualProduct.displayPrice) billed annually")
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            .textCase(.uppercase)

        // Show savings if monthly product exists
        if let monthlyProduct = subscriptionManager.monthlyProduct {
            let monthlyCost = (monthlyProduct.price as NSDecimalNumber).doubleValue * 12.0
            let annualCost = (annualProduct.price as NSDecimalNumber).doubleValue
            let savings = monthlyCost - annualCost
            let percentSavings = (savings / monthlyCost) * 100.0

            HStack(spacing: 6) {
                Text(String(format: "$%.2f", monthlyCost))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .strikethrough()

                Text(String(format: "%.0f%% off", percentSavings))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .textCase(.uppercase)
            }
        }
    } else {
        Text("Loading...")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
    }
}
```

**Note:** This dynamically calculates monthly equivalent price and savings from StoreKit products.

#### Change 2.2: Update MonthlyPlanCard to Use Monthly Product (Line 289)

**Replace lines 288-297 with:**

```swift
VStack(alignment: .leading, spacing: 6) {
    // Price from StoreKit - MONTHLY PRODUCT
    if let monthlyProduct = subscriptionManager.monthlyProduct {
        Text(monthlyProduct.displayPrice)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            .textCase(.uppercase)

        Text("per month")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            .textCase(.uppercase)
    } else {
        Text("Loading...")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
    }
}
```

#### Change 2.3: Add Privacy/Terms Links (After line 105)

**Replace lines 98-105 (legal fine print) with:**

```swift
VStack(spacing: 8) {
    // Complete Schedule 2 disclosures - use selected plan's product
    if let product = (selectedPlan == .annual ? subscriptionManager.annualProduct : subscriptionManager.monthlyProduct) {
        SubscriptionDisclosureText(price: product.displayPrice)
            .padding(.horizontal, layout.horizontalPadding)
    }

    // Privacy and Terms links
    HStack(spacing: 16) {
        Link("Terms of Service", destination: URL(string: "https://screentimerewards.com/terms")!)
        Text("•")
        Link("Privacy Policy", destination: URL(string: "https://screentimerewards.com/privacy")!)
    }
    .font(.system(size: 11))
    .foregroundColor(.secondary)
}
.padding(.bottom, layout.isLandscape ? 8 : 12)
```

#### Change 2.4: Fix Purchase Button Logic for Annual vs Monthly

**Update purchase functions (Lines 150-163):**

```swift
private func purchaseAnnual() {
    guard let product = subscriptionManager.annualProduct else {
        purchaseError = "Unable to load annual subscription. Please try again."
        return
    }
    purchase(product)
}

private func purchaseMonthly() {
    guard let product = subscriptionManager.monthlyProduct else {
        purchaseError = "Unable to load monthly subscription. Please try again."
        return
    }
    purchase(product)
}
```

**These now use different products based on the user's selection.**

---

### STEP 3: Fix SubscriptionPaywallView.swift

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionPaywallView.swift`

#### Change 3.1: Replace Legal Text (Lines 223-238)

**Replace entire legalText computed property with:**

```swift
var legalText: some View {
    VStack(spacing: 12) {
        // Complete Schedule 2 disclosures
        if let product = subscriptionManager.product(for: selectedTier) {
            SubscriptionDisclosureText(price: product.displayPrice)
        }

        // Privacy and Terms links
        HStack(spacing: 16) {
            Link("Terms of Service", destination: URL(string: "https://screentimerewards.com/terms")!)
            Text("•")
            Link("Privacy Policy", destination: URL(string: "https://screentimerewards.com/privacy")!)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
    .multilineTextAlignment(.center)
}
```

#### Change 3.2: Improve Restore Button Visibility (Lines 217-220)

**Replace:**

```swift
var restoreButton: some View {
    Button {
        Task {
            await restore()
        }
    } label: {
        Text("Restore Purchases")
            .font(.system(size: 16, weight: .medium))  // Increased from 14
            .foregroundColor(.primary.opacity(0.7))     // More visible than .secondary
    }
}
```

---

### STEP 4: Update SubscriptionManager for Monthly + Annual Products

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Services/SubscriptionManager.swift`

#### Change 4.1: Add Computed Properties for Monthly and Annual Products (After line 21)

```swift
// Computed properties for easy access to specific products
var monthlyProduct: Product? {
    products.first { $0.id == "com.screentimerewards.family.monthly" }
}

var annualProduct: Product? {
    products.first { $0.id == "com.screentimerewards.family.yearly" }
}
```

#### Change 4.2: Add Error State (After line 15)

```swift
@Published var productLoadError: String?
```

#### Change 4.3: Update productIDs to Include Annual (Around line 35-40)

**Find the productIDs property and update it:**

```swift
private var productIDs: [String] {
    [
        "com.screentimerewards.individual.monthly",
        "com.screentimerewards.family.monthly",
        "com.screentimerewards.family.yearly"  // ADD THIS LINE
    ]
}
```

#### Change 4.4: Update loadProducts() with Error Handling (Lines 42-57)

**Replace with:**

```swift
func loadProducts() async {
    do {
        products = try await Product.products(for: productIDs)
        productLoadError = nil
        #if DEBUG
        print("[SubscriptionManager] Loaded \(products.count) products")
        for product in products {
            print("  - \(product.id): \(product.displayPrice)")
        }
        #endif
    } catch {
        productLoadError = "Unable to load subscription options. Please check your connection and try again."
        print("[SubscriptionManager] Failed to load products: \(error)")
    }
}
```

#### Change 4.3: Display Error in Paywalls

**Add to SubscriptionPaywallView.swift after featureList (around line 181):**

```swift
// Product load error
if let error = subscriptionManager.productLoadError {
    VStack(spacing: 12) {
        Text(error)
            .font(.system(size: 14))
            .foregroundColor(.red)
            .multilineTextAlignment(.center)

        Button {
            Task {
                await subscriptionManager.loadProducts()
            }
        } label: {
            Text("Retry")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(AppTheme.vibrantTeal)
                .cornerRadius(8)
        }
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.red.opacity(0.1))
    )
}
```

**Add same error handling to Screen6_TrialPaywallView.swift after line 96**

---

## Files to Modify

### Must Edit (StoreKit Configuration):
1. `ScreenTimeRewardsProject/ScreenTimeRewards/Configuration.storekit`
   - Add annual product: `com.screentimerewards.family.yearly`
   - Set recurring period to P1Y
   - Configure pricing (e.g., $59.99)
   - Add 1-month free trial

### Must Edit (Models):
2. `ScreenTimeRewardsProject/ScreenTimeRewards/Models/SubscriptionTier.swift`
   - Add BillingPeriod enum
   - Add productID(for:) method
   - Add computed properties for monthly/yearly product IDs

### Create New (Component):
3. `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/Components/SubscriptionDisclosureText.swift` (new file)
   - Reusable Schedule 2 disclosure component

### Must Edit (Views):
4. `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Onboarding/Screens/Screen6_TrialPaywallView.swift`
   - Lines 210-234: Update AnnualPlanCard to use annualProduct from StoreKit
   - Line 289: Update MonthlyPlanCard to use monthlyProduct from StoreKit
   - Lines 98-105: Replace with complete disclosures + Privacy/Terms links
   - Lines 150-163: Fix purchase logic to use correct products (annual vs monthly)

5. `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionPaywallView.swift`
   - Lines 223-238: Replace with complete disclosures
   - Lines 217-220: Improve restore button visibility
   - After line 181: Add error handling UI

### Must Edit (Services):
6. `ScreenTimeRewardsProject/ScreenTimeRewards/Services/SubscriptionManager.swift`
   - After line 15: Add productLoadError property
   - After line 21: Add monthlyProduct and annualProduct computed properties
   - Around line 35-40: Add annual product ID to productIDs array
   - Lines 42-57: Update loadProducts() with error handling

---

## Testing Checklist

After implementing changes:

- [ ] Run app in simulator - verify no build errors
- [ ] Check both paywalls display prices from StoreKit (not hardcoded)
- [ ] Verify Privacy Policy and Terms links work in Screen6
- [ ] Verify complete disclosure text appears in both paywalls
- [ ] Test restore button is visible and clickable
- [ ] Test product load error (disconnect network, check error message displays)
- [ ] Test in different StoreKit configurations (change displayPrice)
- [ ] Verify text is readable in both light and dark mode
- [ ] Test on iPhone SE (small screen) and iPhone 15 Pro Max (large screen)

---

## Compliance Status After Fix

| Requirement | Before | After |
|-------------|--------|-------|
| Prices from StoreKit | ❌ Hardcoded | ✅ Dynamic |
| Complete Schedule 2 disclosures | ❌ Missing | ✅ Complete |
| Privacy/Terms in Screen6 | ❌ Missing | ✅ Present |
| Restore button visibility | ⚠️ Low | ✅ Improved |
| Subscription management link | ❌ Missing | ✅ Present |
| Product load error handling | ❌ None | ✅ Added |

**Result:** Full compliance with App Store requirements

---

## Estimated Time

- Step 0 (Add annual product to StoreKit config): 30 minutes
- Step 0B (Update SubscriptionTier model): 30 minutes
- Step 1 (Create disclosure component): 30 minutes
- Step 2 (Fix Screen6 with annual product logic): 2-3 hours
- Step 3 (Fix SubscriptionPaywallView): 1 hour
- Step 4 (Update SubscriptionManager for monthly + annual): 1 hour
- Testing: 1-2 hours

**Total: 6-8 hours** (implementing Option B with both monthly and annual products)

**Plus:** App Store Connect setup time (creating annual product in production)
