# Paywall Compliance Audit — February 2026

**Date:** February 26, 2026
**Context:** App submitted for review. This audit documents known compliance gaps against Apple's latest 2026 guidelines for future reference if Apple flags issues.

---

## Summary

**Overall:** Mostly compliant. No critical blockers found (hardcoded price issues from Dec 2025 audit are resolved). Two medium-severity gaps remain.

| Category | Status |
|---|---|
| Toggle patterns (banned Jan 2026) | PASS — no toggle paywalls |
| Dynamic pricing via RevenueCat | PASS — all prices from `localizedPriceString` |
| Restore Purchases button | PASS — present on all 4 paywalls |
| Monthly/Annual plan selector | PASS — standard selector, not a trial toggle |
| External payment links | N/A — all purchases via Apple IAP |
| DEBUG code guarded | PASS — all dev skip buttons in `#if DEBUG` |
| Terms/Privacy links | **FAIL** — missing on 2 of 4 paywalls |
| Full Schedule 2 disclosure | **FAIL** — built but unused |
| Trial implementation model | **RISK** — local trial, not StoreKit introductory offer |

---

## Issues to Fix (if Apple requests)

### Issue 1: Missing Terms/Privacy Links (2 paywalls)

**Guideline:** 5.1.2, Schedule 2 Section 3.8(b)

| Paywall | Terms/Privacy Links |
|---|---|
| `Views/Subscription/SubscriptionPaywallView.swift` | Present |
| `Views/Subscription/ChildSubscriptionView.swift` | Present |
| `Views/Onboarding/Screens/Screen6_TrialPaywallView.swift` | **MISSING** |
| `Views/ParentMode/ParentPaywallView.swift` | **MISSING** |

**Fix:** Add the same `HStack` with Terms of Service and Privacy Policy links used in `SubscriptionPaywallView` to both missing screens. Links:
- Terms: `https://i6dev.ca/braincoinz/terms.html`
- Privacy: `https://i6dev.ca/braincoinz/privacy.html`

### Issue 2: Incomplete Auto-Renewal Disclosure

**Guideline:** Schedule 2, Section 3.8(b)

A proper `SubscriptionDisclosureText.swift` component exists at `Views/Subscription/SubscriptionDisclosureText.swift` with the full required text:
- Payment charged at confirmation
- Auto-renewal terms with 24-hour window
- Renewal cost
- Trial forfeiture clause
- Link to Account Settings

**Problem:** This component is **not used anywhere**. Each paywall has its own abbreviated version instead:

| Paywall | Current Disclosure |
|---|---|
| `SubscriptionPaywallView` (line ~384) | "Cancel anytime. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period." |
| `ChildSubscriptionView` (line ~392) | Similar abbreviated text |
| `Screen6_TrialPaywallView` (line 135) | "14-day free trial. No charge until your trial ends. You can cancel anytime in your iPhone settings." |
| `ParentPaywallView` (line 304) | "Payment will be charged to your Apple ID account. Subscription automatically renews unless canceled at least 24 hours before the end of the current period." |

**Fix:** Replace abbreviated disclosure text in all 4 paywalls with the `SubscriptionDisclosureText` component. Pass the dynamic price from RevenueCat.

### Issue 3 (Low Risk): Local Trial Implementation

The 14-day trial is managed locally via Keychain + CoreData rather than as a StoreKit introductory offer (`Products.storekit` has `introductoryOffer: null` for all products). Users get the trial without initiating a purchase.

This is a **design choice** (allows trial before commitment), not necessarily a violation, but it's non-standard. If Apple objects, the fix would be:
1. Configure introductory offers in App Store Connect
2. Remove local trial logic from `SubscriptionManager.swift`
3. Change trial to begin at subscription purchase (free period before billing)

**Note:** This was also flagged in the Dec 2025 audit and was not rejected.

---

## Passing Areas (No Action Needed)

1. **No toggle paywalls** — Apple banned trial toggle patterns in Jan 2026. Our paywalls use a standard monthly/annual plan selector which is compliant.

2. **Dynamic pricing** — All prices come from RevenueCat `localizedPriceString` with StoreKit fallback. No hardcoded prices remain (fixed since Dec 2025 audit).

3. **Restore Purchases** — Present and functional on all 4 paywall screens.

4. **Clear trial messaging** — "14-day free trial" prominently displayed with "no charge until trial ends" language.

5. **No external payment links** — All purchases through Apple IAP. No anti-steering concerns.

---

## Recent Apple Guideline Changes (Context)

### Toggle Paywalls Banned (Jan 2026)
Apple now rejects apps using toggle switches to add/remove free trials, citing Guideline 3.1.2. Our app does NOT use this pattern.

### External Payment Links (U.S.)
- May 2025: Epic v. Apple ruling allowed external payment links with zero commission
- Dec 2025: Ninth Circuit allowed Apple to charge a "reasonable fee" (TBD by district court)
- Current: External links permitted in U.S. apps; final fee structure pending

### EU Changes
- Core Technology Fee phased out Jan 1, 2026
- Replaced with sales-based commissions (10-20%)

### Other
- New age-rating questionnaire required for new submissions (Jan 31, 2026)
- All apps must use iOS 18 SDK (since April 2025)

---

## Files Reference

| File | Role |
|---|---|
| `Views/Subscription/SubscriptionPaywallView.swift` | Main paywall (all tiers) |
| `Views/Subscription/ChildSubscriptionView.swift` | Child device paywall (Solo) |
| `Views/Onboarding/Screens/Screen6_TrialPaywallView.swift` | Onboarding trial paywall |
| `Views/ParentMode/ParentPaywallView.swift` | Parent device paywall |
| `Views/Subscription/SubscriptionDisclosureText.swift` | Full Schedule 2 disclosure (unused) |
| `Services/SubscriptionManager.swift` | RevenueCat + local trial logic |
| `Services/RevenueCatConfig.swift` | RC API keys and product IDs |
| `Products.storekit` | StoreKit product definitions |

---

## Previous Audit

See `docs/paywall-compliance-assessment.md` (Dec 28, 2025) for the prior assessment. Key changes since then:
- Hardcoded prices → **Fixed** (now dynamic via RevenueCat)
- Trial changed from 30 days → 14 days
- Annual products added to `Products.storekit`
- Terms/Privacy links and full disclosure still not integrated on all screens

---

*This document should be updated after Apple's review response.*
