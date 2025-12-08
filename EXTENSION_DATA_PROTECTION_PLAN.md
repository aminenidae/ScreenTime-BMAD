/cle# Extension Data Protection Plan

## Problem

Usage time sometimes gets inflated somewhere in the flow from extension to UI. We need to protect the extension's recorded data as the **source of truth** so we can:
1. Always verify what iOS actually reported
2. Detect and correct any downstream corruption
3. Debug where inflation occurs

## Solution: Protected Write-Only Keys with Timestamps

The extension writes to dedicated `ext_` prefixed keys that the main app **never writes to**.

---

## Data Structure

### Extension Writes (Protected - Read-Only for Main App)

| Key | Type | Description |
|-----|------|-------------|
| `ext_usage_{appID}_today` | Int | Seconds used today (from iOS thresholds) |
| `ext_usage_{appID}_total` | Int | Total seconds all-time |
| `ext_usage_{appID}_date` | String | Date string (YYYY-MM-DD) for "today" |
| `ext_usage_{appID}_hour` | Int | Hour (0-23) of last threshold |
| `ext_usage_{appID}_timestamp` | Double | Unix timestamp of last write |

### Main App Writes (Processed Data)

| Key | Type | Description |
|-----|------|-------------|
| `app_usage_{appID}_today` | Int | App's processed/displayed seconds |
| `app_usage_{appID}_*` | * | Any other app-side tracking |

---

## Implementation

### 1. DeviceActivityMonitorExtension.swift

When `eventDidReachThreshold()` fires:

```swift
let now = Date()
let calendar = Calendar.current
let dateString = ISO8601DateFormatter().string(from: now).prefix(10) // "2025-11-28"
let hour = calendar.component(.hour, from: now)

let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")

// Protected writes (ext_ prefix)
defaults?.set(thresholdSeconds, forKey: "ext_usage_\(appID)_today")
defaults?.set(totalSeconds, forKey: "ext_usage_\(appID)_total")
defaults?.set(String(dateString), forKey: "ext_usage_\(appID)_date")
defaults?.set(hour, forKey: "ext_usage_\(appID)_hour")
defaults?.set(now.timeIntervalSince1970, forKey: "ext_usage_\(appID)_timestamp")
```

### 2. ScreenTimeService.swift

When reading extension data:

```swift
func readExtensionUsageData() {
    // Read from protected ext_ keys (NEVER write to these)
    let extToday = defaults.integer(forKey: "ext_usage_\(appID)_today")
    let extDate = defaults.string(forKey: "ext_usage_\(appID)_date")
    let extHour = defaults.integer(forKey: "ext_usage_\(appID)_hour")
    let extTimestamp = defaults.double(forKey: "ext_usage_\(appID)_timestamp")

    // Process and write to app_ keys
    defaults.set(processedValue, forKey: "app_usage_\(appID)_today")
}
```

### 3. Validation/Debugging

Add a function to compare extension vs app data:

```swift
func validateUsageData(for appID: String) -> (ext: Int, app: Int, diff: Int) {
    let ext = defaults.integer(forKey: "ext_usage_\(appID)_today")
    let app = defaults.integer(forKey: "app_usage_\(appID)_today")
    return (ext, app, app - ext)
}
```

---

## Rules

1. **Extension**: Only writes to `ext_` keys
2. **Main App**:
   - Reads from `ext_` keys (source of truth)
   - Writes to `app_` keys (processed data)
   - **NEVER** writes to `ext_` keys
3. **UI**: Displays from `app_` keys (or directly from ext_ if we trust it more)

---

## Migration

Existing keys to migrate:
- `usage_{appID}_today` → `ext_usage_{appID}_today`
- `usage_{appID}_total` → `ext_usage_{appID}_total`

New keys to add:
- `ext_usage_{appID}_date`
- `ext_usage_{appID}_hour`
- `ext_usage_{appID}_timestamp`

---

## Benefits

1. **Source of Truth**: Extension data is immutable, always available for reference
2. **Day Boundary**: `ext_..._date` clearly marks which day the data belongs to
3. **Hourly Bucketing**: `ext_..._hour` enables accurate hourly breakdown
4. **Freshness Check**: `ext_..._timestamp` shows data age
5. **Debugging**: Compare `ext_` vs `app_` to find where inflation occurs

---

## Files to Modify

| File | Changes |
|------|---------|
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Write to `ext_` keys with timestamps |
| `ScreenTimeRewards/Services/ScreenTimeService.swift` | Read from `ext_` keys, write to `app_` keys |
| `ScreenTimeRewards/Shared/UsagePersistence.swift` | Update key references if needed |

---

## Future: Self-Correction

Once this is in place, we can add automatic correction:

```swift
if appUsage > extUsage {
    // App has inflated data, correct it
    appUsage = extUsage
    log("Corrected inflation: was \(appUsage), now \(extUsage)")
}
```
