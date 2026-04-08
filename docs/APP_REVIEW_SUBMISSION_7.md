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

## Resolution — Build 17 (Apr 1, 2026)

All 3 issues resolved. No resubmission rejection pending.

### Issue 1 + 2 Fix (code)
- `RevenueCatConfig.swift`: updated 3 monthly product IDs (`SoloMonthly`, `IndividualMonthly`, `FamilyMonthly`) after subscription group restructure in App Store Connect
- `Products.storekit`: aligned product IDs to match
- `SubscriptionManager`: search all RevenueCat offerings (not just current) so Solo/Individual prices load

### Issue 3 Fix (paywall UI)
- `Screen6_TrialPaywallView`: annual price prominence per Apple 3.1.2, dynamic savings %, dynamic post-trial price in fine print, ToS/Privacy links, visual trial timeline (Today → Day 13 → Day 15)

### Build 18 (Apr 1, 2026) — Conversion optimizations
Based on Superwall's 4,000-paywall analysis (see `/Users/ameen/.gemini/antigravity/brain/f6f024a8-af5f-4a59-b260-67e93edd27ef/paywall_best_practices.md.resolved`):
- `AnnualPlanCard`: weekly price breakdown ("just $X.XX/week") instead of monthly equivalent — stronger anchoring
- `AnnualPlanCard` + `MonthlyPlanCard`: "No commitment. Cancel anytime." below CTA — ~10% conversion lift

### Build 19 (Apr 2, 2026) — Paywall parity across all 3 paywalls
Build 17/18 changes were only applied to `Screen6_TrialPaywallView`. Applied same changes to remaining 2 paywalls:
- `ParentPaywallView` (parent device onboarding paywall):
  - Weekly breakdown ("just $X/week") instead of monthly equivalent
  - "No commitment. Cancel anytime." below subscribe button
  - Dynamic savings % (was hardcoded "Save 50%")
  - ToS/Privacy links added to legal text
- `SubscriptionPaywallView` (child device + monitor from parent device):
  - Weekly breakdown ("just $X/week") instead of monthly equivalent
  - "No commitment. Cancel anytime." below purchase button
  - Dynamic savings % (was hardcoded "Save ~50%")
- `ChildSubscriptionView` (child device solo plan):
  - Weekly breakdown ("just $X/week") instead of monthly equivalent
  - "No commitment. Cancel anytime." below subscribe button

### Build 20 (Apr 2, 2026) — Hero image + visual prominence improvements
- Added `paywall_hero` image to `ParentPaywallView`, `SubscriptionPaywallView`, `ChildSubscriptionView` (already in Screen6)
- Weekly price upgraded to size 17 bold vibrantTeal across all 3 paywalls
- "No commitment. Cancel anytime." upgraded to size 13 semibold vibrantTeal + checkmark icon across all 4 paywalls
- `AnnualPlanCard` (Screen6) weekly price reduced to size 14 to avoid competing with size 18 annual headline

### Build 21 (Apr 2, 2026) — Weekly price hierarchy fix in Screen6
- `AnnualPlanCard`: weekly price reduced from size 17 → 14 so it reads as secondary to the `$X/year` headline

---

## Submission 9 — April 7, 2026 (metadata reply + resubmission)

**Status:** Submitted for review

### What was submitted
Metadata-only resolution in response to Guideline 3.1.2(c). No new build — same Build 25.

### Pre-submission actions completed (Apr 7, 2026)
1. **App Store Connect → App Description**: Added ToS and Privacy Policy URLs to bottom of description
2. **Replied to Apple Resolution Center** (Submission ID 65e2084c): confirmed metadata update, attached screen recording of in-app ToS link
3. **i6dev-website ToS updated** (`i6dev-website/braincoinz/terms.html`, pushed to `aminenidae/i6dev-website`):
   - All 6 plans listed with correct prices and renewal periods
   - Trial length corrected: 30 days → 14 days
   - Added §4.5 Refund Policy (Apple handles all refunds)
   - Added §5 Intellectual Property
   - Added §8 Termination, §9 Service Modifications, §10 Third-Party Terms
   - Strengthened §11 Liability Limitation (indirect damages exclusion + 12-month cap)
   - Added §13 Governing Law: Ontario, Canada
4. **i6dev-website Privacy Policy updated** (`i6dev-website/braincoinz/privacy.html`, pushed to `aminenidae/i6dev-website`):
   - Updated Last Updated date
   - Added Third-Party Services section (RevenueCat, Apple payments, DeviceActivity)
   - Added per-category Data Retention timelines
   - Added 3 explicit data deletion paths
   - Expanded COPPA: consent mechanism, children cannot subscribe, no advertising/profiling clause
   - Added Changes to Policy clause
5. **Docs synced**: `docs/terms-of-service.md` and `docs/privacy-policy.md` updated to match live website

---

## Submission 8 — Build 25 (Apr 3, 2026 → Apr 7, 2026)

**Status:** Re-review rejection — 1 issue (Apr 7, 2026)

### Issue — Guideline 3.1.2(c): EULA link missing from App Store metadata

**Submission ID:** 65e2084c-2e10-462c-b7e5-1b449de63006
**Review device:** iPhone 17 Pro Max and iPad Air 11-inch (M3)

Apple's finding: In-app ToS/Privacy links are present in all 4 paywall views, but the **App Store listing metadata** (App Description) does not include a functional link to the Terms of Use (EULA).

### Resolution (Apr 7, 2026) — metadata only, no code change

1. **App Store Connect → App Description**: Appended to the bottom of the description:
   ```
   Terms of Use: https://i6dev.ca/braincoinz/terms.html
   Privacy Policy: https://i6dev.ca/braincoinz/privacy.html
   ```
2. **Replied to Apple in Resolution Center** with confirmation + screen recording showing in-app ToS link tapping through to `https://i6dev.ca/braincoinz/terms.html`.

No new build required — metadata-only change.

---

## Submission 8 (original) — Build 21 (Apr 3, 2026)

**Status:** Submitted for review

### Pre-submission blockers resolved
- **Part XX ITA compliance** — form completed (selected "No" — app does not facilitate personal services). Apple backend sync delay caused submission block for 24+ hours despite form showing Complete. Resolved via Apple Developer Support ticket (submitted Apr 2, cleared Apr 3).
- **Subscription products** — all 6 products submitted for review with the binary:
  - Monthly plans (SoloMonthly, IndividualMonthly, FamilyMonthly): first-time review submission
  - Annual plans (SoloAnnual, IndividualAnnual, FamilyAnnual): resubmitted for review (were in "Waiting for Review" from prior submission)

### Notes for Reviewer (submitted with binary)
See full text in conversation. Covers resolution of all 3 Submission 7 issues + two-device testing instructions.
