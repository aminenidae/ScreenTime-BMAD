# Parent Dashboard Performance & Correctness Overhaul

**Date**: 2026-05-14
**Branch**: `refactor/unified-usage-counter`
**Status**: ✅ Shipped — user-validated end-to-end
**Affected files**:
- `Services/CloudKitSyncService.swift`
- `Services/DevicePairingService.swift`
- `ViewModels/ParentRemoteViewModel.swift`
- `Views/ParentRemote/ChildDeviceSummaryCard.swift`
- `Views/ParentRemote/ChildUsageDashboardView.swift`
- `Views/ParentRemoteDashboardView.swift`
- `Views/ParentMode/ParentPairingView.swift`

---

## Table of Contents

1. [Symptoms reported by user](#symptoms-reported-by-user)
2. [Architectural diagnosis](#architectural-diagnosis)
3. [Fixes shipped (in order)](#fixes-shipped-in-order)
4. [Resulting flow](#resulting-flow)
5. [Things that did NOT work / known limitations](#things-that-did-not-work--known-limitations)
6. [Rules for future contributors](#rules-for-future-contributors)
7. [Commit log](#commit-log)

---

## Symptoms reported by user

A Family-plan parent device with 5 paired children exhibited a stack of overlapping issues:

1. **Pull-to-refresh on Family Dashboard took ~3 minutes** to complete.
2. **Tapping a child card showed a stuck "Loading {device}…" spinner**, often forever; user workaround was to swipe to a different child and back.
3. **Tapping kid A's card sometimes opened kid B's dashboard** (wrong child's content under the right child's header).
4. **A QR-code generation hung indefinitely** on the "Generating QR code…" spinner.
5. **A newly-paired child wouldn't appear in the parent dashboard** even after the child app confirmed the pairing (~1 minute later).
6. **Family Dashboard card layout visibly shifted** after the CK background sync completed.
7. **Disk cache showed 5 children but only 4 were rendered** — user feared the system thought they had hit the family-plan limit.

The 30s-per-child sync time was the headline complaint, but the wrong-child and stuck-spinner issues turned out to be symptoms of a deeper architectural mismatch between SwiftUI view-update timing and async CloudKit work.

---

## Architectural diagnosis

The parent dashboard runs **one shared `ParentRemoteViewModel`** that holds the currently-displayed child's data in `@Published` properties (`childLearningAppsFullConfig`, `childRewardAppsFullConfig`, `usageRecords`, etc.) plus a `selectedChildDevice` pointer.

The Family Dashboard cards, the carousel-paged child detail view, and every per-child sub-view all read from this same VM. Several code paths competed to mutate the VM concurrently:

- `loadLinkedChildDevices()` ran on app launch and on every pull-refresh.
- `loadChildData(device)` was called from 7+ places: cards' `onAppear`, the dashboard's auto-select, the dashboard's `refreshData`, page swipes, the refresh button, pull-to-refresh per tab, and the `NewChildPaired` notification.
- Each `loadChildData` ran 7 sequential CloudKit fetches (usage, basic configs, full configs, shields, history, snapshot, streaks) and wrote results to the shared `@Published` arrays.

Three independent root-cause families:

### A. CloudKit was doing far more work than necessary

| Layer | Behavior before |
|---|---|
| `fetchLinkedChildDevices` | Enumerated 23 zones in the parent's private DB (4 real + 19 orphans from old pairings) sequentially, downloading every record (~1500/zone) just to extract one `CD_RegisteredDevice`. |
| `fetchChildShieldStates` | Zone-specific CKQuery returned `"Did not find record type: CD_ShieldState"`; code fell back to scanning all 33 zones, each returning the same error. CloudKit's `Error rate mitigation activated` then slowed the entire session. |
| Per-child fetches | 6 dependent fetches ran sequentially per child; with 5 children, dashboard load was 30s × 5 = ~150s wall-clock. |

### B. SwiftUI render timing didn't match async update timing

`loadChildData` is async — `selectedChildDevice` and the data arrays update only after a `Task` completes its first hop. But `ChildUsageDashboardView` re-evaluates its body the moment the user taps a card. The first render happens BEFORE the Task can update the VM. So the page either showed a stuck spinner (selection mismatch) or stale content (selection right, data still belongs to the previous child).

### C. Card layout was non-deterministic across sync passes

`populateFromLocalCache` wrote `linkedChildDevices` in Core Data fetch order. The subsequent CK fetch then replaced the array with whatever order the service returned (and with **transient** managed objects, not the same Core Data rows). The `LazyVGrid` in `DeviceCardCarousel` reshuffled the cards visually — under the user's finger, the position of "Iness" could become the position of "Imane" in the milliseconds between tap and navigation.

---

## Fixes shipped (in order)

### 1. Known-zone cache + service-level coalescing (`04adbc0`)

**Problem:** Every entry point that called `fetchLinkedChildDevices` re-enumerated all 23 zones, downloading thousands of unrelated records.

**Fix:**
- Persist the set of known child-zone names per parent in app-group `UserDefaults` (`parent_known_child_zones_v1_<parentID>`). After the first successful fetch, every subsequent call restricts the scan to those 4 zones.
- Persist a `deviceID → (zoneName, zoneOwner)` mapping so `populateFromLocalCache` can enrich `RegisteredDevice` rows with `sharedZoneID` synchronously. Without this enrichment, every per-child fetch fell back to a 33-zone "all-zones" scan because `device.sharedZoneID` was `nil`.
- Coalesce concurrent `fetchLinkedChildDevices(restrictToKnownZones: true)` callers onto a single in-flight `Task`.
- Retry transient zone-fetch errors up to 3× with backoff; a single dropped packet had previously been enough to silently lose a paired child.
- One-shot orphan-zone cleanup (`parent_orphan_zone_cleanup_v1_done_<parentID>`) deletes ChildMonitoring zones not in the fresh result set. Safety conditions: full scan was used, every zone succeeded, result non-empty. Only successfully-scanned zones are deletion candidates — a failed scan is never grounds for deletion.

### 2. Parallelize per-child fetches + freshness short-circuits (`818c485`)

**Problem:** 7 sequential CK fetches per child × N children × 7-second average per fetch.

**Fix:**
- Wrap the 6 fetches inside `loadChildAppConfigurations` and the 4 fetches inside `loadChildData` in `async let` so they fire concurrently. Wall-clock collapses to the slowest single query.
- Per-child throttle: track `lastChildLoadAt[deviceID]`; skip the CK fetch within a 30s window unless the caller passes `forceRefresh: true`. Pull-to-refresh and the refresh button bypass; page swipes and `onAppear` don't.
- VM-level freshness short-circuit on `fetchLinkedChildDevices(restrictToKnownZones: true)`: within 30s of a successful fetch, synthesize the result from local Core Data + the cached zone mapping. No CK round-trip for repeat callers.
- Add `selectedChildDevice` mismatch guards to `loadChildStreakRecords` and `loadExtensionSyncStatus` writes — they now run in parallel so could land after a user swipe.

### 3. Targeted record-type query (`70dfa87`)

**Problem:** `fetchAllRecordsInZone` downloaded every record in the zone (~1500/zone) to find one `CD_RegisteredDevice`.

**Fix:**
- New `fetchRegisteredDeviceRecordsInZone` runs `CKQuery(recordType: "CD_RegisteredDevice", predicate: NSPredicate(value: true))`. The predicate references no fields, so it doesn't depend on per-field queryable indexes — only the record type needs to be enumerable.
- Session-scoped fallback flag: if the query gets `"not marked queryable"` (production schema doesn't promote `CD_RegisteredDevice` in the user's case), subsequent zones in the same run go straight to the slow `fetchAllRecordsInZoneWithRetry` path without a wasted round-trip.

**Status:** The CKQuery path works once `CD_RegisteredDevice` is promoted as queryable in CloudKit Dashboard. Until then, the fallback path runs (see fix #4).

### 4. Parallelize zone enumeration (`ba7462a`)

**Problem:** Even after the targeted query, the fallback case still hit the slow zone-changes path. The for-loop over zones was sequential — 4 real zones × 6s each = 24-30s wall-clock for device discovery.

**Fix:** Replace the for-loop with a `TaskGroup` so all zones fetch concurrently. Per-zone processing (filtering for `CD_RegisteredDevice`, deduplication) still runs sequentially after the parallel fetch returns, but it's local CPU work with no I/O.

### 5. CD_ShieldState all-zone-scan short-circuit (in `818c485`/`70dfa87`)

**Problem:** When the zone-specific shield-states query failed with `"Did not find record type"`, the fallback enumerated all 33 zones — each returning the same error. The cascade tripped CloudKit's error-rate mitigation, slowing the entire session.

**Fix:** When the zone-specific attempt fails with that specific error, record the schema miss in the session-scoped cache and return empty immediately. No all-zone fallback.

### 6. QR generation no longer hangs on in-flight fetches (`04adbc0`)

**Problem:** `DevicePairingService.createSecurePairingSession` and `createPairingSession` called `cloudKitSync.fetchLinkedChildDevices().count` to validate the seat limit. With service-level coalescing, this would await any in-flight refresh — if that refresh was slow, the "Generating QR code…" spinner hung.

**Fix:** New `localPairedChildCount()` reads the count directly from local Core Data. `NSPersistentCloudKitContainer` mirrors `RegisteredDevice` rows in near-real-time, so the local count tracks CloudKit truth without a CK round-trip.

### 7. Polling baseline race on new pairing (in `04adbc0`)

**Problem:** `ParentPairingView.startPollingForNewChild` was calling `fetchLinkedChildDevices(restrictToKnownZones: false)` to capture a baseline count, then polling every 2s for the count to increase. The baseline fetch took ~60s (full scan). During that window, the child finished pairing and was already in the count. The poll loop then waited for the count to exceed N+1, which never happened.

**Fix:** Capture the freshly-created zone ID from `createSecurePairingSession` and poll that specific zone for any `CD_RegisteredDevice` with the matching parent. Single-zone targeted query, immune to timing races.

### 8. Family Dashboard cards no longer mutate shared VM state (`1deeb2e`)

**Problem:** Each `ChildDeviceSummaryCard.onAppear` called `viewModel.loadDeviceSummary`, which ran `loadChildData`, which mutated `selectedChildDevice`. With 5 cards firing concurrently on dashboard appearance, `selectedChildDevice` thrashed between children. When the user then tapped a card and navigated, a later card's `loadChildData` would land and steal `selectedChildDevice` — the destination page's `isVMShowingThisDevice` gate flipped to false and the spinner stuck.

**Fix:** Cards now read their tile data (screen time, points, app count) directly from `ParentDeviceCacheService.dailySnapshot` on disk. No CK round-trip, no shared VM mutation. The disk cache is populated by previous successful per-child loads.

### 9. Skip launch-time per-child load (`7fb2393`)

**Problem:** `ParentRemoteDashboardView.refreshData(isAuto: true)` — fired on app launch and on scenePhase active — was force-loading the auto-selected child's full per-child data. User is on the Family Dashboard at that moment, not a child page; cards render from disk cache. The launch-time per-child load was pure waste and its `clearChildSpecificState` + `restoreCachedChildState` cascade kept the @Published arrays churning when the user then tapped into a child.

**Fix:** `isAuto: true` now only refreshes the device list. Explicit pull-to-refresh and refresh-button still force the per-child load with `forceRefresh: true`.

### 10. `selectAndRestoreFromCache` guard with state-owner tracking (`7fb2393`, `09adce4`)

**Problem:** Calling `selectAndRestoreFromCache` for a device that was already selected re-cleared and re-restored all child-specific @Published vars — ~20 `objectWillChange` events for nothing.

**First attempt** guarded on `selectedChildDevice?.deviceID == device.deviceID && !configs.isEmpty`. **Broken** when views set `selectedChildDevice` synchronously: the guard would short-circuit while the @Published state still belonged to the previous child, leaving stale data on screen.

**Fix:** Introduce `childStateOwnerDeviceID` — a separate tracker, updated only by `restoreCachedChildState`, that records which device the @Published state actually belongs to. The guard now checks `childStateOwnerDeviceID == device.deviceID` instead of `selectedChildDevice`. Selection can update synchronously without confusing the data-owner check.

### 11. Synchronous select-and-restore on tap + stable card order (`fb2f93c`)

**Problem:** Even after the previous fixes, tapping kid A could open kid B's dashboard. Two interacting causes:

(a) `ChildUsageDashboardView.onAppear` was setting `viewModel.selectedChildDevice = device` synchronously (good for spinner gate) and scheduling `loadChildData` as a `Task` (bad). The sync set opened the gate; the @Published arrays still held the previous child's data; render showed tapped-child header + previous-child content.

(b) `linkedChildDevices` was unsorted. `populateFromLocalCache` and `performLoadLinkedChildDevices` produced different orders. Carousel cards visibly reshuffled when the CK fetch completed. User observation: *"the family dashboard has a specific child card layout, after the CK sync is done, the layout changes"*. Tap landed on the wrong card.

**Fix:**

(a) New public entry point `selectAndRestoreFromCacheSync(_:)` on the VM. Views call this synchronously in `onAppear` and `onChange(currentIndex)` — both `selectedChildDevice` AND the @Published state swap to the tapped device's cache in one atomic step before SwiftUI re-evaluates the body.

(b) Sort `linkedChildDevices` by `deviceID` at both assignment sites. Layout is now stable across the local-cache → CK-fetch transition.

---

## Resulting flow

### App launch

1. `ParentRemoteViewModel.init` runs.
2. `populateFromLocalCache` reads Core Data + enrichment cache → `linkedChildDevices` populated (sorted) → cards render instantly.
3. `Task { loadLinkedChildDevices() }` kicked off.
4. `loadLinkedChildDevices` hits the freshness short-circuit if within 30s, or runs `performLoadLinkedChildDevices`.
5. `performLoadLinkedChildDevices` calls `fetchLinkedChildDevices(restrictToKnownZones: true)` → 4 zones queried in parallel via `TaskGroup`, returns within ~1s on fast path or ~6s on CKQuery-fallback path.
6. `linkedChildDevices` re-sorted and reassigned — same order, no visual reshuffle.
7. `selectedChildDevice` auto-set to first device (sorted by deviceID) → `selectAndRestoreFromCache` paints from disk cache.
8. No per-child data load runs at launch (`isAuto: true` skips it).

### User taps a child card

1. `DeviceCardCarousel` NavigationLink fires → `ChildUsageDashboardView` pushed.
2. `init` sets `currentIndex` to the tapped device's index in the (stable) `devices` array.
3. First body render: `currentDevice == devices[currentIndex]` — the tapped child.
4. `onAppear` fires:
   - `viewModel.selectAndRestoreFromCacheSync(device)` — both selection AND cached @Published state swap atomically.
   - `Task { loadChildData(device) }` schedules the background CK refresh.
5. SwiftUI re-evaluates body after the synchronous mutation. `isVMShowingThisDevice == true`. Spinner hidden. Tabs show this child's cached data.
6. CK refresh completes in background (~5-10s for a fresh load, instant if throttled). State updates seamlessly.

### Per-child refresh on swipe

1. `onChange(of: currentIndex)` fires the same synchronous `selectAndRestoreFromCacheSync` + async `loadChildData`.
2. Throttle: if the destination device was loaded within 30s, skip CK; just keep the cached state in view.
3. If forced refresh (pull-down): re-fetch even if recent.

### Pull-to-refresh on Family Dashboard

1. `refreshData(isAuto: false)` runs.
2. `loadLinkedChildDevices()` — fast on the freshness short-circuit path.
3. `loadChildData(selectedChildDevice, forceRefresh: true)` — bypasses throttle. 7 fetches in parallel.

---

## Things that did NOT work / known limitations

### CKQuery for CD_RegisteredDevice — schema-dependent

`CKQuery(recordType: "CD_RegisteredDevice", predicate: NSPredicate(value: true))` is rejected by the user's production CloudKit schema with `"not marked queryable"`. The fallback `fetchAllRecordsInZoneWithRetry` runs instead. **To unlock another ~5× speedup**, promote `CD_RegisteredDevice` recordType as queryable in CloudKit Dashboard → Schema → Record Types → CD_RegisteredDevice → recordType → mark queryable → Deploy to Production.

### Per-child zone holds ~1500 records

Each child's monitoring zone accumulates `CD_DailyUsageHistory` records (one per app per day) indefinitely. After 6 months × 15 apps × 30 days = 900+ records per zone. There's no aging-out logic. Cleanup would require rolling daily records up into monthly summaries (the app's Daily/Weekly/Monthly view depends on the daily granularity for recent data and would need an aggregate record type for older data). **Not addressed in this overhaul** — left as future work. The new CKQuery fast path and zone parallelization make the record count irrelevant for the device-discovery side; per-child data fetches use targeted `CD_deviceID == X` predicates that return only the matching records anyway.

### Disk cache holds historical kids (5 entries for 4 active)

`ParentDeviceCacheService` is append-only — entries for unpaired kids stay on disk indefinitely. The UI doesn't render from this cache directly, so it's harmless. **Not addressed**. Worth pruning eventually for hygiene.

### Firebase `family.childCount` parallel state

Firebase server-side stores its own `family.childCount` separately from CloudKit and the local cache. When a child is unpaired via a path that doesn't call `removeChildFromFamily`, Firebase's count stays inflated. **Not addressed** — would require an auditor that compares local count vs Firebase count and reconciles. For the affected user, `localPairedChildCount()` now bypasses both Firebase and CloudKit for the seat-limit gate during QR generation, so this drift doesn't block pairing.

---

## Rules for future contributors

These rules emerged from this session — break them and you'll resurrect symptoms we just fixed.

1. **Don't call `loadChildData` from views that aren't actively displaying that child.** Cards on the Family Dashboard, list views, summary widgets — none of them should mutate the shared `ParentRemoteViewModel` state. Read from `ParentDeviceCacheService.shared.loadCachedState(parentID:)` directly.

2. **`selectedChildDevice` and the child-specific @Published arrays must be swapped together.** Setting `selectedChildDevice = device` synchronously while leaving the data arrays for a different child causes "tapped X, see Y's data". Use `selectAndRestoreFromCacheSync(_:)`.

3. **Don't add zone-changes operations to discover specific records.** Use a `CKQuery` filtered by `recordType` with `NSPredicate(value: true)`. Even when schema indexes aren't promoted, the fallback in `fetchRegisteredDeviceRecordsInZone` handles it gracefully.

4. **Don't await `cloudKitSync.fetchLinkedChildDevices()` just to get a count.** Use `localPairedChildCount()` or the equivalent `linkedChildDevices.count`. Awaiting the service can block on an in-flight slow fetch and freeze UI indefinitely.

5. **All-zone fallback scans are dangerous.** When a record-type doesn't exist in CK, the fallback hits every zone with the same error, triggering CK error-rate mitigation that slows the entire session. If a zone-specific fetch fails with `"Did not find record type"`, return empty immediately and record the schema miss.

6. **Keep `linkedChildDevices` sorted deterministically.** The carousel renders by array order. Reordering mid-flight under the user's finger is a UX bug. Sort by `deviceID` whenever the array is assigned.

7. **Orphan-zone cleanup is one-shot per parent device.** Don't add another cleanup pass without checking the `parent_orphan_zone_cleanup_v1_done_<parentID>` flag. Repeated deletions on every launch invite race conditions with newly-paired children.

8. **Never trust `selectedChildDevice` as a "what's in the @Published state" indicator.** Views can update it synchronously. Use `childStateOwnerDeviceID` (private to VM) if you need to know which device the visible data actually belongs to.

---

## Commit log

| Commit | Subject |
|---|---|
| `04adbc0` | fix(parent-sync): eliminate slow CloudKit fetches in parent-side flows |
| `818c485` | perf(parent-sync): parallelize per-child fetches, add freshness short-circuits |
| `70dfa87` | perf(parent-sync): use CKQuery to fetch only CD_RegisteredDevice records per zone |
| `ba7462a` | perf(parent-sync): parallelize zone enumeration in fetchLinkedChildDevices |
| `1deeb2e` | fix(parent-sync): decouple Family Dashboard cards from shared VM state |
| `7fb2393` | fix(parent-sync): stop redundant launch-load and cache-restore cascade |
| `09adce4` | fix(parent-sync): wrong-child dashboard when tapping a card |
| `fb2f93c` | fix(parent-sync): wrong-child dashboard — sync cache restore + stable card layout |

---

## Measured impact (user-reported)

| Operation | Before | After |
|---|---|---|
| Initial dashboard paint | 30s+ per child × 5 = several minutes | <1s (cache-first), background CK refresh |
| Pull-to-refresh | ~3 minutes (rate-limited) | ~5-10s |
| Tap a child card | spinner stuck, workaround required | instant; correct child's data |
| Swipe between children | felt slow | near-instant with throttled fast path |
| QR code generation | hung indefinitely | ~2s |
| New child pairing detection | never (polling baseline race) | within ~2s of child writing record |
