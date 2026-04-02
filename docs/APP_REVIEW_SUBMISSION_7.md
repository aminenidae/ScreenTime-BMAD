# Brain Coinz — App Store Submission 7 Rejection

**Submission ID:** ffc7bde3-0b25-4e90-89a7-8d14f198221e
**Review date:** 2026-04-01
**Build:** 1.0.2 (13)
**Review device:** iPad Air (5th generation), iPadOS 26.4
**Status:** Rejected — 3 issues

Good news: Guideline 2.3 (the `ScreenTimeReportExtension` installation blocker) is **resolved**.

---

## Issue 1 — Guideline 3.1.2(b): Subscription Group Structure

### Apple's finding
Different subscription durations (e.g., monthly vs. yearly) were created as **separate IAP products** rather than as different products **within the same subscription group**.

### Why this matters
Apple requires that duration variants of the same subscription live in one group. This enables seamless upgrades/downgrades between durations (e.g., monthly → yearly) and is enforced by guideline 3.1.2(b).

### Fix required
In App Store Connect:
1. Create a single subscription group (e.g., "Brain Coinz Premium")
2. Add both duration products (monthly, yearly) as products within that group
3. Set upgrade/downgrade relationships between them
4. Delete or deprecate the separate standalone IAP products
5. Update the app's `StoreKit` product IDs to match the new group-based products

---

## Issue 2 — Guideline 2.1(b): IAP / Subscription Page Fails to Load

### Apple's finding
Reviewer was unable to load the subscription page on iPad Air (5th gen), iPadOS 26.4.

### Likely causes
1. **Subscription group not configured** — directly related to Issue 1. StoreKit can't load products that aren't properly set up in App Store Connect.
2. **Missing Paid Apps Agreement** — Apple requires the Account Holder to accept the Paid Apps Agreement in the Business section of App Store Connect before IAP products can function in review.
3. **Sandbox environment** — Apple reviews IAP in sandbox. Ensure sandbox testers are configured and products are approved/ready-for-review state.
4. **iPadOS 26 compatibility** — Verify `StoreKit 2` API calls work correctly on iPadOS 26.

### Fix required
1. Resolve Issue 1 (subscription group structure) first — this likely unblocks loading
2. Verify Paid Apps Agreement is accepted in App Store Connect → Business
3. Test subscription page in sandbox on an iPad running iPadOS 26
4. Confirm all IAP products are in "Ready to Submit" or "Approved" state

---

## Issue 3 — Guideline 2.3.2: Metadata Doesn't Label Paid Features

### Apple's finding
App description references screen time tracking but does not disclose that a purchase is required to access this functionality.

### Fix required
Update the App Store description to either:
- **Option A**: Add explicit labeling, e.g.: *"Full access requires a Brain Coinz subscription. A free trial is available."*
- **Option B**: Remove references to features that are behind the paywall, describing only what's available for free

The simplest path is Option A — one sentence added to the description or a "In-App Purchases" callout near the top.

---

## Resolution Priority

1. **App Store Connect first**: Fix subscription group structure (Issue 1) — this likely resolves Issue 2 automatically
2. **Verify Paid Apps Agreement** is accepted
3. **Update metadata** description to disclose purchase requirement (Issue 3)
4. **Test end-to-end** in sandbox on iPad before resubmitting
5. **No code changes needed** for Issues 1 and 3 — pure App Store Connect + metadata work

---

## Next Submission

This is Submission 7 (Build 13 resubmitted, or Build 14 if code changes are needed).
No changes to the app binary are required for Issues 1 and 3.
Issue 2 may require a code fix if StoreKit product IDs change after restructuring the subscription group.
