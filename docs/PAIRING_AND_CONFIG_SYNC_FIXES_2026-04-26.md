# Pairing & Config Sync Fixes

**Date:** 2026-04-26
**Branch:** fix/shield-race-and-newapp-pinning
**Status:** Implemented + verified end-to-end on physical devices
**Commits:** `aef81e4`, `780280b`, `f22ee46`, `8709a11`

---

## Overview

Multi-day debugging session that started with "child device displays reward apps in the Learning tab" and unwound into a chain of compounding bugs across child→parent CK upload, parent→child config sync, the v2 secure pairing flow, and Firebase's child-count tracking. By the end of the session, parent ↔ child config sync was working bidirectionally for the first time end-to-end.

What this doc captures: the architecture findings, the bug chain, the fixes, and the open caveats.

---

## Bug 1: Child overwrites parent's edits on every launch

### Symptom
Parent edits an app's category on the parent device → command lands on child → child applies → next refresh on parent shows the OLD category. The parent's edit appeared to "revert" silently.

### Root Cause
The startup chain in `ScreenTimeRewardsApp.swift:174-215` runs three things in sequence on every child app launch:

1. `processPendingCommands()` — applies parent's edit to **Core Data** `AppConfiguration`. ✅
2. `backfillAppConfigurationsForCloudKit()` — reads `usagePersistence.persistedApp.category` (App Group, NOT updated by step 1) and **overwrites Core Data with the OLD value**. ❌
3. `uploadAppConfigurationsToParent()` — sends OLD Core Data state back to CK, wiping the parent's edit. ❌

`ChildConfigCommandProcessor.applyConfiguration` only wrote to Core Data + the schedule store. It never touched `usagePersistence.persistedApp` (the App Group canonical source for `categoryAssignments` rebuild on next launch). So the persisted state always lagged Core Data, and backfill kept resetting Core Data to match persisted.

### Fix
**`ChildConfigCommandProcessor.swift`** — added `applyToUsagePersistence(payload)` to the apply chain. It now:
- Writes the new category + rewardPoints + lastUpdated to `usagePersistence.persistedApp` via `saveApp(...)`. Canonicalizes case via `AppCategory.parse(_:)` so legacy lowercase strings land as canonical capitalized.
- Walks `service.familySelection.applications` to find the matching token, then calls `service.assignCategory(...)` + `service.assignRewardPoints(...)` to update LIVE in-memory `categoryAssignments` so the dashboard reflects the change immediately without a relaunch.

Backfill becomes a harmless no-op since persistedApp now matches Core Data.

---

## Bug 2: Picker re-add doesn't trigger CK upload

### Symptom
Adding a new app on the child device via FamilyActivityPicker (in parent-mode) saved locally but never reached the parent dashboard.

### Root Cause
`AppUsageViewModel.mergeCurrentSelectionIntoMaster` only triggered `uploadAppConfigurationsToParent()` when there were **removed** tokens (`if !removedTokens.isEmpty`). Adds-only saves fell through with no upload.

### Fix
**`AppUsageViewModel.swift`** — `onCategoryAssignmentSave()` now unconditionally calls `backfillAppConfigurationsForCloudKit()` + `uploadAppConfigurationsToParent()` at the end of every picker save (removals and adds alike). Already shipped in commit `aef81e4`.

---

## Bug 3: Case-mismatched category strings silently drop records

### Symptom
After a parent push of a Reward category, the child's dashboard showed reward apps under the Learning tab. Parent's "Reward" tab on its own dashboard appeared empty even though CK held the records.

### Root Cause
`AppUsage.AppCategory` raw values are `"Learning"` / `"Reward"` (capitalized). But `PairingConfigView.swift:840,872` wrote `"learning"` / `"reward"` (lowercase) into Core Data. Many comparators across the code used strict capitalized comparison:

- `restoreFamilySelection` — `AppCategory(rawValue: persistedApp.category)` returned nil → `categoryAssignments[token]` never set → dashboard fell back to `.learning` default.
- `uploadDailyUsageHistoryToParent` guard at line 2981 — `app.category == "Learning" || app.category == "Reward"` skipped the entire app, today's running counter never reached CK.
- `ParentRemoteViewModel` partition + `RemoteDashboardDataAdapter` + daily snapshot aggregator on parent — silently dropped records.

### Fix
**`AppUsage.swift`** — added `AppCategory.parse(_:)` static method for case-insensitive lookup.

All load-bearing comparators across `ScreenTimeService.swift`, `ScreenTimeService+CloudKit.swift`, `ChildConfigCommandProcessor.swift`, `CloudKitSyncService.swift`, `ParentRemoteViewModel.swift`, `RemoteDashboardDataAdapter.swift`, `MutableAppConfigDTO.swift` rerouted through `AppCategory.parse(...)`.

Lowercase writers fixed at the source: `PairingConfigView.swift:840,872`, test seed at `ScreenTimeService.swift:4569`. Outbound CK records and `persistedApp.category` writes now canonicalize before write.

One-time data heal in `restoreFamilySelection`: rewrites any lingering lowercase `persistedApp.category` strings to canonical capitalized form on next launch.

Already shipped in commit `aef81e4`.

---

## Bug 4: Child upload chain hung silently for ~15s+ at iOS QoS

### Symptom
Child startup chain log showed `Found N active AppConfigurations to sync` then nothing. No `Synced app configurations to parent`, no `Synced shield states`, no `Synced daily usage history`. Parent dashboard showed stale data.

### Root Cause
`CKFetchRecordZoneChangesOperation` ran at default `.background` QoS. Under iOS throttling — especially when the child app was attached to the Xcode debugger (1623 of 1751 Darwin notifications missed in the captured log) — the operation's `fetchRecordZoneChangesResultBlock` never fired. The awaited continuation never resumed, hanging the entire sequential upload chain (configs → shields → daily usage are sequential `await`s).

### Fix
**`CloudKitSyncService.swift`** — three changes:

1. Bumped `qualityOfService = .userInitiated` on both fetch operations (in `uploadAppConfigurationsToParent` and `uploadDailyUsageHistoryToParent`).
2. Wrapped each fetch in a 15s timeout guard backed by an actor-isolated resume flag, so a stuck operation can no longer hang the whole chain.
3. Switched `CD_AppConfiguration` recordNames from `"AC-{UUID()}"` to deterministic `"AC-{deviceID}-{logicalID}"`. Without this, a timed-out dedup fetch (`existingByLogicalID` empty) would generate fresh UUIDs every run and accumulate duplicate CK records.

Already shipped in commit `aef81e4`.

---

## Bug 5: v2 secure pairing flow never delivered the parent commands zone share

### Symptom
After re-pairing the child, parent edits still didn't reach the child even though pairing reported success. Parent's `findActiveSharedParentCommandsZone` reported `[owner=accepted]` only — no accepted child participant — even though the user had just paired.

### Root Cause
`SecureChildPairingPayload` (the v2 QR payload schema in `FirebaseValidationService.swift`) had **no `commandsShareURL` field**. The QR payload only carried the monitoring zone share URL. The parent's `createSecurePairingSession` DID create a parent commands zone (line 765) but its share URL was stored only in `sessionData` UserDefaults locally, not in the QR.

`acceptSecureParentPairing` on the child accepted only the monitoring share. It set `commandsZoneID: nil` on `PairedParentInfo`. The legacy v1 `acceptParentShareAndRegister` HAD the commands-share-acceptance code; the v2 flow was an incomplete copy.

So in v2 pairings: child→parent usage upload worked (monitoring share OK); parent→child commands never had a delivery path because the child was never invited to the commands zone.

### Fix
**`FirebaseValidationService.swift`** — added optional `commandsShareURL: String?` to `SecureChildPairingPayload`. `generateChildPairingQRData(...)` accepts and forwards it.

**`DevicePairingService.swift`** — `createSecurePairingSession`:
- Reordered so `createParentCommandsZone()` runs BEFORE `generateChildPairingQRData(...)`.
- Passes the resulting `commandsShareURL` to the QR payload.

**`DevicePairingService.swift`** — `acceptSecureParentPairing`:
- Mirrors the legacy v1 commands-share acceptance: fetches the commands share metadata via `container.fetchShareMetadata`, calls `container.accept(commandsMetadata)`, persists the resulting zone name into `commandsZoneID` on `PairedParentInfo`.
- Logs `✅ Parent commands share accepted: <zoneName>` on success or `⚠️ No commandsShareURL in payload` warning if the field is absent (backward compat with old QR codes).

Shipped in commit `f22ee46`.

---

## Bug 6: Parent's deviceID rotation orphans the commands zone

### Symptom
Even before the v2 pairing fix, the user's parent device had **8** ParentCommands-* zones in its private DB. The child's shared DB held invites to 4 of them (`1F1FE24B`, `917C505F`, `E3DE10BC`, `37BA3724`). The parent was writing all new commands to `ParentCommands-07D51256-...` (its current deviceID) — which the child had no access to.

### Root Cause
`getOrCreateParentCommandsZone` and `createParentCommandsZone` always built the zone name as `"ParentCommands-{DeviceModeManager.shared.deviceID}"` — using the CURRENT deviceID, not the one active at pairing time.

`DeviceModeManager.swift:67-89` (parent code path) deliberately stores deviceID in **UserDefaults only** (with a comment "will be lost on reinstall for parent"). The child uses Keychain. So every parent app reinstall (Xcode rebuild without a backup restore, etc.) rotates the parent's deviceID. Each rotation creates a fresh ParentCommands zone via `createParentCommandsZone`, leaving the previously-shared zones orphaned with stale shares.

Compounding: 7 of the 8 historic zones had **no records** at all (root records gone — likely from a past zone-cleanup pass that deleted records but not the zone itself). The 1 current zone had a share but only the owner as accepted participant.

### Fix
**`CloudKitSyncService.swift`** — `getOrCreateParentCommandsZone` rewrites:

1. Always runs `findActiveSharedParentCommandsZone(...)` first.
2. New `findSharedRootRecord(in:db:)` walks each zone's records via `CKFetchRecordZoneChangesOperation` (10s timeout) to discover the actual shared root record, instead of guessing its name from the rotated deviceID.
3. `findActiveSharedParentCommandsZone(...)` inspects `share.participants` and adopts the first zone that has at least one accepted child participant (i.e. not just a share with the owner).
4. Persists the chosen zone name in UserDefaults (`primaryParentCommandsZoneName_v3`) so the choice survives across launches.
5. Falls back to current-deviceID zone (without persisting) only when no accepted-share zone exists. Logs a `⚠️ This command will NOT reach any child until a fresh pairing is performed` warning so operators know the system is in a degraded state.

`sendConfigCommandToSharedZone`, `shareParentCommandsZoneWithChild`, `sendWebRestrictionCommandToSharedZone` now use the discovered `rootRecordID` from `getOrCreateParentCommandsZone`'s return tuple instead of constructing `"CommandsRoot-{currentDeviceID}"` by string concat.

Shipped in commit `f22ee46`.

### Caveat (1.0.5)
The underlying `DeviceModeManager` design (parent uses UserDefaults only) is still fragile. My fix recovers from rotation when a previously-shared zone with accepted participants exists. But if the parent reinstalls with NO previously-paired children (or the user has a clean install), the next pair attempt will create a fresh zone — and works fine until the next rotation.

For 1.0.5, the proper fix is to persist the parent's deviceID in Keychain (matching the child's existing behavior). The "fresh-start behavior" comment in `DeviceModeManager.swift:67-74` should be revisited — its consequence (silent pairing breakage on reinstall) is far worse than whatever fresh-start scenario it was trying to enable.

---

## Bug 7: Unpair doesn't decrement Firebase's child count

### Symptom
After unpairing a child (from either side), re-pair attempts hit "Failed to pair: Device limit reached. Upgrade to the Family plan." — even though CloudKit-side seats showed open.

### Root Cause
`removePairedParent` (child side) and `unpairChildDevice` (parent side) both cleaned up CloudKit zones via `cleanupZone(...)`. Neither touched Firebase. The `validateChildPairing` Cloud Function counts `families/{familyId}/children` subcollection size to enforce the per-tier device limit. The unpaired child's document persisted, so the count stayed at the limit forever, blocking all future re-pairs.

### Fix
**`firebase-functions/src/family.ts`** — added `removeChildFromFamily` Cloud Function (deployed to production). Idempotent: deletes both `families/{familyId}/children/{childDeviceId}` and `devices/{childDeviceId}` in a batch. Resolves familyId from the device's record if not supplied. Returns `{success: true, alreadyRemoved: true}` if the docs are missing — safe to retry.

**`FirebaseValidationService.swift`** — added Swift caller `removeChildFromFamily(childDeviceId:familyId:)`.

**`CloudKitSyncService.swift`** — `unpairChildDevice` calls `removeChildFromFamily(childDeviceId:, familyId: currentFamilyId)` after CK cleanup. Errors are non-fatal.

**`DevicePairingService.swift`** — `removePairedParent` calls `removeChildFromFamily(childDeviceId: <self>, familyId: nil)` after CK cleanup. Function looks up familyId server-side from the device record. Errors are non-fatal.

Shipped in commits `780280b` (function) + `f22ee46` (Swift wiring).

---

## Bug 8: Child-side parent-mode schedule edits don't sync to parent

### Symptom
User edits daily limits / time windows / linked apps / unlock mode / streak settings via the child's parent-mode UI. Edits saved locally but the parent dashboard never showed the changes.

### Root Cause
6 `onSave` sites across `LearningTabView.swift`, `RewardsTabView.swift`, and `AppUsageDetailViews.swift` (LearningAppDetailView + RewardAppDetailView) all called `scheduleService.saveSchedule(savedConfig)` and locally invalidated shields, but **none triggered an upload to CK**. The child's `uploadAppConfigurationsToParent` already includes `scheduleConfigJSON` / `linkedAppsJSON` / `streakSettingsJSON` in the records — the upload was just never being called from these surfaces.

### Fix
Each affected View got a `propagateLocalScheduleEditToParent()` helper:
- Guards on `isChildDevice && hasPairedParent`.
- Runs `backfillAppConfigurationsForCloudKit()` + `uploadAppConfigurationsToParent()`.
- Logs success/failure per view.

Called from every `onSave` after `saveSchedule`. The picker-save path (`onCategoryAssignmentSave`) was already covered by the earlier upload-on-adds fix.

Shipped in commit `8709a11`.

---

## Architecture findings (worth remembering)

### v2 secure pairing was an asymmetric copy of v1
v1 (`acceptParentShareAndRegister`) accepted both monitoring AND commands shares. v2 (`acceptSecureParentPairing`) only accepted monitoring. The v2 flow was added for Firebase token validation but the commands-share acceptance was forgotten. Easy class of bug to repeat — any time a "v2" of a multi-step flow is added, audit each step.

### One-zone-per-parent-shared-with-all-children pattern
`ParentCommands-{parentDeviceID}` is a SINGLE zone shared with all paired children (multi-tenant). Per-child routing happens via `targetDeviceID` field on each `ConfigurationCommand` record. NOT a per-child zone like `ChildMonitoring-*`. The accumulated 8 historic ParentCommands zones in the user's setup were all from deviceID rotations, not from a per-child design.

### Parent forgets, child remembers
`PairedParentInfo` (child side) stores full pairing-channel coordinates (zoneName, owner, root recordName) and survives in Keychain. The parent has no equivalent `PairedChildInfo` storing the per-child commands zone — it just recomputes from current deviceID. Fragility on parent reinstall.

### CK propagation lag is real, deviceID rotation in dev is constant
Repeated Xcode reinstalls during dev rotated the parent's deviceID 8+ times. Each rotation created a new zone. Most users won't hit this — but the LATENT vulnerability was already there for any production user who reinstalls.

### Firebase + CloudKit can drift apart
Two independent sources of truth (Firebase children count, CloudKit ChildMonitoring zones). If unpair only touches one, they diverge silently and one path will block on stale state. Anywhere we add a write to one, audit the other.

---

## Verification protocol

End-to-end signals to look for after a clean re-pair:

**Parent log (on QR generation):**
```
[CloudKitSyncService] 🔍 Found shared parent commands zone: ParentCommands-... (1 accepted participant(s))
[CloudKitSyncService] ✅ Adopted active shared zone (deviceID likely rotated): ...
[CloudKitSyncService] Setting parent reference to: <discovered root recordName>
[CloudKitSyncService] [PER-RECORD] ✅ Record saved
```

**Child log (on cold launch after parent edit):**
```
[ChildConfigCommandProcessor] Found N pending command(s) in shared zone
[ChildConfigCommandProcessor] ===== Processing Full Config Command (Shared Zone) =====
[ChildConfigCommandProcessor] Configuration applied successfully
[ChildConfigCommandProcessor] ✅ Mirrored to UsagePersistence: <name> → <Category>, <N>pts/min
[ScreenTimeService] Assigned category <Category> to <name>
[ScreenTimeService] ✅ Synced N goal configs to extension
```

**Child log (after local schedule edit on parent-mode):**
```
[LearningAppDetailView] ✅ Pushed local schedule edit to parent
   OR
[RewardAppDetailView] ✅ Pushed local schedule edit to parent
[CloudKitSyncService] ✅ Successfully uploaded N full AppConfigurations to parent's zone
```

If any of these markers is missing in a verification run, the corresponding bug class has resurfaced.

---

## Open caveats / 1.0.5 work

1. **Parent deviceID persistence** — `DeviceModeManager.swift:67-74` clears the parent's Keychain entry on every launch ("fresh-start behavior"). This is the underlying cause of bug #6. Move parent deviceID to Keychain (synchronizable across iCloud Keychain) to eliminate the rotation risk entirely.

2. **Conflict resolution stub** — `ChildConfigCommandProcessor.checkForConflicts` always returns `(parentWins: true)`. Timestamp-based last-writer-wins is wired up to use (`payload.parentModifiedAt` is logged but never compared to local `appConfig.lastModified`). User decided this is acceptable for current product UX since real conflict windows are narrow. Revisit if a real user reports a child-mode edit got overwritten.

3. **Orphan ParentCommands zones** — the user's parent has 7 unused ParentCommands zones in private DB (CK quota leak). Cleanup would walk all `ParentCommands-*` zones, identify ones with no shared root record AND not the current persisted choice, and delete via `db.deleteRecordZone`. Not breaking anything; just clutter.

4. **Legacy `update_configuration` send path is dead code** — `RemoteAppConfigurationView`'s toggle-enabled, toggle-blocking, and edit handlers still call `sendConfigurationToChild(deviceID:, mutableConfig:)` which writes a Core Data `ConfigurationCommand` with `commandType="update_configuration"`. The child's `processPendingCommands` only matches `update_full_config` and `update_web_restrictions` from the shared zone. Those legacy commands are silently ignored. Either delete the view or rewire its handlers to use `sendConfigCommandToSharedZone`.

5. **No CKQuerySubscription for ConfigurationCommand on child** — child only picks up parent commands at app foreground or BGTask (~30 min). Adding a subscription would deliver commands via push within seconds. Latency improvement, not a correctness issue.
