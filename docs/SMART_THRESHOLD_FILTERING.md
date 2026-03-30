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
