# Smart Threshold Filtering

**Date**: 2026-02-14
**Supersedes**: `FLOOD_PREVENTION_AND_RECOVERY_PLAN.md`, `PHANTOM_FIX_ATTEMPTS.md`, `PHANTOM_FIX_ATTEMPT_12.md`, `PHANTOM_FIX_PLAN_2026-01-28.md`, `PHANTOM_RESTART_LESSONS_LEARNED.md`

---

## Problem

When `startMonitoring()` is called on `DeviceActivityCenter`, iOS fires catch-up threshold events for ALL cumulative daily usage. Previous approach: a 60-second window in the extension blocked these events, but iOS considered the thresholds "delivered." If usage was high enough (e.g., 30+ minutes across apps), all registered thresholds were consumed — monitoring died silently. The only recovery was manually opening the main app, which is impractical for a parental controls app on a child's device.

This led to 21+ fix attempts over 3 months (Dec 2025 – Feb 2026), adding increasingly complex flood detection/correction machinery: `flood_max` capture, bidirectional corrections, dual correction paths, `flood_detected` signaling, 65-second delayed restarts, foreground flood recovery, and `last_flood_correction_timestamp` suppression. Despite all this, the fundamental issue persisted: blocked catch-up events consumed thresholds, killing monitoring.

## Root Cause

Thresholds were always registered starting at minute 1 regardless of current usage. iOS always had catch-up events to fire for any accumulated usage.

## Solution

Register thresholds starting **above** current cumulative usage. No thresholds below current usage = no catch-up events = no floods = monitoring starts cleanly.

### How It Works

In `scheduleActivity()` (the only place `startMonitoring()` is called), before building the events dictionary:

1. Read each app's current daily usage from shared UserDefaults (`ext_usage_{logicalID}_today`)
2. Verify the data is from today (`ext_usage_{logicalID}_date`)
3. Compute `currentUsageMinutes = seconds / 60`
4. Filter out all threshold events where `minuteNumber <= currentUsageMinutes`
5. Pass only the remaining (above-current-usage) events to `startMonitoring()`

```
Example: App has 30 minutes of recorded usage today
- Before: Register thresholds 1-60 → iOS fires catch-up for 1-30 → all blocked → dead
- After:  Register thresholds 31-60 → iOS has nothing to catch up on → monitoring works
```

### Defense in Depth

| Layer | Location | Purpose |
|-------|----------|---------|
| Smart filtering | `scheduleActivity()` in ScreenTimeService | Prevents catch-up events at registration time |
| 60s restart window | `setUsageToThreshold()` in extension | Safety net for small usage-estimate drift |
| `activities.contains()` | `init()` crash recovery in ScreenTimeService | Skips restart if monitoring already active at OS level |
| `checkMonitoringHealth()` | Foreground check in ScreenTimeRewardsApp | Detects dead monitoring, triggers restart (safe with smart filtering) |
| `includesPastActivity: false` | `deviceActivityEvent()` on iOS 17.4+ | Apple's own catch-up prevention (additional safety) |

---

## What Was Removed

### Flood Machinery (all removed)

| Component | What It Did | Why Removed |
|-----------|-------------|-------------|
| `flood_skip_count` | Counted events blocked by 60s window | No floods → no blocked events to count |
| `flood_detected` / `flood_detected_time` | Signaled main app for recovery when >10 events blocked | No floods → no signal needed |
| `flood_max_{appID}` | Captured highest threshold during flood as iOS ground truth | No floods → no ground truth to capture |
| Bidirectional flood correction | Set usage to `flood_max` value (intervalDidStart + restart-reset block) | No floods → nothing to correct |
| `last_flood_correction_timestamp` | Suppressed false flood detection during expected catch-up | No flood detection to suppress |
| `last_flood_recovery_timestamp` | 5-minute cooldown for foreground recovery | Replaced by simple health check |
| 65s delayed restart | Second restart after crash recovery to get fresh thresholds | Smart filtering makes first restart sufficient |
| `ext_lastHandledRestartTimestamp` | Prevented re-applying correction for same restart | Kept — still used for lastThreshold reset |

### UserDefaults Keys Removed

```
flood_skip_count
flood_detected
flood_detected_time
flood_max_{appID}          (per-app, dynamic key)
last_flood_correction_timestamp
last_flood_recovery_timestamp
```

### UserDefaults Keys Kept

```
monitoring_restart_timestamp    — 60s safety window
ext_lastHandledRestartTimestamp  — post-restart lastThreshold reset
tracked_app_ids                 — iteration target for resets
wasMonitoringActive             — crash recovery flag
```

---

## What Was Kept / Simplified

### Extension Filter Chain (`setUsageToThreshold()`)

| Filter | Purpose | Status |
|--------|---------|--------|
| 60s restart window | Safety net for small drift | **Simplified** — just log + return false (no flood machinery) |
| Post-restart threshold reset | Reset `lastThreshold` to 0 for all apps | **Simplified** — no flood correction, just reset |
| 55s per-app cooldown | Same app can't fire twice in <55s | Unchanged |
| Minimum threshold (60s) | Block sub-minute phantom events | Unchanged |
| Shielded reward app | Block events for blocked apps | Unchanged |
| Threshold progression | Same-day thresholds must increase | Unchanged |

### Extension `intervalDidStart()`

Simplified to:
- Set `monitoring_restart_timestamp`
- Reset `lastThreshold` to 0 for all tracked apps
- Lifecycle log + heartbeat

### Foreground Recovery

Replaced flood-gated recovery with `ScreenTimeService.checkMonitoringHealth()`:
- Checks `activities.contains(activityName)` via `DeviceActivityCenter`
- If monitoring should be active but isn't registered → restarts
- Safe because `restartMonitoring()` → `scheduleActivity()` → smart filtering → no flood

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Fresh install (no usage) | All 60 thresholds registered (currentMinutes=0), normal |
| Usage >= 60 min for an app | All thresholds filtered, no events registered (tracking complete for today) |
| Usage estimate off by 1-2 min | 60s safety window catches the overlap |
| Day change | `ext_usage_date` is yesterday → currentMinutes=0 → all 60 thresholds |
| Multiple rapid restarts | Each call reads latest usage, filters correctly |
| Extension process dies during recording | UserDefaults persists; next event reads correct state |
| Main app killed in background | `checkMonitoringHealth()` recovers on next foreground |

---

## Files Modified

| File | Changes |
|------|---------|
| `Services/ScreenTimeService.swift` | Smart threshold filtering in `scheduleActivity()`, removed 65s delayed restart, added `checkMonitoringHealth()` |
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Simplified `intervalDidStart()`, stripped flood machinery from filter chain |
| `ScreenTimeRewardsApp.swift` | Replaced flood recovery with `checkMonitoringHealth()` call |

---

## Historical Context

The flood problem emerged Dec 2, 2025 (`b5b097e`) when `monitoring_restart_timestamp` was first introduced with a 10-second catch-up window. Before that (`4aac8be`, Nov 27), the extension had no restart awareness — floods existed but events leaked through and were recorded, so monitoring never died. The problem intensified when thresholds were increased from 60 to 180 (Dec 10) and then 240 (Jan 21) per app, amplifying flood size. After reverting to 60 (Jan 24), the 60-second window was added but it blocked ALL events, consuming thresholds without recording — causing the "monitoring dies after flood" symptom that persisted through 21 fix attempts.

The fundamental insight: **prevent floods at the source** (skip already-exceeded thresholds) rather than **handle floods after they occur** (block + detect + correct + recover).
