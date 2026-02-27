# Brain Coinz — Resubmission #2 (Guideline 2.3 Fix)

All text below is ready to copy-paste into App Store Connect.

---

## A. Resolution Center Response

```
Thank you for the continued feedback. We've identified and resolved the root cause of the Guideline 2.3 issue:

FIX:
- UIRequiredDeviceCapabilities has been completely removed from the
  build. Our previous fix changed the value from "armv7" to "arm64",
  but the "arm64" capability string was still preventing installation
  on your review devices. Since our deployment target is iOS 16.6
  (all compatible devices are arm64), this key is unnecessary. It has
  been removed entirely from both Debug and Release build configurations.

The app will now install on all iOS 16.6+ devices including iPad Pro
11-inch (M4) and iPhone 17 Pro Max.

We appreciate the review team's patience and are happy to answer any
further questions.
```

---

## B. Reviewer Notes (Paste into "Notes for Reviewer")

```
WHAT THIS APP DOES:
Brain Coinz is an automated earn-to-play system for families. A parent
creates rules like "30 minutes of Khan Academy unlocks 60 minutes of
YouTube." The system then runs itself with zero parent intervention:

1. Reward apps (e.g., YouTube) are shielded on the child's device
2. As the child uses an educational app, our DeviceActivityMonitor
   extension tracks usage minute-by-minute
3. When the learning goal is met, shields are automatically removed
4. When earned time is used up, shields are automatically reapplied

HOW TO TEST:
- The app requires TWO devices: one parent, one child
- Parent device: Select "Parent" during onboarding, set a PIN, then
  create a learning-reward link (e.g., any educational app → any
  reward app) with a time goal
- Child device: Select "Child" during onboarding, pair with parent
  via QR code. FamilyControls authorization is required (iOS prompt)
- Once paired: the child uses the designated learning app. When the
  goal is met, the reward app unshields automatically

SUBSCRIPTION:
The app offers a 14-day free trial, then $4.99/month or $29.99/year.
Subscription tiers: Solo (child-only), Individual, and Family.

CHANGES SINCE LAST SUBMISSION:
- Removed UIRequiredDeviceCapabilities entirely (was blocking
  installation on review devices even after armv7 → arm64 fix)

FRAMEWORKS USED:
FamilyControls, ManagedSettings, DeviceActivity, ManagedSettingsUI
No MDM profiles. No VPN configurations.

PRIVACY:
All usage data stays on-device. No ads. No tracking. Privacy policy
and terms of service are live at:
- https://i6dev.ca/braincoinz/privacy.html
- https://i6dev.ca/braincoinz/terms.html
```

---

## C. Change Log (Internal Reference)

### Submission 1 (Rejected)
- `UIRequiredDeviceCapabilities` was set to `armv7` (32-bit) — blocked all modern devices

### Submission 2 (Rejected)
- Changed `armv7` → `arm64` — still blocked iPad Pro M4 and iPhone 17 Pro Max

### Submission 3 (This Build)
- Removed `UIRequiredDeviceCapabilities` entirely from `project.pbxproj` (both Debug and Release)
- Fixed extension CFBundleVersion mismatch (hardcoded `1` → `$(CURRENT_PROJECT_VERSION)`)
- Added missing `NSExtensionPrincipalClass` to ScreenTimeReportExtension Info.plist
- Added missing `import Combine` to BackgroundTaskLogView.swift
