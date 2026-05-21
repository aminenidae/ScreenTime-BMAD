/clear# Usage Accuracy: Complete History & Final Architecture

**Created:** February 12, 2026
**Branch:** `test/no-phantom-handling`
**Status:** All fixes applied, testing in progress
**Scope:** December 2025 → February 12, 2026

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [The Problem](#the-problem)
3. [Timeline & Phases](#timeline--phases)
4. [Phase 1: Initial Phantom Detection (Dec 2025)](#phase-1-initial-phantom-detection-dec-2025)
5. [Phase 2: Phantom Fix Attempts 1-21 (Feb 1-9, 2026)](#phase-2-phantom-fix-attempts-1-21-feb-1-9-2026)
6. [Phase 3: The Clean Slate (Feb 10, 2026)](#phase-3-the-clean-slate-feb-10-2026)
7. [Phase 4: Usage Under-Counting Bugs (Feb 11, 2026)](#phase-4-usage-under-counting-bugs-feb-11-2026)
8. [Phase 5: Usage Inflation & Flood Correction (Feb 11-12, 2026)](#phase-5-usage-inflation--flood-correction-feb-11-12-2026)
9. [Final Architecture](#final-architecture)
10. [Extension Memory Optimization](#extension-memory-optimization)
11. [Flood Prevention & Recovery](#flood-prevention--recovery)
12. [UserDefaults Key Reference](#userdefaults-key-reference)
13. [Known Limitations](#known-limitations)
14. [Verification & Testing](#verification--testing)
15. [Lessons Learned](#lessons-learned)
16. [Related Documents](#related-documents)

---

## Executive Summary

iOS DeviceActivityMonitor extensions receive threshold events (min.1, min.2, min.3...) as apps are used. Our extension records these as usage. The core challenge: **when monitoring restarts, iOS sends "catch-up" flood events for ALL cumulative daily usage across ALL tracked apps**. These floods arrive within seconds and, if recorded, inflate usage massively.

Over ~6 weeks and 21+ fix attempts, we evolved from simple time-window filters to a comprehensive architecture that:

1. **Blocks flood events** via a 60-second restart window
2. **Captures iOS ground truth** from flood events (`flood_max` = highest threshold per app)
3. **Corrects usage bidirectionally** using flood_max as the authoritative daily total
4. **Prevents SKIP_REGRESSION** by resetting `lastThreshold` to 0 after every restart
5. **Uses threshold deltas** instead of flat +60s to handle iOS event batching
6. **Optimizes extension memory** to survive under the 6MB hard limit

The final solution accepts that **floods are the primary data source** (not genuine 1-per-minute events) because iOS kills the extension process after processing floods, preventing genuine events from ever arriving.

---

## The Problem

### iOS DeviceActivity Behavior (Undocumented)

1. **Catch-up floods on restart**: When monitoring restarts (app-initiated, iOS daily cycle, or crash recovery), iOS fires threshold events for ALL cumulative daily usage across ALL tracked apps. A device with 9 apps and 30+ minutes each produces 150+ events in <30 seconds.

2. **Thresholds fire once per session**: Each threshold (min.1 through min.60) fires exactly once per monitoring session. After a flood "delivers" them, no new events fire for genuine usage until monitoring restarts again.

3. **Extension process is ephemeral**: iOS aggressively kills DeviceActivityMonitor extension processes after they finish processing events. The extension has a ~30-second lifespan and a 6MB hard memory limit.

4. **Event batching**: iOS may batch threshold events and deliver them hourly rather than every 60 seconds. All events in a batch arrive within <1 second of each other.

### Consequences

Without handling these behaviors:
- **Usage inflation**: Flood events add +60s per threshold, recording 30+ minutes of phantom usage per restart
- **Usage under-counting**: Floods consume all thresholds; genuine usage events never fire
- **Usage loss after restart**: `lastThreshold` retains pre-restart values, causing SKIP_REGRESSION to block genuine events

---

## Timeline & Phases

| Phase | Date | Focus | Outcome |
|-------|------|-------|---------|
| 1 | Dec 2025 | Initial phantom detection | SKIP_RESTART + SKIP_RAPID filters |
| 2 | Feb 1-9, 2026 | 21 fix attempts for post-phantom usage | Multi-layer protection (complex, fragile) |
| 3 | Feb 10, 2026 | Clean slate — remove all 21 attempts | Two surgical guards replace everything |
| 4 | Feb 11, 2026 | Under-counting bugs A & B | intervalDidStart fix + threshold delta |
| 5 | Feb 11-12, 2026 | Inflation & flood correction | Bidirectional correction, dual-path architecture |

---

## Phase 1: Initial Phantom Detection (Dec 2025)

### Problem
Using 1 learning app for 2 minutes recorded 11 minutes across 5 apps. iOS sends threshold events for ALL monitored apps on restart, not just the active one.

### Solution: Three-Layer Detection
- **SKIP_RESTART**: Block events within 120s of monitoring restart (later tuned to 50s, then 55s, then 60s)
- **SKIP_RAPID**: Block events arriving <30s apart for the same app
- **THRESH_DECREASE**: Detect threshold going backwards (catch-up indicator)

### Key Discoveries
- SET semantics (`max(current, threshold)`) fail after restart — iOS resets its counter, so new events have low thresholds that get rejected
- INCREMENT semantics (`current + 60`) work with phantom detection but are vulnerable to double-counting
- Race condition: `monitoring_restart_timestamp` must be set BEFORE `startMonitoring()`, not after
- Darwin notifications don't work in Xcode debugger — added DEBUG polling

### Commits
- `f68ea18` — Initial phantom protection
- `b8f7b53` — Reduce SKIP_RESTART window from 120s to 50s

### Documents
- `PHANTOM_USAGE_FIX_REPORT.md` — Dec 2025 investigation and 5 fixes
- `USAGE_TRACKING_BIBLE.md` — Architecture reference (Dec 2025 vintage)

---

## Phase 2: Phantom Fix Attempts 1-21 (Feb 1-9, 2026)

After Phase 1, a critical problem remained: **after a phantom flood, iOS stops sending new threshold events** because it considers them "delivered." Real usage goes unrecorded.

### The Core Dilemma
- To record new usage → need new threshold events from iOS
- iOS won't send new events → thresholds already "delivered" during flood
- To reset iOS state → must restart monitoring
- Restarting → triggers another catch-up flood

### Failed Approaches (Attempts 1-11)

| Attempt | Approach | Failure Mode |
|---------|----------|--------------|
| 1 | Darwin notification → main app restarts monitoring | Usage inflation on restart |
| 2 | Post-restart catch-up filter | Inflation continued after filter window |
| 3 | Universal threshold guard | Blocked legitimate post-restart usage too |
| 4 | Cadence-based detection | iOS consumed thresholds regardless of blocking |
| 5 | SET semantics (idempotent events) | Under-counted — thresholds are per-session, not daily |
| 5b | Cadence-based INCREMENT | iOS consumed thresholds, no new events |
| 6 | Block + immediate restart | Created infinite restart loop |
| 7 | Delayed restart (wait for quiet period) | Late phantom floods bypassed window filter |
| 8 | Block all rapid-fire regardless of window | First phantom with 92s gap leaked through |
| 9 | Session boundary detection | Partial — helped but didn't solve core issue |
| 10 | Cross-app phantom detection | Partial — blocked cross-app phantoms |
| 11 | Background timer fix (RunLoop.common) | Timer died when app suspended |

### Successful Approaches (Attempts 12-20)

| Attempt | Approach | Result |
|---------|----------|--------|
| 12 | Event buffering with flood detection | Buffer + validate later |
| 13 | Require 3+ rapid events to discard buffer | Fixed false-positive discards |
| 14 | Retry logic with exponential backoff | Monitoring reliably restarts |
| 15 | Block phantom usage for locked reward apps | Shielded apps can't generate real usage |
| 16 | Foreground phantom restart check | Recovery when user opens app |
| 17 | 0.5s stop/start delay + CloudKit throttle | Reduced extension kills |
| 18 | Background task phantom recovery | Recovery via BGAppRefreshTask (~15 min) |
| 19 | Extension-initiated monitoring restart | Direct restart, zero gap |
| 20 | Lightweight flood mode | Skip heavy processing during floods, extension survives |
| 21 | Monitoring health check | Detect silent monitoring deaths |

### Final Multi-Layer System (Attempts 12-20)
The result was a complex 4-layer system:
1. **Event filtering**: 5 filters (monitoring gap, cadence, locked reward, duplicate, buffer)
2. **Buffer validation**: Buffer events, validate with flood detection
3. **Flood detection & recovery**: 4 recovery mechanisms (extension restart, timer, foreground, BGTask)
4. **Prevention**: CloudKit throttle, lightweight flood mode

**Problem**: This system was complex, fragile, and had many interacting state machines.

### Documents
- `PHANTOM_FIX_ATTEMPTS.md` — Detailed log of all 20 attempts
- `PHANTOM_FIX_PLAN_2026-01-28.md` — Investigation and SKIP_RESTART fix
- `PHANTOM_RESTART_LESSONS_LEARNED.md` — Key architectural insights
- `PHANTOM_FILTERING_TEST_RESULTS.md` — Test results
- `PHANTOM_FIX_ATTEMPT_12.md` — Event buffering deep dive

---

## Phase 3: The Clean Slate (Feb 10, 2026)

### Decision: Remove Everything

All 21 attempts of phantom handling code were removed and replaced with **two surgical guards**:

1. **`activities.contains(activityName)`** in ScreenTimeService crash recovery — skips restart if monitoring already active at OS level
2. **60s restart window filter** in `setUsageToThreshold()` — blocks ALL events within 60s of monitoring restart

### Why This Works
- Genuine events can't arrive until 60s+ after restart (1-minute threshold minimum)
- The 60s window catches ALL flood events (they arrive within ~30s)
- No buffering, no flood detection, no restart logic needed
- Event processing is stateless and simple

### What Was Removed
- Event buffering system (buffer/validate/flush)
- Phantom flood detection and counting
- Extension-initiated monitoring restart
- Lightweight flood mode
- Background timer for phantom recovery
- All phantom-specific UserDefaults keys
- Cross-app phantom detection
- Session boundary detection

### Commits
- `2f76291` — Robust event filter chain + extension memory optimization
- `963948c` — Flood prevention & recovery (energy budget reduction)

---

## Phase 4: Usage Under-Counting Bugs (Feb 11, 2026)

Two distinct bugs causing under-counting were discovered from production device logs.

### Bug A: SKIP_REGRESSION After iOS-Initiated Restart

**Evidence:**
```
[19:07:34] INTERVAL_END activity=ScreenTimeTracking
[19:08:59] INTERVAL_START activity=ScreenTimeTracking
[19:11:04] EVENT appID=16CB572C... min=1 currentToday=2520s lastThresh=3600s
[19:11:04] SKIP_REGRESSION threshold=60 <= lastThreshold=3600 (same day)
```

**Root cause**: After `INTERVAL_END`/`INTERVAL_START`, iOS resets its cumulative counter. Events start from min.1 (60s), but `lastThreshold=3600` from the pre-restart epoch. Since 60 <= 3600, SKIP_REGRESSION blocks EVERY genuine event.

Additionally, `intervalDidStart` (iOS-initiated restart) did NOT set `monitoring_restart_timestamp` — only `ScreenTimeService.scheduleActivity()` did. So the 60s restart window filter never activated for iOS-initiated restarts.

**Fix (2 changes):**
1. `intervalDidStart` now sets `monitoring_restart_timestamp` — iOS-initiated and app-initiated restarts handled identically
2. After restart window passes (first event at 60s+), reset `lastThreshold` to 0 for all tracked apps via the restart-reset block

### Bug B: Batch Under-Counting (COOLDOWN + Flat +60s)

**Evidence:**
```
[12:11:45] EVENT appID=4AF106C2... min=16 → SKIP_COOLDOWN (0s < 55s)
[12:11:45] EVENT appID=4AF106C2... min=19 → SKIP_COOLDOWN
[12:11:45] EVENT appID=4AF106C2... min=21 → SKIP_COOLDOWN
[13:11:41] EVENT appID=4AF106C2... min=37 → RECORDED oldToday=240s +60 = 300s
```

Between min.20 and min.37, 17 minutes of real usage accumulated. But flat +60s only captured 1 minute. **83% under-counting** for this app over 7 hours.

**Root cause**: `let newToday = currentToday + 60` always added flat +60s regardless of how many minutes passed since the last recording. iOS batches events hourly, so the first event that passes COOLDOWN should capture the full gap.

**Fix**: Use threshold delta instead of flat +60:
```swift
let delta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60
let newToday = currentToday + delta
```

The `lastThreshold > 0` guard ensures delta is only used when we have a reliable baseline. After restart (lastThreshold = 0), we fall back to safe +60 to prevent phantom amplification.

### Commits
- `2085477` — Capture real usage from flood events to correct under-counting

### Documents
- `USAGE_UNDERCOUNTING_FIX_PLAN.md` — Detailed analysis of both bugs

---

## Phase 5: Usage Inflation & Flood Correction (Feb 11-12, 2026)

### Discovery: Floods Are the Primary Data Source

Testing revealed that the extension process gets killed by iOS after processing flood events. No genuine events arrive after the 60s window. The restart-reset block (which needs a genuine event to trigger) **never fires**.

This means:
- `flood_max` values (iOS ground truth captured during SKIP_RESTART) sit uncorrected in UserDefaults
- `lastThreshold` values from floods stay stale, causing SKIP_REGRESSION
- Usage drift accumulates with every restart cycle

### Bug C: intervalDidStart Timing (Feb 11)

**Problem**: `intervalDidStart()` contained flood correction code that ran BEFORE the current flood arrived. It found no `flood_max` values (they don't exist yet), but marked the restart as "handled" via `ext_lastHandledRestartTimestamp`. This blocked the restart-reset block from applying correction later when `flood_max` WAS populated.

**Fix (attempt 1)**: Strip `intervalDidStart()` to just timestamp setting + logging. Let the restart-reset block handle everything.

**Result**: Restart-reset block never fired because no genuine events arrived after 60s (extension killed).

### Bug D: lastThreshold Set to floodMax (Feb 11)

**Problem**: The restart-reset block set `lastThreshold = floodMax` (e.g., 1740). After restart, iOS resets its counter — events start from min.1 (60s). Since 60 <= 1740, EVERY genuine event was SKIP_REGRESSION'd.

**Evidence:**
```
RESTART_THRESHOLD_RESET: Reset lastThreshold for 9 apps after monitoring restart (with flood correction)
EVENT appID=EFF1E31D... min=1 → SKIP_REGRESSION threshold=60 <= lastThreshold=1740
EVENT appID=EFF1E31D... min=2 → SKIP_REGRESSION threshold=120 <= lastThreshold=1740
EVENT appID=EFF1E31D... min=3 → SKIP_REGRESSION threshold=180 <= lastThreshold=1740
```

User confirmed: "this is legit usage I just ran!!"

**Fix**: Always set `lastThreshold = 0` after restart, regardless of flood_max. The restart-reset block now resets lastThreshold outside the flood correction if/else.

### Bug E: No Genuine Events After Flood (Feb 12)

**Problem**: The extension process is killed by iOS after processing the flood. No genuine events arrive after the 60s window. The restart-reset block (which requires a genuine event to trigger) **never fires**. `flood_max` values sit uncorrected in UserDefaults forever.

**User test**: "no legit usage got recorded after the flood. no threshold call events at all!"

**Key insight**: `intervalDidStart()` runs BEFORE the current flood but AFTER the previous flood. The previous flood's `flood_max` is in UserDefaults, ready to be consumed. Each restart corrects from the previous flood — one cycle delayed but **always fires**.

**Fix**: Restore flood correction in `intervalDidStart()` with critical differences from the original:
1. Process PREVIOUS flood's `flood_max` (bidirectional correction)
2. Always reset `lastThreshold = 0` (iOS resets its counter)
3. Do NOT set `ext_lastHandledRestartTimestamp` (allows restart-reset block as dual correction path)
4. Set `last_flood_correction_timestamp` (suppresses false flood detection during expected catch-up)

### The Dual Correction Architecture

| Path | Trigger | When it fires | What it corrects |
|------|---------|---------------|------------------|
| `intervalDidStart` | Every restart (iOS daily cycle, app-initiated, recovery) | Always | PREVIOUS flood's `flood_max` |
| Restart-reset block | First genuine event after 60s window | Only if extension survives | CURRENT flood's `flood_max` |

Correction cycle:
```
Restart A → intervalDidStart: no previous flood_max → just resets lastThreshold=0
Flood A   → SKIP_RESTART builds flood_max per app. Extension killed.
Restart B → intervalDidStart: finds Flood A's flood_max → APPLIES CORRECTION + resets lastThreshold=0
Flood B   → SKIP_RESTART builds NEW flood_max. Extension killed.
Restart C → intervalDidStart: finds Flood B's flood_max → APPLIES CORRECTION
```

Correction is one restart delayed but **always fires**. Restarts happen frequently: iOS daily cycle (automatic), app-initiated (`scheduleActivity()`), foreground recovery.

### Flood Detection Suppression

Added `last_flood_correction_timestamp` check to flood detection logic. Without this, the expected catch-up flood after restart would trigger `flood_detected` → main app recovery restart → another flood → infinite loop.

Flood detection only fires when `timeSinceCorrection > 120s` (expected catch-up floods complete within ~30s).

### Foreground Recovery Cooldown

Added 5-minute cooldown to foreground flood recovery in `ScreenTimeRewardsApp.swift`. Without this, rapid app foreground/background cycles could trigger recovery loops:
```
foreground → flood_detected → restart → flood → flood_detected → foreground → restart → ...
```

### Commits
- `c4fe506` — Restore intervalDidStart flood correction (one-restart-delayed dual path)

---

## Final Architecture

### File: `DeviceActivityMonitorExtension.swift`

The extension processes threshold events through a 5-filter chain, then records usage:

```
eventDidReachThreshold(event)
         │
         ▼
   recordUsageEfficiently()
         │
         ▼
   setUsageToThreshold()
         │
    ┌────┴─────────────────────────────────────────────┐
    │              FILTER CHAIN                         │
    │                                                   │
    │  Filter 1: 60s Restart Window                    │
    │  → SKIP_RESTART (capture flood_max)              │
    │                                                   │
    │  [Restart-Reset Block]                           │
    │  → Bidirectional flood correction                │
    │  → Reset lastThreshold=0                         │
    │                                                   │
    │  Filter 2: 55s Per-App Cooldown                  │
    │  → SKIP_COOLDOWN                                 │
    │                                                   │
    │  Filter 3: Minimum Threshold (< 60s)             │
    │  → SKIP_INVALID                                  │
    │                                                   │
    │  Filter 4: Shielded Reward App                   │
    │  → SKIP_SHIELDED                                 │
    │                                                   │
    │  Filter 5: Threshold Progression                 │
    │  → SKIP_REGRESSION (same day: must increase)     │
    │  → SKIP_DUP (cross-day: block exact duplicates)  │
    └──────────────┬───────────────────────────────────┘
                   │
                   ▼
            RECORD USAGE
         (day rollover or same-day delta)
```

### Filter 1: 60s Restart Window (lines 300-329)

Blocks ALL events within 60s of monitoring restart. During this window, captures `flood_max` per app (highest threshold = iOS daily cumulative ground truth).

```swift
if timeSinceRestart < 60.0 && restartTimestamp > 0 {
    // Block event
    // Capture flood_max (iOS ground truth)
    let floodMaxKey = "flood_max_\(appID)"
    if thresholdSeconds > currentFloodMax {
        defaults.set(thresholdSeconds, forKey: floodMaxKey)
    }
    return false
}
```

### Restart-Reset Block (lines 331-368)

On the first event past the 60s window, corrects usage from flood_max and resets lastThreshold:

```swift
if restartTimestamp > lastHandledRestart && restartTimestamp > 0 {
    for trackedAppID in trackedAppIDs {
        // Bidirectional flood correction
        if floodMax != currentToday {
            let correction = floodMax - currentToday
            defaults.set(floodMax, forKey: todayKey)    // Correct UP or DOWN
            defaults.set(max(0, total + correction), forKey: totalKey)
        }
        // Always reset lastThreshold to 0
        defaults.set(0, forKey: lastThresholdKey)
    }
    defaults.set(restartTimestamp, forKey: "ext_lastHandledRestartTimestamp")
}
```

### intervalDidStart (lines 122-167)

Runs before the current flood, after the previous flood. PRIMARY correction path:

```swift
override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
    // Set restart timestamp + flood detection suppression
    defaults.set(now, forKey: "monitoring_restart_timestamp")
    defaults.set(now, forKey: "last_flood_correction_timestamp")

    // Correct from PREVIOUS flood's flood_max
    for trackedAppID in trackedAppIDs {
        if floodMax > 0 && floodMax != currentToday {
            // Bidirectional correction
        }
        defaults.removeObject(forKey: floodMaxKey)
        defaults.set(0, forKey: lastThresholdKey)  // Always reset
    }
    // NOTE: Do NOT set ext_lastHandledRestartTimestamp
}
```

### Usage Recording (lines 474-519)

Uses threshold delta for same-day recording to handle iOS event batching:

```swift
let delta = (lastThreshold > 0) ? max(60, thresholdSeconds - lastThreshold) : 60
let newToday = currentToday + delta
```

- **Normal 1-per-minute events**: delta = 60 (unchanged behavior)
- **Batched events**: delta = full gap (e.g., 1020 for 17-minute gap)
- **After restart**: lastThreshold=0, delta=60 (safe fallback)

### File: `ScreenTimeRewardsApp.swift`

Foreground flood recovery (Layer 3):
- Checks `flood_detected` flag when app becomes active
- 5-minute cooldown prevents recovery loops
- Triggers `restartMonitoring()` if stale flag found (>65s old)

### File: `ScreenTimeService.swift`

- `scheduleActivity()` sets `monitoring_restart_timestamp` before `startMonitoring()`
- Auto-restart 65s after crash recovery (ensures fresh thresholds)
- `restartMonitoring()` with retry logic (3 attempts, exponential backoff)

---

## Extension Memory Optimization

The extension has a **6MB hard memory limit**. Several critical optimizations were applied:

| Issue | Before | After | Savings |
|-------|--------|-------|---------|
| `debugLog` | Read-parse-rewrite ~500KB per call | O(1) append-only with size-based trim | ~7-10MB per event |
| `DateFormatter` | Created fresh 12-16x per event | Cached as `static let` | ~200KB per event |
| Decoders/Encoders | Created fresh each call | Cached as `static let` | ~350KB-1.1MB per event |
| Shield configs | Decoded twice per event | Decoded once, passed to both functions | ~100KB per event |
| `dictionaryRepresentation()` | Materialized ALL UserDefaults | `tracked_app_ids` string array | ~500KB per call |
| CloudKit framework | Always loaded (~1-2MB) | Gated behind `ext_cloudkit_sync_enabled` (default false) | ~1-2MB |

### Document
- `EXTENSION_MEMORY_OPTIMIZATION_PLAN.md` — Full analysis and implementation plan

---

## Flood Prevention & Recovery

### Prevention: Reduce Extension Kills

iOS kills the extension due to energy budget exhaustion. Background task reduction:

| Task | Before | After | Rationale |
|------|--------|-------|-----------|
| Config check | 15 min poll | 6-hour fallback | CloudKit push handles real-time |
| Shield state sync | 15 min | Merged into usage-upload (30 min) | Same direction, eliminate overhead |
| Usage upload | 30 min | 30 min (unchanged) | Only way to get data from extension to parent |

**Result**: ~78% fewer background wakeups/day (240 → 52)

### Recovery: Three Layers

| Layer | Mechanism | When | Delay |
|-------|-----------|------|-------|
| 1 | Extension flood detection | During flood processing | Immediate flag |
| 2 | Auto-restart after crash recovery | 65s after `scheduleActivity()` | 65 seconds |
| 3 | Foreground recovery | User opens app | 5-min cooldown |

### Document
- `FLOOD_PREVENTION_AND_RECOVERY_PLAN.md` — Full prevention and recovery architecture

---

## UserDefaults Key Reference

### Usage Tracking Keys

| Key | Type | Purpose |
|-----|------|---------|
| `usage_<appID>_today` | Int | Today's usage in seconds |
| `usage_<appID>_total` | Int | All-time usage in seconds |
| `usage_<appID>_lastThreshold` | Int | Last recorded threshold (for regression check) |
| `usage_<appID>_reset` | Double | Timestamp of last daily reset |
| `usage_<appID>_modified` | Double | Timestamp of last modification |
| `ext_usage_<appID>_today` | Int | Today's usage (ext_ mirror, source of truth for main app sync) |
| `ext_usage_<appID>_total` | Int | All-time usage (ext_ mirror) |
| `ext_usage_<appID>_date` | String | Date of last update (YYYY-MM-DD) |
| `ext_usage_<appID>_hour` | Int | Hour of last update (0-23) |
| `ext_usage_<appID>_hourly_N` | Int | Usage in hour N (0-23) |
| `ext_usage_<appID>_timestamp` | Double | Unix timestamp of last update |

### Monitoring & Restart Keys

| Key | Type | Purpose |
|-----|------|---------|
| `monitoring_restart_timestamp` | Double | Set before `startMonitoring()`, used by 60s filter |
| `ext_lastHandledRestartTimestamp` | Double | Prevents restart-reset block from firing twice |
| `last_flood_correction_timestamp` | Double | Suppresses false flood detection during expected catch-up |
| `tracked_app_ids` | [String] | List of all tracked app IDs (avoids `dictionaryRepresentation()`) |
| `wasMonitoringActive` | Bool | Tracks if monitoring should be active |

### Flood Detection & Correction Keys

| Key | Type | Purpose |
|-----|------|---------|
| `flood_max_<appID>` | Int | Highest threshold during SKIP_RESTART (iOS ground truth) |
| `flood_skip_count` | Int | Count of SKIP_RESTART events in current window |
| `flood_detected` | Bool | Flag: unexpected flood detected, recovery needed |
| `flood_detected_time` | Double | Timestamp of flood detection |
| `last_flood_recovery_timestamp` | Double | 5-minute cooldown for foreground recovery |

### Per-App Filter Keys

| Key | Type | Purpose |
|-----|------|---------|
| `last_recorded_<appID>` | Double | Timestamp of last recording (55s cooldown) |
| `last_recorded_timestamp` | Double | Global last recording timestamp (diagnostics) |

### Extension Lifecycle Keys

| Key | Type | Purpose |
|-----|------|---------|
| `extension_debug_log` | String | Rolling debug log (~50KB, 200 lines) |
| `monitoring_lifecycle_log` | String | Start/stop/kill events (~100KB, 400 lines) |
| `ext_last_session_id` | String | Last extension session UUID (kill detection) |
| `extension_heartbeat` | Double | Last extension activity timestamp |
| `extension_initialized` | Double | Extension init timestamp |
| `ext_cloudkit_sync_enabled` | Bool | Gate for CloudKit in extension (default false) |

---

## Known Limitations

### One-Restart-Delayed Correction

Flood correction in `intervalDidStart` processes the PREVIOUS flood, not the current one. Usage values may be temporarily inaccurate until the next restart. In practice, restarts happen frequently (daily iOS cycle, app opens, foreground recovery).

### ~2 Minute Tracking Gap

Between flood processing and the next genuine event (if one arrives), there's a ~2 minute blind spot. The 60s window blocks everything, and genuine events need at least 60s of usage to fire.

### Daily Limit: 60 Thresholds

Only 60 thresholds are configured per app (min.1 through min.60). Apps used for more than 60 minutes in a day have no threshold events after the 60th minute. Usage beyond 60 minutes relies on flood correction from subsequent restarts.

### Extension Killed Before Genuine Events

iOS kills the extension process after processing flood events. Genuine events that should arrive after the 60s window are never received. This is why `intervalDidStart` is the PRIMARY correction path, not the restart-reset block.

### Requires At Least One Restart

If the extension process is killed and no restart ever occurs (monitoring dead, user never opens app), usage is lost. The foreground recovery (Layer 3) requires the user to open the app at least once.

---

## Verification & Testing

### Test 1: Normal Usage Recording
1. Configure a learning app
2. Use it for 3 minutes
3. Check usage = ~180s
4. Use 2 more minutes → ~300s

### Test 2: Flood Handling (Build-Triggered)
1. Note current usage
2. Build and run in Xcode (triggers restart → flood)
3. Usage should NOT inflate
4. Extension log shows SKIP_RESTART for all flood events
5. `flood_max_<appID>` values captured

### Test 3: Flood Correction
1. Trigger a flood (restart monitoring)
2. Trigger ANOTHER restart (daily cycle or manual)
3. Lifecycle log should show `FLOOD_CORRECTION <appID>... Xs → Ys`
4. Usage values should converge with iOS Screen Time

### Test 4: Post-Restart Recording
1. Trigger restart
2. Wait 60s+ for window to pass
3. Use a tracked app for 2+ minutes
4. Events should show RECORDED (no SKIP_REGRESSION)
5. `lastThreshold=0` confirmed in restart-reset block log

### Test 5: iOS Daily Cycle
1. Wait for iOS INTERVAL_END → INTERVAL_START cycle (typically overnight)
2. Lifecycle log should show INTERVAL_START with restart timestamp
3. Next day's events should record normally
4. Previous day's flood_max should be corrected

### Test 6: Event Batching
1. Use app for 10+ minutes
2. Check if iOS batches events (all arrive in a burst)
3. RECORDED log should show `+delta` values > 60 (e.g., `+1020` for 17-min gap)
4. Total usage should match actual usage time

---

## Lessons Learned

### 1. Floods Are the Primary Data Source
The extension is ephemeral (~30s lifespan). iOS kills it after processing floods. Genuine 1-per-minute events are rare. The architecture must work with floods alone.

### 2. iOS Thresholds Are Per-Session, Not Daily
Each monitoring session has its own counter. After restart, iOS resets to min.1. `lastThreshold` from a previous session will block all new events via SKIP_REGRESSION.

### 3. Bidirectional Correction Is Essential
Flood_max can be higher (under-counting) or lower (inflation from previous bugs) than current usage. Correction must go both directions. `max(0, total + correction)` prevents negative totals.

### 4. Never Set ext_lastHandledRestartTimestamp in intervalDidStart
This blocks the restart-reset block from firing. Since intervalDidStart processes the PREVIOUS flood and the restart-reset block processes the CURRENT flood, both paths must remain open.

### 5. Extension Memory Is the Hardest Constraint
6MB hard limit. Every allocation counts. `debugLog` with read-parse-rewrite was the #1 killer — caused 7-10MB of transient allocations per event. O(1) append-only with size-based trim solved it.

### 6. Simplicity Beats Complexity
21 attempts with buffering, flood detection, extension restart, lightweight flood mode, Darwin notifications, BGTask recovery — all replaced by two surgical guards + flood correction. The final architecture has fewer moving parts and handles more edge cases.

### 7. Extension-Initiated Restart Does NOT Work
Proven in Attempt 19/20: the extension CAN restart monitoring, but iOS immediately fires all thresholds for apps with cumulative usage, creating another flood that kills the extension. The 60s filter + flood correction approach is more reliable.

### 8. Race Conditions at Monitoring Boundaries
`monitoring_restart_timestamp` MUST be set BEFORE `startMonitoring()`. Otherwise, early catch-up events arrive before the timestamp exists, bypassing the 60s filter.

### 9. intervalDidStart Runs Before Floods
This is the critical timing insight. `intervalDidStart` → 30s → flood events arrive → extension killed. This means:
- `intervalDidStart` CAN'T process the current flood (doesn't exist yet)
- `intervalDidStart` CAN process the previous flood (already in UserDefaults)
- This one-cycle-delayed correction always fires because intervalDidStart always runs

### 10. iOS Event Batching Is Real
iOS doesn't always deliver events every 60 seconds. It may batch them hourly. The threshold delta approach (`thresholdSeconds - lastThreshold`) handles this correctly. Flat +60s loses accumulated minutes.

---

## Related Documents

| Document | Content | Status |
|----------|---------|--------|
| `PHANTOM_USAGE_FIX_REPORT.md` | Dec 2025 initial investigation | Historical — superseded by this document |
| `USAGE_TRACKING_BIBLE.md` | Dec 2025 architecture reference | Historical — needs update |
| `PHANTOM_FIX_PLAN_2026-01-28.md` | Jan 2026 SKIP_RESTART fix | Historical — superseded |
| `PHANTOM_RESTART_LESSONS_LEARNED.md` | Feb 1 revert and insights | Historical — superseded |
| `PHANTOM_FIX_ATTEMPTS.md` | Attempts 1-20 detailed log | Historical — reference only |
| `PHANTOM_FIX_ATTEMPT_12.md` | Event buffering deep dive | Historical — approach removed |
| `PHANTOM_FILTERING_TEST_RESULTS.md` | Test results | Historical |
| `USAGE_UNDERCOUNTING_FIX_PLAN.md` | Bugs A & B analysis | Current — still accurate |
| `EXTENSION_MEMORY_OPTIMIZATION_PLAN.md` | Memory optimization plan | Current — all applied |
| `FLOOD_PREVENTION_AND_RECOVERY_PLAN.md` | Energy budget + 3-layer recovery | Current — still accurate |
| `USAGE_ACCURACY_IMPROVEMENT_PLAN.md` | Earlier improvement plan | Historical — superseded |

---

*This is the authoritative reference for all usage tracking accuracy work. It supersedes all previous phantom fix documents.*
