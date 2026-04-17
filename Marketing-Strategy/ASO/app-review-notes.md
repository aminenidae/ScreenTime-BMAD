# App Review Notes — Brain Coinz

Versioned source of truth for the **App Review Information → Notes** field in App Store Connect. Paste this (or an updated version) into every submission so reviewers can find the parent dashboard without guessing.

---

## Notes to paste into App Store Connect

```
Brain Coinz is a Screen Time / parental-control app built on Apple's
FamilyControls, ManagedSettings, and DeviceActivity frameworks
(com.apple.developer.family-controls entitlement granted). The app
manages access to OTHER apps on the device; it does not host
child-facing in-app content.

To access parent features:
1. Launch the app and complete onboarding.
2. At Device Selection, choose "Child Device" (default reviewer flow)
   or "Parent Device" (parent-only flow).
3. At the Mode Selection screen, tap "PARENT SPACE" (top half, lock icon).
4. Create a 4-digit PIN when prompted (stored in Keychain, SHA-256).
5. The Parent Dashboard will appear with:
   - App Configuration (select Learning Apps and Reward Apps)
   - Reward Ratios and time limits
   - Website Blocking
   - Usage Monitoring / real-time sync

FamilyControls authorization prompt appears the first time a parent
enters the dashboard — please tap Allow when prompted.

The app is not submitted under the Kids Category; it is a Lifestyle /
parental-control utility intended for adults managing their child's device.
```

---

## Age Rating Questionnaire — Verified Answers

Per Apple's verbatim definitions in the [Age ratings values and definitions reference](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/):

| Field | Apple's Definition (verbatim) | Brain Coinz Answer | Why |
|---|---|---|---|
| **In-App Controls → Parental Controls** | "Settings or tools that allow parents/guardians to monitor, manage, or restrict a child's access to **in-app content or features that may not be suitable**." | **None** | Brain Coinz has no child-facing in-app content with parent-restrictable features. The app **is** the parental control system — it manages OTHER apps via FamilyControls. |
| **In-App Controls → Age Assurance** | "Mechanism to confirm an individual's age meets the age requirement for accessing specific content or services. May include: declared age range API; age estimation; age verification via government-issued passport, drivers license, national ID." | **None** | The 4-digit PIN is access control, not age assurance. We do not implement Apple's Declared Age Range API or government-ID verification. |

**Do not change these answers** unless the app's behavior changes. Marking either as "Yes" without the matching feature triggers Guideline 2.3.6 rejection (see history below).

---

## Rejection History — Guideline 2.3.6 (Apr 16, 2026) → ✅ Approved (Apr 17, 2026)

**Status:** ✅ **Approved.** Apple accepted the metadata-only resubmission of 1.0.3 (1) on Apr 17, 2026 — the day after rejection. The resolution path documented below (set "In-App Controls / Parental Controls" to None + Resolution Center reply) is confirmed working for this guideline and this app architecture.

**Submission ID:** c884ef92-a8e4-4f3a-8da2-599ff76472f1
**Review date:** April 16, 2026 (rejection) → April 17, 2026 (approval)
**Version reviewed:** 1.0.3 (1)
**Reviewer device:** iPad Air 11-inch (M3)
**Guideline cited:** 2.3.6 — Performance — Accurate Metadata

**Trigger:** This rejection landed on a **metadata-only resubmission** of the 1.0.3 (1) build that had previously been approved. The metadata update was the first batch of ASO copy/keyword changes from [`ASO_EXECUTION_PLAN.md`](./ASO_EXECUTION_PLAN.md) (subtitle, keyword field, promotional text, description). The Age Rating questionnaire was re-saved as part of that submission flow, which is when "In-App Controls → Parental Controls" was inadvertently flipped to **Yes**. The binary itself was unchanged; the rejection was triggered by the questionnaire answer, not by anything in the ASO copy.

### Verbatim Apple response

```
Hello,

Thank you for submitting an update to the app, Brain Coinz: Earn Screen Time,
for review. We noticed some issues that require your attention. Please see
below for additional information.

If you have any questions, we are here to help. Reply to this message in
App Store Connect and let us know.

Review Environment

Submission ID: c884ef92-a8e4-4f3a-8da2-599ff76472f1
Review date: April 16, 2026
Review Device: iPad Air 11-inch (M3)
Version reviewed: 1.0.3 (1)

Guideline 2.3.6 - Performance - Accurate Metadata


Issue Description

The content description selected for the app's Age Rating indicates that
the app includes In-App Controls. However, we were unable to find either
Parental Controls or Age Assurance mechanisms in the app.

Next Steps

If the app currently includes these features, reply to this message and
let us know how to locate them.

Otherwise, update the Age Rating selections to "None" for "Parental
Controls." Age Rating selections can be found on the App Information
page after selecting the app in App Store Connect.

Resources

- Learn more about In-App Controls in Age ratings values and definitions.
- Learn more about age rating requirements in guideline 2.3.6.
```

### Root cause

The questionnaire's "In-App Controls → Parental Controls" was set to **Yes**, which signals to Apple that the app has parent-restrictable controls over its **own** in-app content (e.g., a streaming app's kids profile). Brain Coinz does not host such content — it manages other apps via FamilyControls / ManagedSettings / DeviceActivity. Apple's reviewer correctly could not locate any in-app parental-control surface and rejected for inaccurate metadata.

### Resolution

1. Set "In-App Controls / Parental Controls" → **None** in the Age Rating questionnaire.
2. Set "In-App Controls / Age Assurance" → **None** (already None; re-verified).
3. Pasted the Notes block above into App Store Connect → App Review Information → Notes.
4. Replied in the Resolution Center (verbatim text below).
5. Resubmitted the same 1.0.3 (1) build (metadata-only fix, no new binary).

### Verbatim Resolution Center reply (sent Apr 16, 2026)

```
Hello,

Thank you for the review. We have updated the Age Rating questionnaire as
suggested in your "Otherwise" guidance.

Per Apple's definition, "In-App Controls / Parental Controls" describes
"settings or tools that allow parents/guardians to monitor, manage, or
restrict a child's access to in-app content or features that may not be
suitable." Brain Coinz does not host child-facing in-app content with
parent-restrictable features — instead, the entire app is a Screen Time /
parental-control system that manages OTHER apps on the device using
Apple's FamilyControls, ManagedSettings, and DeviceActivity frameworks
(com.apple.developer.family-controls entitlement).

We have set "In-App Controls / Parental Controls" and "Age Assurance" to
"None" in the age rating questionnaire.

For your reference, the parent management interface is accessible via:
Onboarding → Device Selection (Child) → Mode Selection → "PARENT SPACE"
(lock icon) → 4-digit PIN setup (Keychain, SHA-256) → Parent Dashboard
(app configuration, reward ratios, website blocking, usage monitoring).

Reviewer notes with a demo PIN have been added to App Review Information.

Please let us know if any further clarification is helpful.

Thank you,

Amine Nidae
i6 Development
```

### Known inconsistency in the Apr 16 reply — confirmed harmless by Apr 17 approval

The reply stated *"Reviewer notes with a demo PIN have been added to App Review Information."* The Notes block above was submitted **without** a demo PIN — it instructs the reviewer to create one at step 4. The app was approved Apr 17 despite the mismatch, confirming the reviewer's blocker was the questionnaire answer, not the Notes content.

**Forward fix (next submission):** add an actual demo PIN to the Notes block (e.g., `Demo PIN: 1234`) so any future reply that references a demo PIN is truthful, and so reviewers can move through the parent flow faster.

### Lesson for future ASO metadata-only submissions

Every metadata-only resubmission re-opens the Age Rating questionnaire. **Verify both "In-App Controls" fields are still set to None before submitting**, even when the only intended change is keyword/subtitle/description copy from the ASO plan. Re-flipping these answers is silent — there is no diff or warning in App Store Connect. If the Resolution Center reply references the Notes, re-read the Notes immediately before submitting both to confirm they agree.

---

## Reference

- [Age ratings values and definitions — App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [App Review Guidelines — Guideline 2.3.6](https://developer.apple.com/app-store/review/guidelines/#2.3.6)
- [Family Controls — Apple Developer Documentation](https://developer.apple.com/documentation/familycontrols)
- [Updated age ratings in App Store Connect — Apple Developer News](https://developer.apple.com/news/?id=ks775ehf)
