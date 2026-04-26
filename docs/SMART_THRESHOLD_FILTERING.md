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

**Status:** DISCOVERED — NOT YET FIXED

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
