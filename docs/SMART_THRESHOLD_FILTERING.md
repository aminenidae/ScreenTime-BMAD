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
| 60s restart window | `setUsageToThreshold()` in extension | Safety net for small usage-estimate drift; captures `catchup_max` |
| `catchup_max` correction | Extension + main app (4 paths) | Recovers lost usage from burst-delivered events |
| Calibration reset | `scheduleActivity()` in ScreenTimeService | One-time clear of inflated ext_usage from previous bug |
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

### UserDefaults Keys Added

```
catchup_max_{appID}            — per-app, highest threshold from burst (cleared after correction)
ext_usage_calibrated_v1        — one-time flag, prevents re-running calibration reset
```

---

## What Was Kept / Simplified

### Extension Filter Chain (`setUsageToThreshold()`)

| Filter | Purpose | Status |
|--------|---------|--------|
| 60s restart window | Safety net for small drift | Now also captures `catchup_max` before returning false |
| Post-restart threshold reset | Reset `lastThreshold` to 0 for all apps | Now applies `catchup_max` correction before resetting |
| 55s per-app cooldown | Same app can't fire twice in <55s | Now also captures `catchup_max` before returning false |
| Minimum threshold (60s) | Block sub-minute phantom events | Unchanged |
| Shielded reward app | Block events for blocked apps | Unchanged |
| Threshold progression | Same-day thresholds must increase | Unchanged |
| Catchup correction (pre-record) | Apply pending `catchup_max` before recording | **New** — corrects usage from cooldown-blocked bursts |

### Extension `intervalDidStart()`

- Set `monitoring_restart_timestamp`
- Apply pending `catchup_max` corrections for all tracked apps (primary correction path)
- Reset `lastThreshold` to 0 for all tracked apps
- Lifecycle log + heartbeat

### Foreground Recovery

Replaced flood-gated recovery with `ScreenTimeService.checkMonitoringHealth()`:
- Checks `activities.contains(activityName)` via `DeviceActivityCenter`
- If monitoring should be active but isn't registered → restarts
- Safe because `restartMonitoring()` → `scheduleActivity()` → smart filtering → no flood

---

## catchup_max Burst Correction

### Problem

When iOS kills the extension process and relaunches it, all accumulated thresholds arrive in the same second. The 55s per-app cooldown blocks all but the first event per app, losing most accumulated usage.

Example: App 2D4AEC4E had 16 events (min.28–43) arrive at 07:36:55. Only min.38 was recorded (+60s). Result: 28 min recorded vs 43 min actual. 15 minutes lost.

### Solution

During SKIP_RESTART and SKIP_COOLDOWN, capture the highest threshold per app as `catchup_max_{appID}`. This represents iOS's ground truth for cumulative usage. Apply bidirectional correction (up or down) at the next opportunity.

### 4 Correction Paths

| Path | Location | When | Priority |
|------|----------|------|----------|
| `intervalDidStart()` | Extension | iOS daily restart / monitoring restart | PRIMARY — extension often killed after burst |
| RESTART_THRESHOLD_RESET | Extension `setUsageToThreshold()` | First event after 60s restart window | Catch-ups from SKIP_RESTART |
| Before recording | Extension `setUsageToThreshold()` | Next event after 55s cooldown | Catch-ups from SKIP_COOLDOWN |
| `readExtensionUsageData()` | Main app ScreenTimeService | Every foreground via `refreshFromExtension()` | Most reliable — runs in main app process |

### Correction Logic (same in all 4 paths)

```
catchup_max = highest threshold seen during burst
currentToday = current recorded usage
correction = catchup_max - currentToday
→ Set usage_today = catchup_max
→ Set ext_usage_today = catchup_max
→ Adjust total by correction delta
→ Clear catchup_max key
```

---

## One-Time Calibration Reset

### Problem

The previous version's flood correction code (`flood_max` capture + bidirectional correction) inflated `ext_usage_today` values for some apps. After removing that code and adding smart filtering, these inflated values created a deadlock:

Inflated ext_usage → smart filtering skips all thresholds → no catch-up events → `catchup_max` never captures anything → no correction → ext_usage stays inflated.

Apps with 0 real usage were worst affected — they had inflated ext_usage but iOS had 0 cumulative usage, so nothing could ever fire.

### Solution

One-time reset gated by `ext_usage_calibrated_v1` flag, triggered at the top of `scheduleActivity()`:

1. Clear `ext_usage_today`, `ext_usage_date`, `usage_today` for all tracked apps
2. Reset `persistedApp.todaySeconds` to 0 in persistence
3. Set `ext_usage_calibrated_v1 = true`

After the reset, smart filtering sees 0 for all apps → registers all 60 thresholds → iOS sends catch-up events for actual cumulative usage → blocked by 60s window → `catchup_max` captures → main-app correction path applies on next foreground.

Apps with 0 real usage: no catch-ups (iOS has nothing to report) → ext_usage stays 0 → correct.

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
| Extension killed after burst delivery | `catchup_max` persists; corrected at next intervalDidStart or foreground |
| Main app killed in background | `checkMonitoringHealth()` recovers on next foreground |
| Inflated ext_usage from previous version | Calibration reset clears on first `scheduleActivity()` call |

---

## Files Modified

| File | Changes |
|------|---------|
| `Services/ScreenTimeService.swift` | Smart threshold filtering in `scheduleActivity()`, `checkMonitoringHealth()`, catchup_max correction in `readExtensionUsageData()`, calibration reset in `scheduleActivity()` |
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | `catchup_max` capture in SKIP_RESTART/SKIP_COOLDOWN, correction in RESTART_THRESHOLD_RESET + before-recording + `intervalDidStart()` |
| `ScreenTimeRewardsApp.swift` | Replaced flood recovery with `checkMonitoringHealth()` call |

---

## Historical Context

The flood problem emerged Dec 2, 2025 (`b5b097e`) when `monitoring_restart_timestamp` was first introduced with a 10-second catch-up window. Before that (`4aac8be`, Nov 27), the extension had no restart awareness — floods existed but events leaked through and were recorded, so monitoring never died. The problem intensified when thresholds were increased from 60 to 180 (Dec 10) and then 240 (Jan 21) per app, amplifying flood size. After reverting to 60 (Jan 24), the 60-second window was added but it blocked ALL events, consuming thresholds without recording — causing the "monitoring dies after flood" symptom that persisted through 21 fix attempts.

The fundamental insight: **prevent floods at the source** (skip already-exceeded thresholds) rather than **handle floods after they occur** (block + detect + correct + recover).
