# Usage Tracking FAQ

**Last Updated:** 2025-11-19
**App Version:** 1.0

Common questions and troubleshooting for Screen Time Rewards usage tracking.

---

## Quick Start: Best Practices for Accurate Tracking

### ✅ Required Setup

1. **Disable "Share Across Devices"**
   Go to: **iOS Settings → Screen Time → Share Across Devices → OFF**
   ⚠️ **Critical:** This is the #1 cause of tracking inaccuracies!

2. **Grant Screen Time Permissions**
   When prompted, tap "Continue" and authorize Screen Time access.

3. **Keep App Installed**
   The app can run in the background. Force-closing may reduce tracking accuracy to ~80%.

4. **Use Native Apps**
   Choose native learning apps when possible (avoid web-based apps for best accuracy).

### Expected Accuracy

| Scenario | Accuracy | Notes |
|----------|----------|-------|
| **App running or backgrounded** | ~100% | Best case - all threshold events fire correctly |
| **App force-closed** | ~80% | Extension may miss 1-2 events per 10 minutes |
| **"Share Across Devices" enabled** | Unknown | May cause inflated totals (iOS bug) |
| **Web-based apps** | Variable | May trigger Safari double-counting |

---

## Common Questions

### Q: Why is my tracked time different from iOS Settings Screen Time?

**A:** There are several possible reasons:

1. **iOS Screen Time Bug (iOS 17.6.1 - 18.5+)**
   Apple has confirmed a bug causing inflated usage totals in iOS Settings Screen Time.
   **Solution:** Our app uses a different approach that avoids this bug. Trust our totals.

2. **"Share Across Devices" Enabled**
   iOS Settings may include usage from other devices (iPhone, Mac) even when this setting is OFF.
   **Solution:** Disable "Share Across Devices" in iOS Settings → Screen Time.

3. **Different Counting Methods**
   iOS Settings counts all apps; we only count your selected learning/reward apps.
   **Solution:** This is expected - compare specific app totals, not overall screen time.

### Q: Why did my child miss minutes when the app was closed?

**A:** This is a known limitation of iOS background extensions.

**How It Works:**
- When the app is **running or backgrounded:** 100% accuracy ✅
- When the app is **force-closed:** ~80% accuracy (may miss 1-2 minutes per 10 minutes) ⚠️

**Why It Happens:**
iOS may terminate background extensions to save battery and memory. This occasionally causes threshold events to be missed.

**Solution:**
- Tell your child to **keep the app installed** (backgrounded is fine)
- **Don't force-close** the app (swipe up in App Switcher)
- Normal use (pressing home button, switching apps) works perfectly

### Q: I see "Share Across Devices" is enabled. Should I disable it?

**A:** YES! Absolutely disable it.

**Steps:**
1. Open **iOS Settings**
2. Tap **Screen Time**
3. Tap **Share Across Devices**
4. Turn **OFF**

**Why:**
iOS has a confirmed bug where usage from other devices (iPhone, Mac, other iPads) is incorrectly included in tracking, even when this setting is OFF. Disabling it reduces the risk of inflated totals.

### Q: Can I use web-based learning apps (like Khan Academy web)?

**A:** You can, but native apps are more accurate.

**Risk:**
iOS 17.6.1+ has a bug where Safari usage is counted both as "Safari" and as individual websites, causing double-counting.

**Recommendation:**
- ✅ **Use native apps** whenever available (e.g., Khan Academy app, not Safari)
- ⚠️ **Avoid web apps** if you want the most accurate tracking
- If you must use Safari, be aware totals may be slightly inflated

### Q: My child's usage seems too high. Is it accurate?

**Check these common issues:**

1. **"Share Across Devices" Enabled?**
   → Disable in iOS Settings → Screen Time

2. **Multiple iOS Devices on Same Apple ID?**
   → iOS may be including usage from other devices (iPhone, parent's iPad, etc.)
   → Disable Screen Time on other devices or use a different Apple ID for the child's iPad

3. **Learning App Includes Ads or Web Content?**
   → Some apps embed webviews that trigger iOS Safari counting bugs
   → Try switching to a different learning app

4. **Background Usage?**
   → Some apps run in background (music, podcasts)
   → This is legitimate usage - iOS counts it

**Diagnostic Steps:**
1. Go to **Parent Mode → Settings → Tracking Health**
2. Review diagnostic report
3. Check for "Potential Overcounting Detected" warning
4. Follow recommended actions

### Q: My child's usage seems too low. What's wrong?

**Possible Causes:**

1. **App Force-Closed**
   → Extension may have missed threshold events (~80% accuracy)
   → Ask child to keep app installed, not force-close it

2. **Screen Time Permissions Denied**
   → Re-authorize in iOS Settings → Screen Time → App Limits

3. **Learning App Crashed or Hung**
   → iOS may not have counted usage correctly
   → Try different learning app

4. **Challenge Reset During Session**
   → Resetting a challenge clears all usage data
   → This is expected behavior

**Diagnostic Steps:**
1. Go to **Parent Mode → Settings → Extension Diagnostics**
2. Check for missed threshold events
3. Verify Screen Time permissions are granted

---

## Troubleshooting

### Issue: No usage recorded at all

**Solutions:**
1. Verify Screen Time permissions granted
2. Check that learning apps are actually in the challenge
3. Ensure child used learning apps for at least 1 full minute
4. Try "Manual Usage Sync" in Settings → Manual Sync

### Issue: Usage stuck at same number

**Solutions:**
1. Tap "Manual Usage Sync" in Parent Mode → Settings
2. Wait 4-5 minutes (iOS enforces DeviceActivityReport delays)
3. If still stuck, delete and recreate the challenge

### Issue: Duplicate threshold fires (same minute recorded twice)

**This is a critical iOS bug indicator!**

**Solutions:**
1. **Immediately disable "Share Across Devices"** in iOS Settings
2. Disable Screen Time on all other devices using this Apple ID
3. Go to Settings → Tracking Health → Export Diagnostic Report
4. Contact support with diagnostic report

### Issue: Extension diagnostics shows errors

**Common errors and solutions:**

- **"Authorization denied"**
  → Re-grant Screen Time permissions in iOS Settings

- **"Extension crashed"**
  → iOS may have terminated extension due to memory pressure
  → Restart the device, recreate challenge

- **"Threshold event missed"**
  → App was force-closed
  → Keep app installed and backgrounded

---

## Technical Details

### How Our Tracking Works

We use **static threshold events** to track usage:

1. **60 Threshold Events Per App**
   - Event 1 fires at 1 minute of usage
   - Event 2 fires at 2 minutes of usage
   - ... up to Event 60 at 60 minutes

2. **Fixed 60-Second Increments**
   - Each event records exactly 60 seconds
   - We don't rely on Apple's accumulated totals (which can be buggy)

3. **Deduplication Guard**
   - If same event fires twice within 5 seconds, we ignore the duplicate
   - This protects against iOS duplicate callback bugs

### Why We Avoid iOS Overcounting Bugs

**Apple Bug (iOS 17.6.1 - 18.5+):**
iOS Screen Time APIs have confirmed bugs causing 2x+ inflated totals, premature threshold fires, and duplicate callbacks.

**Our Protection:**
- ✅ **Static thresholds** (not dynamic queries)
- ✅ **Specific app tokens** (not broad categories)
- ✅ **No web domain tracking** (avoids Safari double-counting)
- ✅ **Deduplication guards** (ignore rapid re-fires)

**Testing Results:**
- App running: **100% accuracy** ✅
- App force-closed: **80% accuracy** ⚠️
- No evidence of overcounting bugs in our implementation

### Known iOS Limitations

1. **Extension Termination**
   iOS may kill background extensions to save resources.
   **Impact:** ~20% missed events when app force-closed.

2. **4-Minute DeviceActivityReport Delay**
   iOS enforces delays before reports update.
   **Impact:** "Manual Sync" button may need 4-5 minutes to show new data.

3. **Cross-Device Aggregation Bugs**
   iOS incorrectly merges usage even with "Share Across Devices" OFF.
   **Impact:** Inflated totals if other devices active.
   **Solution:** Disable Screen Time on other devices.

---

## Diagnostic Tools

### Parent Mode → Settings → Tracking Health

**What it shows:**
- Current validation status (Healthy / Warning / Error)
- Detected issues with severity levels
- Extension reliability rate
- Recommended actions

**When to use:**
- Child's usage seems inaccurate
- Suspicious large jumps in usage
- Troubleshooting tracking problems

### Parent Mode → Settings → Extension Diagnostics

**What it shows:**
- Extension execution logs
- Threshold event fires
- Missed events
- Crash reports

**When to use:**
- Diagnosing missed usage
- Understanding extension behavior
- Reporting bugs to support

### Export Diagnostic Report

**How to export:**
1. Go to Parent Mode → Settings → Tracking Health
2. Tap "Export Diagnostic Report"
3. Share via Messages, Mail, or Files

**What it includes:**
- Device info (iOS version, model)
- Tracking statistics
- Detected issues
- Configuration recommendations

**When to export:**
- Contacting support
- Reporting suspected bugs
- Sharing with other parents for comparison

---

## Support

### Getting Help

1. **Check This FAQ First**
   Most common issues are covered above.

2. **Run Diagnostics**
   Go to Settings → Tracking Health and review detected issues.

3. **Export Diagnostic Report**
   Include it when contacting support.

4. **Contact Support**
   Email: support@screentimerewards.com
   Include: Diagnostic report + description of issue

### Reporting Bugs

**What to include:**
1. Diagnostic report (Settings → Tracking Health → Export)
2. Screenshots of the issue
3. Steps to reproduce
4. iOS version and device model
5. Whether "Share Across Devices" is enabled

---

## Additional Resources

- **Technical Documentation:** `/docs/SCREENTIME_OVERCOUNTING_ANALYSIS.md`
- **Accuracy Testing:** `/USAGE_TRACKING_ACCURACY.md`
- **Apple DTS Feedback:** FB15103784 (Screen Time API bugs)

---

**Version History:**
- **2025-11-19:** Initial version with iOS 17.6.1 - 18.5 bug analysis
