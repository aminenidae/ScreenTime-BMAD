# Subscription Audit — Builds 21–23
**Date:** 2026-04-04  
**Branch:** `feature/streamline-usage-recording`  
**Trigger:** TestFlight Build 21 — Solo annual purchase completed but app remained on lockout screen

---

## Summary

A TestFlight subscription validation session uncovered **7 distinct bugs** across the subscription flow, parent device authentication, and App Store Connect configuration. Bugs were fixed across Builds 22 and 23. One critical compliance issue (subscription group structure) requires App Store Connect action and has no code fix.

---

## Build History

| Build | Changes |
|---|---|
| 21 | Shipped to TestFlight. Purchase confirmed by StoreKit but lockout screen persisted. |
| 22 | Fix entitlement ID mismatch + RevenueCat logging + purchase() resilience. Also fixed Settings tab bypass (ParentDeviceAuthView). |
| 23 | Fix DeviceModeManager missing from SwiftUI environment (crash on Settings tab). Fix dashboard infinite loading gate. |

---

## Bug 1 — Entitlement ID Mismatch (PRIMARY ROOT CAUSE)

**Symptom:** Subscription purchased successfully (StoreKit confirmed, RevenueCat recorded), but app stayed on lockout screen.

**Root cause:** `RevenueCatConfig.swift` had entitlement identifiers that didn't match the names configured in the RevenueCat dashboard.

| Code (was) | RevenueCat dashboard (actual) |
|---|---|
| `"premium_solo"` | `"Solo"` |
| `"premium_individual"` | `"Individual"` |
| `"premium_family"` | `"Family"` |

`updateTierFromCustomerInfo()` in `SubscriptionManager.swift` looked up `info.entitlements["premium_solo"]` which always returned `nil`. `hasAccess` was always `false`.

**Fix:** `RevenueCatConfig.swift`
```swift
static let premiumSolo = "Solo"
static let premiumIndividual = "Individual"
static let premiumFamily = "Family"
```

---

## Bug 2 — Purchase Dismissed Sheet on Failure

**Symptom:** If purchase completed but entitlement wasn't granted, paywall and lockout views called `dismiss()`/`finishFlow()` unconditionally — user saw no error and was left on lockout screen with no explanation.

**Fix:** `ChildSubscriptionView.swift` and `SubscriptionPaywallView.swift` — added `hasAccess` check before dismissing:
```swift
try await subscriptionManager.purchase(package)
await MainActor.run {
    if subscriptionManager.hasAccess {
        onComplete?()
        dismiss()
    } else {
        errorMessage = "Purchase recorded but activation is pending. Please tap 'Restore Purchases' or restart the app."
        showError = true
    }
}
```

---

## Bug 3 — userCancelled Not Handled

**Symptom:** RevenueCat's `purchase(package:)` returns a struct with `userCancelled: Bool` rather than throwing when the user cancels. Code never checked this flag, so cancelling the purchase sheet called `dismiss()` as if the purchase succeeded.

**Fix:** `SubscriptionManager.swift` — added guard and auto-restore fallback:
```swift
func purchase(_ package: Package) async throws {
    let result = try await Purchases.shared.purchase(package: package)
    guard !result.userCancelled else {
        throw SubscriptionError.userCancelled
    }
    customerInfo = result.customerInfo
    updateTierFromCustomerInfo()
    if !hasAccess {
        // Auto-restore as fallback (handles sandbox race conditions)
        customerInfo = try await Purchases.shared.restorePurchases()
        updateTierFromCustomerInfo()
    }
    await updateLocalSubscription(from: customerInfo)
}
```

---

## Bug 4 — No RevenueCat Logging in TestFlight

**Symptom:** RevenueCat debug logging was gated on `#if DEBUG` only — TestFlight builds (release config) produced no RevenueCat output, making subscription issues impossible to diagnose from device logs.

**Fix:** `RevenueCatConfig.swift` — added sandbox receipt detection for TestFlight:
```swift
static var shouldEnableDebugLogging: Bool {
    #if DEBUG
    return true
    #else
    return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    #endif
}
```

`SubscriptionManager.swift` — changed logging initialization to use this flag:
```swift
if RevenueCatConfig.shouldEnableDebugLogging {
    Purchases.logLevel = .info
}
```

---

## Bug 5 — Settings Tab Never Visible (Parent Device)

**Symptom:** On a parent device, after PIN authentication, the Settings tab never appeared. The only visible content was `ParentRemoteDashboardView`. There was no way to access subscription management before pairing a child device.

**Root cause:** `ParentDeviceAuthView.swift` presented `ParentRemoteDashboardView()` directly instead of `ParentTabView()`. The tab bar (which includes Settings) was completely bypassed.

**Fix:** `ParentDeviceAuthView.swift` line 33:
```swift
// Was:
ParentRemoteDashboardView()

// Fixed:
ParentTabView()
```

`ParentTabView` contains both the Family Dashboard tab and the Settings tab, making subscription management accessible even before pairing.

---

## Bug 6 — App Crash on Settings Tab (Missing EnvironmentObject)

**Symptom:** Tapping the Settings tab crashed the app immediately:
```
SwiftUICore/EnvironmentObject.swift:93: Fatal error: No ObservableObject of type DeviceModeManager found.
```

**Root cause:** `SubscriptionManagementView` (inside Settings tab) uses `@EnvironmentObject var deviceModeManager: DeviceModeManager`. `DeviceModeManager.shared` was declared as `@StateObject` in `ScreenTimeRewardsApp.swift` but never injected into the SwiftUI environment.

**Fix:** `ScreenTimeRewardsApp.swift` — added `.environmentObject(modeManager)` to root view:
```swift
LaunchScreenView()
    .environment(\.managedObjectContext, persistenceController.container.viewContext)
    .environmentObject(viewModel)
    .environmentObject(sessionManager)
    .environmentObject(subscriptionManager)
    .environmentObject(modeManager)  // ADDED — was missing
```

---

## Bug 7 — Dashboard Infinite Loading (Fresh Install)

**Symptom:** On first launch with no paired devices, `ParentRemoteDashboardView` showed a full-screen `SyncingOverlayView` ("Loading Family Dashboard...") that blocked the entire UI for 10–15 seconds while CloudKit's `allRecordZones()` call completed. No content was visible; the user could not interact with anything.

**Root cause:** The view had a loading gate:
```swift
private var showInitialLoadingOverlay: Bool {
    viewModel.isLoading && viewModel.linkedChildDevices.isEmpty
}
```
On a fresh install with no paired devices, this condition is always true during the initial CloudKit fetch, producing a blank locked screen.

**Fix:** `ParentRemoteDashboardView.swift` — removed the loading gate entirely. Empty state now renders immediately; CloudKit updates it in the background when ready.

---

## Critical Compliance Issue — Three Separate Subscription Groups

**Discovery:** During Test 2, purchasing Individual Monthly on a device that already had Family Annual active showed **both subscriptions simultaneously active** in RevenueCat. Investigation revealed the App Store Connect setup:

| Group name | Products |
|---|---|
| Solo | SoloMonthly, com.screentimerewards.solo.annual |
| Individual | IndividualMonthly, com.screentimerewards.individual.annual |
| Family | FamilyMonthly, com.screentimerewards.family.annual |

Apple only enforces mutual exclusivity **within a single subscription group** (guideline 3.1.2(b)). With 3 groups, a user can simultaneously subscribe to all three tiers and be billed for all three.

**This is a billing disaster and a compliance violation — requires App Store Connect action.**

### Required Fix (App Store Connect, no code changes)

1. Create one new unified group — suggested name: **"Brain Coinz"**
2. Recreate all 6 products inside this single group (cannot move products between groups; delete and recreate since no real production subscribers exist)
3. Set upgrade/downgrade order: `Solo < Individual < Family`
4. Delete the 3 old separate groups
5. Update RevenueCat dashboard to reflect new product IDs (if changed) and verify entitlement mappings

**Code impact:** None. Product IDs and entitlement names in `RevenueCatConfig.swift` are correct as-is.

### Verification steps after consolidation
1. Sandbox: purchase Solo Annual
2. Purchase Individual Monthly from same account → Solo should auto-cancel
3. Purchase Family Annual → Individual should auto-cancel
4. RevenueCat should show only one active subscription at any time

---

## Files Changed

| File | Change |
|---|---|
| `Services/RevenueCatConfig.swift` | Entitlement IDs: `"premium_*"` → `"Solo"/"Individual"/"Family"`. Added `shouldEnableDebugLogging`. |
| `Services/SubscriptionManager.swift` | Added `userCancelled` guard, auto-restore fallback, TestFlight logging. |
| `Views/Subscription/ChildSubscriptionView.swift` | Added `hasAccess` check before dismiss. UI: hero image, weekly pricing. |
| `Views/Subscription/SubscriptionPaywallView.swift` | Added `hasAccess` check before `finishFlow()`. |
| `Views/Authentication/ParentDeviceAuthView.swift` | Line 33: `ParentRemoteDashboardView()` → `ParentTabView()`. |
| `ScreenTimeRewardsApp.swift` | Added `.environmentObject(modeManager)` to root view. |
| `Views/ParentRemoteDashboardView.swift` | Removed initial loading gate; empty state now shows immediately. |
| `ScreenTimeRewards.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION`: 21 → 22 → 23. |

---

## Pending Actions

- [ ] **App Store Connect**: Consolidate 3 subscription groups into 1 "Brain Coinz" group (see above)
- [ ] **RevenueCat**: Re-verify entitlement and offering mappings after group consolidation
- [ ] **TestFlight**: Archive and upload Build 23 for proper end-to-end subscription testing
- [ ] **Verify cancellation flow**: Sandbox test confirms Solo → Individual → Family cancels prior tier
- [ ] **Investigate "Free Trial Active" status**: Subscription management screen showed "Free Trial Active" for Family Annual — confirm whether intro offer is configured or if it's a status mapping bug
- [ ] **Consider native subscription management**: Replace `https://apps.apple.com/account/subscriptions` link with `StoreKit.showManageSubscriptions(in:)` API for better in-app experience
