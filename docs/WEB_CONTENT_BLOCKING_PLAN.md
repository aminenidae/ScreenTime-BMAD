# Website & Content Blocking Implementation

> **Status: COMPLETE** - Implemented and tested January 2026

## Summary

Web content restrictions using **ManagedSettings** framework with three levels:
1. **Block specific websites** (picker-based selection)
2. **Block browsers entirely** (Safari + third-party)
3. **Enable adult content filter** (Apple's built-in filter - always-on)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    PARENT DEVICE                             │
├─────────────────────────────────────────────────────────────┤
│  SettingsTabView                                             │
│    └── "Web Restrictions" section                            │
│         ├── Block specific websites (picker)                 │
│         ├── Block browsers toggle (Safari + others)          │
│         └── Adult Content Blocked (status indicator)         │
│                                                               │
│  On change → CloudKitSyncService.sendWebRestrictionCommand() │
│           → WebRestrictionPayload sent to ParentCommands zone│
└─────────────────────────────────────────────────────────────┘
                              │
                              │ CloudKit Sync
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    CHILD DEVICE                              │
├─────────────────────────────────────────────────────────────┤
│  fetchPendingCommandsFromSharedZone()                        │
│    └── Receives WebRestrictionPayload                        │
│         ├── Apply webDomain shields                          │
│         └── Apply browser app blocks                         │
│                                                               │
│  ManagedSettingsStore applies:                               │
│    - shield.webDomains = [blocked domain tokens]             │
│    - application.blockedApplications = [Safari, Chrome...]   │
│    - webContent.blockedByFilter = .auto(except: [])         │
│      ↑ Applied automatically on authorization (always-on)    │
└─────────────────────────────────────────────────────────────┘
```

---

## Feature 1: Block Specific Websites

### How It Works
- Parent selects websites from FamilyActivityPicker (based on child's browsing history)
- Selected domains are shielded immediately
- Custom shield UI shows "Website Blocked" message

### API Used
```swift
managedSettingsStore.shield.webDomains = Set<WebDomainToken>
```

### Limitations
- Only domains visible in picker (from browsing history)
- No manual URL entry
- Max ~30-50 domains before performance issues

---

## Feature 2: Block Browsers Entirely

### How It Works
- Toggle to block Safari and/or third-party browsers
- Uses `Application(bundleIdentifier:)` for known browsers
- Shield appears when child tries to open browser

### API Used
```swift
let safari = Application(bundleIdentifier: "com.apple.mobilesafari")
let chrome = Application(bundleIdentifier: "com.google.chrome.ios")
let firefox = Application(bundleIdentifier: "org.mozilla.ios.Firefox")
let edge = Application(bundleIdentifier: "com.microsoft.msedge")

managedSettingsStore.application.blockedApplications = [safari, chrome, ...]
```

### Supported Browsers
| Browser | Bundle ID |
|---------|-----------|
| Safari | `com.apple.mobilesafari` |
| Chrome | `com.google.chrome.ios` |
| Firefox | `org.mozilla.ios.Firefox` |
| Edge | `com.microsoft.msedge` |
| DuckDuckGo | `com.duckduckgo.mobile.ios` |
| Brave | `com.brave.ios.browser` |
| Opera | `com.opera.gx` |

---

## Feature 3: Adult Content Filter (Always-On)

### How Apple's Filter Works
Apple's built-in adult content filter:
- **Scans web page content** as it loads in Safari/WebKit
- **Detects adult terms** including profanity and sexually explicit language
- **Automatically blocks** pages that match adult content patterns
- **Algorithm is opaque** - Apple doesn't publish exact rules, may change between iOS versions
- **Works best in Safari** - third-party browsers with custom rendering may bypass

### Implementation
- **Enabled by default** when app is installed - no toggle
- System automatically blocks adult sites in Safari/WebKit
- UI shows status indicator: "Adult Content Blocked" with security/shield icon

### API Used
```swift
// Applied automatically on app install/authorization
managedSettingsStore.webContent.blockedByFilter = .auto(except: [])
```

### When to Apply
- On successful FamilyControls authorization (child mode setup)
- On app launch (re-apply to ensure persistence)
- After CloudKit sync (child receives parent pairing)

### Side Effect
- **Disables private/incognito browsing in Safari** (no workaround)
- Only effective in Safari and WebKit-based browsers
- This is a FEATURE for parental control - incognito would bypass filters

---

## UI Design

### Location: New Section in SettingsTabView

```
SETTINGS
─────────────────────────────
ACCOUNT
  Exit Parent Mode

SUBSCRIPTION
  Manage Subscription

WEB RESTRICTIONS  ← NEW SECTION
  ┌─────────────────────────┐
  │ 🌐 Blocked Websites     │  → Opens WebsiteBlockingView
  │    3 sites blocked      │
  ├─────────────────────────┤
  │ 🚫 Block All Browsers   │  [Toggle]
  │    Safari, Chrome, etc. │
  ├─────────────────────────┤
  │ 🛡️ Adult Content Blocked │  ← STATUS INDICATOR (no toggle)
  │    ✓ Always protected   │     (shield.fill icon, green checkmark)
  └─────────────────────────┘

DEVICES
  Pairing Status
  Pairing Configuration
```

### Adult Content Status Row (read-only)
```swift
HStack {
    Image(systemName: "shield.fill")
        .foregroundColor(.green)
    VStack(alignment: .leading) {
        Text("Adult Content Blocked")
            .font(.headline)
        Text("Always protected")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    Spacer()
    Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
}
```

### WebsiteBlockingView (new screen)

```
BLOCKED WEBSITES
─────────────────────────────
  tiktok.com              [x]
  instagram.com           [x]
  youtube.com             [x]

  + Add Website to Block
    (opens FamilyActivityPicker)
```

---

## CloudKit Sync

### New Payload Model

**File:** `Models/WebRestrictionPayload.swift` (new)

```swift
struct WebRestrictionPayload: Codable {
    let blockedWebDomainTokens: [Data]  // Serialized WebDomainToken
    let blockedBrowserBundleIDs: [String]  // e.g., ["com.apple.mobilesafari"]
    // NOTE: Adult content filter NOT in payload - it's always-on locally
    let updatedAt: Date
}
```

### Adult Content Filter (Not Synced)
The adult content filter is applied locally on the child device during:
1. FamilyControls authorization (child mode setup)
2. App launch (ensure persistence)

It does NOT need CloudKit sync since it's always-on.

### Integration with Existing Sync

Extend `ConfigurationCommand` to support new type:
```swift
enum CommandType: String {
    case updateFullConfig = "update_full_config"
    case updateWebRestrictions = "update_web_restrictions"  // NEW
}
```

### Sync Flow

1. **Parent device:**
   - User changes web restrictions in SettingsTabView
   - `CloudKitSyncService.sendWebRestrictionCommand(payload)` called
   - Command saved to ParentCommands-{deviceID} zone

2. **Child device:**
   - Polls `fetchPendingCommandsFromSharedZone()`
   - Receives `update_web_restrictions` command
   - Applies restrictions via `ScreenTimeService.applyWebRestrictions(payload)`
   - Marks command executed

---

## Implementation Details

### Adult Content Filter on Authorization (Always-On)

**File:** `ScreenTimeService.swift`

Added to authorization flow:
```swift
func requestAuthorization() async throws {
    try await AuthorizationCenter.shared.requestAuthorization(for: .child)

    // Apply adult content filter immediately after authorization
    enableAdultContentFilter()
}

func enableAdultContentFilter() {
    managedSettingsStore.webContent.blockedByFilter = .auto(except: [])
}

func onAppLaunch() {
    // Re-apply on every launch to ensure persistence
    if isChildMode {
        enableAdultContentFilter()
    }
}
```

### Web Restriction Storage & Service Methods

**File:** `ScreenTimeService.swift`

```swift
// MARK: - Web Restrictions

private var blockedWebDomains: Set<WebDomainToken> = []
private var blockedBrowserBundleIDs: Set<String> = []

func applyWebRestrictions(_ payload: WebRestrictionPayload) {
    // 1. Block specific websites
    blockedWebDomains = deserializeWebDomainTokens(payload.blockedWebDomainTokens)
    managedSettingsStore.shield.webDomains = blockedWebDomains.isEmpty ? nil : blockedWebDomains

    // 2. Block browsers
    let browsers = payload.blockedBrowserBundleIDs.compactMap {
        Application(bundleIdentifier: $0)
    }
    managedSettingsStore.application.blockedApplications = Set(browsers)

    // 3. Persist locally
    persistWebRestrictions(payload)

    // NOTE: Adult filter already enabled (always-on) - no action needed
}
```

### WebRestrictionPayload Model

**File:** `Models/WebRestrictionPayload.swift`

### UI Views

**Files:**
- `Views/SettingsTabView.swift` (Web Restrictions section inline)
- `Views/ParentMode/WebsiteBlockingView.swift` (picker screen)

### CloudKit Sync

**File:** `CloudKitSyncService.swift`

Added `sendWebRestrictionCommand()` method.

**File:** `ChildConfigCommandProcessor.swift`

Added handling for `update_web_restrictions` command type.

### Shield Extension

**File:** `ShieldConfigurationExtension.swift`

Added "Website Blocked" theme with red background.

---

## Files Created/Modified

| File | Action | Status |
|------|--------|--------|
| `Models/WebRestrictionPayload.swift` | Created | ✅ |
| `Views/ParentMode/WebsiteBlockingView.swift` | Created | ✅ |
| `Services/ScreenTimeService.swift` | Modified | ✅ |
| `Services/CloudKitSyncService.swift` | Modified | ✅ |
| `Services/ChildConfigCommandProcessor.swift` | Modified | ✅ |
| `Views/SettingsTabView.swift` | Modified | ✅ |
| `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` | Modified | ✅ |

*Note: Web Restrictions section was implemented inline in SettingsTabView rather than as a separate component.*

---

## Limitations & Considerations

### Technical Limitations
1. **Picker-only selection:** Cannot type custom URLs
2. **30-50 domain limit:** Performance degrades with more
3. **WebKit-only:** Privacy browsers may bypass
4. **Incognito disabled:** Adult filter disables private browsing (a feature, not a bug)
5. **Token instability:** iOS may randomly change tokens

### UX Considerations
1. Incognito being disabled is actually desirable for parental control
2. Explain picker limitation (only browsed sites appear)
3. Consider providing preset blocklists (social media, gaming)

---

## Testing Checklist

### Website Blocking
- [x] Block website via picker → verify shield appears
- [x] Unblock website → verify access restored

### Browser Blocking
- [x] Block Safari → verify app won't open
- [x] Block Chrome → verify app won't open

### Adult Content Filter (Always-On)
- [x] Fresh install + authorization → adult filter active immediately
- [x] Adult sites blocked in Safari (test known adult site)
- [x] Private/incognito mode disabled in Safari
- [x] App restart → adult filter persists

### CloudKit Sync
- [x] Parent blocks website → child receives restriction
- [x] Parent blocks browser → child can't open it
- [x] Persistence: Kill app → restrictions persist

> **All tests passed** - January 2026

---

## Sources

- [WebContentSettings | Apple Developer](https://developer.apple.com/documentation/managedsettings/webcontentsettings)
- [WebContentSettings.FilterPolicy.auto | Apple Developer](https://developer.apple.com/documentation/managedsettings/webcontentsettings/filterpolicy/auto(_:except:))
- [Screen Time API Guide](https://medium.com/@juliusbrussee/a-developers-guide-to-apple-s-screen-time-apis-familycontrols-managedsettings-deviceactivity-e660147367d7)
- [Block Safari by Bundle ID | Apple Developer Forums](https://developer.apple.com/forums/thread/726226)
