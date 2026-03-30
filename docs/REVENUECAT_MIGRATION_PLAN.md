# RevenueCat Migration & Subscription Overhaul Plan

## Summary
Migrate from native StoreKit 2 to RevenueCat for dynamic pricing and A/B testing. Update pricing structure, reduce trial to 14 days, and enhance device limit enforcement.

---

## New Pricing Structure

| Plan | Monthly | Annual | Children | Parents |
|------|---------|--------|----------|---------|
| **Individual** | $9.99/mo | $59.99/yr | 1 | 2 |
| **Family** | $12.49/mo | $74.99/yr | 5 | 2 per child |
| **Trial** | 14 days free | - | 5 | 2 |

**RevenueCat API Keys:**
- Production: `appl_PczAwhOyMcvGQynjpbVCKSwAhAZ`
- Sandbox: `test_OHMkOgzEzvRFQukDbFFlzBTYbhR`

- No freemium (remove free tier)
- Trial: 14 days (reduced from 30)

---

## Pre-Implementation Setup Required

### 1. RevenueCat Account
1. Sign up at https://www.revenuecat.com (free tier available)
2. Create new project for ScreenTime Rewards
3. Add iOS app with your bundle ID
4. Get API key (starts with `appl_`)

### 2. App Store Connect Products
Create 4 auto-renewable subscription products:

| Product ID | Price | Duration |
|------------|-------|----------|
| `com.screentimerewards.individual.monthly` | $9.99 | 1 month |
| `com.screentimerewards.individual.annual` | $59.99 | 1 year |
| `com.screentimerewards.family.monthly` | $12.49 | 1 month |
| `com.screentimerewards.family.annual` | $74.99 | 1 year |

### 3. RevenueCat Configuration
1. Import products from App Store Connect
2. Create entitlements: `premium_individual`, `premium_family`
3. Create offering with all 4 products
4. Map products to entitlements

---

## Implementation Phases

### Phase 1: RevenueCat SDK Setup
1. Add RevenueCat SDK via SPM (`https://github.com/RevenueCat/purchases-ios`)
2. Create `RevenueCatConfig.swift` with API key and entitlement IDs
3. Configure RevenueCat on app launch

### Phase 2: Update Subscription Models
**Files:**
- `Models/SubscriptionTier.swift` - Remove `free` case, add `trial`, add annual product IDs, add `parentDeviceLimitPerChild`
- `CoreData/UserSubscription+CoreDataProperties.swift` - Add `revenueCatUserID`, `billingPeriod`
- `Models/RegisteredDevice.swift` - Add `subscriptionStatus`, `subscriptionExpiryDate` for CloudKit sync

### Phase 3: Rewrite SubscriptionManager
**File:** `Services/SubscriptionManager.swift`

Replace StoreKit 2 with RevenueCat:
- Configure `Purchases.shared` on init
- Fetch offerings for dynamic pricing
- Replace `Product` with RevenueCat `Package`
- Replace transaction handling with `CustomerInfo`
- Update trial duration to 14 days
- Add `parentDeviceLimitPerChild` property
- Add CloudKit sync for child verification

### Phase 4: CloudKit Subscription Sync
**File:** `Services/CloudKitSyncService.swift`

Add methods:
- `updateParentSubscriptionStatus(tier:status:expiryDate:)` - Parent syncs status to CloudKit
- `fetchParentSubscriptionStatus(parentDeviceID:)` - Child verifies parent's subscription
- `countParentDevicesForChild(childDeviceID:)` - Enforce 2-parent limit

### Phase 5: Update Device Pairing
**File:** `Services/DevicePairingService.swift`

- Add `canAnotherParentPair(withChildDeviceID:)` method
- Update pairing validation to check parent device count
- Sync subscription status after successful pairing

### Phase 6: Update Paywall Views
**Files:**
- `Views/Subscription/SubscriptionPaywallView.swift` - Dynamic pricing from RevenueCat offerings
- `Views/Onboarding/Screens/Screen6_TrialPaywallView.swift` - Update "30 days" → "14 days", dynamic prices
- `Views/ChildMode/ChildPairingView.swift` - Use `SubscriptionManager.parentDeviceLimitPerChild`

---

## Files to Modify

| File | Changes |
|------|---------|
| `Services/SubscriptionManager.swift` | Complete rewrite for RevenueCat |
| `Services/CloudKitSyncService.swift` | Add subscription sync methods |
| `Services/DevicePairingService.swift` | Add parent device counting |
| `Models/SubscriptionTier.swift` | Update tiers, add annual products |
| `CoreData/UserSubscription+CoreDataProperties.swift` | Add RevenueCat fields |
| `Views/Subscription/SubscriptionPaywallView.swift` | Dynamic pricing |
| `Views/Onboarding/Screens/Screen6_TrialPaywallView.swift` | 14-day trial, dynamic prices |
| `Views/ChildMode/ChildPairingView.swift` | Dynamic parent limit |
| `Configuration.storekit` | Add annual products |
| `project.pbxproj` | Add RevenueCat SPM dependency |

## New Files to Create

| File | Purpose |
|------|---------|
| `Services/RevenueCatConfig.swift` | API key, product IDs, entitlement IDs |

---

## Child Device Subscription Verification Flow

```
Parent purchases → SubscriptionManager updates → Syncs to CloudKit
                                                      ↓
Child device polls CloudKit → Gets parent subscription status → Grants/denies access
```

The child device has a different iCloud account than the parent. To verify subscription:

1. **Parent Device Flow:**
   - Parent purchases subscription via RevenueCat
   - `SubscriptionManager` updates local state
   - Subscription status synced to CloudKit `RegisteredDevice` record
   - Record shared with child via existing pairing system

2. **Child Device Flow:**
   - Child device polls CloudKit for parent's `RegisteredDevice` record
   - Extracts `subscriptionTier`, `subscriptionStatus`, `subscriptionExpiryDate`
   - Grants/denies features based on parent's subscription
   - Falls back to cached data if CloudKit unavailable

---

## Device Limit Enforcement

### Child Device Limits (enforced on parent)
- Individual: 1 child device
- Family: 5 child devices
- Checked in `DevicePairingService.createPairingSession()`

### Parent Device Limits (enforced on child)
- All tiers: 2 parent devices per child
- Checked in `DevicePairingService.acceptParentShareAndRegister()`
- Stored count: Number of entries in `PairedParentInfo` array

---

## A/B Testing Capability

With RevenueCat, you can:

1. **Create multiple Offerings** in RevenueCat dashboard
   - `default` - Standard pricing
   - `pricing_test_a` - Higher prices
   - `pricing_test_b` - Lower prices with longer trial

2. **Assign users to experiments**
   - RevenueCat automatically assigns users
   - Tracks conversion rates per offering

3. **Analyze results** in RevenueCat dashboard
   - Conversion rate by offering
   - Revenue per user
   - Trial-to-paid conversion

No code changes needed to run A/B tests - just configure in dashboard.

---

## Risk Considerations

1. **CloudKit latency**: Child may have stale subscription data; use 7-day grace period
2. **Different iCloud accounts**: Already handled by existing pairing system
3. **RevenueCat outage**: Fall back to local CoreData cache

---

## Testing Checklist

- [ ] New user gets 14-day trial
- [ ] Paywall shows dynamic prices from RevenueCat
- [ ] Individual plan limits to 1 child device
- [ ] Family plan allows 5 child devices
- [ ] Parent device limit (2) enforced per child
- [ ] Child device can verify parent subscription via CloudKit
- [ ] Purchase flow completes successfully
- [ ] Restore purchases works
- [ ] Subscription status syncs to CloudKit
- [ ] Grace period works correctly after expiry
