# App Store Connect Configuration Guide

**Complete setup instructions for ScreenTime Rewards in App Store Connect**

**Time Required:** 45-60 minutes (first-time setup)

---

## Prerequisites

- [ ] Apple Developer Program membership ($99/year) - Active and paid
- [ ] Apple ID with Account Holder or Admin role
- [ ] Accepted latest Apple Developer Agreement
- [ ] Bundle ID: `i6dev.ScreenTimeRewards` (from your Xcode project)

---

## Part 1: Create App Record

### Step 1.1: Access App Store Connect

1. Open browser: https://appstoreconnect.apple.com

2. **Sign in** with your Apple Developer Apple ID

3. **Accept agreements** if prompted:
   - Paid Applications Agreement
   - Apple Developer Program License Agreement

### Step 1.2: Create New App

1. Click **"My Apps"** tile (or from header menu)

2. Click **"+"** button (top left corner)

3. Select **"New App"**

### Step 1.3: App Information

**Platform:**
- ✓ **iOS**
- ⬜ tvOS (unchecked)
- ⬜ macOS (unchecked)
- ⬜ visionOS (unchecked)

**Name:**
- Enter: **ScreenTime Rewards**
  - Must be unique across App Store (if taken, try variants)
  - Can be changed later
  - 30 character limit

**Primary Language:**
- Select: **English (U.S.)** (or your primary market language)

**Bundle ID:**
- Dropdown: Select **i6dev.ScreenTimeRewards**
  - **CRITICAL:** Must match Xcode exactly
  - If not in list, register it first (see Step 1.4)

**SKU:**
- Enter: **screentimerewards-001**
  - Internal tracking number (not shown to users)
  - Can be any unique string
  - Cannot be changed after creation

**User Access:**
- Select: **Full Access** (default)
  - Determines which team members can see this app

**Click "Create"**

### Step 1.4: If Bundle ID Not Found

If `i6dev.ScreenTimeRewards` doesn't appear in dropdown:

1. Open new tab: https://developer.apple.com/account/resources/identifiers/list

2. Click **"+"** button (Register a New Identifier)

3. Select **"App IDs"** → Continue

4. Select **"App"** → Continue

5. **Description:** ScreenTime Rewards

6. **Bundle ID:**
   - Select: **Explicit**
   - Enter: `i6dev.ScreenTimeRewards`

7. **Capabilities:** (scroll through and check these)
   - ✓ In-App Purchase
   - ✓ iCloud (CloudKit)
   - ✓ App Groups
   - ✓ Family Controls
   - ✓ Push Notifications

8. Click **"Continue"** → **"Register"**

9. Return to App Store Connect and refresh page - Bundle ID should now appear

---

## Part 2: Configure In-App Purchases (Subscriptions)

**CRITICAL:** Subscriptions must be configured BEFORE TestFlight upload for in-app purchase testing to work.

### Step 2.1: Create Subscription Group

1. App Store Connect → **My Apps** → **ScreenTime Rewards**

2. Left sidebar → **Features** → **In-App Purchases**

3. Click **"+"** button (Manage Subscriptions)

4. Click **"Create Subscription Group"** (if no groups exist)

**Subscription Group Name:**
- Enter: **ScreenTime Premium**
  - Shown to users on App Store
  - Cannot be changed after first subscription is approved

**Click "Create"**

### Step 2.2: Create Subscription 1 - Individual Monthly

1. In **ScreenTime Premium** group, click **"+"** → **Create Subscription**

**Reference Name:**
- Enter: **Individual Monthly**
  - Internal use only (not shown to users)

**Product ID:**
- Enter: **com.screentimerewards.individual.monthly**
  - **CRITICAL:** Must match exactly what's in your code
  - Cannot be changed after creation
  - Format: `com.screentimerewards.[tier].[period]`

**Click "Create"**

### Step 2.3: Configure Individual Monthly Details

**Subscription Duration:**
- Select: **1 Month**

**Subscription Prices:**
1. Click **"Add Subscription Price"**

2. **United States:**
   - Price: **$7.99 USD**
   - Click **"Add"**

3. **Other regions:**
   - Click **"Add Equalized Prices"**
   - Apple auto-calculates based on USD price
   - Review and adjust if needed for specific countries

**Free Offer (Trial):**
1. Scroll to **"Subscription Offers"** section

2. Click **"Create Promotional Offer"** → **"Create Introductory Offer"**

3. **Offer Type:**
   - Select: **Free**

4. **Offer Duration:**
   - Duration: **1 Month**
   - Number of Periods: **1**

5. **Eligibility:**
   - Select: **New Subscribers Only**

6. Click **"Save"**

**Subscription Localizations:**
1. Scroll to **"Subscription Display Name"**

2. Click **"Add Localization"**

3. **Language:** English (U.S.)

4. **Subscription Display Name:**
   - Enter: **Individual Plan**
   - Shows in App Store and Settings

5. **Description:**
   - Enter: **Individual plan for 1 child device. Perfect for single-child families.**

6. Click **"Save"**

**Family Sharing:**
- ✓ **Turn OFF** (Individual plan should NOT be family shareable)

**Review Information:**
1. Scroll to **"Review Information"**

2. **Screenshot:** Upload 1 screenshot showing subscription benefits
   - Size: 640x920 or larger
   - Shows: Subscription paywall or features screen

3. **Review Notes:**
   ```
   Individual monthly subscription for monitoring 1 child device.

   Features:
   - Educational app tracking
   - Reward system
   - CloudKit family sync
   - 30-day free trial

   Test in Sandbox with account: [your-sandbox-email]
   ```

**Click "Save" at top right**

### Step 2.4: Create Subscription 2 - Family Monthly

1. Return to **In-App Purchases** → **ScreenTime Premium** group

2. Click **"+"** → **Create Subscription**

**Reference Name:** **Family Monthly**

**Product ID:** **com.screentimerewards.family.monthly**

**Click "Create"**

**Configure:**
- **Duration:** 1 Month
- **Price:** $12.99 USD + equalized
- **Free Offer:** 1 Month free trial
- **Display Name:** Family Plan
- **Description:** Family plan for up to 5 child devices. Share across family members with Family Sharing.
- **Family Sharing:** ✓ **Turn ON** (CRITICAL for family plan)
- **Screenshot:** Same or similar to Individual plan
- **Review Notes:** Family monthly subscription for up to 5 child devices. Family Sharing enabled.

**Click "Save"**

### Step 2.5: Create Subscription 3 - Family Yearly

1. **ScreenTime Premium** group → **"+"** → **Create Subscription**

**Reference Name:** **Family Annual**

**Product ID:** **com.screentimerewards.family.yearly**

**Configure:**
- **Duration:** 1 Year
- **Price:** $59.99 USD + equalized
  - Shows savings: (~38% off monthly)
- **Free Offer:** 1 Month free trial
- **Display Name:** Family Plan (Annual)
- **Description:** Family plan for up to 5 child devices, billed annually. Save $95.88/year compared to monthly!
- **Family Sharing:** ✓ **Turn ON**
- **Screenshot:** Similar to monthly plans
- **Review Notes:** Family annual subscription with significant discount. Billed yearly at $59.99.

**Click "Save"**

### Step 2.6: Submit Subscriptions for Review

**IMPORTANT:** Subscriptions must be approved before they work in TestFlight.

For EACH subscription (Individual Monthly, Family Monthly, Family Annual):

1. Open the subscription

2. Scroll to top

3. Status shows: **"Ready to Submit"** or **"Missing Metadata"**

4. If **Missing Metadata:**
   - Review checklist on right side
   - Fill in missing fields (usually screenshot or localization)

5. Click **"Submit for Review"** button (top right)

6. **Confirmation dialog:**
   - Review product details
   - Click **"Submit"**

7. Status changes to: **"Waiting for Review"**

**Timeline:**
- **Sandbox approval:** Usually automatic (few minutes)
- **Production approval:** 24-48 hours (happens with app review)

**Result:**
- You can now test subscriptions in Sandbox mode immediately
- Production subscriptions will activate when app is approved

---

## Part 3: Create Sandbox Test Accounts

**Why?** To test subscription purchases without real charges.

### Step 3.1: Add Sandbox Tester

1. App Store Connect → Header menu → **Users and Access**

2. Left sidebar → **Sandbox** → **Testers**

3. Click **"+"** button

**Tester Information:**
- **First Name:** Test
- **Last Name:** User
- **Email:** **test.screentimerewards@icloud.com**
  - **CRITICAL:** Must be a UNIQUE email not associated with any Apple ID
  - Cannot use your real Apple ID
  - Consider: `test1.screentimerewards@icloud.com`, `test2...`, etc.

**Password:**
- Create a memorable password: `TestPass123!`
  - You'll enter this when testing

**Secret Question + Answer:**
- Choose any question/answer pair
- Example: Favorite color? Blue

**Date of Birth:**
- Enter any date making tester 18+ years old

**Country/Region:**
- Select: **United States** (or your primary market)

**Click "Save"**

### Step 3.2: Create Multiple Test Accounts (Recommended)

Create 2-3 sandbox accounts for different testing scenarios:
- `test1.screentimerewards@icloud.com` - Individual plan testing
- `test2.screentimerewards@icloud.com` - Family plan testing
- `test3.screentimerewards@icloud.com` - Free trial testing

### Step 3.3: Using Sandbox Accounts

**On your iOS test device:**

1. **Settings** → **App Store** → Scroll to bottom

2. **SANDBOX ACCOUNT** section appears (only on iOS 15+)

3. Tap **SANDBOX ACCOUNT** → Sign in
   - Email: `test.screentimerewards@icloud.com`
   - Password: `TestPass123!`

**Alternative (iOS 14 and earlier):**
1. Sign OUT of production Apple ID in Settings → App Store
2. Do NOT sign in anywhere
3. Launch app → attempt purchase
4. Sandbox prompt appears → enter sandbox credentials

**IMPORTANT:**
- Never sign into iCloud with sandbox account (only App Store)
- Subscriptions in Sandbox are accelerated (1 month = 5 minutes for testing)
- Subscriptions auto-renew 6 times then stop

---

## Part 4: App Privacy Configuration

**Required by Apple for all apps. Shown as "Privacy Nutrition Label" on App Store.**

### Step 4.1: Start Privacy Survey

1. App Store Connect → **My Apps** → **ScreenTime Rewards**

2. Left sidebar → **App Store** → **App Privacy**

3. Click **"Get Started"** (or "Edit" if previously started)

### Step 4.2: Data Collection Survey

**Question: "Does this app collect data from users?"**

- Answer: ✓ **YES**

**Click "Next"**

### Step 4.3: Select Data Types

**Data Types Your App Collects:**

1. **Contact Info**
   - ✓ **Name** (parent/child names entered by user)

2. **User Content**
   - ✓ **Other User Content** (screen time data, app usage data)

3. **Identifiers**
   - ✓ **User ID** (iCloud identifier for CloudKit sync)

4. **Usage Data**
   - ✓ **Product Interaction** (which features used in app)

**Click "Next"** after selecting each category

### Step 4.4: Configure Name Collection

**Screen: "How is NAME used in this app?"**

**Linked to user's identity:**
- ✓ **YES**
- Reason: Names are associated with parent/child accounts

**Used for tracking:**
- ⬜ **NO**
- Reason: We don't track users across apps/websites

**Purposes for collecting NAME:**
- ✓ **App Functionality**
  - Reason: To personalize accounts and display in app

**Click "Next"**

### Step 4.5: Configure Other User Content

**How is OTHER USER CONTENT used?**

**Linked to identity:** ✓ YES (screen time data tied to child accounts)

**Used for tracking:** ⬜ NO

**Purposes:**
- ✓ **App Functionality** (monitoring screen time)

**Click "Next"**

### Step 4.6: Configure User ID

**How is USER ID used?**

**Linked to identity:** ✓ YES (CloudKit user identifier)

**Used for tracking:** ⬜ NO

**Purposes:**
- ✓ **App Functionality** (CloudKit sync)

**Click "Next"**

### Step 4.7: Configure Product Interaction

**How is PRODUCT INTERACTION used?**

**Linked to identity:** ⬜ NO (anonymous usage analytics)

**Used for tracking:** ⬜ NO

**Purposes:**
- ✓ **Analytics** (understand feature usage)
- ✓ **App Functionality** (improve user experience)

**Click "Next"**

### Step 4.8: Confirm No Tracking

**Question: "Do you or your third-party partners use data from this app for tracking purposes?"**

- Answer: ⬜ **NO**

**Explanation:**
- We don't use third-party analytics
- We don't use advertising SDKs
- We don't track users across apps/websites

**Click "Save"**

### Step 4.9: Review Privacy Nutrition Label

1. Review the generated Privacy Nutrition Label

2. **Verify it shows:**
   - Data Used to Track You: **None**
   - Data Linked to You: Name, Other User Content, User ID
   - Data Not Linked to You: Product Interaction

3. **Click "Publish"**

**Result:** Privacy label will appear on your App Store listing

---

## Part 5: App Information

### Step 5.1: Basic Information

1. App Store Connect → **My Apps** → **ScreenTime Rewards**

2. Left sidebar → **App Store** → **App Information**

**Name:** ScreenTime Rewards (already set)

**Subtitle:** (30 characters max)
- Enter: **Turn Screen Time into Rewards**
- Alternative: **Earn Rewards for Learning**

**Privacy Policy URL:**
- Enter: **https://screentimerewards.com/privacy**
- **MUST be live and accessible**

**Primary Category:**
- Select: **Productivity**
- Alternative: **Education** (if you prefer positioning as educational tool)

**Secondary Category:**
- Select: **Lifestyle**

**Content Rights:**
- ⬜ Contains Third-Party Content: NO (unless using licensed assets)

**Age Rating:**
- Click **"Edit"**
- Complete questionnaire (see Step 5.2)

**Click "Save"**

### Step 5.2: Age Rating Questionnaire

**Violence:**
- Cartoon/Fantasy Violence: **None**
- Realistic Violence: **None**

**Sexual Content/Nudity:**
- All: **None**

**Profanity/Crude Humor:**
- All: **None**

**Horror/Fear Themes:**
- All: **None**

**Mature/Suggestive Themes:**
- All: **None**

**Medical/Treatment Information:**
- All: **None**

**Alcohol, Tobacco, Drugs:**
- All: **None**

**Gambling & Contests:**
- Simulated Gambling: **None**

**Privacy:**
- **IMPORTANT:** Unrestricted Web Access: **NO**
- User Generated Content: **NO**
- User to User Communication: **NO**
- Personal Information: **YES**
  - Question: Does app collect/transmit personal info?
  - Answer: **YES** (names, screen time data)
  - **Parental Gate:** Will you implement parental gate for children?
  - Answer: **YES** (PIN code is parental gate)

**Expected Rating:** **4+** (Ages 4 and up)

**Click "Done"**

---

## Part 6: Prepare App Store Metadata (For Future Full Release)

**Note:** Not required for TestFlight, but prepare now to save time later.

### Step 6.1: Screenshots

**Required Sizes:**
- **iPhone 6.7" Display** (1290 x 2796) - iPhone 14 Pro Max, 15 Pro Max - REQUIRED
- **iPhone 6.5" Display** (1242 x 2688) - iPhone 11 Pro Max, XS Max - REQUIRED
- **iPad Pro 12.9" 3rd gen** (2048 x 2732) - If supporting iPad

**Quantity:** 3-10 screenshots per device size (optimal: 5)

**Screenshot Content Suggestions:**
1. Parent dashboard showing child activity summary
2. Educational app selection screen
3. Reward redemption / time bank screen
4. QR code pairing flow
5. Subscription benefits overview

**Design Tips:**
- First 2-3 screenshots are most important
- Add text captions highlighting benefits
- Use app's brand colors (vibrant teal, sunny yellow)
- Show actual app UI (not mockups)

**Tools:**
- Xcode Simulator (take screenshots at required sizes)
- `Cmd+S` in Simulator to save screenshot
- Photoshop/Figma for adding captions

### Step 6.2: App Preview Video (Optional)

**Specs:**
- 15-30 seconds
- H.264 codec
- Same sizes as screenshots
- Show complete flow: Onboarding → Pairing → Earning

**Not required for TestFlight, but recommended for App Store**

### Step 6.3: Description

**Draft:** (See separate template in docs, 4000 char max)

### Step 6.4: Keywords

**100 characters, comma-separated, no spaces:**
```
parental control,screen time,educational apps,kids rewards,family sync,learning tracker,child monitoring,positive reinforcement,icloud family
```

**Strategy:**
- No stop words (and, the, for)
- No duplicates from name/subtitle
- Focus on parent search terms

### Step 6.5: Support URL

**Enter:** https://screentimerewards.com/support

**Must include:**
- Contact form or email address
- FAQ section
- Device/iOS requirements

**Can be:**
- Dedicated support site
- GitHub wiki
- Notion page
- Google Site

**MUST be live and accessible before submission**

### Step 6.6: Marketing URL (Optional)

**Enter:** https://screentimerewards.com

**Can feature:**
- Feature highlights
- Pricing information
- App Store badge
- Testimonials

---

## Part 7: TestFlight Configuration

### Step 7.1: Internal Testing Group

1. App Store Connect → **TestFlight** tab

2. Left sidebar → **Internal Testing**

3. **Default group:** "App Store Connect Users"
   - Automatically created
   - Includes all team members

4. **Add testers:**
   - Click group → **"+"** button
   - Select team members from list
   - OR invite external email addresses (must have Apple ID)

5. **Enable Automatic Distribution:**
   - Toggle: **ON**
   - Every new build automatically goes to this group

6. **Test Details** (What to Test):
   ```
   Version 1.0 - Initial Beta Release

   REQUIREMENTS:
   • Two iOS devices (parent + child)
   • iOS 16.6 or later
   • iCloud account

   SETUP:
   1. Parent device: Download and complete onboarding
   2. Child device: Download and scan QR code from parent

   TEST FOCUS:
   ✓ Onboarding flow (all 6 screens)
   ✓ QR code pairing
   ✓ Subscription purchase (Sandbox: test.screentimerewards@icloud.com)
   ✓ Educational app tracking
   ✓ Reward redemption
   ✓ CloudKit sync

   KNOWN ISSUES:
   • [List any known bugs]

   FEEDBACK:
   Use TestFlight screenshot tool or email: [your-email]
   ```

### Step 7.2: External Testing (Optional)

**Only if you want public beta testers beyond your team.**

1. Left sidebar → **External Testing**

2. Click **"+"** → **Create New Group**

**Group Name:** Public Beta Testers

**Enable Automatic Distribution:**
- Toggle based on preference
- ON: New builds auto-deploy
- OFF: Manual control per build

3. **Add build** (after upload and processing):
   - Click **"+"** next to Builds
   - Select build 1.0 (1)
   - Submit for **Beta App Review** (requires 1-2 days approval)

4. **Beta App Review Information:**
   - Demo Account: Create functional test account
   - Contact Info: Your email/phone
   - Notes: Testing instructions for Apple reviewers
   - Screenshots: 2-5 showing critical flows

**Public Link:**
- After approval, enable **Public Link**
- Share: `https://testflight.apple.com/join/XXXXXX`
- Anyone can join (up to 10,000 testers)
- Link expires after 90 days (renewable)

---

## Part 8: Demo Account for App Review

**CRITICAL:** Apple reviewers need to test your app.

### Step 8.1: Create Demo Account

**Requirement:** Functional account with pre-configured data

**Options:**

**Option A: Dedicated Review Account**
1. Install app on two test devices
2. Complete onboarding as parent on Device 1
3. Pair with Device 2 as child
4. Use subscription sandbox account
5. Note credentials and setup steps

**Option B: Bypass Paywall for Reviewers**
- Implement developer/review mode
- Add hidden button to skip trial (not recommended for TestFlight)

### Step 8.2: Document Credentials

**App Review Information** (enter when submitting for App Store):

```
PARENT DEVICE CREDENTIALS:
Email/Username: appreviewer@screentimerewards.com
Password: ReviewDemo2024!

CHILD DEVICE SETUP:
1. Install app on second device
2. Tap "Child Mode" on onboarding
3. Scan QR code from parent device Settings > Add Child

SUBSCRIPTION TESTING:
Sandbox Account: test.screentimerewards@icloud.com
Password: TestPass123!

NOTES:
• App requires Family Controls permission on first launch
• Two devices required for full testing
• CloudKit sync may take 5-10 seconds
• Pre-configured with 1 paired child device

Contact: [your-email] for assistance
```

---

## Checklist: Ready for TestFlight?

Before uploading your first build:

### App Store Connect Setup
- [ ] App record created with correct bundle ID
- [ ] 3 subscriptions created and submitted for review:
  - [ ] Individual Monthly ($7.99/month)
  - [ ] Family Monthly ($12.99/month)
  - [ ] Family Annual ($59.99/year)
- [ ] Sandbox test account(s) created
- [ ] App Privacy configuration complete
- [ ] Age rating completed (4+)
- [ ] Privacy Policy URL live and accessible
- [ ] Support URL live (can wait until App Store submission)

### Terms & Privacy Pages
- [ ] Terms of Service published at https://screentimerewards.com/terms
- [ ] Privacy Policy published at https://screentimerewards.com/privacy

### Xcode Project
- [ ] PrivacyInfo.xcprivacy added to project
- [ ] All bundle IDs correct
- [ ] Version/build numbers set (1.0 / 1)
- [ ] Signing configured (Automatic, team selected)
- [ ] All entitlements present

### TestFlight Preparation
- [ ] Internal testers added
- [ ] Test Details / "What to Test" notes written
- [ ] Demo account prepared

---

## After First Upload

1. **Monitor Processing:**
   - Check email for "Processing Complete"
   - App Store Connect → TestFlight → iOS → Builds

2. **Provide Export Compliance:**
   - Answer: YES to encryption
   - Select: Standard encryption exemption
   - Click "Start Internal Testing"

3. **Test Installation:**
   - Install on your device via TestFlight
   - Verify all core features work
   - Test subscription purchase with Sandbox account

4. **Gather Feedback:**
   - Ask testers to use screenshot feedback tool
   - Monitor crash reports in App Store Connect
   - Fix critical bugs → upload Build 2

5. **Prepare for App Store:**
   - After 2-4 weeks of stable testing
   - Create screenshots and descriptions
   - Submit for full App Review

---

## Support Resources

**App Store Connect Help:**
- https://help.apple.com/app-store-connect/

**TestFlight Documentation:**
- https://developer.apple.com/testflight/

**In-App Purchase Guide:**
- https://developer.apple.com/in-app-purchase/

**App Review Guidelines:**
- https://developer.apple.com/app-store/review/guidelines/

**Contact Apple:**
- https://developer.apple.com/contact/

---

## Summary

✅ **App Record:** Created with unique bundle ID
✅ **Subscriptions:** 3 products configured with free trials
✅ **Privacy:** App Privacy and age rating completed
✅ **Testing:** Sandbox accounts and internal testers ready
✅ **Documentation:** Terms, Privacy, and support URLs prepared

**Time to First TestFlight Build:** Upload archive → 5-30 min processing → Add testers → Ready!

Good luck with your App Store Connect configuration! 🎉
