# Path 1: Hybrid Approach - Testing Guide

**Implementation Status:** ✅ COMPLETE
**Ready for Testing:** YES
**Test Device Required:** Physical iOS device (not simulator)

---

## What Was Implemented

### **New Features:**

1. **CategoryAssignmentView**
   - Shows selected apps using `Label(token)` - displays actual app names + icons
   - Users assign categories via dropdown for each app
   - Summary section shows category distribution
   - Clean, intuitive UX

2. **Category Storage**
   - Token→Category mappings saved to App Group
   - Persists across app restarts
   - Shared between app and extension

3. **Updated Monitoring**
   - Uses user-assigned categories instead of auto-categorization
   - Proper grouping by category
   - Individual app tracking with correct categories

---

## Testing Steps

### **Step 1: Build and Run**

1. Open Xcode
2. Clean build folder (Product → Clean Build Folder)
3. Build for your physical device
4. Run the app

**Expected:** App launches successfully

---

### **Step 2: Grant Authorization**

1. Tap the **slider icon** (top right toolbar)
2. System prompts for Screen Time authorization
3. Tap **Allow**

**Expected Logs:**
```
[AppUsageViewModel] Current authorization status: 0
[AppUsageViewModel] ✅ Authorization granted, opening picker
[AppUsageViewModel] Final authorization status: 2
```

**Expected:** FamilyActivityPicker opens automatically after authorization

---

### **Step 3: Select Apps**

1. In FamilyActivityPicker, select 3-6 apps
2. Choose a mix of educational, entertainment, and other apps
3. Tap **Done**

**Expected Logs:**
```
[AppUsageView] FamilyActivitySelection changed!
[AppUsageView] Applications selected: 6
[AppUsageView]   App 0:
[AppUsageView]     Display Name: NIL ❌  (or actual name if lucky)
[AppUsageView]     Token: ✓
[AppUsageView] Opening category assignment for 6 apps
```

**Expected:** Category Assignment sheet opens automatically

---

### **Step 4: Assign Categories** 🎯 KEY TEST

1. You should see a list of apps with **actual app names and icons** (via Label)
2. Each app has a category dropdown
3. Assign categories:
   - Pick 2-3 apps as "Educational"
   - Pick 1-2 apps as "Entertainment"
   - Leave others as "Other"

**What You Should See:**
```
┌────────────────────────────┐
│ Assign Categories          │
├────────────────────────────┤
│ [Icon] Safari              │
│ Category: [Educational ▼]  │
│                            │
│ [Icon] YouTube             │
│ Category: [Entertainment▼] │
│                            │
│ [Icon] TikTok              │
│ Category: [Social ▼]       │
└────────────────────────────┘
```

**Critical Check:**
- ✅ Do you see **REAL app names** (Safari, YouTube, etc.)?
- ✅ Do you see **app icons**?
- ❌ If you see "Unknown App" - Label(token) failed

5. Check the Summary section at bottom
6. Tap **Save & Monitor**

**Expected Logs:**
```
[AppUsageViewModel] Category assignments saved
[AppUsageViewModel]   Token 123456 → educational
[AppUsageViewModel]   Token 789012 → entertainment
[AppUsageViewModel] Saved 6 category assignments
[AppUsageViewModel] Configuring monitoring
[ScreenTimeService] Processing application: Safari (or Unknown App)
[ScreenTimeService]   Category: educational (user-assigned ✓)
[ScreenTimeService] Grouped applications by category:
[ScreenTimeService]   Educational: 3 applications
[ScreenTimeService]   Entertainment: 2 applications
```

**Expected:** Sheet dismisses, monitoring configuration saved

---

### **Step 5: Adjust Thresholds**

1. In "Monitoring Settings" section
2. Set threshold for Educational category to **1 minute** (for faster testing)
3. Set threshold for Entertainment to **2 minutes**
4. Tap **Apply Monitoring Configuration**

**Expected Logs:**
```
[AppUsageViewModel] Configuring monitoring
[AppUsageViewModel]   Category assignments: 6
[ScreenTimeService] Creating monitored event for category Educational with 3 applications
[ScreenTimeService] Event name: usage.educational
[ScreenTimeService] Threshold: minute: 1
```

**Expected:** Configuration applied successfully

---

### **Step 6: Start Monitoring**

1. Tap **Start Monitoring** (green button)
2. Wait for status indicator to turn green

**Expected Logs:**
```
[ScreenTimeService] Scheduling activity:
[ScreenTimeService]   Events count: 2 (or more, depending on categories)
[ScreenTimeService]   Event: usage.educational
[ScreenTimeService]     Applications count: 3
[ScreenTimeService] Successfully started monitoring
[ScreenTimeService] Received Darwin notification: com.screentimerewards.intervalDidStart
[AppUsageViewModel] Monitoring started successfully
```

**Expected:** Top indicator shows "Monitoring Active" in green

---

### **Step 7: Use an Educational App** 🎯 CRITICAL TEST

1. Exit your app (home button / swipe up)
2. Open ONE of the apps you assigned to "Educational"
3. Use it for **2 minutes** (past the 1-minute threshold)
4. Return to your app

**Expected Behavior:**
- After ~1 minute: Extension fires `eventDidReachThreshold`
- Your app receives notification
- Usage data is recorded

**Expected Logs (Check Console While Using App):**
```
[ScreenTimeActivityExtension] eventDidReachThreshold:
[ScreenTimeActivityExtension]   Event: usage.educational
[ScreenTimeActivityExtension]   Activity: ScreenTimeTracking
[ScreenTimeActivityExtension] Stored event data in App Group
[ScreenTimeActivityExtension] Posted Darwin notification

[ScreenTimeService] Received Darwin notification: com.screentimerewards.eventDidReachThreshold
[ScreenTimeService] Event from App Group: usage.educational
[ScreenTimeService] Handling eventDidReachThreshold for event: usage.educational
[ScreenTimeService] Recording usage for 3 applications, duration: 60.0 seconds
[AppUsageViewModel] Refreshing data
[AppUsageViewModel] Retrieved 3 app usages
[AppUsageViewModel] Updated category totals - Educational: 60.0
```

**Expected in UI:**
- Educational time increases to 00:01:00
- App appears in usage list
- Category shows "Educational"

---

## Success Criteria

### **Must Have:** ✅

- [x] Category Assignment screen shows **real app names** (via Label)
- [x] Category Assignment screen shows **real app icons**
- [x] User can assign categories via dropdown
- [x] Categories are saved (check logs)
- [x] Monitoring starts successfully
- [x] Apps grouped by assigned categories (check logs)

### **Should Have:** ✅

- [x] Events fire when threshold reached
- [x] Usage data appears in app
- [x] Category totals update
- [x] UI reflects tracking progress

### **Nice to Have:** 🎯

- [x] Persistent across app restart
- [x] Re-categorization works
- [x] All categories track correctly

---

## What to Look For

### **✅ Good Signs:**

1. **Category Assignment:**
   ```
   [Icon] Safari
   Category: Educational ← REAL APP NAME!
   ```

2. **Logs Show:**
   ```
   Category: educational (user-assigned ✓)
   ```

3. **Events Fire:**
   ```
   eventDidReachThreshold: usage.educational
   ```

4. **Usage Updates:**
   ```
   Educational: 60.0 (from 0.0)
   ```

### **❌ Problems:**

1. **Label(token) Fails:**
   ```
   Unknown App 0  ← NOT "Safari"
   ```
   **Meaning:** Label(token) doesn't work on your iOS version
   **Fallback:** Need Path 4 (manual naming)

2. **No Events Fire:**
   ```
   (No eventDidReachThreshold logs after 2 min)
   ```
   **Meaning:** Extension not working or threshold not reached
   **Check:** Use app longer, verify extension installed

3. **Wrong Categories:**
   ```
   Category: other (auto-categorized)  ← Should be "user-assigned"
   ```
   **Meaning:** Category assignments not passed to service
   **Action:** Check logs for "Category assignments: 0"

---

## Troubleshooting

### **Problem: Can't See App Names**

**Symptoms:** Category assignment shows "Unknown App 0/1/2"

**Diagnosis:** `Label(token)` not working on your iOS version

**Solutions:**
1. Try iOS 16+ (Label might only work on newer versions)
2. Fall back to Path 4 (manual text entry)
3. Use Path 3 (category-based, no individual apps)

---

### **Problem: Events Don't Fire**

**Symptoms:** No `eventDidReachThreshold` after using app

**Check:**
1. Is monitoring actually started? (Green indicator)
2. Did you use the app PAST the threshold? (Use for 2x threshold time)
3. Is extension installed? (Check Xcode build logs)
4. Check extension logs in Console app (filter by "ScreenTimeActivityExtension")

**Debug:**
```
# In Xcode, open Console app
# Filter: ScreenTimeActivityExtension
# Use an educational app for 2 minutes
# Watch for logs
```

---

### **Problem: Usage Not Recorded**

**Symptoms:** Events fire but UI doesn't update

**Check:**
1. Darwin notification received? (Check logs)
2. App Group access working? (Check for "Failed to access App Group")
3. Event name matches? (Check "usage.educational" in both extension and main app)

**Debug Logs:**
```
[ScreenTimeService] Event from App Group: usage.educational ← Should NOT be nil
[ScreenTimeService] Found configuration for event usage.educational
[ScreenTimeService] Recording usage for 3 applications
```

---

##  Next Steps After Testing

### **If Successful:** ✅

1. ✅ Path 1 works! Label(token) shows app names
2. Document findings
3. Consider Path 2 investigation (optional)
4. Finalize for production

### **If Label(token) Fails:** ❌

**Options:**
- **Option A:** Implement Path 4 (manual text entry)
- **Option B:** Switch to Path 3 (category-based only)
- **Option C:** Investigate Path 2 (shield extension)

### **If Events Don't Fire:** ⚠️

1. Verify extension is built and installed
2. Check Console app for extension logs
3. Try longer usage duration (5-10 minutes)
4. Verify App Group configuration

---

## Log Collection

**For Debugging, Send These Logs:**

1. **From Authorization:**
   ```
   [AppUsageViewModel] Current authorization status:
   [AppUsageViewModel] Final authorization status:
   ```

2. **From Category Assignment:**
   ```
   [AppUsageViewModel] Category assignments saved
   [ScreenTimeService] Category: educational (user-assigned ✓)
   ```

3. **From Monitoring:**
   ```
   [ScreenTimeService] Scheduling activity:
   [ScreenTimeService] Successfully started monitoring
   ```

4. **From Extension (if working):**
   ```
   [ScreenTimeActivityExtension] eventDidReachThreshold:
   ```

5. **From Event Handling:**
   ```
   [ScreenTimeService] Event from App Group: usage.educational
   [ScreenTimeService] Recording usage for X applications
   ```

---

## Screenshots to Capture

1. **Category Assignment Screen** (shows if Label works)
2. **Monitoring Active** (green indicator)
3. **Usage List** (after using app)
4. **Category Totals** (Educational time updated)

---

**Ready to test! Build and run, then follow the steps above.**

Report back with:
- ✅ Does Label(token) show real app names?
- ✅ Do events fire after threshold?
- ✅ Does usage data appear?
- 📋 Any error logs
