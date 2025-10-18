# ShieldConfiguration Extension - Xcode Setup Guide

**Date:** 2025-10-16
**Time Required:** 10-15 minutes
**Difficulty:** Medium

---
Ignore this path unless asked to use this guide.
## 📦 Files Created (Ready to Use!)

All extension files have been created in:
```
ScreenTimeRewardsProject/ScreenTimeShieldConfiguration/
├── ShieldConfigurationExtension.swift  ✅ Main extension code
├── Info.plist                          ✅ Extension configuration
└── ScreenTimeShieldConfiguration.entitlements ✅ Capabilities
```

---

## 🔧 Xcode Setup Steps (Manual - Required)

### Step 1: Add Extension Target to Xcode Project

1. **Open Xcode project:**
   ```bash
   cd ScreenTimeRewardsProject
   open ScreenTimeRewards.xcodeproj
   ```

2. **Add new target:**
   - Click on project in Navigator (top of file list)
   - Click **"+"** button at bottom of targets list
   - Choose **iOS → Application Extension → Shield Configuration Extension**
   - Click **Next**

3. **Configure target:**
   - **Product Name:** `ScreenTimeShieldConfiguration`
   - **Team:** (Select your team)
   - **Organization Identifier:** `com.screentimerewards`
   - **Bundle Identifier:** `com.screentimerewards.ScreenTimeShieldConfiguration`
   - **Language:** Swift
   - **Project:** ScreenTimeRewards
   - **Embed in Application:** ScreenTimeRewards
   - Click **Finish**

4. **Activate scheme (if prompted):**
   - Click **Activate** when Xcode asks to activate the new scheme

---

### Step 2: Replace Default Files with Our Implementation

Xcode created template files. We need to replace them with our implementation:

1. **Delete Xcode's template files:**
   - In Project Navigator, find `ScreenTimeShieldConfiguration` folder
   - Select these files and **DELETE** (Move to Trash):
     - `ShieldConfigurationExtension.swift` (template)
     - `Info.plist` (template)
     - Any other auto-generated files

2. **Add our implementation files:**
   - **Right-click** on `ScreenTimeShieldConfiguration` folder
   - Choose **Add Files to "ScreenTimeRewards"...**
   - Navigate to: `ScreenTimeRewardsProject/ScreenTimeShieldConfiguration/`
   - Select ALL files:
     - `ShieldConfigurationExtension.swift` ✅
     - `Info.plist` ✅
     - `ScreenTimeShieldConfiguration.entitlements` ✅
   - **Important:** Check **"Copy items if needed"** (UNCHECKED - files are already in place)
   - **Important:** Under "Add to targets", check **ScreenTimeShieldConfiguration** ONLY
   - Click **Add**

---

### Step 3: Configure Target Settings

1. **Select extension target:**
   - Click on project in Navigator
   - Select **ScreenTimeShieldConfiguration** target from list

2. **General tab:**
   - **Deployment Info:**
     - iOS: 15.0 (or higher)
   - **Frameworks, Libraries, and Embedded Content:**
     - Should auto-include: ManagedSettings.framework, ManagedSettingsUI.framework
     - If missing, click **"+"** and add them

3. **Signing & Capabilities tab:**

   **a. Configure Signing:**
   - **Automatically manage signing:** ✅ (checked)
   - **Team:** (Select your team)
   - **Bundle Identifier:** `com.screentimerewards.ScreenTimeShieldConfiguration`

   **b. Add Family Controls capability:**
   - Click **"+ Capability"**
   - Search for **"Family Controls"**
   - Add it
   - Under Family Controls:
     - **Request Authorization:** Individual

   **c. Add App Groups capability:**
   - Click **"+ Capability"**
   - Search for **"App Groups"**
   - Add it
   - Click **"+"** under App Groups
   - Enter: `group.com.screentimerewards.shared`
   - **Important:** Must match EXACT name in main app!

4. **Build Settings tab:**
   - Search for: "Defines Module"
   - Set **Defines Module** to **YES**

---

### Step 4: Verify Entitlements File

1. **Select ScreenTimeShieldConfiguration target**
2. **Build Settings tab**
3. **Search for:** "Code Signing Entitlements"
4. **Set to:** `ScreenTimeShieldConfiguration/ScreenTimeShieldConfiguration.entitlements`
5. If not set, enter the path manually

---

### Step 5: Update Main App Info.plist (If Needed)

1. **Select ScreenTimeRewards target** (main app)
2. **Info tab**
3. **Check for NSExtension keys** - should already be present
4. If building fails, may 
need to add:
   - Key: `NSExtensionPointIdentifier`
   - Value: `com.apple.ManagedSettingsUI.ShieldConfiguration`

---

### Step 6: Build and Verify

1. **Clean build folder:**
   - Product → Clean Build Folder (Shift+Cmd+K)

2. **Select main app scheme:**
   - Top toolbar: Select **ScreenTimeRewards** scheme
   - Select your physical device (NOT simulator)

3. **Build:**
   - Product → Build (Cmd+B)
   - Watch for errors in Issue Navigator

4. **Expected result:**
   - ✅ Build succeeds
   - ✅ No signing errors
   - ✅ Extension embedded in app bundle

---

## 🔍 Troubleshooting

### Error: "Signing for ScreenTimeShieldConfiguration requires a development team"
**Fix:**
- Select extension target
- Signing & Capabilities → Team → Select your team

### Error: "Code signing entitlements file not found"
**Fix:**
- Build Settings → Code Signing Entitlements
- Set to: `ScreenTimeShieldConfiguration/ScreenTimeShieldConfiguration.entitlements`

### Error: "App Group not found"
**Fix:**
- Both main app AND extension must have SAME App Group
- Check main app: `group.com.screentimerewards.shared`
- Check extension: `group.com.screentimerewards.shared`
- Spelling must be identical!

### Error: "ManagedSettingsUI framework not found"
**Fix:**
- Extension target → General → Frameworks and Libraries
- Click "+" → Add ManagedSettings.framework
- Click "+" → Add ManagedSettingsUI.framework

### Build succeeds but extension doesn't run
**Fix:**
- Extension only runs when shield is triggered
- Must block an app first
- Try opening blocked app to trigger shield

---

## ✅ Verification Checklist

After setup, verify:

- [ ] Extension target exists in project
- [ ] Extension files added to target (not main app)
- [ ] Bundle ID: `com.screentimerewards.ScreenTimeShieldConfiguration`
- [ ] Family Controls capability added to extension
- [ ] App Groups capability added to extension
- [ ] App Group name matches main app exactly
- [ ] Entitlements file configured
- [ ] Build succeeds without errors
- [ ] Extension embedded in app bundle

---

## 🧪 Quick Test

**After setup:**

1. **Run app on device**
2. **Block a reward app** (e.g., any game or social app)
3. **Exit app** (home button)
4. **Try to open blocked app**
5. **Expected:** Custom shield screen appears with:
   - Orange background (reward app)
   - Game controller icon
   - App's real name (not "Unknown App")
   - Custom message

6. **Check console for:**
   ```
   [ShieldConfig] 🎯 Shielding app:
   [ShieldConfig]   Bundle ID: com.example.app
   [ShieldConfig]   Display Name: AppName
   [ShieldConfig] 🎮 Auto-categorized as Reward
   [ShieldConfig] ✅ Stored mappings for com.example.app
   ```

---

## 📋 Next Steps (After Setup)

Once extension is working:

1. **Update main app** to read bundle ID mappings
2. **Test auto-categorization** for various apps
3. **Verify shared storage** works correctly
4. **Compare** auto-categorization vs manual assignment

See `PATH2_SHIELDCONFIGURATION_PLAN.md` for full implementation details.

---

## 🆘 Need Help?

**Common issues:**
- Extension not running → Check it's embedded in main app
- No bundle IDs → Check console logs when shield appears
- Signing errors → Verify team and entitlements
- App Group errors → Verify EXACT same name in both targets

**Debug tips:**
- Use console logs to verify extension runs
- Check App Group UserDefaults for stored mappings
- Test with well-known apps (Instagram, YouTube, etc.)
- Verify shield appears when blocked app opened
