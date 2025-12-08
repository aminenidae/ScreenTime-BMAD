# Personalized Shield Messages - Debug Log

## Date: 2025-11-29

## Problem Statement

All 3 reward apps display the **same shield message** even though each app has different time window configurations. The personalized shield feature was implemented but name matching between the main app and the Shield Extension is failing.

## Root Cause (Confirmed)

**App names are always "Unknown App 1", "Unknown App 2", etc.** due to iOS privacy restrictions. The numbering is NOT stable across processes - the same app can have different "Unknown App X" identifiers in the main app vs the extension. Name-based lookup will never work reliably.

## Solution Implemented

Switched from **name-based lookup** to **token-hash-based lookup**. The ApplicationToken hash (SHA256) is stable and unique per app across all processes.

## Implementation Status

### Completed Features
- `BlockingReason` enum with 3 reasons: `outsideTimeWindow`, `dailyLimitReached`, `challengeNotMet`
- `AppBlockingInfo` struct with all necessary data for personalized messages
- `ShieldDataService` with sync methods for storing blocking info by token hash
- `AppUsageViewModel.syncBlockingInfoForAllRewardApps()` calculates blocking reasons
- `ShieldConfigurationExtension` updated with token hash lookup (matching main app's hashing)
- Fallback chain: token hash → first available → legacy

### Fix Applied (2025-11-29)

Added to `ShieldConfigurationExtension.swift`:
1. `import CryptoKit`
2. `extractTokenData()` - extracts internal data from ApplicationToken via reflection
3. `hashToken()` - computes SHA256 hash in format `token.sha256.<hex>`
4. `getBlockingInfoByTokenHash()` - looks up by token hash
5. Updated `generateConfiguration()` to try token hash first

### Debug Logging (Can Be Removed)

#### ShieldDataService.swift (Main App)
Location: `syncAllBlockingInfo()` method

```swift
print("[ShieldDataService] 📝 === SYNCING BLOCKING INFO ===")
for app in apps {
    infoByToken[app.tokenHash] = app
    infoByName[app.appNameLower] = app
    print("[ShieldDataService] 📝 Storing: '\(app.appName)' -> key: '\(app.appNameLower)' | reason: \(app.reason.rawValue)")
}
print("[ShieldDataService] 📝 All keys: [\(infoByName.keys.joined(separator: ", "))]")
```

#### ShieldConfigurationExtension.swift (Extension)
Location: `generateConfiguration()` method

```swift
let appName = getAppName(application)
print("[ShieldExtension] 🔍 === GENERATING CONFIG ===")
print("[ShieldExtension] 🔍 App name from iOS: '\(appName ?? "nil")'")
print("[ShieldExtension] 🔍 Lookup key would be: '\(appName?.lowercased() ?? "nil")'")
```

Location: `getBlockingInfoByName()` method

```swift
print("[ShieldExtension] 📚 Available keys: [\(allInfo.keys.joined(separator: ", "))]")
print("[ShieldExtension] 🔍 Looking up: '\(lookupKey)'")
// On match:
print("[ShieldExtension] ✅ Found match for '\(lookupKey)' -> reason: \(info.reason.rawValue)")
// On no match:
print("[ShieldExtension] ❌ No exact match for '\(lookupKey)'")
```

Location: `findBlockingInfoByPartialMatch()` method

```swift
print("[ShieldExtension] 🔍 Partial match: '\(searchName)' <-> '\(storedName)'")
// Or:
print("[ShieldExtension] ❌ No partial match found for '\(searchName)'")
```

## How to View Logs

1. **Run the app** on device through Xcode
2. **Open a shielded reward app** to trigger the shield
3. **Check Console.app** on Mac:
   - Open Console.app
   - Select your iPhone in the sidebar
   - Filter for `[ShieldDataService]` or `[ShieldExtension]`

## Expected Log Output

### Main App (on sync):
```
[ShieldDataService] 📝 === SYNCING BLOCKING INFO ===
[ShieldDataService] 📝 Storing: 'YouTube' -> key: 'youtube' | reason: outsideTimeWindow
[ShieldDataService] 📝 Storing: 'TikTok' -> key: 'tiktok' | reason: outsideTimeWindow
[ShieldDataService] 📝 Storing: 'Instagram' -> key: 'instagram' | reason: dailyLimitReached
[ShieldDataService] 📝 All keys: [youtube, tiktok, instagram]
```

### Extension (on shield display):
```
[ShieldExtension] 🔍 === GENERATING CONFIG ===
[ShieldExtension] 🔍 App name from iOS: 'YouTube'
[ShieldExtension] 🔍 Lookup key would be: 'youtube'
[ShieldExtension] 📚 Available keys: [youtube, tiktok, instagram]
[ShieldExtension] 🔍 Looking up: 'youtube'
[ShieldExtension] ✅ Found match for 'youtube' -> reason: outsideTimeWindow
[ShieldExtension] ✅ Using EXACT match config for 'YouTube'
```

### If Mismatch (what we're debugging):
```
[ShieldExtension] 🔍 === GENERATING CONFIG ===
[ShieldExtension] 🔍 App name from iOS: 'YouTube: Watch, Listen, Stream'
[ShieldExtension] 🔍 Lookup key would be: 'youtube: watch, listen, stream'
[ShieldExtension] 📚 Available keys: [youtube, tiktok, instagram]
[ShieldExtension] 🔍 Looking up: 'youtube: watch, listen, stream'
[ShieldExtension] ❌ No exact match for 'youtube: watch, listen, stream'
[ShieldExtension] 🔍 Partial match: 'youtube: watch, listen, stream' <-> 'youtube'
[ShieldExtension] ✅ Using PARTIAL match config for 'YouTube: Watch, Listen, Stream'
```

## Next Steps

1. **Test the fix** - Run the app and open each of the 3 shielded reward apps
2. **Verify** each app shows its **specific** time window message (not all the same)
3. **If working**, remove the debug logging from:
   - `ShieldDataService.swift` - remove print statements in `syncAllBlockingInfo()`
   - `ShieldConfigurationExtension.swift` - remove unused name-based lookup methods

## Files Modified

| File | Changes |
|------|---------|
| `ScreenTimeRewards/Services/ShieldDataService.swift` | Added debug logging in `syncAllBlockingInfo()` |
| `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` | Added CryptoKit import, token hashing methods, token-hash lookup, updated generateConfiguration() |

## Related Documentation

- `docs/PERSONALIZED_SHIELD_MESSAGES.md` - Feature specification

## Build Status

**BUILD SUCCEEDED** - 2025-11-29
