# TestFlight Launch Documentation

**Complete documentation for launching ScreenTime Rewards on TestFlight**

---

## 📋 Quick Status

### ✅ COMPLETED
- All 4 critical Xcode configuration issues fixed
- Privacy Manifest created
- Deployment targets corrected
- Push notifications set to production
- Export compliance key added

### ⚠️ ACTION REQUIRED
1. **Add Privacy Manifest to Xcode** (2 minutes)
2. **Publish Terms & Privacy pages** (10-60 minutes)
3. **Configure App Store Connect** (45-60 minutes)
4. **Archive and upload** (30-45 minutes)

---

## 📚 Documentation Index

### 1. [Terms of Service Template](./terms-of-service.md)
Complete, ready-to-customize Terms of Service covering:
- Subscriptions and billing
- Acceptable use policy
- Privacy and data protection
- COPPA compliance for children
- Dispute resolution

**Action:** Customize placeholder fields [in brackets] and publish at:
- https://screentimerewards.com/terms

---

### 2. [Privacy Policy Template](./privacy-policy.md)
Comprehensive Privacy Policy aligned with your app's actual data practices:
- What data is collected (minimal, iCloud-based)
- How data is used (app functionality only)
- COPPA, CCPA, and GDPR compliance
- Children's privacy protections
- No tracking or third-party sharing

**Action:** Customize placeholder fields and publish at:
- https://screentimerewards.com/privacy

---

### 3. [Xcode Archive Guide](./xcode-archive-guide.md)
Step-by-step instructions for:
- Adding Privacy Manifest to Xcode (CRITICAL)
- Verifying project configuration
- Creating archive
- Validating before upload
- Uploading to App Store Connect
- Handling export compliance
- Troubleshooting common errors

**Action:** Follow carefully, especially the Privacy Manifest step

---

### 4. [App Store Connect Configuration Guide](./app-store-connect-guide.md)
Complete setup for:
- Creating app record
- Configuring 3 subscription products
- Setting up Sandbox test accounts
- App Privacy declarations
- TestFlight internal/external testing
- Demo account preparation

**Action:** Complete before first TestFlight upload

---

## 🚀 Quick Start Checklist

### Phase 1: Publish Legal Pages (10-60 min)

**Option A - Quick GitHub Pages Setup (10 minutes):**
```bash
# Create GitHub repo for hosting
# Copy terms-of-service.md and privacy-policy.md
# Enable GitHub Pages
# Point screentimerewards.com/terms and /privacy to repo
```

**Option B - Use Template Generator (30-60 minutes):**
- Visit: https://www.termsfeed.com or https://www.iubenda.com
- Customize templates for your specific app
- Download and publish to your domain

**Option C - Host on Notion/Google Sites (15-30 minutes):**
- Create public Notion page or Google Site
- Copy content from templates
- Share public URL

**CRITICAL:** URLs must be accessible before TestFlight submission completes.

---

### Phase 2: Add Privacy Manifest to Xcode (2 minutes)

```bash
# File already created at:
# /Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/ScreenTimeRewards/PrivacyInfo.xcprivacy

# Steps:
1. Open ScreenTimeRewards.xcodeproj in Xcode
2. Right-click ScreenTimeRewards folder (blue icon)
3. Select "Add Files to ScreenTimeRewards..."
4. Navigate to PrivacyInfo.xcprivacy
5. Check "ScreenTimeRewards" target ONLY
6. Click "Add"
7. Verify file appears in Project Navigator
8. Save project (Cmd+S)
```

---

### Phase 3: Configure App Store Connect (45-60 min)

Follow [app-store-connect-guide.md](./app-store-connect-guide.md):

**Priority 1 - Required for TestFlight:**
- [ ] Create app record (bundle ID: `i6dev.ScreenTimeRewards`)
- [ ] Create 3 subscriptions:
  - [ ] com.screentimerewards.individual.monthly ($7.99/month)
  - [ ] com.screentimerewards.family.monthly ($12.99/month)
  - [ ] com.screentimerewards.family.yearly ($59.99/year)
- [ ] Submit subscriptions for review
- [ ] Create Sandbox test account
- [ ] Complete App Privacy configuration

**Priority 2 - Can wait until App Store submission:**
- Screenshots and descriptions
- Keywords and support URL
- Marketing materials

---

### Phase 4: Archive & Upload (30-45 min)

Follow [xcode-archive-guide.md](./xcode-archive-guide.md):

**Steps:**
1. Clean Build Folder (Shift+Cmd+K)
2. Select "Any iOS Device (arm64)"
3. Product → Archive
4. Validate App (recommended, catches errors early)
5. Distribute App → Upload to App Store Connect
6. Wait for processing (5-30 minutes)
7. Provide export compliance (standard encryption exemption)
8. Add internal testers
9. Install via TestFlight and test!

---

## 📁 File Structure

```
/Users/ameen/Documents/ScreenTime-BMAD/
├── ScreenTimeRewardsProject/
│   ├── ScreenTimeRewards/
│   │   ├── PrivacyInfo.xcprivacy ✅ (created, needs to be added to Xcode)
│   │   ├── Info.plist ✅ (export compliance key added)
│   │   └── ScreenTimeRewards.entitlements ✅ (production push notifications)
│   └── ScreenTimeRewards.xcodeproj/
│       └── project.pbxproj ✅ (deployment target fixed)
└── docs/
    ├── README.md (this file)
    ├── terms-of-service.md ✅
    ├── privacy-policy.md ✅
    ├── xcode-archive-guide.md ✅
    └── app-store-connect-guide.md ✅
```

---

## ⚠️ Important Notes

### Terms & Privacy Policy Customization

**BEFORE PUBLISHING, replace these placeholders:**

**In terms-of-service.md:**
- `[Your State/Country]` → Your jurisdiction (e.g., "California" or "United States")
- `[your-email@example.com]` → Your support email
- `[dpo@example.com]` → Data Protection Officer email (if applicable for GDPR)
- Review all subscription details match your actual implementation

**In privacy-policy.md:**
- `[your-email@example.com]` → Your support email
- `[Your Business Address]` → Physical mailing address (required for GDPR)
- `[dpo@example.com]` → DPO email (if you have one)
- Verify all data collection statements match your app

### Legal Disclaimer

**These templates are starting points, not legal advice.**

**We recommend:**
1. Consult with an attorney familiar with:
   - App Store regulations
   - COPPA (Children's Online Privacy Protection Act)
   - CCPA (California Consumer Privacy Act)
   - GDPR (if targeting EU users)

2. Consider legal services:
   - **TermsFeed** - https://www.termsfeed.com (templates + legal review)
   - **Iubenda** - https://www.iubenda.com (automated policy generation)
   - **LegalZoom** - For attorney consultations

3. Update policies as your app evolves:
   - New features may require privacy updates
   - Data collection changes must be disclosed
   - Always update "Last Updated" date

---

## 🐛 Troubleshooting

### "Privacy Manifest not found" error during upload

**Fix:**
1. Verify PrivacyInfo.xcprivacy is in Project Navigator (not grayed out)
2. Check Build Phases → Copy Bundle Resources → File is listed
3. Clean Build Folder and re-archive

### Subscription "Product not found" in app

**Causes:**
1. Subscriptions not submitted for review in App Store Connect
2. Product IDs don't match code exactly
3. Not signed into Sandbox account on device

**Fix:**
1. App Store Connect → In-App Purchases → Submit each subscription
2. Verify product IDs: `com.screentimerewards.individual.monthly` (exact match)
3. Device Settings → App Store → SANDBOX ACCOUNT → Sign in

### "Invalid Binary" email after upload

**Common reasons:**
1. Missing app icon sizes (especially 1024x1024)
2. Invalid entitlements (Family Controls not approved)
3. Info.plist errors

**Fix:**
- Read email for specific error code
- Fix issue in Xcode
- Increment build number (1 → 2)
- Re-archive and upload

### Can't find bundle ID in App Store Connect

**Fix:**
1. Register at: https://developer.apple.com/account/resources/identifiers/list
2. Create new App ID with bundle ID: `i6dev.ScreenTimeRewards`
3. Enable capabilities: In-App Purchase, iCloud, App Groups, Family Controls, Push Notifications
4. Return to App Store Connect and refresh

---

## 📊 Timeline Estimate

| Task | Time | Can Parallelize? |
|------|------|------------------|
| Publish Terms & Privacy | 10-60 min | No (required first) |
| Add Privacy Manifest to Xcode | 2 min | After legal pages |
| Configure App Store Connect | 45-60 min | After legal pages |
| Xcode Archive & Upload | 30-45 min | After App Store Connect |
| Apple Processing | 5-30 min | (automatic) |
| Export Compliance | 2 min | After processing |
| Add Testers & Install | 10 min | Final step |

**Total Time:** 1.5 - 3 hours (depending on legal page option chosen)

**Same-Day TestFlight:** Achievable if you start in the morning

---

## 🎯 Success Criteria

Your TestFlight launch is successful when:

- [ ] Build appears in App Store Connect with green checkmark
- [ ] Export compliance status shows "Complete"
- [ ] Internal testers receive invitation emails
- [ ] App installs via TestFlight on test device
- [ ] Subscription purchase flow works with Sandbox account
- [ ] QR code pairing works between two devices
- [ ] CloudKit sync working (data appears on second device)
- [ ] No crashes during basic testing
- [ ] Family Controls authorization granted successfully

---

## 📞 Support

If you encounter issues:

1. **Xcode/Build Errors:** See [xcode-archive-guide.md](./xcode-archive-guide.md) Troubleshooting section
2. **App Store Connect:** See [app-store-connect-guide.md](./app-store-connect-guide.md) Support Resources
3. **Apple Developer Support:** https://developer.apple.com/contact/
4. **App Store Connect Help:** https://help.apple.com/app-store-connect/

---

## 🔄 Next Steps After TestFlight

### Week 1-2: Internal Testing
- Test on multiple devices and iOS versions
- Verify subscription flows thoroughly
- Check CloudKit sync reliability
- Fix critical bugs → upload Build 2

### Week 2-4: Extended Testing
- Add more internal testers (friends, family)
- Test edge cases (offline mode, poor connectivity)
- Gather UX feedback
- Refine onboarding flow if needed

### Week 4+: App Store Preparation
- Create professional screenshots (use designs/mockups)
- Write compelling App Store description
- Prepare app preview video (optional but recommended)
- Submit for full App Store Review
- Plan marketing launch

---

## 📝 Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-28 | 1.0 | Initial TestFlight documentation created |

---

**You're ready to launch! 🚀**

Start with Phase 1 (publish legal pages), then work through each phase sequentially. Take your time, follow the guides carefully, and you'll have a successful TestFlight launch.

Good luck with ScreenTime Rewards!
