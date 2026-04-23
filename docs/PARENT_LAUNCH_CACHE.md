# Parent Device Launch Cache

**Date**: 2026-04-22
**Commits**: `d997cbb` (first pass) → `e99a690` (cache-restore on child switch) → `1719e93` (don't pre-restore into every VM) → `c7f29e3` (top bar UI)

## Problem

Parent main-app cold launch took ~60s on a 5-child iPad before any child card appeared. During that window the dashboard rendered "No Child Devices Linked" as a lie. Tapping a child then showed a full-screen modal spinner over a "0 min" dashboard for another several seconds. Latency scaled linearly with paired children (and orphaned zones from prior pairings).

Xcode launch log on 2026-04-22 showed five compounding causes:

1. Every cold start blocked on CK fetches for children + usage + configs + snapshot + shield states + history.
2. "No Child Devices Linked" empty state had no `hasCompletedFirstLoad` guard — rendered immediately while the fetch was in flight.
3. `loadLinkedChildDevices()` fired 3× per launch (pre-PIN + post-PIN + device-click) from 8 call sites. The `isLoadingDevices` flag-flip guard didn't coalesce callers.
4. `CD_ShieldState` fallback queried all 25 zones on schema-miss, tripping CK's `Error rate mitigation activated` rate-limit which poisoned every subsequent call.
5. `loadExtensionSyncStatus` hit `sharedCloudDatabase` with a zone that was actually private → `Only shared zones can be accessed in the shared DB` error twice per launch.

## Solution

Three-layer cache-first render:

1. **Device list** — already persisted in Core Data via `NSPersistentCloudKitContainer`. Read synchronously on init (no CK round-trip).
2. **Per-child state** (daily snapshot, usage history, full app configs, shield states) — persisted to disk JSON by new `ParentDeviceCacheService`. One file per parent at `Application Support/ParentCache/parent_<parentID>.json`.
3. **CK refresh** — runs in background after cache is rendered. Top indeterminate progress bar signals in-flight state; dashboard stays interactive throughout.

## Architecture

### `ParentDeviceCacheService` (`Services/ParentDeviceCacheService.swift`)

Singleton. Codable DTOs mirror the non-Codable `FullAppConfigDTO` / `DailySnapshotDTO` / `DailyUsageHistoryDTO` / `ShieldStateDTO`. Atomic writes via `Data.write(to:options:.atomic)`, 500ms debounce so rapid `objectWillChange` emissions don't thrash disk. Schema version 1 — bump on field-shape changes, loader returns nil on mismatch (safe cold-start).

```
ParentDeviceCacheSnapshot
├── schemaVersion: Int
├── savedAt: Date
└── children: [CachedChild]
      ├── deviceID, displayName, sharedZoneID, sharedZoneOwner, lastSyncAt
      ├── dailySnapshot: CachedDailySnapshot?
      ├── dailyUsageHistory: [CachedDailyUsageHistory]?
      ├── configs: CachedConfigSnapshot?        // learningConfigs + rewardConfigs
      └── shieldStates: [CachedShieldState]?
```

Public API:
- `loadCachedState(parentID:) -> ParentDeviceCacheSnapshot?`
- `saveCachedState(_:parentID:)` — debounced
- `saveCachedStateImmediately(_:parentID:)` — escape hatch for critical writes
- `updateChild(deviceID:parentID:mutating:)` — atomic per-child edit
- `clearCache(parentID:)` — for unpair-all / sign-out

### `ParentRemoteViewModel` changes

- **`@Published var hasCompletedFirstLoad = false`** — flips true at end of `loadLinkedChildDevices` (success OR failure). View gates the empty state on this.
- **`inFlightLoadTask: Task<Void, Never>?`** — coalesces concurrent callers of `loadLinkedChildDevices()` onto a single running task. Replaces the old `isLoadingDevices` flag-flip guard.
- **`populateFromLocalCache()`** — called from `init()`. Reads `RegisteredDevice` rows from local Core Data (`deviceType == "child" AND parentDeviceID == <my id>`) and populates `linkedChildDevices`. Does NOT restore any child-specific state here — see next.
- **`restoreCachedChildState(deviceID:)`** — single source of truth for cache→published properties. Populates `childDailySnapshot`, `childDailyUsageHistory`/`ByApp`, `childLearningAppsFullConfig`, `childRewardAppsFullConfig`, `childShieldStates` for the target device. Called only by `loadChildData(for:)`, never from `init`.
- **`loadChildData(for:)`** — after the state wipe (clears fields that are device-specific), calls `restoreCachedChildState(deviceID:)` for the target device, THEN runs the CK fetch. Cache paints first, CK refines.
- **`persistChildToCache(device:)`** — called at end of `loadChildAppConfigurations` success. Flattens current in-memory state into `CachedChild` via `FullAppConfigDTO.toCache()` and writes via `ParentDeviceCacheService.updateChild`.
- **`FullAppConfigDTO.fromCache(_:)` / `.toCache()`** — round-trip through JSON strings matching the CD_-prefixed CKRecord shape. Sub-structures (`AppScheduleConfiguration`, `[LinkedLearningApp]`, `AppStreakSettings`) encode/decode identically to the CKRecord init path.
- **`loadExtensionSyncStatus`** — routes to `privateCloudDatabase` if `sharedZoneOwner == CKCurrentUserDefaultName || == <my recordName>`, else `sharedCloudDatabase`. Soft-fallback on routing error (log once, skip).

### `CloudKitSyncService` changes

- Session-scoped `schemaMissSet: Set<String>` keyed `"<zone>:<recordType>"`. Static. First `Did not find record type` error per zone records the miss; subsequent fallback iterations skip that zone. Prevents the 25-zone cascade that used to trip CK's rate-limit.
- Wired into the `CD_ShieldState` fallback at the existing all-zones enumeration.

### View gating

**`ParentRemoteDashboardView.swift`** — three-way empty-state gate:
1. `!linkedChildDevices.isEmpty` → carousel.
2. `!hasCompletedFirstLoad` → `ProgressView("Loading your family…")` skeleton.
3. else → truthful "No Child Devices Linked" empty state with pairing CTA.

**`ChildUsagePageView` in `ChildUsageDashboardView.swift`** — full-screen modal spinner replaced with a 2pt linear `ProgressView` at the top of the `VStack`. Dashboard + tabs remain interactive throughout. Fade in/out ~200ms. Reserves zero space when idle.

## Why cache is NOT pre-restored in `init`

Each SwiftUI view that uses the dashboard owns its own `@StateObject ParentRemoteViewModel`:
- `ParentTabView.swift:15`
- `ParentRemoteDashboardView.swift:6`
- `ChildUsageDashboardView.swift:10`

If `populateFromLocalCache()` auto-restored the FIRST child's state into every new VM's init, a fresh `ChildUsageDashboardView` for a non-first child would render the first child's numbers behind the spinner before `onAppear` fired `loadChildData(for: currentDevice)`. User observed this as "same dashboard of the first child" bleeding through on child switch (commit `e99a690` log). Commit `1719e93` removed the init-time restore; each view's `loadChildData(for:)` call drives its own cache restore for the correct device.

## What this does NOT solve (follow-ups)

- **Three-VM duplication**: the three `@StateObject` instantiations still each run their own CK fetch on cold launch. Dedup is per-instance. Fix is architectural — single shared VM passed via `@EnvironmentObject` or `@ObservedObject` from `ParentTabView` — deferred per user direction.
- **"Updated N min ago" per-card freshness label**: planned in original spec, not yet shipped.
- **`CKServerChangeToken`-based incremental fetches**: the cache scaffolding unlocks this but the token plumbing isn't there yet.
- **`CKDatabaseSubscription` + APNs push refresh**: long-term, would make the dashboard passively fresh.
- **Stale-zone cleanup on server**: 10 of 15 `ChildMonitoring-*` zones are orphans from prior pairings. The session schema-miss cache neutralizes their cost; cleanup is a CK Dashboard operation when you have a moment.
- **Empty-state `ProgressView`s** in `RemoteUsageSummaryView`, `HistoricalReportsView`, `ChildDeviceSummaryCard`, `ChildFullPageView`, `RemoteAppConfigurationView` — these are section-level placeholders, not modal blockers. Left untouched for now.

## Verification

End-to-end on the parent device with ≥2 paired children, after at least one prior successful launch (so the cache is warm):

1. **Hot relaunch**: kill + relaunch main app → PIN screen → immediately shows carousel with all children from local Core Data (no 60s blank).
2. **Tap a previously-visited child**: dashboard renders its own cached usage + configs instantly. Top bar visible while CK refresh runs; tabs + scroll + app configuration remain tappable throughout.
3. **Swipe between children**: each page shows its own cached data, not bleed-through from the first child.
4. **Tap a never-visited child**: still cold (no cache for that ID) — spinner + zeros briefly until CK lands. Subsequent taps that child is cached.
5. **Extension debug log scan**: no `Error rate mitigation activated`. `Did not find record type: CD_ShieldState` appears at most once per zone per session.
6. **Cache location**: `Application Support/ParentCache/parent_<parentID>.json` exists, schema 1, children count matches paired.

## Known gotchas

- **`FullAppConfigDTO.fromCache` / `.toCache`** round-trip through JSON strings. If `AppScheduleConfiguration`, `LinkedLearningApp`, or `AppStreakSettings` lose Codable conformance, cache restore silently degrades to defaults. Writes still succeed (JSON fields become nil), reads produce struct with empty sub-structures — symptom would be dashboard showing "Unlimited / All day / no linked apps" after a relaunch.
- **Cache never self-invalidates by time**. If a child is unpaired from another parent device or a config is edited out-of-band, the cache here keeps stale data until the next CK fetch on this device updates it. CK always wins on conflict, so this is self-healing on refresh.
- **Schema version on `ParentDeviceCacheSnapshot` is 1**. Bump whenever a cached field shape changes; the loader returns nil on mismatch → safe cold-start.
- **Pull-to-refresh still works** (`.refreshable` on `ChildUsagePageView`) — explicit user-triggered path alongside the passive top bar.
