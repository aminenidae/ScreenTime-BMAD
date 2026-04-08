# Privacy Policy — Brain Coinz

**Last Updated:** April 7, 2026
**Live URL:** https://i6dev.ca/braincoinz/privacy.html
**Source file:** `i6dev-website/braincoinz/privacy.html`

---

## Changelog

### April 7, 2026 (pass 2 — competitor cross-check)
- Added explicit Apple payment processing statement (billing handled entirely by Apple; we never access payment details)
- Expanded Data Retention section with per-category timelines:
  - iCloud data: until deleted by parent or account closed
  - Local device data: removed on app deletion
  - RevenueCat anonymous ID: per RevenueCat's retention policy
  - Pairing codes: discarded immediately after pairing
- Added "Subscriptions and Account Registration" clause: children under 13 cannot subscribe or register; only parents (18+) can
- Added "No advertising or profiling" clause for children's data

### April 7, 2026 (pass 1 — Apple compliance)
- Updated Last Updated date from February 15 → April 7, 2026
- Added Third-Party Services section: RevenueCat (anonymous ID + purchase receipts), Apple CloudKit & iCloud, Apple DeviceActivity framework
- Added Data Retention and Deletion section with 3 deletion paths (in-app reset, iCloud settings, email request with 30-day SLA)
- Expanded COPPA section: parental consent mechanism (QR code + PIN pairing), what child data is collected, how parents can review/delete
- Added "Changes to This Policy" clause

### February 15, 2026 (initial)
- Initial publication

---

## Full Text (current)

## Introduction
Brain Coinz ("we," "our," or "us") respects your privacy and is committed to protecting your personal information. This Privacy Policy explains how we collect, use, store, and protect information when you use the Brain Coinz mobile application ("the App").

**By using the App, you agree to the collection and use of information in accordance with this Privacy Policy.**

## Information We Collect

### 1. Information You Provide Directly

**Parent Account Information:**
- Parent name (required, for display purposes)
- Device pairing codes (temporary, for QR code authentication)
- PIN code (stored locally on your device, encrypted)
- Custom app names and configurations

**Child Account Information:**
- Child name or nickname (you choose what to enter)
- Device identifier (for pairing purposes)

**Important: We do NOT require:**
- Email addresses
- Phone numbers
- Passwords (authentication via Apple Family Controls and local PIN)
- Payment information (handled entirely by Apple)

### 2. Automatically Collected Information

**Screen Time Data:**
- Educational app usage duration (which apps, how long used)
- Reward app usage duration
- Daily usage statistics
- App categories (learning vs. reward apps)
- Device screen time authorization status

**Device Information:**
- Device type (iPhone or iPad)
- iOS version
- App version
- Device timezone (for accurate daily tracking)
- iCloud account identifier (anonymous, for CloudKit sync)

### 3. Information We Do NOT Collect
- Browsing history
- Location data
- Contact lists
- Photos or media
- Emails or messages
- Financial information
- Social media data
- Advertising identifiers
- Analytics from third-party trackers

## How We Use Your Information

- **Pairing Devices:** To establish secure connections between parent and child devices
- **Tracking Progress:** To monitor educational app usage and calculate earned rewards
- **CloudKit Sync:** To synchronize data across your family's devices via your private iCloud container

## Third-Party Services

### RevenueCat
Used for subscription management. Receives:
- An anonymous app user identifier (randomly generated, not linked to identity)
- Purchase receipts and subscription status (provided by Apple)
- Subscription events (e.g., trial started, renewed, cancelled)

RevenueCat does not receive name, email, screen time data, or any personal information.
Privacy policy: https://www.revenuecat.com/privacy

### Apple (Payments, CloudKit & iCloud)
All subscription billing and payment information is collected and processed directly by Apple through the App Store. We do not store, access, or process payment details at any point. All screen time data and family configurations are stored in the user's private iCloud container, governed by Apple's privacy policy (https://www.apple.com/legal/privacy/). We cannot access this data without explicit iCloud credentials.

### Apple Screen Time Framework (DeviceActivity)
Used to track app usage on child devices. This data never leaves the device or private iCloud container and is not accessible to us.

## How We Store and Protect Your Information

**iCloud Private Container:**
- ALL screen time data and configurations are stored in YOUR private iCloud container (`iCloud.com.screentimerewards`)
- Associated with YOUR Apple ID
- We cannot access this data without your explicit iCloud credentials
- Apple controls access, encryption, and security

**Local Device Storage:**
- PIN codes stored using Apple's Keychain (encrypted)
- App preferences stored in UserDefaults (non-sensitive settings only)

## Data Retention and Deletion

### Retention by data category
- **Screen time data & configurations (iCloud):** Retained until deleted by the parent or until the iCloud account is closed.
- **Local device data** (PIN, preferences, daily counters): Removed immediately when the App is deleted from the device.
- **RevenueCat anonymous ID & subscription events:** Retained per RevenueCat's retention policy (https://www.revenuecat.com/privacy). We do not control this data.
- **Temporary pairing codes:** Discarded immediately after device pairing is complete.

### How to delete your data
1. **In-App:** Use the Reset or Delete Data option in the App's settings to clear all local and iCloud data.
2. **iCloud Settings:** Go to Settings → [your name] → iCloud → Manage Account Storage → Brain Coinz to delete all associated iCloud data.
3. **Contact Us:** Email support@i6dev.ca to request complete data deletion. We will respond within 30 days.

## Children's Privacy (COPPA Compliance)

### Subscriptions and Account Registration
Children under 13 cannot subscribe to or register for Brain Coinz. Only parents or guardians (18+) may create an account and purchase a subscription. Children use the App exclusively on their own device under the parent's active authorization — they do not have independent accounts.

### Parental Consent
- **Required:** A parent or guardian must set up the App on the parent device and explicitly authorize each child device by completing the pairing process (via QR code scan and PIN verification). No child device can be monitored without this active parental authorization.
- **Control:** Parents control all settings, monitored apps, reward thresholds, and can revoke access or delete all data at any time.
- **What we collect from children:** Only the child's nickname (entered by the parent) and screen time usage data on the child's device. Stored exclusively in the family's private iCloud container; not accessible to us.
- **No advertising or profiling:** We do not use children's data for advertising, profiling, or sale to third parties.
- **Data review and deletion:** Parents can review or delete all data at any time via the App or by contacting support@i6dev.ca.

## Changes to This Policy
We may update this Privacy Policy from time to time. When we make material changes, we will update the "Last Updated" date at the top of this page and notify users through the App or via the App Store update notes. Continued use of the App after changes are posted constitutes your acceptance of the revised Policy.

## Contact Us
- **Email:** support@i6dev.ca
- **Website:** https://i6dev.ca/braincoinz
