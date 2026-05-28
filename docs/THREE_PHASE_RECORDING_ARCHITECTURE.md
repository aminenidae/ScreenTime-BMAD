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

**Update 2026-05-23:** the "every real phantom flood includes shielded events" assumption broke. On Amine's iPhone, an 8-app phantom flood fired at kill-respawn while every reward app was already unshielded (pool=2474min, all goals met). The shielded-in-burst signal could not fire; over-credit went through (Mobile Legends +69min, YouTube +66min, Mini Motorways +69min). The shadow burst-judge correctly classified `verdict=phantom` from the kill-replay signature but was diagnostic-only. **Resolution:** the wall-clock budget check (multi-app aggregate, originally dropped from this section) has been re-introduced in shadow mode. More importantly, the heal mechanism shipped same day fundamentally changes the threat model — phantom credits no longer need to be perfectly prevented because they can be corrected after the fact via iOS ground-truth catch-up. See "2026-05-23 — Heal mechanism" below for the architectural realization.

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
| Multi-app phantom flood (Device C): N apps fire after kill, NO shielded events | Early events credit at arrival. Two layers of defense: (1) the wall-clock budget check (shadow, logs `SHADOW_BUDGET_CHECK verdict=exceeded\|within`) — promotes to enforcement after validation. (2) When promoted, `verdict=exceeded` will trigger a silent heal rather than `revertBurstCredits` — heal asks iOS for ground truth and overwrites whatever the phantom credited. See heal section below. |
| Multi-app phantom flood including a shielded reward app event | Early events credit. When shielded event arrives (Phase A SKIP_SHIELDED) → revert all credited apps → no net credit. |
| Solo phantom event arrives after long idle | Credits at arrival. SKIP_STALE_FLUSH and SKIP_PIN_REPLAY catch absurd thresholds in Phase A. |
| Roblox sliding-window recovery: high-threshold event after silence | Credits at arrival (no predecessor), usage_today set to threshold value. |
| User triggers heal (manual button or future auto-trigger) | Today's usage zeros, sliding window re-registers at current=0, iOS delivers catch-up burst covering today's authoritative cumulative for every app. Anti-phantom defenses respect `heal_active_until` and stand aside. Validated 2026-05-23 — three apps healed to ±1 min of iOS Screen Time. |
| Long-absence phantom (Flaw 1: phantom fits inside large wall-clock budget) | Budget check passes (verdict=within), credit lands. Auto-heal trigger (future) gated on "wall-clock was suspiciously large" calls heal to verify against iOS ground truth — phantom credit gets overwritten. |

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
- [x] Verify on device — May 20 single-device validation (Amine's iPhone, see log below)
- [x] Second-device validation — May 20 Betty's iPhone with multi-reinstall catch-up burst (see log below)
- [x] Migrate `feat/three-phase-recording-architecture` improvements into this branch (day rollover, monitoring-health, sliding-window rebuild — all carried forward as-is)
- [ ] Multi-device validation across mixed iOS memory tiers and usage shapes (one more device beyond Amine's + Betty's)
- [x] **Wait-and-watch:** real-world phantom flood — observed 2026-05-21 on Amine's iPhone (see log below). FLOOD + REVERT path worked correctly; but uncovered a post-flood recording blackout (~10h) caused by iOS-side threshold exhaustion with no rebuild trigger
- [ ] **Post-flood recovery fix:** add `requestMainAppWindowRebuild` call inside `revertBurstCredits` so a full `restartMonitoring` kicks off automatically the moment a flood is reverted (see "2026-05-21 — Phantom flood + recovery hole" below)
- [x] **Multi-app phantom flood without shielded events** — observed 2026-05-23 morning on Amine's iPhone. Initial shape-based enforcement attempt rolled back same day. Replaced by wall-clock budget check (shadow) and the heal mechanism. See "2026-05-23 — Multi-app phantom flood without shielded events" + "2026-05-23 — Heal mechanism" below.
- [x] **Wall-clock budget check** — shipped in shadow mode 2026-05-23 (`SHADOW_BUDGET_CHECK`). Heal-mode bypass added so heal's own catch-up can't trip it.
- [x] **Heal mechanism (extension-canonical)** — manual button validated 2026-05-23, three apps healed to ±1 min of iOS Screen Time. Refactored to extension-canonical implementation same day.
- [ ] **Auto-heal triggers** — wire judge verdicts and budget anomalies to call `performHealUsage` silently. Thresholds and cooldown TBD.
- [ ] **Production-ready user-facing heal button** — friendlier UX wording, silent-update mode that doesn't visibly flicker the dashboard.

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

## Second-device validation log (2026-05-20 — Betty's iPhone)

Branch: `feat/credit-on-arrival-no-buffer`. Same build as Amine's device. Distinct in that this device had an expired subscription and ran on dev-bypass for most of the day (no proper monitoring schedule), then was reinstalled twice in the evening:

1. **~21:44** — reinstall from TestFlight (proper monitoring resumed)
2. **~22:04** — fresh TestFlight install picked up by iOS
3. **~22:15** — Xcode dev build installed to access diag menu

Each install reset the extension's session ID and triggered iOS to dump catch-up threshold events for the cumulative usage it had been tracking independently.

### Ground-truth comparison at 22:15

| App | iOS Screen Time | Brain Coinz app display | Drift |
|-----|-----------------|------------------------|-------|
| Instagram | 2h 36m (156 min) | 2h 36m | 0 |
| YouTube | 1h 14m (74 min) | 1h 14m | 0 |
| Facebook | 54 min | 56 min | +2 min |
| WhatsApp | 11 min | 11 min | 0 |

The +2 min Facebook drift is rounding noise (Apple Screen Time and our minute-bucket boundary aren't perfectly aligned).

### How the catch-up recovery played out

The Instagram timeline is the clean illustration:

| Time | Wake event | Instagram `lastThreshold` jumps to |
|------|-----------|-----------------------------------|
| 05:03–05:22 | Sequential per-minute play | min 20 |
| 21:44:36 | First post-reinstall extension wake | min 40 (catch-up burst) |
| 21:45 | Continued flood from same wake | min 80 |
| 22:04 | TestFlight install wake | min 120 |
| 22:15 | Xcode install wake | **min 156** (matches iOS) |

At each wake, iOS fired a flurry of threshold events out-of-order. Our extension accepted each ascending threshold and rejected the duplicates as `SKIP_REGRESSION`. Three apps recovered in parallel from these floods (Instagram, YouTube, Facebook) with no cross-app interference.

### What this validated

- ✅ Legit catch-up recovery works across **multiple same-day reinstalls** — iOS retains its cumulative threshold queue across app reinstalls, and the new extension binary correctly absorbs the replay
- ✅ `MAPPING_RECOVERED` (stable-hash backfill of event-name → appID after extension state wipe) restored mappings without losing usage data
- ✅ `SKIP_REGRESSION` correctly filters the out-of-order portion of the catch-up replay without rejecting the ascending portion
- ✅ Multi-app concurrent recovery — Instagram, YouTube, and Facebook all caught up in interleaved fashion in the same 1.5-second window at 21:44:36
- ✅ Subscription/dev-bypass transition does not corrupt the day's cumulative once monitoring resumes

### What this did NOT validate (still pending)

- **Phantom flood with shielded event in burst** — no shielded reward app fired during any of the three catch-up bursts on this device, so the `FLOOD` + `REVERT` path was not exercised. Still awaiting natural occurrence.

### Coverage status after May 20

| Path | Status |
|------|--------|
| Single event (no neighbors within 5s) → credit on arrival | ✅ Validated (Amine + Betty) |
| Legit catch-up burst (multiple ascending events within 5s, no shielded signal) | ✅ Validated (Betty — three separate bursts) |
| Phantom flood (shielded reward app event arriving during burst) | ✅ Validated 2026-05-21 (Amine — see section below). Net credit zero; flood revert worked. **But** uncovered a post-flood recording blackout, fix planned. |

---

## 2026-05-21 — Phantom flood + recovery hole (Amine's iPhone)

First natural phantom flood observed since shipping the credit-on-arrival + undo architecture. The flood classifier itself worked exactly as designed. But the *aftermath* exposed a gap: once a flood fires, iOS's registered sliding-window thresholds are consumed by the burst, and the current architecture has no automatic path to re-register them. Result on this device: ~10 hours of completely silent recording until a manual force-restart at 13:57.

### What the flood looked like

`ext-log-2026-05-21.log`, session `5681D16A`:

- **03:10:52.283** — One legit credit lands first: BB131A01 (Instagram) → 180s on min.3 (`RECORDED ... newToday=180s`)
- **03:10:52.554** — 0.27s later, shielded reward app C6DA269B fires during the same 5s burst window → `BURST_REVERT reason=shield-in-burst-C6DA269B appsReverted=1 — BB131A01(180s→0s)`
- **03:10:52.559** — `PHANTOM_FLOOD_DETECTED` locks out 30s
- **03:10:52.589–03:10:55.547** — Next ~110 events for 8 apps silently rejected as `SKIP_FLOOD`

Threshold values reported during the flood reached **min.30 (Instagram), min.20 (Facebook), min.19 (YouTube)** — confirming this was iOS dumping its full queued event backlog in 3 seconds.

### The dead 10-hour tail

After the flood, the log contains **zero threshold events** until the manual restart at 13:57. Three app launches in between (06:13, 11:30, 13:32) all logged `MONITORING_ALIVE — OS confirms active, skipping restart`. From iOS Screen Time at 13:34: Instagram 20 min, Facebook 6 min — real usage that our recording missed entirely.

### Root cause — two sliding-window states diverged

There are two "sliding window" states, and the flood hit them differently:

1. **iOS's registered thresholds** (the bells iOS will ring): every one of these fired during the flood, even though our extension rejected each event as SKIP_FLOOD. Once iOS rings a bell, it's gone. **State after flood: empty.**

2. **Our internal counter** `usage_<id>_today`: correctly reverted by `revertBurstCredits` back to its pre-flood value (0 for every app today, since BB131A01 was the only credit and it was rolled back). **State after flood: untouched/zero.**

The rebuild trigger (`triggerRebuildIfNearWindowTop` at line 341, and the state-based `WINDOW_TOP_HIT` check at line 1673) both require a successful credit to fire. Flood-rejected events skip both. The main-app safety net (`scheduleActivity` on app open) is gated by `MONITORING_ALIVE` skip-restart, which exists specifically to prevent phantom floods on every app launch.

Net effect: iOS believes monitoring is alive, but the schedule is an empty husk. No bell to ring → no callback to our extension → 10 hours of silence.

### Force-restart validation (13:57)

To test the recovery hypothesis, manually triggered `restartMonitoring` via the diag menu's `settings_refresh_tracking_button`. Same log file, session `B0D1F227`:

- **13:57:33** — `MONITORING_RESTART — reason: settings_refresh_tracking_button`
- **13:57:34** — Extension killed, fresh session B0D1F227 starts
- **13:57:49.556** — First catch-up arrives: `RECORDED appID=BB131A01... newToday=120s` (Instagram min.2)
- **13:57:49.643** — `RECORDED appID=E8B1C8C6... newToday=120s` (Facebook min.2)
- **13:57:49.695–13:57:52.061** — iOS dumps the rest. Instagram climbs 2 → 13 → 14 → 15 → 18 → 20. Facebook 2 → 6
- **13:57:52** — Final state: Instagram=20 min, Facebook=6 min. **Matches iOS Screen Time exactly.**

`EXT_REBUILD_APP` log at 13:57:52 confirms the rebuild registered windows based on the *correctly reverted* counters and shows the iOS-actual-cumulative for every app:

| App | Rebuild window | iOS catch-up fires | Real today usage |
|-----|----------------|---------------------|------------------|
| BB131A01 (Instagram) | 21–40 (post-credit) | min.2 → 3 → 13 → 14 → 15 → 18 → 20 | **20 min** |
| E8B1C8C6 (Facebook) | 7–26 (post-credit) | min.2 → 6 | **6 min** |
| C6DA269B (reward) | 1–90 | none | **0 min** |
| D63AE4AA (reward) | 1–20 | none | **0 min** |
| 642B7130 (reward) | 1–90 | none | **0 min** |
| 739C4A42 (reward) | 1–5 | none | **0 min** |
| 93088665 (reward) | 1–5 | none | **0 min** |
| FAE1D45B | 1–30 | none | **0 min** |

### Zero flood re-trigger — and why

Two reinforcing reasons the recovery burst credited cleanly:

1. The catch-ups themselves satisfied today's goals (BB131A01 hit 5 min in the first second of the recovery burst), unshielding the reward apps mid-burst.
2. **More important finding:** the rebuild registered min.1–90 windows for every reward app, and iOS fired **zero catch-ups for any of them.** That confirms the original 03:10 flood's "reward app at min.5" events were ghost values inside a corrupted iOS event-delivery batch, **not real iOS cumulative.** iOS's actual internal counters for those apps today: zero. Our flood-revert correctly discarded usage that never existed.

### The fix — three small pieces using the existing `pending_window_rebuild` flag

The flag and the recovery handler already exist. They're used today for `WINDOW_TOP_HIT` rebuild requests. The flood path just needs to (a) write the flag, and (b) be honored by the app-launch and foreground-health paths that currently skip restart when `MONITORING_ALIVE` is true.

**Piece 1 — Extension writes the flag on flood revert.** Inside `revertBurstCredits` (DeviceActivityMonitorExtension.swift:362), immediately after `defaults.set(true, forKey: "burst_is_flood")`:

```swift
requestMainAppWindowRebuild(reason: "post-flood-recovery", defaults: defaults)
```

That posts a Darwin notification and writes the persistent flag. If the main app is in memory, it handles the notification immediately and runs `restartMonitoring`. If it isn't, the flag persists for any later recovery path to find.

**Piece 2 — App-launch safety net.** In `ScreenTimeService.swift` around line 567, the `MONITORING_ALIVE` block already checks `midnight_pending_refresh` and forces a restart if set. Add a parallel check for `pending_window_rebuild` right next to it. This catches the case where the main app was suspended during the flood — the Darwin notification may have been dropped, but the flag persists, and we drain it the next time the app launches.

**Piece 3 — Foreground health-check safety net.** Same idea in `checkMonitoringHealth` around line 2121 (called on `scenePhase = .active`). Add the same `pending_window_rebuild` check next to the existing `midnight_pending_refresh` check. This catches the case where the main app was already in memory but backgrounded when the flood happened.

### Why this is the right shape

- **No spurious restarts.** Normal days: no flood → flag never set → no extra restart cost. The `MONITORING_ALIVE` skip stays in place for the normal case it was designed for.
- **Real signal, not a calendar heuristic.** "Restart on first launch of the day" would force a restart every morning whether or not anything went wrong; that re-introduces the phantom-flood risk that `MONITORING_ALIVE` was added to prevent. The flag-based version only fires when the extension actually detected something it can't recover from.
- **Self-clearing.** `restartMonitoring` clears the flag on entry (line 2227). Once recovery succeeds, the flag is gone.
- **No infinite-loop risk.** The only way recovery could re-trigger flood detection is if a shielded reward app fires during the catch-up burst — physically impossible (shields prevent launch). The May 21 test confirmed this empirically: reward apps in the original flood had zero iOS-cumulative and fired no catch-ups during recovery.

### Plan — implementation steps

1. **Piece 1** — Add `requestMainAppWindowRebuild(reason: "post-flood-recovery", defaults: defaults)` inside `revertBurstCredits`, right after the `burst_is_flood = true` write
2. **Piece 2** — In `ScreenTimeService.swift`'s app-launch `MONITORING_ALIVE` block (~line 567), add parallel `pending_window_rebuild` check that calls `restartMonitoring(reason: "post-flood pending window rebuild (init)")`
3. **Piece 3** — In `checkMonitoringHealth` (~line 2121), add the same `pending_window_rebuild` check that calls `restartMonitoring(reason: "post-flood pending window rebuild (foreground)")`
4. On-device test: wait for natural flood (or simulate by toggling a reward app's shield mid-burst) → confirm auto-recovery completes within ~10s, no manual intervention needed
5. Update the test-scenarios table — "Multi-app phantom flood including a shielded reward app event" → add "and recording auto-resumes within seconds via post-flood rebuild"

### Known residual concern — immediate-recovery race

If the main app is in memory at the moment the flood fires, the Darwin notification triggers `handleWindowRebuildRequest` → debounces 5s → `restartMonitoring` within ~5-7 s of flood detection. iOS will then dump catch-ups within another 2-3 s. Those catch-ups may land while:

- `phantom_flood_active_until` is still active (30 s lockout from `PHANTOM_FLOOD_DETECTED`)
- `burst_is_flood = true` and `last_event_arrival_global` is recent (Phase B sees `gap < 5 s` → in-burst → no clear)

In that window the catch-ups would be rejected by `SKIP_FLOOD` and/or `BURST_FLOOD_SKIP`. The system still self-recovers within ~30-60 s — fresh thresholds are registered, lockouts eventually expire, the next real per-minute event credits cleanly — but the catch-up burst itself doesn't recover the missed usage.

This is a **strictly better failure mode than today** (10 h of silence → ~60 s of silence) and matches the existing accepted trade-off for phantom floods (the architecture already accepts net-zero credit on flood). The late-recovery path (main app suspended at flood time → recovery on next launch or foreground transition) is unaffected — by the time the flag is drained at launch, all flood timers have long since expired, which is exactly the case the 2026-05-21 force-restart test validated end-to-end.

If immediate-recovery becomes a problem in practice (we observe a real-device incident where the kid had real usage iOS would have caught us up on, and we missed it because immediate-restart fired during active lockout), the fix is to clear `phantom_flood_active_until` and `burst_is_flood` at the start of `restartMonitoring` when the reason contains "post-flood-recovery". Defer until evidence warrants.

---

## 2026-05-23 — Multi-app phantom flood without shielded events (Amine's iPhone)

First real-device occurrence of the "Device C" scenario the architecture had explicitly accepted as risk. The shielded-in-burst defense couldn't fire because every reward app was already unshielded at burst time — pool=2474min historical, all four learning goals were met. iOS killed the extension (memory pressure, session age 1420s = 23.6 min), and on respawn replayed catch-up events for every monitored app. Without a shielded reward app to trigger `revertBurstCredits`, the over-credit landed in production.

### Evidence

`ext-log-2026-05-23.log`, session boundary `465C140C → EDCB4069` at 08:38:56:

```
[08:38:56] EXTENSION_KILLED — new session detected (was: 465C140C, now: EDCB4069) age=1420s
[08:38:56] EXTENSION_INIT session=EDCB4069
SHADOW_BURST_JUDGE dur=10.1s events=183 apps=8 timeSinceKill=0s
  signals=[COLD_START_HIGH=fail GROWTH_VS_UNSHIELD=pass]
  verdict=phantom
  details=[BB131A01:start=16min growth=4min | C6DA269B:start=0min growth=67min cold=true |
           FAE1D45B:start=0min growth=30min cold=true | 642B7130:start=0min growth=70min cold=true |
           93088665:start=0min growth=70min cold=true | E8B1C8C6:start=49min growth=18min |
           D63AE4AA:start=0min growth=20min cold=true | 739C4A42:start=0min growth=3min cold=true]
```

User-visible damage compared to iOS Screen Time ground truth (09:32 snapshot):

| App | App showed | iOS reported | Phantom |
|---|---|---|---|
| Mobile Legends (642B7130) | 69 min | 0 min (not in top apps) | +69 min |
| YouTube (C6DA269B) | 67 min | 1 min | +66 min |
| Mini Motorways (93088665) | 69 min | 0 min (not in top apps) | +69 min |
| Facebook (E8B1C8C6) | 67 min | 49 min | +18 min |

The judge captured the kill-replay signature exactly (cold apps at high thresholds, all 8 monitored apps in the burst, `timeSinceKill=0s`). Its output was correct; it just wasn't acting on the verdict.

### First attempt (rolled back same day): shape-based enforcement

Initial fix promoted the judge's `verdict=phantom` to call `revertBurstCredits` when three conditions held: `apps≥2`, `timeSinceKill∈[0,60]s`, `COLD_START_HIGH=fail`. **This was wrong.** The shape signals (cold apps + high thresholds + recent kill) describe phantom *and* legitimate catch-up identically — iOS replays the same threshold events whether the underlying usage was real (kid actually used apps during the kill window) or phantom (iOS firing residual thresholds without underlying activity). Pattern-matching on shape cannot distinguish them.

A 7-day audit confirmed the problem: across 1094 judge fires, 13 multi-app bursts within 60s of a kill were classified `legit`, and the shape-based enforcement would have indiscriminately reverted them. Some were likely real catch-ups of legitimate usage during long kill windows; reverting them would have erased screen time the kid actually earned. Worse than the phantom-flood bug we were trying to fix.

### The rigorous test: wall-clock budget

The only signal that doesn't get fooled by "kid was actually using apps during the kill window" is the physical-impossibility check: a child can use one app at a time, so the total minutes claimed in a burst across all apps cannot exceed the wall-clock time available before the burst began. This was the multi-app aggregate check originally dropped on May 19 due to implementation bugs (timestamp updated mid-burst collapsed the budget). The concept was sound; the previous implementation wasn't.

Mechanism:
1. When a new burst begins (first event with gap ≥ 5s from the previous arrival), snapshot `last_credited_global_timestamp` into `shadow_burst_baseline_credit_ts`. This is the timestamp of the most recent legitimate credit before this burst — frozen for the burst's lifetime.
2. As burst events flow in and credits update `last_credited_global_timestamp`, the snapshot is unaffected. The burst's own credits do not get to update its own budget reference.
3. When the burst closes, compute `total_growth_min = sum(max_threshold − today_at_burst_start)` across all apps in the burst. Compute `wallclock_min = burst_start_ts − baseline_credit_ts`. Apply 10% grace: `budget = wallclock_min × 1.1`. Emit `SHADOW_BUDGET_CHECK verdict=exceeded|within|no-baseline`.

Validation against the May 23 incident:
- Total claimed across 8 apps: ~282 min (4+67+30+70+70+18+20+3)
- Baseline: previous session was actively recording credits until ~24 min before the burst — `wallclock_min ≈ 24`
- Budget: ~27 min
- 282 > 27 → would trip cleanly. 10× margin over budget.

### Known limitations (accepted)

- **Long-absence floods:** if our extension is dead for hours and the last credit is from before that gap, the budget grows correspondingly. A phantom flood with claims that fit inside the long budget would slip through. Mitigation: the shielded-in-burst defense catches this — overnight, reward apps typically re-shield (bank depletes, goals reset), so any phantom touching them trips `BURST_REVERT reason=shield-in-burst-…`. The remaining hole is daytime long-kill scenarios with a very large bank pool, which is uncommon but possible.
- **First event of the day:** baseline could be from yesterday or `0`. We emit `verdict=no-baseline` for these and do not enforce on them.
- **Mixed bursts:** in 7 days of log audit we did not observe a single burst that mixed real catch-up usage with phantom thresholds — phantom floods either come entirely from iOS replay residue or are entirely real catch-up. So all-or-nothing revert is acceptable.

### Status: shadow only

Currently emits `SHADOW_BUDGET_CHECK` log lines for diagnostic observation. No enforcement. Once we have a few days of shadow data confirming `verdict=exceeded` cleanly correlates with phantom floods (and `verdict=within` with legitimate growth), we'll promote to enforcement — but per the heal-as-safety-net realization below, the trigger should be a silent heal rather than `revertBurstCredits`.

### Implementation

`ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`:
- `shadowBurstTrack`: snapshot `last_credited_global_timestamp` into `shadow_burst_baseline_credit_ts` at burst start.
- `shadowBurstEmit`: compute and log `SHADOW_BUDGET_CHECK`. Heal-mode bypass (added later same day) logs `verdict=heal-bypass` and skips the comparison so heal's own catch-up can't trip itself.
- `shadowBurstReset`: clear the baseline key.

### Known limitation (Flaw 1)

When the wall-clock budget is large (e.g. overnight gap of 8 hours), a phantom flood claiming a few hundred minutes can fit inside that budget and slip through with `verdict=within`. This case is now addressed by the heal mechanism (see below): an auto-heal trigger gated on suspicious-large-budget bursts can call back to iOS for ground truth and overwrite the phantom credit. Design details in the heal section.

---

## 2026-05-23 — Heal mechanism (the architectural turning point)

The most consequential change in this branch's history. Started as a debug button, ended as a fundamental shift in the threat model.

### What heal does

1. Wipe today's recorded usage to zero (per-app `usage_<id>_today`, `lastThreshold`, hourly buckets, every related counter).
2. Reset state flags so the upcoming catch-up burst doesn't trip any anti-phantom defense: zero the global burst-credited-apps CSV, clear `burst_is_flood`, clear `last_event_arrival_global`, clear `phantom_flood_active_until`, reset shadow burst tracker.
3. Anchor wall-clock budget baseline at start-of-today (`last_credited_global_timestamp = startOfToday`).
4. Set `heal_active_until = now + 30s` — the flag every anti-phantom defense consults.
5. Re-register the sliding window with `current = 0` for every tracked app.
6. iOS responds by firing catch-up threshold events for every threshold ≤ its real cumulative for today. The extension processes them normally; `applyCredit`'s SET-to-max semantics rebuild today's totals to match iOS's authoritative count.

### Why this works at all

DeviceActivity exposes iOS's cumulative usage per app per day via threshold events. We never had a way to read that cumulative directly — we'd built our entire model around interpreting whatever events iOS happened to send. The heal repurposes the threshold mechanism as a query: "iOS, please tell me your full cumulative for today by firing every threshold up to it." iOS obliges. The numbers we receive are not estimates; they are iOS's authoritative count.

### Validation: May 23 morning incident

Pre-heal state (corrupted from phantom flood at 08:38:56):
- Mobile Legends: 69 min recorded, 0 in iOS Screen Time
- YouTube: 67 min recorded, 1 min in iOS Screen Time
- Mini Motorways: 69 min recorded, 0 in iOS Screen Time
- Facebook: 67 min recorded, 49 min in iOS Screen Time
- Instagram (later): 116 min recorded, 116 min in iOS Screen Time (this one happened to be correct)

After heal at 12:02 (after the four sub-fixes below were complete):
- Mobile Legends: 0 min ✓
- YouTube: 1 min ✓
- Mini Motorways: 0 min ✓
- Facebook: 49 min ✓
- Instagram: 117 min ✓ (1 min over due to ongoing real usage during heal)

Every value matched iOS Screen Time within ±1 minute. Total heal time: ~2 minutes from button press to final settle.

### The four sub-fixes (in order of discovery)

The initial heal didn't work cleanly. Each failure exposed a different downstream interaction that had to be unblocked.

**Fix 1 — Heal infrastructure itself.** Initial commit: wipe data + restart monitoring. Tested at 11:00. Result: Instagram capped at 40 min, Facebook capped at 40 min. Both apps had real usage > 40 min, but the catch-up stopped at the registered window top.

**Fix 2 — Relax the rebuild debounce during heal.** `triggerRebuildIfNearWindowTop` has a 60-second per-app debounce. The sliding window rebuilds itself when a credit lands near the top. During normal use, one rebuild per minute per app is plenty. During heal, the catch-up needs to chain through multiple windows (1-20 → 20-39 → 39-58 → ...) within seconds. Added: while `heal_active_until > now`, debounce drops to 1 second. Tested at 11:21. Result: Instagram reached 80 min before stopping. Better, but still incomplete.

**Fix 3 — Self-extending heal flag.** The 30-second flag expired before all the chained rebuilds completed. iOS sometimes pauses 10-18 seconds between catch-up batches, and a long catch-up (Instagram's 6 rebuild rounds) couldn't fit in a fixed 30-second window. Added: every successful credit and every rebuild request that fires while in heal mode pushes the flag forward another 30 seconds. The flag only expires after a real silence period. Tested at 11:31. Result: Instagram capped at 60 min — even worse this time.

**Fix 4 — Bypass anti-phantom defenses during heal.** The regression at 11:31 had a different cause: the catch-up's first events caused YouTube (a reward app) to fire while in a re-shielded state (heal had zeroed its usage, learning goal became unmet, shield went back up). The existing `SKIP_SHIELDED` defense correctly identified "shielded reward app firing event" as a phantom signature, called `BURST_REVERT` (wiping Facebook's just-credited 19 min), and set `PHANTOM_FLOOD_DETECTED` (locking out the next 30 seconds of events). The anti-phantom defenses, designed for kid-vs-system flood scenarios, had no way to know this multi-app burst was intentional. Added heal-mode bypass for `SKIP_FLOOD`, `SKIP_SHIELDED`, `BURST_REVERT`, `PHANTOM_FLOOD_DETECTED`, and `FIRST_EVENT_BUFFER`. Tested at 12:02. Result: complete success — all three apps healed to within ±1 min of iOS Screen Time.

### Why extension-side (canonical implementation)

The first heal implementation lived in the main app's `ScreenTimeService`. After the validation succeeded, we refactored to put `performHealUsage(reason:defaults:)` in the extension as the canonical implementation. Reasons:

1. **Auto-heal triggers fire from inside the extension.** When a future budget-anomaly trigger calls heal, the extension can do it inline — no Darwin notification, no waiting for main app to wake, no round trip. Sub-second response.
2. **Heal works when main app is terminated.** iOS can wake the extension via threshold events even when the main app has been swiped away. Manual-button heal still needs the main app for the button press, but the actual wipe-and-rebuild work happens in the extension.
3. **No inter-process race.** The earlier implementation had a small race window between main app zeroing keys and the extension's next event arrival (we discussed it as safe due to `applyCredit`'s `max()` semantics and `SKIP_REGRESSION`, but eliminating it is cleaner).
4. **Architectural consistency.** ~90% of recording work already runs in the extension. Heal belongs alongside the rest of the recording machinery.

Manual button path now:
1. User taps "Heal Usage Data" in main app settings.
2. Main app writes `heal_requested_at = now` and `heal_requested_reason` flags to UserDefaults.
3. Main app calls `restartMonitoring` — this triggers `stopMonitoring` then `startMonitoring` on DeviceActivityCenter.
4. iOS calls `intervalDidStart` on the extension.
5. Extension's `consumeHealRequestIfPresent` hook reads the flag, drains it, and calls `performHealUsage` locally.
6. iOS then delivers catch-up events against the fresh sliding window.

Auto-heal path (future, not yet implemented):
1. Some extension-internal trigger condition (e.g., budget-check anomaly) fires.
2. Extension calls `performHealUsage` directly inline.
3. Same catch-up flow as the manual path.

### The big realization

Up until heal, the entire filter architecture rested on a premise: "if we credit a phantom, we can never take it back." Every defense — `SKIP_SHIELDED`, `BURST_REVERT`, `PHANTOM_FLOOD_DETECTED`, the wall-clock budget check, the buffer-and-watch logic — exists because each event arrival was treated as a one-shot decision: credit now and live with it, or reject now and risk losing real usage forever.

That premise broke with heal. The truth is always available — iOS keeps cumulative per app per day. We just never had a reliable way to read it. Now we do.

Consequences:

1. **The wall-clock budget check's biggest known gap (Flaw 1: long-absence floods)** is no longer urgent. Even if a phantom slips through during an overnight gap, an auto-heal trigger gated on "wall-clock was suspiciously large" can call iOS for ground truth and overwrite the phantom credit afterward.

2. **Filters can lean toward "trust by default"** instead of "reject when unsure." The cost of false-rejection (lost real usage) no longer requires perfect filter accuracy — we can heal to recover. Same for false-acceptance.

3. **Auto-heal becomes viable as a routine maintenance operation.** Examples we should consider:
   - Budget-check `verdict=exceeded` → silent background heal
   - Judge `verdict=phantom` from kill-replay signature → silent background heal
   - Once-an-hour scheduled background heal (belt and suspenders)
   - First foreground of the day → heal to start from ground truth

4. **When promoting the budget check from shadow to enforcement, wire it to heal rather than to `revertBurstCredits`.** The original plan was to revert burst credits when budget exceeded. Heal is strictly better — it doesn't just delete the suspicious credit, it asks iOS what the truth is and writes that. No edge case where we revert legitimate usage and the kid loses earned time.

### UX trade-offs (will matter when shipping to production)

- **Brief dashboard zero.** The current heal wipes data first, then rebuilds. Visible for 1-3 seconds. For auto-heal in the background, the kid won't see it; for manual heal triggered by the user, they're already expecting a refresh.
- **Brief shield flicker.** Reward apps may re-shield (goals temporarily unmet) and unshield (catch-up restores them) during the ~2-minute heal window. A kid tapping a reward app at the wrong moment might briefly see it locked.
- **iOS resource usage.** Each heal triggers a full sliding-window re-registration plus a catch-up burst. Cheap individually, but auto-heals add up. Worth measuring before shipping background auto-heal.

### Status: shipped (debug button only)

- Manual button: shipped in `#if DEBUG` builds, validated end-to-end on Amine's iPhone 2026-05-23.
- Extension-canonical implementation: refactored 2026-05-23.
- Anti-phantom heal-mode bypasses: shipped.
- Wall-clock budget check heal-mode bypass: shipped (logs `verdict=heal-bypass`).
- Auto-heal triggers: not yet implemented. Open questions: which conditions trigger, how often, with what cooldown, silent vs visible.
- User-facing button ("Update usage"): not yet implemented. Will be the same `performHealUsage` mechanism with friendlier UX wording.

### State storage additions

```
heal_active_until        — TimeInterval; flag consulted by anti-phantom defenses
                           and rebuild debounce to switch into heal mode.
                           Self-extends on every credit and rebuild during heal.

heal_requested_at        — TimeInterval; main app sets this to request a heal.
                           Extension's intervalDidStart drains it and calls
                           performHealUsage. Stale requests (>60s) discarded.

heal_requested_reason    — String; descriptive reason preserved for logging.

shadow_burst_baseline_credit_ts — TimeInterval; budget-check baseline,
                                  snapshot at burst start (see budget check
                                  section above).
```

### Implementation

`ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`:
- `performHealUsage(reason:defaults:)` — canonical heal implementation.
- `consumeHealRequestIfPresent(defaults:)` — drains the main app's request flag.
- `intervalDidStart` — invokes `consumeHealRequestIfPresent` before normal processing.
- `triggerRebuildIfNearWindowTop` — heal-mode debounce relaxation (60s → 1s) and self-extending flag.
- `applyCredit` — self-extending flag on every credit during heal mode.
- `setUsageToThreshold` — `inHealMode` short-circuits `SKIP_FLOOD`, `SKIP_SHIELDED`, `BURST_REVERT`, `PHANTOM_FLOOD_DETECTED`, and `FIRST_EVENT_BUFFER`.
- `shadowBurstEmit` — heal-mode bypass for `SHADOW_BUDGET_CHECK`.

`ScreenTimeRewards/Services/ScreenTimeService.swift`:
- `healUsageData(reason:)` — thin wrapper that sets the flag and triggers `restartMonitoring`.

`ScreenTimeRewards/Views/SettingsTabView.swift`:
- `healUsageRow` — debug-only button with confirmation alert and result message.

---

## 2026-05-23 — Parent-device sync fixes (heal follow-up)

The heal mechanism rebuilt today's totals correctly on the child device, but the parent dashboard kept showing stale phantom data. Investigation traced through three sequential bugs in the child→CloudKit→parent sync chain, each only visible after fixing the one above it.

### Bug 1 — `SAFEGUARD 2` blocked updates of existing records to zero

`syncUsageRecordFromExtensionData` in `ScreenTimeService.swift` had a guard `guard todaySeconds > 0 else { return }` that skipped record processing when the extension reported zero seconds. The guard's intent was "don't create empty records for never-used apps," but it also blocked legitimate UPDATE of an existing record from a phantom value back to zero. Result: after heal, a phantom-cleared app's Core Data record stayed at the old phantom value with `isSynced=true`, so the background sync never re-uploaded.

**Fix:** moved the guard so it only applies to the create-new branch. Existing records always update — including to zero.

### Bug 2 — Upload skipped today's record when `todaySeconds == 0` AND no existing CK record

`uploadDailyUsageHistoryToParent` in `CloudKitSyncService.swift` line 3765 (pre-fix) had `if app.todaySeconds > 0 { upload }`. For an app like Mobile Legends with phantom-then-healed-to-zero usage, todaySeconds was 0 and the parent's CloudKit zone never received an updated record — the old phantom value stayed.

**Fix:** condition relaxed to `app.todaySeconds > 0 || hasExistingTodayRecord` so existing records always update, including to zero. The `> 0` guard still applies to creating brand-new records (no point creating empty records for apps that never had usage). Same pattern as Bug 1.

### Bug 3 — Upload failed silently with `record to insert already exists`

After fixes 1 and 2, all 8 apps showed `upload=true` in diagnostics, but Facebook and TikTok still didn't reach the parent. The save log showed `Saved batch 1: 81 records` — looked successful. But CloudKit's `modifyRecords` returns a per-record `Result<CKRecord, Error>`; individual failures don't throw. Per-record diagnostic logging revealed:

```
❌ Save FAILED for DUH-{deviceID}-BB131A01-...-2026-05-10:
  record to insert already exists
```

Root cause: the upload starts with a dedup-fetch (`CKFetchRecordZoneChangesOperation`) that has a 15-second timeout. When CloudKit was slow, the timeout fired with an incomplete set of existing records. The code then took the "create new" path for records that actually existed on CloudKit. The default save policy (`.ifServerRecordUnchanged`) rejected those as duplicates. Affected records stayed at their old value.

**Fix:** two parts.
1. Pass `savePolicy: .allKeys, atomically: false` to `modifyRecords`. With `.allKeys`, records overwrite-on-collision instead of failing. This is the correct upsert pattern when the local device is the authoritative writer for these per-day totals.
2. Bumped the dedup-fetch timeout from 15s to 60s. With `.allKeys` this is no longer required for correctness, but a complete dedup set keeps the upload's create-vs-update counts accurate in logs.

### Bug 4 — Parent's fetch silently capped at 100 records

After fixes 1, 2, and 3, the child's save log finally showed `Saved batch 1: 81 succeeded, 0 failed` — every record landed on CloudKit including Facebook and TikTok for today. But the parent STILL didn't see Facebook today. Parent log showed `Zone-specific fetch returned 100 history records` consistently.

Root cause: `db.records(matching:inZoneWith:)` returns a **maximum of ~100 records per page** by default. The function call returns both a result tuple and a `CKQueryOperation.Cursor` for fetching the next page. The previous code ignored the cursor entirely — `let (matches, _) = try await db.records(...)`. The zone had ~123 records total; Facebook and TikTok for today happened to be returned beyond record #100 in CloudKit's ordering and were never fetched.

**Fix:** paginated the fetch via cursor loop. The function now fetches page 1, checks for a non-nil cursor, fetches page 2, and continues until cursor is nil. New log line:

```
Zone ChildMonitoring-...: found 123 history records across 2 page(s)
```

This was the final fix that unblocked parent sync for the heal's results.

### Validation

Tested 2026-05-23 18:58 on Amine's iPhone (child) and parent device. After heal:
- Child Facebook = 77 min (4620s) ✓
- Parent Facebook (after pull-to-refresh) = 77 min ✓
- All 8 apps reconciled within ~2 minutes

### Lessons captured

- **Per-record results require per-record logging.** Aggregate counts (`Saved 81 records`) hide silent partial failures in CloudKit's API. Any future bug investigation in CloudKit sync should immediately drill down to per-record results.
- **Default page limits are silent.** CloudKit query APIs cap at ~100 results and require explicit cursor pagination. Audit any other `records(matching:)` call in the codebase that doesn't loop on `queryCursor`.
- **Save policy `.allKeys` is the correct upsert pattern.** Default `.ifServerRecordUnchanged` is for optimistic-concurrency UPDATE-only workflows; for one-writer aggregate snapshots (per-day totals), upsert-with-overwrite is correct.

### Implementation files

`ScreenTimeRewards/Services/ScreenTimeService.swift`:
- `syncUsageRecordFromExtensionData` — moved SAFEGUARD 2 to apply only to record creation.

`ScreenTimeRewards/Services/CloudKitSyncService.swift`:
- `uploadDailyUsageHistoryToParent` —
  - today-upload condition: `app.todaySeconds > 0 || hasExistingTodayRecord`.
  - save call uses `savePolicy: .allKeys, atomically: false` for upsert.
  - dedup-fetch timeout bumped 15s → 60s.
  - per-batch logging now breaks down successes vs failures per record ID.
- `fetchChildDailyUsageHistory` — paginates via `queryCursor` until exhausted.

---

## 2026-05-27 — Budget-enforce flood left the window dead (Alex's iPhone)

The same recovery hole as **2026-05-21**, re-opened through a new rejection path. The May 21 fix wired post-flood recovery into `revertBurstCredits` (the shielded-in-burst detector). On 2026-05-26, commit `ae771b2` promoted the wall-clock budget check from shadow to enforce as a bare `return false` — a third way to reject a flood that never enters `revertBurstCredits` and so never re-arms the consumed sliding window.

### What happened

`Alex-ext-log-2026-05-27.log`:

- Normal per-minute recording all morning through **14:41** (last credit: learning app E8B1C8C6 → 12 min).
- **14:39** — learning goal met; all reward apps unshielded.
- **14:43:44–14:43:55** — iOS dumped a phantom flood: **112 threshold events across 15 apps in 11 seconds.** Only YouTube (C6DA269B) had real usage today; every other app's events were phantom.
- The cross-app budget check tripped correctly (`proposedGrowth ≈ 11,000s` vs `budget ≈ 230s`) and rejected all 112 events as `SKIP_BURST_BUDGET`. **The filter did its job.**
- After 14:43:55: **zero threshold events for the rest of the day (~6 h).** Three later app launches all logged `MONITORING_ALREADY_ACTIVE — skipping`. No heal, no rebuild.

### Root cause — identical mechanism to 2026-05-21

- iOS fired (and thereby consumed) every registered threshold for each app during the flood — including all 30 of YouTube's 14–43 window — even though we rejected each event.
- The sliding-window rebuild only fires on a successful credit (`RECORDED → REBUILD_REQUEST`). A 100%-rejected flood produces no credit, so the window never advances or re-registers.
- The cross-app budget is unique in that it rejects the **entire** flood, including the one legit app: YouTube's real growth was swept up because the phantom apps kept the cross-app total over budget — so not even the real app produced a credit to drive a rebuild.
- `MONITORING_ALIVE` keeps the periodic restart from making a fresh session. The window stays a dead husk while everything looks healthy.

`ae771b2` shipped only the blocking half of the design. The doc had already prescribed the other half (see "The big realization" → "When promoting the budget check from shadow to enforcement, wire it to heal rather than to `revertBurstCredits`"). The commit did neither — no heal, no rebuild signal.

### The fix

Wire `SKIP_BURST_BUDGET` to the same recovery `revertBurstCredits` already uses. At the budget reject, before `return false`:

```swift
defaults.set(true, forKey: "burst_is_flood")
requestMainAppWindowRebuild(reason: "post-budget-recovery", defaults: defaults)
```

- `burst_is_flood = true` classifies the burst as a flood so the remaining events short-circuit at the `burst_is_flood` check (the `BURST_FLOOD_SKIP` branch) instead of re-running the budget math and re-posting the rebuild notification per-event. It auto-clears when the next genuine burst opens (Phase B gap ≥ 5 s → `clearBurstState`).
- `requestMainAppWindowRebuild` raises `pending_window_rebuild` + posts the Darwin notification. The main app drains it three ways (Darwin handler, app-launch check, foreground health check) — all reason-agnostic, so `post-budget-recovery` is handled exactly like `post-flood-recovery`.

Net: a budget-rejected flood now forces a fresh sliding window within seconds instead of going dark for the rest of the day.

### Why rebuild and not heal (for now)

The doc's preferred end-state is to trigger a silent heal on budget-exceeded (ground-truth re-query, not just re-arm). This fix takes the smaller step — re-arm the window the same way the shield-in-burst path does — because it's a one-line parallel to proven, shipping code and carries the existing accepted trade-offs (see the immediate-recovery race note in the 2026-05-21 section). Heal-on-budget-exceeded remains the eventual target under "Auto-heal triggers."

### Status

- [x] Wire post-budget recovery into `SKIP_BURST_BUDGET` — `DeviceActivityMonitorExtension.swift`.
- [ ] On-device validation: confirm `WINDOW_REBUILD_REQUESTED reason=post-budget-recovery` follows the next `SKIP_BURST_BUDGET` flood and catch-up resumes (vs. dead silence).

---

## 2026-05-27 — Heal last-batch flood (Ali's iPhone)

A manual heal at 22:53 ran its 7 reward batches, but instead of catching up app-by-app in calm waves, **79 of the ~106 total catch-up credits landed in the final batch (22:58–23:00)** while batches 1–4 produced ~10. The extension crashed and respawned **11 times** during the ~8-minute heal, and the registered-threshold count ballooned from ~150 at batch 6 to a peak of **~1,400** at batch 7 — well over iOS's ~500 ceiling.

Benign for correctness (heal mode bypassed the filters, `verdict=heal-bypass`, SET-to-max is idempotent — nothing rejected, no data lost), but it crashed the extension repeatedly and defeated the entire point of batching.

### Root cause — three compounding mechanisms

1. **Cumulative re-registration.** Each batch registers the current batch *plus every earlier batch* (`allowedApps = batchPlan.prefix(currentBatch + 1)` at `processHealBatchIfNeeded` and the main app's `windowSize()`). The batching held *future* apps back (`window_size=0`) but never capped *past* apps. So the registered crowd only grew — 5 → 8 → 11 → … → 22 — and the final batch re-registered the whole fleet, the exact thing batching was added to prevent (`DeviceActivityMonitorExtension.swift:753`).

2. **Tier promotion during catch-up.** As each app passed 25 min it promoted 30 → 90 thresholds (`promoteTierIfNeeded`). With ~15 apps doing this in the final batch, the alarm count exploded — and that's what crashed the 6 MB extension repeatedly.

3. **Keepalive overwrite (the cadence bug).** The per-credit and per-rebuild heal keepalives did `set(heal_active_until = now + 10)` — overwrite, not extend (the comment even claimed "30 seconds"). The first catch-up credit *crushed* the batch's 60 s floor (`max(current, now+60)` at `:851`) down to +10 s. Since iOS pauses **up to 18 s between delivery waves**, the batch advanced *mid-delivery* during a pause — before its apps finished. Unfinished catch-up kept getting shoved down the line until the final batch, where (no batch behind it to interrupt) iOS finally dumped everything at once.

### The fix (two interdependent halves)

**Half 1 — bound concurrent alarms.** Establish one rule everywhere windows are decided during heal: **future batch → 0, past (recovered) batch → sentinel 5, current batch → full window.** A recovered app at a 5-alarm window just above its total fires no catch-up (its `usage_today` already equals iOS's cumulative), so it stops re-flooding and stops eating memory. Two sites:
- `DeviceActivityMonitorExtension.swift` `processHealBatchIfNeeded` — after restoring the current batch, demote `allowedApps − batchApps` to `window_size=5`.
- `ScreenTimeService.swift` `windowSize()` heal branch — for an app in `allowedApps` but not in the current batch, return `shieldedSentinel` regardless of the stored `window_size` (closes the race where it's still tier-promoted to 90). Scoped to the reward branch, where the 90-promotion balloon happens; past learning apps re-registered at their goal window fire no catch-up either (nothing above current), so they're left to the existing learning path.

Peak alarms worst-case (final batch, 22 apps): 19 past × 5 + 3 current × 90 ≈ **365**, under the ~500 ceiling → crash loop ends, final batch is no longer a full-fleet wake-up.

**Half 2 — make "advance when quiet" mean quiet.** Change both keepalives from `set(now + 10)` to `set(max(heal_active_until, now + 25))`. `max()` so the keepalive only ever *extends* — never shortens the 60 s batch floor. The 25 s settle window exceeds iOS's ≤18 s inter-wave pause, so a batch isn't advanced during a delivery pause. This restores the existing settle-detector (advance once `heal_active_until` passes) that the overwrite had been sabotaging. Strengthens, doesn't undo, the 2026-05-26 "heal_active_until expired too early" fix.

The halves depend on each other: Half 1 bounds memory and kills the final-batch flood; Half 2 guarantees a batch fully settles before Half 1 demotes its apps (otherwise demotion would truncate an unfinished catch-up → undercount).

Conscious trade-off: each batch now waits ~25 s of real silence, so a heal takes a bit longer (~3–4 min vs ~2). Correctness over speed.

### Status

- [x] Half 1a — demote past batches to sentinel in `processHealBatchIfNeeded` (`DeviceActivityMonitorExtension.swift`).
- [x] Half 1b — mirror the sentinel rule in `windowSize()` heal branch (`ScreenTimeService.swift`).
- [x] Half 2 — keepalive extend-not-overwrite at both sites (`DeviceActivityMonitorExtension.swift` credit + rebuild paths).
- [ ] On-device validation: next heal shows credits spread across batches (not piled in the last), peak `EXT_REBUILD_SUCCESS events=` stays under ~500, and zero `EXTENSION_KILLED` during the heal.

---

## 2026-05-28 — Window ceiling stranded by mid-hand-off kill (Alex's iPhone)

Instagram stopped recording at 20 min while iOS Screen Time showed 29 — a silent 9-min undercount with **no flood and no heal involved**. The sliding-window re-arm trigger went dead for the entire day because the per-app ceiling (`window_top_min_<id>`) was never refreshed to match the day's freshly-registered windows.

### What broke

Each threshold window is registered once at midnight (`extensionRebuildSlidingWindow`). As the kid nears the top of a window, a rebuild trigger (`triggerRebuildIfNearWindowTop` + the state-based `WINDOW_TOP_HIT` check) re-registers the next batch. Both triggers are gated on `window_top_min_<id>` — they fire when `recordedMin >= windowTop − 5`.

On 5-28 the trigger fired **zero** times all day: `REBUILD_REQUEST=0`, `WINDOW_TOP_HIT=0`, `EXT_REBUILD_SUCCESS=0`. Instagram's window was registered 1–20 at midnight and never extended. When the kid passed 20 min, iOS had no higher threshold to fire (confirmed: iOS re-fired min.20 → `SKIP_REGRESSION`), so recording froze at 20.

### Root cause — two independent facts collided

1. **`window_top_min` is not reset at midnight.** `resetAllDailyCounters` clears usage, lastThreshold, hourly buckets, pin/phantom state — but not `window_top_min`. It carries over from the prior day. On 5-27 Instagram had been used to 36 min and its window extended to a ceiling of **56**; that 56 persisted into 5-28.
2. **The midnight rebuild was killed before it recorded the day's real ceilings.** `extensionRebuildSlidingWindow` registered all 17 windows (Instagram 1–20) and called `startMonitoring`, which synchronously re-entered `intervalDidStart` (the shield check). iOS terminated the 6 MB extension mid-callback — `MIDNIGHT_EXT_REBUILD_OK`, `MIDNIGHT_PENDING_SET`, and even `INTERVAL_START_SHIELD_CHECK completed` all logged **zero** for the whole day. The `window_top_min` write sat on the success path *after* `startMonitoring`, so it never ran.

Result: today's real ceiling (20) was never written; the stored ceiling stayed at the stale **56**. The re-arm trigger waited for usage to reach 51 (56−5) before extending — but iOS only had bells up to min.20, so recorded usage could never reach 51. Deadlock: window frozen at 1–20, real usage 29, 9 min lost.

### Why it didn't surface before

The ceiling is refreshed by any monitoring restart that runs to completion — and on prior days plenty happened: the self-sustaining `credit-near-top` trigger (261× on 5-26, once seeded), developer heal-testing, `schedule edited` config changes, an occasional `midnight background task`. The 45-min `intraday-refresh` BGTask never fired in any log. Crucially, **opening the app does not refresh the ceiling** — app launches hit `MONITORING_ALIVE` and skip the restart. On 5-28 none of the seeding restarts happened (0 restarts all day), the midnight seed was killed, and the self-sustaining trigger was poisoned by the stale 56 — so nothing reseeded the ceiling.

The midnight rebuild failing to complete is **common** (`MIDNIGHT_EXT_REBUILD_OK=0` on ~1/3 of logged days); it had always been masked by one of the other restart sources. Test devices mask it especially well because they're opened/restarted constantly; a quiet real-user device — particularly a child's device the parent rarely touches — is the exposed case. This is a *could-happen-when-the-dice-land-wrong* bug, not a *will-happen-to-everyone* one: it needs (a) the midnight rebuild killed mid-hand-off, (b) no other completing restart that day, and (c) an app used past its fresh-morning window carrying a higher stale ceiling.

### The fix (`DeviceActivityMonitorExtension.swift`, `extensionRebuildSlidingWindow`)

Move the `window_top_min_<id>` write to **before** `startMonitoring`, mirroring how `monitoring_restart_timestamp` and the `map_` event→app keys are already persisted pre-hand-off. The ceilings become durable the instant the windows are defined, so a mid-hand-off kill can no longer strand them. On `startMonitoring` failure the catch block reverts each ceiling to its prior value (the old schedule is still the registered one). Because every rebuild path shares this function, midnight, the self-sustaining trigger, and heal are all hardened at once; the correct ceiling also overwrites any stale prior-day value, dissolving the deadlock.

We can't stop iOS from killing the extension mid-callback (that's its 6 MB/CPU budget, not our bug), so the fix targets the *consequence* of an incomplete rebuild rather than trying to force completion: the rebuild's essential output is recorded before the kill point.

### Status

- [x] Write `window_top_min` before the `startMonitoring` hand-off + revert-on-failure.
- [ ] On-device validation: a day with a cut-short midnight rebuild (`EXT_REBUILD_SUCCESS=0`) where windows nonetheless keep extending and per-app totals track iOS.
- [ ] Fallback (belt-and-suspenders): reset `window_top_min` at midnight so a stale value can never poison the trigger even if the pre-hand-off write is skipped.

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

### 2026-05-25 — Tiered threshold windows: 5 → 30 → 90

**Problem:** When the learning goal is met, all reward apps immediately jump from 5 to 90 thresholds — even apps the child never opens. On Device 2 (May 24, weekend), 13 reward apps × 90 = 1,170 thresholds registered at once. iOS batched and delayed delivery under this load, producing 40+ minute gaps followed by catch-up bursts instead of 1-per-minute delivery. Those bursts then interact poorly with BURST_REVERT and other filters.

**Root cause confirmed:** Today's 4-device test (May 25) with only 1 active reward app (185 thresholds total) showed perfect 1-per-minute delivery across all 4 devices, zero BURST_REVERT events. The threshold count was the variable.

**Solution — tiered window promotion based on actual usage:**

| Tier | Window size | When |
|------|------------|------|
| Tier 0 (sentinel) | 5 thresholds | Default for shielded AND newly-unshielded apps |
| Tier 1 (interested) | 30 thresholds | First threshold fires — child started using the app |
| Tier 2 (favorite) | 90 thresholds | Usage crosses 25 min — sustained play |

**Tier transitions:**
- Shield drops → app stays at tier 0 (was: instant jump to 90)
- First RECORDED event for an app at tier 0 → promote to tier 1 (or tier 2 if catch-up reports 25+ min)
- RECORDED event crosses 25 min at tier 1 → promote to tier 2
- Shield re-applied (daily limit, downtime, goal unmet) → demote to tier 0

**Simulation against Device 2 May 24 (realistic sequential play):**

| Moment | Current system | Tiered system | Savings |
|--------|---------------|---------------|---------|
| Shield drop (all 13 apps) | 1,260 | 155 | 87% |
| 1 app active | 1,260 | 215 | 83% |
| 3 apps active (peak) | 1,260 | 325 | 74% |
| Day winds down | 1,260 | 190 | 85% |

**Implementation touch points:**
1. `DeviceActivityMonitorExtension.checkAndUpdateShields()` — removed instant `window_size = 90` on shield drop
2. `DeviceActivityMonitorExtension.promoteTierIfNeeded()` — new function called after every RECORDED event
3. `DeviceActivityMonitorExtension.checkAndUpdateShields()` — three shield-application paths (downtime, daily limit, learning goal) now set `window_size = 5` on re-shield
4. `ScreenTimeService.windowSize(for:category:isShielded:)` — reward apps now read `window_size_<id>` from shared UserDefaults (extension-set tier) instead of hardcoding 90

**Heal compatibility:** After heal resets usage to 0, catch-up events fire. `promoteTierIfNeeded` handles this correctly — if catch-up reports 25+ min, the app promotes straight from tier 0 to tier 2 in one step (no intermediate tier 1 rebuild).

**Logging:** `TIER_PROMOTE appID=... 5→30 (usage=1min)` and `TIER_PROMOTE appID=... 30→90 (usage=25min)` appear in the extension log for each transition.

### 2026-05-25 — BURST_REVERT mid-shield fix

When a reward app crossed its daily limit during a catch-up burst, the shield was applied mid-burst. The very next catch-up event (arriving <1s later) saw the shield and triggered BURST_REVERT, erasing the just-recorded usage. This created a permanent freeze: usage stuck below the limit → shield removed on next restart → child plays more → repeat.

Device 2 (May 24): Roblox tracked 118 min vs iOS 188 min due to 3 BURST_REVERTs at 19:57, 20:35, and 23:00, each rolling back to 7080s (118 min).

Fix: in SKIP_SHIELDED, check if the triggering app was credited earlier in the same burst (i.e., in `burst_credited_apps`). If so, the shield was applied mid-burst by that credit — the remaining catch-ups are real pre-shield usage. Block the event but preserve credits. Only revert when the shield was already on before the burst started (true phantom signal).

### 2026-05-26 — Burst budget promoted from shadow to enforce

The shadow budget check (`SHADOW_BUDGET_CHECK`) correctly detected phantom floods on every occasion but never blocked them — it was diagnostic-only. On Amine's device (May 26), a "schedule edited" restart at 12:15 produced 43 min of phantom across 11 unused reward apps; the shadow logged `verdict=exceeded` but let every event through.

The `applyCredit` code path (credit-on-arrival) had no wall-clock budget enforcement. The legacy `setUsageToThreshold` path had `SKIP_BURST_BUDGET` but it was never ported to the active path.

Fix: added enforcing budget check before `applyCredit` in `setUsageToThreshold`. Uses the same shadow burst state (`shadow_burst_baseline_credit_ts`, per-app growth tracking). Budget = wallclock × 1.1 + 60s grace. Heal mode bypasses the check (heal catch-ups are intentional). Logs `SKIP_BURST_BUDGET` on reject.

**Bug (same day, later):** The enforcing check double-counted the current event's contribution. `shadowBurstTrack` runs before the enforcing check and updates `shadow_burst_max_thresh_<id>` for the current event. The enforcing check then summed `max_thresh - today_at_start` across all burst apps (already including this event), then ADDED `thresholdSeconds - usage_today` on top — counting the same 60s twice. Every normal 1-per-minute event showed 120s growth against ~60s wallclock → always over budget → legit usage blocked. Amine's device: Clue (739C4A42) had 6 consecutive normal events rejected at 14:01–14:06.

Fix: only add the proposed delta for apps not yet in the burst CSV. If the app is already tracked (which it always is by the time the enforcing check runs), its contribution is already in `totalGrowthSec`.

### 2026-05-26 — Tier promotion debounce clear

On Sami's device, Roblox promoted 30→90 at 11:50:55 but the rebuild debounce (60s) was still active from the 5→30 promotion 21 seconds earlier. The window stayed at 4-33 (old tier-1 range), exhausted at min 33, and Roblox went dark for 97 minutes until the main app opened. Imane's device worked because events arrived at normal 1-per-minute cadence — the debounce cleared naturally before the window exhausted.

Fix: `promoteTierIfNeeded` clears the per-app rebuild debounce timestamp on every promotion. The next event that approaches the window top triggers the rebuild immediately. No mid-burst monitoring restart (which would cause phantom floods) — just clearing the gate so the existing rebuild path fires sooner.

### 2026-05-27 — Heal batch window_size restore

When the heal batch processor advances to a new batch, it sets `window_size=0` for apps in future batches (correct). But it never restored `window_size` to a positive value for apps in the **current** batch. Those apps had `window_size=0` from being deferred in batch 0, and it stayed at 0.

Imane's device (May 27): Roblox was in batch 2. Learning app recovered in batch 0 (goal met). When batch 2 ran, `extensionRebuildSlidingWindow` read `window_size=0` for Roblox → registered 0 thresholds → iOS had nothing to fire → Roblox recovered 0 min despite 2+ hours of real usage. Required 3 heal attempts; first recovered 5 min, second recovered 133 min (from batch 0 sentinel leaking), third recovered 0 min.

Sami's device (May 27): same build without the `heal_batch_active` check in `windowSize()`. Main app's `scheduleActivity()` registered 5-threshold sentinels for ALL apps during batch 0. iOS fired catch-ups for reward apps in the learning batch → phantom inflation (e.g. Stumble Guys 118 min vs iOS 55 min).

Fix: `processHealBatch` now restores `window_size` for apps entering the current batch — learning apps get 30, reward apps get 5 (sentinel, tier promotion handles expansion).

### 2026-05-27 — Main app heal batch isolation: read the actual batch plan

The `heal_batch_active` + `extensionWindow == 0` check in `windowSize()` was insufficient. Reward apps with `window_size=90` from tier-2 promotion (set during normal usage before the heal) bypassed the check because `extensionWindow` was 90, not 0. The extension's heal reset zeroes `window_size` for deferred apps, but `scheduleActivity()` can run before or concurrently — a race condition.

Sami's device (May 27): 852B1F13 had `window_size=90` and `usage_today=118` (inflated from a previous heal's phantom). The stale check saw `window_size=90, usage > 0 → return 90`. Full 90-threshold window registered during batch 0 → iOS fired catch-ups → phantom flood. Imane's device worked by luck: reward apps had `usage_today=0` (never recorded due to double-count bug), so the stale check returned 5 (less damage).

Additional issue: overlapping heals. When a second heal started while the first was still batching, the first heal's batch timer continued advancing and overwrote `window_size` values after the second heal had cleared them.

Fix: during `heal_batch_active`, `windowSize()` now reads the actual batch plan from UserDefaults and checks if the app is in an allowed batch. Any app not in the allowed list returns 0, regardless of its `window_size` value.

### 2026-05-26 — Heal duration and batch isolation fixes

Two problems broke the heal mechanism:

**1. `heal_active_until` expired before iOS delivered catch-ups.** The timer was set to now+10s and extended only by successful credits. With 6 batches advancing every 10s (60s total) + iOS delivery delay (15-60s), heal mode expired long before catch-ups arrived. Shielded reward apps then triggered `PHANTOM_FLOOD_DETECTED` which locked out ALL events including legitimate learning-app catch-ups.

Fix: initial `heal_active_until` now covers the full batch window (`batchCount × 10s + 60s`, minimum 120s). Each batch extends to `max(current, now+60s)` instead of resetting to `now+10s`.

**2. Main app `scheduleActivity()` broke batch isolation.** The extension's batch mode set `window_size=0` for deferred apps, but `scheduleActivity()` (triggered by Darwin notification) overrode it to 5 (sentinel) because the tiered-window stale-check treated 0 as "unset." iOS then fired sentinel catch-ups for all 17 apps during the learning batch.

Fix (two layers):
- `windowSize()` respects `window_size=0` when `heal_batch_active` is true — returns 0 instead of sentinel.
- `requestMainAppWindowRebuild` suppressed during heal mode — the extension handles all rebuilds, no Darwin notification sent to main app.

Validated on Amine's device: heal recovered Instagram=22min (exact), Clue=15min (exact), all 14 other reward apps=0min (zero phantom).

### 2026-05-25 — Foreground-only periodic shield refresh

BlockingCoordinator's 60s periodic timer (`refreshAllBlockingStates`) was running even when the app was backgrounded. On Device 4 (May 25), this caused all reward apps to briefly unshield at ~12:09 — the main app's evaluation disagreed with the extension's ground truth because its Core Data was stale. The extension is the shield authority. Fix: timer callback now checks `UIApplication.shared.applicationState == .active` and skips when backgrounded.

### 2026-05-18 — Section markers, not function extraction, for Step 2
Original Step 2 plan: extract Phase A filters into a `passesHardRejects()` helper. Revised to add prominent section markers in place without moving code. Rationale: extraction would change inline state-write ordering (e.g., `last_event_arrival_<id>` is updated at the top of the to-be-removed SKIP_FLOOD filter and reading it from a different position could change the burst-context behavior of OTHER filters). Extraction lands once Phase B is active and the legacy filters are being removed (Step 5).
