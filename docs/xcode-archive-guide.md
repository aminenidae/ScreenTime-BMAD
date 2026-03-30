# Xcode Archive & TestFlight Upload Guide

**Complete step-by-step instructions for archiving and uploading ScreenTime Rewards to TestFlight**

---

## Prerequisites Checklist

Before starting, verify you have completed:

- [x] Fixed all 4 critical configuration issues (Privacy Manifest, deployment target, push notifications, export compliance)
- [ ] Added `PrivacyInfo.xcprivacy` to Xcode project
- [ ] Published Terms of Service at https://screentimerewards.com/terms
- [ ] Published Privacy Policy at https://screentimerewards.com/privacy
- [ ] Configured In-App Purchases in App Store Connect
- [ ] Created Sandbox test account in App Store Connect
- [ ] Enrolled in Apple Developer Program ($99/year)
- [ ] Accepted latest license agreement in App Store Connect

---

## Part 1: Add Privacy Manifest to Xcode (REQUIRED)

### Step 1.1: Open Xcode Project
```bash
cd /Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject
open ScreenTimeRewards.xcodeproj
```

**Or:** Double-click `ScreenTimeRewards.xcodeproj` in Finder

### Step 1.2: Add Privacy Manifest File

1. In Xcode's **Project Navigator** (left sidebar), locate the `ScreenTimeRewards` folder (blue icon)

2. **Right-click** on the `ScreenTimeRewards` folder → **"Add Files to ScreenTimeRewards..."**

3. Navigate to:
   ```
   /Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/PrivacyInfo.xcprivacy
   ```

4. **CRITICAL - Verify these settings in the dialog:**
   - ✓ **"Copy items if needed"** - CHECKED
   - ✓ **"Create groups"** - SELECTED (not "Create folder references")
   - ✓ **"Add to targets"** - Check ONLY "ScreenTimeRewards" (main app)
     - ❌ Do NOT check extension targets
     - ❌ Do NOT check test targets

5. Click **"Add"**

6. **Verify:** The file now appears in Project Navigator under `ScreenTimeRewards` folder with a document icon (not grayed out)

### Step 1.3: Verify Privacy Manifest in Build Phases

1. Click on **ScreenTimeRewards** project (blue icon at top of navigator)

2. Select **ScreenTimeRewards** target (under TARGETS, not PROJECT)

3. Click **Build Phases** tab

4. Expand **"Copy Bundle Resources"**

5. **Verify:** `PrivacyInfo.xcprivacy` is listed
   - If NOT listed: Click **"+"** → Add `PrivacyInfo.xcprivacy`

6. **Save project:** Cmd+S

---

## Part 2: Pre-Archive Verification

### Step 2.1: Verify Bundle Identifier

1. Click **ScreenTimeRewards** project → **ScreenTimeRewards** target

2. **General** tab → **Identity** section

3. **Verify:**
   - Display Name: `ScreenTime Rewards` (or your preferred name)
   - Bundle Identifier: `i6dev.ScreenTimeRewards`
   - Version: `1.0` (marketing version)
   - Build: `1` (increment for each upload)

4. **Repeat for ALL extension targets:**
   - Click **ScreenTimeActivityExtension** target
     - Bundle ID should be: `i6dev.ScreenTimeRewards.ScreenTimeActivityExtension`
     - Version: `1.0`, Build: `1` (must match main app)
   - Click **ScreenTimeReportExtension** target
     - Bundle ID should be: `i6dev.ScreenTimeRewards.ScreenTimeReportExtension`
     - Version: `1.0`, Build: `1`
   - Click **ShieldConfigurationExtension** target
     - Bundle ID should be: `i6dev.ScreenTimeRewards.ShieldConfigurationExtension`
     - Version: `1.0`, Build: `1`
     - **Deployment Target:** iOS 16.6 (verify the fix worked)

### Step 2.2: Verify Signing & Capabilities

1. **ScreenTimeRewards** target → **Signing & Capabilities** tab

2. **Verify:**
   - ✓ **"Automatically manage signing"** - CHECKED
   - **Team:** KQ5KZR3DQ5 (or your team name) - SELECTED
   - **Signing Certificate:** "Apple Distribution" or "Apple Development" (Xcode manages this)
   - **Status:** "ScreenTimeRewards has the following signing issues:" should show NOTHING
     - If you see errors, click them for details

3. **Check all capabilities are present:**
   - ✓ In-App Purchase
   - ✓ iCloud → CloudKit
   - ✓ App Groups → `group.com.screentimerewards.shared`
   - ✓ Family Controls
   - ✓ Push Notifications
   - ✓ Background Modes → Remote notifications, Background processing

4. **Repeat for extension targets** (each should have App Groups and Family Controls)

### Step 2.3: Check Provisioning Profiles (if issues occur)

If you see signing errors:

1. **Xcode menu** → **Preferences** (or Settings on newer Xcode)

2. **Accounts** tab

3. Click your Apple ID → Click your team name

4. Click **"Download Manual Profiles"** button

5. Wait for download to complete

6. Close Preferences, return to project

7. **Signing & Capabilities** tab should now show no errors

### Step 2.4: Verify App Icon

1. Project Navigator → **Assets.xcassets** → **AppIcon**

2. **Verify:** All required icon sizes are filled (especially 1024x1024)

3. **Check 1024x1024 icon properties:**
   ```bash
   cd /Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/Assets.xcassets/AppIcon.appiconset
   sips -g pixelWidth -g pixelHeight -g hasAlpha Icon-1024x1024.png
   ```

   **Expected output:**
   ```
   pixelWidth: 1024
   pixelHeight: 1024
   hasAlpha: no
   ```

   **If hasAlpha shows "yes":** Icon has transparency, must be recreated without alpha channel

---

## Part 3: Clean Build & Archive

### Step 3.1: Clean Build Folder

1. Xcode menu → **Product** → **Clean Build Folder**
   - Keyboard shortcut: **Shift+Cmd+K**

2. Wait for "Clean Finished" in status bar (5-10 seconds)

**Why?** Removes cached build artifacts that can cause upload issues.

### Step 3.2: Select Archive Destination

1. Look at the **toolbar** at top of Xcode window

2. Click the **device selector** (left of play/stop buttons)
   - Usually shows "iPhone 15 Pro" or similar

3. Scroll to the **top** of the dropdown menu

4. Select **"Any iOS Device (arm64)"**
   - **CRITICAL:** Do NOT select a Simulator
   - If you don't see this option, connect a physical iOS device first

**Visual confirmation:** Toolbar should now show "Any iOS Device (arm64)" or your connected device name

### Step 3.3: Edit Scheme (Verify Release Configuration)

1. Click **scheme dropdown** (next to device selector)

2. Click **"Edit Scheme..."** or **Product menu** → **Scheme** → **Edit Scheme**

3. In the left sidebar, click **"Archive"**

4. **Verify:**
   - Build Configuration: **Release** (not Debug)
   - ✓ Reveal Archive in Organizer: CHECKED

5. Click **"Close"**

### Step 3.4: Create Archive

1. Xcode menu → **Product** → **Archive**
   - **No keyboard shortcut** (to prevent accidental archives)

2. **Watch the build progress** in the toolbar
   - Shows: "Build ScreenTimeRewards"
   - Then: "Build ScreenTimeActivityExtension"
   - Then: "Build ScreenTimeReportExtension"
   - Then: "Build ShieldConfigurationExtension"
   - Finally: "Archiving..."

3. **Expected time:** 2-5 minutes (depending on Mac speed)

4. **If build fails:** See "Troubleshooting Build Errors" below

### Step 3.5: Archive Success

When archiving completes successfully:

1. **Xcode Organizer** window opens automatically
   - If it doesn't: **Window menu** → **Organizer** → **Archives** tab

2. You should see your archive listed:
   - Name: **ScreenTime Rewards** (or your display name)
   - Version: **1.0 (1)**
   - Date: Today's date and time
   - Size: Typically 5-20 MB

3. **Archive appears selected** (highlighted in blue)

---

## Part 4: Validate Archive (Recommended)

**Why validate?** Catches upload errors BEFORE the long upload process, saving time.

### Step 4.1: Start Validation

1. In **Xcode Organizer**, ensure your archive is selected

2. Click **"Validate App"** button (right side)

3. **Distribution method** dialog appears

### Step 4.2: Configure Validation Options

**Screen 1: Distribution Method**
- Select: **"App Store Connect"**
- Click **"Next"**

**Screen 2: Destination**
- Select: **"Upload"** (not Export)
- Click **"Next"**

**Screen 3: App Store Connect Distribution Options**
- **App Thinning:** All compatible device variants
- **Rebuild from Bitcode:** NO (deprecated, automatically unchecked)
- ✓ **Upload your app's symbols:** CHECKED (enables crash reports)
- ✓ **Manage Version and Build Number:** UNCHECKED (we manage manually)

- Click **"Next"**

**Screen 4: Distribution Certificate**
- **Automatically manage signing:** Recommended
  - Xcode will create/download distribution certificates automatically
- OR **Manually manage signing** if you have custom provisioning profiles

- Click **"Next"**

**Screen 5: Review ScreenTimeRewards.ipa content**
- Shows: App thinning size report
- Review: Main app + 3 extensions should be listed
- Click **"Validate"**

### Step 4.3: Validation Progress

1. Dialog shows: "Validating ScreenTimeRewards.ipa..."

2. Progress bar appears (1-3 minutes)

3. Validation performs these checks:
   - Code signing certificates valid
   - Provisioning profiles include required entitlements
   - App icons present and correct size
   - Info.plist keys correct
   - Export compliance declared (we added ITSAppUsesNonExemptEncryption)
   - Privacy manifest present
   - API usage compliant

### Step 4.4: Validation Results

**✅ SUCCESS:**
- Dialog: **"App validation completed successfully"**
- Click **"Done"**
- Proceed to upload (Step 5)

**❌ FAILURE:**
- Dialog shows errors or warnings
- **Warnings:** Usually safe to ignore, but review
- **Errors:** Must fix before upload
- See "Troubleshooting Validation Errors" below
- After fixing, increment build number and re-archive

---

## Part 5: Upload to App Store Connect

### Step 5.1: Start Upload

1. In **Xcode Organizer**, ensure your archive is selected

2. Click **"Distribute App"** button

3. Same configuration screens as validation (Step 4.2)
   - Distribution method: **App Store Connect**
   - Destination: **Upload**
   - Options: Same as validation
   - Signing: Automatically manage

4. Review ScreenTimeRewards.ipa

5. Click **"Upload"**

### Step 5.2: Upload Progress

1. Dialog: **"Uploading ScreenTimeRewards.ipa..."**

2. **Progress bar** (5-15 minutes depending on internet speed)
   - Archive size: ~10-20 MB (actual upload may be larger with symbols)
   - Upload includes: Main app + 3 extensions + dSYM files (symbols)

3. **Do not close Xcode or put Mac to sleep during upload**

### Step 5.3: Upload Complete

**SUCCESS:**
- Dialog: **"App successfully uploaded"**
- "Your app has been uploaded to App Store Connect. It will be processed and appear in Activity in a few minutes."
- Click **"Done"**

**NEXT:** The build is NOT ready yet - Apple must process it (5-30 minutes)

---

## Part 6: App Store Connect Processing

### Step 6.1: Check Processing Status

1. Open browser: https://appstoreconnect.apple.com

2. **Sign in** with Apple Developer account

3. Click **"My Apps"**

4. Click **"ScreenTime Rewards"** (or your app name)

5. Click **"TestFlight"** tab at top

6. Click **"iOS"** in left sidebar

7. Look for **"Builds"** section

**Initial status:**
- **"Processing"** with spinning icon
- Version 1.0 (1) shown
- "Build uploaded via Xcode"

### Step 6.2: Processing Timeline

**Apple performs:**
- Binary malware scan
- Entitlement verification
- API usage analysis
- Symbol processing (for crash reports)
- Asset optimization

**Expected time:** 5-30 minutes (usually ~10-15 minutes)

**You will receive emails:**
1. **"App upload received"** - Immediate
2. **"Processing complete"** OR **"Invalid binary"** - After processing

### Step 6.3: Check Processing Complete

**Refresh the page** every few minutes until status changes:

**✅ SUCCESS - Status changes to:**
- **Icon:** Green checkmark (instead of spinning icon)
- **Export Compliance:** "Missing Compliance" (this is normal, we'll fix next)
- **Build becomes selectable** for testing

**❌ FAILURE - You receive "Invalid Binary" email:**
- Email explains rejection reason
- Common reasons:
  - Missing required app icon sizes
  - Invalid entitlements (Family Controls not approved)
  - Privacy manifest issues
  - Info.plist errors
- **Solution:** Fix issue, increment build number to 2, re-archive and upload

---

## Part 7: Export Compliance

**CRITICAL:** Your app uses encryption (CloudKit, HTTPS) and must declare export compliance.

### Step 7.1: Provide Export Compliance Information

1. App Store Connect → **TestFlight** → **iOS** → **Builds**

2. Click on build **1.0 (1)**

3. **Export Compliance** section shows: **"Missing Compliance"**

4. Click **"Provide Export Compliance Information"**

### Step 7.2: Answer Questions

**Question 1:**
> "Is your app designed to use cryptography or does it contain or incorporate cryptography?"

- **Answer:** ✓ **YES**

**Why?** Your app uses CloudKit (encrypts data) and HTTPS (encrypts network traffic)

**Question 2:**
> "Does your app qualify for any of the exemptions provided in Category 5, Part 2 of the U.S. Export Administration Regulations?"

- **Answer:** ✓ **YES**

**Question 3:** (Appears after answering YES above)
> "Which exemption applies to your app?"

- **Select:** ✓ **(e) Encryption within an Apple operating system**

**Explanation box (optional but helpful):**
```
This app uses standard encryption provided by Apple's iOS frameworks:
- CloudKit for data synchronization (Apple's built-in encryption)
- HTTPS/TLS for network communication (Apple's URLSession)
- No custom cryptography implemented
```

### Step 7.3: Submit Compliance

1. Click **"Start Internal Testing"** button

2. Export compliance status changes to: **"Complete"** ✓

3. Build is now available for internal testing!

---

## Part 8: Verify Upload Success

### Checklist:

- [ ] Build appears in App Store Connect → TestFlight → iOS → Builds
- [ ] Status shows green checkmark (not "Processing")
- [ ] Export compliance shows "Complete"
- [ ] Version shows 1.0 (1)
- [ ] Build date is today
- [ ] No warnings or errors displayed

**SUCCESS!** Your app is now ready for TestFlight testing.

---

## Troubleshooting

### Build Errors During Archive

#### Error: "Signing for ScreenTimeRewards requires a development team"

**Fix:**
1. ScreenTimeRewards target → Signing & Capabilities
2. Team dropdown → Select your team (KQ5KZR3DQ5)
3. Repeat for ALL extension targets

#### Error: "Provisioning profile doesn't include the Family Controls entitlement"

**Cause:** You haven't received Apple approval for Family Controls distribution entitlement

**Fix:**
1. Visit: https://developer.apple.com/contact/request/family-controls-distribution
2. Submit request (if not already done)
3. Wait for approval email (2-5 days)
4. After approval: Xcode → Preferences → Accounts → Download Manual Profiles
5. Try archiving again

#### Error: "Failed to register bundle identifier"

**Cause:** Bundle ID `i6dev.ScreenTimeRewards` is already taken

**Fix:**
1. Change bundle ID to something unique: `com.yourname.screentimerewards`
2. Update ALL targets (main app + 3 extensions) to use new base ID
3. Update App Store Connect app record to match
4. Update entitlements files (App Groups, iCloud container)

#### Error: "The app icon set named AppIcon did not have any applicable content"

**Fix:**
1. Verify Icon-1024x1024.png exists and is valid
2. Check it has no transparency (alpha channel)
3. Ensure it's added to Assets.xcassets/AppIcon.appiconset
4. Check Contents.json references the file correctly

### Validation Errors

#### "Invalid Icon. Icon dimensions must be 1024x1024"

**Fix:**
```bash
cd ScreenTimeRewards/Assets.xcassets/AppIcon.appiconset
sips -Z 1024 -s format png --deleteColorManagementProperties source_icon.png --out Icon-1024x1024.png
```

#### "This bundle is invalid. The Info.plist file is missing required keys."

**Fix:**
1. Verify Info.plist has all required keys
2. Check extension Info.plist files
3. Ensure NSExtension keys are present for extensions

#### "Asset validation failed. Missing required icon file."

**Fix:**
1. Open Assets.xcassets → AppIcon
2. Ensure ALL iOS icon slots are filled
3. Re-drag icons if necessary
4. Clean build and re-archive

### Upload Errors

#### "Unable to process application - An error occurred uploading to the App Store"

**Fix:**
1. Check internet connection
2. Try uploading again (sometimes Apple's servers are overloaded)
3. Use Application Loader as alternative (Xcode → Open Developer Tool → Application Loader)

#### Upload hangs at 99% for 30+ minutes

**Fix:**
1. Cancel upload
2. Quit Xcode completely
3. Restart Xcode
4. Try uploading again
5. If persists, wait 1 hour and retry (Apple server issue)

---

## Next Steps After Upload

1. **Wait for processing** (check email or App Store Connect)

2. **Provide export compliance** (Step 7)

3. **Set up internal testing:**
   - TestFlight → Internal Testing → Add testers
   - Create testing notes
   - Enable automatic distribution

4. **Test installation:**
   - Install on your device via TestFlight
   - Verify subscription purchase flow
   - Test device pairing

5. **Prepare for external testing** (optional):
   - Submit for Beta App Review
   - Create public test link
   - Gather broader feedback

6. **Fix bugs and iterate:**
   - Increment build number for each upload
   - Update "What to Test" notes for each build

---

## For Subsequent Uploads (Build 2, 3, etc.)

When uploading new builds:

1. **Increment build number:**
   - All targets → General → Build: Change from `1` to `2`
   - Version can stay `1.0` (change to `1.1`, `2.0`, etc. for feature releases)

2. **Clean, archive, upload** (same process as above)

3. **No export compliance needed** (only required for first build of each version)

4. **Update "What to Test"** in App Store Connect with changes/fixes

---

## Summary

✅ **Preparation:** Add Privacy Manifest, verify settings
✅ **Archive:** Clean → Select device → Product → Archive
✅ **Validate:** Catches errors before upload
✅ **Upload:** Distribute App → App Store Connect
✅ **Processing:** Wait 5-30 minutes
✅ **Export Compliance:** Standard encryption exemption
✅ **Ready for Testing:** Add testers and start gathering feedback

**Time investment:** ~1 hour first time, ~20 minutes for subsequent uploads

Good luck with your TestFlight launch! 🚀
