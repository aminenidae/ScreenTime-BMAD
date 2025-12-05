# Hourly Usage Chart Fix

## Problem Statement

The hourly usage chart on the dashboard only shows usage for the last hour (or the hour when the main app synced), instead of showing accurate per-hour breakdown for the entire day.

### Root Cause

1. **Extension records hour correctly**: Each threshold event in `DeviceActivityMonitorExtension` records the hour it occurred (`ext_usage_\(appID)_hour`)

2. **Main app ignores this**: When `ScreenTimeService` syncs, it calculates a delta and adds it to the **current hour** at sync time, not the hour when the extension recorded the event

3. **Result**: If extension records usage at 9am, 10am, 11am but main app syncs at 2pm, all usage appears in hour 14 (2pm)

## Solution Overview

Have the extension maintain per-hour usage counters in UserDefaults, then have the main app read this hourly breakdown directly.

---

## Implementation Plan

### Step 1: Extension - Add Per-Hour Tracking

**File:** `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`

In `setUsageToThreshold()` function, add hourly bucket tracking:

```swift
// After recording usage, also bucket into the current hour
let hourlyKey = "ext_usage_\(appID)_hourly_\(hour)"
let currentHourlySeconds = defaults.integer(forKey: hourlyKey)
defaults.set(currentHourlySeconds + 60, forKey: hourlyKey)

// Also store the date for this hourly data (for day rollover detection)
defaults.set(dateString, forKey: "ext_usage_\(appID)_hourly_date")
```

**Day rollover handling**: When a new day starts, reset all 24 hourly keys:

```swift
// In day rollover section, add:
for h in 0..<24 {
    defaults.set(0, forKey: "ext_usage_\(appID)_hourly_\(h)")
}
defaults.set(dateString, forKey: "ext_usage_\(appID)_hourly_date")
```

### Step 2: Main App - Read Extension's Hourly Data

**File:** `ScreenTimeRewards/Views/ParentMode/DailyUsageChartCard.swift`

Replace the `getHourlyData()` function to read directly from extension's per-hour keys:

```swift
private func getHourlyData(for category: AppUsage.AppCategory) -> [(date: Date, minutes: Int)] {
    guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
        return []
    }

    let calendar = Calendar.current
    let now = Date()
    let today = calendar.startOfDay(for: now)
    let currentHour = calendar.component(.hour, from: now)

    // Get all app logicalIDs for this category
    let logicalIDs: [String] = {
        if category == .learning {
            return viewModel.learningSnapshots.map { $0.logicalID }
        } else {
            return viewModel.rewardSnapshots.map { $0.logicalID }
        }
    }()

    var hourlyData: [Date: Int] = [:]

    // Read hourly data directly from extension's protected keys
    for logicalID in logicalIDs {
        // Check if hourly data is from today
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: now)
        let storedDate = defaults.string(forKey: "ext_usage_\(logicalID)_hourly_date")

        guard storedDate == todayString else { continue }

        // Read each hour's usage
        for hour in 0...currentHour {
            let seconds = defaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
            if seconds > 0 {
                if let hourDate = calendar.date(byAdding: .hour, value: hour, to: today) {
                    hourlyData[hourDate, default: 0] += seconds / 60
                }
            }
        }
    }

    return hourlyData
        .sorted { $0.key < $1.key }
        .map { (date: $0.key, minutes: $0.value) }
}
```

### Step 3: Sync Hourly Data to Persistence (Optional)

**File:** `ScreenTimeRewards/Services/ScreenTimeService.swift`

When syncing from extension, also copy the hourly breakdown to `persistedApp.todayHourlySeconds`:

```swift
// In syncUsageFromExtension(), after reading ext_ keys:

// Read hourly breakdown from extension
var hourlySeconds = Array(repeating: 0, count: 24)
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd"
let todayString = dateFormatter.string(from: Date())
let storedDate = defaults.string(forKey: "ext_usage_\(logicalID)_hourly_date") ?? ""

if storedDate == todayString {
    for hour in 0..<24 {
        hourlySeconds[hour] = defaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
    }
}
persistedApp.todayHourlySeconds = hourlySeconds
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Add per-hour tracking in `setUsageToThreshold()` |
| `ScreenTimeRewards/Views/ParentMode/DailyUsageChartCard.swift` | Update `getHourlyData()` to read extension's hourly keys |
| `ScreenTimeRewards/Services/ScreenTimeService.swift` | (Optional) Sync hourly data to persistence |

---

## Data Flow (After Fix)

```
Extension fires at 9:15 AM:
  → ext_usage_app123_hourly_9 += 60
  → ext_usage_app123_hourly_date = "2024-12-04"

Extension fires at 10:30 AM:
  → ext_usage_app123_hourly_10 += 60

Extension fires at 10:31 AM:
  → ext_usage_app123_hourly_10 += 60  (now = 120)

User opens app at 2:00 PM:
  → Chart reads ext_usage_app123_hourly_0 through hourly_14
  → Hour 9: 60s (1 min)
  → Hour 10: 120s (2 min)
  → Hour 14: 0s (just opened)
```

---

## Testing Checklist

- [ ] Extension records usage to correct hourly bucket
- [ ] Day rollover resets all hourly buckets
- [ ] Chart shows bars for past hours with usage
- [ ] Chart shows 0 for hours with no usage
- [ ] Multiple apps accumulate correctly per hour
- [ ] Learning vs Reward apps separated correctly
- [ ] Build succeeds for both app and extension

---

## Rollback Plan

If issues arise:
1. Revert extension changes
2. `getHourlyData()` will fall back to reading `todayHourlySeconds` from persistence
3. Behavior returns to current (broken but stable) state
