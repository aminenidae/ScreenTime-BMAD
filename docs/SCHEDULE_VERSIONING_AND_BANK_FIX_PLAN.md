# Schedule Versioning, Parent Bank Fix, and Shield Stale-Data Plan

**Date drafted:** 2026-05-02
**Branch suggestion:** `feature/schedule-versioning-and-bank-fixes`
**Status:** Draft — pending approval

---

## Context

A 2026-05-02 device session surfaced three connected problems:

1. **Retroactive ratio rewriting.** When a parent edits the reward ratio (`rewardMinutesEarned / ratioLearningMinutes`), the new ratio is applied to *all* historical learning seconds, not just future earning. A decrease silently wipes the kid's accumulated bank; an increase silently inflates it. Math (validated against the device today): cumulative L = 208 min, cumulative R = 1081 min — at ratio 1:4 the bank reads 0 (clamped); at 1:6 it reads 167; at 1:8 it reads 583. The kid would have to re-earn 63 min of learning at 1:4 just to climb back to zero.
2. **Parent-side bank is wrong by design.** `ParentRemoteViewModel.fallbackEarnedMinutes` (`ParentRemoteViewModel.swift:669-716`) ignores ratios entirely — sums learning seconds 1:1 — so the parent's view of the kid's bank diverges from the child's view whenever the ratio is anything other than 1:1.
3. **Shield message reports stale "278 min used."** While today's reward usage is 0 across all 14 reward apps, the reward shield reads `usage_<rewardID>_today = 16,680s` for one specific reward app. Root cause traced: `resetAllDailyCounters` only iterates `tracked_app_ids`, which `ScreenTimeService` builds from `monitoredEvents` — the actively-monitored set, which excludes reward apps. A reward app whose logical ID falls out of the monitored set carries its `usage_<id>_today` past midnight indefinitely.

This plan delivers the three fixes in two phases. Phase 1 is shippable as a single PR and stops the bleeding (parent-side correctness + UX guardrail + the shield stale-data fix). Phase 2 is the structural fix (versioned schedule) that closes the retroactivity hole permanently.

---

## Phase 1 — Ship now (single PR)

Goal: stop the immediate bleeding without a CloudKit schema migration.

### 1A. Parent fallback bank — apply ratios

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift:669-716`

Today's `fallbackEarnedMinutes` does:

```swift
let usageMinutes = totalSeconds / 60   // BUG: 1:1 implicit
if usageMinutes >= lowestThreshold {
    totalEarnedMinutes += usageMinutes // BUG: no ratio applied
}
```

Fix: build a `ratiosPerLearningApp: [String: Double]` map from `childRewardAppsFullConfig` (each `FullAppConfigDTO.scheduleConfig` already carries `rewardMinutesEarned` and `ratioLearningMinutes`). For each linked-learning relationship, compute `Double(rewardMinutesEarned) / Double(max(1, ratioLearningMinutes))` and pick a deterministic ratio per learning app (first-found, mirroring `AppUsageViewModel.totalEarnedMinutes`). Multiply once before accumulation.

**Caller chain to verify:** `ParentRemoteViewModel.fallbackAvailableMinutes` (line ~721) → `RemoteDashboardDataAdapter.earnedMinutes` (line 112). No further plumbing needed; both already read from `childRewardAppsFullConfig`.

**No DTO changes required.** `FullAppConfigDTO` already carries the ratio fields.

### 1B. Schedule-edit confirmation dialog

**Files:**
- `ScreenTimeRewardsProject/ScreenTimeRewards/Views/ParentRemote/ParentAppEditSheet.swift:172-173` (remote-parent save button)
- `ScreenTimeRewardsProject/ScreenTimeRewards/Views/AppConfig/AppConfigurationSheet.swift` (local-parent save button)

Both currently call `onSave(localConfig)` / `scheduleService.saveSchedule(savedConfig)` with no preview. Wrap the save action in a comparison:

1. Compute the kid's current bank (`viewModel.cumulativeAvailableMinutes` for local; child's most-recent synced snapshot for remote).
2. Re-compute the same bank under the proposed schedule using the same formula (`getHistoricalRemainingMinutes` with the new ratio map + today's earned/used).
3. If the new bank < current bank, show:

   > *"Saving these changes will reduce {child}'s available time from **X min** to **Y min**. Past learning will be re-priced at the new ratio. Continue?"*

   Buttons: **Cancel** (default), **Save Anyway**.

4. If the new bank ≥ current bank, save silently (no dialog) — increases don't need a guardrail; this also avoids friction for the common case (parent is being generous).

**Reuse:** `UsagePersistence.getHistoricalRemainingMinutes(...)` (`UsagePersistence.swift:270-301`) is the single source of truth for the bank baseline; pass it the proposed ratio map.

This is *not* the structural fix — it just makes the side effect visible. Phase 2 makes the dialog unnecessary.

### 1C. Shield stale-data — fix `tracked_app_ids` coverage

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift:2371-2376`

Today, `tracked_app_ids` is set to `Array(appTemplates.keys)`, where `appTemplates` is built only from `monitoredEvents` (line 2335-2341). Reward apps that don't currently have monitored thresholds are excluded, so `resetAllDailyCounters` (`DeviceActivityMonitorExtension.swift:1019-1064`) skips them at midnight.

Fix: when writing `tracked_app_ids`, take the union of:
- `appTemplates.keys` (currently-monitored apps)
- All reward-app logical IDs from `AppScheduleService.allSchedules` (every app the kid has ever been configured to receive as a reward)
- All learning-app logical IDs from those same schedules

This guarantees that any app the kid has ever had assigned a category sees its `usage_<id>_today` cleared at midnight. Memory cost is trivial (logical IDs are ~36 bytes each; 30 apps = ~1KB).

### 1D. One-shot stale-cleanup on next launch

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift` (new function, called from `init` after `loadSchedules()`)

Existing devices already carry stale `usage_<id>_today` values. Add a one-shot migration gated on `UserDefaults` key `stale_usage_cleanup_v1`:

```swift
private func performStaleUsageCleanupIfNeeded() {
    let key = "stale_usage_cleanup_v1"
    guard sharedDefaults?.bool(forKey: key) != true else { return }
    let today = Self.dayDateFormatter.string(from: Date())
    for logicalID in allKnownLogicalIDs {
        let dateKey = "ext_usage_\(logicalID)_date"
        let storedDate = sharedDefaults?.string(forKey: dateKey)
        if storedDate != today {
            sharedDefaults?.set(0, forKey: "usage_\(logicalID)_today")
            sharedDefaults?.set(0, forKey: "ext_usage_\(logicalID)_today")
        }
    }
    sharedDefaults?.set(true, forKey: key)
}
```

Reuse the same union-of-logical-IDs source as 1C.

### 1E. Shield copy improvement (optional, low-risk)

**File:** `ScreenTimeRewardsProject/ShieldConfigurationExtension/ShieldConfigurationExtension.swift:335-340`

Current copy: *"You used 278 minutes of reward time. Complete more learning to earn more!"*

After 1C+1D, this number will be accurate. Consider tightening copy to clarify scope: *"You've used 278 min of today's reward time."* (Adds "today's" so the user understands the framing.) No data-source change.

---

## Phase 2 — Versioned schedule (next PR)

Goal: structurally eliminate retroactivity. After this lands, Phase 1B's dialog becomes a no-op (proposed bank ≡ current bank) because past days are pinned to their version.

### 2A. Data model — `AppScheduleVersion`

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Models/AppScheduleConfig.swift`

Add a sibling struct:

```swift
struct AppScheduleVersion: Codable, Equatable {
    let logicalID: String              // matches AppScheduleConfiguration.id
    let effectiveFromDay: String       // "yyyy-MM-dd"
    let ratioLearningMinutes: Int
    let rewardMinutesEarned: Int
    let linkedLearningApps: [LinkedLearningApp]   // captures per-link minutesRequired
    let dailyLimits: DailyLimits
    let dailyTimeWindows: DailyTimeWindows
    let allowedTimeWindow: AllowedTimeWindow
    let unlockMode: UnlockMode
    let createdAt: Date                // audit only
}
```

`AppScheduleConfiguration` keeps its current shape (it represents "current settings"). `AppScheduleVersion[]` is append-only history.

### 2B. Storage

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Services/AppScheduleService.swift`

- New App Group key: `AppScheduleVersions` (JSON-encoded `[AppScheduleVersion]`).
- New API:
  - `saveScheduleWithVersion(_ config: AppScheduleConfiguration, effectiveFromDay: String) throws` — writes both current schedule and appends to versions. `effectiveFromDay = tomorrow` by default.
  - `versionActive(logicalID: String, on day: String) -> AppScheduleVersion?` — binary search by `effectiveFromDay`; returns the most recent version `≤ day`.
  - `pruneVersionsOlderThan(_ cutoffDay: String)` — drop versions older than the oldest `dailyHistory` row (30-day window).

**Migration (one-shot, key `schedule_versioning_v1`):** for every existing `AppScheduleConfiguration`, write a single seed `AppScheduleVersion` with `effectiveFromDay = "1970-01-01"` carrying its current values. Result: kids see no bank jump on upgrade.

### 2C. Bank pipeline — read per-day version

**Files & changes:**

- `ScreenTimeRewardsProject/ScreenTimeRewards/Shared/UsagePersistence.swift:270-301` — `getHistoricalRemainingMinutes` accepts a closure `ratioOnDay: (LogicalAppID, String) -> Double` instead of the current static `learningRatios: [String: Double]`. Caller wires it to `AppScheduleService.versionActive(...).ratio`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift:156-198, 210-222` — `totalEarnedMinutes` uses the *current-day* version (today still uses today's settings); `cumulativeAvailableMinutes` walks history with `versionActive(on: row.date)`.
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift:4138-4175` — `syncBankHistoricalBaselineToExtension` uses the version-aware path; the resulting `bank_historical_remaining_minutes` is identical in shape to today, so the extension (`DeviceActivityMonitorExtension.swift:1485-1528`) needs **no changes**.
- `ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift:669-716` — same versioned lookup, plus the Phase 1A ratio fix becomes derived ("first-found ratio" replaced by "ratio active on `record.date`").

### 2D. CloudKit sync of versions

**File:** `ScreenTimeRewardsProject/ScreenTimeRewards/Services/CloudKitSyncService.swift`

- Add field `CD_scheduleVersionsJSON` (String, JSON-encoded `[AppScheduleVersion]`) to the existing `CD_AppConfiguration` record.
- Parent decodes it into `FullAppConfigDTO.scheduleVersions: [AppScheduleVersion]?` (optional, default `[]`).
- Parent's bank computation uses `versionActive(on:)` against `scheduleVersions` for each child usage row.

This is additive to an existing record type — old clients ignore the new field, new clients tolerate `nil` (fall back to current schedule applied to all days, matching pre-versioning behavior).

### 2E. Effectivity policy: today-if-no-learning, otherwise midnight-tomorrow

`saveScheduleWithVersion` decides `effectiveFromDay` at call time:

```swift
let todayLearningSeconds = sum(
    usage_<learningID>_today for learningID in config.linkedLearningApps
)
let effectiveFromDay = (todayLearningSeconds == 0) ? today : tomorrow
```

Rationale: the "tomorrow" rule exists to prevent retroactively re-pricing minutes the kid has already earned today. If today's learning is still 0, there's nothing to re-price — apply the new ratio immediately, which matches the parent's mental model ("I changed it, kid starts at the new rate now"). Parent who edits at 8 AM before the kid wakes up doesn't suffer an artificial day-long lag.

- The current `AppScheduleConfiguration` is updated *immediately* either way so the UI reflects the parent's intent.
- Remote-parent flow reads `todayLearningSeconds` from the most recent synced `DailyUsageHistoryDTO`. If the sync is stale (no row for today), default to `tomorrow` (safe fallback — never silently re-prices).
- Edge case: parent edits at 11 PM with `todayLearningSeconds == 0`. Effective-today is still correct; tomorrow inherits the same version via `versionActive(on:)`. No math difference.
- Edge case: if no version exists with `effectiveFromDay ≤ today`, fall back to the current `AppScheduleConfiguration` values (covers the upgrade window before the seed migration runs).

### 2F. Phase 1B dialog becomes informational

After 2C lands, the proposed-vs-current bank delta will normally be zero (history is pinned). The dialog from 1B can stay as a "starting tomorrow" preview ("Tomorrow's earning rate: 1 learning min → 4 reward min"). No removal needed.

---

## Out of scope (separate tickets, not in this PR)

- **Streak retroactivity.** `StreakService` is already write-once-immutable, so threshold changes don't retroactively flip past days. Documented in code; no fix needed here.
- **Schedule audit UI for parent.** "View history of changes" is a future feature once `AppScheduleVersion[]` exists.
- **Per-link versioning.** Versioning the whole `AppScheduleConfiguration` per change is sufficient; per-link granularity is unnecessary complexity.
- **`includesPastActivity` / threshold-flood handling.** Separate workstream.

---

## Decisions baked into this plan

1. **Edits apply today if `todayLearningSeconds == 0`, otherwise tomorrow.** No retroactive re-pricing, no artificial lag when nothing has been earned yet. Eliminates row-splitting math and partial-day ambiguity.
2. **Migration backfills the initial version with current ratio.** No kid sees a sudden bank jump on upgrade. Lossy for *historical* ratio truth (we don't know what the ratio was 20 days ago), but the alternative (assuming 1:1) would visibly break working installs.
3. **Per-schedule versioning, not per-link.** One version row per save, not one per linked-learning-app. Vastly simpler; no observed need for per-link granularity.
4. **Decreases require confirmation; increases don't.** Asymmetric on purpose — parents won't object to silent generosity, but a silent decrease is the bug we're fixing.
5. **Shield stale-data fix is part of Phase 1, not a separate PR.** It shares migration infrastructure (one-shot key, `allKnownLogicalIDs` enumerator) with the bank-baseline fix; splitting them duplicates work.

---

## Critical files

| Concern | File | Lines |
|---|---|---|
| Parent fallback bug | `ParentRemoteViewModel.swift` | 669-716 |
| Local schedule edit save | `AppConfigurationSheet.swift` | save action |
| Remote schedule edit save | `ParentAppEditSheet.swift` | 172-173 |
| Shield read | `ShieldConfigurationExtension.swift` | 335-340, 212-219 |
| Shield write | `DeviceActivityMonitorExtension.swift` | 1418-1423, 1571-1581 |
| Midnight reset | `DeviceActivityMonitorExtension.swift` | 1019-1064 |
| `tracked_app_ids` build site | `ScreenTimeService.swift` | 2371-2376 |
| Bank historical baseline write | `ScreenTimeService.swift` | 4138-4175 |
| Bank historical baseline read | `DeviceActivityMonitorExtension.swift` | 1485-1528 |
| `getHistoricalRemainingMinutes` | `UsagePersistence.swift` | 270-301 |
| `cumulativeAvailableMinutes` | `AppUsageViewModel.swift` | 210-222 |
| `totalEarnedMinutes` | `AppUsageViewModel.swift` | 156-198 |
| Schedule struct | `AppScheduleConfig.swift` | 457-626 |
| Schedule service | `AppScheduleService.swift` | 30-145 |
| CloudKit schedule sync | `CloudKitSyncService.swift` | ~2026 |
| Daily history struct | `UsagePersistence.swift` | 16-30 |
| Daily history prune | `UsagePersistence.swift` | 373-376 |
| Existing migration pattern | `AppScheduleService.swift` | 52-83 |

---

## Verification

### Phase 1 (manual + device)

1. **Parent fallback ratio fix.** Set ratio to 1:4 on a paired child. Have the kid log ~20 min of learning. On parent device, force a fallback path (e.g., delete cached snapshot or use a fresh parent install). Confirm parent dashboard's "earned" number matches `20 × 4 = 80`, not `20`.
2. **Confirmation dialog — decrease.** With cumulative L=208, R=1081, current ratio 1:8 (bank=583). Edit ratio to 1:4. Dialog must appear with "from 583 to 0". Cancel → no change. Save Anyway → ratio updates, bank reads 0 (current behavior, but now consented).
3. **Confirmation dialog — increase.** From 1:4 to 1:8. No dialog. Bank reads 583 immediately.
4. **`tracked_app_ids` union.** Configure 1 learning app + 14 reward apps (matches today's device state). After `scheduleActivity()`, dump `tracked_app_ids`. Expected count: 15 (1 learning + 14 reward), not 1 (learning only).
5. **Stale-cleanup migration.** On a device with the 278-min stale value: launch app once. Verify `usage_<rewardID>_today` is now 0 for all 14 reward apps; `stale_usage_cleanup_v1` flag is set; subsequent launches don't re-run the cleanup.
6. **Shield text.** With stale data cleared, attempt to launch a reward app while pool is empty. Shield should show "0 minutes" (or new copy "today's reward time"), not "278".

### Phase 2 (unit + device)

1. **`versionActive(on:)` lookup.** Unit-test: 3 versions with `effectiveFromDay` 2026-04-01 / 2026-04-15 / 2026-05-01. Query 2026-04-10 → returns the 2026-04-01 version. Query 2026-05-02 → returns the 2026-05-01 version. Query 2026-03-31 → returns nil.
2. **Migration seeding.** Fresh install with existing schedule at ratio 1:6. After upgrade, exactly one `AppScheduleVersion` exists with `effectiveFromDay = "1970-01-01"` and ratio 1:6. Bank value identical pre- and post-upgrade.
3. **Cross-day pinning.** Day 1: ratio 1:1, kid earns 60 min, bank shows 60. Midnight rolls over.
   - **3a — edit before kid uses learning.** Day 2 morning: `todayLearningSeconds == 0` → parent edits to 1:4 effective TODAY. Kid then earns 30 min at 1:4 → Day 2 bank = 60 (Day 1, pinned at 1:1) + 120 (Day 2 at 1:4) = 180.
   - **3b — edit after kid has already earned.** Day 2 afternoon: `todayLearningSeconds > 0` (kid already did 30 min at 1:1) → parent edits to 1:4 effective TOMORROW. Day 2 bank = 60 + 30 = 90 (Day 2 stays at 1:1). Day 3: kid earns 10 min at 1:4 → bank = 60 + 30 + 40 = 130.
4. **Parent recompute parity.** With the same Day-3 state, the parent's bank for the kid must equal 130 — confirms `versionActive` is wired through `fallbackEarnedMinutes` and the synced `scheduleVersions` round-trip.
5. **CloudKit additive field.** Old client (pre-versioning) reading a record written by new client must still load schedule correctly (just ignoring `CD_scheduleVersionsJSON`). New client reading old record (no versions field) must fall back to "treat current schedule as active for all days."

### Regression checks

- Memory budget on the extension stays within 6 MB. The extension code is unchanged; only the value of `bank_historical_remaining_minutes` shifts. Verify with extension logs.
- Existing pool-aware shield invariant (extension `checkAndUpdateShields` ↔ main-app `BlockingCoordinator.evaluateBlockingState`) still holds — neither function's logic changes.
- `includesPastActivity: true`, midnight rebuild, sliding-window threshold registration — all untouched.
