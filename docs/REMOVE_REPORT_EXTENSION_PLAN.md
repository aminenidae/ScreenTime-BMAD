# Plan: Remove ScreenTimeReportExtension (Build 12)

## Context

Brain Coinz has been blocked from App Store distribution since Submission 1 by a single iOS 26
runtime error:

```
MIInstallerErrorDomain Code=152 — AppexBundleContainsClassOrStoryboard
installd line 350: Appex bundle defines either an NSExtensionMainStoryboard or
NSExtensionPrincipalClass key, which is not allowed for the extension point
com.apple.deviceactivityui.report-extension
```

iOS 26 forbids both keys for `com.apple.deviceactivityui.report-extension`. App Store Connect
validator requires one of them. No technical workaround exists — both sides are Apple systems.

The solution is to remove `ScreenTimeReportExtension` from the app entirely. Investigation on
March 30, 2026 confirmed:

1. The extension is a **UI-only extension** — it cannot run in the background, on a timer, or
   independently of UI rendering.
2. The `HiddenUsageReportView` hack (invisible 1×1 SwiftUI embed) was never reliable — iOS does
   not guarantee `makeConfiguration()` is invoked for invisible views.
3. The code itself documented this: `ScreenTimeService.swift` line 1900:
   `// Report refresh timer doesn't work (DeviceActivityReport is UI-only) - removed`
4. The reconciliation functions `syncFromReportSnapshot()` and `requestUsageReportRefresh()`
   are **never called** from anywhere in the codebase — confirmed dead code.
5. The 60-second staleness gate in `syncFromReportSnapshot()` means any snapshot that did
   arrive would be discarded immediately.
6. All real usage tracking is performed by `ScreenTimeActivityExtension`
   (`com.apple.deviceactivity.monitor-extension`) via sliding window threshold events.

Removing the extension eliminates the installation blocker with **zero impact on functionality**.

See `docs/APP_REVIEW_RESPONSE_2.3.md` Sections F and H for full investigation details.

---

## Branch

`feature/remove-report-extension` (branched from `feature/sliding-window-thresholds` at
commit `850988e`)

---

## Files to Delete Entirely

| File | Reason |
|------|--------|
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/ScreenTimeReportExtension.swift` | Extension entry point — entire target removed |
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/TotalActivityReport.swift` | Extension report scene — entire target removed |
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/TotalActivityView.swift` | Extension UI — entire target removed |
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/Info.plist` | Extension Info.plist — entire target removed |
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/Info-Debug.plist` | Extension debug plist — entire target removed |
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/ScreenTimeReportExtension.entitlements` | Extension entitlements — entire target removed |
| `ScreenTimeRewardsProject/ScreenTimeReportExtension/MainInterface.storyboard` | Storyboard added in Build 11 investigation — no longer needed |
| `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Shared/HiddenUsageReportView.swift` | Entire file is dead — the hidden trigger view |

---

## Files to Modify

### 1. Xcode Project — `project.pbxproj`
**Recommended method: Xcode GUI** (Delete target via Project Navigator → target → Delete)

Xcode will automatically remove all associated entries. The manual IDs for reference:

| Section | ID | Description |
|---------|----|-------------|
| PBXNativeTarget | `43E1F0132F1A000100123450` | ScreenTimeReportExtension target |
| PBXBuildFile | `43E1F0202F1A000100123450` | ScreenTimeReportExtension.swift in Sources |
| PBXBuildFile | `43E1F0212F1A000100123450` | TotalActivityReport.swift in Sources |
| PBXBuildFile | `43E1F0222F1A000100123450` | TotalActivityView.swift in Sources |
| PBXBuildFile | `43E1F0232F1A000100123450` | DeviceActivity.framework in Frameworks |
| PBXBuildFile | `43E1F0242F1A000100123450` | FamilyControls.framework in Frameworks |
| PBXBuildFile | `43E1F0252F1A000100123450` | ManagedSettings.framework in Frameworks |
| PBXBuildFile | `43E1F0262F1A000100123450` | ScreenTimeReportExtension.appex in Embed App Extensions |
| PBXBuildFile | `43E1F0A02F1A000100123450` | MainInterface.storyboard in Resources |
| PBXFileReference | `43E1F0002F1A000100123450` | ScreenTimeReportExtension.appex |
| PBXFileReference | `43E1F0022F1A000100123450` | ScreenTimeReportExtension.swift |
| PBXFileReference | `43E1F0032F1A000100123450` | TotalActivityReport.swift |
| PBXFileReference | `43E1F0042F1A000100123450` | TotalActivityView.swift |
| PBXFileReference | `43E1F0052F1A000100123450` | Info.plist |
| PBXFileReference | `43E1F0062F1A000100123450` | .entitlements |
| PBXFileReference | `43E1F09F2F1A000100123450` | MainInterface.storyboard |
| PBXGroup | `43E1F0072F1A000100123450` | ScreenTimeReportExtension group |
| Build phases | `43E1F010/11/12` | Sources, Frameworks, Resources |
| Build config list | `43E1F0322F1A000100123450` | Debug + Release configs |
| File access exception | `43EC48452F0D8FF600E5D3AD` | Hardened runtime exception |

### 2. Xcscheme — `ScreenTimeRewards.xcscheme`
Remove the `BuildActionEntry` for `ScreenTimeReportExtension.appex`:
```xml
<!-- REMOVE THIS ENTIRE BLOCK -->
<BuildActionEntry ...>
    <BuildableReference
       BuildableIdentifier = "primary"
       BlueprintIdentifier = "43E1F0132F1A000100123450"
       BuildableName = "ScreenTimeReportExtension.appex"
       BlueprintName = "ScreenTimeReportExtension"
       ReferencedContainer = "container:ScreenTimeRewards.xcodeproj">
    </BuildableReference>
</BuildActionEntry>
```

### 3. `ScreenTimeRewards/Views/MainTabView.swift`
Remove two occurrences of `HiddenUsageReportView()`:
- Line 69 (child tab body)
- Line 109 (parent tab body)

### 4. `ScreenTimeRewards/Views/SettingsTabView.swift`
Remove `HiddenUsageReportView()` at line 163 (and its `.allowsHitTesting(false)` modifier).

### 5. `ScreenTimeRewards/Views/Tutorial/GuidedTutorialContainerView.swift`
Remove `HiddenUsageReportView()` at line 204.

### 6. `ScreenTimeRewards/Services/ScreenTimeService.swift`
Remove the following dead code:

| Symbol | Location | Action |
|--------|----------|--------|
| `reportRefreshRequestedNotification` | line 16 | Delete static property |
| `lastProcessedSnapshot` | line 214 | Delete private var |
| `enableSnapshotReconciliation` | line 218 | Delete private var |
| Comment block lines 1896–1901 | — | Delete comment |
| `requestUsageReportRefresh()` | lines 1906–1914 | Delete entire function |
| `syncFromReportSnapshot()` | lines 1917–2035 (approx) | Delete entire function |

### 7. `project.pbxproj` — Build Number
Bump `CURRENT_PROJECT_VERSION` from `11` → `12` across all 3 remaining App Store targets:
- `ScreenTimeRewards` (main app)
- `ScreenTimeActivityExtension`
- `ShieldConfigurationExtension`

---

## Implementation Order

1. **Xcode GUI**: Open project → Project Navigator → delete `ScreenTimeReportExtension` target
   (choose "Move to Trash" for source files). This handles `project.pbxproj` automatically.
2. **Xcscheme**: Remove `BuildActionEntry` for the extension (Claude Code edit).
3. **HiddenUsageReportView.swift**: Delete the file (Claude Code).
4. **MainTabView.swift**: Remove 2× `HiddenUsageReportView()` (Claude Code edit).
5. **SettingsTabView.swift**: Remove `HiddenUsageReportView()` (Claude Code edit).
6. **GuidedTutorialContainerView.swift**: Remove `HiddenUsageReportView()` (Claude Code edit).
7. **ScreenTimeService.swift**: Remove dead code block (Claude Code edit).
8. **project.pbxproj**: Bump build to 12 (Claude Code edit).
9. **Build in Xcode**: Confirm zero errors, zero warnings related to report extension.
10. **Archive**: Release build → Xcode Organizer.
11. **Validate**: Organizer → Validate App.
12. **Upload**: Distribute via Transporter or Organizer.

---

## Verification

### Build-time checks
- [ ] Xcode build succeeds with no reference to `ScreenTimeReportExtension`
- [ ] No `DeviceActivityReport` import warnings
- [ ] No `HiddenUsageReportView` references (grep confirms zero)
- [ ] `syncFromReportSnapshot` and `requestUsageReportRefresh` references: zero

### Archive checks
```bash
ARCHIVE=$(ls -td ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/*.xcarchive | head -1)
# Confirm only 2 extensions (not 3)
ls "${ARCHIVE}/Products/Applications/ScreenTimeRewards.app/PlugIns/"
# Expected: ScreenTimeActivityExtension.appex  ShieldConfigurationExtension.appex

# Confirm build number
plutil -p "${ARCHIVE}/Products/Applications/ScreenTimeRewards.app/Info.plist" | grep CFBundleVersion
# Expected: "CFBundleVersion" => "12"
```

### Validator check
Upload to Transporter (or validate in Organizer). Expected: **no AppexBundleContainsClassOrStoryboard
error**. The extension point `com.apple.deviceactivityui.report-extension` will no longer be present
in the binary at all.

### Device check (TestFlight)
Install Build 12 on iPhone 15 (iOS 26.3.1). Expected: **install completes**. Confirm via
Console.app (filter: installd) — no `MIInstallerErrorDomain Code=152` log entries.

### Functional check
- [ ] Child device: usage tracking increments correctly during a test session
- [ ] Reward app unshields when learning goal is met
- [ ] Reward app reshields when earned time expires
- [ ] No regression in threshold events or sliding window behaviour

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Xcode GUI leaves orphan pbxproj entries | Low | Verify with `git diff project.pbxproj` post-deletion |
| Missed `HiddenUsageReportView` reference causes compile error | Low | Grep before archiving |
| `syncFromReportSnapshot` had a hidden caller not found by grep | None — confirmed by grep | N/A |
| Usage tracking regression | None — monitor extension unaffected | Functional test confirms |
| App Store validator introduces new rule for missing extension | Unlikely | If it occurs, document and escalate |

---

## Expected Outcome

Build 12 installs on iOS 26 devices via TestFlight and App Store without modification.
The `AppexBundleContainsClassOrStoryboard` error is eliminated because the extension that
triggered it no longer exists in the bundle.

The app retains 100% of its usage tracking, reward, and shield functionality.
