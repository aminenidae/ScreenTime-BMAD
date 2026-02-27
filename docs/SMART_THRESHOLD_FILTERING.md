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
| **SKIP_COOLDOWN** (55s per-app) | Same app can't fire twice in <55s | Silently drops burst events (NO catchup_max capture — late bursts can carry stale cross-midnight data) |
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

**Trade-off:** Legitimate mid-day SKIP_COOLDOWN burst corrections are still lost (10-20 min undercount possible). The sliding window self-corrects over subsequent restart cycles. SKIP_RESTART captures now recover the most important case: usage between midnight and first app foreground.

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

**Daytime threshold exhaustion (new finding):** With 60 thresholds per app, heavy usage (>60 min since last `scheduleActivity()`) exhausts all thresholds mid-day, silently killing monitoring for that app. The extension cannot call `scheduleActivity()` — only the main app can. If the user doesn't open the app, monitoring remains dead until the next foreground activation.

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
4. **SKIP_COOLDOWN does NOT capture** catchup_max — late bursts (40+ min after restart) can carry stale data through extension kill/relaunch cycles

**Correction paths (2 active):**

| Path | Location | When |
|------|----------|------|
| `readExtensionUsageData()` | Main app ScreenTimeService | On foreground sync — **main recovery path**, works even when no events fire |
| NEW_DAY branch | Extension `setUsageToThreshold()` | When child uses app again — `thresholdSeconds` already includes catchup usage via iOS cumulative |

Note: `intervalDidStart()` same-day correction and before-recording correction paths from the Feb 20 era are no longer present. The main app's `readExtensionUsageData()` is now the primary recovery path, which is simpler and doesn't require extension-side correction logic.

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

**Status:** Confirmed. Architectural constraint with two contributing bugs. Fix in progress (Approach 1: BGTask + scheduleActivity).

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
