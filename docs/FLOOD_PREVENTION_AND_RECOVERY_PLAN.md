# Flood Prevention & Recovery Plan

## Context

iOS killed the app's DeviceActivity monitoring due to **energy budget exhaustion** (`Decision: MNP` / `Energy Budget: Required:1.00, Observed:0.00`). When the user manually launched the app, monitoring was found dead, triggering a restart that caused a catch-up flood of ~150 events. The 60s filter blocked all events (no inflation), but iOS considers all thresholds "delivered" — no new events fire for genuine usage.

**This is a production issue**, not just a debug/Xcode issue.

**Root cause**: Background tasks (config-check every 15 min, shield-state-sync every 15 min, usage-upload every 30 min) plus CloudKit push notification handling exhausted the app's iOS energy budget. iOS responded by killing processes and clearing the DeviceActivity monitoring registration.

---

## Part 1: Prevention — Eliminate Redundant Background Tasks

### Changes Made

| Task | Identifier | Before | After | Rationale |
|------|-----------|--------|-------|-----------|
| Config check | `com.screentimerewards.config-check` | 15 min poll | **6-hour fallback** | CloudKit push subscription (`parent-config-changes`) already delivers configs in real-time. The BGTask is now just a safety net for missed silent pushes. |
| Shield state sync | `com.screentimerewards.shield-state-sync` | 15 min auto-scheduled | **Merged into usage-upload** | Both are child→parent CloudKit uploads. Shield states now upload alongside usage records every 30 min instead of as a separate 15-min task. No longer auto-scheduled on startup. |
| Usage upload | `com.screentimerewards.usage-upload` | 30 min | **30 min (unchanged)** | Only way to get data from extension to parent (extension can't use CloudKit directly due to 6MB memory limit). Now also handles shield state sync. |

### Energy Impact

- **Before**: ~240 background wakeups/day (96 config-check + 96 shield-sync + 48 usage-upload)
- **After**: ~52 background wakeups/day (4 config-check + 0 shield-sync + 48 usage-upload)
- **Reduction**: ~188 fewer wakeups/day (~78% reduction)

### Rationale

The iOS energy budget system (`com.apple.pushLaunch` policy) tracks cumulative energy usage across all background activity — BGTasks, push notification handling, timers. When the budget hits zero, iOS issues `MNP` (May Not Proceed) and can:
- Deny future background launches
- Kill running processes
- Clear DeviceActivity monitoring registrations

The config-check BGTask was fully redundant — CloudKit silent push notifications already deliver parent config changes in real-time. The shield-state-sync was a separate task doing the same direction of work (child→parent) as usage-upload, so merging them eliminates the overhead of a separate wakeup.

---

## Part 2: Recovery — Delayed Restart After Flood

### The Problem

When monitoring restarts after being dead, iOS fires catch-up events for ALL cumulative daily usage. Our 60s filter blocks them (preventing inflation), but iOS considers the thresholds "delivered." For apps with high cumulative usage, all 60 thresholds are exhausted — no new events will fire for genuine usage.

### The Solution: Three-Layer Recovery

#### Layer 1: Extension Flood Detection

**File**: `DeviceActivityMonitorExtension.swift` (in SKIP_RESTART block)

When the extension sees many SKIP_RESTART events in quick succession, it sets a flag:

```
Inside SKIP_RESTART block:
1. Increment `flood_skip_count` in UserDefaults
2. If count > 10: set `flood_detected = true` and `flood_detected_time = now`
3. Reset counter when timeSinceRestart >= 60 (first event past the flood window)
```

Cost: 2 UserDefaults writes per event — lightweight enough to survive the flood.

#### Layer 2: Auto-Restart After Crash Recovery

**File**: `ScreenTimeService.swift` (after `scheduleActivity()` in init/crash recovery)

When the app detects monitoring is dead and restarts it, automatically schedule a second restart after 65 seconds:

```
scheduleActivity()  // Session 1 starts → catch-up flood → thresholds exhausted
isMonitoring = true

// Schedule delayed restart for fresh thresholds
Task {
    await Task.sleep(65 seconds)
    restartMonitoring(reason: "post-flood threshold refresh")
    // Session 2 starts → another catch-up flood → blocked by 60s filter
    // After 60s: fresh thresholds available for genuine usage
}
```

**Why 65s**: The 60s filter window must fully pass before the second restart's `monitoring_restart_timestamp` is set. 65s provides a 5s margin.

**Why this works**: Empirically proven in Attempts 1v2, 19, and 20 of PHANTOM_FIX_ATTEMPTS.md — after a restart + flood, genuine usage events fire for thresholds above the cumulative-usage level. The second restart gives iOS a fresh session where post-flood genuine usage triggers new events.

#### Layer 3: Foreground Recovery (Safety Net)

**File**: `ScreenTimeRewardsApp.swift` (in `.active` scenePhase handler)

If the auto-restart (Layer 2) didn't complete (e.g., app was killed before the 65s delay), the foreground check catches it:

```
On app foreground:
1. Check flood_detected flag in UserDefaults
2. If set AND > 65s since flood: clear flag, call restartMonitoring()
3. This gives the user a way to recover just by opening the app
```

### Recovery Flow

```
Normal production scenario:
1. iOS kills monitoring (energy budget / silent death)
2. User opens app
3. activities.contains() → false → scheduleActivity() → Session 1
4. Catch-up flood (~150 events) → all SKIP_RESTART blocked
5. Extension sets flood_detected=true (after 10+ skips)
6. 65s later: auto-restart → restartMonitoring() → Session 2
7. Session 2 catch-up flood → blocked by new 60s filter window
8. After 60s: genuine usage triggers fresh thresholds
9. Usage recording resumes

If app killed before 65s delay:
1. Steps 1-5 same as above
2. App killed before auto-restart fires
3. User reopens app → foreground check sees flood_detected=true
4. flood_detected_time > 65s ago → triggers restartMonitoring()
5. Recovery proceeds from step 7 above
```

---

## Files Modified (Summary)

| File | Change |
|------|--------|
| `DeviceActivityMonitorExtension.swift` | Add flood counter + flag in SKIP_RESTART block |
| `ScreenTimeService.swift` | Add 65s delayed restart after crash-recovery `scheduleActivity()` |
| `ScreenTimeRewardsApp.swift` | Add foreground flood recovery check in `.active` handler |
| `ChildBackgroundSyncService.swift` | Config-check → 6h fallback; shield-state-sync merged into usage-upload |

## New UserDefaults Keys (app group)

| Key | Type | Purpose |
|-----|------|---------|
| `flood_skip_count` | Int | Count of SKIP_RESTART events in current flood window |
| `flood_detected` | Bool | Flag: flood was detected, recovery needed |
| `flood_detected_time` | Double | Timestamp of flood detection |

---

## Known Limitations

- **~2 min tracking gap**: Between the initial flood and the second restart completing its own 60s filter window, genuine usage is not recorded. This is inherent to the iOS threshold system.
- **60+ min apps**: Apps with more than 60 minutes of daily cumulative usage have all 60 thresholds consumed by the catch-up flood. Even after a second restart, only thresholds ABOVE the cumulative level fire. If all 60 are already consumed, no new events fire until the next day.
- **Requires app launch**: Recovery only starts when the user opens the app (since that's what triggers monitoring restart). If the user never opens the app, monitoring stays dead.

---

## Verification Plan

1. **Energy prevention**: Deploy and monitor iOS console for `Energy Budget Policy` / `MNP` logs — expect significantly fewer occurrences with ~78% fewer background wakeups
2. **Flood recovery (automated)**:
   - Force-close the app, wait for monitoring to die (or observe in console)
   - Relaunch the app
   - Watch logs: first SKIP_RESTART flood → flood_detected flag → 65s delay → second restart
   - Use a tracked app after recovery — verify events fire and usage increments
3. **Flood recovery (foreground)**:
   - Trigger a flood, then kill the app within 65s (before auto-restart)
   - Reopen the app — verify foreground check detects flag and triggers restart
4. **No regression**: Normal app usage (no flood scenario) should be completely unaffected
5. **Parent UX**: Verify parent dashboard still receives usage data within 30 min of child activity (usage-upload task now includes shield state sync)
