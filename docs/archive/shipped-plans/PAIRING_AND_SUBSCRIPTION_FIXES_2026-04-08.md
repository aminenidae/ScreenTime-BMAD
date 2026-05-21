# Pairing & Subscription Fixes

**Date:** 2026-04-08
**Branch:** feature/streamline-usage-recording
**Status:** Implemented

---

## Overview

Three bugs were discovered and fixed during TestFlight testing of build 26, all related to child device pairing and subscription state management.

---

## Bug 1: Child Pairing Blocked — "Maximum of 0 Parent Devices Reached"

### Symptom
On the child device Pairing Status screen:
- UI showed "Maximum of 0 parent devices reached." and "0/0 Connected Grown-Ups"
- Scan QR button was enabled (correct)
- After scanning, a "Connection Error" fired: *"This child device is already paired with the maximum number of parent devices (2)."*

### Root Cause
`SubscriptionManager.currentTier` on the child device was resolving to `.solo` (e.g., from a stale sandbox entitlement or shared Apple ID during TestFlight). `SubscriptionTier.solo.parentDeviceLimitPerChild = 0`, so `canAnotherParentPair()` evaluated `0 < 0 = false` and threw `maxParentsReached`.

The UI's `canAddParent` had already been patched to bypass the limit when no parents were connected, but the service-layer check had not — so the button opened the scanner, then the service immediately rejected.

The underlying architectural issue: **a child device's own subscription tier should never gate parent pairing**. The child doesn't purchase a plan to determine how many parents it can have.

### Fixes
**`DevicePairingService.swift` — `canAnotherParentPair()`**
- Added first-pairing bypass: if `getPairedParentCount() == 0`, always return `true`
- A child with no paired parents can always pair, regardless of their own subscription tier

**`DevicePairingService.swift` — `PairingError.maxParentsReached`**
- Changed from `case maxParentsReached` to `case maxParentsReached(limit: Int)`
- Error message now shows the actual limit dynamically instead of hardcoded "(2)"
- All three throw sites updated to pass the real limit

**`ChildPairingView.swift` — `scanCardSubtitle`**
- Changed condition from `pairedParents.count >= maxParentDevices` to `!canAddParent`
- Prevents "Maximum of 0 reached" showing alongside an enabled button

---

## Bug 2: Child Paywall Not Unlocking After Successful Pairing

### Symptom
After pairing succeeds (success alert shown), the child app stayed on the paywall (`SubscriptionLockoutView`) instead of unlocking.

### Root Cause
`refreshParentSubscriptionIfNeeded()` in `SubscriptionManager` is called at the end of every pairing flow to inherit the parent's subscription. It only granted child access when the parent was on `individual` or `family`. If the parent was on **trial**, it fell into the `else` branch and set `currentStatus = .expired` on the child:

```swift
// Before (broken)
if tier == .individual || tier == .family {
    currentStatus = status   // .active → hasAccess = true ✓
} else {
    // Trial hits here too!
    currentStatus = .expired // hasAccess = false → paywall stays ✗
}
```

During TestFlight, parents are on trial — so every pairing immediately revoked child access right after granting it.

### Fix
**`SubscriptionManager.swift` — `refreshParentSubscriptionIfNeeded()`**

Changed the logic to block only `.solo` (which explicitly doesn't support child pairing), and allow all other tiers (trial, individual, family):

```swift
// After (fixed)
if tier == .solo {
    // Solo doesn't support a separate child device
    currentTier = .trial
    currentStatus = .expired
} else {
    // trial, individual, family all support child pairing
    // Inherit parent's tier and status; status carries the real access state
    if currentTier != tier { currentTier = tier }
    currentStatus = status  // .trial → hasAccess = true ✓
}
```

This also means: if the parent's trial expires later, `status` becomes `.expired` and the child automatically loses access with no extra logic needed.

### Subscription Inheritance Design

The child's `currentTier` and `currentStatus` are a **local cache of the parent's subscription**, not a real subscription. They exist solely to answer: *does this child have access?*

- Parent writes `(tier, status)` to its CloudKit zone via `updateParentSubscriptionStatus()`
- Child reads it via `fetchParentSubscriptionStatus()` in `CloudKitSyncService`
- Child's `currentTier`/`currentStatus` mirror the parent's
- `hasAccess = currentStatus.isAccessGranted` gates `SubscriptionLockoutView`

---

## Bug 3: Parent Paywall Has No StoreKit Fallback + Wrong Tier Pre-Selection

### Symptom
- If RevenueCat offerings failed to load, the parent paywall purchase button was permanently disabled — no fallback
- Tapping "Upgrade to Family" from `SubscriptionManagementView` opened the paywall pre-selected on Individual instead of Family

### Root Cause
`ChildSubscriptionView` had been patched with a StoreKit fallback (loads offerings, falls back to StoreKit if RevenueCat unavailable), but `SubscriptionPaywallView` (the parent paywall) had not received the same treatment.

`SubscriptionPaywallView` had no `initialTier` parameter, so all callers always opened it on `.individual` regardless of intent.

### Fixes
**`SubscriptionPaywallView.swift`**
- Added `init(initialTier:isOnboarding:onComplete:)` using `State(initialValue:)` so callers can pre-select the tier
- Added `selectedStoreKitProduct` computed property (StoreKit fallback)
- Added `.task` that loads RevenueCat offerings if neither source is available
- `purchaseButton` shows spinner during load; enables once either RevenueCat package *or* StoreKit product is ready
- `purchase()` falls back to `purchaseStoreKitProduct()` if no RevenueCat package
- `buttonText` handles the StoreKit product case

**`SubscriptionManagementView.swift`**
- Added `@State private var paywallInitialTier: SubscriptionTier = .individual`
- Sheet now passes `initialTier: paywallInitialTier` to `SubscriptionPaywallView`
- "Upgrade to Family" sets `paywallInitialTier = .family` before opening → paywall opens pre-selected on Family
- "Unlock Premium" (trial) sets `paywallInitialTier = .individual`
- "Upgrade Plan" in excess children warning also sets `.family`

---

## Files Modified

| File | Changes |
|------|---------|
| `Services/DevicePairingService.swift` | First-pairing bypass in `canAnotherParentPair()`; dynamic `maxParentsReached(limit:)` error |
| `Services/SubscriptionManager.swift` | Fixed `refreshParentSubscriptionIfNeeded()` to allow trial parents; added `purchaseStoreKitProduct()` |
| `Views/ChildMode/ChildPairingView.swift` | `scanCardSubtitle` uses `canAddParent`; catch updated for `maxParentsReached(_)` |
| `Views/Subscription/ChildSubscriptionView.swift` | StoreKit fallback + "Scan Parent's QR Code" button (pre-existing work) |
| `Views/Subscription/SubscriptionManagementView.swift` | `paywallInitialTier` state; tier pre-selection on upgrade buttons |
| `Views/Subscription/SubscriptionPaywallView.swift` | StoreKit fallback; `initialTier` init parameter |
