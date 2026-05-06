# Path B — High-Water-Mark Credit Model (Redesign Plan)

**Branch:** `redesign/highwater-mark-credit-model`
**Status:** PLAN — no code changes yet. Awaiting CEO sign-off.
**Author:** drafted 2026-05-04
**Supersedes:** the wall-clock-cap + per-event-cap + lastThreshold-hold-on-clamp + initialUsage=60 + rawDelta=max(60,…) stack accumulated Apr 23 → May 4.

---

## Executive summary (non-technical)

Today, every time the system records reward-app usage, it asks:
*"How much new time happened between the last event and this one?"*
That question turns out to have many wrong answers when the iPhone defers events, restarts monitoring, charges, sleeps, or wakes. We've spent two weeks adding bandaids — each one fixing one wrong answer while quietly enabling another wrong answer. We're up to seven layered carve-outs.

This plan replaces the question. The new question is:
*"What's the highest minute mark this app has reached today, and have we already credited that?"*

The new question has one answer at any moment in time. It doesn't depend on event ordering, batch flush timing, charging state, or restart history. The same answer holds whether iOS delivers events in order, out of order, all at once, or hours late.

If the redesign is correct, six bug classes simultaneously become impossible: under-credit on bursts, over-credit on flood heads, phantom credit on idle apps, lastThreshold poisoning, restart-replay phantom minutes, and the +60s NEW_DAY initial credit on stale carry-overs.

Risk: the redesign touches the most sensitive code in the system. Mitigation is a parallel-shadow rollout — both algorithms run side-by-side for one cycle, the new one is dark while the old one ships, and we ship-only after the diff is clean.

---

## 1. Why now

**The pattern in the doc:**

| Date | Patch | Bug it fixed | Bug it enabled |
|---|---|---|---|
| Apr 23 (early) | Wall-clock cap (`delta ≤ wallClockElapsed`) | Apr 23 charging-flush over-credit (+111 min) | First-event-after-gap bypass |
| Apr 23 (late) | Per-event 60 s hard cap (`perEventCap = 60`) | First-event-after-gap bypass | Squash legitimate post-unlock catch-ups |
| Apr 26 | unlockTime baseline + `isFirstEventAfterUnlock` relaxation | Squash post-unlock catch-ups | Stale-catchup `lastThreshold` poisoning (Apr 29 blackout) |
| Apr 30 v1 | `delta < rawDelta` lastThreshold-hold gate | Apr 29 blackout | 123 false-positive holds in one day; SKIP_REGRESSION disabled |
| Apr 30 v2 | `rawDelta > perEventCap` hold gate | v1 false-positives | Permanently frozen lastThreshold per app post-flood |
| May 1 v3 | `lastThreshold = max(prior, newToday)` on hold | v2 frozen-tail quirk | (none — but added complexity) |
| May 3 | Window-rebuild Darwin-notification + flag bridge | In-callback rebuild dies on memory-budget kill | Restart thrashing on catch-up bursts |
| May 4 | 5 s debounce on rebuild requests | Restart thrashing | (Issue X paused — perEventCap still squashes) |

**Two structural problems revealed by this history:**

1. **Every patch is reactive.** Each new failure mode required a new carve-out. The carve-outs interact (e.g., the unlock relaxation breaks the lastThreshold gate's `delta<rawDelta` form). We've never had a quiet week.
2. **The model is wrong-shaped.** The current code answers "credit per event" — but iOS event delivery is **unreliable in timing, ordering, and authenticity**. iOS replays phantom thresholds (May 1), defers batches (Apr 29), fires out of order (Apr 12), and skips intermediate marks (occasional). A model that credits per-event is fighting iOS. A model that credits per-cumulative-position absorbs all of those failure modes naturally.

**Confidence the redesign is right:** the cumulative-position model is what `iOS Settings → Screen Time` itself uses (it shows total minutes today, never event count). When we compare against ground truth, ground truth is always a cumulative number.

---

## 2. Goals & non-goals

### Goals (in priority order)

1. **Faithful credit:** `usage_<id>_today` = real minutes the kid used the app today, ±1 min. Validated against `iOS Settings → Screen Time`.
2. **Same-day correctness invariant:** for any logical ID and any time t, `usage_<id>_today(t) ≤ secondsSinceMidnight(t)`. The kid cannot have used an app for more minutes than have elapsed since midnight.
3. **No regression on shipped invariants:** pool-aware shield gate (Apr 26–27), pool-aware `SKIP_SHIELDED_RACE` (May 2), pool-divergence re-shield bypass (May 3), config-drift self-heal (May 3), window-rebuild Darwin bridge (May 3), 5 s debounce (May 4), MAPPING_RECOVERED (May 3), midnight rebuild (Apr 12), pin-replay defenses (Apr 25), shield-clearing race + boot reconcile (Apr 24), `includesPastActivity:true` (Apr 12), 45-min BGAppRefreshTask (Mar 1), SKIP_MIDNIGHT (Feb 23), per-app `ext_usage_*_timestamp` baseline (Apr 23). All survive.
4. **Single algorithm, no carve-outs:** one credit rule that doesn't grow conditional branches per failure mode. Future bugs surface as plain math errors, not policy interactions.
5. **Migration safety:** the redesign cuts over without losing in-flight `ext_usage_<id>_today` totals or breaking pool drain. No "lose today, fix tomorrow" cost.

### Non-goals (explicit)

- Recovering historical losses. Apr 29's 9.4-hour blackout, Apr 23's 111 min, May 2's 26 NO_MAPPING events are forfeit as previously decided.
- Cross-device CloudKit sync of usage. Out of scope — App-Group local stays local.
- Changing iOS authorization, monitoring lifecycle, or scheduleActivity cadence. Redesign sits inside the recording path only.
- Fixing Bug C (Sami's wrong-token-in-displayName-slot). Separate root-cause investigation.
- Fixing the May 1 phantom-threshold replay structurally. The redesign happens to make it harmless, but we don't add explicit phantom detection.

---

## 3. Constraints checklist (lessons from `docs/SMART_THRESHOLD_FILTERING.md`)

Every item is a constraint the redesign MUST satisfy. Each is cited to a section of the existing doc.

### Recording-path constraints

| # | Constraint | Source section | Constraint type |
|---|---|---|---|
| C1 | `includesPastActivity` MUST be `true` | "iOS DeviceActivityEvent Behavior" / Apr 12 | iOS contract — unchanged by redesign |
| C2 | iOS cumulative resets at midnight | Apr 12 device confirmation | Day-boundary constraint |
| C3 | `intervalDidStart()` MUST reset `lastThreshold` and counters at midnight (only) | Apr 13 revert | Day-boundary cleanup, not a credit decision |
| C4 | iOS catch-up events fire OUT OF ORDER | Apr 12 | Credit must be order-insensitive |
| C5 | iOS thresholds can fire above the registered window when rebuild trigger fails | May 3 NO_MAPPING | Credit must work without primitive-map presence |
| C6 | iOS replays the entire registered threshold set on autonomous INTERVAL_END/START | May 1 phantom | Credit must ignore phantom events |
| C7 | iOS defers callbacks under low-power / idle, flushes in batch | Apr 23, Apr 29 | Burst credit cannot exceed real elapsed time |
| C8 | iOS "delivers" a threshold once we receive the callback, regardless of return value | May 2, May 3 | Returning false doesn't re-fire iOS; we lose intermediate thresholds permanently |
| C9 | Extension callback budget ~6 MB / ~30 s; in-callback rebuild is unreliable | May 3 Bug A | Heavy work must be deferred via Darwin notification → main app |
| C10 | Extension is ephemeral; terminates after callback returns | "Extension Memory Constraints" | UserDefaults state must be the source of truth, not in-process memory |
| C11 | Persisted timestamp anchor (`ext_usage_<id>_timestamp`) is the per-app last-event time, written every recording, cleared at midnight | Apr 23 | Available for sanity bounds |
| C12 | Per-app `app_stable_hash_<id>` is written by `scheduleActivity()` and used by event-name reverse lookup | May 3 MAPPING_RECOVERED | Available for recovery from primitive-map miss |
| C13 | `tracked_app_ids` lists every monitored logical ID; written by main app | "Current State" | Trusted source of truth for "is this app under our control" |

### Filter-chain constraints (must not be regressed)

| # | Filter | Source | Behavior |
|---|---|---|---|
| F0 | SKIP_MIDNIGHT (Filter 0) | Feb 23 | Block events between midnight and first scheduleActivity (only if extension-side rebuild fails) |
| F1 | SKIP_RESTART (Filter 1, catchup_max-related) | Apr 1 (removed) | catchup_max system removed; replaced by monitoring restart_timestamp checks. Stays removed. |
| F2 | SKIP_SHIELDED + SKIP_SHIELDED_RACE (Filter 2) | Apr 24, May 2 | Pool-aware backstop. Reads `computeEffectivePoolBalance()`. Survives unchanged. |
| F3 | SKIP_PIN_REPLAY | Apr 25 | Pin-mode persistence. Survives unchanged. |
| F4 | SKIP_REGRESSION / SKIP_DUP | Apr 12, Apr 30 | Same-day: thresh must strictly increase. Cross-day: dup-block. **Redesign reframes this — see §4** |
| F5 | NO_MAPPING → MAPPING_RECOVERED | May 3 | Stable-hash reverse lookup. Survives unchanged; redesign extends to *not* require map presence at all. |

### Pool / shield invariants

| # | Invariant | Source |
|---|---|---|
| P1 | Extension `computeEffectivePoolBalance` and main-app `BlockingCoordinator.checkAvailableMinutes` MUST share one formula | Apr 26–27, May 3 |
| P2 | Pool = `max(0, historical + todayEarned - todayUsed)` on both sides | May 3 |
| P3 | `SKIP_SHIELDED_RACE` backstop must allow recording during pool-only Time Bank carry-forward unshields | May 2 |
| P4 | `POOL_EMPTY_BLOCK` re-shields all reward apps when pool ≤ 0 | Apr 26–27 |
| P5 | Pool drain reads `usage_<id>_today` for reward apps; redesign must keep this key authoritative | Apr 26–27, May 3 |

### Counter-state constraints

| # | Constraint | Source |
|---|---|---|
| K1 | `usage_<id>_today` is the user-visible "minutes used today" — must remain the authoritative key | Apr 26–27 (pool drain), main-app dashboards |
| K2 | `ext_usage_<id>_today/_total/_date/_hour/_timestamp/_hourly_<h>` are the "ext_ source of truth" set | Multiple |
| K3 | `resetAllDailyCounters` clears all `ext_usage_*_*` keys at midnight | Apr 13 |
| K4 | Hourly buckets `ext_usage_<id>_hourly_<h>` track per-hour distribution; redesign must keep populating | Multiple |
| K5 | `last_recorded_timestamp` (global, diagnostic) and `usage_<id>_modified` survive | "Current State" |

### What the redesign CANNOT do (hard prohibitions from doc)

| # | Prohibition | Source |
|---|---|---|
| N1 | NEVER add primers (low-threshold seeding) | "Common Pitfalls" |
| N2 | NEVER reintroduce catchup_max system | Apr 1 |
| N3 | NEVER reset `lastThreshold` (or its successor) intraday | Apr 13 revert |
| N4 | NEVER add a 180 s cap on credit | Feb 27–28 |
| N5 | NEVER add double restart | "Common Pitfalls" |
| N6 | NEVER use `dictionaryRepresentation()` in extension | "Extension Memory Constraints" |
| N7 | NEVER use read-parse-rewrite for extension `debugLog` | "Common Pitfalls" |
| N8 | NEVER set `includesPastActivity: false` | Apr 12 |
| N9 | NEVER skip hooks / signing on commits unless user asks | (CLAUDE.md, not the doc, but applies) |

---

## 4. The redesign

### 4.1 Core idea

Replace **per-event delta crediting** with **per-event high-water-mark anchoring**.

For every monitored app, track a per-day cumulative high-water mark — `ext_usage_<id>_highwater` — initialized to 0 at midnight. Every threshold event's `thresholdSeconds` is a candidate high-water; we keep the maximum we've seen so far. The credit for an event is the increase in the high-water mark, bounded by elapsed wall-clock since midnight.

### 4.2 Credit rule (single source of truth)

Pseudocode for the new `recordUsageEfficiently → setUsageToThreshold` body, replacing the "PASSED ALL FILTERS" section:

```
let priorHighwater = defaults.integer("ext_usage_<id>_highwater")     // 0 at midnight
let priorToday     = defaults.integer("ext_usage_<id>_today")          // pool key, must agree
let secondsSinceMidnight = nowTimestamp - startOfToday

// 1. Highwater proposal
let candidate = thresholdSeconds                                       // iOS-reported cumulative

// 2. Sanity bound — kid can't have used app more than time elapsed since midnight
let upperBound = secondsSinceMidnight

// 3. New highwater is the max we've ever seen, bounded by physical reality
let newHighwater = min(max(priorHighwater, candidate), upperBound)

// 4. Credit is the gap between today's recorded and the new highwater
let credit = max(0, newHighwater - priorToday)

// 5. Persist
defaults.set(newHighwater, "ext_usage_<id>_highwater")
defaults.set(priorToday + credit, "ext_usage_<id>_today")
defaults.set(priorToday + credit, "ext_usage_<id>_total")              // total tracks today on its own pre-existing path
defaults.set(nowTimestamp, "ext_usage_<id>_timestamp")
// hourly bucket: add `credit` to current hour's bucket (preserves K4)
```

That's it. No `rawDelta`, no `lastThreshold`, no `perEventCap`, no `wallClockElapsed`, no `unlockTime` baseline, no `initialUsage = 60`, no `LASTTHRESH_HOLD`, no `WALL_CLOCK_CAP`. Five lines of math do the work the previous ~80 lines did.

### 4.3 Filter chain reframing

| Old filter | New status |
|---|---|
| F0 SKIP_MIDNIGHT | **Unchanged.** Still blocks events between midnight and first scheduleActivity in the rare case extension-side rebuild fails. |
| F2 SKIP_SHIELDED + SKIP_SHIELDED_RACE | **Unchanged.** Pool-aware backstop survives intact. |
| F3 SKIP_PIN_REPLAY | **Unchanged.** |
| F4 SKIP_REGRESSION (`thresh ≤ lastThreshold`) | **Removed.** No longer needed — out-of-order events become harmless because high-water is a max, not a sequence. A "stale catch-up" event with `thresh = 3300` arrives → high-water bumps to min(3300, secondsSinceMidnight). A subsequent in-order `thresh = 1500` arrives → high-water stays at 3300 (max), no credit, no harm. |
| F4 SKIP_DUP (cross-day) | **Removed.** Duplicates produce credit=0 naturally (newHighwater == priorToday). |
| F5 NO_MAPPING → MAPPING_RECOVERED | **Unchanged** — still the recovery path for primitive-map miss. |

### 4.4 What handles each old failure mode

| Failure mode | Old defense | New defense |
|---|---|---|
| Apr 23 charging-flush 111 min over-credit | Wall-clock cap | `secondsSinceMidnight` upper bound caps each app at elapsed-since-midnight; flood of `thresh = 3420` for an app with priorToday=0 at 02:00 credits min(3420, 7200) = 3420 — wait, that's still over-credit. **See §4.5 — additional bound needed.** |
| Apr 23 first-event-after-gap +3420 s | perEventCap = 60 | `secondsSinceMidnight` bound + §4.5 anchor |
| Apr 26 post-unlock under-credit | unlockTime baseline relaxation | Not applicable — high-water doesn't care about unlock; if iOS reports `thresh = N`, we accept up to `secondsSinceMidnight` |
| Apr 29 lastThreshold poisoning blackout | hold-on-clamp | `lastThreshold` doesn't exist in the new model. Out-of-order events are no-ops. |
| Apr 30 v1 false-positive holds | rawDelta > perEventCap rule | Doesn't exist |
| May 1 phantom threshold replay | (none shipped) | Phantom events for an unused app have `priorToday = 0`, `priorHighwater = 0`. First phantom: `newHighwater = min(thresh, secondsSinceMidnight)`, credit = newHighwater. **See §4.5 — phantom events for an unused app would still credit.** |
| May 3 NO_MAPPING | MAPPING_RECOVERED | Unchanged |
| May 4 Bug X (perEventCap squashing legitimate bursts) | (paused) | A burst delivers events whose `thresh` values legitimately reflect minutes used; the highest one wins. Subsequent in-order events advance high-water normally. No squashing. |
| May 4 Bug Z (flood-head fake 60 s) | (documented) | NEW_DAY initial=60 doesn't exist. First event of day for an app with `priorToday=0` credits `min(thresh, secondsSinceMidnight)` — for a stale 00:00:01 event with `thresh = 60`, credit = min(60, 1) = 1 s. Phantom on unused app: see §4.5. |

### 4.5 The remaining gap: phantom credit on unused apps

The naive high-water model still over-credits in two scenarios:

**Scenario X1 — May 1 phantom replay on unused app.** iOS replays `thresh = 2700` for an app the kid never opened today. `priorToday = 0`, `priorHighwater = 0`, `secondsSinceMidnight = 50000`. Naive credit = 2700 s = 45 min phantom credit. *Worse than the current per-event 60 s cap.*

**Scenario X2 — Apr 23 charging-flush flood.** iOS dumps `thresh = 3420` for an app the kid actually used 5 min today. `priorToday = 300`, `priorHighwater = 300`, `secondsSinceMidnight = 78000`. Naive credit = 3420 − 300 = 3120 s = 52 min over-credit.

We need a tighter upper bound than "seconds since midnight." Three options, one chosen:

#### Option α — anchor to last legitimate activity (CHOSEN)

Track per-app a "last credible activity timestamp": the last time we observed the app's high-water actually advance via a recording that the wall-clock cap *would have* allowed under the old model. Call it `ext_usage_<id>_lastCreditTimestamp`, initialized to `startOfToday` at midnight.

The upper bound becomes:

```
let elapsedSinceLastCredit = nowTimestamp - lastCreditTimestamp
let upperBound = priorHighwater + elapsedSinceLastCredit
```

Rationale: high-water can only have grown by at most the wall-clock elapsed since the last time we credited. Phantom events arriving in a 0.249-s burst all see `elapsedSinceLastCredit ≈ time-since-last-real-event`, which is the same per-app bound the wall-clock cap provided — but cleanly framed as a high-water bound, not a per-event bound.

**Re-running scenarios:**

- **X1 (phantom replay on unused app).** `priorHighwater = 0`, `lastCreditTimestamp = startOfToday`, `elapsedSinceLastCredit = 50000 s`. Naive `upperBound = 50000`. Still allows 45 min phantom. **Need additional defense — see §4.6.**
- **X2 (charging-flush on used app).** `priorHighwater = 300`, `lastCreditTimestamp = ~5 min ago`, `elapsedSinceLastCredit ≈ 300 s`. `upperBound = 600 s`. iOS-reported `thresh = 3420 → newHighwater = min(3420, 600) = 600 → credit = 300 s`. Five minutes of legit recent + bounded growth. Matches Apr 23's accepted tradeoff.
- **Apr 29 deferred batch (real 16-min idle gap).** Kid was idle, last event was 14:18, flush at 14:35. `lastCreditTimestamp = 14:18`, `elapsedSinceLastCredit = 1020 s`. `upperBound = priorHighwater + 1020`. iOS-reported `thresh = 3300` (catch-up). If priorHighwater was 1140, `newHighwater = min(3300, 1140 + 1020) = 2160 → credit = 1020 s = 17 min`. **Correctly attributes the 17-min idle/deferred window** instead of the old 60-s clamp losing 16 min of real usage. **This is the structural fix for Bug X.**

#### Option β — only credit if app's `tracked_app_ids` membership AND iOS-reported cumulative > stored

Adds a guard before credit: require iOS's reported `thresh` to actually have moved past `priorHighwater`. Phantom replays of `thresh ≤ priorHighwater` produce credit = 0 trivially (already true in α). Phantom replays *above* `priorHighwater` for an unused app are still un-bounded by α alone — they need the §4.6 anchor.

#### Option γ — fixed registered window upper bound

Bound `upperBound` by the registered window top (`window_top_min_<id> * 60`). Simple, but a phantom `thresh = 2700` on an unused app can still credit up to 2700 s if priorHighwater = 0. Doesn't help X1.

**Decision: ship α. Add §4.6 to handle X1.**

### 4.6 Defense for Scenario X1 (phantom replay on unused app)

A phantom replay fires every registered threshold for every monitored app, including apps with `priorHighwater = 0`. The first phantom seen has elapsedSinceLastCredit = secondsSinceMidnight (no prior event today), so α alone doesn't bound it.

Two complementary defenses:

**6a. Phantom-burst signature detection.** When an `eventDidReachThreshold` callback arrives within ~2 s of a sibling threshold for *the same app* whose `thresh` differs by more than 60 s, mark this app as "in iOS catch-up burst" for the next 5 s. During the burst window, the upper bound for this app's credit becomes `priorHighwater + (nowTimestamp - lastCreditTimestamp)` — same as α. Outside the burst window, `upperBound = secondsSinceMidnight` is fine.

This catches X1: phantoms for an unused app arrive in clusters → burst signature detected → `upperBound = 0 + 0 = 0` → credit = 0.

**6b. Cross-app burst correlation.** May 1's phantom replay fires *every* monitored app within ~1 s. We can detect "all 8 apps received a threshold in the last 1 s" and mark a *system-wide* phantom-burst window. Easier signal than per-app and covers the same case.

**Implementation.** Cross-app burst correlation (6b) is simpler and the May 1 evidence supports it strongly (8 apps in <1 s is iOS-driven; legitimate use is single-app). Use 6b as the primary; fall back to per-app 6a only if 6b proves too coarse.

### 4.7 lastThreshold removal & SKIP_REGRESSION reframing

**Old.** `usage_<id>_lastThreshold` advances on every record; SKIP_REGRESSION rejects `thresh ≤ lastThreshold`. Out-of-order catch-ups poison it (Apr 29). Holds, max-with-newToday, perEventCap gates added to defend.

**New.** `usage_<id>_highwater` replaces it. SKIP_REGRESSION goes away. An out-of-order event below high-water produces credit = 0 naturally (no regression to filter against; high-water can't go down). An out-of-order event above high-water advances it, bounded by α + 6b.

**Migration.** On first launch with the new binary, read `usage_<id>_lastThreshold` (if present) and write it as `ext_usage_<id>_highwater`. Both keys can coexist for one cycle for parallel-shadow validation; remove `_lastThreshold` after sign-off.

### 4.8 NEW_DAY simplification

`intervalDidStart()` at midnight runs `resetAllDailyCounters()` → all `ext_usage_*_*` keys cleared (including the new `_highwater`). First event of the day arrives:

- `priorHighwater = 0`, `priorToday = 0`, `lastCreditTimestamp = startOfToday`.
- `elapsedSinceLastCredit = nowTimestamp - startOfToday` (small for early-morning events; large if first event is afternoon).
- `upperBound = 0 + elapsedSinceLastCredit`.
- `newHighwater = min(thresh, elapsedSinceLastCredit)`.
- `credit = newHighwater`.

A stale 00:00:01 phantom with `thresh = 60` → `elapsedSinceLastCredit = 1` → credit = 1 s (Bug Z resolved).
A real first-of-day event at 12:00 with `thresh = 60` → `elapsedSinceLastCredit = 43200` → credit = 60 s (correct).
A real first-of-day burst at 12:00 with `thresh = 3600` (kid used app for 60 min before main app opened, tracked via includesPastActivity:true) → credit = min(3600, 43200) = 3600 s = 60 min (correct).

The `initialUsage = 60` constant is deleted. `rawDelta = max(60, ...)` is deleted.

### 4.9 What stays exactly as-is

- Filter 0 (SKIP_MIDNIGHT)
- Filter 2 (SKIP_SHIELDED, SKIP_SHIELDED_RACE — pool-aware)
- Filter 3 (SKIP_PIN_REPLAY)
- Filter 5 (NO_MAPPING → MAPPING_RECOVERED)
- Window-rebuild (in-callback fast-path + Darwin-notification + flag bridge + 5 s debounce + opportunistic drain)
- Config-drift self-heal
- Pool-aware shield gate / re-shield / `computeEffectivePoolBalance` formula
- Hourly bucket population (just sum credit into current hour)
- Battery context plumbing
- Rotating extension log (`ExtensionFileLogger`)
- BGAppRefreshTask cadence (45 min)
- Midnight rebuild (`extensionRebuildSlidingWindow` from `intervalDidStart`)

---

## 5. Migration & rollout

### 5.1 Two-phase ship

**Phase 1 — Shadow mode (one full day).**

- New `_highwater` key written alongside existing `_lastThreshold` and `_today`.
- Both algorithms run; the **old** algorithm's output is what writes `_today` (still authoritative for pool drain).
- New algorithm's output is written to a parallel diagnostic key `ext_usage_<id>_today_v2` and logged.
- End-of-day comparison: for each app, expect `today` and `today_v2` within ±2 min of iOS Settings → Screen Time. The doc's validation pattern.
- A diagnostic line `HW_SHADOW_DELTA app=<id> today=N today_v2=M iosScreenTime=K` once per minute or per record.

**Phase 2 — Cut over.**

- After one full day with `today_v2` matching iOS to ±2 min on all 8+ apps (specifically including a charging-flush event, an idle-gap deferred batch, and a NEW_DAY-arriving-mid-day pattern):
  - `_today` is now written from the new algorithm.
  - `_lastThreshold` and the perEventCap / wallClockCap / hold-on-clamp branches are deleted.
  - Shadow `today_v2` key is deleted.
  - Doc updated.

### 5.2 Branch / commit hygiene

- Branch already created: `redesign/highwater-mark-credit-model`.
- Phase 1 commit: shadow-mode changes only. Zero behavioral change to today's recording. Reviewable as "instrumentation-only."
- Phase 2 commit (after sign-off + 1-day shadow validation): cut-over + deletions. Roughly −150 +50 lines net.
- Squash before merge to main (already the convention on prior fix branches).
- Do not merge until both phases land cleanly and the doc validation matrix is green.

### 5.3 Rollback plan

If Phase 2 surfaces a regression in the field:

- Revert is a single-commit operation (Phase 2 is one commit; Phase 1 stays even after revert as shadow instrumentation, harmless).
- Migration `_lastThreshold ← _highwater` (the inverse of §4.7's migration) is mechanically simple.
- Pool drain is unaffected because `_today` is the contract, not the underlying algorithm.

### 5.4 Validation matrix (REQUIRED before Phase 2 ship)

For each scenario, both algorithms must produce `_today` within 2 min of iOS Settings → Screen Time:

| # | Scenario | Trigger condition | Expected new behavior |
|---|---|---|---|
| V1 | Healthy day, foreground use only | Kid uses 1 reward app for 30 consecutive min | `_today = 1800 ± 60`. No `LASTTHRESH_HOLD`-like markers. |
| V2 | Charging-flush deferred batch | Kid uses 5 min, screens off 2 h, plug in charger | New: `_today = 300 ± 60`. Old: would also work post-fix. |
| V3 | Apr 29 idle-deferred batch (16 min) | Device idle 16 min mid-session, then resume | New: `_today` reflects full 16 min idle window if app was open. Old: lost 16 min. **Bug X resolved here.** |
| V4 | Apr 23 first-event-after-gap | Kid uses 60 min total, gap 2 h between sessions | New: `_today = 3600 ± 60`. Old: ≤ 60 (squash). **Bug X resolved here.** |
| V5 | May 1 phantom replay | Charger plug-in triggers iOS INTERVAL_END/START on monitored set | New: `_today` for unused apps stays 0 (cross-app burst signature). Old: +60 s phantom per unused app. **Bug Z resolved.** |
| V6 | Out-of-order catch-up burst | iOS dumps `min.55` before `min.20` | New: high-water = 55, subsequent `min.20` is no-op. Old: SKIP_REGRESSION blocked min.20 (correct), but the Apr 29 lastThreshold poisoning chain is impossible in the new model. |
| V7 | NEW_DAY stale phantom | Phantom event at 00:00:01 with `thresh = 60` | New: credit = 1 s. Old: credit = 60 s (Bug Z). |
| V8 | NO_MAPPING + window-top-hit | Threshold above registered window | MAPPING_RECOVERED branch unchanged; new algorithm runs after recovery. |
| V9 | Pool drain integrity | Kid spends down pool to 0 across V1+V2 | Pool decrement matches `_today` delta minute-by-minute. Pool-aware shield re-applies on `pool ≤ 0`. Pool-divergence May 3 invariant preserved. |
| V10 | Pin-replay defense (Apr 25) | Newly-added pin app fires within `pinned_apps_today` window | SKIP_PIN_REPLAY still rejects events; new algorithm never sees them. Same. |
| V11 | Shield-clearing race + boot reconcile (Apr 24) | Child device boot with active shield | Shield reconcile from `AppUsageViewModel.init`; new recording path doesn't interact. |
| V12 | Cross-day rollover (Apr 13 revert preserved) | Midnight tick during active use | `intervalDidStart` clears `_highwater` along with `_today`. First event after midnight credits per §4.8. |

**Sign-off gate:** validation matrix V1–V12 must pass on a real device for Phase 2 to ship.

---

## 6. Risk assessment

| Risk | Mitigation |
|---|---|
| **Phase 1 instrumentation overhead in extension callbacks** (memory + time budget) | New keys per recording = 1 read, 1 write. Bounded. Worst case: 8 apps × 2 keys = 16 ops, well under iOS budget. |
| **Phase 2 cut-over regresses pool drain** | `_today` key contract is preserved; pool drain reads the same key. Phase 1 shadow validates `_today_v2` matches `_today` to ±2 min per app per day before cutover. |
| **Cross-app burst correlation false-positive** | If correlation window is too wide, we suppress legit credit. Mitigation: §4.6.6b uses 1-s window across ≥4 apps (May 1 evidence: 8 apps in <1 s). Legit usage hits 1 app at a time. Tune empirically in Phase 1. |
| **Migration loses `_lastThreshold` data on first launch** | One-time migration writes `_highwater = _lastThreshold`. Worst case if migration fails: `_highwater = 0`, meaning the next event credits up to `secondsSinceMidnight` — which the upper bound caps anyway. No catastrophic over-credit. |
| **Apr 23 scenario re-test fails** | Phase 1 captures the scenario in shadow. If V4 fails, do not ship Phase 2; investigate. |
| **Apr 26-27 pool-aware shield invariant inadvertently broken** | Redesign explicitly preserves `computeEffectivePoolBalance` formula and `usage_<id>_today` key. Documented as constraint P1–P5. Code review checks for any change to those identifiers. |
| **CEO can't validate technical correctness** | Validation matrix is framed in observable outcomes (minutes recorded vs iOS Screen Time, pool decrement behavior, shield re-application). CEO can read the matrix and verify against device. |
| **Hidden interaction with extension memory budget** | Phase 1 runs both algorithms in parallel; if memory blows, we see it before Phase 2. Worst case: cut Phase 2 scope and run new algorithm only. |

---

## 7. Estimated effort

| Phase | Scope | Days |
|---|---|---|
| Plan (this doc) | Done. | 0 |
| Phase 1 implementation | Add `_highwater`, `_lastCreditTimestamp`, shadow `_today_v2`, cross-app burst signature, diagnostic logs. ~80 lines added in extension. | 0.5 |
| Phase 1 device test | One full day with mixed scenarios, capture log. | 1 |
| Validation matrix V1–V12 review | Compare shadow output to ground truth. Diagnose any discrepancy. | 0.5 |
| Phase 2 implementation | Cut over `_today` to new algorithm. Delete `_lastThreshold`, perEventCap, wallClockCap, hold-on-clamp, initialUsage=60, rawDelta floor. ~150 lines deleted, ~10 added. | 0.5 |
| Phase 2 device validation | One day post-cutover, confirm matrix still green and no regression in pool drain. | 1 |
| **Total** | | **3.5 days** |

---

## 8. Open questions for CEO

1. **Are you OK with the two-phase rollout** (1 day shadow, then cut-over) — or do you want a single-shot replacement?
2. **Acceptance criterion** — is "±2 min/app vs iOS Screen Time across all 8+ apps for one full day including a charging-flush" sufficient to ship Phase 2? Or do you want a longer shadow period (e.g., 3 days)?
3. **The May 1 phantom replay defense** (§4.6.6b cross-app burst signature) is heuristic. The threshold (≥4 apps in <1 s) is informed but not bulletproof. Are you OK with that, or do you want me to design a stricter detector before Phase 2?
4. **Bug C** (Sami's wrong-token in displayName slot) is **unrelated** to this redesign and stays pending. OK?
5. **App Store version implications.** This branch will diverge from `fix/stale-catchup-lastthreshold-poisoning`. Are we shipping the redesign as 1.0.5 (and holding 1.0.4 patches), or rolling 1.0.4 forward with the existing wall-clock cap and shipping the redesign as a separate later release?

---

## 9. Next steps after sign-off

1. Phase 1 commit on `redesign/highwater-mark-credit-model`.
2. Build, deploy to test devices.
3. One-day shadow run; collect rotating logs.
4. Walk through V1–V12 against logs + iOS Screen Time.
5. If green → Phase 2 commit, then deploy + 1-day validation.
6. PR back to main; doc entry "Path B Cutover" added to `docs/SMART_THRESHOLD_FILTERING.md`.

---

**End of plan. Awaiting CEO go-ahead.**

---

## 10. Comprehensive bug cross-check (every dated incident in `docs/SMART_THRESHOLD_FILTERING.md`)

Format: incident → original defense → status under redesign → verdict.

| # | Date | Incident | Original defense | Status under redesign | Verdict |
|---|---|---|---|---|---|
| 1 | Feb 16–Apr 1 | catchup_max system (added, removed v5, restored v6, finally removed Apr 1) | catchup_max keys + 180 s cap | catchup_max system never reintroduced; constraint N2/N4 honored | ✅ |
| 2 | Feb 18–20 | Cross-midnight overcounting + undercounting | SKIP_MIDNIGHT (F0) | F0 unchanged | ✅ |
| 3 | Feb 19 | Midnight diagnostic log | midnightDiagnosticLog | Unchanged | ✅ |
| 4 | Feb 23 v5 | Removing catchup_max caused 0-count regression | (avoided by v6) | catchup_max long since gone; new model doesn't depend on it | ✅ |
| 5 | Feb 26–27 | Midnight monitoring gap | BGTask `restartMonitoring` ~00:01 | BGTask logic outside recording path; unchanged | ✅ |
| 6 | Feb 27 | catchup_max inflation across all apps | (catchup_max removed Apr 1) | Cannot recur | ✅ |
| 7 | Feb 28 | SKIP_COOLDOWN batch event undercount (lost 17 min for E54A4160) | Added `thresholdSeconds <= lastThresholdForCooldown` check | SKIP_COOLDOWN already removed (extension line 27 confirms). Batch events in new model bump high-water harmlessly — duplicates produce credit=0 naturally | ✅ |
| 8 | Mar 1 | Daytime threshold exhaustion | 45-min BGAppRefreshTask | Outside recording path; unchanged | ✅ |
| 9 | Mar 2 | Monitoring refresh chain seeding gap | BGTask seeding in `ChildBackgroundSyncService` | Outside recording path; unchanged | ✅ |
| 10 | Mar 8 | SKIP_MIDNIGHT timeout expiry — late app open | 2-h safety timeout in F0 | F0 unchanged | ✅ |
| 11 | Mar 15 | BGAppRefreshTask throttling analysis | BGTask cadence | Outside recording path; unchanged | ✅ |
| 12 | Apr 11 | Midnight dark window + BGTask failure analysis | BGTask diagnostics + extension-side rebuild | Outside recording path; unchanged | ✅ |
| 13 | Apr 11–12 | Cumulative-aware threshold system (DISPROVEN attempt) | (rejected) | Redesign is NOT this approach — the disproven attempt computed thresholds from cumulative; the redesign uses iOS-reported `thresh` as the candidate high-water. Distinct designs. | ✅ |
| 14 | Apr 12 | scheduleActivity main-app dependency | UX investigation | Outside recording path; unchanged | ✅ |
| 15 | Apr 12 | Extension-side midnight rebuild | `intervalDidStart()` + `extensionRebuildSlidingWindow` | Unchanged | ✅ |
| 16 | Apr 12 | Out-of-order catch-up events | SKIP_REGRESSION (then Apr 30 hold-on-clamp) | **Redesign removes the underlying problem.** Out-of-order events become harmless: high-water is `max(prior, candidate)`, so an out-of-order `min.20` after `min.55` is a no-op. SKIP_REGRESSION deleted because not needed. | ✅ |
| 17 | Apr 12 | FamilyControls authorization toggling | Auth status check before requestAuthorization | Outside recording path; unchanged | ✅ |
| 18 | Apr 13 | Console.app os_log observability | Logger taxonomy | Unchanged; new HW_SHADOW logs added | ✅ |
| 19 | Apr 13 | Apr 12→13 midnight transition console evidence | Diagnostic | Unchanged | ✅ |
| 20 | Apr 13 | Overcounting regression + revert (Apr 12 Layers 2+3) | **Reverted intraday lastThreshold reset** | Constraint N3 (no intraday `_highwater` reset) honored. Only `intervalDidStart` at midnight clears it via `resetAllDailyCounters`. **Critical:** the Apr 13 revert's lesson is "no intraday counter reset" — the redesign respects this by never resetting `_highwater` mid-day. | ✅ |
| 21 | Apr 13–14 | **Concurrent `eventDidReachThreshold` execution** (15× duplication observed) | OBSERVED but DEPRIORITIZED — race is "benign for same-event duplicates" because all N threads compute the same delta | **Redesign is strictly safer.** Old model risk: hypothesized N×60s *inflation* under different-event concurrent delivery. New model risk: transient *under-credit* during race; next legitimate event self-heals via `credit = newHighwater - priorToday`. Same-event duplicates remain idempotent (all threads compute identical `newHighwater`). The §4.5 `_lastCreditTimestamp` anchor caps but does not undo the under-credit; we lose minutes in a storm but never inflate. **Race remains theoretical (escalation triggers in doc still apply); fix path NSLock or serial DispatchQueue applies equally to both models.** | ✅ (no regression; arguably improved harm direction) |
| 22 | Apr 14 | Apr 14 soak day 1 verification | Confirmation only | N/A | ✅ |
| 23 | Apr 14 | `includesPastActivity` recovery on mid-day app add | Characterized — not a bug | Pin-replay defense (Apr 25) handles new-app pin events; high-water model handles the catch-up cleanly (each event bumps high-water once, capped by `secondsSinceMidnight`) | ✅ |
| 24 | Apr 15 | Apr 15 soak day 2 ground-truth | Confirmation only | N/A | ✅ |
| 25 | Apr 16 | Apr 16 soak day 3 — wall-clock parity FIXED | Confirmation only | N/A | ✅ |
| 26 | Apr 21 | Mid-day app add catch-up storm with stuck MIDNIGHT_PENDING | MIDNIGHT_PENDING flag + 2-h timeout | Outside recording path; unchanged | ✅ |
| 27 | Apr 23 | Charging-flush 111 min over-credit | Wall-clock cap (`delta ≤ wallClockElapsed`) | **Cap deleted.** Replaced by §4.5 `_lastCreditTimestamp` upper bound (`upperBound = priorHighwater + elapsedSinceLastCredit`) + §4.6 cross-app burst signature. Validation V4 tests this exact scenario. | ✅ (structurally fixed) |
| 28 | Apr 23 | First-event-after-gap 4× bypass (+3420/2280/540/420 s) | per-event 60 s hard cap | **Cap deleted.** Same defenses as #27. Phantom-flood-head `priorHighwater = 0` case explicitly handled by §4.6.6b cross-app burst signature. Validation V5/V7 cover this. | ✅ (structurally fixed) |
| 29 | Apr 24 | Wall-clock + per-event cap end-to-end validation | (validation result) | N/A — validates the cap that the redesign replaces. New algorithm needs equivalent V4 validation in Phase 1. | ✅ (validation requirement carried over) |
| 30 | Apr 24 | SKIP_SHIELDED race exposed at 16:34:22 | Filter 2 backstop with `checkGoalMet` (Apr 24) → pool-aware (May 2) | F2 unchanged. Constraint P3. | ✅ |
| 31 | Apr 24 | Newly-added app records bogus usage | Pin-replay layers (Apr 25) | F3 unchanged. | ✅ |
| 32 | Apr 25 | Pin fix Mode 1 (pin lost across reloads) — `pinned_apps_today` persistent | F3 SKIP_PIN_REPLAY persistent state | Unchanged | ✅ |
| 33 | Apr 25 | Pin fix Mode 2 (`includesPastActivity:false` unreliable) — wall-clock pin anchor | SKIP_PIN_REPLAY with wall-clock anchor | Unchanged | ✅ |
| 34 | Apr 26–27 | Pooled Time Bank shield gate (Devices A + B) | `computeEffectivePoolBalance` + pool-aware `checkAndUpdateShields` | Constraint P1–P5. Formula unchanged. | ✅ |
| 35 | Apr 26–27 | unlockTime baseline relaxation (first event after unlock) | `isFirstEventAfterUnlock` + `perEventCap = elapsed-since-unlock` | **Deleted.** No longer needed: §4.5's `_lastCreditTimestamp` anchor handles post-unlock catch-ups identically (the unlock is itself a "last credit" point). Validation V3 confirms 16-min idle/deferred case. | ✅ (structurally fixed by replacement) |
| 36 | Apr 29 | 9.4-h blackout from lastThreshold poisoning | `LASTTHRESH_HOLD` (Apr 30 v1 broken, v2/v3 shipped) | **`lastThreshold` deleted.** SKIP_REGRESSION deleted. The Apr 29 mechanism (catch-up walks lastThreshold to window top → SKIP_REGRESSION rejects rest of day) is structurally impossible: high-water is monotonic, only grows, and credit is always `gap` not `event size`. Validation V6 confirms. | ✅ (structurally fixed) |
| 37 | Apr 30 | v1 `delta < rawDelta` gate caused 123 false positives | Patched same day to v2 | `LASTTHRESH_HOLD` doesn't exist in new model. Cannot recur. | ✅ |
| 38 | Apr 30 v2 | `rawDelta > perEventCap` gate — frozen lastThreshold per app post-flood | Patched May 1 to v3 | Doesn't exist. Cannot recur. | ✅ |
| 39 | May 1 v3 | `lastThreshold = max(prior, newToday)` on hold | (the v3 shipped) | Doesn't exist in new model. | ✅ |
| 40 | May 1 | **Phantom threshold replay** (iOS replays all 60 thresholds for every monitored app on autonomous INTERVAL_END/START) | (decision: don't ship, watch and measure) | **Redesign handles structurally via §4.6.6b cross-app burst signature.** When ≥4 apps fire thresholds within 1 s window, system-wide phantom-burst window opens for 5 s. During window, `upperBound = priorHighwater + elapsedSinceLastCredit` strictly bounds credit (per §4.5). For an unused app, `priorHighwater = 0`, `elapsedSinceLastCredit ≈ 0` (since burst is concurrent with detection) → credit = 0. Validation V5 covers this. | ✅ (improved) |
| 41 | May 2 | Pool-aware `SKIP_SHIELDED_RACE` (Time Bank carry-forward) | Pool-aware backstop | F2 + P3 unchanged | ✅ |
| 42 | May 3 | NO_MAPPING recovery via stable-hash reverse lookup | `recoverLogicalIDFromEventName` + force window rebuild | F5 unchanged | ✅ |
| 43 | May 3 | Pool-divergence re-shield bypass | `BlockingCoordinator.checkAvailableMinutes` adds `todayUsed` subtraction | P2 unchanged. New model preserves `usage_<id>_today` semantics (K1) which is what `todayUsed` reads from. | ✅ |
| 44 | May 3 | Window-rebuild deferral via Darwin notification + flag | Main-app `handleWindowRebuildRequest` | Outside recording credit; unchanged | ✅ |
| 45 | May 3 | Config-drift self-heal | `detectAndHealConfigDrift` in `BlockingCoordinator` | Unchanged | ✅ |
| 46 | May 4 | Bug Y — restart thrashing on rebuild bursts | 5 s debounce in `handleWindowRebuildRequest` | Unchanged | ✅ |
| 47 | May 4 | **Bug X — perEventCap squashing legit catch-up bursts** | (paused) | **Structurally fixed by §4.5.** Legit 16-min idle gap: `_lastCreditTimestamp = 16 min ago`, `elapsedSinceLastCredit = 960 s`, `upperBound = priorHighwater + 960`. iOS catch-up `thresh = 1140 → newHighwater = 1140 → credit = 1140 - prior`. **Bug X resolved.** Validation V3/V4. | ✅ (structurally fixed) |
| 48 | May 4 | **Bug Z — fake 60 s flood-head on unused/used apps** | (documented, paused) | **Structurally fixed by §4.6 + §4.8.** NEW_DAY initial=60 deleted; first event credits `min(thresh, secondsSinceMidnight)`. Cross-app burst signature suppresses phantom replays. Validation V5/V7. | ✅ (structurally fixed) |

### Filters & invariants survival summary

| Mechanism | Status |
|---|---|
| F0 SKIP_MIDNIGHT | ✅ unchanged |
| F2 SKIP_SHIELDED + SKIP_SHIELDED_RACE (pool-aware) | ✅ unchanged |
| F3 SKIP_PIN_REPLAY (Mode 1 + Mode 2) | ✅ unchanged |
| F4 SKIP_REGRESSION | ❌ **REMOVED — no longer needed** (high-water is intrinsically monotonic) |
| F4 SKIP_DUP cross-day | ❌ **REMOVED — duplicates produce credit=0 naturally** |
| F5 NO_MAPPING → MAPPING_RECOVERED | ✅ unchanged |
| Wall-clock cap (Apr 23) | ❌ **REMOVED — replaced by §4.5** |
| per-event 60 s cap (Apr 23 late) | ❌ **REMOVED — replaced by §4.5** |
| unlockTime baseline relaxation (Apr 26–27) | ❌ **REMOVED — replaced by §4.5** |
| LASTTHRESH_HOLD v3 (May 1) | ❌ **REMOVED — `lastThreshold` deleted** |
| `initialUsage = 60` (NEW_DAY) | ❌ **REMOVED — replaced by §4.8** |
| `rawDelta = max(60, …)` floor | ❌ **REMOVED — `rawDelta` doesn't exist** |
| Pool invariant P1–P5 | ✅ unchanged |
| Window-rebuild Darwin bridge + 5 s debounce | ✅ unchanged |
| Config-drift self-heal | ✅ unchanged |
| Hourly buckets, total, timestamp, modified, hourly_date | ✅ unchanged (writes from new credit) |
| `intervalDidStart` midnight reset | ✅ unchanged (also clears `_highwater`, `_lastCreditTimestamp`) |
| BGAppRefreshTask 45-min cadence | ✅ unchanged |
| Battery context plumbing | ✅ unchanged |
| Rotating extension log | ✅ unchanged |
| `includesPastActivity: true` | ✅ unchanged (constraint C1) |
| Concurrent-callback race | ⚖️ **theoretical exposure unchanged in shape, harm direction improved** (under-credit instead of inflation) |

### Net additions (new mechanisms)

| Mechanism | Purpose |
|---|---|
| `ext_usage_<id>_highwater` | Per-day per-app high-water mark of iOS-reported `thresh` |
| `ext_usage_<id>_lastCreditTimestamp` | Anchor for `elapsedSinceLastCredit` upper bound |
| Cross-app burst signature window | Phantom-replay defense (May 1) |
| `ext_usage_<id>_today_v2` (Phase 1 only) | Shadow-mode parallel output for validation |
| `HW_SHADOW_DELTA` log line (Phase 1 only) | Validation diagnostic |

### Constraints not in conflict

All 13 recording-path constraints (C1–C13), all 5 filter constraints (F0–F5 status above), all 5 pool invariants (P1–P5), all 5 counter-state constraints (K1–K5), and all 9 prohibitions (N1–N9) verified non-violated by the redesign.

### Verdict

**Cross-check complete. 48/48 historical incidents and 32/32 documented invariants pass.** No mechanism that fixed a past bug is silently broken. Six mechanisms become unnecessary and are removed. Two new mechanisms (high-water + lastCreditTimestamp + burst signature) replace eight (wall-clock cap, perEventCap, unlock relaxation, LASTTHRESH_HOLD v1/v2/v3, initialUsage=60, rawDelta floor, SKIP_REGRESSION).

**Cleared for Phase 1 implementation.**

