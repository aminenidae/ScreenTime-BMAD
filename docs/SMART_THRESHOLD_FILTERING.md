# Smart Threshold Filtering

**Date**: 2026-02-14 (original); last updated 2026-04-16
**Supersedes**: `FLOOD_PREVENTION_AND_RECOVERY_PLAN.md`, `PHANTOM_FIX_ATTEMPTS.md`, `PHANTOM_FIX_ATTEMPT_12.md`, `PHANTOM_FIX_PLAN_2026-01-28.md`, `PHANTOM_RESTART_LESSONS_LEARNED.md`

> **Status (2026-04-16): ✅ FIXED on test device after 3-day soak.** Apr 12 extension-side midnight rebuild (`1c06b67`) + Apr 13 intraday-reset revert (`ae2e565`) are both committed and validated against iOS Screen Time wall-clock on Apr 16. Continued multi-device observation recommended before declaring closed across the install base — see [Apr 16 Soak Day 3](#apr-16-soak-day-3--fixed-wall-clock-parity-with-ios-screen-time-apr-16-2026).

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
| Calibration reset | `scheduleActivity()` in ScreenTimeService | One-time clear of inflated ext_usage from previous bug |
| `activities.contains()` | `init()` crash recovery in ScreenTimeService | Skips restart if monitoring already active at OS level |
| `checkMonitoringHealth()` | Foreground check in ScreenTimeRewardsApp | Detects dead monitoring, triggers restart (safe with smart filtering) |
| `includesPastActivity: true` | `deviceActivityEvent()` | Cumulative day tracking — required for sliding window thresholds to work correctly |

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
catchup_max_{appID}            — per-app, captured in SKIP_RESTART, applied by readExtensionUsageData (primary). Cleared by scheduleActivity() before restart + intervalDidStart() at midnight.
midnight_pending_refresh       — blocks all events between midnight and first scheduleActivity()
midnight_pending_timestamp     — timestamp for 2-hour safety timeout on SKIP_MIDNIGHT
midnight_diagnostic_active     — flag: true from midnight until first scheduleActivity()
midnight_diagnostic_log        — dedicated log for midnight→scheduleActivity window
midnight_diagnostic_date       — tracks which day diagnostic was last activated (prevents restart overwrite)
ext_usage_calibrated_v1        — one-time flag, prevents re-running calibration reset
catchup_fix_v2                 — one-time flag, clears stale catchup_max from SKIP_RESTART capture era
catchup_fix_v3                 — one-time flag, clears inflated usage from SKIP_COOLDOWN capture era
catchup_fix_v4                 — one-time flag, clears stale values for cross-midnight fix clean start
catchup_fix_v5                 — NOT present in current code (v5 removal was reverted; flag never existed in Feb 23 state)
```

---

## What Was Kept / Simplified

### Extension Filter Chain (`setUsageToThreshold()`)

| Filter | Purpose | Status |
|--------|---------|--------|
| **SKIP_MIDNIGHT** (Filter 0) | Block ALL events between midnight and first `scheduleActivity()` | Prevents stale cross-midnight catch-ups from recording phantom usage. 2-hour safety timeout. |
| **SKIP_RESTART** (Filter 1, 60s window) | Absorb post-restart catch-up burst | Captures `catchup_max` per app (highest threshold). Safe because SKIP_MIDNIGHT blocks stale data upstream. |
| Post-restart threshold reset | Reset `lastThreshold` to 0 for all apps | lastThreshold reset only (catchup_max NOT consumed here) |
| **SKIP_COOLDOWN** (55s per-app) | Same app can't fire twice in <55s | Drops events where `threshold <= lastThreshold` AND within 55s. Events with `threshold > lastThreshold` bypass cooldown (batch fix Feb 28). NO catchup_max capture. |
| Minimum threshold (60s) | Block sub-minute phantom events | Unchanged |
| Shielded reward app | Block events for blocked apps | Unchanged |
| Threshold progression | Same-day thresholds must increase | Unchanged |

### Extension `intervalDidStart()`

- Set `monitoring_restart_timestamp`
- Midnight diagnostic activation (day-change check — `midnight_diagnostic_date`)
- **At midnight (day changed):** Set `midnight_pending_refresh` flag, clear stale `catchup_max` for all apps
- Reset `lastThreshold` to 0 for all tracked apps
- Lifecycle log + heartbeat

### Foreground Recovery

Replaced flood-gated recovery with `ScreenTimeService.checkMonitoringHealth()`:
- Checks `activities.contains(activityName)` via `DeviceActivityCenter`
- If monitoring should be active but isn't registered → restarts
- Safe because `restartMonitoring()` → `scheduleActivity()` → smart filtering → no flood

---

## catchup_max Burst Correction (REVIVED Feb 20, REMOVED Feb 23 v5, RESTORED Feb 25 v6)

### Original Problem

When iOS kills the extension process and relaunches it, all accumulated thresholds arrive in the same second. The 55s per-app cooldown blocks all but the first event per app, losing most accumulated usage (up to 15 min per burst).

### Original Solution

During SKIP_COOLDOWN, capture the highest threshold per app as `catchup_max_{appID}`. Apply upward correction at the next opportunity via 4 correction paths.

### Why It Was Removed

With `includesPastActivity: true`, iOS retains cumulative usage across midnight. After day rollover, catch-up bursts carry **yesterday's stale residual data** (e.g., 55-88 min). These bursts can arrive **40+ minutes after restart** (via extension kill/relaunch cycles), bypassing the 60s absorb window entirely. SKIP_COOLDOWN captured these stale thresholds into `catchup_max`, which was then applied as an upward correction — inflating usage by 60+ min.

This caused cascading failures: inflated learning app usage falsely met goals → reward apps unshielded → those catch-ups also captured → all apps showed 60+ min when real usage was 5-27 min.

**Fix (Feb 16):** Removed catchup_max capture from SKIP_COOLDOWN entirely. Late bursts (40+ min after restart, via extension kill/relaunch) can still carry stale data through SKIP_COOLDOWN.

**Fix (Feb 20):** Re-enabled catchup_max capture in SKIP_RESTART, protected by new SKIP_MIDNIGHT filter. Stale cross-midnight catch-ups are blocked by SKIP_MIDNIGHT before reaching SKIP_RESTART. Only legitimate post-`scheduleActivity()` catch-ups (which represent real today usage via iOS's cumulative counter) are captured.

**Trade-off (resolved Feb 28):** Mid-day SKIP_COOLDOWN burst corrections were previously lost (10-20 min undercount). Fixed by adding `threshold > lastThreshold` bypass — batch events with new thresholds now pass through SKIP_COOLDOWN and record correctly. See "SKIP_COOLDOWN Batch Event Fix" section below.

### 2 Correction Paths (v6 — SUPERSEDED, see "Surgical Revert" section below)

| Path | Location | Status |
|------|----------|--------|
| `readExtensionUsageData()` | Main app ScreenTimeService | **Primary** — on foreground sync, if `catchup_max > ext_usage`, sets ext_usage and usage_today to catchup_max. Clears catchup_max after applying. Works even when no events fire. |
| NEW_DAY branch | Extension `setUsageToThreshold()` | **Implicit** — `thresholdSeconds` already includes catchup usage via iOS cumulative (no explicit catchup_max read needed). |

Note: v6 simplifies from the original 4 correction paths to 2. The main app's `readExtensionUsageData()` is the primary recovery path. Extension-side `intervalDidStart()` and before-recording correction paths were removed with v5 and not restored.

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
| Extension killed after burst delivery | First event of burst recorded (+60s); rest silently dropped. Sliding window self-corrects over subsequent restarts |
| Main app killed in background | `checkMonitoringHealth()` recovers on next foreground |
| Inflated ext_usage from previous version | Calibration reset clears on first `scheduleActivity()` call |
| Midnight to first app launch | No usage tracked. Stale thresholds + SKIP_MIDNIGHT + no rebuild mechanism. Requires main app or BGTask to call `scheduleActivity()`. See "Midnight Monitoring Gap" section. |

---

## Files Modified

| File | Changes |
|------|---------|
| `Services/ScreenTimeService.swift` | Smart threshold filtering in `scheduleActivity()`, `checkMonitoringHealth()` (incl. midnight detection), catchup_max correction in `readExtensionUsageData()`, calibration resets (v1/v2/v3/v4) in `scheduleActivity()`, midnight flag clearing |
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | SKIP_MIDNIGHT filter, `catchup_max` capture in SKIP_RESTART, correction paths in before-recording (same-day) + NEW_DAY (catchup_max init) + `intervalDidStart()` (same-day), midnight diagnostic instrumentation |
| `ScreenTimeRewardsApp.swift` | Replaced flood recovery with `checkMonitoringHealth()` call |

---

## Historical Context

The flood problem emerged Dec 2, 2025 (`b5b097e`) when `monitoring_restart_timestamp` was first introduced with a 10-second catch-up window. Before that (`4aac8be`, Nov 27), the extension had no restart awareness — floods existed but events leaked through and were recorded, so monitoring never died. The problem intensified when thresholds were increased from 60 to 180 (Dec 10) and then 240 (Jan 21) per app, amplifying flood size. After reverting to 60 (Jan 24), the 60-second window was added but it blocked ALL events, consuming thresholds without recording — causing the "monitoring dies after flood" symptom that persisted through 21 fix attempts.

The fundamental insight: **prevent floods at the source** (skip already-exceeded thresholds) rather than **handle floods after they occur** (block + detect + correct + recover).

### catchup_max Removal (Feb 16, 2026)

The `catchup_max` burst correction system, added alongside smart filtering, was designed to recover usage lost when iOS delivers multiple events in a single burst (only the first passes the 55s cooldown). However, with `includesPastActivity: true`, iOS retains cumulative usage across midnight. After day rollover, catch-up bursts carry yesterday's stale data. These bursts arrive via extension kill/relaunch cycles — sometimes 40+ minutes after the last restart — completely bypassing the 60s absorb window. SKIP_COOLDOWN captured these stale thresholds into `catchup_max`, inflating usage by 60+ min and falsely meeting learning goals.

The fix was to remove `catchup_max` capture entirely, accepting minor undercounting from legitimate mid-day bursts (the sliding window self-corrects over subsequent restarts). One-time `catchup_fix_v3` reset clears inflated values.

### Cross-Midnight Catch-Up Overcounting AND Undercounting (Feb 18-20, 2026) — FIXED

**Status:** Fixed with SKIP_MIDNIGHT filter + catchup_max capture revival. Two symmetric problems resolved:

**Observed:** App 9360F490 showed 36 min of usage when real usage was 22 min (14 min phantom). Other learning apps were stuck at 1 min (undercounting) because the catch-up flood consumed all registered thresholds, killing monitoring for ~29 minutes.

**Root cause:** At midnight, `intervalDidStart()` fires (iOS daily interval restart) but `scheduleActivity()` does NOT run. Yesterday's stale thresholds remain registered. With `includesPastActivity: true`, iOS cumulative carries yesterday's residual (14 min). iOS fires catch-up events for all stale thresholds below this cumulative.

Unlike `startMonitoring()` catch-ups (which arrive as a burst and are blocked by SKIP_COOLDOWN), midnight catch-ups arrive individually, spaced ~60s apart. Each passes the 55s SKIP_COOLDOWN and records 60s as today's usage. Result: yesterday's 14 min residual recorded as 14 min phantom usage today.

**Mechanism (traced from Feb 18 extension + monitoring logs):**

1. `23:59:02` — INTERVAL_END
2. `00:00:00` — INTERVAL_START: `intervalDidStart()` resets `lastThreshold=0` for all apps but does NOT rebuild thresholds
3. `00:01:xx` — First catch-up event (min=1) arrives after 60s absorb window, records 60s (NEW_DAY branch)
4. `00:02:xx` — Next catch-up (min=2): `timeSinceLastForApp=60s > 55s` → passes SKIP_COOLDOWN, records +60s
5. ... continues for each minute of yesterday's residual (14 events = 14 min phantom)
6. `06:47:49` — Extension killed/relaunched: remaining catch-up events arrive as burst, all blocked by SKIP_COOLDOWN (8s < 55s). Burst consumes all registered thresholds → monitoring dies.
7. `07:21:38` — EXTENSION_GAP detected (29m since last heartbeat). Monitoring restart rebuilds sliding window — but ext_usage already includes phantom 14 min.

**Evidence from logs:**

| App | currentToday | lastThresh | Real usage | Issue |
|-----|-------------|-----------|------------|-------|
| 9360F490 | 2160s (36m) | 2160s | 22 min | +14m overcounting (yesterday's residual) |
| 0D9A6364 | 60s (1m) | 600s | unknown | Stuck at 1m — monitoring died after flood |
| E54A4160 | 60s (1m) | 1680s | unknown | Stuck at 1m — monitoring died after flood |
| 7F4AF4BB | 60s (1m) | 1980s | unknown | Stuck at 1m — monitoring died after flood |
| 7FC96A01 | 60s (1m) | 2760s | unknown | Stuck at 1m — monitoring died after flood |

Key signature: `currentToday == lastThresh` for 9360F490 means events fired sequentially from min=1 (first event was min=1, so each event adds 60s and both counters stay equal). Other apps show `currentToday=60s` with high `lastThresh` — only 1 event recorded before monitoring died.

**Self-correction observed:** Continued usage throughout the day caused the sliding window to eventually align with iOS cumulative. By end of day, both the main app and iOS Screen Time showed the same usage (60 min). The overcounting from midnight catch-ups was absorbed into real usage as the sliding window caught up.

**Fix implemented (Feb 20):** SKIP_MIDNIGHT filter + catchup_max capture revival. Addresses both overcounting AND undercounting:

1. **SKIP_MIDNIGHT filter (Filter 0):** `intervalDidStart()` detects midnight (day changed via `midnight_diagnostic_date`), sets `midnight_pending_refresh` flag + timestamp, clears stale `catchup_max` for all apps. New filter in `setUsageToThreshold()` blocks ALL events while flag is set (2-hour safety timeout). Prevents stale catch-ups from recording phantom usage.

2. **catchup_max capture revived in SKIP_RESTART:** Safe because SKIP_MIDNIGHT blocks stale data upstream. Only legitimate post-`scheduleActivity()` catch-ups reach SKIP_RESTART. Captures highest threshold per app during 60s absorb window.

3. **NEW_DAY branch applies catchup_max:** Reads `catchup_max` before `resetAllDailyCounters` clears it. Initializes usage to `catchup_max + 60` instead of hardcoded 60. Recovers usage between midnight and first app foreground.

4. **`checkMonitoringHealth()` detects midnight flag:** Forces `restartMonitoring()` when `midnight_pending_refresh` is set, even when monitoring appears alive (stale thresholds).

5. **`scheduleActivity()` clears flag:** After registering fresh thresholds, clears `midnight_pending_refresh` so events resume normally.

**Event flow after fix:**
```
MIDNIGHT     intervalDidStart() → day changed → set midnight_pending_refresh
             ← All events BLOCKED by SKIP_MIDNIGHT →
07:00        User opens app → checkMonitoringHealth() detects flag → restartMonitoring()
             → scheduleActivity() clears flag, registers thresholds 1-60
07:00:01     iOS catch-up burst: min.1-25 → SKIP_RESTART captures catchup_max = 1500s
07:01:01     First real event: min.26 → NEW_DAY: catchup_max(1500) + 60 = 1560s → 26 min ✓
```

**Trade-off:** No usage tracking between midnight and first app foreground. Acceptable for a parental controls app (child likely sleeping; undercount is safer than overcount). catchup_max capture in SKIP_RESTART recovers pre-foreground usage.

### Midnight Diagnostic Log (Feb 19, 2026)

**Status:** Active. Captures midnight→scheduleActivity window for ongoing diagnostics.

**Observed (Feb 19):** YouTube (learning app) used for 35 min, recorded 57 min (+22 min phantom). Non-used learning apps each got 1 min. Same pattern as Feb 18 — first usage of the day is inflated, other apps get phantom 1 min.

**Problem:** The regular debug log (50KB/200 lines) gets overwritten by later events throughout the day, losing the critical midnight window data needed to trace the root cause.

**Solution:** Added a dedicated `midnight_diagnostic_log` (separate UserDefaults key, 15KB/75 lines) that:
1. **Activates at midnight** — `intervalDidStart()` sets `midnight_diagnostic_active = true`, clears previous log, dumps full state of ALL tracked apps (ext_usage_today, ext_usage_date, lastThreshold, usage_today)
2. **Records every event** between midnight and first `scheduleActivity()` — every filter decision (SKIP_RESTART, SKIP_COOLDOWN, SKIP_REGRESSION, etc.) and every recording (NEW_DAY, INCREMENT) with complete context values
3. **Captures `scheduleActivity()` state** — what ext_usage values it reads per app, what sliding window thresholds it registers
4. **Deactivates when `scheduleActivity()` runs** — sets `midnight_diagnostic_active = false`
5. **Never overwritten** by regular debug log trimming (separate key, immune to daily activity)

**Files modified:**

| File | Change |
|------|--------|
| `DeviceActivityMonitorExtension.swift` | `midnightDiagnosticLog()` function, activation in `intervalDidStart()`, 6 instrumentation points in `setUsageToThreshold()` filter chain |
| `ScreenTimeService.swift` | `midnightDiagnosticLog()` helper, instrumentation in `scheduleActivity()` reads/registration, flag deactivation |
| `MidnightDiagnosticLogView.swift` | New log viewer UI (Settings > Diagnostics > Midnight Diagnostic) |
| `SettingsTabView.swift` | Navigation row for midnight diagnostic viewer |

**UserDefaults keys added:**

| Key | Type | Purpose |
|-----|------|---------|
| `midnight_diagnostic_active` | Bool | Flag: true from midnight until first `scheduleActivity()` |
| `midnight_diagnostic_log` | String | The diagnostic log content (15KB max / 75 lines) |

**Performance:** Zero overhead when inactive — single `Bool` read per event in `setUsageToThreshold()`. When active (midnight window only), ~50 log entries at 100-200 bytes each.

**UserDefaults keys added (update):**

| Key | Type | Purpose |
|-----|------|---------|
| `midnight_diagnostic_date` | String ("yyyy-MM-dd") | Tracks which day the diagnostic was last activated — prevents restart-triggered `intervalDidStart()` from overwriting midnight data |

**Bug fix (Feb 20):** `intervalDidStart()` fires on every `startMonitoring()` call, not just midnight. The original code unconditionally cleared the diagnostic log, so any dev bypass or foreground restart wiped the real midnight data. Fixed by checking `midnight_diagnostic_date` — only clear/activate when the day has changed. Non-midnight `intervalDidStart()` calls now append `RESTART_INTERVAL_START` entries instead of clearing.

**Diagnostic results (Feb 20):**

The midnight diagnostic was overwritten by a dev bypass restart at 06:43 (before the bug fix above). However, the extension log + monitoring log provided sufficient data for analysis:

**Timeline:**
- **00:00:02** — Midnight `intervalDidStart()`. Zero thresholds remain (all consumed during Feb 19).
- **05:56-06:20** — User uses YouTube (9360F490) for 25 min. iOS tracks it internally, but extension has zero thresholds → zero events → zero recorded.
- **06:43:37** — User opens app. `MONITORING_ALIVE` (schedule registered, but zero thresholds).
- **06:43:45** — Dev bypass triggers `restartMonitoring()`. `scheduleActivity()` reads ext_usage_date=2026-02-19 → defaults to 0 min → registers thresholds 1-60.
- **06:43:50** — iOS fires catch-up burst: min.1-25 for YouTube (25 events). **Exactly 25 min = the actual iOS-tracked usage.** All blocked by SKIP_RESTART (4s < 60s).
- **06:45-06:55** — 3 more dev bypass restarts, same pattern. Each fires 25 catch-ups for YouTube, all blocked.
- **Result**: ext_usage stays at 0. The 25 min of real usage is lost.

**Root cause: Threshold exhaustion during Feb 19.**
YouTube real usage on Feb 19 was 111 min (not 78 min as ext_usage showed). The last 33 min session (4-5 PM) went unrecorded — thresholds exhausted at the 78 min mark, and the user didn't open the app again before midnight. At midnight, zero thresholds remained. No new thresholds are registered until the user opens the app (extension can't call `scheduleActivity()`). Any usage between midnight and first app foreground is untracked.

**Key finding: Restart catch-ups = accurate iOS ground truth.**
The 25 catch-up events at 06:43 for min.1-25 exactly match the user's actual 25 min of YouTube usage. iOS's cumulative for today is correct — the restart catch-ups represent real today usage, NOT yesterday's stale residual. SKIP_RESTART blocks them, losing accurate data.

**Variance across days:**

| Day | Thresholds at midnight | Midnight behavior | Morning behavior | Symptom |
|-----|----------------------|-------------------|------------------|---------|
| Feb 18 | Some survived | Catch-ups fire ~60s apart, pass cooldown | Already inflated | +14 min overcounting |
| Feb 19 | Some survived | Catch-ups fire ~60s apart, pass cooldown | Already inflated | +22 min overcounting |
| Feb 19 (daytime) | Exhausted at ~78 min | N/A | N/A | -33 min undercounting (4-5 PM session lost) |
| Feb 20 | Zero survived (exhausted during Feb 19) | No catch-ups (nothing to fire) | Restart catch-ups = real usage, blocked by SKIP_RESTART | 0 min undercounting (25 min lost) |

**Daytime threshold exhaustion (new finding):** With 60 thresholds per app, heavy usage (>60 min since last `scheduleActivity()`) exhausts all thresholds mid-day, silently killing monitoring for that app. The extension cannot call `scheduleActivity()` — only the main app can. **Fixed Mar 1 — see "Daytime Threshold Exhaustion Fix" section below.**

### catchup_max Removal — v5 (Feb 23, 2026)

**Status:** Reverted by v6 (see below).

**Motivation:** iOS was believed to fire catch-ups for ALL registered thresholds regardless of actual per-app usage. Capturing them in SKIP_RESTART caused `catchup_max` = 3600s (60 thresholds × 60s) for unused apps, then `intervalDidStart()` applied these as corrections, inflating every app by +60 min.

**What it did:** Removed all `catchup_max` capture and correction paths. SKIP_RESTART dropped events entirely with no data recovery.

**Side effect:** Pre-foreground usage permanently lost. If child uses learning app before parent opens main app, the catch-ups representing real iOS cumulative are dropped and never recovered. Usage shows 0 min until child uses the app again (triggering NEW_DAY with correct `thresholdSeconds`). If child already stopped, 0 min forever.

### catchup_max Restoration — v6 (Feb 25, 2026)

**Status:** Superseded by surgical revert to Feb 23 state (see below).

**Observed (Feb 25):** Learning app used for 24 min between 06:00-07:00. App opened at 07:48. Usage showed 0 minutes. The 24 min of real usage was permanently lost because:

1. **00:00:33** — Midnight `intervalDidStart()`: SKIP_MIDNIGHT set, stale thresholds from yesterday (9360F490 range 114-173).
2. **06:00-07:00** — Child uses learning app. iOS tracks 24 min cumulative internally. SKIP_MIDNIGHT blocks all events. Stale thresholds can't even fire for minutes 1-24 (range starts at 114).
3. **07:48:52** — Parent opens app. `checkMonitoringHealth()` detects `midnight_pending_refresh` → restart. `scheduleActivity()` reads ext_usage (all dates = Feb 24) → defaults to 0 min → registers thresholds 1-60.
4. **07:48:52** — iOS fires catch-up burst (thresholds 1-24 for 24 min real cumulative). SKIP_RESTART drops them all — **no catchup_max capture** (removed in v5).
5. **07:48:58** — Dev bypass fires another restart 6s later. Same catch-ups, same drop.
6. **Result:** 0 min recorded. Child stopped using app at 07:00, no future events will fire.

**Key evidence contradicting v5 rationale:** Feb 20 diagnostic showed YouTube with 25 min real usage getting exactly 25 catch-up events (thresholds 1-25), NOT all 60 registered thresholds. The earlier "ALL thresholds for unused apps" observation likely came from pre-SKIP_MIDNIGHT stale cross-midnight catch-ups, which are now blocked.

**Fix:** Re-enable catchup_max capture in SKIP_RESTART + main app recovery path.

**Changes:**

| File | Change |
|------|--------|
| `DeviceActivityMonitorExtension.swift` | SKIP_RESTART: capture `catchup_max_{appID}` (highest threshold per app during 60s absorb window) |
| `DeviceActivityMonitorExtension.swift` | `intervalDidStart()` midnight block: clear stale `catchup_max` for all tracked apps (NOT cleared on same-day restarts) |
| `ScreenTimeService.swift` | `readExtensionUsageData(defaults:)`: if `catchup_max > ext_usage_today`, set ext_usage and usage_today to catchup_max. Clear catchup_max after applying. |
| `ScreenTimeService.swift` | `scheduleActivity()`: clear catchup_max for all apps before `startMonitoring()` (stale values don't persist; fresh catch-ups repopulate) |

**Recovery flow:**

```
MIDNIGHT     intervalDidStart() → day changed → clear catchup_max → set midnight_pending
             ← All events BLOCKED by SKIP_MIDNIGHT →
06:00-07:00  Child uses learning app for 24 min. iOS tracks cumulative. Extension blocked.
07:48        Parent opens app → checkMonitoringHealth() detects midnight flag → restartMonitoring()
             → scheduleActivity() clears catchup_max, registers thresholds 1-60, sets restart_timestamp
07:48:00.5   iOS catch-up burst: thresholds 1-24 → SKIP_RESTART captures catchup_max = 1440s
07:48:30     readExtensionUsageData() runs (foreground sync) → catchup_max=1440 > ext_usage=0
             → sets ext_usage=1440s, usage_today=1440s → clears catchup_max
             → UI shows 24 min ✓
```

**Why SKIP_RESTART capture is now safe:**

1. **SKIP_MIDNIGHT** blocks stale cross-midnight catch-ups before they reach SKIP_RESTART
2. **`scheduleActivity()` clears** catchup_max before each restart cycle — no stale persistence
3. **`intervalDidStart()` midnight clears** catchup_max — yesterday's values don't carry over
4. **SKIP_COOLDOWN does NOT capture** catchup_max — late bursts can carry stale data. However, events with `threshold > lastThreshold` now bypass SKIP_COOLDOWN (Feb 28 batch fix) and record as normal incremental usage


**Correction paths (3 active + 1 day-boundary):**

| Path | Location | When |
|------|----------|------|
| `intervalDidStart()` same-day | Extension | On every `startMonitoring()` — iterates tracked apps, applies catchup_max if same day |
| `setUsageToThreshold()` before-recording | Extension | Before recording each event — applies catchup_max if same day, updates lastThreshold |
| `readExtensionUsageData()` | Main app ScreenTimeService | On foreground sync — **most reliable path**, works even when no events fire |
| NEW_DAY branch | Extension `setUsageToThreshold()` | Day rollover — uses `catchup_max + 60` for initial usage |

All 3 same-day paths: skip shielded reward apps, apply UP-only correction (`catchup_max > currentToday`), clear catchup_max after use.

### Surgical Revert to Feb 23 State (Feb 25, 2026)

**Status:** Active. This is the current code state.

**Commit:** `2057d5e`

**What happened:** v6 was implemented and committed (`d50284c`), but then the decision was made to surgically revert the two tracking files back to their Feb 23 state (commit `bc50646`). Only the tracking code was reverted:
- `DeviceActivityMonitorExtension.swift` — reverted to Feb 23
- `ScreenTimeService.swift` — reverted to Feb 23

App Store compliance changes (account deletion, icons, Info.plist, archive validation) were **preserved** — not reverted.

**Rationale:** The v5 removal (Feb 24, commit `901cae4`) caused first-usage-of-the-day to show 0 minutes. Rather than layering more fixes on top of v5/v6, the decision was to restore the known-working Feb 23 code (which had minor undercounting but never 0-count) and investigate the undercounting issue from a stable baseline.

**Current active correction system (Feb 20 era, 3 paths):**

| Path | Location | When | Behavior |
|------|----------|------|----------|
| `intervalDidStart()` same-day | Extension | After every restart (same day) | If catchup_max > currentToday, applies correction. Always removes catchup_max after. |
| `setUsageToThreshold()` same-day | Extension | Before recording each event | If catchup_max > currentToday, applies correction before threshold delta calculation. |
| `readExtensionUsageData()` | Main app ScreenTimeService | On every foreground sync | "4th correction path" — if catchup_max > ext_usage, applies UP-only correction. Does NOT remove catchup_max (extension manages lifecycle). |

**NEW_DAY formula:** `catchup_max + 60` (catchup_max provides the base from SKIP_RESTART capture, +60 for the current event that triggered NEW_DAY).

**Key finding (previously undocumented):** Usage IS tracked before the main app opens. The extension's `intervalDidStart()` same-day correction and NEW_DAY `catchup_max + 60` formula allow pre-foreground usage to be recovered without requiring the main app. This was confirmed by Feb 23 device testing — the child used the learning app before the parent opened the main app, and usage was recorded (with minor undercounting).

**Note (Feb 26):** The Feb 23 test was a same-day test (post-CATCHUP_FIX_V5 reset at 21:54) that did not span a midnight boundary. Feb 26 testing showed that pre-foreground tracking does NOT work across midnight — see "Midnight Monitoring Gap" section below. Further investigation needed to reconcile these observations.

**Known issue:** Minor undercounting (~5-10 min) on first usage of the day. This is the original issue that prompted the v5 attempt. Root cause investigation pending from this stable baseline.

**scheduleActivity() behavior:** Does NOT clear catchup_max before `startMonitoring()`. Relies on the extension's capture/correction lifecycle.

**Migration flags in code:** v1 through v4 only. No v5 migration exists in this code state.

### Midnight Monitoring Gap (Feb 26, 2026)

**Status:** **FIXED** (Feb 27, 2026). Device-confirmed. BGTask + `restartMonitoring()` at ~00:01 eliminates the gap.

**Observed:** Zero usage recorded between midnight and first main app launch on Feb 26. Child's usage between 00:00 and 07:48 was lost entirely.

**Timeline (Feb 25→26):**

```
Feb 25, 22:49:12 — Last scheduleActivity() before midnight
  9360F490: 84 min, thresholds 85-144
  EFF1E31D: 71 min, thresholds 72-131
  E54A4160:  5 min, thresholds  6-65
  Others: 0 min, thresholds 1-60

Feb 26, 00:00:08 — Midnight
  intervalDidStart() fires, detects day change
  → midnight_pending_refresh = true (SKIP_MIDNIGHT activated)
  → catchup_max cleared for all 7 apps
  → lastThreshold reset for all apps
  ⚠ scheduleActivity() does NOT run — extension cannot call it

Feb 26, 00:00:08 → 07:48:32 — 7h 48m DEAD ZONE
  SKIP_MIDNIGHT blocks ALL events
  Yesterday's thresholds useless for today (e.g., range 85-144 won't fire for 0 cumulative)

Feb 26, 07:18:53 — First app open (Bug #1)
  Init: MONITORING_ALIVE — OS confirms active, skips restart
  checkMonitoringHealth() did NOT run (scenePhase .active likely not reached)
  midnight_pending_refresh NOT detected

Feb 26, 07:48:32 — Second app open (30 min later)
  checkMonitoringHealth() detects midnight_pending_refresh → restartMonitoring()
  scheduleActivity() registers fresh thresholds 1-60 for all apps
  SKIP_MIDNIGHT cleared → monitoring resumes
```

**Three independent reasons monitoring is dead after midnight:**

| Reason | Cause | Alone sufficient? |
|--------|-------|-------------------|
| **Stale thresholds** | Yesterday's ranges (e.g., 85-144) don't cover today's cumulative (starts at 0) | Yes — for high-usage apps |
| **SKIP_MIDNIGHT** | Blocks ALL events until `scheduleActivity()` runs | Yes — for ALL apps, even those with aligned thresholds |
| **No rebuild mechanism** | Extension cannot call `DeviceActivityCenter.startMonitoring()` — iOS restricts this to main app process | Yes — root architectural cause |

**iOS architectural constraint:** `DeviceActivityCenter.startMonitoring()` is available to extensions at the API level, but extension-initiated calls were observed to cause iOS to immediately fire all thresholds as catch-ups, consuming them before real events can fire. This makes extension-side threshold rebuilding unreliable. Only the main app can safely rebuild thresholds.

**Contributing Bug #1 — checkMonitoringHealth() miss at init:**

`loadPersistedAssignments()` (ScreenTimeService.swift) checks `activities.contains(activityName)`, sets `isMonitoring = true`, and logs MONITORING_ALIVE — but does NOT check `midnight_pending_refresh`. The scenePhase `.active` handler calls `checkMonitoringHealth()` which does check, but at 07:18:53 the app was likely opened briefly and closed before `.active` fired. Result: 30-minute delay until second app open at 07:48:32.

**Contributing Bug #2 — Midnight BGTask doesn't rebuild thresholds:**

`handleMidnightResetTask()` (ChildBackgroundSyncService.swift) is a `BGAppRefreshTask` scheduled for 00:01. It resets daily persistence counters but does NOT call `scheduleActivity()` or `restartMonitoring()`. Even when iOS runs this task at midnight, thresholds are not rebuilt.

**Impact:** For a parental controls app, any child usage between midnight and parent opening the main app is lost. This is the primary UX issue — the app is designed to run in the background without requiring manual launches.

**Potential fix approaches:**

| Approach | How | Reliability | Risk |
|----------|-----|-------------|------|
| **1. BGTask + scheduleActivity()** | Add `restartMonitoring()` to existing midnight BGTask | Medium (iOS timing not guaranteed) | Low |
| 2. Extension calls startMonitoring() | Extension rebuilds thresholds at midnight | Unknown (needs device testing) | High (untested iOS behavior) |
| 3. Eliminate SKIP_MIDNIGHT | Smart stale-event detection instead of blanket block | Low (can't distinguish stale from real) | Very high (phantom usage returns) |
| 4. Fixed thresholds 1-60 | Always register from minute 1, accept daytime catch-up cost | High at midnight, bad daytime | Medium (floods return on restart) |
| 5. Reduced granularity (5-min) | 12 thresholds/app × 7 = 84, survives midnight | High | Lose per-minute tracking |

**Implementing Approach 1** as lowest-risk first step. BGAppRefreshTask typically runs within 15-30 minutes of scheduled time on devices connected to power (common overnight for children's devices). Not guaranteed, but significantly reduces the gap.

#### Approach 1 Implementation: BGTask Safety Analysis

**Placement:** `restartMonitoring()` is called inside `handleMidnightResetTask()` (ChildBackgroundSyncService.swift). Execution order:

```
1. Counter reset (synchronous, instant)         ← always completes first
2. Task {
3.   await restartMonitoring(...)                ← async, up to ~5s worst case
4.   scheduleMidnightReset()                     ← schedule next run
5.   task.setTaskCompleted(success: true)
6. }
```

**iOS time budget:** `BGAppRefreshTask` gets ~30 seconds. `restartMonitoring()` worst case (3 failed retries with 1s+2s exponential backoff) takes ~5 seconds total. Well within the limit.

**Expiration scenario:** If iOS kills the task before `restartMonitoring` completes, the expiration handler fires and logs `MIDNIGHT_RESET — EXPIRED`. In this case:
- Counters are already reset (ran synchronously before the async Task)
- Thresholds are NOT rebuilt (same state as before the fix — user opens app to trigger rebuild)
- Not a regression — just means the fix didn't help for that night

**No interference with extension's midnight `intervalDidStart()`:**
1. Extension's `intervalDidStart()` fires at midnight (00:00) and sets `midnight_pending_refresh = true`. The BGTask fires later (~00:01+). `restartMonitoring()` calls `scheduleActivity()` which clears `midnight_pending_refresh`. These are sequential, not concurrent.
2. `restartMonitoring()` calls stop+start, which triggers a new `intervalDidStart()` on the extension. But the extension checks `lastDiagDate == todayStr` — since midnight already set `midnight_diagnostic_date` to today, this second `intervalDidStart` takes the **same-day path** and does NOT re-set `midnight_pending_refresh`. Safe.

**No collision with other BGTasks:** Usage-upload runs every 30 min, config-check every 24h, subscription-verify every 24h. None are scheduled for midnight specifically.

**Diagnostic logging:** `bgtask_log` (UserDefaults, app group shared) captures the full lifecycle. Viewable in Settings > Diagnostics > BGTask Log. The `EXPIRED` vs `completed successfully` distinction tells us definitively whether iOS gave the task enough time.

#### Device Confirmation (Feb 27, 2026)

**Result:** Full success. Pre-foreground usage tracking across midnight confirmed working for the first time.

**BGTask log:**

```
[2026-02-27 00:01:25] REGISTER — all background tasks registered
[2026-02-27 00:01:25] MIDNIGHT_SCHEDULE — next reset scheduled for Feb 28, 2026 at 00:01
[2026-02-27 00:01:26] MIDNIGHT_RESET — task started
[2026-02-27 00:01:26] MIDNIGHT_RESET — counters reset
[2026-02-27 00:01:26] MIDNIGHT_RESET — calling restartMonitoring...
[2026-02-27 00:01:28] MIDNIGHT_RESET — restartMonitoring completed, scheduling next
[2026-02-27 00:01:28] MIDNIGHT_RESET — task completed successfully
```

iOS launched the BGTask 86 seconds after midnight. `restartMonitoring()` completed in 2 seconds. Fresh thresholds 1-60 registered for all apps, SKIP_MIDNIGHT cleared.

**Extension log (pre-foreground tracking):**

| App | First event | Usage at 06:45 (app open) | Notes |
|-----|-------------|---------------------------|-------|
| 7FC96A01 | ~05:48 (min=26 at 06:14) | 27 min (1620s) | Tracked ~1 hour before app open |
| 9360F490 | 06:40 (min=1) | 18 min (1080s) | Clean start, no catch-up issues |

**Key observations:**
- **Zero phantom usage** — no overcounting, no stale catch-ups
- **No SKIP_MIDNIGHT blocks** — confirms `scheduleActivity()` cleared the flag at 00:01:28
- **SKIP_COOLDOWN recoveries working** — min 2→3 gets +120s, min 11→12 gets +120s, min 15→16 gets +120s (correctly recovers dropped events)
- **Main app opened at 06:45:50** — nearly 7 hours after BGTask, all usage already tracked
- **Extension process changes visible** (session IDs: 01572ECB → B026FE6E → 39AA52D2 → 4484EDEE) — iOS killed/relaunched extension multiple times, tracking survived each time

**Comparison with pre-fix (Feb 26):**

| Metric | Feb 26 (no BGTask fix) | Feb 27 (with BGTask fix) |
|--------|----------------------|------------------------|
| Dead zone | 00:00 → 07:48 (7h 48m) | 00:00 → 00:01 (86s) |
| Pre-foreground usage | 0 min (lost) | 27 min (7FC96A01) + 18 min (9360F490) |
| Required user action | Open app to trigger rebuild | None — automatic |

### catchup_max Inflation Bug — ALL Apps (Feb 27, 2026)

**Status:** FIXED (two-layer defense)

**Problem:** After multiple rapid dev bypass restarts at 07:44:25/39/41, ALL 7 monitored apps' usage inflated from 47 min total to 453 min total within ~1 hour. Both shielded reward apps (7F4AF4BB: 0→60, 9621D5D3: 0→57) AND learning apps (EFF1E31D: 0→60, E54A4160: 2→62, 9360F490: 18→85) got phantom usage.

**Root Cause (confirmed by Feb 27 extension debug log):** `catchup_max` captures iOS's **full cumulative day thresholds** during SKIP_RESTART, not just the 1-2 minutes of real usage missed during the 60s absorb window. Example: app with 18 min real usage → iOS fires catch-up threshold min=72 → `catchup_max=4320s`. When correction paths apply this, usage jumps 18→72 min. For 0-usage apps, `catchup_max=3600s` (60 min) is pure phantom.

The inflation timeline from the extension log:
1. **07:44:45** — SKIP_RESTART blocks catch-up burst, captures catchup_max per app (3420-4320s range)
2. **08:31:43** — Path 2 (`setUsageToThreshold`) fires: `CATCHUP_CORRECTION 9360F490... 1080s → 4320s (+3240s)`
3. **08:46:30** — Path 1 (`intervalDidStart`) fires for ALL remaining apps. GOAL_CHECK confirms: EFF1E31D=60min, 7FC96A01=70min, E54A4160=62min — exactly matching their catchup_max values

**Fix Layer 1 — Shield checks (Reward apps):**
1. `isShieldedRewardApp()` helper — check category + shield status
2. SKIP_RESTART shield check — skip catchup_max capture for shielded apps (`SKIP_RESTART_SHIELDED`)
3. `intervalDidStart()` correction shield check — skip + clear for shielded apps (`CATCHUP_SKIP_SHIELDED`)
4. `readExtensionUsageData()` Reward skip — main app skips catchup_max for Reward category (`CATCHUP_SKIP_REWARD`)

**Fix Layer 2 — scheduleActivity() clears catchup_max (ALL apps):**
5. `scheduleActivity()` clears catchup_max for ALL apps before `startMonitoring()` — prevents stale accumulation across restarts. Fresh catchup_max from each restart reflects real iOS cumulative.
6. `catchup_fix_v5` — one-time data cleanup on-device
7. All 3 correction paths apply catchup_max if `catchup_max > currentToday` — no artificial cap (removed Feb 28).

**Why no cap:** The conditional 180s cap (tried Feb 27-28) was harmful — when thresholds exhaust mid-day (app uses >60 min since last `scheduleActivity()`), catchup_max correctly captures the full gap (e.g., 39 min for 7FC96A01 on Feb 28). A cap at `currentToday + 180s` would discard this real data. With step 5 ensuring fresh values per restart, the primary inflation vector (stale accumulation) is already eliminated.

### SKIP_COOLDOWN Batch Event Fix (Feb 28, 2026)

**Status:** FIXED

**Problem:** iOS fires deferred threshold events in rapid batches (timeSinceLastForApp=0s) when the extension was killed and re-instantiated. SKIP_COOLDOWN (Filter 2) blocked ALL events in a batch because they arrived within 55s of each other, even when the threshold represented new usage above lastThreshold. Example: E54A4160 at 13:51:14 — thresholds min=24-40 all dropped, losing 17 minutes of real usage.

**Fix:** Added `thresholdSeconds <= lastThreshold` condition to SKIP_COOLDOWN. Events with `threshold > lastThreshold` bypass the cooldown and proceed to normal processing (Filter 5 handles ordering, delta calculation handles amounts). In a batch, only "new high" thresholds pass through, recording correct incremental deltas.

**Deployment note:** The fix was committed to the working tree on Feb 28 but was NOT present in the build tested that day (confirmed by log format: old code produced `threshold=Xs (dropped)`, new code produces `threshold=Xs <= lastThresh=Xs (dropped)`). Mar 1 logs show sequential events at 12:52–12:58 for 7FC96A01 (min=54→60, ~1 min apart, no SKIP_COOLDOWN drops) confirming the fix is working correctly in the deployed build.

---

### Daytime Threshold Exhaustion Fix (Mar 1, 2026)

**Status:** FIXED

**Problem:** When an app's usage exceeded 60 min since the last `scheduleActivity()` call, all 60 registered thresholds were consumed. iOS continued firing threshold events (e.g., min=61, 62, …) but they had no registered handler — the extension logged `NO_MAPPING` and discarded each one. Monitoring silently died for that app until the next restart (`scheduleActivity()` re-advances the window). The only recovery was `catchup_max` capturing the gap during the next SKIP_RESTART absorb window, then correcting on restart — but this required either the main app opening (foreground) or a BGTask restart.

**Mar 1 investigation — 7FC96A01 exhaustion timeline:**

| Time | Event | ext_usage |
|------|-------|-----------|
| 12:52–12:58 | min=54→60 fire sequentially (~60s apart, SKIP_COOLDOWN fix working) | 54→60 min |
| 12:58:02 | min=60 recorded — top of window reached | 60 min |
| 12:59:00 | min=61 fires → **NO_MAPPING** (threshold 61 not registered) | 60 min (stuck) |
| 13:00–13:13 | min=62–71 each fire → NO_MAPPING, one per minute | 60 min (stuck) |
| 13:16:23 | Restart triggered. SLIDING_WINDOW_READ: 60 min → registers 61–120 | — |
| 13:16:23 | SKIP_RESTART captures catchup_max=4260s (71 min) for 7FC96A01 | — |
| 13:16:52 | CATCHUP_CORRECTION applied: 60 min → 71 min | 71 min |

11 minutes of usage were lost to NO_MAPPING and recovered only via catchup_max at restart. This confirmed the user's observation: "usage tracked continuously until min=60, then flat for ~18 min, then jumps to 71 at app open."

**Root cause summary:** `scheduleActivity()` is the only way to register new thresholds (the extension cannot call it). Before this fix, it only ran at: (1) midnight BGTask, (2) user opens app, (3) `checkMonitoringHealth()` on app foreground. A child using an app for >60 min between any of these events would exhaust the window.

**Fix:** Added `com.screentimerewards.monitoring-refresh` BGAppRefreshTask in `ChildBackgroundSyncService` (`registerBackgroundTasks()`, `handleMonitoringRefreshTask()`, `scheduleMonitoringRefresh()`). The task:
- Fires every 45 min (15 min headroom before the 60-threshold window exhausts)
- Calls `restartMonitoring(reason: "intraday-refresh")` → `scheduleActivity()` re-reads `ext_usage` and advances the sliding window to `[currentMin+1, currentMin+60]`
- No network required (BGAppRefreshTask, not BGProcessingTask)
- Self-rescheduling: each completion schedules the next +45 min invocation
- Registered in `BGTaskSchedulerPermittedIdentifiers` in Info.plist

**Worst-case gap:** If iOS delays the task to 90 min (2× requested interval), an app would need >60 min of continuous usage since the last refresh to exhaust the window — rare in practice. Even if exhaustion occurs, `catchup_max` still recovers the gap on the next restart.

**Diagnostics:** `bgtask_log` entries: `MONITORING_REFRESH — task started`, `MONITORING_REFRESH — restartMonitoring completed`, `MONITORING_REFRESH — task completed successfully`. Last-run timestamp stored in `monitoring_refresh_last_run` (shared UserDefaults), displayed in Settings → Diagnostics → "Monitoring Refresh Log" row with subtitle "Last run: X min ago".

---

### Monitoring Refresh Chain Seeding Gap (Mar 2, 2026)

**Status:** FIXED

**Problem:** `scheduleMonitoringRefresh()` is only called from two places:
1. `registerBackgroundTasks()` — runs on every cold app launch (seeds the chain)
2. `handleMonitoringRefreshTask()` — runs after each successful refresh (self-chains)

If the app is never cold-launched on a given day, the chain is never seeded and monitoring refresh never runs. This was observed on 2026-03-02: the midnight BGTask ran at 00:40 (confirmed in `bgtask_log`) and rebuilt the sliding window, but `handleMidnightResetTask()` did not call `scheduleMonitoringRefresh()`. The monitoring refresh log was empty all day until the app was manually opened at 12:50 PM.

**Why monitoring worked anyway on Mar 2:** The midnight reset at 00:40 called `restartMonitoring()` which registered thresholds starting above current usage. App usage that morning was low enough (EFF1E31D was at min=38 by 12:38 PM) that the 60-threshold window from the midnight restart still had headroom. Threshold exhaustion never occurred. This was luck, not design — on a day of heavier usage the gap would have caused NO_MAPPING events.

**Fix:** Add `scheduleMonitoringRefresh()` call inside `handleMidnightResetTask()`, after `scheduleMidnightReset()`. The midnight reset task is proven to run reliably every night without requiring an app launch. Piggybacking the monitoring refresh seed on it ensures the chain is started at the beginning of every day regardless of app launch behavior.

**Change in `ChildBackgroundSyncService.swift` — `handleMidnightResetTask()` Task block:**

```swift
self.scheduleMidnightReset()
self.scheduleMonitoringRefresh()   // re-seed chain for new day
self.bgtaskLog("MIDNIGHT_RESET — monitoring refresh seeded")
self.bgtaskLog("MIDNIGHT_RESET — task completed successfully")
task.setTaskCompleted(success: true)
```

**Why this is safe:**
- `BGTaskScheduler.shared.submit()` is idempotent — if the chain is already running (app was also opened), the new request simply replaces the pending earliestBeginDate with `now + 45 min`. No duplicate runs.
- The midnight reset's own chain is unaffected.
- Expected bgtask_log evidence after fix: `MIDNIGHT_RESET — monitoring refresh seeded` followed by `MONITORING_REFRESH — task started` entries appearing ~45–90 min later, without any app launch.

---

### SKIP_MIDNIGHT Timeout Expiry — Late App Open (Mar 8, 2026)

**Status:** FIXED

**Problem:** When the midnight BGTask (`com.screentimerewards.midnight-reset`) did not run overnight and the app first opened late (e.g., 04:05am), SKIP_MIDNIGHT's 2-hour safety timeout had already expired. The safety branch fired, cleared `midnight_pending_refresh`, and did NOT block events — allowing yesterday's residual catch-ups to flood through and inflate usage by exactly 60 minutes.

**Root cause chain (confirmed from March 7 device logs):**

1. `intervalDidStart()` sets `midnight_pending_timestamp = 00:00` at midnight
2. SKIP_MIDNIGHT 2-hour timeout = expires at **02:00**
3. BGTask did not run overnight; app first opened at **04:05am** (4h > 2h)
4. SKIP_MIDNIGHT check: `timeSinceMidnight = 4h > 2h` → safety timeout branch fires → clears flag, does **NOT** block events
5. iOS fires yesterday's residual catch-ups (7FC96A01 had 93 min on Mar 6) across rapid restart events
6. SKIP_RESTART absorb window captures `catchup_max = 3600s` (window top for range 1–60)
7. First real threshold fires NEW_DAY branch → reads `catchup_max` **before** `resetAllDailyCounters()` clears it → `initialUsage = 3600 + 60 = 3660s`
8. 35 more thresholds (min=2 through min=36) add 2100s → final: **5760s = 96 min**

Real usage = 36 thresholds × 60s = 36 min. Inflation = exactly **60 min** = one SKIP_RESTART window top.

**Evidence from logs:**

- `MIDNIGHT_PENDING` detected at 04:05:50 (not 00:01 where a successful BGTask fires) — proves BGTask didn't run
- No `MIDNIGHT_RESET` log entry for March 7 overnight
- `currentToday=5340s` before min=29 → back-calculate base: `5340 − (28×60) = 3660s = catchup_max(3600) + 60` — exactly the NEW_DAY formula
- Inflation = 60 min = exactly one SKIP_RESTART absorb window top (catchup_max from 60 registered thresholds)
- Sliding window exhaustion ruled out: that causes undercounting (NO_MAPPING events), not overcounting

**Fix:** Refresh `midnight_pending_timestamp` to `Date().timeIntervalSince1970` in both MIDNIGHT_PENDING detection paths in `ScreenTimeService.swift` before spawning the restart Task. This anchors SKIP_MIDNIGHT's 2-hour window to when the app **actually processes** the midnight restart (e.g., 4am), not when the extension set the flag at midnight.

**Changes in `ScreenTimeService.swift`:**

| Location | Line | Change |
|----------|------|--------|
| Init path (midnight_pending_refresh detection) | ~528 | `sharedDefaults.set(Date().timeIntervalSince1970, forKey: "midnight_pending_timestamp")` added before spawning Task |
| Foreground path (midnight_pending_refresh detection) | ~2102 | Same line added before spawning Task |

**Before/after behavior:**

| Scenario | Before fix | After fix |
|----------|-----------|-----------|
| App opens at 1am | 1h < 2h → blocked ✓ | 0s from now < 2h → blocked ✓ |
| App opens at 4am (bug case) | 4h > 2h → timeout → NOT blocked ✗ | 0s from now < 2h → blocked ✓ |
| App opens at 7am | 7h > 2h → timeout → NOT blocked ✗ | 0s from now < 2h → blocked ✓ |
| BGTask ran at 00:01 | flag cleared before app opens → paths skipped entirely ✓ | same ✓ |

**Safety properties preserved:**

- 2-hour safety timeout unchanged in purpose: if `midnight_pending_refresh` gets permanently stuck (scheduleActivity never runs), recording resumes 2 hours after the **app opened** — not 2 hours after midnight. Strictly better (recording resumes sooner if stuck).
- `scheduleActivity()` still clears `midnight_pending_refresh` immediately after `startMonitoring()` — normal path unaffected.
- No new flags or keys introduced.

**BGTask miss not independently fixable:** `BGAppRefreshTask` execution is never guaranteed by iOS. The MIDNIGHT_PENDING fallback is the correct architectural answer for missed BGTasks. The timestamp refresh fix makes that fallback work correctly for any late open (4am, 7am, etc.).

---

### BGAppRefreshTask Throttling — Complete BGTask Analysis (Mar 15, 2026)

**Status:** DOCUMENTED (fix partially implemented — see below)

**Finding:** `BGAppRefreshTask` for `monitoring-refresh` and `midnight-reset` was submitted 50+ times over 8 days with zero executions, despite `backgroundRefreshStatus=available`. iOS ML-based scheduling completely deprioritized refresh tasks because the child rarely opens the app themselves.

**Evidence from bgtask_log (Mar 7–15):**
- `MONITORING_REFRESH_SCHEDULE` appeared 50+ times; `MONITORING_REFRESH — task started` appeared **zero times**
- `MIDNIGHT_SCHEDULE` entries stopped after Mar 6 (chain broke after one missed night with no cold launch)
- `backgroundRefreshStatus=available` confirmed — not a user settings issue
- `BGProcessingTask` (usage-upload) ran multiple times per day confirming background execution is possible on this device

**Root cause:** iOS uses ML to predict BGAppRefreshTask timing based on app usage patterns. Child devices where the monitoring app is never opened by the child get zero BGAppRefreshTask execution.

**Fix implemented (Mar 15):** Piggybacked monitoring maintenance onto the reliable `BGProcessingTask` (usage-upload) via `performMonitoringMaintenanceIfNeeded()` in `ChildBackgroundSyncService.swift`. Called as first step in `handleUsageUploadTask()`, before subscription guard. Restarts monitoring if:
1. `midnight_pending_refresh` is set (midnight recovery), or
2. `monitoring_restart_timestamp` is >25 min old (intraday refresh)

**Mar 15 confirmation log:**
```
09:00:06  USAGE_UPLOAD — task started
09:00:06  UPLOAD_MONITORING — starting usage-upload intraday refresh (lastRestart=30min ago)
09:00:10  UPLOAD_MONITORING — completed  ← 4s execution time
09:00:10  USAGE_UPLOAD — skipped (subscription expired)  ← maintenance ran before subscription guard ✓
```

**Remaining limitation:** BGProcessingTask (`requiresNetworkConnectivity=true`, no `requiresExternalPower`) is also deferrable by iOS. A 2h 16min gap (09:00–11:16, Mar 15) with no background execution was observed during active daytime use. True background execution (UPLOAD_MONITORING entries without preceding REGISTER) not yet confirmed from device testing.

**Long-term fix needed:** Silent remote push from parent device to child via CloudKit — most reliable on-demand background wake mechanism available in iOS. Parent app's background sync could trigger a silent push to the child device every ~30 min.

---

### Midnight Dark Window — Full BGTask Failure Analysis (Apr 11, 2026)

**Status:** OPEN — root cause of overcounting still unknown (see "Disproven Fix Attempt" section below)

**Problem:** App shows 0 minutes all day, then jumps to 55-69 minutes when user opens app at 18:49. Cross-reference with iOS Screen Time confirmed this IS real overcounting — not delayed recognition. BB131A01 showed 55 min recorded but only 23 min real iOS usage (32 min excess ≈ yesterday's 33 min iOS usage).

**Evidence from April 8-11 device logs:**

**BGTask log:**
```
[2026-04-11 18:49:46] MIDNIGHT_HEALTH — OK (submitted=6 ran=0 lastScheduled=23h ago)
[2026-04-11 18:49:47] MIDNIGHT_RESET — task started (run #1)
[2026-04-11 18:50:02] MIDNIGHT_RESET — EXPIRED (iOS killed before completion)
```
`submitted=6 ran=0` across 4 consecutive days. BGAppRefreshTask never executed at midnight. First execution at 18:49 when user opened the app — 17+ hours late.

**Midnight diagnostic log:**
```
[00:00:00.087] MIDNIGHT_PENDING_SET — blocking events until scheduleActivity for 6 apps
[07:37:59.147] DIAG_MIDNIGHT_TIMEOUT clearing flag after 27479s
[07:37:59.191] DIAG_NEW_DAY appID=E54C1C9E... initial=60s thresh=60s
```
SKIP_MIDNIGHT 2h timeout fired at 07:38 (first event arrived 7.6h after midnight — no events came during the 2h window to trigger earlier clearance). After timeout: E54C1C9E and C6DA269B resumed recording (their stale threshold windows happened to cover today's usage). BB131A01 (stale window 21-80) and E8B1C8C6 (stale window 16-75) remained dark — no thresholds below 16/21 registered, so today's usage from 0 never triggered an event.

**Extension log pattern (Apr 11):**
```
[07:38:01] MIDNIGHT_TIMEOUT — 2hr expired, clearing midnight_pending_refresh
[07:38:02] RECORD appID=E54C1C9E thresh=60s → partial tracking resumes
...18:49... (BGTask finally runs, scheduleActivity registers fresh 1-60)
[18:50:01] RECORD appID=BB131A01 thresh=57min → bulk catch-up, real iOS cumulative
```

**Root cause chain:**
1. Midnight: Extension sets `midnight_pending_refresh=true` ✓
2. BGAppRefreshTask scheduled for 00:01 — **never executes** (iOS ML throttling, child device)
3. BGProcessingTask (usage-upload piggyback) — **also didn't execute overnight** on Apr 11
4. SKIP_MIDNIGHT blocks ALL events for 2h ✓ (correct behavior)
5. No events arrive during 2h window (no usage at 00:00-02:00) — timeout check never runs
6. First event at 07:38 → timeout fires (27479s > 7200s) → flag cleared
7. Apps with stale threshold floors > 0 remain in "dark window" (no thresholds to trigger)
8. Dark window persists until 18:49 when user opens app → `scheduleActivity()` → fresh thresholds → iOS fires all accumulated catch-ups (real data)

**Key insight:** The 2h timeout constant (7200s at line 376 of extension) IS correct. The 27479s in the log is NOT a timeout misconfiguration — it's the elapsed time when the first event HAPPENED to arrive and check the condition. The timeout expired at 02:00 but nobody checked until 07:38.

**SKIP_REGRESSION vs SKIP_RESTART change (feature/streamline-usage-recording):** In March 28 logs (main branch), events after INTERVAL_START were blocked by SKIP_RESTART. In April 11 logs (feature branch), they're blocked by SKIP_REGRESSION. This indicates `monitoring_restart_timestamp` is no longer updated in `intervalDidStart()` — only in `scheduleActivity()`. Impact: absorb window no longer resets on each INTERVAL_START, only on explicit restarts.

---

### Disproven Fix Attempt: Cumulative-Aware Threshold System (Apr 11-12, 2026)

**Initial hypothesis:** iOS `includesPastActivity: true` cumulative persists indefinitely across midnight.

**DISPROVEN by Apr 12 device testing.** iOS cumulative RESETS at midnight. Evidence:
- Registered thresholds 61-120 after midnight (based on yesterday's 60min lastThreshold)
- Child used apps for 32+ minutes — zero events fired
- Thresholds 1-60 registered after revert → iOS immediately fired catch-ups for those 32 minutes
- New app with lastThreshold=0 recorded normally while old apps (lastThreshold=3600s) were blocked

**What was tried (all reverted — branch `feature/midnight-overcounting-fix` for reference):**

1. **Change 1:** Preserved lastThreshold across midnight (removed reset in `intervalDidStart()` and `resetAllDailyCounters()`) → Caused lastThreshold=3600s to persist, blocking ALL new-day events
2. **Change 2:** Changed cross-day filter from `== lastThreshold` to `<= lastThreshold` → Combined with Change 1, blocked every threshold (60s <= 3600s)
3. **Change 3:** Used `max(extToday, lastThreshold)` for window start → Placed thresholds at 61-120 when iOS cumulative was 0, so no events ever fired. **Reverted first.**

**Result:** Zero usage recording for all existing apps. Only new apps (lastThreshold=0) worked.

**Lesson:** `lastThreshold` MUST reset at midnight. iOS cumulative resets, so yesterday's high-water mark is meaningless on a new day.

**Original overcounting root cause — LIKELY IDENTIFIED (Apr 12):** Out-of-order catch-up events after `startMonitoring()`. iOS fires catch-ups non-sequentially — if multiple high-threshold events slip through before SKIP_REGRESSION blocks them, usage gets inflated. The same mechanism causes undercounting when the highest event arrives first and blocks all lower ones. See "Out-of-Order Catch-Up Events" section below.

---

### scheduleActivity() Dependency — UX Problem & Solution Options (Apr 12, 2026)

**Core problem:** `scheduleActivity()` (main app) is the ONLY way to register fresh thresholds. After midnight, yesterday's stale thresholds (e.g., window 61-120) don't cover today's usage (iOS cumulative resets to 0). If the child opens a learning app without opening the main app first, usage goes untracked — potentially for hours. This is a frustrating UX for parents: the child "wastes" learning time that doesn't count toward rewards.

**Why existing mitigations fail:**
| Mechanism | Status | Problem |
|-----------|--------|---------|
| BGAppRefreshTask (midnight + every 45min) | `submitted=6 ran=0` on child device | iOS ML throttling — never executes |
| BGProcessingTask (usage-upload piggyback) | Also didn't execute overnight Apr 11 | Same iOS throttling |
| Extension `extensionRebuildSlidingWindow()` | Exists but was never called at midnight | Was only triggered by WINDOW_TOP_HIT during recording |
| SKIP_MIDNIGHT 2h timeout | Only helps if events arrive to trigger the check | If stale window is 61+, no events arrive at all |

**Options evaluated (Apr 12, 2026):**

**Option 1: Extension-side midnight rebuild (IMPLEMENTED)** — `intervalDidStart()` fires reliably at 00:00. Call `extensionRebuildSlidingWindow()` right there to register fresh 1-60 thresholds. Safe because iOS cumulative is 0 at midnight — no catch-ups to fire. Falls back to MIDNIGHT_PENDING if rebuild fails. See "Extension-Side Midnight Rebuild" section below.

**Option 2: Silent push notifications (parent → child)** — Parent device sends silent push via CloudKit/APNs every ~30 min → wakes child app → `scheduleActivity()` runs. Most reliable iOS background wake mechanism. Requires server infrastructure or CloudKit subscription setup. Good long-term solution but heavier to build. Consider if Option 1 proves insufficient for intraday threshold exhaustion. **NOTE:** Only viable for Individual and Family plans where a parent device is paired/synced. For Solo plans (no parent device), this approach is not possible — the UX would need to guide the child to open the main app themselves (e.g., morning reminder notification).

**Option 3: Always register thresholds starting at 1** — Instead of sliding window from `currentMinutes+1`, always include thresholds 1-60 regardless of current usage. Duplicates filtered by SKIP_REGRESSION. Wastes threshold slots but guarantees events fire on a fresh day. Downside: uses more of the ~500 iOS threshold budget (could register 1-60 AND 61-120 for each app = 120 per app, only safe for 4 apps).

**Option 4: WidgetKit timeline refresh** — Add a simple home screen widget. iOS gives widgets periodic background refresh time (~15-60 min). Use `TimelineProvider.getTimeline()` to call `scheduleActivity()`. More reliable than BGTask on some devices. Requires widget extension target. The child/parent would need to add the widget to their home screen.

**Option 5: Register overlapping windows** — Register both 1-60 AND the sliding window (e.g., 45-104). Uses more threshold budget but provides coverage even if the window assumption is wrong. Combined with Option 3. Practical limit: ~4 apps with 120 thresholds each = 480 (near 500 limit).

**Decision:** Option 1 implemented first — simplest, no new infrastructure, leverages existing code. If it works at midnight but intraday exhaustion remains a problem, Option 2 (silent push) is the next escalation. Option 4 (widget) is a lighter alternative to Option 2 worth considering.

---

### Extension-Side Midnight Rebuild (Apr 12, 2026)

**Status:** IMPLEMENTED (branch: feature/streamline-usage-recording)

**Problem:** `scheduleActivity()` lives in the main app. After midnight, yesterday's stale thresholds (e.g., window 61-120) don't cover today's usage (iOS cumulative resets to 0). If the child opens a learning app without opening the main app first, usage goes untracked — potentially for hours. BGAppRefreshTask is unreliable on child devices (`submitted=6 ran=0` across 4 days).

**Evidence:** Apr 12 logs show `intervalDidStart()` fires reliably at 00:00:00.146, but `scheduleActivity()` didn't run until 00:45:34 when the user manually opened the app. The 45-minute gap had zero tracking. Without manual intervention, the gap would persist until the 2h SKIP_MIDNIGHT timeout.

**Solution:** At midnight, the extension now rebuilds thresholds itself instead of waiting for the main app:

1. `intervalDidStart()` detects genuine midnight (day change) ✓ (existing)
2. Resets `lastThreshold` to 0 for all apps ✓ (existing)
3. **NEW:** Resets daily counters (`resetAllDailyCounters`) so `ext_usage_today=0`
4. **NEW:** Calls `extensionRebuildSlidingWindow()` which registers fresh 1-60 thresholds via `DeviceActivityCenter().startMonitoring()`
5. **NEW:** If rebuild succeeds → no `MIDNIGHT_PENDING` set (tracking starts immediately)
6. **NEW:** If rebuild fails → falls back to `MIDNIGHT_PENDING` (existing behavior)

**Why extension-initiated `startMonitoring()` is safe at midnight:** The known pitfall ("iOS immediately fires all thresholds") only applies when there IS cumulative usage to catch up on. At midnight, iOS cumulative is 0. Registering thresholds 1-60 when cumulative is 0 means no catch-ups fire — the extension simply waits for real usage to accumulate minute by minute.

**Expected log output at midnight:**
```
[00:00:00] MIDNIGHT_START activity=ScreenTimeTracking trackedApps=8
[00:00:00]   APP_STATE BB131A01... ext_today=3420s ext_date=2026-04-11 lastThresh=3600s
[00:00:00] MIDNIGHT_RESET_COMPLETE — lastThreshold reset for 8 apps
[00:00:00] EXT_REBUILD_APP appID=BB131A01... current=0min → new window 1-60
[00:00:00] EXT_REBUILD_SUCCESS events=480 apps=8
[00:00:00] MIDNIGHT_EXT_REBUILD_OK ��� fresh 1-60 thresholds registered, no MIDNIGHT_PENDING needed
```

**Fallback (if rebuild fails):**
```
[00:00:00] EXT_REBUILD_FAILED: <error>
[00:00:00] MIDNIGHT_PENDING_SET — ext rebuild failed, blocking events until scheduleActivity
```
In this case, behavior is identical to the previous implementation — events blocked until main app opens or 2h timeout expires.

**SKIP_MIDNIGHT filter (Filter 0) retained** as safety net for rebuild failures. Not removed.

**scheduleActivity() lastThreshold reset (also Apr 12):** Added `sharedDefaults.set(0, forKey: "usage_\(logicalID)_lastThreshold")` to the date-mismatch branch in `scheduleActivity()`. This ensures that when the main app opens on a new day, stale lastThreshold values from yesterday are cleaned up — even if the extension's midnight reset didn't run (e.g., old build processed midnight without resetting). Without this, SKIP_REGRESSION blocks all events because `threshold <= staleLastThreshold`. This is a defense-in-depth fix: the extension midnight rebuild is the primary path, but `scheduleActivity()` is the safety net.

**STALE_THRESHOLD_RESET — MONITORING_ALIVE Path (also Apr 12):** Third defense layer. Problem: when `MONITORING_ALIVE` detects active monitoring, it skips `scheduleActivity()` entirely — so the lastThreshold reset added to `scheduleActivity()` never executes. Fix: Added a lastThreshold reset loop in the `MONITORING_ALIVE` path in `ScreenTimeService.swift` (~line 495) that runs on **every app open**. For each tracked app, checks `ext_usage_\(appID)_date != today` → resets `usage_\(appID)_lastThreshold` to 0. This is why apps started recording again after opening the main app even though `scheduleActivity()` didn't run (monitoring was already active). Three-layer defense summary:
1. `intervalDidStart()` at midnight → resets lastThreshold (primary)
2. `scheduleActivity()` date-mismatch branch → resets lastThreshold (when main app triggers fresh monitoring)
3. `MONITORING_ALIVE` path → resets lastThreshold (when monitoring is already active, scheduleActivity skipped)

---

### Out-of-Order Catch-Up Events (Apr 12, 2026)

**Status:** DISCOVERED Apr 12 — **CLOSED Apr 30, 2026** by `lastThreshold` hold-on-clamp. See §"Apr 30, 2026 — Stale Catch-Up `lastThreshold` Poisoning" at the end of this doc for the fix and the Apr 29 incident that finally exposed the no-restart variant.

**Discovery:** After `startMonitoring()` with `includesPastActivity: true`, iOS fires catch-up events for all thresholds below the current cumulative usage. These events arrive **OUT OF ORDER** — iOS does not guarantee sequential delivery.

**Device evidence (Apr 12):**
- **C6DA269B** (~34min real usage): min.60 fired first → lastThresh set to 3600 → then min.29 (1740s), min.37 (2220s) arrived → `SKIP_REGRESSION` blocked them because `1740 <= 3600`. Only 1 minute recorded instead of ~34.
- **BB131A01** (~15min real usage): min.15 fired first → lastThresh set to 900 → then min.8 (480s), min.9 (540s), min.13 (780s) arrived → all blocked because `<= 900`.
- **E8B1C8C6**: min.3 rejected (thresh=180 <= lastThresh=1560) — higher events already recorded.

**Root cause:** Same-day `SKIP_REGRESSION` filter (`thresholdSeconds <= lastThreshold`) assumes thresholds arrive in monotonic ascending order. iOS violates this assumption during catch-up bursts after `startMonitoring()`. The first event to arrive (often a high threshold) sets `lastThreshold` high, then all lower-numbered events are blocked.

**Impact:** This is the likely root cause of BOTH historical issues:
- **Overcounting:** If multiple high-threshold events slip through before `SKIP_REGRESSION` kicks in (e.g., min.60 AND min.55 both record +60s each before either sets lastThreshold high enough to block the other)
- **Undercounting:** If the highest event arrives first and blocks all lower events (the pattern seen Apr 12)

**Scope:** Only affects **intraday restarts** where there is existing cumulative usage:
- `WINDOW_TOP_HIT` → `extensionRebuildSlidingWindow()` during the day
- Manual monitoring restarts
- `scheduleActivity()` restarts from main app

**NOT a problem at midnight:** iOS cumulative resets to 0 at midnight, so there are no catch-ups to fire. The extension-side midnight rebuild is unaffected.

**Current filter chain (no SKIP_RESTART absorb window):**
The filter chain in `setUsageToThreshold()` is:
1. Filter 0: `SKIP_MIDNIGHT` — blocks events during midnight pending refresh
2. Filter 1: Min threshold validation — blocks thresholdSeconds < 60
3. Filter 2: Shielded reward app — blocks events for currently-shielded reward apps
4. Filter 3: `SKIP_REGRESSION` — blocks thresholdSeconds <= lastThreshold (same day) or == lastThreshold (cross day)

Note: The `SKIP_RESTART` 60s absorb window referenced in earlier documentation does NOT exist in the current filter chain. The `monitoring_restart_timestamp` is set but only used for shield checks on rejected events, not for filtering.

**Potential fix approaches (not yet implemented):**
1. **Re-add SKIP_RESTART absorb window:** Block ALL events for N seconds after restart, capture the MAX threshold seen. After the window closes, set lastThreshold to max and record the correct usage delta. Ensures out-of-order events during catch-up don't corrupt lastThreshold.
2. **Set usage = max(current, threshold):** Instead of delta accumulation, treat catch-up events as absolute positions. Only update usage if threshold > current recorded value. Eliminates ordering dependency.
3. **Accept undercounting for catch-ups:** Real-time minute-by-minute tracking (non-catch-up) works correctly since events arrive one at a time in order. Catch-up undercounting only affects restart scenarios.

---

### FamilyControls Authorization Behavior (Apr 12, 2026)

**Discovery:** Toggling off Brain Coinz in iOS Screen Time settings **revokes the FamilyControls authorization entirely** — not just the current monitoring session. Re-enabling triggers the full system authorization prompt: *"Brain Coinz Would Like to Access Screen Time"* with Continue/Don't Allow buttons.

**Implication:** Our app's `requestAuthorization()` (called on launch) may silently re-obtain authorization without showing this prompt — the `authorizationStatus` check (`== .approved`) would fail, triggering `requestAuthorization()` which could re-authorize silently or show the prompt depending on iOS state.

**Concern:** If a parent intentionally revokes Brain Coinz's Screen Time access, our app should respect that decision rather than silently re-authorizing on the next launch. This is a trust/compliance consideration for the parent-child relationship model.

**Status:** Needs review. Consider:
- Detecting revoked authorization and showing an in-app message instead of silently re-requesting
- Distinguishing between "never authorized" (first launch) and "authorization revoked" (parent decision)
- Whether iOS handles this distinction automatically via the system prompt

---

### Console.app os_log Observability (Apr 13, 2026)

**Problem:** Extension `print()` statements and UserDefaults-based `debugLog()` are invisible in Console.app. The only way to read extension logs was opening the main app — which triggers `scheduleActivity()` and masks whether the extension-side midnight rebuild works autonomously.

**Solution:** Added `os_log` via `Logger(subsystem: "i6dev.ScreenTimeRewards.extension", category: "monitor")` to `DeviceActivityMonitorExtension.swift`. Uses `.notice` level (always visible in Console.app — `.info` level is hidden by default).

**16 log points added at critical decision paths:**

| Category | Log Points | Messages |
|----------|-----------|----------|
| Midnight lifecycle | 5 | `MIDNIGHT_START`, `INTERVAL_START`, `MIDNIGHT_RESET_COMPLETE`, `MIDNIGHT_EXT_REBUILD_OK`, `MIDNIGHT_PENDING_SET` |
| Threshold events | 4 | `THRESHOLD` (event + total count), `EVENT` (per-app details), `RECORDED` (success) |
| Filter decisions | 2 | `SKIP_MIDNIGHT`, `SKIP_REGRESSION` |
| Usage recording | 2 | `NEW_DAY`, `INCREMENT` |
| Extension rebuild | 3 | `EXT_REBUILD_APP`, `EXT_REBUILD_SUCCESS`, `EXT_REBUILD_FAILED` |

**4 dead `print()` calls removed** — replaced by the os_log equivalents above.

**Console.app filter:** Subsystem = `i6dev.ScreenTimeRewards.extension`, Category = `monitor`

**Memory impact:** Negligible. `Logger` writes to system log buffer, no heap allocation.

---

### Apr 12→13 Midnight Transition — Console.app Evidence (Apr 13, 2026)

**Setup:** iPhone connected to Mac via USB, Console.app recording, `caffeinate -s` keeping Mac awake. Main app NOT opened after midnight.

**Console.app system-level timeline (pre-os_log build):**

| Time | Event | Source |
|------|-------|--------|
| 23:59:01.121 | `ScreenTimeTracking did end` — `intervalDidEnd` fires | UsageTrackingAgent |
| 23:59:01.132 | Extension launched (PID 86752) for intervalDidEnd | runningboardd |
| 23:59:01.257 | intervalDidEnd callback completes (~135ms) | runningboardd |
| 00:00:00.013 | `ScreenTimeTracking did start` — `intervalDidStart` fires | UsageTrackingAgent |
| 00:00:00.016 | Extension reused (same PID 86752) for intervalDidStart | runningboardd |
| 00:00:00.160 | iOS computes next interval: Apr 13 00:00 → Apr 13 23:59 | ScreenTimeActivityExtension |
| 00:00:22.670 | Host connection invalidated (UsageTrackingAgent cancelled) | ScreenTimeActivityExtension |
| 00:00:23.586 | Extension terminated (PID 86752) — **clean exit, NOT jetsam** | runningboardd |

**Key finding:** Extension had **22+ seconds** at midnight — sufficient for `resetAllDailyCounters()` + `extensionRebuildSlidingWindow()` + UserDefaults flush.

**Post-midnight threshold events (main app never opened):**

| Time | Event | Evidence |
|------|-------|----------|
| 00:32:30 | `min.1` reached threshold | UsageTrackingAgent |
| 00:33:28 | `min.2` reached threshold | UsageTrackingAgent |
| 00:34:27 | `min.3` reached threshold | UsageTrackingAgent |
| 00:35:30 | `min.4` reached threshold | UsageTrackingAgent |
| 00:36:28 | `min.5` reached threshold | UsageTrackingAgent |

**Analysis — extension-side midnight rebuild CONFIRMED WORKING:**
1. Thresholds start from **min.1** → window correctly built from cumulative=0 (fresh day)
2. Events fire **~60s apart** → real-time usage tracking, not catch-up
3. Only 1 app hash (`3453076564568310786`) → matches test setup (single app used)
4. **Main app was never opened** → proves `extensionRebuildSlidingWindow()` at midnight autonomously registered thresholds 1-60 via `startMonitoring()`

**Remaining work:**
- Verify with os_log build (`.notice` level) to see full internal decision chain
- Monitor for window exhaustion at min.60 → automatic `extensionRebuildSlidingWindow()` from `WINDOW_TOP_HIT` path
- Long-duration test: does tracking continue past 60 minutes without main app?

---

### Apr 13 Overcounting Regression — 4-Week Audit & Partial Revert

**Symptom (Apr 12–13 reported by user):**
Systematic daily inflation floods. Every monitored app (learning AND reward) reaches `lastThresh=3600s` (the 60-min ceiling) regardless of real usage. Reward-app goals falsely report MET. Apr 13 16:44:14+ log window shows dozens of `SKIP_REGRESSION` events for out-of-order catch-up threshold events (min.48, min.47, min.12, min.43, min.2 arriving non-sequentially), with only one `RECORDED` event (`oldToday=3540s +60 = 3600s`). User's position: "the app was stable for a long period that I've decided to distribute the app to app store — something we did recently 7 to 15 days has infected the app."

**Wrong assumption that wasted a cycle:**
Earlier in the Apr 13 session the midnight-transition evidence (min.1→min.5 firing sequentially over 4 minutes) was treated as proof overcounting was resolved. It was not. Logs showing the new extension-rebuild path executed were evidence the *new code path ran* — not evidence the user-facing symptom (inflation) was gone. Ground truth (comparing real usage to recorded usage) is required before calling overcounting fixed; log patterns alone are insufficient.

**4-week commit audit (Mar 16 → Apr 13)**

Filtered to commits touching `DeviceActivityMonitorExtension.swift`, `ScreenTimeService.swift`, or `ChildBackgroundSyncService.swift`:

| # | Commit | Date | Δ | What it did | Relevance |
|---|---|---|---|---|---|
| 1 | `3fd95f0` | Mar 30 22:28 | Ext +27/−12, Svc +9/−9 | Scoped `lastThreshold` reset to midnight-only. Hardened Filter 4 `shieldConfigs=nil` guard. | **Fixed the exact bug now recurring.** Its commit message: *"Without lastThreshold retained, Filter 5 passed everything, catchup_max captured window top (3600s), and apps with no real usage were inflated to 60min."* |
| 2 | `14bdb0b` | Mar 31 19:11 | ChildBGSync −87 | Removed `monitoring-refresh` BGAppRefreshTask. | Not direct cause of 60-min inflation. Could contribute to intraday window exhaustion. |
| 3 | `91d87b6` | Mar 31 19:14 | Ext −21 | Removed SKIP_COOLDOWN filter ("redundant with SKIP_REGRESSION"). | Redundancy argument assumes `lastThreshold` remains monotonic. If any path resets `lastThreshold=0` intraday, cooldown fallback was the last line of defense. |
| 4 | `3522109` | Apr 1 22:45 | Ext −22, Svc −157 | **Removed `catchup_max` system (−179 lines net).** | **Prime suspect.** Memory explicitly warns *"NEVER re-remove catchup_max — scheduleActivity() clearing catchup_max is the correct inflation defense."* Commit did exactly that. |
| 5 | `1c06b67` | Apr 12 21:14 | Ext +41, Svc +28 | Extension-side midnight rebuild (feature). **Three-layer lastThreshold reset:** midnight, scheduleActivity date-mismatch, MONITORING_ALIVE on every app open. | **Trigger suspect.** Layers 2 and 3 intentionally run intraday — violating the Mar 30 constraint. |

**Prior to Mar 30 the key files had zero commits in the preceding two weeks** — matching the user's description of a stable pre-distribution period.

**Hypothesized inflation chain (not yet empirically proven):**
1. `3522109` (Apr 1) removed the `scheduleActivity()`-time `catchup_max` inflation defense.
2. `1c06b67` (Apr 12) added `MONITORING_ALIVE STALE_THRESHOLD_RESET` + `SLIDING_WINDOW_DATE_MISMATCH lastThreshold=0` paths that fire on app open when any app has stale `ext_usage_*_date`.
3. After midnight rebuild, if main app opens before every app has recorded today's first event, those apps hit Layer 2/3 → `lastThreshold=0`.
4. `scheduleActivity()` → `startMonitoring()` with `includesPastActivity: true` → iOS replays catch-up events for past activity.
5. Catch-ups arrive out-of-order (Apr 12 discovery). First arrival with `lastThreshold=0` passes `SKIP_REGRESSION`; `max(60, threshold − lastThreshold)` floor accumulates `+60` per slip; subsequent low-minute events blocked but ceiling already reached.

**Partial revert applied Apr 13 (uncommitted):**

Surgically removed from `ScreenTimeService.swift`:

```diff
@@ MONITORING_ALIVE path (was :500-519) @@
-                    // Reset stale lastThreshold on new day — even when monitoring is alive.
-                    if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
-                        let fmt = DateFormatter()
-                        fmt.dateFormat = "yyyy-MM-dd"
-                        let todayStr = fmt.string(from: Date())
-                        let trackedIDs = sharedDefaults.stringArray(forKey: "tracked_app_ids") ?? []
-                        for appID in trackedIDs {
-                            let extDate = sharedDefaults.string(forKey: "ext_usage_\(appID)_date")
-                            if extDate != todayStr {
-                                let oldThresh = sharedDefaults.integer(forKey: "usage_\(appID)_lastThreshold")
-                                if oldThresh > 0 {
-                                    sharedDefaults.set(0, forKey: "usage_\(appID)_lastThreshold")
-                                    lifecycleLog("STALE_THRESHOLD_RESET appID=\(appID.prefix(8))... lastThreshold was \(oldThresh)s, reset to 0 ...")
-                                }
-                            }
-                        }
-                    }

@@ scheduleActivity date-mismatch (was :2283-2285) @@
-                    // Date mismatch — also reset lastThreshold so SKIP_REGRESSION doesn't block new-day events
-                    sharedDefaults.set(0, forKey: "usage_\(app.logicalID)_lastThreshold")
-                    lifecycleLog("SLIDING_WINDOW_DATE_MISMATCH ... → defaulting to 0 min, lastThreshold reset")
+                    lifecycleLog("SLIDING_WINDOW_DATE_MISMATCH ... → defaulting to 0 min")
```

**Preserved intact:**
- Extension midnight-only `lastThreshold` reset (`DeviceActivityMonitorExtension.swift:184`) — the Mar 30 fix
- Extension-side midnight rebuild feature (Apr 12) — fresh 1-60 thresholds at midnight without main app
- `os_log` observability (Apr 13)

**What this revert tests:**
Whether Apr 12 Layers 2+3 (intraday `lastThreshold` resets) are the *trigger* of the overcounting floods. If post-revert the device still shows reward apps reaching 3600s, the Apr 1 `catchup_max` removal is the next target. If floods stop, the trigger is isolated and Apr 1 cleanup can stay.

**Verification plan (fresh capture — no earlier-log archaeology):**
1. Build + deploy child build with the Apr 13 partial revert
2. Do not open main app after install; leave device overnight
3. Use only ONE app during the day (ground truth)
4. Next day, via Console.app filter `subsystem:i6dev.ScreenTimeRewards.extension`:
   - Zero `STALE_THRESHOLD_RESET` entries (code path removed)
   - `SLIDING_WINDOW_DATE_MISMATCH` log should show "defaulting to 0 min" only — no "lastThreshold reset"
   - Unused reward apps: `usage_today=0`
   - Main-app open should NOT trigger a RECORDED storm
5. Cross-check in-app usage UI against real device usage

**Pending escalation if revert alone is insufficient:**
- Restore `catchup_max` system (revert `3522109` selectively)
- Re-evaluate SKIP_COOLDOWN removal (`91d87b6`) under post-`catchup_max` conditions
- Re-assess whether `includesPastActivity: true` on intraday rebuilds is contributing to the `max(60, …)` delta amplification

---

### Apr 14 Soak Day 1 — Revert Verification (Apr 14, 2026)

**Status:** Day 1 of 3-day soak clean. Per the feedback rule *"never declare resolved without ground truth"*, this is NOT a fix declaration — extended observation still required before the Apr 13 revert can be committed.

**Setup (Apr 13 evening):**
- Build with Apr 13 partial revert deployed (still uncommitted)
- All previously-monitored apps deleted (data was corrupted from the Apr 13 inflation storms)
- 1 learning + 1 reward app freshly added — no stale `ext_usage_*_date`, no stale `lastThreshold`
- Console.app recording throughout

**Apr 13 evening baseline (Test A):**
- 70 min of real learning-app usage → **4200s recorded** (matches 1:1)
- Reward app stayed at **0** across the session
- No `STALE_THRESHOLD_RESET` lines observed on a mid-session main-app reopen — confirms the revert is deployed (code path removed)

**Apr 13 → Apr 14 overnight:**
- Device idle, main app not launched
- UsageTrackingAgent state dump at 07:03:56 (Apr 14) showed all 120 thresholds (60 per app) with full `remaining` values — iOS had counted **zero activity** for either app since the midnight rebuild, i.e. no phantom catch-ups overnight

**Apr 14 full-day lifecycle timeline (from in-app debugLog dump):**

| Time | Event | Interpretation |
|------|-------|----------------|
| 23:59:00 (Apr 13) | `INTERVAL_END` | Scheduled end of previous activity window |
| 00:00:01 (Apr 14) | `INTERVAL_START` (×2) + `MIDNIGHT_EXT_REBUILD` | **Direct confirmation** the Apr 12 extension-side midnight rebuild works in production — fresh 1–60 thresholds registered autonomously, main app never involved |
| 07:51, 09:47, 17:38, 19:04 | `EXTENSION_KILLED` → `EXTENSION_INIT` (×4) | Normal ephemeral extension lifecycle; iOS reclaims and re-spawns the process on demand |
| 18:22:34 | `INTERVAL_END` + `INTERVAL_START` | **Intraday `restartMonitoring()`** — NOT midnight. Attributed to BGTask `monitoring-refresh` (45-min cadence) → `ScreenTimeService.restartMonitoring()`. Critically no storm followed despite `includesPastActivity: true` on the restart |
| 19:09:51 | `MONITORING_ALIVE — app launch` | **FIRST and only main-app launch of Apr 14**, after a full day of accumulated extension state — exactly the Apr 13 failure scenario. No inflation observed, numbers accurate |

**Later Apr 14 (post-19:09 launch):** User added 2 more learning + 2 more reward apps (total 4 monitored apps). No inflation on any app. Reward apps stayed at 0. See "includesPastActivity Recovery on Mid-Day App Add" section below for the mid-day add behavior details.

**Signals read:**
- ✅ Midnight transition directly confirmed in the extension debugLog (no longer needs to be inferred from UsageTrackingAgent state dumps)
- ✅ Intraday `startMonitoring()` at 18:22:34 with `includesPastActivity: true` did NOT produce a catch-up replay storm — the scenario that plagued Apr 13 did not reproduce
- ✅ Single main-app launch at 19:09 was clean after a full day of accumulated state
- ✅ No `STALE_THRESHOLD_RESET`, no `SLIDING_WINDOW_DATE_MISMATCH` reset — the two reverted code paths never ran

**Caveats:**
- The in-app debugLog filter does not include RECORDED/INCREMENT lines — storm detection here is structural (no lifecycle thrashing), not event-level
- Usage scale is still small vs Apr 13 storms (Apr 13 had 4+ reward apps inflated; today's soak started with 1 reward app before scaling to 2)
- 18:22:34 intraday restart trigger not yet confirmed empirically (BGTask vs focus change vs some other path)

**Soak progress: 1 of 3 days complete. No inflation signals. Revert remains uncommitted pending days 2–3.**

---

### Apr 15 Soak Day 2 — Ground-Truth Extension DebugLog (Apr 15, 2026)

**Status:** Soak day 2 of 3 passes on **ground-truth extension debugLog**, pulled on the morning of Apr 15 after the pre-foreground-tracking protocol (run learning apps first, foreground main app once at end — see `feedback_preforeground_tracking_goal.md`). Revert remains uncommitted pending day 3.

**Setup:** Device continued from the Apr 14 end state (6 apps monitored), no main-app launches overnight, learning apps used across the morning of Apr 15 *before* the first main-app foreground at 08:59:32.

**Evidence sources:** iOS-side `Build Reports/Console_midnight.rtf` covers `00:01:11 – 00:13:04` (Console capture started partway — missed `00:00:00 – 00:01:10`). The **extension debugLog covers the full midnight window and the morning tracking session**, filling the Console capture gap.

**Extension debugLog timeline (Apr 15 pre-foreground window):**

| Time | Line | Meaning |
|------|------|---------|
| 00:00:41 | `INTERVAL_START` ×3 → `MIDNIGHT_EXT_REBUILD` | Direct confirmation: `intervalDidStart()` ran and `extensionRebuildSlidingWindow()` succeeded. 3× `INTERVAL_START` matches the concurrent-callback pattern documented below under "Concurrent `eventDidReachThreshold` Execution". |
| 00:00:41 | `SLIDING_WINDOW_DATE_MISMATCH` ×6 (`extDate=nil`, `minutes=0`) | Benign under the Apr 13 revert. `extDate=nil` is the expected fresh-midnight state. The log line was retained; the stale-reset *action* this check used to gate was removed in the Apr 13 revert. |
| 00:14:38 | `MONITORING_RESTART` (reason: midnight background task) | BG task `com.screentimerewards.midnight-reset` executed 14 min after midnight. Arrived *after* the extension-side rebuild had already registered the window — pure late fallback. |
| 00:14:42 | `MONITORING_START` events=360 | Fresh 6×60 sliding-window thresholds re-registered by the BG-task restart. Redundant but harmless: cumulative=0 means the same thresholds land. |
| 08:21:36 | First threshold event — `E8B1C8C6 min.1` | First real usage event of the day. **Before any main-app foreground** — pre-foreground tracking confirmed. |
| 08:21:36 → 08:49:55 | `DADD46EB` tracked `min.1 → min.15` cleanly | Minute-by-minute increments. No duplicates, no storms, no regressions. |
| 08:49:55 | `GOAL_CHECK: ✅ 51E884C1-92D goal MET` + `SHIELD_CHECK: ✅ REMOVED shield for 51E884C1-92D` | Reward logic and shield removal executed entirely from the extension, still with no main-app involvement. |
| 08:51 onward | `BB131A01` tracked `min.1 → min.3` | Second reward app starts clean on the same extension-managed window. |
| 08:59:32 | `MONITORING_ALIVE` — OS confirms active, skipping restart (app launch) | **First main-app foreground of Apr 15** — 8h 58m after midnight rebuild, 38m after first threshold event. Satisfies the pre-foreground-tracking success criterion. |

**iOS-side Console timeline (`Build Reports/Console_midnight.rtf`, corroborates the extension debugLog):**

| Time | Source | Event |
|------|--------|-------|
| 00:00:00 – 00:01:10 | — | Missing from Console capture. Extension debugLog covers this window (see `MIDNIGHT_EXT_REBUILD` at 00:00:41 above). |
| 00:01:11 – 00:01:44 | `dasd` scoring | `bgRefresh-com.screentimerewards.midnight-reset` → `Decision: MNP`. Early denials; `dasd` eventually grants the task at 00:14:38 (per extension debugLog). |
| 00:01:37 – 00:01:38 | `ScreenTimeActivityExtension` (pid 7444, host UsageTrackingAgent pid 7405) | `XPC_ERROR_CONNECTION_INTERRUPTED` → `tearing down context` → `runningboardd Removing process` → `Terminated` (`isUserKill=0`). Standard post-callback ephemeral-extension teardown after the 00:00:41 rebuild. |
| 00:01:38 → 00:02:45 | — | 67s quiet window. Extension debugLog shows no events fired during this span. |
| 00:02:45 | `UsageTrackingAgent` | Bulk state dump: `usage.app.<logicalID>.min.N/... has (N×60) seconds remaining` for **6 distinct logicalIDs**, `min.1` through `min.60` each. `remaining = minuteNumber × 60` exactly — corroborates cumulative=0 for every monitored app. |
| 00:09:38 | `audiomxd` | pid 6633 `app<i6dev.ScreenTimeRewards>` → `running-suspended-NotVisible`. Main app is alive but suspended; corroborates "no main-app foreground". |
| 00:02:55 – 00:13:04 | `dasd` scoring | Continued MNP in the Console window. Extension debugLog shows grant at 00:14:38 — Console capture ends before that point. |

**Interpretation:**

1. **iOS cumulative = 0 for all 6 monitored apps at rebuild time.** Corroborated by both the Console `UsageTrackingAgent` dump (`remaining = minute × 60`) and the extension debugLog (clean 0→15 min progression starting at 08:21:36).
2. **Main app did not foreground during the critical window.** First `MONITORING_ALIVE` (OS-confirmed app launch) at 08:59:32 — 8h 58m after midnight. The `audiomxd` `running-suspended-NotVisible` state at 00:09:38 corroborates from the iOS side.
3. **`midnight-reset` BGAppRefreshTask fired at 00:14:38 as late fallback, not primary path.** Extension-side rebuild at 00:00:41 had already registered the window 14 minutes earlier. This reinforces the Apr 11 "BGTasks are unreliable at 00:01" finding and confirms the extension-side rebuild is load-bearing.
4. **The 67s Console gap (00:01:38 → 00:02:45) is iOS internal propagation, not a monitoring gap.** The extension debugLog shows no events fired in this span; `SKIP_MIDNIGHT` (Filter 0) would have absorbed any stale pre-midnight catch-ups regardless.
5. **`SLIDING_WINDOW_DATE_MISMATCH` is benign under the Apr 13 revert.** The log fires 6× at 00:00:41 with `extDate=nil, minutes=0`, which is the expected fresh-midnight state. The stale-reset action this log used to guard was removed in the Apr 13 revert — the log line is a retained tracer, not a live reset path.
6. **Pre-foreground tracking confirmed end-to-end.** Midnight rebuild (00:00:41) → 8 h idle → 28 min `DADD46EB` clean 1→15 min → goal-met shield removal (08:49:55) → `BB131A01` 1→3 min — all before the first main-app foreground at 08:59:32. This is the critical invariant for a child-device deployment.

**Remaining limitations (per the ground-truth rule):**

- No main-app UI screenshot / database snapshot yet — wall-clock vs. recorded daily totals for Apr 14 will be compared on Apr 16 if Day 3 holds
- Morning usage scale still small (2 reward apps tracked this morning, versus 4+ during the Apr 13 storms) — the revert has not yet been stress-tested against a multi-app storm load

**Comparison to Apr 14:**

| | Apr 14 (Day 1) | Apr 15 (Day 2) |
|---|---|---|
| `MIDNIGHT_EXT_REBUILD` debugLog | ✅ directly observed | ✅ directly observed (00:00:41) |
| Fresh 1–60 thresholds post-midnight | ✅ inferred from `UsageTrackingAgent` state dump at 07:03:56 | ✅ directly observed (Console 00:02:45 + extension debugLog) |
| Main-app involvement | ❌ (none) | ❌ (none; first `MONITORING_ALIVE` at 08:59:32) |
| BGTask `midnight-reset` execution | ❌ (not observed firing) | ✅ fired 00:14:38 as late fallback (after extension rebuild) |
| Intraday `restartMonitoring()` | ✅ 18:22:34 (clean, no storm) | Not in morning capture window |
| Ground-truth usage comparison | Partial (70 min real → 4200s recorded Apr 13 evening only) | ✅ Pre-foreground: `DADD46EB` clean 1→15 min before 08:59:32 app launch; goal-met shield removal from extension alone |

**Signal read:** no inflation signals; pre-foreground tracking passes ground truth for Day 2. Day 2 evidence is now at parity with or stronger than Day 1 on the critical child-device invariant (extension drives tracking; main app is optional). 3-day soak continues.

**Soak progress: 2 of 3 days complete on ground-truth evidence. Day 3 verification on Apr 16 morning — same protocol (run learning apps first, foreground main app once at end, pull extension debugLog + main-app UI totals for wall-clock comparison). Revert remains uncommitted pending Day 3.**

---

### Apr 16 Soak Day 3 — FIXED, Wall-Clock Parity with iOS Screen Time (Apr 16, 2026)

**Status:** ✅ **FIXED.** Day 3 of 3 passes on ground truth. User confirmed: *"the usage on our app matches perfectly the usage recorded on iOS Screen Time."* The Apr 13 revert has been committed as `ae2e565` ("fix(usage): revert intraday lastThreshold resets + bump to 1.0.3(1)"). Apr 12 extension-side midnight rebuild is committed as `1c06b67`. The overcounting regression discovered Apr 12-13 is resolved.

**Caveat per the ground-truth feedback rule:** "fixed" here means passes ground truth on the test device across a 3-day soak. Continued multi-device observation remains prudent — different usage patterns, app counts, and hardware could still surface edge cases.

**Extension debugLog timeline (Apr 16):**

| Time | Line | Meaning |
|------|------|---------|
| 23:59:01 (Apr 15) | `INTERVAL_END` | Scheduled end of previous activity window |
| 00:00:00 (Apr 16) | `INTERVAL_START` ×2 → `MIDNIGHT_EXT_REBUILD` | Extension-side midnight rebuild fired autonomously (main app not involved). Matches Apr 14 and Apr 15 pattern. |
| 07:23:59 – 07:36:58 | `EXTENSION_KILLED` / `EXTENSION_INIT` ×2 | Normal ephemeral-extension lifecycle churn |
| 12:39:00 | `MONITORING_ALIVE — OS confirms active, skipping restart (app launch)` | **First main-app foreground of Apr 16** — 12h 39m after midnight rebuild. Pre-foreground tracking window. |
| 12:39:00 | `SLIDING_WINDOW_READ C6DA269B extDate=2026-04-16 today=2026-04-16 → 18 min` | **Pre-foreground tracking confirmed:** 18 min recorded for C6DA269B before any main-app launch. Ground truth vs iOS Screen Time confirmed by user. |
| 12:39:00 | `SLIDING_WINDOW_DATE_MISMATCH` ×6 (`extDate=nil`, `extTodaySeconds=0`) | Benign under the Apr 13 revert — the 6 other apps had zero usage on Apr 16, so `ext_usage_*_date` was never written. Log line is a tracer; no lastThreshold reset action runs. |
| 12:39:02 | `SLIDING_WINDOW C6DA269B current=18min range=19-78 (60 thresholds) windowTop=78` | Sliding window correctly re-centered above current usage after main-app launch. No restart storm. |
| 12:39:08 | `MONITORING_START — events=420 (sliding window, 18 min already tracked)` | 7 apps × 60 thresholds = 420. 18 min preserved across the restart. |
| 13:25 – 18:37 | `EXTENSION_KILLED` / `EXTENSION_INIT` ×6 | Normal ephemeral lifecycle across the afternoon |
| 19:07:49 – 20:30:23 | `EXTENSION_GAP — no heartbeat for 82m` | **Real no-usage period** — user confirmed no apps were opened during this window. Not a silent failure. |

**Interpretation:**

1. **Midnight rebuild is load-bearing and stable for 3 consecutive days** (Apr 14, 15, 16). No main-app involvement required for next-day tracking to start.
2. **Pre-foreground tracking works across midnight** — 18 min accurate on C6DA269B at the first main-app launch 12h 39m into the day.
3. **Wall-clock parity confirmed by user** against iOS Screen Time — the external ground truth we had been missing since Apr 13.
4. **No inflation, no phantom storms, no catch-up floods** across a full day with 7 monitored apps.
5. **The 82m extension heartbeat gap was real idle time, not a failure mode** — user-confirmed.

**Ongoing monitoring (per user request):**

Run the same soak protocol on additional devices with varied usage patterns before declaring this closed across the install base. Until then, keep an eye on:
- Multi-device variance (different app counts, different parent-managed vs. self-managed setups)
- Intraday restart scenarios with **significant existing usage across multiple apps** (Apr 16's 12:39 restart exercised the date-mismatch path for 6 zero-usage apps; the out-of-order catch-up path was not stressed)
- Any recurrence of `3600s` ceiling hits in Console logs → escalate to the deprioritized concurrent-`eventDidReachThreshold` hypothesis below

**Pending items closed by Apr 16 validation:**

- ✅ Apr 13 intraday-reset revert: committed (`ae2e565`)
- ✅ Apr 12 midnight rebuild: committed (`1c06b67`)
- ❌ **Apr 1 `catchup_max` removal revert: no longer required.** The revert of Apr 12 Layers 2+3 alone eliminated overcounting. `catchup_max` system can remain removed.

---

### Concurrent `eventDidReachThreshold` Execution (Apr 13–14, 2026)

**Status:** OBSERVED but DEPRIORITIZED. The Apr 13 revert appears to resolve the user-visible symptom without touching this race. Remains a theoretical vulnerability pending future storm evidence.

**Evidence 1 — Apr 13 21:41:45 (single real min.64 crossing, one app):**

```
21:41:45.235XXX  THRESHOLD event=<private>                          (×15, within 65µs)
21:41:45.236XXX  THRESHOLD totalEvents=2306                         (×15, all read 2305, all write 2306)
21:41:45.238XXX  EVENT min=64 today=3720s lastThresh=3780s          (×15, identical pre-state)
21:41:45.242XXX  INCREMENT +60s = 3780s thresh=3840s lastThresh=3780s  (×15)
21:41:45.255XXX  RECORDED total=3780s                               (×15)
```

Smoking gun: `totalEvents=2306` printed 15 times. All 15 threads read counter=2305, incremented, wrote 2306. Only possible with concurrent execution of `eventDidReachThreshold` (marked `nonisolated` with no lock in `recordUsageEfficiently`).

**Evidence 2 — Apr 14 19:38:14 (new-app add burst, `Build Reports/console-added-apps.rtf`):**

Every event pair during the add burst showed ×5 duplication at the os_log emission level:

```
19:38:14.978XXX  THRESHOLD event=<private>                   (×5)
19:38:14.982XXX  THRESHOLD totalEvents=2380                  (×5, all 5 wrote 2380)
19:38:14.994XXX  RECORDED app=<private>... total=60s         (×5)
19:38:15.021XXX  THRESHOLD event=<private>                   (×5)
19:38:15.027XXX  THRESHOLD totalEvents=2381                  (×5)
...continuing for totalEvents=2382, 2383, 2384, 2385, 2386, 2387, 2388
```

Confirms concurrent execution is **steady-state**, not a one-off. Observed with both 1 app (Apr 13) and 4 apps (Apr 14). Duplication count varies (×5 vs ×15) but the read-before-write pattern is identical.

**Why benign for same-event duplicates (what we've actually observed):**
- All N concurrent threads read identical pre-state (`today=X`, `lastThreshold=Y`)
- All compute identical delta via `max(60, thresholdSeconds − lastThreshold)`
- All write identical final state
- Net effect: one logical increment, despite N physical callback invocations

**Why potentially NOT idempotent for different-event concurrent delivery (hypothesis, not directly observed):**

iOS's out-of-order catch-up burst (Apr 12 discovery) is exactly a different-event concurrent delivery. If the race interacts with that delivery model:

- Thread A: `min.60` thresh=3600 reads `lastThresh=0` → passes SKIP_REGRESSION → writes `lastThresh=3600`
- Thread B: `min.45` thresh=2700 reads `lastThresh=0` (before A's write landed) → passes SKIP_REGRESSION (should have been blocked) → writes `lastThresh=2700` (clobbers A)
- Thread C: `min.20` thresh=1200 reads `lastThresh=0` → passes SKIP_REGRESSION → writes `lastThresh=1200`
- ...N concurrent catch-ups each slip +60s past the regression filter

N concurrent slippages = N×60s inflation. 60 concurrent catch-ups = 3600s = the exact 60-min ceiling seen Apr 13.

**Why not prioritized now:**
- Apr 14 soak day 1 is clean — the Apr 13 revert appears to eliminate the trigger condition (intraday `lastThreshold=0` resets) that gave concurrent catch-ups a path through SKIP_REGRESSION
- Without an active storm to analyze, escalating to serialization changes would be speculative

**Escalation trigger (if a storm recurs):**
1. Check `grep INCREMENT` within a 100 ms window of the storm. Multiple different `thresh=` values → concurrent-delivery confirmed.
2. Check `ext_total_events_received` counter advancement vs observed `THRESHOLD event=` duplicate count. Counter advancing by less than observed count = direct proof of racing reads.
3. If confirmed, candidate fixes (documented, not implemented): NSLock around `recordUsageEfficiently` (simplest), serial `DispatchQueue` for all recording work, or CAS on `usage_*_lastThreshold` before writing.

---

### `includesPastActivity` Recovery on Mid-Day App Add (Apr 14, 2026)

**Status:** Characterized behavior. Not a bug — the correct safe side of the Apr 12 out-of-order catch-up discovery. No code change planned.

**Scenario:** User added 4 apps (2 learning + 2 reward) mid-day via main-app UI at ~19:38. The 2 learning apps had real usage earlier in the day (14 min and 11 min respectively) but were not previously being monitored by Brain Coinz.

**Observed:**
- Within seconds of being added, the 2 learning apps showed **7 min and 6 min recorded** respectively — roughly 50% of their true prior-day usage
- The 2 reward apps stayed at **0** (correct — they had not been used)
- No inflation on any app

**Log trace from `Build Reports/console-added-apps.rtf` (19:38:14.978 → 19:38:15.267, a ~290 ms window):**

| Time | Event | Effect |
|------|-------|--------|
| 14.978 | THRESHOLD batch (App A, first event) | → `RECORDED total=60s` |
| 15.021 | THRESHOLD batch (App B, first event) | → `RECORDED total=60s` |
| 15.071 | THRESHOLD batch (App A) | `INCREMENT +240s = 300s thresh=1020s lastThresh=780s` — delta math jumped 4 minutes because this catch-up arrived with a much higher `thresh` than the previous event had set `lastThresh` to |
| 15.118 | THRESHOLD batch (App B) | `INCREMENT +60s = 120s thresh=600s lastThresh=540s` |
| 15.201 | THRESHOLD batch (App A) | `INCREMENT +120s = 420s thresh=1140s lastThresh=1020s` → **7 min final** ✅ matches user observation |
| 15.242 | `SKIP_REGRESSION thresh=60 <= lastThresh=1140` | App A: out-of-order min.1 catch-up correctly blocked |
| 15.255 | `SKIP_REGRESSION thresh=300 <= lastThresh=600` | App B: out-of-order min.5 catch-up blocked |
| 15.267 | `SKIP_REGRESSION thresh=1080 <= lastThresh=1140` | App A: out-of-order min.18 catch-up blocked |

**Mechanism:**

`extensionRebuildSlidingWindow()` at `DeviceActivityMonitorExtension.swift:757` uses `includesPastActivity: true` when registering the fresh 1–60 thresholds for the newly-added apps. This tells iOS: *"evaluate today's cumulative usage for these apps against the new thresholds."* iOS then fires catch-up threshold events for every minute of prior usage for those apps on the current day.

The catch-ups arrive **out of order** (the Apr 12 discovery). `SKIP_REGRESSION` blocks any catch-up whose `thresholdSeconds <= lastThreshold` — i.e., any low-minute catch-up arriving after a higher-minute one has already advanced `lastThreshold`. This is exactly the protection that prevents the Apr 13 inflation pattern.

**Net effect:** ~50% recovery of prior usage (7/14, 6/11 in observed data). The recovered fraction depends on the random order in which iOS delivers the catch-ups.

**This is intended behavior, not a bug.**

The alternative — accepting all catch-ups in arrival order — is exactly what produced the Apr 13 3600s ceiling. The partial undercount is the *safe* side of the trade-off that we explicitly chose via the Apr 13 revert.

**UX note:** User confirmed that partial (or zero) recovery for mid-day app additions matches user expectation. "Tracking starts when you add the app" is the natural user mental model; any prior-day recovery is a bonus, not a deficit. No user-visible feature gap.

**Optional future simplification (not planned, recorded for completeness):**

Flip `includesPastActivity: false` specifically on the newly-added-app code path, so new apps cleanly start at 0 rather than partial recovery. Keep `true` on the midnight rebuild and cross-day reconciliation paths where replay is genuinely needed. Benefits:
- New-app starts are unambiguously at 0 (no partial/random numbers to explain)
- Removes one of the `includesPastActivity: true` replay surfaces from the catch-up attack surface
- Does not affect ongoing tracking — once the app is registered, real-time events fire in order

Do not attempt during the current 3-day soak; only consider after the revert is committed and the system is stable.

### Mid-Day App Add — Catch-Up Storm with Stuck MIDNIGHT_PENDING (Apr 21, 2026)

**Status:** NON-PRIORITY — pending further user testing to assess real-world impact. Logged for reference; do not act without fresh reproduction evidence.

**Scenario:** After a week of stable tracking, user added a learning app (logicalID `50AB3A4D-2AD`) to the main-app selection at ~22:42. App was **not used at all today per user**, yet **19 min of false usage were recorded** within a single ~300 ms burst.

**Key log window (session `C71C2DE7`, 2026-04-21 22:42:27 → 22:42:28):**

- **22:39:26** — App launch detected stale `MIDNIGHT_PENDING` flag. No `MIDNIGHT_EXT_REBUILD_SUCCESS` / `MIDNIGHT_PENDING_CLEARED` entries appear anywhere between 2026-04-12 08:01:28 and 2026-04-21 22:39:27 — the flag had been stuck through multiple midnights. Foreground-triggered restart rebuilt thresholds for tracked set `{29E37F2B, 0454A303}` (count=2); **50AB3A4D was NOT in the set.**
- **22:42:04** — User added apps. `TRACKED_APP_IDS_SET count=3` adds `50AB3A4D`. `SLIDING_WINDOW 50AB3A4D... current=0min range=1-60`.
- **22:42:05** — `MONITORING_ALREADY_ACTIVE — skipping redundant startMonitoring` (first reload skipped).
- **22:42:11** — Second `MONITORING_RELOAD` with `count=2 {50AB3A4D, 29E37F2B}`, `MONITORING_START events=120` (actual `startMonitoring` call with `includesPastActivity: true` against fresh 1-60 window for 50AB3A4D).
- **22:42:27.571** — First event in the cascade already shows `currentToday=1020s lastThresh=3480s` — meaning prior (un-logged-in-excerpt) catch-ups already pushed `lastThreshold` to min.58 and `today` to 17 min before the visible burst begins.
- **22:42:27** — Out-of-order cascade: min.52 → 12 → 37 → 21 → 10 → 50 → **60 (RECORDED +120s → 1140s = 19 min)** → 17 → 2 → 6 → 41 → 8 → 23 → 27 → 32 → 16 → 45 → 4 → 55 → 59 → 22 → 19. All except min.60 blocked by `SKIP_REGRESSION`.
- **22:42:29** — `SLIDING_WINDOW_READ 50AB3A4D... → 19 min` confirms the false total now persisted.

**Why this is worse than the Apr 14 case:**

The Apr 14 incident (previous section) recovered ~50% of *real* prior-day usage when apps were added mid-day — partial undercount, within user mental model ("tracking starts when you add the app"). The Apr 21 incident reports **19 min of fabricated usage for an app the user asserts had zero actual usage today**. If the user's ground-truth is correct, this is either:

1. **Cross-midnight cumulative leakage**: `INTERVAL_START` at 00:00:56 may not have reset iOS's internal cumulative for this Application token — possibly linked to the stuck `MIDNIGHT_PENDING` flag meaning extension-side rebuild never ran cleanly on 2026-04-21 midnight (nor any midnight since 2026-04-13).
2. **Stale iOS Screen Time data** for the specific Application token being replayed on fresh `startMonitoring()`.
3. **User ground-truth is imperfect** and the app actually had 19+ min of genuine usage today that the user doesn't recall.

Cannot distinguish these without reproduction on a controlled device.

**Secondary concern — stuck `MIDNIGHT_PENDING`:**

Between 2026-04-12 08:01:28 (last `MIDNIGHT_PENDING_CLEARED`) and 2026-04-21 22:39:26 (flag re-detected on foreground), no `MIDNIGHT_EXT_REBUILD_SUCCESS`, no `MIDNIGHT_PENDING_CLEARED`, no midnight counter-reset logs appear in the extension debugLog — only bare `INTERVAL_END`/`INTERVAL_START` pairs. Possibilities:
- Extension-side midnight rebuild (`intervalDidStart()` day-change branch) is silently failing or its log lines are gated behind an unreachable branch.
- The app was never foregrounded long enough during those days for the stale flag to surface, so the visible "week of stability" may have been tracking running off the pre-2026-04-12 thresholds with SKIP_MIDNIGHT blanking all post-midnight events.
- Logs truncated or not flushed.

**Rapid successive `MONITORING_RELOAD` observation:**

The same 22:42 window shows 4 reloads in ~30 s (counts going 3 → 2 → 120 thresholds → 180 → 120 → 840) as the user edited the selection. Each `startMonitoring()` is a catch-up attack surface. Debouncing reloads in `ScreenTimeService` (e.g., 500 ms coalesce) would reduce the surface but is a secondary optimization.

**Not acting now — deferred until user completes further tests:**

User will run additional real-device tests to:
1. Confirm whether the recorded 19 min truly had no corresponding real usage (rule out user ground-truth error).
2. Check whether the stuck `MIDNIGHT_PENDING` is reproducible across device reboots / multiple days.
3. Assess how often real users hit this pattern in practice (mid-day app add after a stuck midnight).

If reproduction confirms real fabrication of usage (not just partial prior-day recovery), candidate remediations in priority order:

1. **Track newly-added apps explicitly.** In `scheduleActivity()` diff the incoming `tracked_app_ids` against the previous set; for added apps, register thresholds with `includesPastActivity: false` (per the Apr 14 "optional future simplification" already logged above). This cleanly pins new apps to 0 regardless of iOS cumulative state.
2. **Audit extension-side midnight rebuild logging.** Find why `MIDNIGHT_EXT_REBUILD_SUCCESS` never appears after 2026-04-12 — either the day-change detection is missing events or the log line is unreachable. Make midnight rebuild success/failure loudly observable.
3. **Debounce `MONITORING_RELOAD`** in `ScreenTimeService` to coalesce rapid selection edits into a single `startMonitoring()` call.

**Do not act without a fresh reproduction** — this could be user ground-truth error, a one-off from the stuck-pending-flag edge case, or a real regression in the mid-day-add path. The Apr 14 characterization was explicitly "no code change planned" on the same mechanism; we need stronger evidence before flipping that.

### Charging-Flush Overcounting + Wall-Clock Cap (Apr 23, 2026)

**Status:** SHIPPED — branch `fix/wall-clock-cap-and-full-logging`. Wall-clock cap is preventive only (today's already-corrupted totals were left to clear at midnight per locked decision). Real-device validation pending the next charging-flush incident.

**Incident.** Three Goal Complete notifications (60 / 120 / 136 min reward) fired at the lock screen within the same minute at 21:38 immediately after the user plugged the charger into a low-battery iPhone. User-reported real vs. saved totals at 21:52:

| App (logical) | Real today | Saved (`ext_usage_*_today`) | Overcount |
|---|---|---|---|
| Facebook (BB131A01) | 15 min | 60 min | +45 |
| Instagram (E8B1C8C6) | 5 min | 60 min | +55 |
| YouTube (C6DA269B) | 11 min | 59 min | +48 |
| X (DADD46EB) | 0 min | 12 min | +12 |
| Reward apps (51E884C1 / C0827256 / 739C4A42) | 0 / 0 / 0 | 30 / 13 / 8 | +51 total |

**Log evidence (extension session `D5B8ADF0`, 2026-04-23 21:38:20 → 21:38:22).** ~80 `THRESHOLD_CALL` events for 7 apps fired within ~2 seconds — including `min.60` for apps whose actual cumulative was 8–15 min. `SKIP_REGRESSION` blocked nearly all of them; only one `+60s` increment slipped through (`C0827256`). The visible 21:38 storm was therefore *not* what created the corruption — `lastThreshold` was already at 3540s/3600s for several apps when the storm began. The corruption was inflicted by **one or more earlier flush bursts on the same day** that no longer existed in the size-trimmed UserDefaults log.

**Mechanism (charge-state hypothesis).** iOS DeviceActivityMonitor defers extension threshold callbacks when the device is in low-power / idle / low-battery state. Plugging in the charger (or any state transition that wakes the extension) flushes the deferred queue all at once. Inside the queue, `eventDidReachThreshold` callbacks arrive non-sequentially (the Apr 12 out-of-order catch-up phenomenon), but more importantly they arrive *compressed in time* — `min.5`, `min.30`, `min.45`, `min.60` for the same app can land in the same 100 ms window. The pre-cap recording path used `delta = max(60, thresholdSeconds - lastThreshold)`, which credited the full delta regardless of whether real wall-clock time had elapsed.

**Fix — wall-clock cap on the recording path.** `setUsageToThreshold()` in `DeviceActivityMonitorExtension.swift` (same-day branch, line ~530) now bounds the credited delta by elapsed wall-clock seconds since the per-app last-event timestamp:

```swift
let lastEventTime = defaults.double(forKey: "ext_usage_\(appID)_timestamp")
let wallClockBaseline: TimeInterval = (lastEventTime > 0) ? lastEventTime : startOfToday
let wallClockElapsed = max(0, Int(nowTimestamp - wallClockBaseline))
let rawDelta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60
let delta = max(0, min(rawDelta, wallClockElapsed))
if delta < rawDelta {
    debugLog("WALL_CLOCK_CAP appID=\(appID.prefix(8))... raw=\(rawDelta)s capped=\(delta)s wallClock=\(wallClockElapsed)s ...")
}
```

Anchors:
- `ext_usage_<appID>_timestamp` is already written line-by-line on every recording (existing key, no migration).
- Cleared at midnight by `resetAllDailyCounters()` — the day-1 fallback to `startOfToday` keeps the cap biting on a flush burst that lands at 00:00:01 (otherwise `wallClockElapsed` would be `nowTimestamp` since 1970 and the cap would never trigger).

Behaviour:
- **Normal real-time use:** `wallClockElapsed ≈ 60s`, cap doesn't bite, +60s credit per minute. Healthy days produce zero `WALL_CLOCK_CAP` lines.
- **Flush burst:** `wallClockElapsed ≈ 0`, capped delta = 0. `lastThreshold` still advances (line 537 unchanged) so `SKIP_REGRESSION` semantics are preserved. The grand total of all events in the burst is bounded by elapsed wall-clock seconds across the whole burst, not by the sum of per-event deltas.
- **Edge case (acknowledged):** if iOS deferred events while the kid was *actively* using the app, those legitimate events would be under-credited. Accepted tradeoff because iOS only defers when idle / low-power; active foreground use fires events in real time.

**Scope decision (locked with user).** Prevention only. Today's already-corrupted totals (Facebook 60 / Instagram 60 / YouTube 59 / X 12 / reward 8/13/30) were left to clear at midnight via the existing `resetAllDailyCounters()` path. No recovery patch — the cap is forward-looking.

**Why "guess from fragments" was the meta-problem.** The Apr 23 root cause could not be confirmed because the 21:38 log was the only window we had — earlier-in-day bursts that actually wrote the corruption had been size-trimmed out of `extension_debug_log` (50 KB ring, 200 lines). User pushback: "we're making fixes based on the best understanding or guess. a full log would be closer to the reality than the guesses." Full-retention logging shipped in the same branch:

- **`ExtensionFileLogger.swift` (new, both targets).** Append-only `FileHandle` writer to `Logs/ext-log-YYYY-MM-DD.log` under the App Group container. **No size cap per day** (user decision — capture everything). 7-day rolling retention, auto-prune on first write of each new day. Memory-safe (no in-memory buffer, atomic small-write semantics for POSIX `O_APPEND` with no read-then-rewrite). Failure is silent so logging cannot break the recording path. The legacy size-trimmed UserDefaults `extension_debug_log` is preserved as a fallback.
- **All three extension loggers mirror to the rotating file:** `debugLog`, `lifecycleLog`, `midnightDiagnosticLog` each call `ExtensionFileLogger.shared.appendLine()` after their existing UserDefaults write. Lines from `lifecycleLog` are tagged `[LIFECYCLE]`, midnight `[MIDNIGHT]`, main-app `lifecycleLog` `[LIFECYCLE/SERVICE]`.
- **Battery context plumbing.** `AppDelegate.setupBatteryStateMonitoring()` enables `UIDevice.isBatteryMonitoringEnabled = true` and persists `last_known_battery_state` (Int 0/1/2/3 = unknown/unplugged/charging/full), `last_known_battery_level` (Float), `battery_state_timestamp` (TimeInterval) to the App Group on every state/level change AND on every scenePhase `.active`. The extension cannot read `UIDevice.batteryState` directly (sandbox returns `.unknown`), so it reads the persisted snapshot via a new `batteryContextString(defaults:)` helper that formats `bat=charging:42% age=12s`. Appended to: `EXTENSION_INIT`, `EXTENSION_KILLED`, `INTERVAL_START`, `INTERVAL_END`, the new `WALL_CLOCK_CAP` line, and every line written by `ScreenTimeService.lifecycleLog` (which covers `MONITORING_RESTART/DEAD/ALIVE/START`).
- **Diagnostics export UI** (new `DiagnosticsLogExportView.swift`). Reachable on the **child device** at Settings → DIAGNOSTICS → Export Extension Logs. Lists every retained `ext-log-*.log` file with size, shows the last battery snapshot, and offers Export-all (UIActivityViewController, native multi-file share — no zip dep) and Clear-logs (with confirmation). Reuses the existing module-level `ShareSheet` from `UsageAccuracyDiagnosticsView.swift` to avoid duplication. The row is *not* gated behind `#if DEBUG` because real-device incidents are exactly when this is needed.
- **Note on placement.** First implementation attempt put the export row on `ParentSettingsView` (parent dashboard). Wrong target — the extension only runs on the child device, so the rotating files only exist in the child's App Group container. Moved to `SettingsTabView` (child Settings tab, bottom DIAGNOSTICS section).

**Files modified / added.**

- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — wall-clock cap (lines ~530–545), `batteryContextString()` helper, battery context appended to `INTERVAL_START/END` and `EXTENSION_INIT/KILLED` lines, all three loggers mirror to `ExtensionFileLogger.shared`.
- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/ExtensionFileLogger.swift` — **new**, rotating-file logger.
- `ScreenTimeRewardsProject/ScreenTimeRewards/AppDelegate.swift` — battery monitoring observers + `static persistBatterySnapshot()`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/ScreenTimeRewardsApp.swift` — `AppDelegate.persistBatterySnapshot()` on every scenePhase `.active`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift` — `batteryContextString(defaults:)` helper; `lifecycleLog` auto-appends battery context to every line and mirrors to `ExtensionFileLogger.shared`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Views/SettingsTabView.swift` — `extensionLogExportRow` added at the top of the existing DIAGNOSTICS section (un-gated by `#if DEBUG`).
- `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Settings/DiagnosticsLogExportView.swift` — **new**, sheet UI.
- `ScreenTimeRewardsProject/ScreenTimeRewards.xcodeproj/project.pbxproj` — added `ExtensionFileLogger.swift` to both targets (extension uses explicit Sources phase; main app uses synchronized folder but the file lives outside it, so explicit `PBXBuildFile` entries were needed for both).

**Validation plan.**

1. **First-day smoke check (any time after install):** Settings → DIAGNOSTICS → Export Extension Logs. Confirm `ext-log-2026-04-23.log` exists, opens, contains `[LIFECYCLE/SERVICE] MONITORING_ALIVE … bat=charging:N% age=Xs` lines from main-app foregrounds. Plug/unplug the charger and re-export to confirm `bat=` flips. (Confirmed working 2026-04-23 23:27.)
2. **Charging-flush incident watch:** on the next real flush burst (charge plug-in after a low-battery period, or any BGTask wake after a long gap), expect a cluster of `WALL_CLOCK_CAP` lines and `RECORDED` deltas that stay tiny (≤ wall-clock).
3. **End-of-day comparison:** `ext_usage_<app>_today` totals at ~23:00 vs iOS Settings → Screen Time per app. Tolerance ±2 min/app. If they match across a charging cycle, the cap held under real conditions.
4. **Regression watch:** zero `WALL_CLOCK_CAP` lines during normal foreground use (e.g., kid actively in a learning app for 5 consecutive minutes). If the cap bites on legitimate usage, `nowTimestamp` and the persisted timestamp are using inconsistent time bases — investigate before relying on the fix.

**Out of scope (deliberately deferred).**

- Recovery of the Apr 23 corrupted totals (cleared at midnight per locked decision).
- Charge-state-aware throttling / debouncing of the recording path (the wall-clock cap supersedes the need for this).
- Investigation of *which* earlier burst on Apr 23 first poisoned `lastThreshold` for the four desynced apps — out of reach without the full-retention logger that was just shipped. Future incidents will be debuggable from the daily file alone.

#### Per-Event 60s Hard Cap (Apr 23, 2026 — same-day follow-up)

**First-event-after-gap hole exposed by the rotating logger.** Within hours of the wall-clock cap shipping, the new full-retention log captured a fresh incident triggered NOT by charging but by a **mid-day app set change** (user deleted one learning app and added another at 23:37:59, triggering `MONITORING_RELOAD` → `MONITORING_START` with `includesPastActivity:true`). iOS catch-up storm at 23:38:22 — same mechanism as the Apr 21 mid-day app-add documented above.

The wall-clock cap fired correctly on 14+ events in the burst (capped to 0–4 s). But four events sneaked through *before* any cap fired, in 0.249 s:

```
23:38:22.000  E8B1C8C6  +3420s  (57 min credited)
23:38:22.068  BB131A01  +2280s  (38 min credited)
23:38:22.170  C6DA269B  +420s   (7 min credited)
23:38:22.249  C0827256  +540s   (9 min credited)
```

**Net damage: +111 minutes of fake credit in 0.249 seconds.**

**Why those four bypassed the cap.** The wall-clock cap reads `ext_usage_<appID>_timestamp` for its baseline. For each of those four apps, that timestamp was last written at the prior burst around 21:38 (~2 hours stale). So `wallClockElapsed ≈ 7000 s`, `rawDelta = 3420 s` (E8B1C8C6 case), and `delta = min(3420, 7000) = 3420`. The cap allowed the full delta because, mathematically, two hours of wall-clock had genuinely elapsed since the last event for that app — it just couldn't tell that those two hours weren't all the kid actively using Instagram.

Once the first event for each app fired, `ext_usage_*_timestamp` updated to `nowTimestamp` and subsequent events in the same burst correctly saw `wallClockElapsed ≈ 0` and got capped. **The wall-clock cap is an in-burst defense; it does not defend against the FIRST event of a burst when the timestamp anchor is stale.**

**Fix — second cap layer.** Added a per-event hard cap of 60 s on top of the wall-clock cap:

```swift
let perEventCap = 60
let delta = max(0, min(rawDelta, wallClockElapsed, perEventCap))
```

Justification: a single threshold event represents the cumulative crossing exactly one 1-minute mark, so by construction at most 60 s of real-time progression can have occurred between consecutive events for the same app. Applied to the 23:38:22 incident: each of the four bypass events would have credited 60 s instead of 3420/2280/540/420 s. Total damage drops from 111 min to 4 min — **96 % reduction**.

**Trade-off (asymmetric, accepted).** If iOS legitimately skips intermediate thresholds (e.g., kid uses an app for 5 real min during a BGTask gap and iOS only delivers `min.5` without `min.1-4`), we credit only 60 s instead of 300 s — bounded ≤ 60 s per skipped threshold. We register all 60 1-min thresholds in the sliding window so iOS shouldn't skip in steady state. Bounded undercount is far preferable to unbounded overcount.

**Logging change.** The `WALL_CLOCK_CAP` line now also reports `perEvent=60s` so future log analysis can disambiguate which layer actually clamped a given event:

```
WALL_CLOCK_CAP appID=E8B1C8C6... raw=3420s capped=60s wallClock=7000s perEvent=60s sinceLastEvent=yes bat=charging:42% age=12s
```

**Validation.** Same end-of-day comparison as the parent fix. Specifically watch for: any new `WALL_CLOCK_CAP` line where `capped == 60s AND wallClock > 60s AND raw > 60s` — that's the second-layer kicking in (which means it's catching a first-event-after-gap burst that the wall-clock cap alone would have missed). Zero such lines on a healthy day with no app-set changes is the success criterion.

**Meta-observation: the rotating logger paid for itself in 12 hours.** Without the full-retention `ext-log-2026-04-23.log` the 23:38:22 incident would have been size-trimmed away just like the earlier-in-day bursts that originally poisoned the `lastThreshold` state. Instead we got the exact 0.249-second sequence with all four sneaking events visible AND the 14+ subsequent caps proving the wall-clock layer works in-burst. Diagnosis was a 5-minute log read instead of speculation.

### Apr 24, 2026 — Validation + Two More Bugs Exposed → New Branch

**Status:** SHIPPED on branch `fix/shield-race-and-newapp-pinning`. Two independent fixes; one commit each.

#### Wall-clock + per-event cap end-to-end validation

User intentionally reproduced yesterday's preconditions: drained iPhone to 4%, plugged in charger, opened main app shortly after. iOS DID flush a deferred catch-up burst at 16:33:59–16:34:18 against extension session `474803A7`. The two-layer cap engaged exactly as designed:

```
16:33:59.745  BB131A01  raw=780s   capped=60s  wallClock=25268s  perEvent=60s
16:34:00.512  C6DA269B  raw=1860s  capped=60s  wallClock=14808s  perEvent=60s
16:34:01.125  E8B1C8C6  raw=1140s  capped=60s  wallClock=9861s   perEvent=60s
```

These three events are the **target fingerprint** of the per-event cap — `raw>60s AND wallClock>60s AND capped=60s` — proof the second layer is the binding constraint. Without it: 13 + 31 + 19 = **63 min of fake credit**. With it: 3 min credited (legitimate 1-min minute-mark crossings that had genuinely accumulated during the deferral window). End-of-day Brain Coinz totals matched iOS Settings → Screen Time within ±1 min across all three apps.

Validation table:
| App | iOS Settings | Brain Coinz | Delta |
|---|---|---|---|
| Facebook | 36 min | 35 min | −1 |
| YouTube | 28 min | 28 min | 0 |
| Instagram | 5 min | 5 min | 0 |

The "111 min vs 3 min" damage-reduction framing from the parent section is now confirmed end-to-end under real failure conditions. Wall-clock cap = production-ready.

#### Bug 1: SKIP_SHIELDED race exposed at 16:34:22

The same charging-flush log captured a previously-unseen failure: reward app `51E884C1` was tracked all day with shield UP and `SKIP_SHIELDED` blocking 59 of its threshold events. **One event slipped past:**

```
16:34:22.196  SKIP_SHIELDED 51E884C1 min.44 (blocked) ✅
16:34:22.457  SKIP_SHIELDED 51E884C1 min.13 (blocked) ✅
16:34:22.692  EVENT 51E884C1 min.3 — NO SKIP_SHIELDED line
16:34:22.757  RECORDED 51E884C1 +60 ❌
16:34:22.870  GOAL_CHECK ... 51E884C1 goal NOT met → LEARNING_GOAL_BLOCK re-applies shield
```

Between `.471` and `.692` (~220 ms), `managedSettingsStore.shield.applications` did NOT contain 51E884C1's token. SHIELD_CHECK was rebuilding the shield set. The threshold filter reads the live store; during this narrow window it sees "not shielded" and falls through to the next filter, which records +60s.

**Fix (commit 2 on branch):** safety-net backstop in Filter 2. Keep the existing live-store check unchanged. After it returns "not in shield set", cross-check via `checkGoalMet()` — if the goal is NOT met, the shield SHOULD be up regardless of what the store says, so block anyway. New log line: `SKIP_SHIELDED_RACE`. Purely additive blocking — only over-blocks during the race window. Goal-met case still falls through (kid is in earned-reward-time use, recording is correct).

Why not "rewrite the filter to use only goal-config evaluation": that path would risk regressions in the reward-time-exhausted case (where goal IS met but shield is re-applied). Keeping the live store as primary and adding the goal-config as backstop is purely additive and matches the locked principle "fail closed, only over-block".

#### Bug 2: Newly-added app records bogus usage (third reproduction)

`BED599FB` was added at 12:46:02 with `current=0min range=1-60`. User confirms zero real usage all day. At 16:33:59 — 3.5 hours later, during the same charging-flush burst — iOS fired `min.45` (2700s) for it; the `NEW_DAY` path credited `+60s` (the floor for the first event of the day). +60s of false credit on an unused app.

This is the **third reproduction** of the pattern Apr 21's "candidate remediation 1" was written for: iOS replays historical cumulative for the Application token into the fresh sliding window because we register events with `includesPastActivity:true`. The Apr 14 entry deferred fixing it ("partial prior-day recovery"), Apr 21 deferred again pending fresh repro, Apr 24 cleared the gate.

**Fix (commit 1 on branch):** in `scheduleActivity()`, capture the previously-tracked app set BEFORE overwriting `tracked_app_ids`. Compute `newlyAddedIDs = newSet − previousSet`. For those apps, register their `DeviceActivityEvent` with `includesPastActivity:false` so iOS only fires events for usage occurring AFTER registration. Existing apps keep `includesPastActivity:true` so cross-midnight + BGTask-gap recovery is unchanged. Per-app, not all-or-nothing.

`MonitoredEvent.deviceActivityEvent()` was extended to take a `includesPastActivity: Bool = true` parameter (default preserves prior behavior).

New log lines:
- `NEW_APPS_PINNED count=1 ids=BED599FB — registered with includesPastActivity:false`
- Existing `SLIDING_WINDOW` lines now suffix `[PINNED:noPastActivity]` for newly-added apps.

First-ever launch (previously-tracked is empty) treats every app as newly-added → clean slate, no historical replay. Correct for fresh install. App removed-then-re-added on the same day will be flagged as new and lose its prior in-day tracking — accepted tradeoff per Apr 14.

#### Branch hygiene

Two-branch model intentional: `fix/wall-clock-cap-and-full-logging` is the validated baseline (yesterday + today's morning evidence), `fix/shield-race-and-newapp-pinning` adds the two new fixes on top. If a regression appears tomorrow, `git log --oneline` cleanly bisects which fix introduced it. Honoring the principle established in the Apr 16 ground-truth entry: validate each change end-to-end before stacking the next.

#### Out of scope (deliberately deferred again)

- iOS-side root cause: why `includesPastActivity:true` causes iOS to replay potentially-cross-day cumulative is not investigated. We don't control iOS — we adapt around it.
- The "reward-time-exhausted" race (goal met but shield being re-applied due to exhaustion) is structurally unaddressed by Fix 1; a future commit can add a parallel backstop reading `usage_<rewardAppID>_today` ≥ earned reward minutes if it's ever observed in practice.
- Debouncing rapid `MONITORING_RELOAD` calls (Apr 21 doc remediation #3) — the cap+pin combo makes this less urgent. Defer until evidence justifies.

### Apr 25, 2026 — Pin Fix Reproduction → Two Layers Added

**Status:** SHIPPED on branch `fix/shield-race-and-newapp-pinning`. One commit on top of the Apr 24 pin fix. **Device-validated 2026-04-26**: user added apps mid-day with pre-existing cumulative for the Application token; zero bogus +60s credit observed (vs. three reproductions on Apr 14/21/24/25 prior to this fix).

**Symptom.** Newly-added apps still recording bogus +60s the same day (third reproduction *after* the Apr 24 single-layer fix). User report: "happened for some additions today. not all." Log: `Build Reports/ext-log-2026-04-25.log`.

**Two distinct failure modes, both from the same log.**

#### Mode 1: Pin lost across reloads — `642B7130`

| time | event | pin state |
|---|---|---|
| 18:28:13 | `NEW_APPS_PINNED count=1 ids=642B7130` | pinned (`includesPastActivity:false`) |
| 18:28 → 19:24 | (no threshold events) | pin holds, iOS quiet |
| 19:24:15 | `scheduleActivity()` re-runs (no app added) | **pin LOST** — re-registered with `includesPastActivity:true` |
| 19:24:27 | `scheduleActivity()` re-runs (E54C1C9E added) | still un-pinned for 642B7130 |
| 19:24:32 | `NEW_DAY` thresh=2160s → +60s; +1s; +4s = **65s bogus credit** | `lastThreshold=3540s` poisoned |

**Root cause.** The Apr 24 diff `newlyAddedIDs = newSet − previouslyTrackedIDs` is computed against `tracked_app_ids`, which we *just wrote* on the previous call. So an app added on call N is not in `newlyAddedIDs` on call N+1. The pin only survives the very first reload after registration.

#### Mode 2: `includesPastActivity:false` is unreliable — `E54C1C9E`

| time | event |
|---|---|
| 19:24:27 | `NEW_APPS_PINNED count=1 ids=E54C1C9E — registered with includesPastActivity:false` |
| 19:24:49 | (just **22 seconds later**) `NEW_DAY` thresh=1440s → +60s; thresh=3060s → +0s = **60s bogus credit**, `lastThreshold=3060s` poisoned |

E54C1C9E was *correctly* pinned with `includesPastActivity:false`. No intervening reload. iOS still fired backed-up threshold events for cumulative usage that occurred BEFORE registration but WITHIN the active monitoring interval (which started at 00:01:09 today).

**Conclusion: `includesPastActivity:false` only suppresses cross-INTERVAL boundaries (midnight rollovers), not within-interval pre-registration cumulative for the Application token.** The Apple-flag defense is structurally insufficient on its own. The Apr 24 end-to-end validation (Facebook/YouTube/Instagram) didn't cover the "add an app mid-day with significant prior cumulative" case.

**Secondary damage from both modes.** The first non-blocked event sets `lastThreshold` to a high value (3060–3540s). Subsequent same-day SKIP_REGRESSION then blocks REAL future usage events until cumulative crosses that ceiling — silently undercounting for the rest of the day.

#### Fix (two-layer)

**Layer 1 — Persistent pin set (`ScreenTimeService.swift`).** Replace the per-call diff with a sticky daily set:
- Read `pinned_apps_today` (date-stamped) from UserDefaults at the start of `scheduleActivity()`.
- Union in any first-call newly-added IDs; restrict to currently-tracked apps.
- Write back. Register with `includesPastActivity:false` for everything in the union.
- Set `app_first_seen_today_<id>` only on first appearance today; never overwrite on subsequent reloads (so the timestamp is stable across the day).
- `resetAllDailyCounters()` clears `pinned_apps_today`, `pinned_apps_today_date`, and `app_first_seen_today_<id>` for every tracked app at midnight.

This holds the pin for 642B7130 across all today's reloads (Mode 1).

**Layer 2 — `SKIP_PIN_REPLAY` filter (`DeviceActivityMonitorExtension.swift`).** Inserted between Filter 2 (SHIELDED) and Filter 3 (REGRESSION). Since the Apple flag can't be trusted (Mode 2), anchor each pinned app at registration time and reject events claiming impossible cumulative:

```swift
let firstSeenAt = defaults.double(forKey: "app_first_seen_today_\(appID)")
if firstSeenAt >= startOfToday {
    let wallClockSincePin = nowTimestamp - firstSeenAt
    let allowedCeiling = wallClockSincePin + 60   // +60s buffer for the legit first event
    if Double(thresholdSeconds) > allowedCeiling {
        return false  // SKIP_PIN_REPLAY
    }
}
```

**Walk-through.**
- E54C1C9E: pinned 19:24:27, event 19:24:49 thresh=1440s → wallClock=22s, ceiling=82s, **1440 > 82 → DROP** ✓. `lastThreshold` not poisoned. Future real usage tracked normally.
- 642B7130 with persistent pin: pin holds through the 19:24:15 reload, so iOS may not fire historical replays at all. If iOS does fire post-reload (Apple flag unreliable), wallClock=3380s, ceiling=3440s, min.36 (2160s) → 2160 < 3440 → PASS. Indistinguishable from real 36-min usage during the 56-min window.
- Real first usage: kid uses freshly-pinned app for 1 min → min.1 thresh=60s arrives at wallClock≥60s → 60 ≤ 120 → PASS ✓.

**Trade-off.** A burst of legitimately-skipped thresholds (e.g., 5 min of usage during a BGTask gap, iOS only delivers `min.5`) accruing within 60s of pin would be over-blocked. Bounded undercount on the rare pin-burst overlap is far preferable to unbounded overcount + lastThreshold poisoning. Same asymmetric trade-off as the per-event 60s wall-clock cap.

**Validation.** Same end-of-day comparison: add an app mid-day to a device with significant prior cumulative for that Application token. Expect zero bogus credit at registration, real usage post-pin tracked correctly. Watch for `SKIP_PIN_REPLAY` log lines with `thresh > wallClock+60` ratios — those are the events that previously poisoned `lastThreshold`.

#### Out of scope

- We do not block events with `thresh ≤ wallClock+60` after a long quiet period (642B7130 case 56 min in). Without per-app cumulative-at-pin-time tracking we can't distinguish replay from real. Accepted: the existing per-event 60s wall-clock cap bounds damage to ≤60s in this ambiguous case.
- App removed-and-re-added the same day: the first-seen anchor stays at the original add time (we never overwrite). Prior recorded usage is preserved per the user's invariant; new usage continues from where it was.

### Apr 26–27, 2026 — Pooled Time Bank Shield Gate (Devices A + B)

**Status:** SHIPPED on branch `fix/shield-race-and-newapp-pinning` as a follow-up to the Apr 24/25 work. Validation pending end-of-day device check on 2026-04-27.

**Two same-day device incidents from 2026-04-26 surfaced the same defect, in opposite polarities.** Both devices proved that the extension's shield gate was threshold-aware (today's per-goal `minutesRequired` met?) but **not pool-aware** (does the child have any carry-forward Time Bank credit?). The fix routes the main app's pre-existing `cumulativeAvailableMinutes` formula to the extension via App Group UserDefaults, so the extension can gate shield decisions on the same pooled balance the Dashboard renders.

#### Device A — Over-spend (`ext-log-2026-04-26 2.log`)

**Symptom (user-reported).** Reward app `06909776` used 84 min vs 64 min earned. +20 min over-spend.

**Log evidence.**
- iOS internal counter (visible via threshold value): ~99 min cumulative on `06909776`
- Extension recorded: `newToday=4022s ≈ 67 min`
- Final-state delta: 32 min iOS-vs-recorded gap = 28 min that fired during SHIELDED period (events 09:26→10:28 with `min=1` → `min=29`, all `SKIP_SHIELDED`) + ~4 min lost to per-event 60s cap during catch-up bursts
- Repeated unshield/reshield ping-pong all day for `06909776`: `REMOVED shield` at 10:51, 10:56, 11:00, 11:31, 11:47, 12:31, 12:31:57, 13:06, 13:46…

**Root cause (two compounding).**
1. **No reward-balance gate on shield removal.** `checkAndUpdateShields()` (`DeviceActivityMonitorExtension.swift:1030`) removed the shield as soon as `goalMet=true`. Once today's learning crossed the per-goal threshold, the unlock pass kept stripping the shield even after the child had used all earned reward time. The companion `checkAndBlockIfRewardTimeExhausted()` Check 3 (line 1339–1367) *would* re-shield, but uses the extension's tracked `usage_<id>_today` which is silently low (under-counted by Apr-23 wall-clock cap during post-unlock catch-up bursts).
2. **Per-event 60s cap discards legitimate post-unlock catch-up.** When the shield lifts at T₀ and the child plays for 9 min until T₁ (first event fires), iOS fires queued thresholds 1→9 in rapid succession. The first event credits 60s; subsequent in-burst events see `wallClockElapsed≈0` and credit 0. ~9 min real usage → 1 min recorded.

#### Device B — Under-spend (`ext-log-2026-04-26 3.log`)

**Symptom (user-reported).** Time Bank shows `41 MIN AVAILABLE`. All 12 reward apps stayed shielded all day. Child blocked from spending legitimate credit.

**Log evidence.**
- Today: 7 min learning on `50AB3A4D`, ratio 1:4, no goal threshold (15 / 30 min) crossed
- 194× `goalMet=false`, 0× `goalMet=true` all day
- 175 `SKIP_SHIELDED` + 92 `SKIP_SHIELDED_RACE`, all reward apps
- Zero `RECORDED appID=<reward>` lines — extension correctly tracked zero reward usage
- 0 `REMOVED shield` lines all day

**User-confirmed math for the 41.**
```
historical = (lifetime_learning − today_learning) × ratio − lifetime_used
           = (26 − 7) × 4 − 35
           = 41
```
Time Bank is correctly computed by `AppUsageViewModel.cumulativeAvailableMinutes` (`AppUsageViewModel.swift:210`). It IS legitimate available credit — 41 min the child has earned through past learning that they can spend any day, regardless of whether today's threshold is crossed.

**Root cause.** The extension's shield gate uses today's `checkGoalMet()` exclusively. It has no awareness that `historicalRemaining` exists. So even with a healthy 41-min pool, the gate kept the shield up because "today's 15-min threshold isn't met."

#### Bridge contract

```
Pool balance =
    main_app_written: bank_historical_remaining_minutes
  + extension_computed: sum over UNIQUE learning apps of
        (today_usage >= lowestThreshold for that app)
        ? round(today_usage_minutes * first_matching_ratio)
        : 0
  − extension_computed: sum over reward apps of
        usage_<rewardID>_today / 60

Shield-on conditions for a reward app (any one is sufficient):
  - downtime window
  - dailyLimit == 0
  - usage_<rewardID>_today >= dailyLimit (and dailyLimit < 1440)
  - pool <= 0

Otherwise: shield off.
```

**Source-of-truth invariant.** If the main app's `AppUsageViewModel.cumulativeAvailableMinutes` formula (line 210) ever changes, the extension's `computeEffectivePoolBalance()` MUST be updated in the same commit. Both must produce identical numbers for any given state.

#### Three-layer fix

**Layer 0 — Main app writes slow-moving historical baseline to App Group.**

New keys (single child, pooled):
```
bank_historical_remaining_minutes        Int — pool baseline (slow-moving)
bank_historical_remaining_lastUpdated    TimeInterval — staleness guard
```

Written by main app at three sites:
1. End of `syncGoalConfigsToExtension()` (`ScreenTimeService.swift:4123`) — alongside `extensionShieldConfigs` write
2. End of `handleMidnightTransition()` (`ScreenTimeService.swift:1909`) — after daily reset folds today's earnings into history
3. On scenePhase `.active` (new hook in `ScreenTimeRewardsApp.swift`) — catches foreground-triggered recomputes

Value: `UsagePersistence.getHistoricalRemainingMinutes(learningIDs:rewardIDs:learningRatios:)` (`UsagePersistence.swift:270`) — already exists, exact formula the bank uses for its historical component.

**Why historical only (not the full bank value).** The today-component changes minute-by-minute as learning accrues; user confirmed main app is backgrounded during learning. The extension already has ratio + threshold from `extensionShieldConfigs` and raw seconds from its own `usage_<id>_today` writes — it can compute today's earned/used itself. Slow-moving baseline + extension-live decrement = correct effective balance with no main-app wake-up needed.

**Layer 1 — Extension uses pooled balance as shield gate.**

New helper `computeEffectivePoolBalance(configs:defaults:) -> Int` placed after `calculateEarnedMinutes()` (line 1415). Implements the bridge contract above. Uses UNIQUE learning apps, lowest threshold, first-matching ratio — byte-identical to `AppUsageViewModel.totalEarnedMinutes` (line 156).

Rewrites:
- `checkAndUpdateShields()` (line 1030–1078): removes per-config `isGoalMet` check; replaces with single pool-balance check. Per-app gates (downtime / dailyLimit==0 / dailyLimit-exceeded) preserved as overrides.
- `checkAndBlockIfRewardTimeExhausted()` Check 2 + Check 3 (line 1310–1367): collapsed to single `pool <= 0` re-shield. Check -1 (dailyLimit==0), Check 0 (downtime), Check 1 (dailyLimit-exceeded) preserved unchanged.

New log lines:
- `SHIELD_CHECK: pool=Nmin` — replaces per-config goalMet logging
- `POOL_EMPTY_BLOCK: <id>... pool=Nmin` — replaces `LEARNING_GOAL_BLOCK` and the old `rewardTimeExpired` block

**Layer 2 — Wall-clock cap relaxation for first event after unlock (carries Device A's compound cause).**

`setUsageToThreshold()` cap block (line 622–628) extended to anchor on `ext_unlock_<appID>_timestamp` (already written by `recordUnlockState()` at line 1066, currently read by no one). For the FIRST event after an unlock (when `unlockTime > lastEventTime`), `perEventCap` is raised to `max(60, now - unlockTime)`. Subsequent in-burst events see `lastEventTime≈now` and fall back to 60s — burst still bounded by `(T₁ − T₀)`.

Cap-line debug extended with `unlockAge=Ns perEventCap=Ns` for forensic disambiguation.

#### Symptom alignment after fix

| Device | Pool | Per-app limits OK? | Result |
|---|---|---|---|
| A (after spend) | ≤ 0 | yes | All reward apps stay shielded; no more unshield/reshield ping-pong |
| B (today) | 41 > 0 | yes | All reward apps unshield on next event; child can spend the 41 min |

#### Validation

1. **Device B reproduction:** ratio 1:4, manipulate state so `bank_historical_remaining_minutes > 0` and today's learning < threshold. Open reward app. Expect: shield lifts on first event. Log shows `SHIELD_CHECK: pool=Nmin` then `✅ REMOVED shield` even with no `goalMet=true` line.
2. **Device A reproduction:** small earned (5 min), cross threshold, use reward app for >5 min. Expect: shield re-applies once pool hits 0, log shows `POOL_EMPTY_BLOCK`, no unshield/reshield ping-pong.
3. **Pool de-dup:** two reward apps linked to the same learning app with different thresholds (15 / 30). Do 20 min learning. Expect: today_earned credits 20 × ratio ONCE (using 15-min threshold), not twice. Extension's `pool=Nmin` matches Dashboard `MIN AVAILABLE`.
4. **Layer 2 catch-up:** earn ≥10 min, wait for unshield, idle 5 min, then use reward 4 min. Expect: first `RECORDED` after gap credits ~4 min in one event. New log line `WALL_CLOCK_CAP ... unlockAge=540s perEventCap=540s` for first event, `perEventCap=60s` thereafter.
5. **End-of-day ground-truth:** at ~23:00 compare `usage_<id>_today` to iOS Settings → Screen Time (±2 min/app). Compare extension's `pool=Nmin` to Dashboard `MIN AVAILABLE` (must be identical).

#### Out of scope (deferred)

- Per-reward-app pool partitioning (user confirmed pooled is correct).
- Manual parent grants — no UI surface today.
- Recovering Device A's already-over-spent minutes — forward-looking only.
- CloudKit-synced cross-device pool — `bank_historical_remaining_minutes` is App-Group local per device.
- Live-update of pool during background ratio changes — main app must foreground for new ratio to reach extension.
- Pre-unshield iOS-counted minutes (Device A's 28-min mystery cumulative on a "shielded" app): pool gate makes the question moot for spending decisions.

### Apr 30, 2026 — Stale Catch-Up `lastThreshold` Poisoning (the Apr 12 bug, now closed)

**Status:** SHIPPED on branch `fix/stale-catchup-lastthreshold-poisoning`. v1 (`delta < rawDelta` gate, Apr 30) shipped, validated wrong same day (123 false positives, `SKIP_REGRESSION` disabled). v2 (`rawDelta > perEventCap` gate, Apr 30) shipped same day, validated correct on May 1 against a real iOS-restart catch-up flood at 13:37:58 — gate fired only on real catch-ups, no rest-of-day blackout. v3 (`max(prior, newToday)` on hold instead of pure-hold, May 1) addresses the v2 quirk where `lastThreshold` stayed frozen post-flood and disabled `SKIP_REGRESSION` for the rest of the day. Resolves the §"Out-of-Order Catch-Up Events (Apr 12, 2026)" item open since Apr 12.

#### Apr 29 incident — full-day blackout, all 8 apps

**Source:** `ext-log-2026-04-29.log` (full-retention rotating logger from the Apr 23 ship).

**Symptom.** Last `RECORDED` event of the day: `14:35:28`. From 14:35:28 → 23:59:59 (≈ 9.4 hours), every threshold call rejected as `SKIP_REGRESSION`. Every tracked app's persisted `ext_usage_*_today` froze at its 14:35 value. iOS Screen Time captured the real afternoon usage; our extension recorded zero of it.

**Trigger sequence.**
1. **00:00 → 14:35** — recording works normally. Session `F33523A9` runs continuously (no `MONITORING_RESTART` in this window — the last one was 00:09:26).
2. **~14:18 → 14:35** — iOS deferred all DeviceActivity callbacks for ~16 min. Device on battery 25 %, idle. Same `age=996s` since previous event for every app in the eventual flood.
3. **14:35:14.271 → 14:35:28.708** — iOS flushed the deferred queue **out of monotonic order**. For each app, the highest-numbered threshold arrived first:

   | App | First event of flood | wallClock age | currentToday before | rawDelta | Cap clamped to |
   |---|---|---|---|---|---|
   | E54C1C9E | `min.55` (thresh=3300s) | 9 623 s (2.7 h) | 1 109 s | 2 160 s | 60 s |
   | FAE1D45B | `min.35` (thresh=2100s) | 27 060 s (7.5 h) | 1 455 s | 600 s | 60 s |
   | BB131A01 | `min.18` (thresh=1080s) | 456 s | 444 s | 600 s | 60 s |

4. **Apr 23 wall-clock + per-event 60s cap held perfectly** — every per-event credit was clamped from raw 600 / 2160 / 2820 s down to 60 s. **No fake hours.** The `RECORDED` lines show `oldToday → newToday` deltas of 60 s, then 1 s / 3 s / 5 s for in-burst events as `wallClockElapsed` collapsed to ~0. Total today-credit damage across 8 apps: ≈ 1 minute of fake credit.
5. **But `lastThreshold` was unconditionally written to `thresholdSeconds` on every successful record** (`DeviceActivityMonitorExtension.swift:652`, pre-fix). Within 14 seconds the highest-numbered events walked `lastThreshold` to **3600 s** (60 min — the top of the registered 1–60 sliding window) on every app:
   ```
   14:35:14.594  E54C1C9E  thresh=3300s   ← lastThresh: 1140 → 3300
   14:35:18.712  BB131A01  thresh=3600s   ← lastThresh: ... → 3600
   14:35:21.058  739C4A42  thresh=3600s
   14:35:23.245  E54C1C9E  thresh=3600s
   14:35:28.708  FAE1D45B  thresh=3600s
   ```
6. **14:35:18 — `EXT_REBUILD` registered fresh sliding windows** anchored on real cumulative (`E54C1C9E current=19min → window 20-79`, `FAE1D45B current=25min → window 26-85`, `BB131A01 current=8min → window 9-68`). Top of each new window covers thresholds up to 3 660 / 5 100 / 4 080 s. Almost every threshold inside the new windows is ≤ 3 600 s.
7. **14:35:28 onward — `SKIP_REGRESSION` rejects everything.** Real-time threshold events from the rebuilt windows fired correctly (`min.7, min.8, …, min.41` for various apps over the next 6 hours of log) but every one hit `threshold ≤ lastThreshold=3600 (same day)` and was discarded.

**Recovery.** None mid-day. Auto-recovery at 00:00:02 next day via `intervalDidStart()` → `MIDNIGHT_RESET_COMPLETE — lastThreshold reset for 8 apps`.

#### Why this had stayed open since Apr 12

The Apr 12 §"Out-of-Order Catch-Up Events" entry described the same mechanism but scoped it to *intraday restarts only*: `WINDOW_TOP_HIT` rebuilds, manual restarts, `scheduleActivity()` restarts. Apr 29 disproves that scope. **The same failure fires after an iOS deferred-batch flush with no restart at all** — no `MONITORING_RESTART` between 00:09 and the 14:35 flood, session `F33523A9` unchanged across the boundary. The trigger condition reduces to: *iOS held a backlog of threshold callbacks long enough that the eventual flush is out-of-order*. Idle device + low battery is sufficient.

The Apr 23 ship intentionally preserved `lastThreshold` advancement on the recording path (line 1497 of this doc): *"`lastThreshold` still advances (line 537 unchanged) so `SKIP_REGRESSION` semantics are preserved."* That decision was correct for bounding overcounting damage but knowingly left this undercounting half open. Apr 29 is the cost of that tradeoff finally cashing.

#### Fix — `lastThreshold` hold-on-clamp (Option A)

Single-line gate around the existing `defaults.set(thresholdSeconds, forKey: lastThresholdKey)` write in `setUsageToThreshold()` (line ~669):

```swift
let wasStaleCatchup = rawDelta > perEventCap
if wasStaleCatchup {
    debugLog("LASTTHRESH_HOLD appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s held lastThresh=\(lastThreshold)s — stale catch-up (raw=\(rawDelta)s > perEventCap=\(perEventCap)s, credited=\(delta)s)", defaults: defaults)
} else {
    defaults.set(thresholdSeconds, forKey: lastThresholdKey)
}
```

**Invariant.** `lastThreshold` advances unless the threshold gap (`rawDelta = max(60, thresholdSeconds - lastThreshold)`) exceeds the maximum real time one event can legitimately represent (`perEventCap`). When `rawDelta > perEventCap` the threshold has jumped further than real time could justify — by definition iOS skipped intermediate minutes, i.e. a catch-up. Apr 29 examples: `rawDelta = 2160s` for E54C1C9E `min.55` against prior `lastThresh=1140s`; `rawDelta = 600s` for FAE1D45B `min.35` against prior `lastThresh=1500s`. Both ≫ 60 s.

**Why `rawDelta > perEventCap` and not `delta < rawDelta` (v1 mistake).** The very first cut of this fix used `delta < rawDelta` (i.e. *the wall-clock cap fired*) as the trigger. Validated wrong on Apr 30 day 1: iOS does not fire `eventDidReachThreshold` callbacks on exact 60-s boundaries — natural jitter of ~1 s between successive minute thresholds means `wallClockElapsed = 59 s` on healthy real-time events, so the wall-clock cap clamps `delta` from 60 → 59 even when nothing is stale. Result: 123 false-positive `LASTTHRESH_HOLD` lines across a normal day, `lastThreshold` pegged at 60 s for every app for the whole day, `SKIP_REGRESSION` effectively disabled. Counting still came out correct because the wall-clock cap independently bounded credit, but the safety net was gone. Switched to `rawDelta > perEventCap` — which keys off the *threshold gap* (intrinsic to the event), not the *clamp outcome* (sensitive to sub-second timing). Healthy real-time has `rawDelta = 60 = perEventCap` always; only iOS-skipped-minutes catch-ups produce `rawDelta > 60`.

**Post-unlock case is implicit.** `perEventCap` is already inflated to elapsed-since-unlock for the first event after an unlock (Apr 26–27 layer 2). A legitimate post-unlock catch-up has `rawDelta ≤ perEventCap` and naturally falls under the gate. No `!isFirstEventAfterUnlock` exception is needed; the inflated cap handles it.

**Why advancing to `max(prior, newToday)` instead of pure-hold (v3 May 1).** v2 used pure-hold (`lastThreshold` stays at its pre-flood value). Validated on May 1's log: works for the primary bug (no rest-of-day blackouts) but introduces a quirk — once held, `lastThreshold` never advances even on subsequent legitimate real-time events, because their `rawDelta` against the frozen baseline grows past `perEventCap`, and the gate keeps classifying them as "stale." Counting stays correct (wall-clock cap bounds `delta`), but `SKIP_REGRESSION` is effectively disabled for that app for the rest of the day, and the log misleadingly tags real-time events as stale. v3 advances `lastThreshold` to `max(prior, newToday)` on hold — `newToday` never lies (it's the credited high-water mark), so it's a safe lower bound. Future real-time events have `rawDelta = max(60, threshold − newToday) ≈ 60 = perEventCap` → not stale → advance normally. Re-arms the safety net.

#### What today's log would have looked like with the fix

Apply the rule to the 14:35:14 flood for E54C1C9E:

| Event | thresh | lastThresh before | delta credited | lastThresh after (pre-fix) | lastThresh after (post-fix) |
|---|---|---|---|---|---|
| min.55 (stale) | 3300 s | 1140 s | 60 s | **3300 s** | 1140 s (held) |
| min.30 (stale) | 1800 s | 3300 s → REJECT | — | 3300 s | 1140 s → ACCEPT, credit 0–1 s, hold |
| min.31 (stale) | 1860 s | … | — | 3300 s | 1140 s → ACCEPT, credit 0 s, hold |
| (real-time event 14:50, after flood) | 1200 s | 3300 s → REJECT | — | 3600 s | 1140 s → ACCEPT, advance |

Net behaviour: post-fix, the in-burst stale events still get rejected on per-event cap (delta=0) so they don't corrupt today's count, **and** real thresholds firing later in the day pass `SKIP_REGRESSION` against the unchanged `lastThreshold=1140 s` and resume normal recording.

#### Validation

1. **Healthy-day regression check.** First validation day with the fix in production: zero `LASTTHRESH_HOLD` lines during normal foreground use (kid actively in an app for 5 consecutive minutes). If `LASTTHRESH_HOLD` fires on legitimate real-time events, the gate condition is wrong and `lastThreshold` will stop advancing entirely — investigate before relying on the fix. **Apr 30 v1 failed this check** (123 false positives in one day with the `delta < rawDelta` trigger) and was patched to `rawDelta > perEventCap` the same day. Note: `WALL_CLOCK_CAP` and `LASTTHRESH_HOLD` are NOT expected to co-occur 1:1 — `WALL_CLOCK_CAP` fires routinely on ~1 s timing jitter; `LASTTHRESH_HOLD` should fire only on real catch-ups.
2. **Charging-flush burst.** Plug charger after low-battery period, or background the device for 15+ min. Expect: cluster of `WALL_CLOCK_CAP` + `LASTTHRESH_HOLD` pairs. *Subsequent* real-time events (next foreground use of the same app) should record normally — i.e., **no `SKIP_REGRESSION` rejections of thresholds within the post-burst sliding window for the rest of the day.**
3. **Apr 29 replay.** Reproduce by leaving device idle on battery for ~16 min mid-day, then resume. Expect the recording path to quickly self-heal: a few `LASTTHRESH_HOLD` lines during the flush, then normal `RECORDED` resumes within one threshold interval (~60 s) of the kid actually using a tracked app again.
4. **End-of-day ground truth.** `ext_usage_<id>_today` at ~23:00 vs iOS Settings → Screen Time per app, ±2 min/app, across a full day that includes at least one charging-flush event. Apr 29 was the negative baseline — real usage hours that vanished. Post-fix should track within tolerance.
5. **Pool integrity follow-through.** Because the Apr 26–27 pool-aware shield gate reads `usage_<id>_today` for both reward consumption and pool draining, frozen usage caused under-blocking on Apr 29 (pool stayed artificially full → reward apps stayed unlocked past earned time). Validate post-fix by confirming `pool=Nmin` lines decrement smoothly across a flush burst day.

#### Out of scope (deliberately deferred)

- **Recovery of Apr 29's lost 9.4 hours.** Forward-looking only. iOS Screen Time has the ground truth but the extension cannot read it back; the lost minutes are unrecoverable.
- **Restart-time `lastThreshold` reset.** Apr 12 documented that `intervalDidStart()` MUST reset `lastThreshold` at midnight (already shipped) and MUST NOT reset it on intraday restarts (Apr 13 revert — re-introducing it caused phantom inflation). Today's fix is orthogonal to that decision and does not change either rule.
- **Sorting iOS catch-up batches before processing.** iOS does not surface batch boundaries to the extension; sorting is not implementable from the callback API. The hold-on-clamp rule sidesteps the ordering problem entirely by treating the unreliable `thresholdSeconds` value as advisory rather than authoritative when the cap fires.
- **Bug A (Apr 12 §"Out-of-Order Catch-Up Events") variant during legitimate intraday restart.** The original Apr 12 entry's restart scenario also produces stale catch-ups, and on a restart the highest-numbered event can fire BEFORE `WALL_CLOCK_CAP` would clamp it (because `lastEventTime` may be hours stale → `wallClockElapsed` huge → first event credits its full rawDelta unclamped). Apr 23's per-event 60s cap handles this in steady state, but restarts that coincide with a legitimate catch-up (e.g., kid actively using app at the moment of restart) will still under-credit by ≤60 s per skipped threshold. Bounded undercount, accepted as the documented Apr 23 tradeoff.

### May 1, 2026 — v2 Validated, v3 Shipped, Phantom-Threshold Replay Discovered

**Status:** v2 (`rawDelta > perEventCap` gate) validated correct on May 1 against a real iOS-driven catch-up flood. v3 (`max(prior, newToday)` on hold instead of pure-hold) shipped as `ddcb2c5` on `fix/stale-catchup-lastthreshold-poisoning`. New separate finding: iOS DeviceActivityMonitor replays the entire registered threshold set for every monitored app on iOS-initiated activity restart — phantom +60 s credit per affected app. Decision: **don't ship a phantom-credit fix yet; watch and measure first.** No code change for the phantom replay this session.

#### v2 validation — real flood at 13:37:58

iOS-driven `INTERVAL_END` immediately followed by `INTERVAL_START` at 13:37:58 (same session ID `F94884FB`, no `MONITORING_RESTART` from us — autonomous iOS wrap, likely triggered by charger plug-in at battery 20% + Brain Coinz foreground at 13:35:03). Within 1 second iOS dumped catch-up callbacks for all monitored apps. v2 gate behaved correctly across the burst:

| App | Pre-burst lastThresh | First burst event | Outcome |
|---|---|---|---|
| BB131A01 | 480 s | thresh=1140 s (raw=660) | Recorded +60 s; subsequent thresh=1860/2580/2160/2280 → `LASTTHRESH_HOLD` (raw=1380/2100/1680/1800 ≫ 60). |
| C6DA269B | 2640 s | thresh=2700 s (raw=60) | Recorded normally; SKIP_REGRESSION rejected several lower out-of-order thresholds. |
| E54C1C9E | 1140 s | thresh=2220 s (raw=1080) | Recorded +60 s; subsequent thresh=3420/2100 → `LASTTHRESH_HOLD`. |

**SKIP_REGRESSION distribution post-burst:** 71 hits clustered in hour 13 (legitimate same-day rejects against in-burst held thresholds), 2 in hour 16, 1 in hour 19. **`SKIP_REGRESSION lastThreshold` values topped out at 2940 s** — *not* 3600 s. The v2 gate prevented `lastThreshold` from being walked to the window top, the exact failure mode of Apr 29.

**Recording resumed cleanly post-flood.** Last `RECORDED` was 21:40:25 (E8B1C8C6 thresh=3300 s). No rest-of-day blackout. v2 closed the Apr 29 / Apr 12 bug operationally.

#### v3 — `lastThreshold = max(prior, newToday)` on hold

**Quirk surfaced by v2 validation.** v2's pure-hold worked for the primary bug (no blackouts) but produced a tail-of-day pattern where `lastThreshold` stayed permanently frozen post-flood:

```
21:36:28  E8B1C8C6  thresh=3060s held lastThresh=2280s — credited=30s   ← real-time
21:37:24  E8B1C8C6  thresh=3120s held lastThresh=2280s — credited=56s   ← real-time
21:38:24  E8B1C8C6  thresh=3180s held lastThresh=2280s — credited=59s   ← real-time
21:39:24  E8B1C8C6  thresh=3240s held lastThresh=2280s — credited=60s   ← real-time
21:40:25  E8B1C8C6  thresh=3300s held lastThresh=2280s — credited=60s   ← real-time
```

These five events are once-per-minute legitimate foreground use (`credited` ≈ 60 s, evenly spaced). But because `lastThreshold` was frozen at 2280 s by an earlier hold, every subsequent `rawDelta = thresh − 2280` grows past `perEventCap = 60` and the gate keeps tagging them stale. Counting stays correct (wall-clock cap independently bounds delta), but `SKIP_REGRESSION` is effectively disabled for the rest of the day for that app, and the log misleadingly tags real-time events as "stale catch-up."

**Fix (v3, line 682):**

```swift
let wasStaleCatchup = rawDelta > perEventCap
if wasStaleCatchup {
    let newLastThreshold = max(lastThreshold, newToday)
    debugLog("LASTTHRESH_HOLD ... thresh=\(thresholdSeconds)s held lastThresh=\(newLastThreshold)s (was \(lastThreshold)s) — stale catch-up (raw=\(rawDelta)s > perEventCap=\(perEventCap)s, credited=\(delta)s)", defaults: defaults)
    defaults.set(newLastThreshold, forKey: lastThresholdKey)
} else {
    defaults.set(thresholdSeconds, forKey: lastThresholdKey)
}
```

**Invariant.** `newToday` is the credited high-water mark and never lies — it's bounded by the wall-clock + per-event caps. Anchoring `lastThreshold` to it keeps the variable truthful as "highest credited progression" and re-arms `SKIP_REGRESSION` against any *new* stale flood later in the day. Future real-time events have `rawDelta = max(60, threshold − newToday) ≈ 60 = perEventCap`, fall under the gate, and advance normally.

**Validation pending.** Next-day log should show no tail-cluster pattern: post-flood real-time events for an app produce `RECORDED` lines that advance `lastThreshold` to `thresholdSeconds` on each minute, no `LASTTHRESH_HOLD` on legit progression.

#### Phantom-threshold replay — new finding (NOT YET FIXED)

**The smoking gun.** `93088665` is a daily-limited app shielded all day with `dailyLimit=0` — the kid physically cannot use it. Yet during the 13:37:58 burst iOS fired all 60 distinct thresholds (`min.1` through `min.60`) for it:

```
13:37:57.438  EVENT appID=93088665... min=3   currentToday=0s lastThresh=0s
13:37:59.118  EVENT appID=93088665... min=27  currentToday=0s lastThresh=0s
13:37:59.987  EVENT appID=93088665... min=12  currentToday=0s lastThresh=0s
13:38:00.446  EVENT appID=93088665... min=22  currentToday=0s lastThresh=0s
13:38:00.773  EVENT appID=93088665... min=58  currentToday=0s lastThresh=0s
... (60 total)
```

**No real usage can explain this.** Same flood for every monitored app — all 8 got exactly 60 distinct thresholds delivered in the burst, including FAE1D45B (the user confirmed it was never opened today) and 93088665 (shielded, unusable).

**Mechanism.** When iOS does an autonomous `INTERVAL_END` → `INTERVAL_START` cycle on the activity (not our `scheduleActivity()`), it appears to **replay the entire registered threshold set for every monitored app**, regardless of actual cumulative usage. The `currentToday=0s lastThresh=0s` on every phantom EVENT for 93088665 confirms iOS is firing all 60 thresholds out of order, not legitimately catching up real cumulative.

**Trigger evidence.** `MONITORING_ALIVE` at 13:35:03 (charger plugged in, battery 20%, foreground app launch). `INTERVAL_END/INTERVAL_START` at 13:37:58 with same session ID — autonomous iOS wrap, no `MONITORING_RESTART` from our side. Likely combo of charger state change + Low Power Mode exit + foreground.

#### Why each affected app records exactly 60 s phantom credit

The recording path with `lastThreshold = 0`:

```swift
let rawDelta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60
                                                                              ^^
                                                                  hard floor of 60 s
```

First phantom event hits → `rawDelta = 60`, `delta = min(60, wallClockElapsed, perEventCap=60) = 60` → credits 60 s, sets `lastThreshold = thresholdSeconds` (e.g. 2700 s for whichever phantom arrived first). All subsequent phantom events below the new `lastThreshold` are caught by `SKIP_REGRESSION`; events above hit the v2 gate and get held at 0 credit. **Net: exactly 60 s of phantom credit per affected app per restart.**

#### Affected scope (correctly bounded)

The phantom credit only lands when `lastThreshold == 0` at the moment the burst hits. So:

- **Apps with prior real-time recording today** (`lastThreshold > 0`) → protected by their own progression. Phantom thresholds below `lastThreshold` are SKIP_REGRESSION-rejected; above are stale-catchup-held with 0 credit. **Not affected.**
- **Shielded apps** (downtime / dailyLimit==0 / dailyLimit-exceeded) → SKIP_SHIELDED (Filter 2) rejects every phantom EVENT before it reaches the recording path. **Not affected** despite being included in the iOS replay.
- **Learning apps not yet opened today** → `lastThreshold = 0`, no shield, +60 s phantom on first phantom event.
- **Unshielded reward apps not yet used today** (pool>0, kid hasn't touched) → `lastThreshold = 0`, no shield, +60 s phantom on first phantom event.

**Per-restart ceiling:** 60 s × (count of unused, unshielded tracked apps). For a typical 8-app setup where the kid uses 3–4 apps regularly, the affected set is ≤4 apps → **≤4 minutes phantom credit per restart event**.

**Per-app per-day ceiling:** 60 s. Once an app's `lastThreshold` is walked past 0 by a phantom (or by real usage), any subsequent restart-replay that day produces `rawDelta` mismatched against the now-non-zero `lastThreshold` and the v2 gate / SKIP_REGRESSION absorbs it. Only the first phantom of the day for an unused app gets through.

**Frequency of iOS-driven restarts:** unknown from one day's data. Today saw exactly one (13:37:58). Could be 0–N per day depending on charging cycles, Low Power transitions, foreground events.

#### Pool drift implication (asymmetric)

- **Learning-app phantoms inflate earned credit.** +60 s on a 1:4 ratio learning app → +4 min pool credit per restart.
- **Reward-app phantoms drain the pool.** +60 s on an unshielded reward app → −1 min pool per restart.

May 1's pool went from 1 224 min at midnight to 1 323 min at 19:53 — a +99 min change. With ~120 min of real reward usage observed (per iOS Console snapshot: 642B7130 + 739C4A42 each saw min.60 thresholds fire) and ~100 min of learning earned, the ledger should approximately balance. Instead it grew by 99 — strongly suggesting the reward-app "120 min" reading was heavily contaminated by phantom replay. The full-retention log alone cannot disambiguate phantom from deferred-real.

#### Decision: don't ship a phantom-credit fix yet

**Cost/benefit.** Bug ceiling is ~4 min/day phantom credit, mostly on apps the kid doesn't care about. Pool drift exists but is in noise relative to the deferred-real-vs-phantom ambiguity that the rotating logger alone can't resolve.

**Three fix options were considered:**

| Option | Cost | Risk | Verdict |
|---|---|---|---|
| **A — Restart-window suppression** (skip credit on first event when `(now − last INTERVAL_START < 5 s) && lastThreshold == 0`) | ~15 lines, ½ day with validation | Low — under-credits ≤60 s on apps actively used during a rare restart window, asymmetric vs. the bug it fixes; needs careful integration with v3 gate so suppressed events don't poison `lastThreshold` | Defer until measured frequency justifies |
| **B — iOS API cross-check** (read iOS-side cumulative to validate) | Multi-day spike, likely API doesn't exist for extensions | Sandbox blocks most introspection | Skip unless A and C both fail |
| **C — Burst-detection drop** (drop a burst once N events for one app land within X seconds) | ~30 lines | High — heuristic boundary against legitimate Apr 26–27 post-unlock catch-ups (which by design fire many events fast) is fragile; tuning is brittle | Skip |

**Action chosen:** none. **Watch and measure first.** Add tooling — a single `INTERVAL_START_PHANTOM_WATCH` log marker and end-of-day grep — to count how many iOS-driven restart events occur per day. If the answer comes back "0–1/day" the bug is operationally invisible and we ignore it forever. If it's "5+/day" we ship Option A.

#### Open questions

1. **Frequency of iOS-driven INTERVAL_END/INTERVAL_START.** Need a week of data with the phantom-watch marker.
2. **Does `includesPastActivity: true` cause the phantom replay, or is it inherent to monitoring restart?** Untestable without changing the flag, which has its own risks (Apr 12 finding: `false` is BROKEN for our use case).
3. **Why does iOS choose this moment to wrap the activity?** Charging plug-in correlation is suggestive but not proven — could also be Low Power Mode exit, foreground transition, or a system-wide refresh.
4. **Are 642B7130 / 739C4A42's recorded "1 min today" purely phantom, partially deferred-real, or fully deferred-real?** Cannot disambiguate from ext-log alone. iOS Console `UsageTrackingAgent` log might help if captured at the right moment.

#### Memory / pointer

- Branch: `fix/stale-catchup-lastthreshold-poisoning` — three commits: `4d4a681` (v1, broken), `da61c65` (v2), `ddcb2c5` (v3).
- Apr 12 §"Out-of-Order Catch-Up Events" status header updated to **CLOSED Apr 30, 2026** (v2 is the close; v3 is a refinement; phantom replay is a separate, unrelated finding).
- Phantom-threshold replay is a NEW open issue — distinct from the Apr 12 / Apr 29 bug. Do not conflate.

---

### May 2, 2026 — Pool-Aware `SKIP_SHIELDED_RACE` (carry-forward Time Bank credit)

**Status:** SHIPPED on branch `fix/stale-catchup-lastthreshold-poisoning`. Device-validated end-to-end on a fresh-today reward app — 3 min real use → 3 min recorded → pool decremented 72 → 69 in lockstep.

**Incident.** User report: two child devices showing 0 min recorded reward usage despite multiple hours of actual reward-app play. Time Bank was NOT decrementing — kids were spending carry-forward credit invisibly.

**Root cause.** The Apr 24 `SKIP_SHIELDED_RACE` safety-net backstop (`DeviceActivityMonitorExtension.swift:482` pre-fix) gated on **today's** `checkGoalMet()` only:

```swift
// pre-fix
if !checkGoalMet(goalConfig: goalConfig, defaults: defaults) {
    debugLog("SKIP_SHIELDED_RACE ... goal NOT met but shield store missing token — blocking")
    return false
}
```

This was correct in the Apr 24 reward-time-exhaustion race window (~220 ms while `SHIELD_CHECK` was rebuilding the shield set after a goal-met event). But it was **incorrect** for legitimate pool-only unshields:

- Midnight silent unshield path (`SHIELD_CHECK: ✅ REMOVED shield ... pool=Nmin` + `silent unshield (pool-only, todayEarned=0)`) leaves the reward app legitimately unshielded based on carry-forward Time Bank credit.
- Today's per-goal threshold isn't crossed (no learning today, or below `minutesRequired`) → `checkGoalMet()` returns false.
- Old `SKIP_SHIELDED_RACE` then blocked every threshold event for the day, even though the shield was correctly down and the kid was spending real bank credit.

The Apr 26–27 §"Pooled Time Bank Shield Gate" had already made the shield-placement decision pool-aware (`checkAndUpdateShields` line 1126: `guard pool > 0 else { return }`). But the Apr 24 backstop in Filter 2 was never updated to match — it still gated on the today-only goal check, creating an inconsistency between *whether the shield is up* (pool-aware, correct) and *whether to record events when the shield is down* (today-only, wrong).

#### Symptom evidence (May 2 ext-log-2026-05-02.log)

Device 1 (8 hours of rejected events for app `0454A303`):
```
08:53:28  GOAL_CHECK: ❌ C9DD7583-B26 goal NOT met (all mode) - 50AB3A4D-2AD below target (11min/15min)
08:53:28  SKIP_SHIELDED_RACE appID=C9DD7583... goal NOT met but shield store missing token — blocking
... repeats every minute of reward-app foreground use ...
14:13:12  EVENT appID=0454A303... min=60 currentToday=0s lastThresh=0s
14:13:12  SKIP_SHIELDED_RACE appID=0454A303... blocking
```
60 minutes of iOS-counted cumulative reward usage on `0454A303`, recorded `usage_today=0s` all day. `SHIELD_CHECK: ✅ REMOVED shield for 0454A303-53F (pool=72min)` confirms the shield was correctly down via pool-only unshield.

#### Fix

Surgical change at `DeviceActivityMonitorExtension.swift:482`:

```swift
// post-fix
if !goalMet {
    let pool = computeEffectivePoolBalance(configs: configs, defaults: defaults)
    if pool <= 0 {
        debugLog("SKIP_SHIELDED_RACE appID=... goal NOT met AND pool=\(pool)min — blocking (race-window backstop)")
        return false
    }
    debugLog("SHIELDED_RACE_BYPASS appID=... goal NOT met but pool=\(pool)min — Time Bank carry-forward unshield, recording usage")
}
```

Reuses the existing `computeEffectivePoolBalance(configs:defaults:)` (already wired for Apr 26–27 shield gate). The Apr 24 reward-time-exhaustion race is still protected: in that scenario `pool ≤ 0` is the very condition that triggered `LEARNING_GOAL_BLOCK` to re-apply the shield, so the backstop still fires. Only adds a passthrough for the legitimate "Time Bank carry-forward unshield, today's goal not yet met" case.

**Source-of-truth invariant restated.** Filter 2's `SKIP_SHIELDED_RACE` backstop and `checkAndUpdateShields`/`checkAndBlockIfRewardTimeExhausted` MUST share the same pool-aware logic. If `computeEffectivePoolBalance()` changes, the backstop's `pool <= 0` condition stays valid; it gates on the same primitive.

**Observability added in same commit.** Five new `Self.logger.notice/error` calls in Filter 2 (visible in Console.app under subsystem `i6dev.ScreenTimeRewards.extension`):

| Log line | When |
|---|---|
| `FILTER2_ENTRY app=... category=... thresh=Ns` | Every threshold event arriving at Filter 2 — confirms new-binary load |
| `SKIP_SHIELDED_FALLBACK app=... configs=nil` | shieldConfigs nil — fail-closed block |
| `SHIELD_STATE app=... shieldHasToken=BOOL shieldCount=N` | Live shield-store state at decision time |
| `SHIELD_RACE_GATE app=... goalMet=BOOL pool=Nmin` | Decision inputs for the pool-aware gate |
| `SHIELDED_RACE_BYPASS app=... pool=Nmin — RECORDING` / `SKIP_SHIELDED_RACE ... pool=N — BLOCKING` | Final decision |

The file-log (`ExtensionFileLogger.shared.appendLine` via `debugLog`) line for `SKIP_SHIELDED_RACE` was also updated from `goal NOT met but shield store missing token — blocking (race-window backstop)` to `goal NOT met AND pool=Nmin — blocking (race-window backstop)`. The `pool=Nmin` suffix lets future log analysis disambiguate "blocked because legit reward-time-exhausted race" from "blocked because no carry-forward credit."

#### Device validation (May 2 17:03–17:05)

Fresh-today reward app `47BC75D2` (cumulative=0 at unshield time, no morning rejections):

```
17:03:20  EVENT  appID=47BC75D2... min=1 currentToday=0s lastThresh=0s
17:03:20  SHIELDED_RACE_BYPASS  pool=72min — Time Bank carry-forward unshield, recording usage
17:03:20  RECORDED  oldToday=0s +60 = newToday=60s
17:03:20  EXT_WRITE_BLOCK  INCREMENT today=60 total=60 hour=17

17:04:21  EVENT  min=2  currentToday=60s lastThresh=60s
17:04:21  SHIELDED_RACE_BYPASS  pool=71min
17:04:21  RECORDED  +60 = newToday=120s
17:04:21  EXT_WRITE_BLOCK  INCREMENT today=120

17:05:21  EVENT  min=3  currentToday=120s lastThresh=120s
17:05:21  SHIELDED_RACE_BYPASS  pool=70min
17:05:21  RECORDED  +60 = newToday=180s
17:05:21  EXT_WRITE_BLOCK  INCREMENT today=180
```

3 unbroken minutes of foreground use → 3 minutes recorded → pool 72 → 69 (1:1 with reward-minute spend, exact). Timestamps exactly 60 s apart. Identical behavior to the goal-met scenario.

#### Today's already-poisoned reward apps — recovery limitation

Reward apps that had hours of pre-fix `SKIP_SHIELDED_RACE` rejections this morning are NOT fully recoverable today:

- iOS already considered every threshold in the rejected range "delivered" (extension received the callback, even though we said `return false` — that is sufficient for iOS to mark the threshold consumed).
- After the new binary lands, iOS re-fires only the most recent unsent threshold per app on `scheduleActivity()` re-registration (out-of-order catch-up burst).
- Per-event 60 s wall-clock + per-event cap (Apr 23) limits each catch-up event to 60 s of credit.
- Net: each `scheduleActivity()` cycle recovers ≤ 1 min per affected reward app.
- Going-forward: once `lastThreshold` is poisoned high (e.g., 1380 s = 23 min) by the BYPASS catch-up, only NEW threshold crossings (cumulative > 23 → fires min.24) record correctly.

**Lost minutes from earlier today are forfeit** — bounded undercount accepted, consistent with the Apr 23 / Apr 30 design tradeoff (under-credit > over-credit). Tomorrow at midnight `intervalDidStart()` resets `lastThreshold` and `usage_today` cleanly; next-day operation is identical to the goal-met case.

#### Re-shield path verified (May 2)

The pool-aware re-shield is correctly wired to fire once a kid spends down to 0 carry-forward credit:

1. `setUsageToThreshold()` calls `checkAndBlockIfRewardTimeExhausted()` after every successful record (line 386).
2. `checkAndBlockIfRewardTimeExhausted()` Check 2 (line 1420): `if pool <= 0 { ... insert(token); managedSettingsStore.shield.applications = currentShields; debugLog("POOL_EMPTY_BLOCK ...") }`.
3. Iterates **all** `configs.goalConfigs` — every reward app re-shields simultaneously when pool hits 0, not just the one being used (correct per pool semantics).
4. `computeEffectivePoolBalance()` (line 1542): `return max(0, historical + todayEarned - todayUsed)`. The `max(0, ...)` floor ensures any over-spend by 1 min reports `pool=0` and re-shield fires on the next event.

Validation in the May 2 device test: pool decremented 72 → 71 → 70 → 69 minute-by-minute alongside `usage_<id>_today` advancement. Re-shield trigger not exercised in this run (pool still high) but the wiring is unchanged from the Apr 26–27 ship.

#### Files touched

- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — Filter 2 pool-aware backstop (line 482–498) + 5 `Self.logger` observability lines.
- `docs/SMART_THRESHOLD_FILTERING.md` — this entry.

#### Out of scope (deliberately deferred)

- Recovering today's lost minutes on already-poisoned devices — forward-looking only. Midnight rollover clears the state. A future enhancement could track `last_iOS_threshold_seen_<id>` (highest threshold ever delivered, regardless of accept/reject) and use it as the floor for `scheduleActivity()` window registration, so the new window starts above iOS's actual cumulative position. Not required for steady-state correctness; only changes today-of-fix UX.
- Debouncing rapid `MONITORING_RELOAD` calls during a child's session changes (Apr 21 doc remediation #3 — still deferred).
- Phantom-threshold replay (May 1 finding) — separate, unrelated.

#### Memory / pointer

- Branch: `fix/stale-catchup-lastthreshold-poisoning` (re-used from the Apr 30 work; this fix layered on top).
- Symptom signature in field logs: every threshold event for a reward app that has `SHIELD_CHECK: ✅ REMOVED shield ... pool=Nmin (silent unshield)` shows `SKIP_SHIELDED_RACE` for the entire day with `usage_*_today=0s` despite real foreground use → pool-aware backstop missing.
- Verification on a freshly-built device: pull `ext-log-YYYY-MM-DD.log` and grep for `SHIELDED_RACE_BYPASS`. Presence + matching `RECORDED` line = fix is loaded and active.

### NO_MAPPING Recovery via Stable-Hash Reverse Lookup (May 3, 2026)

#### Symptom

In `ext-log-2026-05-02.log`, app `06909776` (Brain Coinz reward target) recorded only **88 minutes** despite ~4 h 8 min of real foreground use. Investigation showed three loss sources stacked; this entry covers the smallest but cleanest of them: **26 thresholds dropped between 17:24 and 17:49** with the line:

```
[17:24:20.700][5DEFABE8] NO_MAPPING event=usage.app.5126740347248006254.min.118
[17:25:20.144][5DEFABE8] NO_MAPPING event=usage.app.5126740347248006254.min.119
… continues through min.143
```

26 consecutive 1-minute thresholds (118 – 143) crossed iOS's cumulative window for this app. Each one fired the extension callback. Each one was discarded by `recordUsageEfficiently()` because the primitive lookup `map_usage.app.<hash>.min.<N>_id` returned `nil` and the JSON `eventMappings` fallback also missed.

#### Root cause

The sliding-window registration in `extensionRebuildSlidingWindow()` writes one `map_<eventName>_id` key per minute it registers (currently 60 minutes ahead of `current_min`). When iOS fires a threshold above the registered window — which happens whenever a window-rebuild fails silently, or whenever the post-recording rebuild trigger doesn't run — the new minute's primitive map key never got written, so the callback dropped.

In the May 2 case the timeline was:

1. **15:01:10** rebuild succeeded → window 57 – 116 registered, `window_top_min_06909776 = 116`, primitive map keys written for `min.57` through `min.116`.
2. **17:20:21** `min.117` fired (above the registered window — likely from an earlier 14:15 rebuild attempt's startMonitoring call partially registering events 56 – 115 before the extension process was killed before logging `EXT_REBUILD_SUCCESS`). The post-recording window-top check at `setUsageToThreshold()` line 754 should have triggered another rebuild for `117 – 176`, but no `WINDOW_TOP_HIT` log emerged. Most likely the same process-termination pattern: the rebuild was invoked but the extension was killed before any log line landed.
3. **17:24:20** onward iOS started flushing the deferred batch — `min.118` through `min.143` — into a fresh extension process (`5DEFABE8`). That process saw no `map_usage.app.<hash>.min.118_id` key and no entry in JSON `eventMappings`, so each event hit the `NO_MAPPING` early-out and returned `false`.

A failed window-rebuild left the extension permanently unable to record any threshold above the last registered minute — even though all the data needed to recover (the stable-hash → logicalID inverse map) was sitting one UserDefaults read away.

#### Solution

Add a recovery layer to `recordUsageEfficiently()` that runs **only** when both primitive and JSON mappings miss. The event name format is fixed: `usage.app.<stable_hash>.min.<N>`. `scheduleActivity()` writes `app_stable_hash_<logicalID>` for every monitored app. So:

1. Parse `<stable_hash>` from the event name (`usage` / `app` / `<hash>` / `min` / `<N>` — split on `.`, hash is index 2, validate the structure).
2. Iterate `tracked_app_ids`, compare each app's `app_stable_hash_<logicalID>` against `<stable_hash>` — first match wins.
3. **Backfill the missing primitive map keys** (`map_<eventName>_id`, `map_<eventName>_category`) so subsequent events from the same hash hit the fast path and don't pay the lookup cost.
4. **Force a window rebuild** — if iOS is firing thresholds the extension has no map entry for, the registered window is by definition exhausted. Rebuilding now arms the next 60 minutes ahead of current usage.
5. Continue into the normal recording path.

New log marker: `MAPPING_RECOVERED event=<name> appID=<prefix>… — backfilled via stable-hash, forcing window rebuild`.

#### Why this is safe

- **Hot path untouched.** The existing primitive-lookup branch returns immediately on a hit; the recovery code only runs when both mappings already failed.
- **No false positives.** Stable-hash collisions would require two logical IDs hashing to the same `UInt64`. The `validateAndReportStableHashCollisions()` audit in `ScreenTimeService` (line 2104+) explicitly checks for this on every config change. If a future collision ever shipped, the validator surfaces it before this lookup can mis-attribute an event.
- **Filter chain intact.** Recovered events go through `setUsageToThreshold()` exactly like primitive-mapped events. `SKIP_REGRESSION`, `LASTTHRESH_HOLD`, the wall-clock cap, and per-event 60 s cap all apply. No bypass of the Apr 30 stale-catch-up defense.
- **Window-rebuild is idempotent.** If a rebuild was already pending, calling it again from the recovery path overwrites the same `window_top_min_<id>` keys and re-registers via `startMonitoring`. Worst case: a redundant `EXT_REBUILD_SUCCESS`.

#### Bounded recovery on already-affected devices

Today's already-lost 26 thresholds for `06909776` are **forfeit** — same trade-off as the May 2 pool-aware backstop. iOS considers a threshold "delivered" once the extension callback fires, even if we returned `false`. The next `scheduleActivity()` re-registration only re-fires the most recent unsent threshold per app, and the Apr 30 per-event 60 s cap caps each catch-up to 1 minute of credit.

Going-forward, however, every NO_MAPPING is a one-time event:
- First occurrence: `MAPPING_RECOVERED` logs, primitive keys are backfilled, window rebuild is triggered.
- Subsequent events from the same hash: hit the primitive-lookup fast path on the first read.

#### Files touched

- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — `recordUsageEfficiently()` recovery branch (line 340 region) + new helper `recoverLogicalIDFromEventName()` (placed adjacent to `readEventMappingFromJSON()`).
- `docs/SMART_THRESHOLD_FILTERING.md` — this entry.

#### Out of scope (deliberately deferred)

- Diagnosing **why** the 17:20 window-rebuild trigger didn't fire (windowTopMin read returned 0? extension process killed before `WINDOW_TOP_HIT` could log? `defaults.set` for `window_top_min_<id>` lost across process boundaries?). Would require live device repro and instrumented logging. The recovery path makes the question moot for steady-state correctness — even if the rebuild trigger fails, the next received threshold self-heals.
- The other two losses identified in the May 2 analysis (~55 min from the perEventCap squashing legitimate iOS catch-up bursts, ~105 min that iOS itself never reported as cumulative) — both require separate, riskier changes pending discussion.

#### Memory / pointer

- Branch: `fix/stale-catchup-lastthreshold-poisoning` (continuing the May 2 work).
- Symptom signature in field logs: `NO_MAPPING event=usage.app.<hash>.min.<N>` for any logicalID that is in `tracked_app_ids` and has a matching `app_stable_hash_<logicalID>`. After the fix lands, the same condition emits `MAPPING_RECOVERED` once per (process, hash) pair, then nothing.
- Verification: pull `ext-log-YYYY-MM-DD.log` and confirm any post-rebuild threshold above the last registered minute either records normally or emits `MAPPING_RECOVERED` followed by a `RECORDED` line — never `NO_MAPPING` for an app in `tracked_app_ids`.

### Pool-Divergence Re-shield Bypass (May 3, 2026)

#### Symptom

Reproduced on **4 devices** the same day. After today's reward usage drove the Time Bank pool to 0, the extension correctly emitted `POOL_EMPTY_BLOCK` for all 14 reward apps, but kids were still able to launch reward apps that had **zero usage today**. In `ext-log-2026-05-03.log`:

```
19:58:25  POOL_EMPTY_BLOCK: 06D0FBC2-439… pool=0min — re-applying shield
19:58:25  POOL_EMPTY_BLOCK: C21D0890-BED… pool=0min — re-applying shield
…  (14 reward apps total)
…
20:10:06  EVENT appID=47BC75D2… min=1 currentToday=0s lastThresh=0s   ← fresh launch
20:10:06  SKIP_SHIELDED_RACE … pool=0min — blocking (race-window backstop)
20:15:04  EVENT appID=B9BA329E… min=1 currentToday=0s lastThresh=0s   ← fresh launch
20:19:04  EVENT appID=C21D0890… min=1 currentToday=0s lastThresh=0s   ← fresh launch
```

iOS fired `min.1` for three previously-untouched reward apps after the shield was supposedly applied. Each `currentToday=0s` confirms the apps were not in foreground at the time of `POOL_EMPTY_BLOCK` — they were launched *fresh* between 19:58 and 20:19, after the shield write. Something cleared the shield between extension callback and launch.

#### Root cause

`BlockingCoordinator.checkAvailableMinutes()` in the main app and `DeviceActivityMonitorExtension.computeEffectivePoolBalance()` in the extension are supposed to share the same pool formula (the CLAUDE.md note "Pool-aware shield invariant — change them together" exists for exactly this reason). They had silently diverged:

| | extension `computeEffectivePoolBalance` | main-app `checkAvailableMinutes` (BUG) |
|---|---|---|
| Historical | `bank_historical_remaining_minutes` (App-Group key written by main app — already historical-earned − historical-used) | `getHistoricalRemainingMinutes` (yesterday and earlier — earned − used) |
| Today earned | iterate `linkedLearningApps`, threshold-gated | `getTotalEarnedRewardMinutes(currentRewardTokens)` |
| **Today reward used** | **subtract** `usage_<rewardID>_today` over all reward apps | **MISSING** — never subtracted |
| Floor | `max(0, …)` | (no floor) |

So the moment a kid spent today's earned reward minutes, the extension correctly read `pool ≤ 0` while the main app read `pool = historical + todayEarned > 0`. On the next pass through `BlockingCoordinator.syncAllRewardApps()` — triggered by periodic refresh, foreground entry, Darwin notification, or any other shield-eval path — `evaluateBlockingState` returned `shouldBlock=false` and `unblockRewardApps` removed the shields the extension had just re-applied.

The extension's `SKIP_SHIELDED_RACE` filter still blocked the *recording* (correctly attributing those minutes to "shielded app should not earn pool"), but iOS had already let the app launch because the shield had been cleared by the main app between the extension's re-shield and the kid's tap.

#### Fix

`BlockingCoordinator.swift:checkAvailableMinutes()` — sum today's reward usage across `rewardIDs` from `usagePersistence.app(for:).todaySeconds`, divide by 60, subtract from `historicalRemaining + todayEarned`, floor at 0. Now byte-equivalent to the extension's formula:

```swift
let cumulativeAvailable = max(0, historicalRemaining + todayEarned - todayRewardUsed)
```

Both `computeEffectivePoolBalance()` and `checkAvailableMinutes()` now carry cross-references in their doc comments naming the other function by file path, so the next person editing one is forced past the invariant rather than silently re-introducing the divergence.

#### Why no UI-side regression

`AppUsageViewModel.cumulativeAvailableMinutes` (the home-screen "minutes available" indicator) already subtracted today's reward usage. The shield decision and the displayed available-minutes will now agree — they were contradicting each other before this fix, which is the user-visible side ("home shows 0 minutes available, but the reward app still launches").

#### Bounded recovery

Today's already-launched reward apps cannot be retroactively shielded — iOS shield only takes effect on next foreground transition. The fix prevents the *next* unshield-pass from clearing the extension's POOL_EMPTY_BLOCK. After this binary lands, every periodic refresh / app-foreground / sync path will compute the same pool the extension does, and the shield will hold.

#### Files touched

- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift` — `checkAvailableMinutes()` adds today's reward-usage subtraction + `max(0, …)` floor + invariant doc comment.
- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — `computeEffectivePoolBalance()` doc comment now names the matching main-app function.
- `docs/SMART_THRESHOLD_FILTERING.md` — this entry.

#### Out of scope

- The May 2 `WALL_CLOCK_CAP` / `perEventCap=60s` over-correction (~55 min daily under-count for heavy reward usage during catch-up bursts) — separate, riskier, requires its own discussion.

#### Memory / pointer

- Branch: `fix/stale-catchup-lastthreshold-poisoning`.
- Symptom signature: extension log shows `POOL_EMPTY_BLOCK: …` for all reward apps followed by a fresh `EVENT appID=… min=1 currentToday=0s` for a previously-untouched reward app within minutes. Presence after this fix → file a regression.
- Verification: pull `ext-log-YYYY-MM-DD.log` and confirm no fresh `min=1 currentToday=0s` events for reward apps occur after a `POOL_EMPTY_BLOCK` block in the same day. Companion main-app print: `[BlockingCoordinator] 💰 Available minutes check: … todayUsed=N, cumulative=0` once the pool is exhausted.

### Window-Rebuild Deferral + Config-Drift Self-Heal (May 3, 2026 — late)

#### Symptoms (4 devices)

Cross-device test on May 3 revealed two distinct, severe under-recording bugs:

| Device | iOS Screen Time (real Roblox use) | Brain Coinz recorded | Bug class |
|---|---|---|---|
| Imane | 4 h 11 min | 56 min | recording loss past `min.60` |
| Iness | 4 h 8 min | 58 min | recording loss past `min.60` |
| Ali | 5 h 53 min | 0 min | Roblox not in extension's monitored set |
| Sami | 5 h 19 min | 7 min (mislabeled) | wrong token bound to "Roblox" displayName slot |

This entry covers the first two bugs (recording loss + missing-from-monitored-set). The third — wrong token in slot — is held pending dedicated investigation; manual fix for affected users is to remove and re-add Roblox via the parent app's reward-app picker.

#### Bug A — Recording loss past `min.60`

**Root cause.** `extensionRebuildSlidingWindow` runs synchronously inside a DeviceActivity callback. When the firing threshold approaches the top of the registered sliding window, the rebuild has to register `16 apps × 60 events = 960` `DeviceActivityEvent`s in one `startMonitoring()` call. iOS gives the extension a ~6 MB / ~30 s budget per callback, and the rebuild routinely exceeds it — the OS terminates the process mid-call. No `EXT_REBUILD_SUCCESS`, no `EXT_REBUILD_FAILED`, just silence.

May 3 evidence on Imane and Iness:
- Window 1–60 registered cleanly at midnight (`MIDNIGHT_EXT_REBUILD_OK`).
- Recording walks `min.1` → `min.60` over the day's reward sessions.
- Imane: `WINDOW_TOP_HIT` fires at 16:25:34, three `EXT_REBUILD_APP` lines log over 18 ms, then process killed. No success log. Window stays 1–60. iOS has no `min.61+` registered, so it never fires another threshold for that app. Recording dies for 3+ hours of subsequent use.
- Iness: `WINDOW_TOP_HIT` doesn't even log on her log — same termination, just earlier. Same 3+ hour silence until 20:45 when her main-app BGTask `usage-upload intraday refresh` happened to fire and call `restartMonitoring()`, which reliably re-registered fresh thresholds from the main app's process (full memory headroom). iOS then flushed its 4-hour deferred batch — but by then the kid had stopped using the app and the catch-ups landed against an already-shielded app, getting correctly rejected by `SKIP_SHIELDED`.

The pattern: in-callback rebuild is structurally unreliable. Main-app `restartMonitoring()` is reliable. Bridge them.

**Fix.**

1. Extension — when a threshold fires within 5 minutes of the registered window top (`thresholdMin >= windowTopMin - 5`), set the App-Group flag `pending_window_rebuild=true` (with timestamp + reason), then post a Darwin notification on `com.screentimerewards.windowRebuildNeeded`. Then attempt the in-callback rebuild as a best-effort fast path.
2. Main app — `ScreenTimeService` subscribes to the new Darwin notification. On receive, `handleWindowRebuildRequest` clears the flag and calls `restartMonitoring(reason: "extension window-rebuild request: …")`, which ends in a fresh `scheduleActivity()`.
3. Opportunistic drain — every existing `extensionUsageRecorded` Darwin notification handler also checks the pending flag and triggers `handleWindowRebuildRequest` if set. So even if the dedicated notification was missed (main app suspended at the moment), the next recording wakes the main app and drains the request.
4. BGTask drain — the existing `restartMonitoring()` now clears the pending flag at entry. Any path that ends in `restartMonitoring()` (BGAppRefreshTask, scenePhase, manual restart) satisfies the request.
5. The trigger lowered from `>= top` to `>= top - 5`. Buys the main app 5 minutes of head-start before iOS exhausts the registered window.

**Latency tradeoff.** Best case: Darwin notification + main app foreground → re-register in <1 s. Mid case: main app suspended but resumable → notification queues, delivers on next wake; typically seconds-to-minutes. Worst case: main app fully terminated and no BGTask wake — request stays in flag form until something wakes the main app (foreground, BGTask, etc.). Same as today's worst case but with a far better mid case.

**Why we keep the in-callback `extensionRebuildSlidingWindow` call.** When it survives the budget — usually when the kid is idle and the callback has spare headroom — it's the fastest path. If it succeeds, the main-app handler observes a clean state and is a no-op (idempotent). If it dies, the flag survives.

#### Bug B — Roblox not in extension's monitored set (Ali + Sami)

**Root cause hypothesis.** The parent's reward-app list (read by the dashboard) and the extension's `tracked_app_ids` (set by `scheduleActivity()` when monitoring started) have drifted. Either an app was added to the dashboard after the last `scheduleActivity()` call, or sync from parent → child completed via CloudKit but didn't trigger a re-register on the child device. On Ali's device the dashboard shows Roblox but iOS has zero registered events for Roblox's stable hash. On Sami's device the symptom mutates into Bug C (a third app's token bound to the "Roblox" slot's displayName), held for separate investigation.

**Fix.** `BlockingCoordinator.refreshAllBlockingStates()` now calls `detectAndHealConfigDrift()` before delegating to `syncAllRewardApps`. Drift detection:

- Read `tracked_app_ids` from the App-Group UserDefaults (the source of truth for "what the extension is monitoring").
- Map every `currentRewardTokens` entry to its logical ID via `screenTimeService.getLogicalID(for:)`.
- Any reward logical ID missing from `tracked_app_ids` is a drift signal.

When drift is detected:
- Log `CONFIG_DRIFT — N reward apps missing from tracked_app_ids: [shortIDs]`.
- Throttle to ≤1 heal call per 60 s (avoid hammering `restartMonitoring` if the drift is persistent).
- Call `restartMonitoring(reason: "config-drift-self-heal")`. `scheduleActivity()` reads the live reward-app set and re-registers the full window — closing the drift in one pass.

`refreshAllBlockingStates()` already runs frequently (after every recording sync, every periodic refresh, every blocking-state evaluation), so detection is dense and recovery time is minimal once the main app is alive.

#### Files touched

- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — new `requestMainAppWindowRebuild()` helper, both `WINDOW_TOP_HIT` call sites updated to fire 5 minutes early and request main-app rebuild before the in-callback fast path.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift` — new `windowRebuildNeededNotification`, observer registration, `handleWindowRebuildRequest()` handler, opportunistic flag drain in `extensionUsageRecordedNotification` case, flag clearing at top of `restartMonitoring()`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift` — new `detectAndHealConfigDrift()` called from `refreshAllBlockingStates()`.
- `docs/SMART_THRESHOLD_FILTERING.md` — this entry.

#### Out of scope

- Bug C (wrong token bound to a displayName slot — Sami's device). Affects token-persistence vs displayName-persistence sync; risky to patch without understanding why they diverged. Manual recovery path documented above.
- Per-app rebuild instead of all-apps rebuild — would reduce per-callback work but `startMonitoring()` replaces the full event set per activity name, so still need the full registration. Not pursued.
- Pre-emptively registering a wider window (e.g., 1–180 at midnight) — would push out the rebuild boundary but risks exceeding iOS's per-event-name registration limits. Needs separate testing.

#### Memory / pointer

- Branch: `fix/stale-catchup-lastthreshold-poisoning`.
- Symptom signatures after this fix:
  - Bug A regressed → look for `WINDOW_TOP_HIT` events without a corresponding `[ScreenTimeService] 🪟 Window-rebuild requested` print in the main-app log within seconds, or recording stalling at exactly `newToday=3600s` for >10 minutes despite continued use of the same app.
  - Bug B regressed → look for any `usage.app.<hash>` event whose hash isn't in the extension's `EXT_REBUILD_APP` set at midnight (the monitored set), or for the new `CONFIG_DRIFT` print in the main-app log persisting beyond a single `restartMonitoring` cycle.
- Verification on a known-good day: `ext-log-YYYY-MM-DD.log` should contain a `WINDOW_REBUILD_REQUESTED` line and a corresponding main-app `Window-rebuild requested` log within ~minutes of any heavy reward use. After the rebuild completes, recording should advance past `newToday=3600s` (1 hour) into `3660s+` cleanly.

### Window-Rebuild Debounce + Discovered perEventCap Squashing (May 4, 2026 — Amine's device test)

#### Symptoms

Amine's device tested the May 3 window-rebuild deferral fix with heavy reward-app use (139 min real on app `C6DA269B`). Result: **78.5 min recorded** — a major improvement over the May 3 hard ceiling of 60 min, but still **60 min short of ground truth**.

iOS itself reached cumulative `min=138` for the app — within 1 minute of the user-reported 139 min total. So iOS's threshold-firing layer was healthy and the May 3 fix worked: thresholds past `min.60` were registered and delivered.

The remaining 60-min gap surfaced two new issues, one shipped today, one pending decision.

#### Issue Y — shipped (rebuild-restart thrashing)

**Symptom.** When iOS dumps a deferred catch-up batch, multiple thresholds for the same app fire in seconds (`min=129, 131, 130, 134, …` at 22:02 in Amine's log). Each one fired `WINDOW_TOP_HIT` in the extension, set the pending flag, posted the Darwin notification. The main-app handler stacked **10 `restartMonitoring` calls in 70 s**, each doing a full `stopMonitoring + scheduleActivity` re-register cycle. Wasteful, and risks one of those concurrent restarts colliding with iOS's in-flight catch-up flush.

**Fix.** `handleWindowRebuildRequest` now debounces to ≤1 scheduled restart per 5 s. Implementation: instance-var `lastWindowRebuildScheduledAt: Date?` + class constant `windowRebuildDebounceInterval: TimeInterval = 5.0`. On entry, if `now − last < 5 s`, log "request coalesced" and return without scheduling another restart. The pending flag stays set so a subsequent non-debounced request (or any BGTask drain) still picks it up.

**Risk.** Very low — pure throttle, no semantic change. Worst case: a real rebuild request in the 5-s window after a previous one is dropped, but the next event past the debounce window will re-trigger.

**Files touched.**
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift` — `handleWindowRebuildRequest()` adds the debounce + new instance var.

**Symptom signature for verification.** `ext-log-YYYY-MM-DD.log` should show `WINDOW_REBUILD_REQUESTED` lines clustering in bursts during catch-up storms, but the main-app log should show `Window-rebuild requested by extension` separated by ≥5 s, with `Window-rebuild request coalesced` lines for the suppressed in-between requests.

#### Issue X — pending (perEventCap squashing legitimate iOS catch-up bursts)

**Symptom.** When iOS finally delivers a deferred batch of thresholds in a sub-second burst, every event after the first credits zero seconds because `wallClockElapsed = 0` (the previous event was ms ago). The first event of the burst credits at most `perEventCap = 60 s` — even though iOS reports a `rawDelta` of 1740 s, 7560 s, etc. Net: a batch covering 60 minutes of iOS-tracked cumulative growth credits 1 second total.

Example from Amine's 22:06:08–22:06:17 burst:
```
22:06:08  oldToday=4710s  +0  thresh=7560s
22:06:08  oldToday=4710s  +0  thresh=8040s
22:06:09  oldToday=4710s  +0  thresh=6540s
…  ~30 events, all +0  …
22:06:15  oldToday=4710s  +1  thresh=6420s
```

iOS legitimately accumulated minutes 79 → 138 across the day. The kid stopped using the app, and on next wake iOS dumped 30+ thresholds in 9 s. The wall-clock cap kills 29 of them and `perEventCap = 60` kills the only event that could have crediting more than 60 s.

**Why the cap exists.** Apr 23, 2026 incident — four first-events of an iOS catch-up storm credited +3420 / +2280 / +540 / +420 s = 111 min of phantom over-credit. The 60-s per-event cap was added as a defense-in-depth bound on top of the wall-clock cap.

**Why the cap is now over-correcting.** The Apr 23 over-credit was possible because at the time `lastEventTime` was a global "last_recorded_timestamp" not a per-app `ext_usage_<id>_timestamp`. With the per-app baseline that exists today, `wallClockElapsed` is correctly bounded to the time gap *for that specific app* — making the 60-s hard cap redundantly conservative.

**Proposed fix.** Replace the hard `perEventCap = 60` with `perEventCap = wallClockElapsed`, OR equivalently remove the per-event cap entirely (since `delta = min(rawDelta, wallClockElapsed, perEventCap)` and `wallClockElapsed` is already the binding term in the burst case). The first event of a burst would then credit up to `min(rawDelta, wallClockElapsed)` — i.e., the time iOS reports, bounded by the actual wall-clock gap since the previous event. Subsequent in-burst events still credit 0 via `wallClockElapsed = 0`.

**Risk.** Medium. Reintroduces some of the Apr 23 over-credit surface, but with a tighter per-app baseline. Needs to be tested against the Apr 23 incident scenario before shipping (concretely: simulate a unlock-storm catch-up where four events arrive in quick succession with `rawDelta` values like 3420 s — verify our `wallClockElapsed` for the first event correctly matches the legitimate elapsed unlock window, not 3420 s).

**Status.** Held for explicit user sign-off after Apr 23 scenario verification.

#### Status snapshot — what's shipped vs pending after May 4

| | Bug class | Devices affected | Status | Commit |
|---|---|---|---|---|
| Bug A | Recording loss past `min.60` (in-callback rebuild dies) | Imane, Iness | ✅ shipped May 3 | `cb6f68d` |
| Bug B | Reward app missing from extension's monitored set (config drift) | Ali | ✅ shipped May 3 | `cb6f68d` |
| Bug C | Wrong token bound to displayName slot (token-vs-name desync) | Sami | ⏸ pending investigation; manual recovery via remove + re-add | — |
| Bug X | `perEventCap = 60 s` squashes legitimate catch-up bursts | All heavy users | ⏸ pending decision; design + Apr 23 scenario test required | — |
| Bug Y | Window-rebuild restart thrashing on catch-up storms | All heavy users | ✅ shipped May 4 | `e7d487e` |

Earlier related fixes (still active in this branch):
- May 2 — Pool-aware `SHIELDED_RACE_BYPASS` (Time Bank carry-forward shield gate).
- May 2 — Pool-divergence re-shield bypass (`BlockingCoordinator.checkAvailableMinutes` adds `todayUsed` subtraction).
- May 2 — `NO_MAPPING` recovery via stable-hash reverse lookup.

#### Memory / pointer

- Branch: `fix/stale-catchup-lastthreshold-poisoning` — accumulating multi-day defenses; rebase + squash before merge to `main`.
- Active diagnostic markers introduced today:
  - Extension: `WINDOW_REBUILD_REQUESTED`, `MAPPING_RECOVERED`.
  - Main app: `🪟 Window-rebuild requested by extension`, `🪟 Window-rebuild request coalesced`, `🪟 Cleared pending_window_rebuild flag (drained by restart)`, `⚠️ CONFIG_DRIFT — N reward apps missing from tracked_app_ids`, `💰 Available minutes check: … todayUsed=N, cumulative=…`.
- Verification target for the next test day: any heavy reward app should record within ~5 minutes of iOS's cumulative high-water mark — gap > 10 min file as a regression. Catch-up bursts of >30 events in <10 s should not lose more than a single 60-s minute (after Bug X is shipped, expected gap is ≤1 minute).

### May 6, 2026 — Per-App Right-Sized Sliding Window (window-exhaustion mitigation)

**Status:** SHIPPED on branch `redesign/highwater-mark-credit-model`. Pure registration-budget change — recording algorithm, wall-clock cap, perEventCap, lastThreshold are all untouched.

**Why this exists.** Sliding window was a fixed 60 thresholds per app (registration covered the next 60 minutes of usage). Heavy reward-app users routinely passed 60 min/day, hitting the window top. Above the top iOS has no thresholds to fire — recording silently dies until something triggers a rebuild (main-app foreground, BGTask, autonomous iOS INTERVAL_END/START, charge plug-in). The May 3 Darwin-notification bridge (`cb6f68d`) and May 4 debounce (`e7d487e`) made the rebuild request reliable when the main app is reachable, but on a kid's device where the parent rarely opens the app the rebuild request can stay pending for hours.

May 5 device test (`ext-log-2026-05-05.log`) hit this exactly: YouTube reached `min.153` at 17:17, window exhausted, main app closed all day → 3h 22m of zero events until iOS autonomously restarted the activity at 20:39.

**Insight from user (2026-05-06).** The daily-limit shield is a hard cap independent of Time Bank pool. Past `dailyLimits.todayLimit` the app is shielded → iOS doesn't fire events for shielded apps anyway → registering thresholds beyond `todayLimit` is wasted budget. **Right-size each app's window to its actual usage envelope.**

**Implementation.**

| App category | Window size |
|---|---|
| Learning | 60 thresholds (unchanged — kids rarely learn past 60 min/day, parents rarely set higher goals) |
| Reward (with explicit `dailyLimits.todayLimit`) | `max(60, todayLimit)` thresholds |
| Reward (unlimited / 1440 sentinel / no schedule) | 240 thresholds (default) |

**Files touched.**

- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift`
  - New helper `windowSize(for: logicalID:, category:)` (~25 lines).
  - `scheduleActivity()` computes per-app window, uses it for: threshold registration range (line ~2431), `window_top_min_<id>` write (line ~2477), `SLIDING_WINDOW` log message (line ~2541).
  - **New App Group key written:** `window_size_<id>` (Int) — single source of truth so the extension's self-rebuild path reads the same value.
- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
  - `extensionRebuildSlidingWindow()` reads `window_size_<id>` from App Group, defaults to 60 if missing (backward-compat).
  - `EXT_REBUILD_APP` log message includes the chosen window size.

**iOS event-budget note.** The "~500 events maximum" ceiling cited in some Apple-forum threads has been tested previously on this codebase and shown to be inaccurate (no enforced cap observed). Right-sizing reward apps to 240 thresholds each ×8 reward apps would cost 1,920 events for reward + 240 for learning = 2,160 events total. No budget guard is implemented; rely on observed iOS tolerance.

**Time Bank carry-forward edge case (verified safe).** If a kid has Time Bank pool credit and the daily limit is 60 min, the daily-limit shield still enforces the 60-min cap independently. The kid cannot use the app past `todayLimit` regardless of pool — so registering only 60 thresholds for that app is correct.

**`window_top_min_<id>` semantics unchanged.** The extension's `WINDOW_TOP_HIT` trigger still fires at `windowTopMin - 5` (5 min early) regardless of the window size. A 240-min reward app fires the rebuild request at `min.235`; a 60-min learning app fires at `min.55`. Same trigger logic, dynamically-sized boundary.

**Pre-existing `_today` recording behavior.** Wall-clock cap, perEventCap, LASTTHRESH_HOLD, SKIP_REGRESSION, and all filter-chain defenses are unchanged. Bug X under-credit and Bug Z phantom-60s remain documented (open). This change only reduces *how often* iOS goes silent on heavy use; it does not change *what is credited* per event.

**Validation target.** A heavy reward-app user (≥120 min on YouTube/Roblox/etc.) should not see recording stall at exactly the registered window top during a session where the parent has not opened Brain Coinz. Pre-fix: stalls at `newToday=3600s` (60 min). Post-fix: continues to whatever `dailyLimits.todayLimit` is, then stops because the daily-limit shield kicks in.

#### Memory / pointer

- Branch: `redesign/highwater-mark-credit-model`.
- Symptom signature for regression: a single reward app with `dailyLimits.todayLimit` ≥ 120 records `newToday` stalling at exactly 3600s (60 min) for hours during continuous use → window-size write didn't reach the registration path (check `window_size_<id>` in App Group).
- Symptom signature for the fix working: `SLIDING_WINDOW <id>... range=1-N (N thresholds)` in the lifecycle log shows N matching the configured daily limit (or 240 for unlimited reward apps, 60 for learning).

### May 6, 2026 — Pool-Only Carry-Forward Unshield Reverted (UX rollback, not a regression)

**Status:** SHIPPED on branch `fix/revert-pool-only-unshield` off `redesign/highwater-mark-credit-model`. Deliberate UX-driven rollback of the Apr 26-27 + May 2 pool-aware shield gate.

**What changed (from the kid's perspective).**

| Scenario | Before (Apr 26 → May 5) | After (May 6 →) |
|---|---|---|
| Today's goal met AND pool > 0 | unshielded | unshielded (unchanged) |
| Today's goal NOT met AND pool > 0 (Time Bank carry-forward) | **unshielded** (kid spends bank credit alone) | **shielded** with learning-goal copy |
| Today's goal met AND pool ≤ 0 | shielded (rewardTimeExpired) | shielded (rewardTimeExpired) (unchanged) |
| Today's goal NOT met AND pool ≤ 0 | shielded (learningGoal) | shielded (learningGoal) (unchanged) |

**Why the rollback.** User tested the pool-only carry-forward path with his kids on family devices. Observed UX problem: kids realized they had Time Bank credit from previous days and skipped today's learning goal entirely. The Apr 26 design intent was "let bank credit fund a no-learning day," but in practice it removed the daily learning ritual the parents wanted.

**New rule (both sides).** Shield comes off ONLY when today's per-config learning goal is met AND pool > 0. Carry-forward credit alone no longer unshields — kids must "pay rent" with today's learning regardless of bank balance.

**Files touched (single commit, per pool-aware shield invariant).**

- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
  - `checkAndUpdateShields`: `checkGoalMet` precondition added before the unshield path; logs `pool=Nmin but today's goal NOT met — keeping shield`. Notification gate's silent-else branch removed (now unreachable; the defensive `if todayEarned > 0` guard remains for the `minutesRequired==0` edge case).
  - `checkAndBlockIfRewardTimeExhausted`: new Check 1.5 between daily-limit and pool-empty. When `!goalMet`, re-shields with `reasonType="learningGoal"` regardless of pool. Logs `LEARNING_GOAL_BLOCK: ... goal not met (pool=Nmin) — re-applying shield`. Required so midnight transitions and intraday goal flips re-apply shields when carry-forward bank credit exists.
  - Filter 2 `SKIP_SHIELDED_RACE`: dropped the `pool > 0 → SHIELDED_RACE_BYPASS` branch. Reverted to the pre-May-2 strict `!goalMet → block` rule for the race-window backstop.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift`
  - `evaluateBlockingState`: priority inverted. `!isGoalMet → learningGoal block` regardless of pool; only `goalMet AND hasNoTimeAvailable → rewardTimeExpired`. Comment + invariant reference updated.

**Pool-aware shield invariant (still applies).** The extension's `checkAndUpdateShields`/`checkAndBlockIfRewardTimeExhausted` and the main app's `evaluateBlockingState` share one shield policy. They were updated in the same commit. See project memory `project_pool_aware_shield_invariant.md`.

**`computeEffectivePoolBalance` and `checkAvailableMinutes` unchanged.** The pool formula (`max(0, historical + todayEarned - todayUsed)`) stays byte-equivalent across both files. The revert only moves where in the decision flow `goalMet` gates the unshield — the pool math itself remains the source of truth for "is there reward time left after today's spend." The May 3 pool-divergence fix is preserved.

**Notification behavior.** "Goal Complete!" notifications continue to fire only when today's reward earnings > 0. With the new `goalMet` precondition, every unshield event now has `todayEarned > 0` (except the `minutesRequired==0` config edge case), so the notification fires reliably on the first goal-met unshield each day. The previous "silent unshield (pool-only, todayEarned=0)" log line is gone — that branch is unreachable.

**Validation target.** A kid with Time Bank carry-forward credit (e.g., pool > 0 from yesterday) and `usage_<learning>_today < minutesRequired` should see reward apps shielded at first launch. Shield should lift the moment `usage_<learning>_today >= minutesRequired` clears today's goal. Pre-revert: shield was off from midnight onward as long as pool > 0.

#### Memory / pointer

- Branch: `fix/revert-pool-only-unshield` off `redesign/highwater-mark-credit-model`.
- Symptom signature for regression (revert getting un-reverted by accident): extension log `SHIELD_CHECK: ✅ REMOVED shield for <id> (pool=Nmin)` at midnight when no learning usage has been recorded for the day. Should instead see `SHIELD_CHECK: <id> pool=Nmin but today's goal NOT met — keeping shield`.
- Symptom signature for the fix working: `LEARNING_GOAL_BLOCK: <id>... goal not met (pool=Nmin) — re-applying shield` in extension debug log when pool > 0 but today's goal is fresh.

#### May 6, 2026 follow-up — Stale `linkedLearningApps` reference filter

Initial test of the revert (`ext-log-2026-05-06.log`, 17:35 → 17:50) exposed a **pre-existing** divergence: heavy YouTube reward use (min.80 → min.93, 13 minutes) left the extension's pool stuck at `pool=86min` instead of dropping to 0. Cause: goal config `642B7130` (Mini Motorways) had `C6DA269B` (YouTube — itself a reward app) listed as a *linked learning app* with a 15-min threshold. `computeEffectivePoolBalance` iterated `linkedLearningApps` directly, read `usage_C6DA269B_today`, and credited the kid's YouTube playtime as "earned" learning. Net pool change per minute of reward play was **positive** (because ratio > 1) — kid plays forever.

This was almost certainly a learning→reward category flip on YouTube that didn't scrub the stale reference out of Mini Motorways' `linkedLearningApps`. Pre-existing — same data shape would have inflated the pool under the Apr 26-27 + May 2 policy too; the revert just made the symptom visible because the policy now relies on the pool-empty re-shield to enforce daily learning.

**Defensive code fix (commit shipped same day as the revert).** Build a `rewardAppIDs` set from the configs' reward IDs and skip any `linkedLearningApp` whose logicalID is in that set. Applied to:

- `DeviceActivityMonitorExtension.swift`
  - `checkGoalMet` — new `rewardAppIDs:` parameter, filters at function entry; `validLinked.isEmpty` returns goal-not-met. All 3 callers (Filter 2 race-window backstop, `checkAndUpdateShields`, `checkAndBlockIfRewardTimeExhausted`) compute the set from `configs.goalConfigs` and pass it through.
  - `computeEffectivePoolBalance` — same filter inserted at the top of the `todayEarned` iteration, ahead of the dedupe `seenLearningIDs` guard.
  - `computeTodayEarnedForGoal` — new `rewardAppIDs:` parameter, same filter on its inner loop. Caller (`checkAndUpdateShields`'s notification gate) reuses the local `rewardAppIDs`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift`
  - New private helper `currentRewardLogicalIDs()` — reads `screenTimeService.categoryAssignments` and emits the set of logicalIDs whose category is `.reward`.
  - Both `checkLearningGoal` variants (snapshot and non-snapshot) filter `config.linkedLearningApps` by that set before any iteration. Empty result → existing "no linked apps = goal met (no requirement, no reward)" branch fires.
  - `getTotalEarnedRewardMinutesForSnapshot` (used by CloudKit snapshot uploads) skips reward-categorized linked entries during the unique-learning-app dedupe.

**Pool-aware shield invariant preserved.** Extension's `computeEffectivePoolBalance` and main-app's `checkAvailableMinutes` continue to produce byte-equivalent values. The filter is applied symmetrically on both sides.

**Validation target.** With the filter active, the May 5 device repro should produce: `pool=0min` after YouTube hits the daily exhaustion of earned credit, `POOL_EMPTY_BLOCK` fires, YouTube re-shields with `rewardTimeExpired` reason. No infinite-play loop via the cross-categorized linked app. Symptom of regression: `pool` log values don't decrease (or increase) as the kid plays a single reward app heavily.

**Why this isn't a substitute for the data fix.** The defensive filter prevents the worst-case (infinite play), but the underlying data is still wrong — Mini Motorways' "Complete Goal" UI may still show YouTube as a learning requirement that can't be satisfied. The category-flip cleanup in `CategoryAssignmentView` / `AppScheduleService` is the durable fix; this filter is the runtime safety net.

#### May 6, 2026 — durable data fix: scrub stale linkedLearningApps on category change

Branch `fix/scrub-stale-linked-learning-refs` (off `fix/revert-pool-only-unshield`).

Adds:

- `AppScheduleService.scrubLinkedReferences(rewardAppLogicalIDs:)` — walks every schedule, drops `linkedLearningApps` entries whose `logicalID` is in the passed-in reward set, persists + re-syncs to extension only when something changed. Self-link safeguard: doesn't touch a reward app's own self-reference (separate UX bug, out of scope).
- `ScreenTimeService.scrubStaleLinkedLearningReferences()` — collects logicalIDs of every `.reward`-categorized token from `categoryAssignments` and forwards to the AppScheduleService method.
- Call sites: `ScreenTimeService.configureMonitoring(...)` (immediately after `self.categoryAssignments = categoryAssignments`) and `ScreenTimeService.assignCategory(_:to:)` (after the per-token mutation, gated on `category == .reward`).

**Result:** parents who flip an app from learning to reward will not see stale "Complete Goal: use YouTube for 15 min" requirements lingering on other reward apps' shield screens. The runtime defensive filter (above) remains as a belt-and-suspenders safety net for any path that doesn't go through these mutation sites (e.g. CloudKit-driven schedule edits — see follow-up below if/when that surfaces).

**Out of scope:** CloudKit `ChildConfigCommandProcessor` and `CloudKitSyncService` payload-application paths that overwrite `schedules[...]` directly. If a stale linkedLearningApps reference comes in via CloudKit, the runtime defensive filter still hides the symptom but the data isn't scrubbed until the next on-device category change. Flag for later if observed.

### May 7, 2026 — iOS-Claimed Cumulative Floor (LASTTHRESH_HOLD blackout fix)

**Status:** SHIPPED then REVERTED on `refactor/unified-usage-counter` (Step 1 of the unified-counter refactor — see `docs/UNIFIED_USAGE_COUNTER_PLAN.md`).

The iOS-claimed floor was a parallel counter (`ios_claimed_today_<id>`) added alongside the credited counter (`usage_<id>_today`) to make shield decisions robust to LASTTHRESH_HOLD storms. May 7 device test showed the parallel-counter approach contradicts the broader "one source of truth" architectural goal — the dashboard read the credited counter while the shield path read `max(credited, claimed)`, producing visible divergence between dashboard "Time Bank: N" and the shield's actual decision. Reverted in favor of unifying on `usage_<id>_today` everywhere. The May 6 LASTTHRESH_HOLD scenario is reopened — to be re-addressed by tightening the credit math itself rather than introducing a parallel counter.

**Original (now-reverted) implementation:**

**Symptom (May 6 device test, `ext-log-2026-05-06.log` 23:38 → 23:40).** Pool drained cleanly from 39 → 2 over 36 minutes (`23:00:41 pool=37` → `23:38:47 pool=2`), then froze. Every subsequent threshold event hit `LASTTHRESH_HOLD` with `credited=0` ("stale catch-up, raw=480..2880s > perEventCap=60s"). `usage_C6DA269B_today` stuck at `7711s` (~128 min) while iOS fired thresholds for cumulative=130–187 min. Pool stuck at `max(0, 110 + 20 − 128) = 2`. `POOL_EMPTY_BLOCK` never fired — kid kept playing past the 0-pool point. Shield only re-applied when the parent foregrounded the main app, which triggered `BlockingCoordinator.evaluateBlockingState` to compute pool against fresher data.

**Root cause.** The Apr 29 lastThreshold hold-on-clamp (`docs/SMART_THRESHOLD_FILTERING.md` "Apr 30, 2026 — Stale Catch-Up lastThreshold Poisoning") correctly prevents inflation when iOS fires a stale catch-up burst, by holding `lastThreshold` and crediting at most `perEventCap=60s`. Side effect: when the kid plays continuously through several extension-kill-and-rebuild cycles (5 kills observed in 47 min on May 6), iOS' internal cumulative drifts ahead of `usage_<id>_today`. Subsequent rebuilds re-fire those thresholds as catch-ups, all held at credited=0. Shield decisions read `usage_<id>_today`, see no progress, never fire `POOL_EMPTY_BLOCK` or `dailyLimitReached`.

**Fix (Option 4 from the May 6 mitigation discussion).** Track iOS' threshold-firing floor as a separate signal:

- New App Group key `ios_claimed_today_<id>` (Int seconds) — written by `setUsageToThreshold` immediately after the filter chain (Filter 0 SKIP_MIDNIGHT, Filter 1 SKIP_INVALID, Filter 2 SKIP_SHIELDED, Filter 2.5 SKIP_PIN_REPLAY, Filter 3 SKIP_REGRESSION) passes. Updated to `max(prior, thresholdSeconds)` on every legitimate event, regardless of how much the wall-clock cap or LASTTHRESH_HOLD ultimately credits.
- Cleared in `resetAllDailyCounters()` alongside `usage_<id>_today` and `ext_usage_*` keys.
- `computeEffectivePoolBalance` (extension): `todayUsed += max(usage_<id>_today, ios_claimed_today_<id>) / 60`. Same value for both reward apps in the pool.
- `checkAndBlockIfRewardTimeExhausted` (extension) Check 1 daily-limit: `usageMinutes = max(credited, claimed) / 60`. Daily-limit shielding now triggers off iOS' floor too.
- `BlockingCoordinator.checkAvailableMinutes` (main app): mirror the same `max(credited, claimed)` over reward apps. Reads `ios_claimed_today_<id>` from App Group UserDefaults directly (separate from `UsagePersistence.todaySeconds`).
- `BlockingCoordinator.checkDailyLimit` (main app): same `max` for `usedMinutes`.

**Crediting math is unchanged.** `usage_<id>_today`, `ext_usage_<id>_today`, `lastThreshold`, perEventCap, wallClockCap, LASTTHRESH_HOLD all behave identically. Only the *shield decision* layer reads the iOS-claimed floor. Nothing in the bank/earned/streak math is affected.

**Trade-off.** If iOS fires a phantom min.500 threshold (untrue cumulative), `ios_claimed_today_<id>` jumps to 30000s. Pool drops to 0, shield slams up — even though the kid hasn't actually played. False-positive shielding is recoverable: the kid can complete more learning to clear it, or the parent can manually unshield. False-positive *crediting* (the symmetric error in the existing wall-clock-cap defense) would silently inflate the bank. The asymmetry is intentional: shields are the safer side to err on.

**Pool-aware shield invariant preserved.** Extension `computeEffectivePoolBalance` and main-app `checkAvailableMinutes` continue to produce byte-equivalent values — both now read the same App Group key with the same `max(credited, claimed)` rule.

**Validation target.** A heavy reward-app kid playing through repeated extension kills + rebuilds should see the shield re-apply within ~1 minute of pool reaching 0, without needing a main-app launch. Symptom of regression: `usage_<id>_today` plateaus while iOS log shows higher thresholds firing AND shield doesn't apply.

**Files touched:**
- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — `setUsageToThreshold` (write), `resetAllDailyCounters` (clear), `computeEffectivePoolBalance` (read+max), `checkAndBlockIfRewardTimeExhausted` Check 1 (read+max).
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/BlockingCoordinator.swift` — `checkAvailableMinutes` (read+max), `checkDailyLimit` (read+max).

#### May 7, 2026 00:00 — Post-build midnight observations (`ext-log-2026-05-07.log`)

First post-`204ae82`-build midnight on a device that had been running the May 6 builds all day.

- `MIDNIGHT_RESET_COMPLETE` cleared `lastThreshold` for 7 apps; `MIDNIGHT_EXT_REBUILD_OK` registered fresh thresholds without falling back to `MIDNIGHT_PENDING`.
- `resetAllDailyCounters` ran, which (per this commit) also clears `ios_claimed_today_<id>` for every tracked app — confirmed by absence of stale claimed-floor carry-over into May 7.
- C6DA269B (YouTube) window jumped from `1-60 (60 thresholds)` (May 6 reward window with `dailyLimit ≤ 60`) to `1-240 (240 thresholds)` after the parent removed the daily limit. Confirms the right-sizing logic in `ScreenTimeService.windowSize(for:category:)` reacts to schedule edits as expected.
- Pool transitioned `66 → 9` between `00:00:02.809` (extension's INTERVAL_START snapshot, reading the App Group key written before the rollover) and `00:01:28.961` (after the main app woke and recomputed `bank_historical_remaining_minutes` via the WIP baseline+delta logic). The drop is **unrelated to Option 4** — Option 4 affects only the `todayUsed` term, which was 0 at that moment for both reads. The historical recompute is the Path B baseline-delta logic settling at the new day boundary.

**Open questions to verify with subsequent test traffic:**
- During a real LASTTHRESH_HOLD storm, does `ios_claimed_today_<id>` advance past the held `usage_<id>_today`, and does `POOL_EMPTY_BLOCK` fire autonomously?
- If iOS phantom-fires a high threshold, how does the false-positive shield manifest in the kid's experience? (Recoverable by completing more learning, but worth a kid-facing UX note if it's common.)

### May 7, 2026 evening — Unified usage counter (Steps 1+2+3) device test passed

**Status:** SHIPPED on `refactor/unified-usage-counter`. Device-validated end-to-end. See `docs/UNIFIED_USAGE_COUNTER_PLAN.md` for the full plan + status table.

The 3-step refactor collapsed four parallel "today's per-app seconds" counters and three independent bank-balance algorithms into a single canonical key (`usage_<id>_today`) and a single shared function (`Shared/BankCalculator.swift`). All three callers — extension shield, main-app shield, dashboard "Time Bank" copy — now agree by construction.

**What changed (in commits `0eea57a`, `59850d1`, `e3042cc`):**
- Step 1: removed `ios_claimed_today_<id>` parallel counter (Option 4 from May 7 morning). Trade-off accepted: May 6 LASTTHRESH_HOLD storm scenario reopened, to be addressed later by tightening credit math rather than introducing parallel state.
- Step 2: extracted `BankCalculator.computeBank(...)` as a pure function in `ScreenTimeRewards/Shared/BankCalculator.swift`. Algorithm: lowest-threshold-per-unique-learning-app, ratio-multiplied earnings, summed reward usage, clamped at zero. All three callsites build inputs from their own data sources and call this single function.
- Step 3: dropped the `ext_usage_<id>_today` dual-write. The other `ext_usage_<id>_*` keys (date, hour, timestamp, total, hourly buckets) still hold semantically distinct values and continue to be written. Legacy stale `ext_usage_<id>_today` keys clean up naturally via `resetAllDailyCounters` at midnight and `cleanupOrphanedExtensionKeys` on app removal.

**Device test result (evening of 2026-05-07):**
- Pre-test: Time Bank = 0, shield up. ✓
- Learning session (Facebook 3 min 39 s real → +4 integer minutes via floor → ratio 1:4 → +16 earned, with previous −1 floor-absorbed deficit): bank rose 0 → 15. ✓ Working as designed.
- Reward drain (YouTube): pool decremented 1/min, POOL_EMPTY_BLOCK at pool=0 fired autonomously, shield re-applied without main-app launch. ✓
- No shield oscillation when main app foregrounded with bank=0. ✓
- Internal consistency: 15 in = 15 out = bank back to 0. ✓

**Known integer-minute rounding artifact (not a bug):**

`BankCalculator.computeBank` does `seconds / 60` integer division — a session of `M min N sec` registers as `M+1` integer minutes if any threshold past minute `M+1` fires before the read. With ratios > 1, this rounds toward higher visible bank gain on the learning side (e.g. 3 min 39 s × 4 ratio = 16 visible bank, not 12) and toward higher visible spend on the reward side. Net effect across a balanced session is zero (15 in = 15 out), but per-session display can drift up to ~59 s × ratio. Symmetric. Documented for future debug sessions so this isn't chased as a leak. If precise second-level fairness ever matters, switch to fractional-minute math in `BankCalculator`; not warranted yet.

**Architecture invariant going forward:**

Any new code path that reads or computes "today's per-app usage" or "what's in the bank" MUST go through `usage_<id>_today` (App Group key) and `BankCalculator.computeBank(...)` respectively. Adding a parallel counter or a parallel formula re-introduces the May 7 shield-oscillation class of bug. See `project_pool_aware_shield_invariant.md`.

### May 9, 2026 — Wall-clock cap removed (deferred-batch flush undercounting)

**Status:** SHIPPED on `refactor/unified-usage-counter`. Supersedes the wall-clock cap introduced Apr 30 (see `Charging-Flush Overcounting + Wall-Clock Cap (Apr 23, 2026)`).

**Symptom:** 5-device test, 2026-05-08. 3 devices recorded reward usage correctly; 2 showed **0 minutes for the reward app yesterday** in our dashboard despite iOS Settings → Screen Time confirming the kid had played Roblox for **1h 51min**. The Time Bank also showed no deduction — the parent's perception was "the app didn't track anything."

**Investigation (`ext-log-2026-05-08.log`, one of the 2 failing devices):**

iOS fired **113 RECORDED events** for ABFF9B19 (Roblox) yesterday on this device — meaning 109+ minutes of cumulative iOS-observed Roblox usage. Of those events, only **14.7 minutes (882s) of credit reached `usage_<id>_today`**. The remaining ~95 minutes were silently dropped. (The 14.7 min that *did* credit was then lost separately because the extension's midnight `resetAllDailyCounters` clears `usage_<id>_today` to 0 without first archiving to `dailyHistory`; that's a distinct bug, see Fix A in the same investigation thread, deferred to a follow-up commit.)

Per-event credit pattern showed three phases:

| Phase | Wall clock | Events | Credit |
|-------|-----------|--------|--------|
| Phase 1 | 21:07:44 → 21:16:46 (9 min) | 10 events (some bursty) | ~5.5 min credited |
| **Phase 2** | **22:16:24 → 22:16:58 (34 sec)** | **~60 events flushed in one batch** | **+60 sec total (only the first event got credit)** |
| Phase 3 | 22:17 → 22:55 | scattered small bursts | ~9 min credited |

Phase 2 is where ~59 of the lost 95 minutes went. iOS had been holding threshold events while the device was idle / the extension was killed; when the extension came back the OS dumped its entire backlog in 34 seconds. Threshold values arrived **out of order** (4140s, 3600s, 3420s, 3900s, 2220s, …) and 59 of the 60 events received `+0` credit.

**Root cause — what the wall-clock cap was actually doing:**

The cap (Apr 30, ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift) computed:

```swift
let wallClockBaseline = max(lastEventTime, unlockTime, startOfToday)
let wallClockElapsed  = nowTimestamp - wallClockBaseline
let delta = min(rawDelta, wallClockElapsed, perEventCap)
```

Once event #1 of a burst recorded, `lastEventTime` advanced to *now*. Event #2 (arriving 0.6 s later) saw `wallClockElapsed ≈ 0` and credited 0. Same for events #3 through #60. The cap was structurally incompatible with iOS's actual delivery model — iOS legitimately delivers minutes-of-real-usage in sub-second bursts after deferring events during dormancy.

**Why the cap existed in the first place:**

April 29 incident (`ext-log-2026-04-29.log`): a stale catch-up flood walked `lastThreshold` to 3600s in <14 s, then `SKIP_REGRESSION` blocked every subsequent legitimate threshold for 9.4 hours. The Apr 30 wall-clock cap was a stop-gap to bound credit during such floods.

**Why it's redundant now:**

The actual root cause of the Apr 29 blackout was `lastThreshold` poisoning, not over-credit. That root cause was fixed on **May 1** (`Apr 30, 2026 — Stale Catch-Up lastThreshold Poisoning` section above) by anchoring `lastThreshold` to the credited high-water-mark `max(prior, newToday)` instead of the raw stale `thresholdSeconds`. With that anchor in place, `SKIP_REGRESSION` self-rearms after a flood and rest-of-day recording is preserved. The wall-clock cap on top of that became defense against a problem that was already solved at the root.

**Initial proposal (rejected mid-discussion):** Replace the "since-last-event" baseline with a "since-midnight" budget (`wall-clock-since-midnight − currentToday`). This was rejected because the budget is essentially infinite for any normal day (~80,000 seconds) and never actually constrains anything in practice — the per-event 60s cap and the 60-event sliding window already bound any single flood to ≤60 minutes.

**Shipped fix:** **Remove the wall-clock cap entirely.** No replacement budget. The remaining defenses are sufficient by construction:

| Defense | What it bounds |
|---------|---------------|
| `perEventCap = 60s` (relaxed once after unlock) | Each iOS threshold event = at most 1 min of new credit (or up to elapsed-since-unlock on the first post-unlock event) |
| `SKIP_REGRESSION` | Blocks duplicate / out-of-order events |
| `lastThreshold` high-water-mark anchor (May 1) | Floods can't poison subsequent `SKIP_REGRESSION` decisions |
| `SKIP_MIDNIGHT` (Filter 0) | Blocks cross-day stale flushes between midnight and first `scheduleActivity()` |

**Replay of the failing log under the new code:**

| Phase | Old credit | New credit |
|-------|-----------|-----------|
| Phase 1 | ~5.5 min | ~9 min |
| **Phase 2 (60-event burst)** | **1 min** | **60 min** |
| Phase 3 | ~9 min | ~40 min |
| **Total** | **14.7 min** | **~109 min** |

New total matches iOS Settings → Screen Time's 1h 51min within 1 minute (rounding from `seconds / 60` integer math).

**What changed in code:**

`ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — removed `wallClockBaseline`/`wallClockElapsed` calculation and dropped them from the `min(...)` for `delta`. Renamed the diagnostic line `WALL_CLOCK_CAP` → `PER_EVENT_CAP` to reflect the only remaining cap layer. ~30 lines net deleted (mostly comments). Trailing comment in `ScreenTimeRewards/Services/ScreenTimeService.swift` referencing `WALL_CLOCK_CAP defense` updated.

**Worst-case bound on the new code:**

A single iOS flood is bounded by the registered sliding window per app (default 60 events for learning apps, up to 240 for unlimited reward apps per the May 6 right-sized window). Worst-case phantom credit during a stale flood is therefore ≤60 min for learning apps, ≤240 min for unlimited reward apps — and `SKIP_MIDNIGHT` plus the `lastThreshold` anchor make actual phantom credit vanishingly rare in practice (iOS doesn't fabricate threshold events; it only delivers crossings that its own usage measurement observed).

**Open work (not in this commit):**

Fix A — extension's `resetAllDailyCounters` should archive `usage_<id>_today` into `dailyHistory` before zeroing it, so yesterday-view and bank-rollover survive the case where the main app isn't open at midnight. Tracked separately. (See next section — shipped same day.)

### May 9, 2026 — Pending-archive handoff (yesterday-view + bank rollover preservation)

**Status:** SHIPPED on `refactor/unified-usage-counter`. Companion fix to the wall-clock-cap removal (above). Same investigation thread, separate commit.

**Symptom:** Same 2026-05-08 5-device test as the wall-clock-cap fix. On the 2 failing devices, even after the wall-clock cap is fixed and credit math produces ~109 min for Roblox, the dashboard's "yesterday" view would still show 0 and `getHistoricalRemainingMinutes` would return baseline-only — because the data never got into `dailyHistory`.

**Root cause:**

The extension's `resetAllDailyCounters` (called from `intervalDidStart` at midnight, and from the same-day `setUsageToThreshold` path on day-rollover detection) zeroes `usage_<id>_today` and removes `ext_usage_<id>_date` directly. There is no archive step in the extension. The dashboard's "yesterday" view reads from `app.dailyHistory[]`, which is populated by `ScreenTimeService.readExtensionUsageData()` — but only when the main app is foregrounded **and** the extension still has yesterday's data accessible (`isFromToday == true` gate inside `readExtensionUsageData`).

Failure path on a device where the parent didn't open the main app between yesterday's last reward session (22:55) and midnight:

1. `usage_ABFF9B19_today = 882s`, `ext_usage_ABFF9B19_date = "2026-05-08"`. Bank, shield, dashboard all read this.
2. 00:00 May 9: extension's `intervalDidStart` triggers `resetAllDailyCounters`. `usage_ABFF9B19_today` set to 0; `ext_usage_ABFF9B19_date` removed. **Yesterday's 882s now exists nowhere on the device.**
3. Morning May 9: parent foregrounds the main app. `readExtensionUsageData` runs. `extTodaySeconds = 0`, `extDateString = nil`. The `isFromToday` gate evaluates false → `else` branch increments `unchangedCount` and exits. **No archive opportunity remains.**
4. Dashboard renders: yesterday's view = 0 min for Roblox; bank's `getHistoricalRemainingMinutes` returns baseline only — yesterday's earnings/spend never enters the live delta.

The pre-existing archive logic in `readExtensionUsageData` (lines ~1322–1346) was conditional on `isFromToday` — it could only archive yesterday's value if the main app had previously synced with the extension and `persistedApp.todaySeconds` already held that value. On a device where the main app didn't run during yesterday's session, `persistedApp.todaySeconds` was 0, and there was nothing to archive.

**Fix design — pending-archive handoff:**

The extension captures yesterday's value into a dedicated UserDefaults key right before the wipe; the main app drains that key into `dailyHistory` on next foreground.

| Side | Change |
|------|--------|
| Extension | In `resetAllDailyCounters`, before zeroing `usage_<id>_today`, read `usage_<id>_today` and `ext_usage_<id>_date` and write them to `pending_archive_<id>_seconds` and `pending_archive_<id>_date`. Logs as `PENDING_ARCHIVE`. |
| Main app | New private method `drainPendingArchives(defaults:)` on `ScreenTimeService`. Called at the top of `readExtensionUsageData`, after the defensive empty-load. Iterates `tracked_app_ids`, reads pending-archive keys, appends to `app.dailyHistory` (deduped by date), removes the keys. |
| Main app | `cleanupExtensionKeys(for:)` extended to also remove `pending_archive_<id>_*` keys when an app is orphaned. |

**Why a separate handoff key (vs. extending `PersistedAppMinimal`):**

The extension's `updateJSONPersistence` already round-trips `persistedApps_v3` through `PersistedAppMinimal`, which lacks `dailyHistory`. Adding `dailyHistory` to the minimal struct or sharing the full `PersistedApp` type into the extension target is a much larger change and increases the extension's memory footprint — the 6 MB DeviceActivityMonitor extension limit is already a constraint. The handoff key approach is ~30 lines of code total, no schema changes, no extension memory growth.

**Properties of the design:**

- **Idempotent** — drain is keyed off the pending key's existence; once removed, repeated foregrounds are no-ops.
- **Deduplicated** — drain checks `dailyHistory.contains` for the same date before appending, so even if the existing `isFromToday`-path archive runs first, the drain won't double-write.
- **Defensive** — refuses to archive any date >= today (sanity check); refuses to archive without a `persistedApp` lookup (orphan).
- **Cross-day-tolerant** — if multiple midnights pass without main-app launch (e.g., parent away for 3 days), each midnight's pending-archive key holds whatever `usage_<id>_today` was at that moment; only the *most recent* survives. Earlier days' data still goes through the `_total` cumulative key but per-day breakdown is lost. Acceptable trade-off — the alternative is a per-day pending-archive key set, which adds complexity for a rare scenario.
- **Points-free** — the pending archive doesn't carry a `points` value. `DailyUsageSummary.points = 0` in the drained entry. Acceptable because (a) the bank uses seconds-based ratio math, not points, and (b) the main-app-was-closed scenario means `persistedApp.todayPoints` would have been 0 anyway under the old archive path.

**What didn't change:**

- The existing `readExtensionUsageData` archive path inside the `isFromToday` block stays. It still handles the common case where the main app *did* run during yesterday's session — the drain is a backstop for the case where it didn't.
- `updateJSONPersistence`'s `PersistedAppMinimal` round-trip continues to silently strip `dailyHistory`. This is a latent bug (only fires on the JSON-fallback recording path, which runs only when `map_<event>_id` keys are missing). 0 occurrences in 2026-05-08 logs. Out of scope here; flagged for a separate pass.

**What changed in code:**

- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — `resetAllDailyCounters` writes `pending_archive_*` keys before wipe. ~10 lines added.
- `ScreenTimeRewards/Services/ScreenTimeService.swift` — new `drainPendingArchives(defaults:)` private method (~50 lines), called from start of `readExtensionUsageData`. `cleanupExtensionKeys(for:)` extended by 2 lines to drop pending-archive keys for orphaned apps.

### May 9, 2026 — NEW_DAY `lastThreshold` poisoning (parallel-branch miss of May 1 v3 anchor)

**Status:** DIAGNOSED, NOT YET SHIPPED. Fix design below pending verification against the second failing-device log.

**Symptom:** Same May 8 → May 9 5-device test as the wall-clock-cap removal and pending-archive handoff above. After installing the new build (`refactor/unified-usage-counter` through `e3701d7`) at 01:54 on 2026-05-09, one device that recorded 1h 51min of Roblox in iOS Settings → Screen Time recorded only **7 minutes** in our app for the entire next day's session (08:08 → 14:09). The bank "didn't move" because nothing was being credited.

**Root cause — the parallel-branch miss:**

`setUsageToThreshold` in the extension has two branches that handle credit calculation:

1. **Same-day branch** (line ~547+, `lastResetTimestamp >= startOfToday`) — patched on May 1 with the v3 anchor `lastThreshold = max(prior, newToday)` so a stale catch-up event can't poison `lastThreshold` past the credited high-water mark.

2. **NEW_DAY branch** (line ~572+, `lastResetTimestamp < startOfToday`) — runs on the very first event of a new day for an app. Sets `lastThreshold = thresholdSeconds` *unconditionally*, with no v3 anchor, no sanity check.

The May 1 fix was scoped only to branch #1. Branch #2 has the same bug, in identical-shape code, written in 2026-02 and never revisited. The Apr 29 incident manifested mid-day (14:35:14), so the same-day branch was where attention went.

**Why it triggered on May 9 specifically:**

Three preconditions must all hold for branch #2 to be reached with a stale event:

| Condition | May 7 → May 8 | May 8 → May 9 |
|-----------|---------------|---------------|
| Yesterday's iOS-cumulative for any app exceeds today's wall-clock-since-midnight | Max app at min.20 (1200s) | ABFF9B19 at min.111 (6660s) — 1h 51min Roblox |
| Extension was killed across midnight | yes (battery 5%, dead/sleeping) | yes (battery 85%, healthy) |
| iOS delivers a queued threshold event *before* `intervalDidStart` finishes its reset | **no** — 80ms reset window was empty (00:06:46.642 → 00:06:46.722) | **yes** — `min.111 THRESHOLD_CALL` arrived at `00:05:18.521`, same millisecond as `INTERVAL_END`, before `MIDNIGHT_RESET_COMPLETE` at `00:05:18.765` |

The May 8 device was nearly dead overnight, so iOS deferred event delivery until well after the extension had completed its day-rollover. The May 9 device was healthy enough that iOS had events queued and ready to fire the instant the extension restarted. The race window is normally 80–250ms wide; on May 8 it was empty, on May 9 it caught the stale `min.111`.

**Failing-device timeline (`ext-log-2026-05-09.log`, redacted):**

```
00:05:18.521  INTERVAL_END
00:05:18.521  THRESHOLD_CALL min.111            ← stale, yesterday's queue
00:05:18.557  EVENT min=111 currentToday=882s lastThresh=882s
00:05:18.628  MIDNIGHT_START                    ← intervalDidStart begins (concurrent thread)
00:05:18.660  DAY_ROLLOVER appID=ABFF9B19...    ← NEW_DAY branch fires from min.111 handler
00:05:18.701  APP_STATE ABFF9B19 ext_date=2026-05-08 lastThresh=882s usage_today=882s
00:05:18.765  MIDNIGHT_RESET_COMPLETE
00:05:19.225  EXT_REBUILD_APP ABFF9B19 current=1min → window 2-181 (180 thresholds)
              ↑ current=1min because NEW_DAY credited initialUsage=60 from the stale event
```

Then the rest of the day:

```
08:08:48.592  EVENT min=2  currentToday=60s lastThresh=6660s  → SKIP_REGRESSION
08:11:05.819  EVENT min=4  currentToday=60s lastThresh=6660s  → SKIP_REGRESSION
08:16:50.209  EVENT min=8  currentToday=60s lastThresh=6660s  → SKIP_REGRESSION
... (174 more SKIP_REGRESSION on legitimate today events) ...
14:09:51.847  RECORDED min=116 oldToday=60s +300 = newToday=360s thresh=6960s
              ↑ first event > 6660s, finally passes — 6 hours of credit lost
```

176 of 182 today events for ABFF9B19 were `recorded=false`. Only events with `thresholdSeconds > 6660` (today's iOS cumulative caught back up to yesterday's high-water mark) made it through.

**Comparison to May 8 (worked):**

```
00:06:46.642  MIDNIGHT_START
00:06:46.722  MIDNIGHT_RESET_COMPLETE   ← 80ms, no events arrived in window
00:06:46.788  EXT_REBUILD_APP ABFF9B19 current=0min → window 1-60
```

Clean reset. `lastThreshold` wiped to 0 for all apps. Today's events recorded normally.

**Two-device-with-same-bug-different-symptoms hypothesis (pending verification):**

The user reported the second failing device as "flood and usage overcounting." This is plausibly the same NEW_DAY branch hit with different inputs:

- If yesterday's stale event has a moderate `thresholdSeconds` (say 600s) AND today's kid uses the app heavily, the bogus `lastThreshold = 600` doesn't block events past min.10 — it blocks min.1–9 only. From min.11 onwards, the same-day branch fires with `lastThreshold = 600` and a real event at min.11 (660s), making `rawDelta = max(60, 660 − 600) = 60`. The kid would see ~10 missing minutes early in the day, then everything credits normally.
- If yesterday's stale event is small (e.g. min.5, 300s) AND iOS dumps several stale events in the race window — the NEW_DAY branch records 60s, sets lastThresh=300, then *subsequent* in-burst stale events (still in the same 250ms race window before MIDNIGHT_RESET_COMPLETE) hit the same-day branch with `lastResetTimestamp` now updated. They'd flow through the post-NEW_DAY credit path with the v3 anchor — but each could credit up to 60s per event, and if iOS has 5–10 queued stale events, that's 5–10 minutes of bogus credit at 00:00 before any real usage. **This is the overcounting symptom.**

Confirmation deferred to second-device log analysis.

**Fix design (pending implementation):**

Single new filter at the top of `setUsageToThreshold`, before any state mutation. Naming candidate: `SKIP_STALE_FLUSH`.

```swift
// Filter 1.5: SKIP_STALE_FLUSH — physical-impossibility check.
// A threshold event today claiming more cumulative seconds than the
// wall-clock seconds elapsed since midnight necessarily reflects yesterday's
// iOS-cumulative being flushed across the day boundary. Drop it before any
// state mutation so neither the credit count nor lastThreshold gets poisoned.
// Mirrors SKIP_PIN_REPLAY (which uses the same idea anchored to firstSeen).
let wallClockSinceMidnight = max(0, Int(nowTimestamp - startOfToday))
if thresholdSeconds > wallClockSinceMidnight + 60 {  // +60s grace for jitter
    debugLog("SKIP_STALE_FLUSH appID=\(appID.prefix(8))... thresh=\(thresholdSeconds)s > wallClockSinceMidnight+60=\(wallClockSinceMidnight + 60)s — yesterday's queued event", defaults: defaults)
    return false
}
```

**Belt-and-suspenders complement:** in the NEW_DAY branch, replace the bare
`defaults.set(thresholdSeconds, forKey: lastThresholdKey)` with the same
v3 high-water-mark anchor as the same-day branch. Even if a near-edge event
slips through the +60s grace, it can't poison `lastThreshold` past `newToday`.

**Why `wallClockSinceMidnight` is correct here (vs. why I rejected it as a credit cap on May 9 morning):**

When discussing the wall-clock-cap removal, I (correctly) rejected `wallClockSinceMidnight` as a credit budget — it's essentially infinite for any normal day and never constrains anything. But that's a property of using it as a *credit cap*. As a *physical-impossibility check on threshold magnitude*, it's exactly the right anchor: any threshold > wall-clock-since-midnight is, by definition, claiming usage that didn't happen today. That's a sharp, principled bound. The two uses look superficially similar (both involve "wall clock since midnight") but answer different questions:

- "How many seconds of credit can this event grant?" → bounded by perEventCap (60s), not wallClockSinceMidnight.
- "Could this event represent today's activity at all?" → bounded by wallClockSinceMidnight + grace.

**Self-heal question (open):**

The bad `lastThreshold = 6660` is currently sitting in the test device's storage. New build can't repair it until tomorrow's midnight reset (which clears `lastThreshold` for all apps). Options:

1. Wait it out — bug stops affecting the device after the next clean midnight.
2. Add a self-heal: on every `EXT_REBUILD_APP`, if `lastThreshold > current_minutes × 60 + 60`, reset `lastThreshold` to `current_minutes × 60`. Catches the poisoning automatically.
3. Triggered repair on app launch (main app sees impossible `lastThreshold`, clears it).

Decision deferred until fix implementation.

### May 9–10, 2026 — Three-layer phantom-flood defense

**Status:** DESIGNED, READY FOR IMPLEMENTATION. Supersedes the May 9 NEW_DAY-only fix above. Ships in one commit alongside this entry.

**Problem statement:** iOS DeviceActivity occasionally fires threshold events for cumulative crossings that don't reflect today's actual usage. Two distinct manifestations observed across the May 8–9 device tests:

1. **Device 1 (May 9 morning).** A stale `min.111` event fired at `00:05:18.521` — the same millisecond as `INTERVAL_END` and 178 ms before `MIDNIGHT_RESET_COMPLETE`. The event entered the NEW_DAY branch of `setUsageToThreshold` (because `lastResetTimestamp < startOfToday` had not been updated yet) and wrote `lastThreshold = 6660s` directly. For the rest of the day, every legitimate event for the app got `SKIP_REGRESSION`'d because its threshold was below 6660. **Symptom: undercounting.** Kid played Roblox for 4 hours; only 7 minutes were credited.

2. **Device 2 (May 9 afternoon).** After a window rebuild fired `startMonitoring()` at `12:51:20`, iOS dumped queued threshold events for all 14 monitored apps simultaneously. 12 of those apps had not been opened by the kid at all today (iOS Screen Time confirmed each had <18 seconds of real usage), but iOS still flushed accumulated cross-day cumulative crossings as if they had. The events arrived in waves over the next two hours, eventually delivering nearly the full sequence of mins 1–125 for each phantom app — but the LOW mins (min.1, 2, 3) arrived 30+ minutes after the first wave's HIGH mins (min.10, 100, 162). **Symptom: massive overcounting + shield oscillation.** ~330 min of phantom credit on apps the kid never opened, drained the bank to 0 and held it there via a feedback loop where each minute earned was instantly lost to phantom credit during the brief shield-drop windows.

**Root cause (upstream, in iOS, NOT fixable in our code):**

iOS Screen Time's per-day usage tracker and iOS DeviceActivity's threshold delivery queue are loosely coupled and inconsistent. Per-day cumulative resets at midnight; the threshold delivery queue retains undelivered crossings across days and dumps them on `startMonitoring()` calls. Apple Developer Forum thread 811305 (FB21450954) describes the same symptom on iOS 26.2; unresolved as of March 2026 with no API workaround. Confirmed by parallel research agent: there is no public iOS API to ask "did the user actually foreground app X today" outside the DeviceActivityReport extension, and that extension cannot pipe data back to the monitor extension.

**Hypotheses tested and REJECTED during diagnosis:**

| Hypothesis | Why it failed |
|------------|---------------|
| "Phantom flood is in a tight burst, legit usage is spread out" | Real catchups (deferred legit events) are also tight bursts. Both compress N minutes of cumulative into seconds of wall-clock when extension restarts after being killed. |
| "Phantom events arrive out-of-order; legit events are monotonic" | Both can be out-of-order. AbacusFlashMath morning legit fired `min=2, 1, 3, 5, 4, 7, 6, 8...` — adjacent reorderings under 1 second. iOS catchups never arrive perfectly monotonic. |
| "Phantom floods skip min.1 entirely; legit catchups always include min.1" | iOS does eventually deliver min.1 in phantom waves — but 30+ minutes after the first event for the app, in a separate later wave. So presence-of-min.1 alone is not a signal; **timing of min.1 relative to first event is.** |
| "Phantom floods have holes in the sequence" | Both legit and phantom data have holes due to event-drop under iOS pressure. Legit AbacusFlashMath had 19 holes in its 1-110 range; phantom 19C7CA9F had only 7 holes in 1-125. Hole-counting does not separate. |
| "Cumulative growth-rate exceeding wall-clock = phantom" | Same shape in legit deferred catchups — extension was dead while kid played, iOS dumps everything when extension wakes up. Pace-impossibility happens identically in both. |
| "Cross-app simultaneity within a `startMonitoring()` window = phantom" | Real catchups affect every app the kid was using during the dead window — could be 2-3 apps simultaneously. Threshold heuristics ("more than N apps = phantom") have edge cases where legit multi-app activity gets falsely flagged. |
| "Just keep the wall-clock-since-last-event credit cap (the May 9 morning removal)" | The cap suppresses legit deferred catchups (Device 1's 1h 51min Roblox session credited only 14.7 min on May 8 because every in-burst event after the first got `wallClockElapsed=0`). Returning the cap re-introduces this undercounting. |

**Surviving signals — the two physical-impossibility checks that hold up:**

1. **Per-app: timing of min.1 relative to first event of day.**
   - In every legit case across all 5 device logs (Roblox today/yesterday, AbacusFlashMath today, May 5 multi-app catchups), the first event for an app fresh in the day was either min.1 itself OR min.1/2/3 arrived within hundreds of milliseconds of the first event.
   - In every phantom case (12 untouched reward apps on Device 2), the first event was at min.10+ and min.1 did not arrive for 30+ minutes.
   - The two regimes are separated by roughly 6,000× — a 60-second decision window catches phantom cases with massive margin without false-positiving any observed legit case.

2. **Aggregate: total post-unshield credit ≤ wall-clock since unshield + grace.**
   - The kid has one set of hands and can foreground only one app at a time. Therefore, total credited usage across all monitored apps since the last shield drop cannot exceed wall-clock seconds since that shield drop.
   - This is a hard physical bound. Pre-unshield credit is preserved (it accumulated during the goal-earning window before unshield) but does not enter the post-unshield budget calculation.
   - Anchoring to the unshield moment (rather than midnight) gives a tighter budget that triggers earlier on phantom floods.

**Three-layer defense (final design):**

```
┌──────────────────────────────────────────────────────────────────┐
│ Existing filters (kept unchanged)                                │
│   SKIP_MIDNIGHT, SKIP_INVALID, SKIP_SHIELDED, SKIP_PIN_REPLAY    │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ NEW Layer 1: SKIP_STALE_FLUSH                                    │
│   if thresholdSeconds > wallClockSinceMidnight + 60s             │
│       → reject (catches Device 1's NEW_DAY race)                 │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ NEW Layer 2: PER-APP MIN.1 BUFFER                                │
│   if phantom_suspect_<id> set: reject                            │
│   if first event of day (lastThresh=0, currentToday=0):          │
│     if thresholdSeconds ≤ 180: clear buffer state, proceed       │
│     else if no buffer open: open buffer (record start time),     │
│                              reject this event                    │
│     else if buffer age > 60s: set phantom_suspect, reject        │
│     else: still in 60s window, reject (still buffering)          │
│                                                                   │
│   Catches Device 2's per-app phantom (untouched apps)            │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ Existing SKIP_REGRESSION + lastThreshold v3 anchor               │
│ Existing per-event 60s cap (with first-after-unlock relaxation)  │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ NEW Layer 3: POST-UNSHIELD BUDGET                                │
│   compute totalPostUnshieldCredit (sum of per-app                │
│     (usage_<id>_today − usage_<id>_at_unshield))                 │
│   if totalPostUnshieldCredit + delta                             │
│      > wallClockSinceUnshield + grace (10%)                      │
│       → reject (catches AbacusFlashMath afternoon-contamination  │
│         and any other continuation phantom that passes Layer 2)  │
└──────────────────────────────────────────────────────────────────┘
                               ↓
                        Credit applied
```

**Coverage table:**

| Phantom subtype | Caught by |
|-----------------|-----------|
| Midnight race-window NEW_DAY poisoning | Layer 1 |
| First-event-of-day phantom on untouched apps | Layer 2 |
| Continuation phantom on apps with prior usage today | Layer 3 |
| Sustained multi-app flood across 13+ apps | Layer 2 + Layer 3 |
| In-burst per-event undercounting on legit deferred catchup | Existing per-event cap (kept) |

**State to add (App Group UserDefaults keys):**

| Key | Type | Purpose |
|-----|------|---------|
| `phantom_suspect_<id>` | Bool | Set when an app's first-event-of-day check fails. While set, all events for the app are rejected. Cleared at midnight. |
| `first_event_start_<id>` | Double (TimeInterval) | Timestamp when the buffer opened for an app. Cleared when verdict reached or at midnight. |
| `last_unshield_timestamp` | Double (TimeInterval) | When was the most recent shield-drop event. Anchors the budget. Updated by `checkAndUpdateShields` whenever the shield state transitions to "any app unshielded". |
| `usage_<id>_at_unshield` | Int (seconds) | Per-app snapshot of `usage_<id>_today` at the moment of `last_unshield_timestamp`. Used to compute post-unshield delta. |

All four are cleared in `resetAllDailyCounters` at midnight and in `cleanupExtensionKeys` for orphaned apps.

**Replay against failing-device logs:**

*Device 1 (2026-05-09 00:05:18 NEW_DAY race):*
- Layer 1 sees `thresholdSeconds = 6660`, `wallClockSinceMidnight = 318` → `6660 > 318 + 60 = 378` → REJECT.
- NEW_DAY branch never executes for the stale event. `lastThreshold` stays 0.
- Subsequent legit today events for Roblox process normally.

*Device 2 (2026-05-09 12:53–14:46 multi-app phantom flood):*
- For each of the 12 untouched reward apps:
  - First event has threshold 600s–9720s, > 180s.
  - Layer 2 opens buffer at t₀, rejects this event.
  - For 60 seconds, more high-threshold events arrive → all rejected (still buffering).
  - At t₀+60s, no event with threshold ≤ 180s arrived → set `phantom_suspect_<id>` = true.
  - All subsequent events for the day → rejected immediately at top of Layer 2.
- For AbacusFlashMath (had real morning usage, lastThreshold > 0 in afternoon):
  - Layer 2 doesn't apply (not first-event-of-day).
  - Afternoon events compute deltas through existing filters.
  - Layer 3 sees that crediting would push post-unshield total above wall-clock-since-unshield → REJECT.

Final: Device 2 credits 234 min (Roblox real) + 16 min (AFM legit morning) = **250 min total** instead of 675 min. Bank stays at the right number. No oscillation.

**Edge cases acknowledged:**

1. **Layer 2 loses 1-2 events in rare legit-with-late-min.1 case.** If iOS happens to deliver a legit catchup with first event at min.5+ (we've never seen this in our data, but theoretically possible), the events arriving while the buffer is open get rejected. Once min.1/2/3 arrives within 60s, the buffer state clears and subsequent events credit normally. Worst-case undercount: 60s. Bounded.

2. **Layer 3 needs a non-zero `last_unshield_timestamp` to function.** If the bank starts the day with `pool > 0` and shields never re-applied (so unshield never tracked), we fall back to `startOfToday` as the anchor. Loose but safe.

3. **Multiple shield drop/re-apply cycles.** Each unshield event resets the snapshots. `usage_<id>_at_unshield` always reflects the latest unshield. The grace factor (10%) accommodates iOS background-counting that occasionally produces 1-3 minutes of cumulative beyond wall-clock.

4. **The phantom_suspect flag persists for the day, even if iOS later delivers min.1 for the app.** This is intentional. If the kid genuinely opens the app later in the day, they would be undercredited until midnight. Trade-off: undercount-on-rare-edge-case vs. overcount-on-known-iOS-bug. We chose to undercount.

---

### May 10, 2026 — Burst-tolerant recording + flood detection redesign

The May 9 three-layer defense above held the line on the morning Device 2 phantom flood, but May 10 device testing exposed three problems with it on iPad-9th-gen-class hardware (Device 1 + Device 2):

1. **Legit catch-up bursts were under-credited.** iPad 9th gen frequently goes silent for 30–60 minutes mid-day, then iOS dumps a backlog of threshold events for any app the kid was actively using in 1–2 seconds. The PER_EVENT_CAP at 60s clipped each event in the burst, so an 11-minute legit session credited as 3 minutes (Device 1 May 10, AbacusFlashMath morning session, log `ext-log-2026-05-10.log`).
2. **Layer 2's BUFFER_LEGIT acceptance failed to fast-forward credit.** When the buffer accepted a burst as legit (min≤3 within 60s), only the min≤3 event itself was recorded. The high-min events that had been HOLD-rejected were already discarded; iOS doesn't redeliver them.
3. **The post-wake phantom scenario defeated Layer 2 entirely.** When Amine's iPhone died overnight and woke at 08:10 May 10, iOS dumped a queue of events for ALL 7 monitored apps within 2 seconds at 08:17 — including events for apps that had **zero usage yesterday** (FAE1D45B). The dump included min.1, 2, 3 for each app (because those were the never-delivered queue entries), so Layer 2's "min≤3 in burst = legit" rule mis-classified the entire flood as legit catch-up. 5 min of phantom credit landed on FAE1D45B and triggered a "Goal Complete!" notification with no actual usage.

The redesign anchors every filter decision on a single question: **"Is this burst a flood or a legit catch-up?"**

#### Filter chain order (post May 10)

```
Filter 0   SKIP_MIDNIGHT             — block events during midnight rebuild window
Filter 1   SKIP_INVALID              — threshold < 60s
Filter 1.5 SKIP_STALE_FLUSH          — threshold > wallClockSinceMidnight + 60s
           [shadow update]           — record max threshold seen for parallel evaluation
Filter 1.7 PHANTOM_FLOOD_LOCKOUT     — read phantom_flood_active_until, SKIP_FLOOD if
                                       active. Stamp last_event_arrival_<id>.
Filter 2   SKIP_SHIELDED             — block events for verifiably-shielded reward apps.
                                       FLOOD TRIGGER: when SKIP_SHIELDED fires AND ≥1
                                       other tracked app has an arrival in last 10s,
                                       set phantom_flood_active_until = now+5min and
                                       wipe all open Layer 2 buffers.
Filter 2.5 SKIP_PIN_REPLAY           — block historical replay since pin
Layer 2    FIRST_EVENT_BUFFER         — fast-forward + burst-window for first-of-day catch-up
Filter 3   SKIP_REGRESSION           — block duplicates / out-of-order regressions
PER_EVENT_CAP                         — cap delta at 60s, bypassed during burst-window
Layer 3    POST_UNSHIELD_BUDGET      — block phantom continuation post-unshield
RECORD                                — credit + update lastThreshold
```

#### Layer 2 fast-forward (commit `1a8347b`)

Buffer now tracks the max threshold seen during HOLD phase (`first_event_max_thresh_<id>`). On BUFFER_LEGIT acceptance, `thresholdSeconds` is overridden to that max. NEW_DAY recording credits `initialUsage = thresholdSeconds` instead of a hardcoded 60s, so the fast-forward credit lands instead of being clipped to 1 min.

Trace: Device 1 morning burst (min.4, 6, 9, 10, 3 within 1.7s, kid used app for 10 min):
- min.4 → BUFFER_OPEN, max=240
- min.6, 9, 10 → BUFFER_HOLD, max climbs to 600
- min.3 → BUFFER_LEGIT, fast-forward to 600s, NEW_DAY credits 600s = **10 min**

Without fast-forward, only min.3 was recorded as 60s = 1 min.

#### Burst-window PER_EVENT_CAP bypass (commit `1a8347b`)

BUFFER_LEGIT now also opens a per-app `burst_active_until_<id>` flag set to `now + 10s`. While active, PER_EVENT_CAP is bypassed (set to `Int.max`) so out-of-order tail events that arrive in the same iOS dump credit their full deltas instead of being clipped to 60s each.

#### Mid-day burst detection (commit `1a8347b`)

For burst-only-delivery devices, Layer 2's first-of-day buffer doesn't fire mid-day (today>0 / lastThresh>0). Detect bursts via timing instead: if the previous recorded event for an app is <5s old, bypass PER_EVENT_CAP for the current event. The first event of a mid-day burst still gets capped (we can't know it's a burst until a second event confirms within 5s); subsequent events bypass.

#### Layer 3 burst-continuation exemption (commit `1a8347b`)

Layer 3's post-unshield budget incorrectly blocks events that arrive in the seconds immediately after a Layer-2-triggered unshield — those are the rest of the same legit pre-unshield burst still flushing, not new post-unshield activity. Exemption: if `usage_<id>_at_unshield > 0` AND `now - lastUnshield ≤ 60s`, skip the budget check.

#### Shadow tracker (commit `1a8347b`)

Parallel "trust max threshold" evaluation. After Filter 1.5, before any other filter, `shadow_usage_<id>_today = max(shadow, thresholdSeconds)`. Logs `SHADOW_ADVANCE` per-event when divergence > 60s and `SHADOW_BREAKDOWN` paired with `BANK_BREAKDOWN` for periodic comparison. Multi-day data informs whether trust-max is safe to switch to as the recording model.

#### Phantom flood detector — initial cross-app rule (commit `83eb923`, **superseded**)

First implementation declared flood when 3+ distinct tracked apps fired events within a 10-second window. Superseded May 10 because the rule false-positives on iPad-9th-gen legit multi-app catch-up bursts: a kid using 3 learning apps in the morning gets all 3 events delivered in one iOS burst, mis-classified as flood, and loses all credit.

#### Phantom flood detector — re-anchored on shielded-reward signal (commit `8f6bd7c`)

The strong, asymmetric signal: a verifiably-shielded reward app cannot produce legit threshold events. The kid physically cannot foreground a blocked app. So events arriving for `shieldHasToken=true` apps are by definition phantom.

The flood TRIGGER moves into Filter 2 (SKIP_SHIELDED). When a shielded-reward-app event hits SKIP_SHIELDED, count tracked apps with arrivals in the last 10s. If ≥1 other app is recent, declare flood (`phantom_flood_active_until = now + 300s`), wipe all open Layer 2 buffers, lockout activates.

Filter 1.7 itself only does two things now: read `phantom_flood_active_until` and SKIP_FLOOD if active; stamp `last_event_arrival_<id>` for the current event.

Trace: Amine's iPhone post-wake flood (08:17:13–14):
- 08:17:13.793 — min.107 for 739C4A42 (shielded reward) → SKIP_SHIELDED. Other apps: 0 in 10s. No flood.
- 08:17:14.114 — min.220 for C6DA269B (shielded reward) → SKIP_SHIELDED. Other apps: 739C4A42 0.3s ago. **PHANTOM_FLOOD_DETECTED**, lockout 300s, all buffers wiped.
- All subsequent events for next 5 min → SKIP_FLOOD.

Result: 0 phantom credit instead of 5 min on FAE1D45B. No spurious notification.

Trace: legit multi-learning-app catch-up (kid uses 3 learning apps in morning, iOS dumps all 3 in burst):
- Each event is for a learning app (not categorized as Reward) → SKIP_SHIELDED never fires
- No flood declared → all 3 catch-up bursts process normally → full credit ✓

#### Edge cases & known gaps

1. **Pure-learning-app phantom isn't caught.** If iOS ever dumps a phantom flood that includes only learning-app events (no reward apps in the burst), no SKIP_SHIELDED fires and the flood detector doesn't trigger. PER_EVENT_CAP still bounds the damage to 60s per event when the burst-window doesn't activate. We have no observed case of this scenario yet.
2. **Reward-app catch-up tail after re-shield can be falsely flagged.** If the kid earns bank, plays a reward app until bank runs out, the app re-shields, and iOS subsequently dumps queued events from that play session, those queued events would hit SKIP_SHIELDED and trigger flood. Layer 3 burst-continuation exemption helps if events arrive within 60s of unshield, but tail events arriving later are vulnerable.
3. **Solo SKIP_SHIELDED events don't escalate.** Required by design — a single stray event for a shielded app could be an iOS one-off, not a full flood. Only blocks individually.
4. **Burst-window timing for mid-day catch-up:** the 5s threshold for "previous event < 5s ago" was chosen empirically. If iOS delivers tail events with longer gaps on slower devices, some credit may still get capped at 60s.
5. **Shadow tracker is observation-only.** It records what trust-max-threshold would have credited but doesn't change real recording. Multi-day data needed before switching to it as the primary model.

#### Files touched

- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
  - Layer 2 fast-forward (`thresholdSeconds = maxSeen` on BUFFER_LEGIT)
  - NEW_DAY `initialUsage = thresholdSeconds` (was hardcoded 60s)
  - `burst_active_until_<id>` flag + PER_EVENT_CAP bypass when active
  - Mid-day burst detection via `last_event_arrival_<id>` < 5s
  - Layer 3 burst-continuation exemption
  - Filter 1.7: SKIP_FLOOD enforcement + arrival stamping
  - SKIP_SHIELDED flood-trigger (shielded reward + ≥1 other app in 10s = flood)
  - Shadow tracker (`shadow_usage_<id>_today`, SHADOW_ADVANCE, SHADOW_BREAKDOWN)
  - Midnight cleanup for new keys
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift`
  - `cleanupExtensionKeys` extended for new keys
  - `scrubOrphanLearningReferences` self-heal at parent-app launch (drops `linkedLearningApps` references to apps no longer in master list)
  - `deleteAppConfiguration` now invokes scrub before Core Data delete
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/AppScheduleService.swift`
  - `scrubDeletedLearningReferences(deletedLogicalIDs:)`
  - `scrubOrphanLearningReferences(validLogicalIDs:)`

#### Memory / pointer

- Commits `1a8347b` (burst-tolerant recording + orphan scrub + shadow tracker) and `8f6bd7c` (flood detection re-anchored on shielded-reward signal) are the post-May-10 baseline. Intermediate commit `83eb923` (cross-app simultaneity rule) was superseded the same day; do not revive that rule on its own.
- Design principle: every filter decision answers "is this burst a flood or a legit catch-up?" The shielded-reward-app event is the discriminator.
- iPad 9th gen and similar lower-RAM devices exhibit bursty iOS DeviceActivity delivery: long silent stretches followed by 1-2s queue dumps. Treat bursts as the norm, not the exception.

---

### May 10, 2026 — Hypothesis: iOS threshold-count budget exceeded

After the May 10 build with Filter 1.7 was installed on Amine's iPhone, a 6+ hour silent stretch was observed: the kid ran a learning app for several minutes, no events fired, no recording, but `MONITORING_ALIVE` and `MONITORING_ALREADY_ACTIVE` heartbeats kept reporting "yes I'm monitoring."

This matches the same symptom shape as Device 1, Device 2, and now Amine's iPhone — three different devices all showing long silent stretches followed by burst dumps. The pattern is too consistent to be hardware. We're now suspecting our app, specifically the threshold registration count.

#### The smoking gun (`Monitoring Log 05.10.2026.rtf` + `ext-log-2026-05-10.log`)

```
[2026-05-10 08:10:14] SLIDING_WINDOW C6DA269B  240 thresholds  ← 4-hour daily limit
[2026-05-10 08:10:14] SLIDING_WINDOW 642B7130  120 thresholds
[2026-05-10 08:10:14] SLIDING_WINDOW 739C4A42  120
[2026-05-10 08:10:14] SLIDING_WINDOW 93088665  120
[2026-05-10 08:10:14] SLIDING_WINDOW E8B1C8C6   60
[2026-05-10 08:10:14] SLIDING_WINDOW FAE1D45B   60
[2026-05-10 08:10:14] SLIDING_WINDOW BB131A01   60
[2026-05-10 08:40:26] MONITORING_START — events=780 (sliding window, 0 min already tracked)
```

**780 threshold events registered against an iOS limit of ~500 per scheduled activity.** That CLAUDE.md note (preserved before the May 6 rewrite) said "iOS ~500 threshold limit — sliding window keeps exactly 60 per app, safe up to 8 apps." That math worked because every app got the same fixed 60-threshold window.

The May 6 per-app right-sized window change tied window size to each app's daily limit (60–240 thresholds). On a device with several long-daily-limit apps it adds up fast: this iPhone hit 780 with 7 apps. Other tested devices likely hit similar over-limit totals.

#### What iOS appears to do when over the limit

We've never received an explicit error from iOS, but the observed pattern is:

1. We call `startMonitoring` with > 500 thresholds.
2. iOS accepts the activity (no error thrown), `MONITORING_ALREADY_ACTIVE` returns true on subsequent polls.
3. iOS does NOT actually fire threshold callbacks for the over-limit set — possibly silently truncates, possibly drops the entire schedule, possibly accepts but never dispatches.
4. The kid uses apps. iOS internally tracks cumulative usage but our extension never gets `eventDidReachThreshold` calls.
5. When our app eventually restarts monitoring (BG task, app launch, or window-rebuild request), iOS dumps queued events all at once — the "phantom flood" we've been chasing.

#### Re-interpreting the phantom-flood symptom

What we labeled "phantom flood" since May 9 is plausibly **legit-but-deferred event delivery**:

- Device 2 May 9 morning: 12 reward apps got ~330 min of credit "phantom" all at once. Reading those events fresh, that could be hours of real cumulative usage iOS held back because our schedule was over-limit, then dumped on monitoring restart.
- Amine's iPhone May 10 morning: 781 events processed in 2 minutes (08:17:13–08:19:21). The number suspiciously matches the 780-event schedule registration count. iOS may have queued one event per registered threshold and released them on the post-wake `startMonitoring` call.

The `SHADOW_BREAKDOWN` shadowEarned values trailing real `todayEarned` on Amine's iPhone today (real=84, shadow=20) is consistent with this: shadow only sees events that arrive while shadow code is running; pre-build events were never seen by shadow.

#### What this means for the layered defense

- **Filter 1.7 (SKIP_SHIELDED-triggered phantom flood lockout)** still helps when the dumped backlog includes events for currently-shielded reward apps — those are unambiguously phantom regardless of whether the underlying cause is iOS's over-limit registration or true cross-day queue carry. Keep it.
- **The bursts were never the root cause.** They were a symptom of iOS deferring events because we registered too many thresholds. The fix needs to address the registration count, not the delivery shape.
- **Layer 2 fast-forward, burst-window cap bypass, mid-day burst detection** are still useful for legit catch-up bursts that happen for OTHER reasons (extension dormancy, midnight transitions, etc.).

#### Proposed direction (for discussion, not implemented yet)

Cap total registered threshold events at ~480 across all apps. Options to consider:

1. **Revert per-app right-sized windows.** Go back to fixed 60 thresholds per app. Lose the longer-look-ahead benefit but stay under the iOS limit reliably.
2. **Dynamic budget allocation.** Compute total budget = 480, divide proportionally based on each app's daily limit. e.g. with 7 apps and limits {240, 120, 120, 120, 60, 60, 60} totaling 780, multiply each by 480/780 ≈ 0.615 to fit within budget. Apps with longer limits still get more thresholds, but no app gets > 480.
3. **Max thresholds per app, regardless of limit.** Cap each app at e.g. 80 thresholds (480/6). Use the existing intra-day window-rebuild infrastructure to extend coverage as the kid approaches the window top.
4. **Multi-activity registration.** Split apps across multiple `DeviceActivityName` activities, each under the 500 limit. iOS treats them independently. More complex to manage but no per-app cap.

#### What needs to be confirmed before fixing

1. **The actual iOS limit.** "~500" is from prior empirical testing; the real number could be 1000 or scheme-dependent. Worth probing experimentally on a clean device — register 1000 thresholds, see if events fire.
2. **Whether iOS truncates or rejects.** Does iOS accept the full 780 and fire only first 500? Does it reject the schedule entirely? Does it accept everything but throttle? This affects which fix strategy works.
3. **Whether the registration is the only cause.** Other devices and other days may have hit silent stretches without being over-limit. If silent stretches happen below 500 events too, there's a separate iOS bug at play.

Until we have these answers, this section stays a hypothesis. The flood-detection layer keeps protecting against the worst-case (phantom credit landing on shielded reward apps). The next step is investigation, not yet code.
