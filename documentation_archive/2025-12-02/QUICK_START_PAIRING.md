# Quick Start: Pair Parent and Child Devices

## Prerequisites
- ✅ Build succeeded
- ✅ Schema initialized
- ✅ Parent device has app installed
- ❌ **Child device needs app installed** ← DO THIS FIRST

---

## 5-Minute Pairing Guide

### Step 1: Install on Child Device (2 min)

**Find child iPad device ID:**
```bash
xcrun xctrace list devices
```

**Build and install:**
```bash
cd /Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject

xcodebuild build -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination "platform=iOS,id=00008120-001C358E20434032" \
  -allowProvisioningUpdates
```

Replace `00008120-001C358E20434032` with your child iPad's device ID.

---

### Step 2: Clean Up Parent Device (30 sec)

**On Parent iPad:**
1. Open app
2. Parent Remote Dashboard → Tap ⚙️ (gear icon)
3. Tap **"Cleanup Duplicate Devices"**
4. Tap **"Check Local Devices"**
5. Verify shows: `Summary: 1 parent(s), 0 child(ren)`

---

### Step 3: Pair Devices (1 min)

**On Parent iPad:**
1. Go back to Parent Remote Dashboard
2. Tap **"Learn How to Pair Devices"**
3. QR code appears
4. **Keep this screen open**

**On Child iPad:**
1. Launch app
2. Select **"Child Device"**
3. **Tap "Pair with Parent"** (or similar)
4. **Point camera at parent's QR code**
5. Wait for "Pairing Successful" ✅

---

### Step 4: Verify Pairing (30 sec)

**On Parent iPad:**
1. Go back to Parent Remote Dashboard
2. **Pull down to refresh**
3. Child device should appear in list ✅

**If child doesn't appear:**
1. Tap ⚙️ (gear icon)
2. Tap **"Check Local Devices"**
3. Should show: `Summary: 1 parent(s), 1 child(ren)` ✅

---

## Troubleshooting

### Child device not in list after pairing

**Check console logs on parent:**
```
[CloudKitSyncService] Found 0 linked child devices  ← BAD
[CloudKitSyncService] Found 1 linked child devices  ← GOOD ✅
```

**If still showing 0:**
1. Wait 30 seconds for CloudKit sync
2. Pull to refresh again
3. Check debug screen → "Query CloudKit Directly"

### Pairing says "successful" but no device

**On parent debug screen:**
```
Tap "Check Local Devices"
```

Look for:
```
Summary: 1 parent(s), 1 child(ren)  ← GOOD ✅
```

If still showing `0 child(ren)`:
- Check child device logs for errors
- Verify child selected "Child Device" mode
- Try pairing again

---

## Console Logs to Watch

### Parent Device (during pairing)
```
✅ [DevicePairingService] Parent device registered successfully
✅ [CloudKit] Device registered: 0BF15E91-3C6A-4BEC-A9C6-82AC27FEA0FC
```

### Child Device (during pairing)
```
✅ [DevicePairingService] Child device registered with parent ID: 0BF15E91-...
✅ [CloudKit] Device registered: <child-device-id>
```

### Parent Device (after refresh)
```
✅ [CloudKitSyncService] Found 1 linked child devices
✅ [ParentRemoteViewModel] Loaded 1 child devices
```

---

## What Success Looks Like

### Parent Dashboard:
```
Linked Devices
┌─────────────────────────────┐
│ 📱 Child Device             │
│ ID: 442798CD-27D8-4E...     │
│ Last Sync: Just now         │
└─────────────────────────────┘
```

### Debug Screen:
```
CloudKit Status: Available ✅
Registered Devices: 2

Local Core Data:
- ID: 0BF15E91..., Type: parent, ParentID: nil
- ID: 442798CD..., Type: child, ParentID: 0BF15E91...

Summary: 1 parent(s), 1 child(ren) ✅
```

---

## Quick Commands

### Get device ID:
```bash
xcrun xctrace list devices | grep iPad
```

### Build for specific device:
```bash
xcodebuild build -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination "platform=iOS,id=<DEVICE_ID>" \
  -allowProvisioningUpdates
```

### Watch console logs:
```bash
# In Xcode: View → Debug Area → Show Debug Area
# Or: Cmd+Shift+Y
```

---

## Important Notes

1. **Child device MUST have app installed** - cannot pair without it
2. **Both devices must be signed into same iCloud account**
3. **Internet connection required** for CloudKit sync
4. **Camera permissions needed** on child device for QR scanning
5. **Wait 30-60 seconds** after pairing for CloudKit to sync

---

## Next Steps After Successful Pairing

Once pairing works:
1. Test usage data sync (use apps on child, check parent dashboard)
2. Test configuration sync (change settings on parent, verify on child)
3. Test real-time updates (pull to refresh should show latest data)

---

**Ready to pair? Start with Step 1! 🚀**
