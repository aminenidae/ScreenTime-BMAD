# Development Handoff Brief
**Date:** 2025-10-22 (UI Shuffle Fix – All Issues Resolved)
**Project:** ScreenTime-BMAD / ScreenTimeRewards
**Status:** ✅ All UI shuffle issues resolved — learningApps/rewardApps now use deterministic snapshot-based ordering with stable token hash IDs

---

## Executive Summary

- `UsagePersistence` now hashes each `ApplicationToken`'s internal `data` payload (128 bytes) with SHA256. The resulting `token.sha256.<digest>` is stored in `tokenMappings_v1` and maps back to the logical ID (bundle ID when available, otherwise generated UUID).
- `ScreenTimeService` uses the new `resolveLogicalID` helper during both `loadPersistedAssignments` and `configureMonitoring`, ensuring Set order changes do not shuffle minutes/points between learning cards.
- Persistent usage records remain in `persistedApps_v3`; the DeviceActivity extension writes into the same store and benefits from the stable logical IDs.
- **Cold launch retention ✅** — News/Books scenario retains minutes/points after relaunch.
- **Background accumulation ✅** — Extension wrote while UI closed; totals persisted on reopen.
- **UI Shuffle Issues ✅** — All UI shuffle issues completely resolved with deterministic snapshot-based ordering.

---

## Latest Findings (Oct 22, 2025)

- All critical issues identified in previous builds have been resolved.
- UI shuffle after "Save & Monitor" completely eliminated through snapshot-based ordering with stable token hash IDs.
- Live usage refresh working correctly - UI updates immediately when usage changes without requiring app restart.
- Cold launch retention verified - usage data persists correctly across app restarts.
- Background accumulation working - DeviceActivity extension correctly records usage while app is terminated.
- Unlock All Reward Apps button visibility fixed - only shows when reward apps are actually shielded.
- Learning tab compile timeout resolved - refactored into helper builders for clean compilation.
- All validation tests passed with no remaining shuffle issues.

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

## Task L - Post-Save Ordering Fix (2025-10-21) - COMPLETED ✅

Despite the snapshot refactor completed on Oct 20, we still observed card reordering immediately after `CategoryAssignmentView` dismisses. Logs showed `sortedApplications` rebuilding, but the published snapshot arrays repopulate in a different sequence. Restarting the app corrected the order, which meant persistence was solid but runtime shuffle stemmed from the view model/service refresh pipeline.

**Root Causes Identified and Fixed**:
1. **Service Sequencing Issue**: `ScreenTimeService` was rehydrating `familySelection.applications` using dictionary order rather than a canonical list. When we merge picker results, the union of new + cached tokens lacked a stored sort index.
2. **ViewModel Sequencing Issue**: `updateSortedApplications()` depended on `masterSelection.sortedApplications(using:)`, but `masterSelection` was replaced only after `mergeCurrentSelectionIntoMaster()`. During `onCategoryAssignmentSave()` we triggered `refreshData()` before the merge, so the first snapshot rebuild used stale ordering.
3. **Snapshot Update Timing**: The service-side comparator was stable, but snapshot arrays were being rebuilt at the wrong time in the save sequence, causing temporary ordering inconsistencies.
4. **Snapshot ID Re-identification**: Snapshots were using logicalID as their ID, which could change during persistence resolution, causing SwiftUI to re-identify rows incorrectly.

**Resolution (Task L - 2025-10-21)**:
1. **Fixed ViewModel Sequencing**: Modified `onCategoryAssignmentSave()` to update sorted applications BEFORE calling `configureMonitoring()` and ensure `masterSelection` reflects the merged selection before any refresh occurs.
2. **Enhanced Snapshot Updates**: Updated `mergeCurrentSelectionIntoMaster()` to immediately update sorted applications after master selection changes.
3. **Stabilized Snapshot IDs**: Updated `LearningAppSnapshot` and `RewardAppSnapshot` to use stable token hashes as their `id` property instead of logicalID, preventing row re-identification when logicalIDs change during persistence resolution.
4. **Added Diagnostic Logging**: Enhanced `updateSnapshots()` with targeted diagnostics to verify ordering stability by logging logical IDs and token hashes before and after save operations.
5. **Ensured Deterministic Sorting**: Confirmed `FamilyActivitySelection.sortedApplications(using:)` uses stable token hash-based sorting that guarantees consistent iteration order.
6. **Fixed Timing Issues**: Ensured snapshot updates occur at the correct time in the save sequence to prevent temporary ordering inconsistencies.

**Validation**:
- ✅ No card reordering after saving category assignments
- ✅ Pull-to-refresh preserves order on both tabs
- ✅ Logs demonstrate stable logical ID and token hash ordering across save cycles
- ✅ Manual testing with 3+ Learning apps shows consistent ordering pre/post save without restart

---

## What's Next (Fix + Validation Checklist)

- [x] **Fix persistence overwrite** — Update `configureMonitoring` / `UsagePersistence` to merge with existing records instead of resetting `totalSeconds`/`earnedPoints`. ✅ Verified via logs `Run-ScreenTimeRewards-2025.10.19_12-39-58--0500.xcresult`.
- [x] **Cold launch retention** — Re-ran News/Books scenario (60 s + 120 s), relaunched, and confirmed minutes/points remain on correct cards (same log + 12:41 PM screenshot).
- [x] **Background accumulation** — Terminated UI, let DeviceActivity fire, reopened, and totals persisted (first build log `…12-33-29…`).
- [x] **Remove displayName fallback** — Removed the displayName fallback in `UsagePersistence.resolveLogicalID` to ensure privacy-protected apps always receive unique logical IDs, preventing potential shuffle regressions (Task K completed).
- [x] **Post-Save Ordering Fix** — Fixed the remaining UI shuffle issue that occurred immediately after saving category assignments (Task L completed).
- [x] **Reauthorization** — Revoke and re-grant Screen Time permission; confirm new tokens still map to existing logical IDs.
- [x] **Snapshot update** — All snapshots now use stable token hash IDs for consistent ordering.
- [x] **Log capture** — All validation tests completed with passing results.

---

## Code Status (2025-10-22)

- `ScreenTimeRewards/Shared/UsagePersistence.swift` — new v4 implementation (SHA256 hashing, in-memory caches, immediate persistence).
- `ScreenTimeRewards/Services/ScreenTimeService.swift` — updated to use `resolveLogicalID`; merges existing totals in `configureMonitoring` and repopulates `appUsages`. Device QA confirms cold-launch retention.
- `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` — updated sequencing for `onCategoryAssignmentSave()` and `mergeCurrentSelectionIntoMaster()` to ensure deterministic ordering. Snapshots now use stable token hash IDs.
- `ScreenTimeRewards/Views/LearningTabView.swift` — decomposed into helper builders to avoid SwiftUI compile blowups.
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` — continues to update `persistedApps_v3` for background usage; logical IDs now stay stable.
- All builds successful; all validation tests passed; no remaining shuffle issues.

---

**END OF HANDOFF BRIEF**