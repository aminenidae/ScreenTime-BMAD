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

## Rejection History — Guideline 2.3.6 (Apr 16, 2026)

**Submission ID:** c884ef92-a8e4-4f3a-8da2-599ff76472f1
**Version reviewed:** 1.0.3 (1)
**Reviewer device:** iPad Air 11-inch (M3)

**Issue:** "The content description selected for the app's Age Rating indicates that the app includes In-App Controls. However, we were unable to find either Parental Controls or Age Assurance mechanisms in the app."

**Root cause:** The questionnaire's "In-App Controls / Parental Controls" was set to **Yes**, which signals to Apple that the app has parent-restrictable controls over its **own** in-app content (e.g., a streaming app's kids profile). Brain Coinz does not host such content — it manages other apps via FamilyControls.

**Resolution:**
1. Set "In-App Controls / Parental Controls" → **None** in the Age Rating questionnaire.
2. Replied in Resolution Center explaining the architecture (FamilyControls / ManagedSettings / DeviceActivity) and pointed reviewers to the parent dashboard navigation.
3. Added these App Review Notes to prevent recurrence.
4. Resubmitted the same 1.0.3 build (metadata-only fix, no new binary).

---

## Reference

- [Age ratings values and definitions — App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [App Review Guidelines — Guideline 2.3.6](https://developer.apple.com/app-store/review/guidelines/#2.3.6)
- [Family Controls — Apple Developer Documentation](https://developer.apple.com/documentation/familycontrols)
- [Updated age ratings in App Store Connect — Apple Developer News](https://developer.apple.com/news/?id=ks775ehf)
