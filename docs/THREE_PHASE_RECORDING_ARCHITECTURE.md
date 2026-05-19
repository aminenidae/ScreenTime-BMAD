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
│   - Shielded reward app                                      │
│   - Threshold regression                                     │
│   - Physical impossibility (thresh > wallclock-since-midnight)│
└──────────────────────────────────┬───────────────────────────┘
                                   │ pass
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE B — Buffer + lazy settlement trigger                   │
│                                                              │
│ 1. Check the in-flight buffer:                               │
│    If buffer's last event was ≥ 5s ago,                      │
│      the buffered batch is finished → SETTLE it (Phase C).   │
│      Then clear the buffer.                                  │
│                                                              │
│ 2. Add the current event to the buffer.                      │
│    Do not credit yet. Return.                                │
└──────────────────────────────────┬───────────────────────────┘
                                   │ on settlement trigger
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE C — Settle the batch                                   │
│                                                              │
│ Batch has 1 event:                                           │
│   No neighbors before or after → ISOLATED                    │
│   Credit it at face value.                                   │
│                                                              │
│ Batch has 2+ events:                                         │
│   Multiple events clustered within 5s of each other = BURST. │
│   Evaluate flood vs legit catch-up:                          │
│     - Sum of claimed credit (max threshold per app)          │
│       vs wallclock since the previous credit (any app)       │
│       before the burst started.                              │
│     - Plus other flood signatures (shielded app event in     │
│       buffer, extension-kill density, etc.)                  │
│   Legit → credit max threshold per app, one shot.            │
│   Flood → reject the whole batch.                            │
└──────────────────────────────────────────────────────────────┘
```

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

## Phase B — Buffer + lazy settlement trigger

Phase B does not classify. It does two things:

1. **If the in-flight buffer's last event is ≥ 5 seconds old, settle the buffer now** (run Phase C on the accumulated batch). Then clear the buffer.
2. **Add the current event to the buffer.** Do not credit. Return.

```swift
func bufferAndMaybeSettle(event: Event, defaults: UserDefaults) {
    let buffer = readBuffer(defaults: defaults)
    let lastBufferTime = buffer.last?.arrivalTime ?? 0
    if !buffer.isEmpty && (event.now - lastBufferTime) >= 5 {
        settle(buffer: buffer, defaults: defaults)
        clearBuffer(defaults: defaults)
    }
    append(event: event, defaults: defaults)
}
```

**Why 5 seconds, not 30:**
Today's flood data showed the maximum within-burst gap was 1.6 seconds across all events of a real phantom flood. 5 seconds gives a 3× safety margin without imposing a 30-second crediting delay on every event. If future logs show bursts with larger internal gaps, we widen — but 5s is the right starting point given the evidence we have.

**Why no immediate credit for isolated events:**
Until we wait the full window after the event, we can't be sure it's isolated. A second wave might arrive in 2-3 seconds. So every event waits — even the eventually-isolated ones. The 5-second delay is small enough not to matter for the user-facing experience (the main app re-reads usage on foreground anyway).

**What "settle" decides — Phase C below.**

---

## Phase C — Settle the batch

When Phase B triggers settlement, the buffer holds N events that all arrived within 5 seconds of each other.

### Case 1 — Single event in the batch

```
N == 1 → ISOLATED.
Credit at face value:
  delta = max(60, event.thresholdSeconds - lastThreshold[event.appID])
  usage_<id>_today += delta
  lastThreshold[event.appID] = event.thresholdSeconds
  last_credited_global_timestamp = event.arrivalTime
```

No flood checks needed — the event had no neighbors before OR after. Phase A's hard rejects already ruled out absurd thresholds (stale flush, pin replay, regression, shielded). Trust it.

### Case 2 — Multiple events in the batch (burst)

The batch is a cluster of events arriving close together. This is either a legit catch-up (kid genuinely played during a tracking gap, iOS dumping queued events) or a phantom flood (iOS firing events for time that wasn't really used).

**Flood signature checks (any one = flood):**

a. **Shielded reward app event** appears in the buffer.
   The kid physically can't use a blocked app. Any threshold event for a currently-shielded reward app means iOS is replaying phantom data. The whole batch is suspect.

b. **Aggregate claim exceeds available wallclock.**
   ```
   claimed = sum over all apps in buffer of (max threshold for that app - last credited threshold for that app)
   budget  = arrivalTime[first event in buffer] - last_credited_global_timestamp_before_this_burst
   if claimed > budget + grace → flood
   ```
   The kid can only use one app at a time, so total credit claimed across all apps cannot exceed the wallclock that passed since the last credit. Grace ≈ 10% to absorb iOS jitter.

c. **(Future) Kill-density signal.**
   If the extension was killed N times in the last 60 seconds, the next batch is suspect.

**Decision:**

- Any flood signature triggers → REJECT ENTIRE BATCH. Log `SETTLE_FLOOD` with the signature. `last_credited_global_timestamp` does not advance.
- Otherwise → LEGIT CATCH-UP. For each app present in the batch:
  ```
  credit = max(thresholdSeconds for this app in batch) - lastThreshold[appID]
  usage_<id>_today += credit
  lastThreshold[appID] = max(thresholdSeconds for this app in batch)
  ```
  Update `last_credited_global_timestamp` to the batch's last event time.

**Key idea:** we credit the highest threshold each app reached, ONCE, instead of crediting each event individually. This avoids per-event-cap arithmetic and naturally handles out-of-order iOS delivery.

---

## State storage

New UserDefaults keys (in app group):

```
burst_buffer_json              — JSON-encoded array of { appID, thresh, time }
burst_first_event_timestamp    — when current burst started
burst_last_event_timestamp     — when last event in burst arrived
last_credited_global_timestamp — (existing) anchors isolation gap

# Per-app, unchanged from current code:
usage_<id>_today
usage_<id>_lastThreshold
usage_<id>_reset
```

Buffer is small (typically <16 events, <2KB JSON). No memory pressure.

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

## Migration plan

We will land this incrementally, not in one giant commit.

### Step 1 — Documentation (this file). ✅
### Step 2 — Phase A extraction.
Move the existing hard-reject filters into `passesHardRejects(...)`. Strip the burst-context gating that some have added. Build, run, verify on test devices.

### Step 3a — Phase B classifier in SHADOW mode.
Add the classifier at the top of `setUsageToThreshold`. Log every event arrival with its classification (`burst` or `isolated`) and the gap from `last_credited_global_timestamp`. **Routing is unchanged.** Run for a full day on test devices and verify:
- Normal per-minute play classifies as `isolated`.
- Multi-event catch-up bursts classify as `burst`.
- Multi-app phantom cascades (Device C scenario) classify as `burst`.
- Roblox sliding-window recovery (single high-threshold event after silence) classifies as `isolated`.

### Step 3b — Shadow buffer + settlement (no active routing yet).
Add the buffer storage and settlement logic alongside the legacy code. Every event goes into the buffer in parallel with legacy processing. Settlement runs on each event arrival (when previous batch's last event is ≥ 5s old). Log what the settlement WOULD credit / reject, but don't change actual credit. Compare shadow outcomes against legacy outcomes for a day on real devices.

### Step 4 — Promote shadow to active routing.
Once shadow logs confirm settlement gives correct outcomes for both flood and legit cases, flip the switch: legacy path becomes a no-op, buffer + settlement becomes the source of truth.

### Step 5 — Remove dead code.
Delete `SKIP_FLOOD`, `FIRST_EVENT_BUFFER`, `PHANTOM_FLOOD_DETECTED`, `SKIP_BURST_BUDGET`, `PER_EVENT_CAP`, `isMidDayBurst`, `isBurstActive`. Each removal is its own commit with a log-diff showing equivalent behavior.

### Step 6 — Device test pass.
Multi-day testing across Devices 1, 2, 3, 4, A, B, C. Confirm:
- Normal per-minute recording: unchanged.
- Roblox sliding-window recovery: works.
- Device C multi-app phantom flood: rejected in settlement.
- Device 4 multi-wave catch-up: credited via max-threshold-per-app.

---

## Test scenarios (acceptance criteria)

| Scenario | Expected behavior |
|----------|-------------------|
| Kid plays one app, events fire every 60s | Each event isolated, credited 60s, no buffer involved |
| Kid switches apps every 5 minutes | Each event isolated (gap ≥ 60s), credited normally |
| Extension dies for 10 min, restarts, iOS dumps 10 catch-up events for app A in 2s | First event isolated (gap from last credited = 10 min); subsequent 9 events join burst buffer; on next isolated event, burst settles → flood check passes (one app, claimed time matches wallclock) → max-threshold-per-app credits the full 10 min in one shot |
| Multi-app phantom flood (Device C): 16 apps fire in 25s after kill cascade | First event isolated (or shielded → hard reject); rest join burst buffer; settlement detects: claimed_total >> wallclock_since_burst_start → FLOOD → reject all 16 events |
| Shielded reward app fires during burst | Phase A rejects the shielded event itself; AND its presence in the buffer (if it slipped in pre-shield-check) flags settlement as flood |
| Solo phantom event arrives after long idle | Isolated; gets credited; SKIP_STALE_FLUSH and SKIP_PIN_REPLAY catch absurd thresholds in Phase A |
| Roblox sliding-window recovery: min.197 fires when our window was at 145, after silence | Isolated (gap from last credited = many minutes); credited at threshold value — gap closes |

---

## Open questions

1. **Buffer eviction on day rollover.** If burst spans midnight, what do we do? Tentative: settle the burst at midnight before resetting daily counters.
2. **Cold-start of the day with a burst.** First-event-of-day no longer needs FIRST_EVENT_BUFFER — Phase B classifier treats `last_credited_global_timestamp` as 0 → isolated → credit. Is that correct for all cases? Need to verify against logs.
3. **Settlement during long idle.** If a burst happens at 10am and no further events come until noon, settlement waits until noon. Should we add a periodic settlement check (e.g., on every scheduleActivity)? Probably yes for safety.
4. **`isFirstEventAfterUnlock` handling.** Currently this is a special path for credit after reward unshield. Where does it fit? Tentative: a small overlay in Phase C-iso that adjusts delta against wallclock-since-unlock instead of trusting the iOS threshold blindly.

---

## Non-goals

- Changing the upstream `scheduleActivity` / sliding-window logic. This is purely about the event-processing path.
- Changing how the main app reads `usage_<id>_today`. The output contract is unchanged.
- Adding new external dependencies or restructuring the extension's lifecycle.

---

## Status checklist

- [x] Architecture doc v1 — commit `d7b805a`
- [x] Step 2: Phase A section markers (no behavior change) — commit `df7eb38`
- [x] Step 3a: Phase B classifier in SHADOW mode (look-backward only, 30s window) — commit `611f1e2`
- [x] Architecture doc v2 — rewritten to "buffer everything + settle on silence" model with 5s window (this revision)
- [ ] Step 3b (new model): shadow buffer + settlement alongside legacy
- [ ] Step 4: promote shadow buffer to active routing
- [ ] Step 5: dead-code removal
- [ ] Step 6: multi-device test pass

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

## Decision log

### 2026-05-18 — Shadow first before active routing
Original plan (Step 3 in doc): land classifier and divert isolated routing in one commit. Revised to ship shadow-only (Step 3a) first, then promote in a separate commit (Step 3b) once shadow logs confirm correct classification. Rationale: kids are actively using the app on test devices; a misclassified routing change is hard to undo mid-day. Cost is one extra commit; benefit is zero behavior change during validation.

### 2026-05-18 — 30s burst window (not 5s, not 50s)
Original code used 5s — tuned for iOS-flush-batch latency, not for "what's normal cadence". CEO pushed back: normal events fire at ~60s, so anything below 60s is suspicious. Widened to 30s as a conservative middle ground (15-25s margin below 60s cadence). Today's shadow data validates the choice: gaps as low as 42s correctly classified as isolated. If we'd picked 50s, the 42s event would have been false-tagged as burst.

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
