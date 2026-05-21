# Feature: Sliding Window Thresholds — Track Beyond 60 Minutes Per App

## Context

Each app currently gets exactly 60 thresholds (min.1-60), meaning **usage tracking stops completely at 60 minutes per day**. iOS has an undocumented ~500 total threshold limit, so we can't just increase to 240/app (already tried in `feature/extend-threshold-240min`, reverted in commit 419cef7 because 3+ apps would exceed the limit).

**Key insight:** Smart filtering already reads `ext_usage` and skips thresholds ≤ current usage, effectively only registering thresholds *above* current usage. But it still caps at min.60. The fix is simple: instead of generating thresholds 1-60 and filtering down, generate thresholds from `(currentMinutes+1)` to `(currentMinutes+60)` directly. This creates a **sliding window** that advances with usage.

**Result:** Always exactly 60 thresholds per app (stays under iOS ~500 limit), but the window slides upward with usage — enabling unlimited daily tracking.

## How It Works

```
App with 0 min usage:   thresholds 1-60   → tracks up to 60 min
App with 45 min usage:  thresholds 46-105  → tracks up to 105 min
App with 100 min usage: thresholds 101-160 → tracks up to 160 min
```

Each monitoring restart shifts the window based on `ext_usage_{appID}_today`. Smart filtering is now built into the generation itself rather than being a post-filter.

**Bonus:** Nearly eliminates catch-up floods on restart. Since only thresholds above current usage are registered, iOS has nothing below cumulative usage to catch up to.

## Reported Issue: "Apps with existing usage don't record"

Fresh apps (0 min) record correctly from threshold 1 onward. But once a second session starts (after a monitoring restart), apps with prior usage stop recording entirely.

**Root cause analysis:** The sliding window directly addresses this. Currently, smart filtering skips min.1-N but only registers up to min.60, leaving few thresholds for real events after catch-ups consume them. The sliding window always provides a full 60 thresholds above current usage.

**Additional fix found:** `tracked_app_ids` (used by RESTART_THRESHOLD_RESET to reset `lastThreshold`) is only populated by the extension on first recording. If an app was never recorded (or data was cleared), it won't be in `tracked_app_ids`, so its `lastThreshold` is never reset after restart. Pre-populating `tracked_app_ids` in `scheduleActivity()` ensures all monitored apps get their `lastThreshold` reset.

## Changes

### File: `ScreenTimeService.swift`

#### 1. Modify `scheduleActivity()` (lines 2366-2431)

**Replace** the existing smart filtering block with sliding window rebuild:

- Read `appCurrentMinutes` per app from `ext_usage` (already done, keep this code)
- After reading, **rebuild `monitoredEvents`** with sliding window:
  - Collect unique apps from existing `monitoredEvents` (one per logicalID)
  - For each app: clear old events, generate from `(currentMinutes+1)` to `(currentMinutes+60)`
  - Use existing `stableHash(logicalID)` for event naming
- Call `saveEventMappings()` to save updated mappings (it already cleans up old ones via `dictionaryRepresentation()`)
- Register ALL events with iOS (no post-filter needed — all are above current usage)
- Keep the `skippedCount` concept for logging: `skippedCount = sum of currentMinutes across apps` (shows how many were "skipped" by sliding the window)

**Concrete code structure:**
```swift
// After reading appCurrentMinutes (existing code)...

// SLIDING WINDOW: Rebuild monitoredEvents with per-app threshold ranges
// Instead of static 1-60, generate (currentMinutes+1) to (currentMinutes+60)
var appTemplates: [String: (app: MonitoredApplication, category: AppUsage.AppCategory)] = [:]
for event in monitoredEvents.values {
    guard let app = event.applications.first else { continue }
    if appTemplates[app.logicalID] == nil {
        appTemplates[app.logicalID] = (app: app, category: event.category)
    }
}

var newMonitoredEvents: [DeviceActivityEvent.Name: MonitoredEvent] = [:]
var totalSkipped = 0
for (logicalID, template) in appTemplates {
    let currentMinutes = appCurrentMinutes[logicalID] ?? 0
    totalSkipped += currentMinutes
    let startMinute = currentMinutes + 1
    let endMinute = currentMinutes + 60
    let stableAppID = stableHash(logicalID)

    for minuteNumber in startMinute...endMinute {
        let eventName = DeviceActivityEvent.Name("usage.app.\(stableAppID).min.\(minuteNumber)")
        newMonitoredEvents[eventName] = MonitoredEvent(
            name: eventName,
            category: template.category,
            threshold: DateComponents(minute: minuteNumber),
            applications: [template.app]
        )
    }
}
monitoredEvents = newMonitoredEvents
saveEventMappings()

// Register all events (all are above current usage — no filtering needed)
let events = monitoredEvents.reduce(into: [DeviceActivityEvent.Name: DeviceActivityEvent]()) { result, entry in
    result[entry.key] = entry.value.deviceActivityEvent()
}
```

#### 2. Update debug logging (lines 2400-2407, 2420-2428)

Update log messages to show sliding window ranges:
```swift
// Per-app: "appID: 45 min recorded, registering min 46-105"
// Summary: "Sliding window: X events registered (Y skipped below current usage)"
```

#### 3. Update threshold generation comments (lines 755-782)

Update the comments at the initial `monitoredEvents` creation to note that `scheduleActivity()` will rebuild with sliding window. No code change needed — the initial 1-60 creation serves as a template.

#### 4. Pre-populate `tracked_app_ids` in `scheduleActivity()`

After rebuilding `monitoredEvents`, write all monitored app logicalIDs to `tracked_app_ids`. This ensures RESTART_THRESHOLD_RESET in the extension covers all apps — even those never recorded yet.

```swift
// Pre-populate tracked_app_ids so extension's RESTART_THRESHOLD_RESET
// resets lastThreshold for ALL monitored apps (not just previously recorded ones)
let allLogicalIDs = Array(appTemplates.keys)
sharedDefaults.set(allLogicalIDs, forKey: "tracked_app_ids")
```

#### 5. Update event count warning (lines 1743-1745)

The `> 500` warning message should still work since we always have 60/app.

### File: `DeviceActivityMonitorExtension.swift`

**No changes needed.** The extension:
- Parses minute values from event names via `extractMinuteFromEventName()` — works for any integer
- Computes `thresholdSeconds = minute * 60` — works for values > 60
- Delta calculation `max(60, thresholdSeconds - lastThreshold)` — works correctly
- Filter chain has no hardcoded 60-minute cap

## Expected Behavior

```
T0:     Restart → sliding window registers min.(current+1) to (current+60)
T0-60:  Absorb window — near-zero catch-ups (only if ext_usage slightly stale)
T60+:   First REAL event fires → RECORDED
T120+:  Next event → RECORDED
...continues every 60s of app usage, indefinitely
```

**After 60 min of app usage:** Next restart shifts window to min.61-120.
**After 120 min:** Window shifts to min.121-180. No cap.

## Verification

1. Build and deploy to device
2. Use a learning app — verify normal recording (min.1, 2, 3...)
3. After ~55 min of usage, trigger a monitoring restart (foreground app)
4. Check lifecycle log: should show "registering min 56-115" (not 1-60)
5. Continue using the app — verify events fire at min.56, 57, 58... past 60
6. Check ext_usage shows >3600s (more than 60 min)
7. Verify total threshold count stays under 500 in diagnostics
