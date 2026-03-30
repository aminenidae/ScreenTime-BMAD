# Fix: Usage Under-Counting — Two Bugs

## Context

Users report that daily usage is not fully recorded — "some apps didn't record usage since 7 AM, others recorded less than what was used." Logs from TWO devices confirm TWO distinct bugs causing under-counting:

**Bug A**: After iOS cycles monitoring (`INTERVAL_END` → `INTERVAL_START`), ALL subsequent events get `SKIP_REGRESSION`'d because `lastThreshold` retains the pre-restart value while iOS resets its cumulative counter.

**Bug B**: iOS batches threshold events hourly (all arrive within <1 second). The 55s COOLDOWN filter blocks all but the first per batch, adding only +60s even when 15+ minutes accumulated. One app showed **83% under-counting** (420s recorded vs 2460s actual over 7 hours).

---

## Bug A: SKIP_REGRESSION After iOS-Initiated Restart

### Evidence (Device 2 log)

```
[19:07:34] INTERVAL_END activity=ScreenTimeTracking
[19:08:59] INTERVAL_START activity=ScreenTimeTracking
[19:11:04] EVENT appID=16CB572C... min=1 currentToday=2520s lastThresh=3600s
[19:11:04] SKIP_REGRESSION threshold=60 <= lastThreshold=3600 (same day)
```

After `INTERVAL_END`/`INTERVAL_START`, iOS resets its cumulative counter. min.1 = 60s, but `lastThreshold=3600` from pre-restart. 60 <= 3600 → blocked. Every subsequent event would also be blocked.

### Root Cause

`lastThreshold` is only reset at midnight (day rollover). There is NO reset when monitoring restarts. Additionally, `intervalDidStart` (iOS-initiated restart) does NOT set `monitoring_restart_timestamp` — only `ScreenTimeService.scheduleActivity()` does. So the 60s restart window filter doesn't activate either.

### Fix (2 changes)

**Change 1: `intervalDidStart` — set restart timestamp**

File: `DeviceActivityMonitorExtension.swift`, lines 83-88

```swift
override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
    if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
        // Set restart timestamp so filter chain treats iOS-initiated restarts
        // the same as app-initiated restarts (60s catch-up window + lastThreshold reset)
        defaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")
        debugLog("INTERVAL_START activity=\(activity.rawValue) session=\(Self.sessionID) — set restart timestamp", defaults: defaults)
    }
    updateHeartbeat()
}
```

**Change 2: Reset `lastThreshold` after restart window passes**

File: `DeviceActivityMonitorExtension.swift`, lines 240-243

Replace the existing flood counter reset:
```swift
// Past the 60s window — reset flood counter (flood window has passed)
if defaults.integer(forKey: "flood_skip_count") > 0 {
    defaults.set(0, forKey: "flood_skip_count")
}
```

With restart-aware reset:
```swift
// Past the 60s window — reset flood counter AND stale lastThreshold values
// When monitoring restarts (app-initiated or iOS INTERVAL_START), iOS resets its
// cumulative counter. lastThreshold values from the pre-restart epoch would cause
// SKIP_REGRESSION to block ALL genuine post-restart events.
let lastHandledRestart = defaults.double(forKey: "ext_lastHandledRestartTimestamp")
if restartTimestamp > lastHandledRestart && restartTimestamp > 0 {
    // New restart detected — reset lastThreshold for all tracked apps
    let trackedAppIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []
    for trackedAppID in trackedAppIDs {
        defaults.set(0, forKey: "usage_\(trackedAppID)_lastThreshold")
    }
    defaults.set(restartTimestamp, forKey: "ext_lastHandledRestartTimestamp")
    defaults.set(0, forKey: "flood_skip_count")
    debugLog("RESTART_THRESHOLD_RESET: Reset lastThreshold for \(trackedAppIDs.count) apps after monitoring restart", defaults: defaults)
} else if defaults.integer(forKey: "flood_skip_count") > 0 {
    defaults.set(0, forKey: "flood_skip_count")
}
```

### Why this works
1. `intervalDidStart` now sets `monitoring_restart_timestamp` → both app-initiated and iOS-initiated restarts are handled identically
2. The 60s window still blocks catch-up events after ANY restart
3. On the first event AFTER the 60s window, `lastThreshold` is reset for all apps → SKIP_REGRESSION won't block genuine events
4. `ext_lastHandledRestartTimestamp` prevents resetting on every event (only once per restart)

---

## Bug B: Batch Under-Counting (COOLDOWN + Flat +60s)

### Evidence (Device 2 log)

App 4AF106C2 between 12:11 and 13:11:
```
[12:11:45] EVENT appID=4AF106C2... min=16 lastThresh=1200s → SKIP_COOLDOWN (0s < 55s)
[12:11:45] EVENT appID=4AF106C2... min=19 → SKIP_COOLDOWN
[12:11:45] EVENT appID=4AF106C2... min=21 → SKIP_COOLDOWN
... (all COOLDOWN'd in batch)
[13:11:41] EVENT appID=4AF106C2... min=37 lastThresh=1200s → RECORDED oldToday=240s +60 = 300s
```

Between the last recording (lastThresh=1200s = min.20) and min.37, **17 minutes** of real usage accumulated. But we only added +60s (1 minute). The `thresholdSeconds - lastThreshold = 2220 - 1200 = 1020s` (17 min) was available but ignored.

### Root Cause

Line 351: `let newToday = currentToday + 60` — always adds flat +60s regardless of how many minutes passed since the last recording. When iOS batches events (delivering them hourly), the first event that passes COOLDOWN only adds 1 minute even when many minutes accumulated.

### Fix

File: `DeviceActivityMonitorExtension.swift`, line 349-358 (same-day recording block)

Change the flat +60 to use the delta between current and last threshold:

```swift
// Same day — use threshold delta to capture full usage since last recording.
// iOS may batch events hourly; flat +60 would lose accumulated minutes.
let currentToday = defaults.integer(forKey: todayKey)
let delta = max(60, thresholdSeconds - lastThreshold)
let newToday = currentToday + delta
debugLog("RECORDED appID=\(appID.prefix(8))... oldToday=\(currentToday)s +\(delta) = newToday=\(newToday)s, thresh=\(thresholdSeconds)s", defaults: defaults)
defaults.set(newToday, forKey: todayKey)
defaults.set(thresholdSeconds, forKey: lastThresholdKey)

// Update total
let currentTotal = defaults.integer(forKey: totalKey)
defaults.set(currentTotal + delta, forKey: totalKey)
```

Also update the ext_ keys (lines 362-370):
```swift
let newExtToday = (currentExtDate == dateString) ? currentExtToday + delta : delta
debugLog("EXT_WRITE_BLOCK appID=\(appID.prefix(8))... INCREMENT today=\(newExtToday) total=\(currentExtTotal + delta) hour=\(hour)", defaults: defaults)
defaults.set(newExtToday, forKey: "ext_usage_\(appID)_today")
defaults.set(currentExtTotal + delta, forKey: "ext_usage_\(appID)_total")
```

And the hourly bucket (line 385):
```swift
defaults.set(currentHourlySeconds + delta, forKey: "ext_usage_\(appID)_hourly_\(hour)")
```

### Why `max(60, thresholdSeconds - lastThreshold)` is safe
- **Normal 1-per-minute events**: delta = (N×60) - ((N-1)×60) = 60. Same as before.
- **Batched events**: delta = gap since last recording (e.g., 1020 for 17 min gap). Captures full usage.
- **After restart (with Bug A fix)**: lastThreshold reset to 0, delta = thresholdSeconds. First event = min.1 = 60s → delta = 60.
- **`max(60, ...)`**: Safety floor — ensures at least 1 minute even if lastThreshold is somehow stale.

---

## Files Modified

| File | Change |
|------|--------|
| `DeviceActivityMonitorExtension.swift:83-88` | `intervalDidStart` sets `monitoring_restart_timestamp` |
| `DeviceActivityMonitorExtension.swift:240-243` | Reset `lastThreshold` for all apps after restart window passes |
| `DeviceActivityMonitorExtension.swift:349-358` | Use threshold delta instead of flat +60 |
| `DeviceActivityMonitorExtension.swift:362-370` | Update ext_ keys with delta |
| `DeviceActivityMonitorExtension.swift:385` | Update hourly bucket with delta |

## Verification

1. **Build**: Xcode build succeeds
2. **Bug A fix**: After `INTERVAL_END`/`INTERVAL_START`, first log should show `RESTART_THRESHOLD_RESET: Reset lastThreshold for N apps` instead of `SKIP_REGRESSION`
3. **Bug B fix**: RECORDED log lines should show `+delta` values > 60 when events arrive in batches (e.g., `oldToday=240s +1020 = newToday=1260s`)
4. **No regression**: Day rollover still works (midnight resets lastThreshold independently)
5. **Catch-up still blocked**: Events within 60s of restart still get `SKIP_RESTART`
6. **Normal events unchanged**: When events arrive 1-per-minute, delta = 60, behavior identical to current
