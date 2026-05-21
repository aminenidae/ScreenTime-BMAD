# iOS 26 Beta: DeviceActivityReportExtension Validation Conflict

## Issue Summary

When building with Xcode 26 beta for iOS 26 beta, there is a conflict between device runtime requirements and App Store Connect validation for `DeviceActivityReportExtension` extensions.

**Date Discovered:** January 16, 2026
**Affected Extension Type:** `com.apple.deviceactivityui.report-extension`
**Status:** Resolved with two-plist workaround (Mar 3, 2026) — Apple bug still unfixed

---

## The Conflict

### iOS 26 Device Runtime
```
Error: Appex bundle defines either an NSExtensionMainStoryboard or
NSExtensionPrincipalClass key, which is not allowed for the extension
point com.apple.deviceactivityui.report-extension
```

**Behavior:** iOS 26 runtime **rejects** `NSExtensionPrincipalClass` in the extension's Info.plist.

### App Store Connect Validation
```
Error: Missing Info.plist values. No values for NSExtensionMainStoryboard
or NSExtensionPrincipalClass found in extension Info.plist for
ScreenTimeRewards.app/PlugIns/ScreenTimeReportExtension.appex.
```

**Behavior:** App Store validation **requires** `NSExtensionPrincipalClass` in the extension's Info.plist.

---

## Technical Details

### Extension Configuration

**File:** `ScreenTimeReportExtension/Info.plist`

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.deviceactivityui.report-extension</string>
    <key>NSExtensionPrincipalClass</key>
    <string>ScreenTimeReportExtension.ScreenTimeReportExtension</string>
</dict>
```

### Swift Entry Point

**File:** `ScreenTimeReportExtension/ScreenTimeReportExtension.swift`

```swift
@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { report in
            TotalActivityView(report: report)
        }
    }
}
```

The `@main` attribute should be sufficient to identify the entry point, and iOS 26 enforces this by rejecting explicit `NSExtensionPrincipalClass`. However, App Store Connect validation has not been updated to reflect this change.

---

## Environment

- **macOS:** 26.1 (Build 25B78)
- **Xcode:** 26.0.1 (Build 17A400)
- **iOS Device:** 26.2 (Build 23C55)
- **Device:** iPhone 15 (iPhone15,4)

---

## Permanent Fix (Mar 3, 2026)

Since no single static plist satisfies both requirements, two Info.plist files are used — one per build configuration. This eliminates manual toggling entirely.

### How It Works

**`ScreenTimeReportExtension/Info.plist`** — used by **Release** (Archive/App Store):
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.deviceactivityui.report-extension</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).ScreenTimeReportExtension</string>
</dict>
```

**`ScreenTimeReportExtension/Info-Debug.plist`** — used by **Debug** (device testing):
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.deviceactivityui.report-extension</string>
</dict>
```

The `project.pbxproj` build settings for `ScreenTimeReportExtension`:
- Debug config (`43E1F0302F1A000100123450`): `INFOPLIST_FILE = ScreenTimeReportExtension/Info-Debug.plist`
- Release config (`43E1F0312F1A000100123450`): `INFOPLIST_FILE = ScreenTimeReportExtension/Info.plist`

### Result

| Configuration | `NSExtensionPrincipalClass` in built appex | Outcome |
|---|---|---|
| Debug (device) | Absent | Device install succeeds on iOS 26 |
| Release (archive) | Present | App Store Connect validation passes |

### Maintenance Note

The two files are identical except for the `NSExtensionPrincipalClass` key. When bumping `CFBundleVersion`, `CFBundleShortVersionString`, or making any other plist changes, **update both files** to keep them in sync.

---

## Resolution

The two-plist approach (Mar 3, 2026) resolves the conflict without requiring Apple to fix either side. If Apple eventually fixes one side, the fix can be simplified:
- If iOS 26 stops rejecting the key → delete `Info-Debug.plist`, revert both configs to `Info.plist`
- If App Store Connect stops requiring the key → remove key from `Info.plist`, delete `Info-Debug.plist`, revert configs

Apple's underlying bug still exists as of iOS 26.3 / Xcode 26.2 (confirmed March 2026 — no fix in Xcode 26.1.1, 26.2, or 26.3 release notes).

---

## Related Files

- `ScreenTimeReportExtension/Info.plist` - Release config plist (with `NSExtensionPrincipalClass` for App Store)
- `ScreenTimeReportExtension/Info-Debug.plist` - Debug config plist (without key for device install)
- `ScreenTimeReports.xcodeproj/project.pbxproj` - `INFOPLIST_FILE` set per configuration
- `ScreenTimeReportExtension/ScreenTimeReportExtension.swift` - Entry point with `@main`
- `ScreenTimeReportExtension/TotalActivityReport.swift` - Report scene implementation
- `ScreenTimeReportExtension/TotalActivityView.swift` - Report UI

---

## Timeline

| Time | Action | Result |
|------|--------|--------|
| 1:57 PM | Archive with auto-generated NSExtensionPrincipalClass | App Store validation passed |
| Later | Source changes triggered rebuild | NSExtensionPrincipalClass stopped being auto-generated |
| Evening | Manual add of NSExtensionPrincipalClass | App Store validation passes, device install fails |
| Evening | Remove NSExtensionPrincipalClass | Device install works, App Store validation fails |

---

## Notes

- The ScreenTimeActivityExtension (`com.apple.deviceactivity.monitor-extension`) does NOT have this issue - it requires and accepts `NSExtensionPrincipalClass`
- Only the report-extension type (`com.apple.deviceactivityui.report-extension`) exhibits this conflict
- This appears to be specific to iOS 26 beta - earlier iOS versions may not have this restriction
