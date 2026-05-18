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
> - Single event (no events before or after ~50s): legit, no doubt → credit.
> - Burst event: run filters to assess → legit catch-up → credit max threshold per app; flood → reject everything.

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
│ PHASE B — Classify context (single decision, single window)  │
│   Gap from last_credited_global_timestamp                    │
│     < 30s  → BURST                                           │
│     ≥ 30s  → ISOLATED                                        │
│                                                              │
│   Also: settle any previously-open burst whose gap to now    │
│   is ≥ 30s. The burst is "done" — evaluate it.               │
└─────────┬────────────────────────────────────────┬───────────┘
          │ ISOLATED                               │ BURST
          ▼                                        ▼
┌────────────────────────┐  ┌──────────────────────────────────┐
│ PHASE C-iso — Credit   │  │ PHASE C-burst — Buffer           │
│ Trust iOS threshold.   │  │ Add this event to in-flight      │
│ Credit immediately.    │  │ burst buffer. Don't credit yet.  │
│ Update lastThreshold.  │  │                                  │
└────────────────────────┘  │ Burst settles on NEXT event with │
                            │ gap ≥ 30s, OR a separate         │
                            │ scheduled settlement check.      │
                            │                                  │
                            │ Settlement decision:             │
                            │   Flood signature → reject all   │
                            │   Legit catch-up → credit max    │
                            │     threshold per app, one shot  │
                            └──────────────────────────────────┘
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

## Phase B — Classify context

One classifier. One window. One source of truth.

```swift
enum EventContext {
    case isolated       // gap >= 30s from last credited event (any app)
    case burst          // gap < 30s — this event continues an active burst
                        // OR starts a new burst (first event after isolation)
}

func classify(now: TimeInterval, defaults: UserDefaults) -> EventContext {
    let lastCredited = defaults.double(forKey: "last_credited_global_timestamp")
    let gap = lastCredited > 0 ? now - lastCredited : .infinity
    return gap < 30 ? .burst : .isolated
}
```

**Why 30 seconds:**
- Normal per-minute thresholds fire at ~60s cadence.
- Anything below 60s is not normal cadence.
- 30s gives a generous margin (events within 30s of each other are clearly clustered).
- In real flow the kid foregrounds one app at a time, so legit cross-app events arrive >60s apart.

**Settlement check (also in Phase B):**

Before classifying the current event, check if there's an in-flight burst buffer. If yes, look at the gap between the buffer's last event and now:
- gap ≥ 30s → burst has settled, evaluate the buffer (flood vs legit), apply or reject credits, clear buffer.
- gap < 30s → burst still in flight, fall through.

This lets settlement happen "lazily" on the next event arrival. No timers, no async — just check on entry.

---

## Phase C — Route by context

### Phase C-iso (isolated event)

```
Trust iOS threshold value.
delta = max(60, thresholdSeconds - lastThreshold)
Credit delta to usage_<id>_today.
Update lastThreshold to thresholdSeconds.
Update last_credited_global_timestamp to now.
```

No budget checks. No per-event caps. Isolated event = legit by definition (per CEO model).

**Safety net:** if an isolated event has an absurd threshold (e.g., min.2700 when wallclock since pin is 60s), Phase A's `SKIP_STALE_FLUSH` and `SKIP_PIN_REPLAY` already catch it. Phase C-iso does not need its own check.

### Phase C-burst (burst event)

```
Add to in-flight burst buffer:
  burst_buffer = [
    { appID, thresholdSeconds, arrivalTime },
    ...
  ]
Do NOT credit yet.
Update burst_last_event_timestamp = now.
Return false (no credit on this call).
```

The buffer accumulates until the burst settles.

### Burst settlement (triggered in Phase B on next event)

When a new event arrives and `now - burst_last_event_timestamp >= 30s`, the burst is done. Evaluate the buffer:

```
1. Flood signature checks (any one of these = flood):
   a. Any shielded reward app event appears in the buffer.
      Kid physically can't use a blocked app → flood.
   b. Sum of (max threshold per app in buffer) > wallclock since burst started + grace.
      Total claimed > wallclock possible → flood.
   c. (Future) Kill-density signal: extension was killed N times in last 60s.

2. If flood → reject all buffer events. Log SETTLE_FLOOD. Clear buffer.

3. If legit catch-up → for each app in the buffer:
     credit = max(thresholdSeconds_per_app) - lastThreshold_per_app
     Apply credit (one shot per app). Update lastThreshold to max.
   Log SETTLE_LEGIT with per-app credits. Clear buffer.
```

**Key change from current code:** for a legit burst, we credit the highest threshold each app reached, ONCE, instead of accumulating per-event deltas. This matches the CEO model and avoids the per-event-cap dance.

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

### Step 3b — Promote isolated routing.
Once shadow logs confirm classification correctness, divert ISOLATED events to the new fast path: trust threshold, credit `max(60, threshold - lastThreshold)`, skip the legacy per-event-cap branching and SKIP_BURST_BUDGET. BURST events continue to fall through to existing burst-handling code until Step 4 replaces it.

### Step 4 — Phase C-burst buffer + settlement.
Add the buffer storage. Replace the per-event burst-handling code with buffer-add. Implement settlement on next event entry. Build, run, validate flood detection on Device C log replay.

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

- [x] Architecture doc (this file)
- [ ] Phase A extraction
- [ ] Phase B classifier
- [ ] Phase C-iso fast path
- [ ] Phase C-burst buffer + settlement
- [ ] Dead-code removal
- [ ] Multi-device test pass
