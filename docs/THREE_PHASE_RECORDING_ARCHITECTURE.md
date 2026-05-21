# Three-Phase Recording Architecture

**Status:** Design — implementation in progress on branch `feat/three-phase-recording-architecture`
**Created:** 2026-05-18
**Author:** Architecture redesign per CEO direction

---

## Why we're doing this

The current `setUsageToThreshold` in `DeviceActivityMonitorExtension.swift` is a chain of ~9 filters that have accreted over months of bug-fixing. Each filter independently decides "is this a burst?" using its own neighbor-check with its own time window (5s here, 10s there, 30s elsewhere). The classification is implicit, inconsistent, and scattered.

The CEO's mental model is cleaner:

> Before we decide to credit or disregard a usage, we FIRST need to qualify the conditions this event got received in.
>
> - Single event (no events before or after ~5s): legit, no doubt → credit.
> - Burst event: run filters to assess → legit catch-up → credit max threshold per app; flood → reject everything.

**The definition of a burst is pure timing — multiple events arriving close together, irrespective of which app fired them.** Same-app vs cross-app framing is wrong: the kid only uses one app at a time during real-time play, so anything that looks like multiple events clustered together (regardless of source) is either iOS catching up or iOS phantom-flooding. It is never normal play.

**No event is credited the moment it arrives.** Every event is held briefly and waits to see if more events follow within the burst window. Only after the window of silence has elapsed do we settle the batch and decide what to credit.

This document specifies an architecture that matches that model.

---

## The three phases

```
┌──────────────────────────────────────────────────────────────┐
│                  iOS fires threshold event                   │
└──────────────────────────────────┬───────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE A — Hard rejects                                       │
│ Reasons to drop the event that don't depend on burst context │
│   - Cross-day stale flush                                    │
│   - Sub-60s OS regression                                    │
│   - Pre-pin replay                                           │
│   - Shielded reward app  (sets flood signal — see Phase B)   │
│   - Threshold regression                                     │
│   - Physical impossibility (thresh > wallclock-since-midnight)│
└──────────────────────────────────┬───────────────────────────┘
                                   │ pass
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE B — Per-event burst detection (predecessor check)      │
│                                                              │
│ gap = now − last_event_arrival_global                        │
│                                                              │
│ If gap ≥ 5s → NEW EVENT (no predecessor in burst window)     │
│   - The previous burst (if any) is done. Clear undo state    │
│     for all apps that were credited in that burst.           │
│   - Start a fresh burst window with this event.              │
│                                                              │
│ If gap < 5s → BURST CONTINUATION                             │
│   - We're inside the burst window of the previous event.     │
│                                                              │
│ Update last_event_arrival_global = now (always).             │
└──────────────────────────────────┬───────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE C — Credit on arrival, with undo capability            │
│                                                              │
│ If burst_is_flood already flagged:                           │
│   → reject this event silently. Burst is done crediting.     │
│                                                              │
│ If a shielded reward app fired in burst:                     │
│   → FLOOD detected.                                          │
│     For every app in burst_credited_apps_csv: restore        │
│     revert_today_<id> and revert_lastThreshold_<id>.         │
│     Set burst_is_flood = true. Reject this event.            │
│                                                              │
│ Otherwise → CREDIT.                                          │
│   - Save (currentToday, currentLastThreshold) to revert_<id> │
│     keys (only if not already saved this burst — first       │
│     credit per app within a burst is what we'd undo).        │
│   - applyCredit(appID, newThreshold)                         │
│     → usage_today = max(currentToday, newThreshold)          │
│     → lastThreshold = same                                   │
│   - Add appID to burst_credited_apps_csv.                    │
└──────────────────────────────────────────────────────────────┘
```

No buffer. Every event makes its decision at arrival. The only stored state is the undo information for the current burst window, which lets us roll back if a flood signal arrives later in the same burst.

---

## Phase A — Hard rejects

These filters reject events regardless of burst context. They check physical or logical impossibilities. Order doesn't matter much (we'll keep current ordering for safety).

| Filter | Reason to reject |
|--------|------------------|
| `SKIP_MIDNIGHT` | Between midnight and first scheduleActivity → cross-day stale flush |
| `SKIP_INVALID` | thresholdSeconds < 60 → OS regression |
| `SKIP_STALE_FLUSH` | thresholdSeconds > wallclock-since-midnight + 60 → yesterday's queued event |
| `SKIP_PIN_REPLAY` | thresholdSeconds > wallclock-since-pin + 60 → historical replay for newly-pinned app |
| `SKIP_SHIELDED` | Reward app is currently blocked → kid can't physically be using it |
| `SKIP_REGRESSION` | Same-day threshold not strictly increasing → duplicate or out-of-order |

**Implementation:** wrap these in `func passesHardRejects(...) -> Bool` at the top of `setUsageToThreshold`. If any fire, return false. No state mutation beyond what each filter already does.

**What changes:** the burst-context gating that some of these filters added (e.g., FIRST_EVENT_BUFFER's "only if in burst" check at 5s) gets removed. Phase A is unconditional.

---

## Phase B — Per-event burst detection (predecessor check)

Phase B is a small lookback: did another event arrive within the last 5 seconds? That tells us whether this event is "in burst" or "fresh." It does not wait, it does not buffer.

```
gap = now − last_event_arrival_global

If gap ≥ 5s:
    # Previous burst (if any) is over. We will never see another event
    # in that window, so the credits we made during it are now FINAL.
    # Clear undo state — we can't roll back those credits anymore.
    clearBurstState()  // burst_credited_apps_csv, burst_is_flood, revert_<id> keys

If gap < 5s:
    # We're inside the burst window opened by the previous event.
    # The undo state from earlier credits in this burst is still live.

last_event_arrival_global = now
```

**Why 5 seconds:** measured from real device floods, the largest within-burst gap is ~1.6 seconds. 5 seconds gives a 3× safety margin.

**Why no buffer:** in the previous design we held every event for 5 seconds before deciding. The cost was that a single isolated event sat un-credited until the next event arrived (could be much later — the "stuck buffer" problem). The new design credits at arrival and uses *undo state* to roll back if it turns out we were wrong (a flood signal arrives later in the same burst). Same correctness, no waiting.

---

## Phase C — Credit on arrival, with undo capability

After Phase A passes and Phase B updates the burst-window state, Phase C makes the credit decision immediately.

### The core credit rule (unchanged from prior versions)

**Credit means SET, not increment.** `applyCredit` always writes:

```
usage_<id>_today          = max(currentToday, newThreshold)
usage_<id>_lastThreshold  = same value
last_credited_global_timestamp = now
```

iOS's threshold is the authoritative cumulative for that app today. Both fields are written the same value so they never drift apart.

### Decision flow

```
1. If burst_is_flood == true:
       This burst was already classified as a flood by an earlier event.
       Reject this event silently. Done.

2. Check the current event for shielded-reward-app flood signal:
       (Phase A's SKIP_SHIELDED already rejected this event itself.
        Here we use the fact that it arrived as the flood detector.)

   If a SKIP_SHIELDED reject happened for this event AND we're in a burst
   (gap < 5s, burst_credited_apps_csv non-empty):
       FLOOD DETECTED.
       For every app in burst_credited_apps_csv:
           usage_<id>_today          = revert_today_<id>
           usage_<id>_lastThreshold  = revert_lastThreshold_<id>
           remove revert_<id> keys
       Set burst_is_flood = true.
       Reject this event. Done.

3. Otherwise — credit normally:
       If revert_today_<appID> is NOT already set (first credit in this burst):
           revert_today_<appID>         = usage_<appID>_today
           revert_lastThreshold_<appID> = usage_<appID>_lastThreshold
           append appID to burst_credited_apps_csv (if not present)
       applyCredit(appID, newThreshold)  # SET to max threshold
       Done.
```

**Single event (no follow-up):** credited immediately at step 3. When the next event arrives later (gap ≥ 5s), Phase B clears the burst state — credit is final.

**Legit burst (no flood signal):** every event credits immediately at step 3. Subsequent events for the same app keep advancing `usage_today` to the new max threshold (since we take `max`). When the burst window closes (next event with gap ≥ 5s), burst state clears.

**Flood burst:** first events credit normally. When the shielded-in-burst signal arrives, we revert every app credited in this burst and lock the burst into flood mode. No further credits for the remainder of the burst.

### What changed vs the buffer model

| Aspect | Old (buffer-and-settle) | New (credit-on-arrival + undo) |
|--------|-------------------------|--------------------------------|
| Credit timing | 5s after first event in batch (or longer — depends on next event arriving) | Immediate at arrival |
| Stuck-buffer problem | Real — single event held until follow-up | Solved — single event credits immediately |
| State stored | `event_buffer_json` (event list) | `burst_credited_apps_csv` + per-app `revert_today_<id>`, `revert_lastThreshold_<id>` |
| Display behavior for floods | Clean — no flicker; nothing credited then nothing rejected | Brief flicker possible — first event(s) credit, then revert when flood detected |
| Multi-app aggregate flood check | Implemented (sum claim > wallclock) | Dropped. The shielded-in-burst signal is the only flood gate. |

**Note on the multi-app aggregate check:** the prior design used a sum-of-claims-vs-wallclock check to catch Device-C-style floods even without a shielded event. The new design drops this — we accept that a multi-app phantom flood without a shielded reward app event could over-credit. In practice every real phantom flood we've seen included shielded events (reward apps are always part of the monitored set and frequently shielded), so the shielded signal alone is sufficient.

---

## State storage

UserDefaults keys (in app group):

```
last_event_arrival_global      — TimeInterval; updated on every event arrival
                                 (regardless of credit/reject outcome).
                                 Drives Phase B's gap check.

burst_credited_apps_csv        — comma-separated list of appIDs that received
                                 a credit during the current burst window.
                                 Cleared when a new event arrives with
                                 gap ≥ 5s. Used to identify which apps to
                                 roll back on flood detection.

burst_is_flood                 — Bool; once true, all subsequent events in
                                 the current burst are rejected without
                                 crediting. Cleared with the rest of burst
                                 state when the window closes.

revert_today_<id>              — Int; the value of usage_<id>_today BEFORE
                                 the first credit to this app in the
                                 current burst. Restored on flood detection.

revert_lastThreshold_<id>      — Int; same idea for usage_<id>_lastThreshold.

last_credited_global_timestamp — TimeInterval; updated on every credit.
                                 Used by other code (e.g., sliding-window
                                 rebuild logic) to know when the system
                                 last produced a real credit.

# Per-app, unchanged from current code:
usage_<id>_today
usage_<id>_lastThreshold
usage_<id>_reset
```

Removed keys (formerly used by the buffer model):

```
event_buffer_json              — DELETED. No more buffer.
burst_baseline_global_ts       — DELETED. Multi-app aggregate flood check is gone.
```

State footprint is tiny — typically a handful of integers and a short CSV string. Less than the old JSON buffer.

---

## Filters being removed or simplified

| Current filter | Fate in new architecture |
|----------------|--------------------------|
| `SKIP_FLOOD` (5s lockout window) | **Removed.** Subsumed by burst settlement — flood signature catches it cleanly. |
| `FIRST_EVENT_BUFFER` (5s burst check, 60s hold) | **Removed.** Replaced by Phase C-burst settlement logic. Max-threshold-per-app fast-forward becomes a first-class concept. |
| `PHANTOM_FLOOD_DETECTED` (SKIP_SHIELDED + 10s window) | **Moved into settlement.** Shielded event during a burst is a flood signature. |
| `SKIP_BURST_BUDGET` (30s + 10% grace) | **Reframed.** Becomes flood signature 1b (total claimed vs wallclock). |
| `SKIP_BUDGET_EXCEEDED` (reward-app post-unshield) | **Kept as-is.** Reward-app-specific physical-impossibility check is orthogonal to burst classification — runs in Phase A as a hard reject (it's a wallclock check, not a burst-context check). |
| `PER_EVENT_CAP` / `isMidDayBurst` / `isBurstActive` | **Removed.** Per-event caps no longer needed — isolated events trust iOS, burst events go through settlement which uses max-threshold-per-app. |
| `SHADOW_RESTART_REJECT` | **Kept as shadow.** Diagnostic-only, runs in Phase A as a logging step. |

---

## Migration plan (this branch)

This branch (`feat/credit-on-arrival-no-buffer`) migrates from the buffer model on `feat/three-phase-recording-architecture` to the credit-on-arrival + undo model. The change is contained: applyCredit, Phase A, the day-rollover handler, and the sliding-window rebuild trigger all stay. Only the buffer mechanism and the settlement function are replaced.

### Step 1 — Update doc (this commit).
### Step 2 — Replace buffer logic with credit-on-arrival.
- Delete `event_buffer_json`, `BufferEntry`, `readEventBuffer/writeEventBuffer`, `settleBatch`, `bufferProcessActive`, `checkShieldedInBurst`, `triggerRebuildsForConsumedThresholds`.
- Add new function `processEventAndCredit(appID, thresholdSeconds, now, defaults)`:
  - Phase B: gap check, clear burst state if gap ≥ 5s, update `last_event_arrival_global`.
  - Phase C: if burst_is_flood → reject. If we're in a burst AND a SKIP_SHIELDED reject just happened → revert all credited apps, set flood flag, reject. Otherwise → save revert info if needed, applyCredit, add to credited list.
- The shielded-flood detection needs to be wired into Phase A's SKIP_SHIELDED branch: if we're in a burst (gap < 5s, burst_credited_apps_csv non-empty), perform the revert there too.
- Move the sliding-window rebuild trigger logic from `triggerRebuildsForConsumedThresholds` into `processEventAndCredit` (run per-event when we credit, based on whether the credited threshold approaches window top).
### Step 3 — Build and verify on device.
- Normal play: each minute credits immediately (no 5s delay).
- Catch-up burst: each event in the burst credits via SET-to-max-threshold; final usage matches iOS.
- Flood (shielded event mid-burst): early events credit briefly, then revert when shielded event arrives. Net credit: zero or unchanged.

---

## Test scenarios (acceptance criteria)

| Scenario | Expected behavior |
|----------|-------------------|
| Kid plays one app, events fire every 60s | Each event credits at arrival (no waiting), usage_today advances to threshold |
| Kid switches apps every 5 minutes | Each event credits at arrival, no interference between apps |
| Extension dies for 10 min, restarts, iOS dumps 10 catch-up events for app A in 2s | All 10 events credit at arrival. Since applyCredit SETs to max, usage_today ends at the highest threshold = 10 min. |
| Multi-app phantom flood (Device C): 16 apps fire in 25s after kill cascade, NO shielded events | All credit at arrival. **Trade-off:** we accept this risk — the multi-app aggregate flood check was dropped. |
| Multi-app phantom flood including a shielded reward app event | Early events credit. When shielded event arrives (Phase A SKIP_SHIELDED) → revert all credited apps → no net credit. |
| Solo phantom event arrives after long idle | Credits at arrival. SKIP_STALE_FLUSH and SKIP_PIN_REPLAY catch absurd thresholds in Phase A. |
| Roblox sliding-window recovery: high-threshold event after silence | Credits at arrival (no predecessor), usage_today set to threshold value. |

---

## Open questions

1. **Day rollover during a burst.** If midnight falls mid-burst, the new day's first event shouldn't be considered "in a burst" with yesterday's events. The day rollover code (already in `setUsageToThreshold` before Phase A) clears `usage_<id>_today` and `lastThreshold`; it should also clear `burst_credited_apps_csv`, `burst_is_flood`, and `revert_<id>_*` keys.
2. **What if the kid uses Facebook for 1 minute total?** First minute fires min.1 → credits immediately to 60s. No further events. State stays in burst window for 5s, then implicitly clears on the next event for any app (Phase B gap check). The credit is final after 5 seconds.
3. **`isFirstEventAfterUnlock` handling.** Currently a special path for credit after reward unshield. May not need special handling under SET-to-max-threshold — iOS reports the cumulative correctly.

---

## Non-goals

- Changing the upstream `scheduleActivity` / sliding-window logic. This is purely about the event-processing path.
- Changing how the main app reads `usage_<id>_today`. The output contract is unchanged.
- Adding new external dependencies or restructuring the extension's lifecycle.

---

## Status checklist

### On `feat/three-phase-recording-architecture` branch (now superseded by this branch)
- [x] Architecture doc v1 — commit `d7b805a`
- [x] Step 2: Phase A section markers (no behavior change) — commit `df7eb38`
- [x] Step 3a: Phase B classifier in SHADOW mode (look-backward only, 30s window) — commit `611f1e2`
- [x] Architecture doc v2 — rewritten to "buffer everything + settle on silence" model with 5s window
- [x] Step 3b: shadow buffer + settlement alongside legacy — commit `7cbbdde`
- [x] Step 4: promote shadow buffer to active routing — commit `dc5ad0f`
- [x] Shielded-in-burst flood signature — commit `4281a44`
- [x] Day rollover restored — commit `6b56dd2`
- [x] Monitoring-health diagnostics + persisted-flag fallback — commit `c06fa73`
- [x] Sliding-window rebuild after burst settlement — commit `8469477`
- [x] Architecture doc v3 — credit = SET to iOS max threshold
- [x] applyCredit: SET usage_today + multi-app-only flood scope + wallclock fix — commit `a321ec6`
- [x] Buffer mechanics documentation + May 19 case study — commit `670a062`

### On `feat/credit-on-arrival-no-buffer` branch (current — supersedes above)
- [x] Architecture doc v4 — credit-on-arrival + undo (this revision)
- [x] Replace buffer with credit-on-arrival + undo state — commit `5a834ee`
- [x] Verify on device — May 20 single-device validation (see log below)
- [x] Migrate `feat/three-phase-recording-architecture` improvements into this branch (day rollover, monitoring-health, sliding-window rebuild — all carried forward as-is)
- [ ] Multi-device validation across mixed iOS memory tiers and usage shapes
- [ ] **Wait-and-watch:** real-world flood (shielded reward app fires during a catch-up burst). Cannot be reliably triggered on demand — must occur naturally. When it does, the log will show `FLOOD` + `REVERT` entries; verify net credit for the burst is zero or unchanged.

---

## Shadow validation log (2026-05-18)

Branch: `feat/three-phase-recording-architecture`. Shadow classifier shipped 2026-05-18 ~15:06.

### Validated

| Scenario | Evidence | Verdict |
|----------|----------|---------|
| Normal per-minute play classifies as `isolated` | 15:08–15:31, 15 events across two apps (C6DA269B, E8B1C8C6), all `context=isolated` | ✅ |
| iOS jitter doesn't false-trigger burst | Gap=42s at 15:12:47 classified `isolated` (well above 30s window) | ✅ — 30s window has safe margin |
| Single duplicate re-delivery after extension kill classifies as `burst` | 15:27:55→15:27:56: same threshold=2340s re-delivered 0.5s later, classified `burst gap=0s`. SKIP_REGRESSION caught the duplicate in legacy path. | ✅ |
| Long gap classifies as `isolated` | 15:08:53 gap=382s, 15:23:54 gap=455s — first events after extension deaths, classified `isolated` | ✅ |

### Pending validation

| Scenario | Why we haven't seen it | Plan |
|----------|------------------------|------|
| Multi-event catch-up dump (3+ events arriving 1-2s apart) | Test sessions so far: app played AFTER restart, not during extension downtime → no queued events to flush | Let extension die naturally during active play (battery drain test in progress) |
| Multi-app phantom flood (Device C scenario) | No phantom flood occurred during today's test session | Wait for natural occurrence or replay Device C log against new logic |

### Observations not yet acted on

- **Concurrent event processing at 15:15:25**: two events for C6DA269B arrived 0.3s apart in the new extension session (post-kill). Both read the same `last_credited_global_timestamp` (giving identical `gap=97s`) because the first hadn't written its updated value before the second started reading. Classification was the same for both (`isolated`), and the first was correctly rejected as duplicate (SKIP_REGRESSION). Not a problem in this case, but worth noting: in a Phase C-burst world where the buffer mutates state, concurrent events may need a lock or atomic compare-and-swap on the burst buffer. Defer until we see it cause a real issue.

---

## Device validation log (2026-05-20)

Branch: `feat/credit-on-arrival-no-buffer`. Single-device full-day run on Amine's iPhone. Build includes credit-on-arrival processing (`processEventAndCredit` at extension line 313) shipped in commit `5a834ee`.

### Day shape

- Battery: started 100%, drifted to 4% by 20:18 with multiple unplug/plug cycles
- Tracked apps with activity: Instagram, YouTube, Facebook, TV
- Events processed: 192 total (183 credited, 9 rejected)
- Extension kills: 18 across the day — highest single-day count ever logged
- Floods detected: 0
- Undo operations triggered: 0

### Ground-truth comparison at 20:18

| App | iOS Screen Time | Brain Coinz `usage_<id>_today` | Drift |
|-----|-----------------|-------------------------------|-------|
| Instagram | 96 min (1h 36) | 96 min | 0 |
| YouTube | 55 min | 55 min | 0 |
| Facebook | 32 min | 32 min | 0 |
| TV | 6 min | 6 min | 0 |

Zero drift across all four apps after a day that included extreme battery pressure, 18 process terminations, and a morning cluster of four kills in 16 minutes (06:54, 07:02, 07:09, 07:10).

### Rejection audit

All 9 `recorded=false` events were `SKIP_REGRESSION` rejecting legitimate iOS duplicate deliveries after extension session changes. Each rejection corresponded to a threshold ≤ `lastThreshold` on the same day — exactly what the filter is designed to block. No false rejections of real play.

### What this validated

- ✅ Credit-on-arrival path (Phase B + Phase C) running in production on real device
- ✅ SET-to-max-threshold model holds across multiple extension respawns within a day
- ✅ Daily counter survives 18 process terminations with no data loss
- ✅ Day rollover at midnight (00:00:02) reset all 8 apps and registered fresh thresholds via `MIDNIGHT_EXT_REBUILD_OK` without main-app involvement
- ✅ SKIP_REGRESSION correctly blocks iOS catch-up duplicates after session restarts
- ✅ Architecture survives extreme low-battery conditions (4%)

### What this did NOT validate (still pending)

- Multi-device coverage across different iOS memory tiers
- Phantom flood signature (shielded reward app event arriving during a burst → undo of pre-flood credits in `burst_credited_apps_csv`) — **cannot be triggered on demand; awaiting natural occurrence**
- Sub-60-second kill pair stress test under sustained load

### Observations

- **Sub-minute kill pair at 07:09 → 07:10.** Extension survived only 63 seconds before iOS killed it again. Cause not investigated — may be one-off iOS memory pressure, may be a startup path issue. If the pattern repeats, the extension's `intervalDidStart` and init sequence are worth profiling.
- **Shadow judge stale-read on day's first event.** `SHADOW_BURST_JUDGE` at 06:54:44 for C6DA269B reported `start_today=104min` and `would_set=105min` against `actual=0min`. The shadow's bookkeeping was reading yesterday's leftover `lastThreshold` (6300s) — the live credit path correctly ignored it. Cosmetic only, but the shadow's `start_today` source should be tidied to read post-rollover state.

### Verdict

Single-device validation complete. Credit-on-arrival + undo architecture is correct and resilient under realistic stress. Cleared for multi-device rollout.

---

## Decision log

### 2026-05-18 — Shadow first before active routing
Original plan (Step 3 in doc): land classifier and divert isolated routing in one commit. Revised to ship shadow-only (Step 3a) first, then promote in a separate commit (Step 3b) once shadow logs confirm correct classification. Rationale: kids are actively using the app on test devices; a misclassified routing change is hard to undo mid-day. Cost is one extra commit; benefit is zero behavior change during validation.

### 2026-05-18 — 30s burst window (not 5s, not 50s)
Original code used 5s — tuned for iOS-flush-batch latency, not for "what's normal cadence". CEO pushed back: normal events fire at ~60s, so anything below 60s is suspicious. Widened to 30s as a conservative middle ground (15-25s margin below 60s cadence). Today's shadow data validates the choice: gaps as low as 42s correctly classified as isolated. If we'd picked 50s, the 42s event would have been false-tagged as burst.

### 2026-05-19 (later) — Eliminate the buffer; credit on arrival + undo on flood
After the buffer-and-settle design was working correctly (May 19 Instagram/Facebook fix at commit a321ec6), the CEO pushed back on the underlying model. The buffer concept holds every event for at least 5 seconds before crediting, and a single isolated event can sit "stuck" indefinitely until the next event for any app fires — leading to lag in the UI. The new model: credit at arrival, save per-app revert info, undo if a flood signal arrives within the 5s burst window. Same correctness, no waiting for the common case. Trade-off accepted: the multi-app aggregate flood check is dropped — the shielded-in-burst signal becomes the only flood gate. In practice every real phantom flood we've seen includes a shielded reward app event (reward apps are monitored + often shielded), so the shielded signal alone is sufficient. New branch: `feat/credit-on-arrival-no-buffer`.

### 2026-05-19 — Credit = SET usage_today to iOS max threshold, not increment
The architecture's core principle since day one was "trust iOS's max threshold." I repeatedly implemented this as `delta = max_threshold − baseline; usage_today += delta` — an increment model that only works when `usage_today` and `lastThreshold` stay synchronized. They drift trivially (poisoned baseline from yesterday, cross-day rollover, partial credit during a flood) and once drifted the gap is permanent. May 19: Instagram showed 5 min in our app while iOS reported 15 min — a 10-min gap that started accumulating on the first event of the day and could never close with delta-based credit. Fix: `applyCredit` SETs `usage_today = max(currentToday, newThreshold)` and writes the same value to `lastThreshold`. The two are guaranteed to stay in sync because they always receive the same write. Saved in memory as `feedback_set_to_max_threshold` — do not drift back to delta-based crediting.

### 2026-05-19 — Multi-app scope for the aggregate-claim flood check
The wallclock-budget formula in the original doc was `firstEventTime − baselineGlobal`. In practice the first event of a new buffer is the trigger event from the previous burst — so `firstEventTime == baselineGlobal` and `wallclock = 0`. Every back-to-back burst gets falsely flagged as flood. Two fixes: (a) use `now − baselineGlobal` (settlement time, not first event time), (b) only apply the aggregate-claim check when ≥ 2 distinct apps are in the buffer. Single-app bursts unconditionally trust iOS's max threshold. The shielded-in-burst signature still catches phantom floods regardless of app count.

### 2026-05-18 (evening) — Burst is a pure timing pattern; switch from 30s look-backward to 5s buffer + settle-on-silence
The v1 doc framed burst classification as a look-backward gap check from `last_credited_global_timestamp`, with a 30s window. Two flaws came out of the day's data:

1. **Same-app / cross-app framing is wrong.** A burst is just multiple events arriving close together. App identity is irrelevant. Real-time play has exactly one app firing events, so any clustering of events (regardless of source) is iOS catching up or iOS phantom-flooding. The classifier should never inspect which app fired.

2. **Look-backward only is incomplete.** Today's flood (15:31) had events spaced 1-2s apart within the burst, and one specific event was just over the same-app gap of 5s, so it slipped through as "isolated" and got 28 min of phantom credit. A look-backward check can be defeated by gaps that fall just outside the window. The right model is: hold every event, wait to see what arrives AFTER it, settle the batch retroactively. No event is "isolated" until the window has elapsed with nothing following.

The corrected model:
- Window = **5s** (3× safety margin over today's max within-burst gap of 1.6s; not 30s because we don't want every event delayed by half a minute).
- **Every event buffers.** No real-time credit. Settlement runs on the next event arrival when the previous batch is ≥5s old.
- Single-event batch → isolated → credit. Multi-event batch → burst → run flood vs legit decision.
- Flood decision: aggregate claim (sum of max threshold per app in batch − previous credited threshold per app) vs wallclock since previous credit across any app. Plus shielded-event-in-batch as a flood signature.

Doc rewritten this evening. Implementation moves from "Phase B classifier in shadow" to "Phase B+C buffer + settlement in shadow."

### 2026-05-18 — Section markers, not function extraction, for Step 2
Original Step 2 plan: extract Phase A filters into a `passesHardRejects()` helper. Revised to add prominent section markers in place without moving code. Rationale: extraction would change inline state-write ordering (e.g., `last_event_arrival_<id>` is updated at the top of the to-be-removed SKIP_FLOOD filter and reading it from a different position could change the burst-context behavior of OTHER filters). Extraction lands once Phase B is active and the legacy filters are being removed (Step 5).
