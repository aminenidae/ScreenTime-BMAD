# Development Handoff Brief
**Date:** 2025-10-19 (Token Persistence v4 Implementation – Awaiting Device Validation)
**Project:** ScreenTime-BMAD / ScreenTimeRewards
**Status:** ⚠️ Persistence overwrite bug discovered during device QA — fix in progress

---

## Executive Summary

- `UsagePersistence` now hashes each `ApplicationToken`’s internal `data` payload (128 bytes) with SHA256. The resulting `token.sha256.<digest>` is stored in `tokenMappings_v1` and maps back to the logical ID (bundle ID when available, otherwise generated UUID).
- `ScreenTimeService` uses the new `resolveLogicalID` helper during both `loadPersistedAssignments` and `configureMonitoring`, ensuring Set order changes do not shuffle minutes/points between learning cards.
- Persistent usage records remain in `persistedApps_v3`; the DeviceActivity extension writes into the same store and benefits from the stable logical IDs.
- **New regression (Oct 19, 11:53 AM):** `configureMonitoring` now overwrites the persisted usage totals with zeroed structs whenever the app relaunches. Cold launches therefore display the correct app list but `0` minutes/points.

**STATUS:** ⚠️ Merge-and-preserve fix required before re-running validation.

---

## Latest Findings (Oct 20, 12:45 PM CDT)

- First launch after reinstall (`Run-ScreenTimeRewards-2025.10.19_11-56-26--0500.xcresult`) shows DeviceActivity events writing 60 s + 120 s into `persistedApps_v3` as expected.
- Cold relaunch (`Run-ScreenTimeRewards-2025.10.19_11-53-14--0500.xcresult`) logs `[UsagePersistence] ✅ Loaded 3 apps, 3 token mappings`, but the very next lines from `ScreenTimeService` print each app with `0.0s, 0pts`.
- Root cause: `ScreenTimeService.configureMonitoring` seeds a new `UsagePersistence.PersistedApp` for every token with `totalSeconds = 0` / `earnedPoints = 0`. Because `saveApp` replaces the cached record, the genuine totals are wiped immediately after load.
- Impact: UI and totals reset on every relaunch; background tracking while the app is terminated is also lost.
- Action: Added `UsagePersistence.app(for:)`, updated `configureMonitoring` to merge existing records, and repopulated the in-memory `appUsages` map so restored totals flow back to the UI (Oct 19); awaiting fresh device logs to confirm the fix.
- Oct 20: Swift compiler started timing out on `LearningTabView` (“unable to type-check this expression in reasonable time”, see `Build ScreenTimeRewards_2025-10-20T12-48-02.txt`). Refactored the tab into small helper builders (mirroring the Rewards tab fix) so it now compiles cleanly.

**Proposed Fix**
1. Introduce a merge helper in `UsagePersistence` (e.g., `upsertApp(logicalID:update:)`) so `configureMonitoring` can preserve historical `totalSeconds`, `earnedPoints`, and timestamps when a record already exists.
2. Keep updating mutable fields (category, rewardPoints) so user edits still apply.
3. Retain the SHA256 mapping; no changes required to token hash extraction based on current logs.

---

## Problem Recap & Pre-Fix Evidence

- Logs `Run-ScreenTimeRewards-2025.10.18_21-46-58--0500.xcresult` → `…21-51-10…` showed learning cards swapping minutes/points after rebuild because the fallback UUIDs were tied to `Unknown App <index>` labels.
- `Run-ScreenTimeRewards-2025.10.19_10-32-47--0500.xcresult` (screenshot attached) loaded the correct tokens but no usage—logical IDs could not be reconstructed after relaunch.
- DeviceActivity extension wrote minutes while the UI was closed, but on reopen the data appeared under the wrong card.

These failures confirmed that persistence must be keyed by token archives rather than display names or Set ordering.

---

## Implemented Solution (Token-Archive Mapping)

1. **Stable logical IDs**
   - `resolveLogicalID(for:bundleIdentifier:displayName:)` returns `(logicalID, tokenHash)` and persists the mapping immediately.
   - Bundle ID remains the logical ID when Apple provides it; otherwise a UUID is generated and tied to the token hash.

2. **Mapping persistence**
   - `cachedTokenMappings` is hydrated from `tokenMappings_v1` on launch; all updates are written back to App Group storage.
   - `logicalID(for tokenHash:)` now succeeds across cold launches and Set reordering.

3. **Usage storage**
   - `cachedApps` retains all persisted apps (`persistedApps_v3`). `saveApp` and `recordUsage` update the in-memory cache and persist to disk.
   - The DeviceActivity extension updates the same `persistedApps_v3` record, so background minutes accrue on the correct logical ID.

4. **Service integration**
   - `loadPersistedAssignments` resolves token hashes up front, rebuilds `categoryAssignments`, and only then reconfigures monitoring.
   - `configureMonitoring` uses the tuple returned by `resolveLogicalID` for both persistence and debugging. The previous `mapTokenArchiveHash` step is no longer required.

---

## What’s Next (Fix + Validation Checklist)

- [x] **Fix persistence overwrite** — Update `configureMonitoring` / `UsagePersistence` to merge with existing records instead of resetting `totalSeconds`/`earnedPoints`. ✅ Verified via logs `Run-ScreenTimeRewards-2025.10.19_12-39-58--0500.xcresult`.
- [x] **Cold launch retention** — Re-ran News/Books scenario (60 s + 120 s), relaunched, and confirmed minutes/points remain on correct cards (same log + 12:41 PM screenshot).
- [x] **Background accumulation** — Terminated UI, let DeviceActivity fire, reopened, and totals persisted (first build log `…12-33-29…`).
- [ ] **Reauthorization** — Revoke and re-grant Screen Time permission; confirm new tokens still map to existing logical IDs.
- [ ] **Snapshot update** — Capture a new screenshot replacing the zero-total state from 10:33 AM Oct 19.
- [ ] **Log capture** — Save new `.xcresult` files for archival once validation passes.

---

## Code Status (2025-10-19)

- `ScreenTimeRewards/Shared/UsagePersistence.swift` — new v4 implementation (SHA256 hashing, in-memory caches, immediate persistence).
- `ScreenTimeRewards/Services/ScreenTimeService.swift` — updated to use `resolveLogicalID`; merges existing totals in `configureMonitoring` and repopulates `appUsages`. Device QA (12:39:58 log) confirms cold-launch retention.
- `ScreenTimeRewards/Views/LearningTabView.swift` — decomposed into helper builders to avoid SwiftUI compile blowups (ref `Build ScreenTimeRewards_2025-10-20T12-48-02.txt`).
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — continues to update `persistedApps_v3` for background usage; logical IDs now stay stable.
- Builds locally; pending device QA to close Story 0.1.

---

**END OF HANDOFF BRIEF**
