# Brain Coinz — App Store Compliance Checklist

Pre-resubmission tasks identified from a full audit against Apple's App Store Review Guidelines (Feb 23, 2026).

---

## Status Key
- [x] Done
- [ ] TODO

---

## CRITICAL — Will Cause Rejection

### 1. [x] Hidden Trial Reset (Guideline 2.3.1)
**Fixed:** Wrapped 5-tap trial reset gesture and alert in `#if DEBUG` in `SettingsTabView.swift`.

### 2. [x] Debug Diagnostics Visible in Production (Guideline 2.3.1)
**Fixed:** Wrapped entire DIAGNOSTICS settings section in `#if DEBUG` in `SettingsTabView.swift`.

### 3. Trial Duration Mismatch + Missing Introductory Offer (Guideline 2.3)
The paywall says "14-DAY FREE TRIAL" but no introductory offer was configured in App Store Connect. The App Store description draft also said "7-day trial."

- [x] **Code:** Updated `APP_REVIEW_RESUBMISSION_DRAFTS.md` from "Free 7-day trial" → "Free 14-day trial"
- [ ] **App Store Connect:** Create Introductory Offer on EACH subscription product:
  - Go to: My Apps → Brain Coinz → Subscriptions → [group] → [product] → Introductory Offers → Create
  - Type: Free Trial
  - Duration: 14 days
  - Do this for ALL 6 products: Solo Monthly, Solo Annual, Individual Monthly, Individual Annual, Family Monthly, Family Annual

### 4. [x] Account & Data Deletion (Guideline 5.1.1(v))
**Fixed:** Added "Delete Account & Data" button in Settings > Danger Zone with two-step confirmation.

**Implementation:**
- `Services/AccountDeletionService.swift` (NEW) — orchestrates cleanup across all services
- `Views/SettingsTabView.swift` — added `deleteAccountRow` with two-step confirmation dialogs + progress spinner

**Deletion sequence:** Stop monitoring → clear shields/web restrictions/mappings → CloudKit cleanup (parent: delete child zones, child: unpair) → batch delete all 16 CoreData entities → clear Keychain (PIN, deviceID, trialStartDate) → clear UserDefaults (standard + app group) → clear UsagePersistence → RevenueCat logout → reset device mode → return to onboarding.

**Notes:** Subscription cancellation is not automated (Apple handles separately) — dialogs inform user to manage via App Store Settings. FamilyControls authorization cannot be revoked programmatically — dialog mentions revoking manually in iOS Settings.

### 5. [x] UIRequiredDeviceCapabilities (Guideline 2.3)
**Fixed:** Changed `armv7` → `arm64` in `project.pbxproj` (both Debug and Release configs).

### 6. [x] Unwrapped Print Statements in Production (Guideline 2.3.1)
**Fixed:** Wrapped two sets of `print()` statements in `#if DEBUG` in `ScreenTimeService.swift`:
- `init()` (lines 253-259): service initialization diagnostics
- `startMonitoring()` (lines 1429-1430): monitoring call trace

---

## HIGH PRIORITY — Could Cause Rejection

### 7. [x] Firebase Analytics Without User Consent (Guideline 5.1.2)
**Fixed:** User unlinked FirebaseAnalytics, FirebaseAnalyticsCore, FirebaseAnalyticsIdentitySupport, FirebaseAI, and FirebaseAILogic from the Xcode target. All analytics code uses `#if canImport(FirebaseAnalytics)` which now evaluates to false. Code is inert. FirebaseFirestore and FirebaseFunctions remain (used by `FirebaseValidationService.swift`).

### 8. [x] Verify Privacy Policy & Terms URLs Are Live
**Verified:** All URLs return valid HTTPS pages:
- [x] https://i6dev.ca/braincoinz/privacy.html
- [x] https://i6dev.ca/braincoinz/terms.html
- [x] https://i6dev.ca/braincoinz/support.html

Referenced in: `SubscriptionPaywallView.swift`, `ChildSubscriptionView.swift`, `AboutView.swift`, `SettingsTabView.swift`

### 9. [x] COPPA Language in Privacy Policy (Guideline 5.1.4)
**Fixed:** Full COPPA section added to `docs/privacy-policy.md` (lines 83-114) and live website. Includes: parental consent requirement, child data scope, parental rights (review/delete/refuse/revoke), no third-party sharing for advertising.

---

## MEDIUM PRIORITY — Best Practice

### 10. [x] Solo Tier Alignment
**Not an issue:** Solo tier shows on child devices via `ChildSubscriptionView.swift`. Individual/Family tiers show on parent devices via `SubscriptionPaywallView.swift`. Working as designed.

### 11. [x] Subscription Price Verification
**Verified:** User confirmed App Store Connect prices match in-app display. Prices are fetched dynamically from StoreKit.

### 12. [x] Privacy Manifest Review
**Verified:** `ScreenTimeRewards/PrivacyInfo.xcprivacy` correctly declares:
- NSPrivacyAccessedAPICategoryUserDefaults (CA92.1)
- NSPrivacyAccessedAPICategoryFileTimestamp (C617.1)
- NSPrivacyAccessedAPICategorySystemBootTime (35F9.1)
- NSPrivacyAccessedAPICategoryDiskSpace (E174.1)
- NSPrivacyTracking: false
- Collected data: UserID (linked), OtherUsageData (linked)
- CloudKit and Keychain don't require separate privacy manifest declarations.

### 13. [ ] Sign in with Apple Check
`ParentPairingView.swift` references Sign in with Apple. Verify:
- Is this actually used as a login method? If yes, Guideline 4.8 applies.
- If it's just for CloudKit authentication (system-level), no action needed.
- The app uses local PIN + anonymous device ID, so Sign in with Apple is likely NOT required.

---

## LOW PRIORITY — Polish Before Submission

### 14. [ ] Verify App Category
Currently: `public.app-category.education` — appropriate for an earn-to-learn app. No change needed unless Apple suggests otherwise.

### 15. [ ] Verify Age Rating in App Store Connect
- Complete IARC questionnaire accurately
- App likely qualifies for 4+ (no objectionable content)
- This is NOT a "Kids Category" app — it's a parent-facing education tool

### 16. [ ] Test iPad Layout
Apple reviewed on iPad Air 11-inch (M3). Verify:
- All views render correctly on iPad
- No layout issues with larger screen
- `TARGETED_DEVICE_FAMILY = "1,2"` is set (confirmed)

---

## Quick Reference: What's Already Done

| Item | Description | Status |
|------|-------------|--------|
| UIRequiredDeviceCapabilities fix (armv7 → arm64) | `project.pbxproj` | Done |
| Hidden trial reset wrapped in `#if DEBUG` | `SettingsTabView.swift` | Done |
| Diagnostics section wrapped in `#if DEBUG` | `SettingsTabView.swift` | Done |
| Unwrapped prints wrapped in `#if DEBUG` | `ScreenTimeService.swift` | Done |
| Description draft trial duration (7 → 14 days) | `APP_REVIEW_RESUBMISSION_DRAFTS.md` | Done |
| Reviewer notes for 2.3 fix | `APP_REVIEW_RESPONSE_2.3.md` | Done |
| Account deletion feature | `AccountDeletionService.swift` + `SettingsTabView.swift` | Done |
| Firebase Analytics unlinked | Xcode target → Frameworks | Done |
| Privacy policy COPPA section | `docs/privacy-policy.md` + live website | Done |
| Privacy/Terms/Support URLs verified | All 3 HTTPS links live | Done |
| Solo tier alignment verified | Child vs parent paywall views | Done |
| Subscription prices verified | App Store Connect matches in-app | Done |
| Privacy manifest verified | `PrivacyInfo.xcprivacy` complete | Done |
