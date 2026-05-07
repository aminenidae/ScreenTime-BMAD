# Unified Usage Counter — Refactor Plan

**Goal (user-stated, 2026-05-07):** "the shield, the UI, CK, and everything else read from the same source. There can only be one truth."

## Current divergence (the mess we're fixing)

"How many minutes has the kid used YouTube today?" is currently answered by four loosely-coupled stores:

1. `usage_<id>_today` — written by `DeviceActivityMonitorExtension.setUsageToThreshold`, read by extension's shield logic. Canonical write target inside the extension.
2. `ext_usage_<id>_today` — also written by `setUsageToThreshold` to the same value, read by `ScreenTimeService.readExtensionUsageData` to sync into `UsagePersistence`. Functionally a duplicate.
3. `ios_claimed_today_<id>` — added 2026-05-07 (commit `204ae82`) as a defensive floor for shield decisions. Tracks the highest `thresholdSeconds` iOS has ever fired. Read by both extension's pool calc and main-app `BlockingCoordinator`.
4. `UsagePersistence.PersistedApp.todaySeconds` — fed from `ext_usage_<id>_today` on main-app foreground via `readExtensionUsageData`. Persisted to `persistedApps_v3` JSON. Read by dashboard, BlockingCoordinator, CloudKit upload.

"What's in the bank?" is answered by three independent implementations:

A. `AppUsageViewModel.cumulativeAvailableMinutes` — dashboard "Time Bank: N MIN AVAILABLE" copy. Uses `totalUsedMinutes` from `rewardSnapshots` + `getHistoricalRemainingMinutes` (WIP baseline+delta).
B. `BlockingCoordinator.checkAvailableMinutes` — shield decision in main app. Same `getHistoricalRemainingMinutes` plus the Option-4 `max(credited, claimed)` floor.
C. Extension's `computeEffectivePoolBalance` — shield decision in extension. Reads `bank_historical_remaining_minutes` (written by main app once per foreground), plus its own todayUsed loop with the Option-4 `max` floor.

These three share a docstring claim of "byte-equivalent" but the inputs they consume differ in practice — which is exactly why the May 6+ shield-oscillation bug surfaces.

## Target architecture

**Today's per-app usage:** one App Group key per app, `usage_<id>_today`. The extension is the sole writer. Every consumer (UsagePersistence, BlockingCoordinator, dashboard, CloudKit, Extension shield logic) reads from this key, directly or via `UsagePersistence.todaySeconds(for: logicalID)` which becomes a thin pass-through.

**Bank balance:** one shared function `BankCalculator.currentBank(...)` in the Shared target. Takes raw inputs (learning IDs, reward IDs, todaySeconds map, dailyHistory map, ratio resolver). Returns one Int. All three current implementations (`cumulativeAvailableMinutes`, `checkAvailableMinutes`, `computeEffectivePoolBalance`) reduce to: gather inputs, call `BankCalculator.currentBank`, use the result.

**No parallel counters.** `ext_usage_<id>_today` write removed. `ios_claimed_today_<id>` removed. `PersistedApp.todaySeconds` becomes derived (read live from `usage_<id>_today` on every access; cached field removed from the persisted struct or kept as a transient mirror that's always refreshed before read).

## Step plan (each step independently shippable)

## Status

| Step | Branch | Commit | Status |
|---|---|---|---|
| 1 — Revert `ios_claimed_today_<id>` | `refactor/unified-usage-counter` | `0eea57a` | SHIPPED |
| 2 — Single `BankCalculator` shared function | `refactor/unified-usage-counter` | (this commit) | SHIPPED |
| 3 — Drop `ext_usage_<id>_today` dual-write | `refactor/unified-usage-counter` | (this commit) | SHIPPED |
| 4 — Make `getHistoricalRemainingMinutes` deterministic | TBD | — | Pending (touches WIP) |
| 5 — `PersistedApp.todaySeconds` as live read | TBD | — | Optional |

### Step 1 — Revert Option 4 (`ios_claimed_today_<id>`)

**Branch:** `refactor/unified-usage-counter` off `fix/scrub-stale-linked-learning-refs`.

**Why first:** this is purely subtractive code. No new abstractions, no behavior change beyond removing the iOS-claim floor. Easiest to review and roll back if needed.

**Files:**
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — remove the write in `setUsageToThreshold`, the read+max in `computeEffectivePoolBalance`, the read+max in `checkAndBlockIfRewardTimeExhausted` Check 1, and the clear in `resetAllDailyCounters`.
- `ScreenTimeRewards/Services/BlockingCoordinator.swift` — remove the read+max in `checkAvailableMinutes`, and the read+max in `checkDailyLimit`.
- `docs/SMART_THRESHOLD_FILTERING.md` — note that the May 7 entry is reverted as part of the unification refactor.

**Trade-off accepted:** the May 6 LASTTHRESH_HOLD storm scenario returns. During a stale catch-up burst, the shield will not auto-apply until a clean threshold event arrives. Re-addressing this happens later, in a way that fits the unified architecture (e.g., make `usage_<id>_today` advance more aggressively under specific conditions, with a single cap policy).

**Validation:** kid plays, pool drains via the credited counter alone (slower under storms, but consistent with what the dashboard shows). Once pool truly hits 0, shield applies. No oscillation between dashboard view and shield decision.

### Step 2 — Single `BankCalculator` function (Shared target)

**Branch:** off Step 1's branch.

**Files:**
- New: `ScreenTimeRewards/Shared/BankCalculator.swift` — pure function `currentBank(learningIDs, rewardIDs, todaySecondsByID, dailyHistoryByID, ratioForDay)` returning Int. No state, no UserDefaults access.
- `AppUsageViewModel.cumulativeAvailableMinutes` — gather inputs from `learningSnapshots` / `rewardSnapshots`, call `BankCalculator.currentBank`.
- `BlockingCoordinator.checkAvailableMinutes` — same. Keep `hasNoTimeAvailable` semantic.
- `DeviceActivityMonitorExtension.computeEffectivePoolBalance` — same. Reads `usage_<id>_today` per goal config, builds inputs, calls `BankCalculator.currentBank`.

**Result:** identical algorithm everywhere. Drift impossible because there's only one implementation.

**Validation:** dashboard "Time Bank: N" matches BlockingCoordinator's pool matches extension's POOL_EMPTY_BLOCK trigger. Always. Even after foregrounds, midnights, recategorizations.

### Step 3 — Eliminate `ext_usage_<id>_today` dual-write

**Branch:** off Step 2's branch.

**Files:**
- Extension: drop the parallel `ext_usage_<id>_today` write in `setUsageToThreshold` (NEW_DAY and same-day branches).
- Main app `readExtensionUsageData`: switch from reading `ext_usage_<id>_today` to reading `usage_<id>_today`.
- All other `ext_usage_<id>_*` keys (date, hour, timestamp, total) stay — they hold semantically distinct values that the canonical `usage_<id>_today` doesn't.
- One-shot cleanup migration: clear `ext_usage_<id>_today` keys after first launch on the new code, since they're no longer written.

**Risk:** sync between extension and main app today flows through `ext_usage_<id>_today`. Switching the read source mid-day on a kid's device could cause a one-time sync glitch. Mitigation: ship after Step 2 has soaked, gate behind a one-shot migration key.

**Validation:** extension and main app see the same `usage_<id>_today` value at all times. Dashboard refresh after foreground reads the canonical key.

### Step 4 — Make `getHistoricalRemainingMinutes` deterministic

**Branch:** off Step 3's branch. Touches the user's WIP baseline+delta logic.

**Goal:** same inputs always produce the same output, regardless of when called.

**Likely fix:**
- Today's row of `dailyHistory` (if present) gets archived only at midnight rollover — never mid-day. Currently the archive logic in `readExtensionUsageData` runs on every foreground; if it ever runs mid-day for any reason, today's usage gets double-counted (in `dailyHistory` AND `todayRemaining`).
- The baseline+delta WIP code (`UsagePersistence.swift` WIP) needs to exclude today's row from `delta` so today flows through `todayRemaining` only. Ensure `summary.date < startOfToday` filter on the delta loops.

**Coordination:** this touches the user's category-flip bank-loss WIP. Coordinate before merging.

### Step 5 — Make `PersistedApp.todaySeconds` a live read (optional)

**Branch:** off Step 4's branch.

**Goal:** remove the cached field; expose `UsagePersistence.todaySeconds(for: logicalID) -> Int` that reads `usage_<id>_today` from App Group every time. No more "stale snapshot" between foregrounds.

**Optional:** if the field is hot-path enough that live reads tank performance, keep the cache but auto-refresh it on every access (or on every Darwin notification from the extension). Profile first.

## Out of scope (this refactor)

- CloudKit upload changes — already reads `UsagePersistence.todaySeconds` and `ext_usage_<id>_*` for legacy reasons. Steps 1–4 propagate the unified counter to CloudKit naturally; no extra work.
- Streak / daily limit / downtime logic — orthogonal to the bank calc, no changes needed.
- Parent-device dashboard — reads via CloudKit, gets the same unified counter.
- ASO / metadata / pairing — unrelated.

## Memory notes

- Pool-aware shield invariant memory (`project_pool_aware_shield_invariant.md`) needs to be updated after each step to reflect the current unified architecture.
- Save the architectural decision so future sessions don't re-introduce parallel counters.
