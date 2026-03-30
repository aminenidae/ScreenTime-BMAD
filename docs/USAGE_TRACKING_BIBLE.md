# Usage Tracking Bible

**Last Updated**: 2025-12-14
**Status**: STABLE (v1.1.9-beta)
**Author**: Development Team + Claude Code

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Data Flow](#data-flow)
4. [Key Files](#key-files)
5. [UserDefaults Key Reference](#userdefaults-key-reference)
6. [Phantom Event Detection](#phantom-event-detection)
7. [The Journey: Mistakes & Lessons](#the-journey-mistakes--lessons)
8. [Current Implementation](#current-implementation)
9. [Known Limitations](#known-limitations)
10. [Debugging Guide](#debugging-guide)
11. [Historical Issues & Resolutions](#historical-issues--resolutions)

---

## Executive Summary

Screen Time Rewards tracks app usage via iOS's DeviceActivity framework. The extension receives threshold events (every minute) and records usage to shared UserDefaults. The main app syncs this data for display.

**The Hard Truth**: iOS DeviceActivityMonitor is unpredictable. It sends "phantom" events for ALL monitored apps when monitoring restarts, not just the app being used. Our implementation has evolved through many painful iterations to handle this behavior.

**Current Solution**:
- INCREMENT-based tracking (+60s per valid event)
- Three-layer phantom detection (SKIP_RESTART, SKIP_RAPID, THRESH_DECREASE)
- Extension writes to `ext_usage_*` keys (source of truth)
- Main app syncs from extension, trusting it completely

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS DeviceActivity Framework                  │
│  - Tracks all app usage in background                           │
│  - Fires threshold events when apps reach configured minutes    │
│  - QUIRK: Fires "catch-up" events for ALL apps on restart       │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│            DeviceActivityMonitor Extension                       │
│            (ScreenTimeActivityMonitorExtension)                  │
│                                                                  │
│  Entry Point: eventDidReachThreshold()                          │
│                                                                  │
│  Responsibilities:                                               │
│  1. Filter phantom events (SKIP_RESTART, SKIP_RAPID)            │
│  2. Record valid usage (+60s per event)                         │
│  3. Write to shared UserDefaults                                │
│  4. Send Darwin notification to main app                        │
│  5. Control shields (unlock/block reward apps)                  │
│                                                                  │
│  Memory Target: <6MB                                             │
│  Strategy: Primitive key-value storage, no JSON parsing         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                │ Writes to App Group UserDefaults
                                │ Posts Darwin Notification
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Shared UserDefaults                             │
│                  (App Group: group.com.screentimerewards.shared) │
│                                                                  │
│  Source of Truth Keys (ext_*):                                   │
│  - ext_usage_<appID>_today    (today's seconds)                 │
│  - ext_usage_<appID>_total    (all-time seconds)                │
│  - ext_usage_<appID>_date     (YYYY-MM-DD for day detection)    │
│  - ext_usage_<appID>_hour     (last update hour)                │
│  - ext_usage_<appID>_hourly_N (per-hour buckets, N=0-23)        │
│                                                                  │
│  Legacy Keys (usage_*):                                          │
│  - usage_<appID>_today        (seconds, may be stale)           │
│  - usage_<appID>_total        (seconds)                         │
│  - usage_<appID>_lastThreshold (for duplicate detection)        │
│  - usage_<appID>_lastEventTime (for rapid-fire detection)       │
│  - usage_<appID>_reset        (timestamp of last daily reset)   │
│                                                                  │
│  Control Keys:                                                   │
│  - monitoring_restart_timestamp (set by main app on restart)    │
│  - extension_debug_log        (rolling 500-entry log buffer)    │
│  - ext_total_events_received  (counter for diagnostics)         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                │ Darwin Notification triggers sync
                                │ (or DEBUG polling every 10s)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Main App (ScreenTimeService)                  │
│                                                                  │
│  Sync Function: readExtensionUsageData()                         │
│                                                                  │
│  Responsibilities:                                               │
│  1. Listen for Darwin notifications                             │
│  2. Read ext_usage_* keys (source of truth)                     │
│  3. Update UsagePersistence (JSON file)                         │
│  4. Update in-memory appUsages dictionary                       │
│  5. Notify UI observers                                         │
│                                                                  │
│  Trust Model: Extension is ALWAYS right                          │
│  - If ext < persisted, persisted was inflated → correct it      │
│  - If ext > persisted, new usage → sync it                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Normal Usage Recording

```
1. User opens learning app
2. iOS tracks usage internally
3. After 1 minute, iOS calls eventDidReachThreshold(event: "usage.app.0.min.1")
4. Extension logs: THRESHOLD_CALL event=usage.app.0.min.1
5. Extension extracts appID from event mapping
6. Extension checks phantom detection:
   - SKIP_RESTART: Is timeSinceRestart < 50s? → Skip
   - SKIP_RAPID: Is timeSinceLastEvent < 30s? → Skip
   - THRESH_DECREASE: Is newThreshold < lastThreshold? → Check above, maybe skip
7. If passes all checks:
   - Increment usage_<appID>_today by 60s
   - Increment ext_usage_<appID>_today by 60s
   - Log: RECORDED appID=XXXX... oldToday=0s +60 = newToday=60s
8. Extension posts Darwin notification
9. Main app receives notification, calls readExtensionUsageData()
10. Main app reads ext_usage_<appID>_today, syncs to persistence
11. UI updates to show new usage
```

### Phantom Event (Blocked)

```
1. User adds new app to monitoring list
2. Main app restarts monitoring, sets monitoring_restart_timestamp
3. iOS sends catch-up events for ALL monitored apps within milliseconds
4. Extension receives: eventDidReachThreshold(event: "usage.app.0.min.3")
5. Extension checks: timeSinceRestart = 2s < 50s
6. Extension logs: SKIP_RESTART appID=XXXX... timeSinceRestart=2s < 50s
7. No usage recorded, no notification sent
8. User's existing usage preserved correctly
```

---

## Key Files

| File | Location | Purpose |
|------|----------|---------|
| `DeviceActivityMonitorExtension.swift` | `ScreenTimeActivityExtension/` | Extension that receives iOS threshold events |
| `ScreenTimeService.swift` | `ScreenTimeRewards/Services/` | Main app service for monitoring and sync |
| `UsagePersistence.swift` | `ScreenTimeRewards/Shared/` | JSON-based persistence layer |
| `AppUsageViewModel.swift` | `ScreenTimeRewards/ViewModels/` | UI data binding for usage display |

---

## UserDefaults Key Reference

### Extension-Written Keys (Source of Truth)

| Key Pattern | Type | Description |
|-------------|------|-------------|
| `ext_usage_<appID>_today` | Int | Today's usage in seconds |
| `ext_usage_<appID>_total` | Int | All-time usage in seconds |
| `ext_usage_<appID>_date` | String | Date of last update (YYYY-MM-DD) |
| `ext_usage_<appID>_hour` | Int | Hour of last update (0-23) |
| `ext_usage_<appID>_hourly_N` | Int | Usage in hour N (0-23) |
| `ext_usage_<appID>_timestamp` | Double | Unix timestamp of last update |

### Legacy Keys (Used for Phantom Detection)

| Key Pattern | Type | Description |
|-------------|------|-------------|
| `usage_<appID>_today` | Int | Today's usage (may drift from ext_*) |
| `usage_<appID>_total` | Int | All-time usage |
| `usage_<appID>_lastThreshold` | Int | Last recorded threshold in seconds |
| `usage_<appID>_lastEventTime` | Double | Unix timestamp of last event |
| `usage_<appID>_reset` | Double | Unix timestamp of last daily reset |

### Control Keys

| Key | Type | Description |
|-----|------|-------------|
| `monitoring_restart_timestamp` | Double | Set by main app when monitoring restarts |
| `extension_debug_log` | String | Rolling log buffer (500 entries) |
| `ext_total_events_received` | Int | Total threshold events received |
| `extension_heartbeat` | Double | Last extension activity timestamp |
| `extension_memory_mb` | Double | Extension memory usage in MB |

### Event Mapping Keys

| Key Pattern | Type | Description |
|-------------|------|-------------|
| `map_<eventName>_id` | String | Maps event name to logical app ID |
| `eventMappings` | Data | JSON blob of all event mappings (fallback) |

---

## Phantom Event Detection

### The Problem

iOS DeviceActivityMonitor has undocumented behavior:

1. When monitoring starts/restarts, iOS fires threshold events for ALL monitored apps
2. These "catch-up" events arrive within milliseconds of each other
3. Events may have LOWER thresholds than previously recorded
4. Without detection, usage would inflate incorrectly

### Evidence from Logs

```
[11:24:38.001] EVENT appID=6D7C9194... min=6 currentToday=1440s lastThresh=1860s
[11:24:38.002] THRESH_DECREASE appID=6D7C9194... new=360s < last=1860s
[11:24:38.003] SKIP_RAPID appID=6D7C9194... timeSinceLastEvent=0s < 30s
[11:24:38.004] EVENT appID=25FCC5BC... min=7 currentToday=2820s lastThresh=2580s
```

All events arrived within 3ms - clearly phantom events, not real usage.

### Three-Layer Detection

#### Layer 1: SKIP_RESTART (50s window)

```swift
let timeSinceRestart = nowTimestamp - restartTimestamp
if timeSinceRestart < 50.0 && restartTimestamp > 0 {
    debugLog("SKIP_RESTART appID=\(appID)... timeSinceRestart=\(Int(timeSinceRestart))s < 50s")
    return false
}
```

**Why 50s?** Originally 120s, but this was too aggressive. Events arriving 50-120s after restart are likely legitimate. Testing confirmed 50s is the sweet spot.

#### Layer 2: SKIP_RAPID (30s per-app window)

```swift
let timeSinceLastEvent = nowTimestamp - lastEventTime
if timeSinceLastEvent < 30.0 && lastEventTime > 0 {
    debugLog("SKIP_RAPID appID=\(appID)... timeSinceLastEvent=\(Int(timeSinceLastEvent))s < 30s")
    return false
}
```

**Why 30s?** Real usage can't generate events faster than once per minute. If events arrive <30s apart, they're phantom catch-up events.

#### Layer 3: THRESH_DECREASE (threshold comparison)

```swift
if thresholdSeconds < lastThreshold {
    // Threshold decreased - could be catch-up OR legitimate new session
    // Check SKIP_RESTART and SKIP_RAPID first
    // If both pass, it's likely a legitimate new session → reset lastThreshold
}
```

---

## The Journey: Mistakes & Lessons

### Mistake 1: SET Semantics for ext_ Keys

**What We Tried**:
```swift
newExtToday = max(currentExtToday, thresholdSeconds)
```

**Why It Failed**: When iOS restarts monitoring, it resets its internal counter. A new min=1 event would be rejected because `max(300, 60) = 300`. Real usage stopped recording.

**Lesson**: SET semantics break after monitoring restart. INCREMENT + phantom detection is the correct approach.

---

### Mistake 2: 120s SKIP_RESTART Window

**What We Tried**: Skip ALL events within 120s of monitoring restart.

**Why It Failed**: Legitimate events arriving 50-120s after restart were blocked. Apps with existing usage couldn't record new usage.

**The Debugging Journey**:
1. Observed: Fresh apps work, existing apps don't record new usage
2. Hypothesis: iOS throttling? No - fresh apps work fine
3. Key insight: The 120s window is too aggressive
4. Fix: Reduce to 50s
5. Result: Existing apps now record correctly

**Lesson**: Phantom detection windows need careful tuning. Too aggressive = blocks real usage. Too lenient = phantom inflation.

---

### Mistake 3: Sync Reads from Legacy Keys

**What We Tried**: Main app sync read from `usage_*` keys.

**Why It Failed**: Legacy keys use INCREMENT semantics and were vulnerable to phantom events writing extra usage before detection kicked in.

**Fix**: Sync now reads from `ext_usage_*` keys exclusively.

---

### Mistake 4: Only Sync if ext > persisted

**What We Tried**:
```swift
if extTodaySeconds > persistedApp.todaySeconds {
    persistedApp.todaySeconds = extTodaySeconds
}
```

**Why It Failed**: If persisted value was inflated (from earlier bug), it would never be corrected.

**Fix**: Always trust extension:
```swift
persistedApp.todaySeconds = extTodaySeconds
```

---

### Mistake 5: Insufficient Debug Logging

**What We Tried**: 100-entry rolling buffer, no session ID.

**Why It Failed**: During rapid events, buffer would overflow. Couldn't tell which extension instance wrote which logs.

**Fix**:
- Increased buffer to 500 entries
- Added session ID (8-char UUID) to all log entries
- Added THRESHOLD_CALL logging at entry point
- Added event counter for diagnostics

---

### Mistake 6: Darwin Notifications Don't Work in Xcode

**Symptom**: No real-time updates when debugging from Xcode.

**Root Cause**: Darwin notifications are sandboxed differently when app runs from debugger.

**Fix**: Added DEBUG polling (every 10s) for Xcode builds:
```swift
#if DEBUG
startDebugPolling()
#endif
```

---

## Current Implementation

### Extension: `setUsageToThreshold()`

```swift
private func setUsageToThreshold(appID: String, thresholdSeconds: Int, defaults: UserDefaults) -> Bool {
    // 1. Day rollover check
    if lastReset < startOfToday {
        // Reset all counters, set today = 60s
        return true
    }

    // 2. Duplicate check
    if thresholdSeconds == lastThreshold {
        // SKIP_DUP
        return false
    }

    // 3. Threshold decrease check (potential catch-up)
    if thresholdSeconds < lastThreshold {
        // Check SKIP_RESTART (50s)
        if timeSinceRestart < 50.0 {
            return false
        }
        // Check SKIP_RAPID (30s)
        if timeSinceLastEvent < 30.0 {
            return false
        }
        // Both passed → new session, reset lastThreshold
    }

    // 4. Record usage
    newToday = currentToday + 60
    defaults.set(newToday, forKey: todayKey)

    // 5. Update ext_ keys (source of truth)
    newExtToday = currentExtToday + 60
    defaults.set(newExtToday, forKey: extTodayKey)

    return true
}
```

### Main App: `readExtensionUsageData()`

```swift
private func readExtensionUsageData(defaults: UserDefaults) {
    for (logicalID, var usage) in appUsages {
        // Read from ext_ keys (source of truth)
        let extTodaySeconds = defaults.integer(forKey: "ext_usage_\(logicalID)_today")
        let extDateString = defaults.string(forKey: "ext_usage_\(logicalID)_date")

        // Check if data is from today
        let isFromToday = extDateString == todayDateString

        if isFromToday {
            // Always trust extension
            persistedApp.todaySeconds = extTodaySeconds
            usagePersistence.saveApp(persistedApp)
        }
    }
}
```

---

## Known Limitations

### iOS Framework Limitations

1. **Event Throttling**: iOS may not fire events exactly every minute. Events can be batched or skipped entirely. We've observed 5+ minutes of usage only generating 3 events.

2. **Phantom Events**: iOS fires catch-up events when monitoring restarts. This is undocumented behavior we must handle.

3. **No Backfill**: If the extension doesn't run (device off, app not authorized), usage is lost.

### Our Limitations

1. **50s Blind Spot**: Events within 50s of monitoring restart are always skipped. If a user genuinely uses an app for <50s after restart, that usage is lost.

2. **30s Minimum Between Events**: Real usage <30s apart is theoretically possible but practically rare. We accept this trade-off.

3. **Daily Reset Timing**: If the extension doesn't run at midnight, daily reset happens on first event of new day. Edge cases possible around midnight.

---

## Debugging Guide

### Reading Extension Logs

Access via diagnostic view or Xcode console:

```
[01:15:28.465][433FA387] EVENT appID=CCEBCF2C... min=6 currentToday=300s lastThresh=300s
[01:15:28.480][433FA387] THRESH_DECREASE appID=CCEBCF2C... new=360s < last=300s
[01:15:28.481][433FA387] SKIP_RESTART appID=CCEBCF2C... timeSinceRestart=85s < 50s
```

**Key Log Patterns**:
- `THRESHOLD_CALL` - Event received (first log entry)
- `EVENT` - Event being processed
- `SKIP_RESTART` - Phantom detected (too close to restart)
- `SKIP_RAPID` - Phantom detected (too fast for same app)
- `SKIP_DUP` - Duplicate threshold
- `THRESH_DECREASE` - Threshold went down (investigating)
- `THRESH_RESET` - New session detected, reset tracking
- `RECORDED` - Usage recorded successfully
- `EXT_WRITE_BLOCK` - Writing to ext_ keys

### Diagnostic Checklist

1. **No events recording?**
   - Check `ext_total_events_received` - is it increasing?
   - If yes: Events arriving but being skipped (check SKIP_* logs)
   - If no: iOS not calling extension (check authorization)

2. **Usage not syncing to UI?**
   - Check `ext_usage_<appID>_today` vs persisted value
   - Check `ext_usage_<appID>_date` matches today
   - Darwin notifications may not work in Xcode (use DEBUG polling)

3. **Usage inflating?**
   - Check for RECORDED entries without corresponding user activity
   - May indicate phantom detection not catching all cases
   - Check `monitoring_restart_timestamp` is being set

4. **Usage dropping unexpectedly?**
   - Check for THRESH_RESET entries
   - May indicate false-positive new session detection
   - Check `timeSinceLastEvent` values in logs

---

## Historical Issues & Resolutions

### Issue: Phantom Usage Inflation (Dec 2025)

**Symptom**: Using 1 app for 2 minutes recorded 11 minutes across 5 apps.

**Root Cause**: iOS sends threshold events for ALL monitored apps on restart.

**Fix**: Three-layer phantom detection (SKIP_RESTART, SKIP_RAPID, THRESH_DECREASE)

**Commit**: `f68ea18`

---

### Issue: Continued Usage Not Recording (Dec 14, 2025)

**Symptom**: Apps with existing usage (5 min) couldn't record new usage. Fresh apps worked fine.

**Root Cause**: 120s SKIP_RESTART window was too aggressive. Events at 85s were blocked.

**Fix**: Reduced SKIP_RESTART from 120s to 50s.

**Commit**: `b8f7b53` (v1.1.9-beta)

---

### Issue: Real Usage Stopped After Monitoring Restart (Dec 2025)

**Symptom**: After Fix 1-3, real usage stopped recording.

**Root Cause**: SET semantics (`max(current, threshold)`) rejected low thresholds after iOS reset its counter.

**Fix**: Reverted to INCREMENT semantics (`current + 60`).

**Commit**: `f68ea18`

---

### Issue: No Real-Time Updates in Xcode (Dec 2025)

**Symptom**: Extension recorded usage but UI didn't update.

**Root Cause**: Darwin notifications don't work when running from Xcode debugger.

**Fix**: Added DEBUG polling every 10 seconds.

**Commit**: `f68ea18`

---

### Issue: Ghost Increments (Partially Resolved)

**Symptom**: ext_today values increased without corresponding RECORDED logs.

**Possible Causes**:
1. Debug buffer overflow (fixed: increased to 500)
2. Old extension instance still running
3. Unlogged code path

**Status**: Improved with session ID tracking and larger buffer. Monitor for recurrence.

---

## Appendix: Stable Build Reference

The iPad build from December 10, 2025 has been stable for days:

- **Commit**: `365ab23`
- **Thresholds**: 60 per app
- **ext_ Logic**: INCREMENT
- **Sync Source**: ext_ keys
- **Result**: Up to 66 minutes tracked, no inflation, no drops

This serves as our reference implementation.

---

## Appendix: Testing Checklist

### Test 1: Fresh Install
- [ ] Delete app, install fresh
- [ ] Add 1 learning app
- [ ] Run for 3 minutes → verify 180s

### Test 2: Continued Usage
- [ ] With existing usage, run 2+ more minutes
- [ ] Verify +60s per minute
- [ ] Repeat 3 times

### Test 3: App Switch
- [ ] Run App A for 2 min → 120s
- [ ] Run App B for 2 min → 120s
- [ ] Run App A for 2 min → A=240s, B=120s

### Test 4: Post-Restart (50s window)
- [ ] Run app 1 min, restart monitoring
- [ ] Wait 50+ seconds
- [ ] Run 2 more minutes → verify records

### Test 5: Day Boundary
- [ ] Note usage before midnight
- [ ] After midnight, run app
- [ ] Verify fresh start for today

---

*This document is the authoritative reference for Screen Time Rewards usage tracking. Update it whenever significant changes are made.*
