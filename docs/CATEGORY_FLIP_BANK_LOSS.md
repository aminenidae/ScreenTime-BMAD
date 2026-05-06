# Category-Flip Bank Loss

**Status:** OPEN — root-caused 2026-05-05, fix not yet shipped.
**Severity:** HIGH — silent loss of accumulated Time Bank credit when a parent re-categorizes an app.
**Scope:** orthogonal to threshold filtering / usage counting. Not covered by `docs/SMART_THRESHOLD_FILTERING.md`.

---

## Symptom

Flipping an app's category in the parent app (learning ↔ reward) silently erases that app's historical contribution to the Time Bank. Worse: a learning→reward flip *double-debits* the bank, because the same historical seconds get removed from "earned" AND added to "used."

User-visible: pool drops in seconds from a healthy multi-hour balance to near-zero, with no notification, error, or audit trail.

---

## Real-world incident — Amine's device, 2026-05-04

User flipped **YouTube (logical ID `C6DA269B`)** from a learning app to a reward app sometime late May 4. YouTube was the most-used learning app on the device (~28 hours of accumulated `dailyHistory`).

**Log evidence** (`/Users/ameen/Downloads/ext-log-2026-05-04 2.log`):

| Timestamp | Pool value | Trigger |
|---|---|---|
| 22:05:23.020 | **1363 min** | SHIELD_CHECK |
| 22:05:26.737 | 1363 min | SHIELD_CHECK (last sample with healthy bank) |
| 22:05:26 | — | `TRACKED_APP_IDS_SET` + `SLIDING_WINDOW × 8` (main-app `scheduleActivity()` ran) |
| 22:05:26.836 | **54 min** | SHIELD_CHECK (bank wiped, 99 ms after `scheduleActivity`) |

**Net loss: 1,309 minutes ≈ 21 h 49 m of bank credit, in 99 milliseconds.**

The pool stayed at ~54 min for the rest of May 4 and into May 5 (midnight rehydrate read pool=0 → main-app sync raised it to 57 min, where today's earned-vs-used produces the residual baseline).

The trigger that surfaced the bug was **rapid `MONITORING_RESTART → scheduleActivity()` cycles** caused by the May 4 catch-up storm (LASTTHRESH_HOLD on YouTube `min.91/102/113/122` at 22:05:23). Each restart called `syncBankHistoricalBaselineToExtension()`, but only the first such call AFTER the category flip wrote the wrong value. Subsequent calls re-confirmed the wrong value because the underlying logic was deterministic.

The category flip itself happened earlier; the storm only made the wrong write visible quickly.

---

## Root cause

`ScreenTimeService.syncBankHistoricalBaselineToExtension()` (`ScreenTimeService.swift:4288`) builds `learningIDs` and `rewardIDs` from `categoryAssignments` — which holds the **current** category for each app token. It then calls `UsagePersistence.getHistoricalRemainingMinutes(learningIDs:, rewardIDs:, ratioForDay:)` (`UsagePersistence.swift:285`), which:

1. For each `logicalID` in `learningIDs`: iterate `cachedApps[logicalID].dailyHistory`, multiply each day's seconds by `ratioForDay(logicalID, dayKey)`, accumulate into `totalEarnedSeconds`.
2. For each `logicalID` in `rewardIDs`: iterate `cachedApps[logicalID].dailyHistory`, accumulate raw seconds into `totalUsedSeconds`.
3. Return `(totalEarnedSeconds − totalUsedSeconds) / 60`.

**`dailyHistory` records `(date, seconds)` per app but does not record the category the app had on that day.** When a parent flips an app's category, the iteration logic retroactively rewrites the meaning of every historical entry:

- **Before flip (YouTube = learning):** all 28 hours of `dailyHistory` count as `totalEarned × ratio`.
- **After flip (YouTube = reward):** same 28 hours of `dailyHistory` count as `totalUsed`.

Net change to `historicalRemaining` for this app:
```
ΔhistoricalRemaining = −(historicalSeconds × ratio) − historicalSeconds
                     = −historicalSeconds × (ratio + 1)
```

For YouTube with ~28 h history at ratio = 1.0: `Δ = −2 × 28 h = −56 h`. The bank had absorbed +28 h before the flip; the flip subtracted 28 h *and* re-added 28 h as "used" → net −56 h reflected in the bank.

The actual observed delta (1363 → 54 = −1309 min ≈ −21.8 h) is consistent with a slightly lower YouTube history (~10–14 h of pre-flip learning) at the active ratio.

---

## Why this is structurally invisible

- **`dailyHistory` is on disk and intact.** No data deletion happened. The category flip just changed how the aggregator interprets the existing rows.
- **Reverting the flip would restore the bank.** Flipping YouTube back to learning would re-include its history in `totalEarned` and exclude it from `totalUsed`. The bank would jump back up by ~21–28 h on the next `syncBankHistoricalBaselineToExtension()` call.
- **No audit trail.** Neither the main app nor the extension logs a "−1309 min" event. The only forensic trace is the SHIELD_CHECK pool readings before and after the flip.
- **No user warning.** The category-change UI does not surface the bank impact before committing.

---

## Predates Phase 1 redesign

This bug has nothing to do with the high-water-mark redesign currently being shadow-validated on `redesign/highwater-mark-credit-model`. Phase 1 only writes parallel `_v2` keys for *today's* recording — it never touches `bank_historical_remaining_minutes`, `categoryAssignments`, or `dailyHistory`. The bug has been latent since the bank-credit feature shipped (see commit history of `getHistoricalRemainingMinutes` and `syncBankHistoricalBaselineToExtension`).

---

## Recovery for the current incident

YouTube's ~28 h of `dailyHistory` is still on disk. Two recovery paths:

1. **Flip YouTube back to learning** (safest, no data manipulation): on the next `scheduleActivity()` or `syncBankHistoricalBaselineToExtension()` call, the bank balance restores. Confirmed by reading `cachedApps` flow.
2. **Manual parent-grant** (if user wants YouTube to stay reward): no UI surface today.

User direction pending.

---

## Fix options

### Option 1 — Bank baseline snapshot on category change (RECOMMENDED)

When a parent flips an app's category, capture the current `historicalRemaining` value and persist it as a frozen baseline. The aggregator becomes:

```
historicalRemaining = bank_baseline_at_last_flip + Δ since flip
```

Where `Δ since flip` is computed only from `dailyHistory` rows whose date is ≥ the flip date.

**Pros:** simplest. Mirrors the schedule-versioning Phase 2 pattern (`effectiveFromDay` cutoff). Matches user's mental model of "earned time should be permanent."
**Cons:** future flips compound — each flip locks in a new baseline. Auditing pre-baseline history becomes opaque.

### Option 2 — Versioned category per day

Same pattern as `AppScheduleVersion` but for category. Each `DailyUsageSummary` records the category active on that day. `getHistoricalRemainingMinutes` iterates per-day, summing earned/used based on the day's recorded category.

**Pros:** architecturally correct. Future flips don't disturb history. Preserves audit trail forever.
**Cons:** larger refactor — touches `DailyUsageSummary` model, persistence schema, CloudKit sync, and parent dashboard aggregation.

### Option 3 — Block category flips for apps with bank history (TEMPORARY GUARD)

UI confirmation dialog before saving a category change for any app whose historical contribution to the bank is non-zero. Doesn't fix the underlying bug; prevents accidental loss while a real fix is designed.

**Pros:** ships in an afternoon. No persistence changes. Kills the silent-loss vector.
**Cons:** doesn't recover already-lost balances. Doesn't help if a parent confirms anyway.

---

## Pending decisions

1. Recovery path for Amine's bank: flip YouTube back to learning, or accept the −21.8 h loss?
2. Which fix to implement: 1 (snapshot), 2 (versioned category), or 3 (UI guard)?
3. Should existing parent-side category change flows surface a warning even before fix #3 ships?

Awaiting user direction before implementing.

---

## Files referenced

- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift:4288` — `syncBankHistoricalBaselineToExtension()`
- `ScreenTimeRewardsProject/ScreenTimeRewards/Shared/UsagePersistence.swift:285` — `getHistoricalRemainingMinutes(learningIDs:, rewardIDs:, ratioForDay:)`
- `ScreenTimeRewardsProject/ScreenTimeRewards/Models/AppScheduleConfig.swift:660` — `AppScheduleVersion.ratio`
- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift:1725` — extension reads `bank_historical_remaining_minutes` for pool computation

## Log references

- `/Users/ameen/Downloads/ext-log-2026-05-04 2.log` — collapse at 22:05:26 (lines 13778–13805 in the file)
- `/Users/ameen/Downloads/ext-log-2026-05-03 2.log` — healthy baseline (pool=1428 at midnight, peaked at 1711)
- `/Users/ameen/Downloads/ext-log-2026-05-05.log` — post-collapse residual (pool=57 at midnight rehydrate, climbed to 145 from today's earnings)
