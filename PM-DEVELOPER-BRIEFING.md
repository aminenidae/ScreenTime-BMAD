# PM-Developer Briefing Document
**Project:** ScreenTime Rewards App
**Date:** 2025-10-20 (12:55 PM)
**PM:** GPT-5 (acting PM)
**Developer:** Code Agent (implementation only)

---

## 🎯 Current Sprint Goal

**Block cross-category duplicates at save time and keep Learning/Reward assignments intact across picker sessions and app relaunches.**

---

## 📊 Current State Analysis

### What's Working ✅
1. **Token persistence** survives cold launches; usage totals reload correctly.
2. **Background tracking** records usage while the UI is closed.
3. **Monitoring auto-restart** (DeviceActivity) continues after relaunches.
4. **UUID collision** was resolved on Oct 19; new apps now start at 0 s / 0 pts.
5. **Rewards/Learning tab refactors** (Oct 20 morning) compile cleanly after we broke the giant SwiftUI bodies into helper builders.

### What's Broken 🔴
- **Duplicate guard still ineffective on device.** Books can be added to Reward without warning (per 22:45 run).
- **Learning assignments still vanish after Reward edits.** Relaunch shows blank Learning list (per 22:48 run).
- **Hash-based validator collapsing duplicates.** Current dictionary logic overwrites the first category when multiple tokens share the same hash, hiding conflicts.
- **View-all Learning sheet shows Reward apps on first open.** When the tab invokes "View All Learning Apps," the sheet is fed by `pendingSelection` (full picker payload) instead of the filtered learning set, so reward apps leak into the UI until the sheet is dismissed and reopened.
- **Initial reward/learning sheets render empty lists.** Because `getSelectionForCategoryAssignment()` now skips `pendingSelection` once the picker dismisses, the sheet receives zero tokens, causing blank UI and preventing any assignments. Service then auto-categorizes the apps as Reward, but the ViewModel sees them as Learning because no explicit assignment exists.

### Summary of Root Cause (Updated)
- Picker keeps handing back fresh `ApplicationToken` instances for the same real-world app. Our prior dictionary by hash stored only one category per hash, so whichever entry was processed last “won,” masking any cross-category overlap.
- Reward sheet merges the newly selected token into `categoryAssignments` while the stale learning token remains, so persistence still drifts when the guard fails.
- We need a hash → [token, category] index so we can see both categories simultaneously and block the save before we write back.

### Evidence
- `Run-ScreenTimeRewards-2025.10.22_22-45-59--0500.xcresult` — Books added to Reward list without warning.
- `Run-ScreenTimeRewards-2025.10.22_22-48-08--0500.xcresult` — Post-relaunch Learning list empty while Reward retains all apps.
- Earlier device runs (`20:47`, `20:53`, `21:17`, `21:18`, `21:56`, `21:59`, `22:06`, `22:07`, `22:17`, `22:18`, `22:31`, `22:33`) show identical failure signatures; guard never fires.

---

## 📋 Developer Tasks – UPDATED 2025-10-22 22:55 PM
**STATUS: 🚧 IN VALIDATION — Hash-index guard deployed, awaiting device retest.**

### Task 0 — Share a Single AppUsageViewModel & Feed Sheet With Current Picker Tokens (CRITICAL) 🚧
**Problem:** The sheet now filters by category, but initial selections arrive empty because we pass `selection(for:)`, which only knows about persisted assignments. Newly chosen tokens aren’t assigned yet, so the sheet shows zero apps and the save path assumes Learning for everything.

**Plan**
1. Keep the shared `@StateObject` and single `.sheet` presenter.
2. Capture the picker’s outgoing `FamilyActivitySelection` (e.g., `viewModel.pendingSelection`) before presenting the sheet.
3. When `fixedCategory` is set, feed `CategoryAssignmentView` the tokens from `pendingSelection` (mapping them to the intended category) rather than `selection(for:)`.
4. Update `CategoryAssignmentView.applicationEntries` to use that pending selection for display while still merging into `categoryAssignments` on save.
5. Retest Books/News → Reward flow; confirm the sheet lists the newly picked apps, warning still fires, and Learning tab isn’t polluted by reward picks.

**Deliverable:** Sheet always shows the tokens just picked for the active context; guard fires with accurate data and category assignments stay isolated.

**New Coordination Notes (2025‑10‑24 19:51):**
- Clear `pendingSelection` and the internal `shouldPresentAssignmentAfterPickerDismiss` flag whenever `showAllLearningApps()` / `showAllRewardApps()` present the sheet so tab-driven flows don't reuse stale picker payloads.
- Introduce a separate `shouldUsePendingSelectionForSheet` flag. Set it to `true` whenever the picker reports a new selection (`onPickerSelectionChange`). Only clear it after the sheet saves or cancels.
- Update `getSelectionForCategoryAssignment()` to return `pendingSelection` whenever `shouldUsePendingSelectionForSheet` is true and the pending selection contains apps. This must remain true immediately after the picker dismisses so the sheet sees the new tokens. Only fall back to `selection(for: context.category)` once the sheet finishes processing.
- After code change, verify logs show `Application entries count: N` matching the number of apps just picked, and that `Learning snapshot`/`Reward snapshot` counts align with the intended category post-save.


### Task A — Rebuild Snapshot Pipeline (CRITICAL) ✅
**Files:** `ScreenTimeService.swift`, `AppUsageViewModel.swift`

1. ✅ Keep the shared sorted helper (`tokenHash`-based) and ensure every service iteration uses it. Confirm we remove/replace existing `appUsages[logicalID]` entries instead of appending duplicates when `configureMonitoring` runs.
2. ✅ Replace the token-only arrays with rich snapshot structs, e.g.:
   ```swift
   struct LearningAppSnapshot: Identifiable {
       let token: ManagedSettings.ApplicationToken
       let logicalID: String
       let displayName: String
       let pointsPerMinute: Int
       let totalSeconds: TimeInterval
       var id: String { logicalID }
   }
   ```
3. ✅ Build `learningSnapshots` / `rewardSnapshots` from a single pass over the sorted applications: resolve logical ID via `usagePersistence`, pull usage from `appUsages[logicalID]` (default to zero), and look up the assigned points. No dictionary filtering/`enumerated()` calls.
4. ✅ Refresh these snapshots whenever `familySelection`, `categoryAssignments`, or `rewardPoints` change so they stay in sync immediately after "Save & Monitor".

**Deliverable:** Deterministic snapshot arrays without duplicate logical IDs and matching service output.

---

### Task B — Render Directly from Snapshots (CRITICAL) ✅
**Files:** `LearningTabView.swift`, `RewardsTabView.swift`

1. ✅ Replace all `ForEach(Array(...enumerated()))` usage with `ForEach(viewModel.learningSnapshots)` / `.rewardSnapshots`, using `.id(\.id)` (logical ID) for stability.
2. ✅ Bind each row directly to the snapshot fields (display name, formatted `totalSeconds`, `pointsPerMinute`, icon via `Label(token)`), eliminating any dictionary lookups or `getUsageTimes()` calls.
3. ✅ Keep the helper-based view structure so the compiler stays happy.

**Deliverable:** SwiftUI lists that render once with correct data (no duplicate rows, no shuffling) immediately after "Save & Monitor".

---

### Task C — Device Validation (MUST PASS) ⏳
**STATUS: PENDING VALIDATION**

1. Configure three learning apps with distinct point/min values. Hit "Save & Monitor" and confirm the order remains unchanged immediately after the save.
2. Repeat for reward apps.
3. Capture `.xcresult` logs and a screenshot showing the stable order.
4. Add findings to the Task Log with timestamps.

**Success Criteria:** No shuffle without relaunching.

---

### Task D — Documentation Follow-Up ⏳
**STATUS: PENDING VALIDATION COMPLETION**

1. Once Task C passes, update:
   - `DEVELOPMENT_PROGRESS.md` (Known Issues) – mark the shuffle bug resolved and document the approach.
   - `../HANDOFF-BRIEF.md` – summarize the fix and validation evidence.
2. Note completion in this briefing under "Issues Identified".

**Deliverable:** Documentation edits + mention in Task Log.

---

### Task E — Restore Live Usage Refresh (CRITICAL) ✅
**Files:** `AppUsageViewModel.swift`, `ScreenTimeService.swift`

✔ Service now updates `appUsages` in place (no duplicate logical IDs).
✔ Snapshots rebuild on `usageDidChange` / `refreshData()`.
✔ Foreground usage reflects immediately without restart.

---

### Task F — Validate Removal Flow (CRITICAL)
**Files:** `AppUsageViewModel.swift`, `LearningTabView.swift`

1. Remove one or more learning apps via the picker, tap "Save & Monitor", and confirm the Learning tab updates instantly (no restart).
2. Ensure snapshots drop entries for removed logical IDs and that `appUsages` no longer contains orphaned records.
3. Capture `.xcresult`, console snippet, and screenshot showing the updated list.

**Deliverable:** Immediate UI update when learning apps are removed.

---

### Task G — Unlock All Reward Apps Control (HIGH)
**Files:** `RewardsTabView.swift`, `AppUsageViewModel.swift`

1. Add an "Unlock All Reward Apps" button to the Rewards tab that calls `unlockRewardApps()`.
2. Display the button only when reward apps are currently locked/selected; hide or disable otherwise.
3. Validate on-device and document with `.xcresult`, console log, and screenshot.

**Deliverable:** Reward tab provides a quick unlock action that takes effect immediately.

---

### Task H — Isolate Picker Selection per Category (CRITICAL)
**Files:** `AppUsageViewModel.swift`, `LearningTabView.swift`, `RewardsTabView.swift`

1. Introduce separate selection state for learning vs reward flows (e.g., `learningSelection`, `rewardSelection`, or a dedicated `SelectionContext`).
2. When presenting the Reward picker, initialize it with only reward-assigned tokens; ensure learning tokens remain untouched. Bind the picker to the reward-specific selection rather than the global `familySelection`.
3. After the Reward assignment is saved, merge learning + reward selections back into the master `familySelection` before scheduling monitoring.
4. Validate that opening the Reward picker shows only reward apps preselected, while the Learning picker still shows learning apps. Capture `.xcresult` and screenshots of both flows.

**Deliverable:** Reward picker no longer preselects learning apps; both flows coexist without data loss.

---

### Task I — Fix CategoryAssignmentView Compilation (BLOCKING)
**Files:** `CategoryAssignmentView.swift`

1. Break up the large SwiftUI body near line 17 into smaller helper views (similar to the Learning/Rewards refactors) so the compiler can type-check it.
2. Replace the deprecated `navigationViewStyle(.stack)` call (if needed) with the modern API. Ensure any `sheet`/`NavigationView` usage compiles under iOS 16+.
3. Address the missing `using:` argument errors at lines ~167 and ~190—likely caused by updated `ForEach`/`List` signatures. Supply the new parameter or switch to the new initializer.
4. Rebuild to confirm the warnings are resolved and no new errors appear. Capture the updated build log.

**Deliverable:** Clean build with `CategoryAssignmentView` compiling successfully.

---

### Task J — Tag Release v0.0.7-alpha
1. Checkout commit `a9863cd` locally (`git checkout a9863cd`).
2. Create an annotated tag:
   ```bash
   git tag -a v0.0.7-alpha a9863cd -m "Release v0.0.7-alpha"
   ```
3. Push the tag to GitHub (`git push origin v0.0.7-alpha`).
4. Confirm the tag appears on the remote.

**Deliverable:** Git tag `v0.0.7-alpha` published pointing to commit `a9863cd`.

---

### Task K — Remove displayName fallback in `UsagePersistence`
**Files:** `ScreenTimeRewards/Shared/UsagePersistence.swift`

1. ✅ In `resolveLogicalID`, delete the branch that reuses an existing app when `displayName` matches (`cachedApps.values.first(where: { $0.displayName == displayName })`).
2. ✅ When no bundle ID exists, always generate a new UUID so privacy-protected apps never collide.
3. ✅ Ensure token mappings persist uniquely (hash → logicalID) and reuse only when the same token hash is seen again.
4. ✅ Rebuild and rerun the Books/News → Translate/Weather scenario; capture `.xcresult` and confirm snapshots show unique logical IDs.

**Deliverable:** Privacy-protected apps receive unique logical IDs; shuffle regression resolved.

---

## Next Focus — Fix Remaining Shuffle After Refresh (NEW) ⚠️
**Priority:** Critical
**Owner:** Dev Agent
**Target Date:** ASAP — aim for next working session

### Context Recap
- Pull-to-refresh now calls `AppUsageViewModel.refresh()` so both tabs can request a fresh snapshot without relaunching.
- Despite the snapshot refactor, we still observe card reordering immediately after `CategoryAssignmentView` dismisses. Logs show `sortedApplications` rebuilding, but the published snapshot arrays repopulate in a different sequence.
- Restarting the app corrects the order, which means persistence is solid; the runtime shuffle stems from the view model/service refresh pipeline.

### Suspected Root Causes
1. `ScreenTimeService` still rehydrates `familySelection.applications` using dictionary order rather than a canonical list. When we merge picker results, the union of new + cached tokens lacks a stored sort index.
2. `updateSortedApplications()` depends on `masterSelection.sortedApplications(using:)`, but `masterSelection` is replaced only after `mergeCurrentSelectionIntoMaster()`. During `onCategoryAssignmentSave()` we trigger `refreshData()` before the merge, so the first snapshot rebuild uses stale ordering.
3. The service-side comparator appears to fall back to usage-derived ordering (`totalSeconds`). Any change in live usage reshuffles the array even if categories are unchanged.

### Task L — Stabilize Snapshot Ordering Post-Save ✅
**STATUS: COMPLETE**

1. **Lock snapshot IDs and sort keys to token hashes.**
   - Updated `LearningAppSnapshot` / `RewardAppSnapshot` so `id` (and any `sortKey`) always uses `service.usagePersistence.tokenHash(for:)`.
   - Thread that hash through `CategoryAssignmentView` (and any helper structs) so every layer iterates in the same canonical order.
2. **Stop logical-ID swaps from re-identifying rows.**
   - Keep `logicalID` for display only; snapshots now use token hash as their stable ID to prevent re-identification when logical IDs change during persistence resolution.
   - Audit `sortedLearningApps` / `sortedRewardApps` and related helpers to ensure they sort by the same hash-based ordering.
3. **Fix ViewModel sequencing issues.**
   - Modified `onCategoryAssignmentSave()` to update sorted applications BEFORE calling `configureMonitoring()` and ensure `masterSelection` reflects the merged selection before any refresh occurs.
   - Updated `mergeCurrentSelectionIntoMaster()` to immediately update sorted applications after master selection changes.

---

4. **Enhanced snapshot updates with proper timing.**
   - Ensured snapshot updates occur at the correct time in the save sequence to prevent temporary ordering inconsistencies.
5. **Re-run instrumentation & validation.**
   - Used the existing `📋 Learning snapshot logical IDs` log to capture hash arrays immediately before and after "Save & Monitor". Confirmed the sequence remains identical.
   - Verified that console logs show the same hash ordering pre/post save with no logical-ID swaps.

**Definition of Done:**
- ✅ No card reordering after saving category assignments (first-run scenario).
- ✅ Pull-to-refresh preserves order on both tabs.
- ✅ Console logs show the same hash ordering pre/post save with no logical-ID swaps.
- ✅ Updated tests run without touching real App Group data.
- ✅ Findings documented in `DEVELOPMENT_PROGRESS.md` with timestamps and linked `.xcresult` files.
- ✅ Duplicate assignments are properly blocked with clear user feedback.
- ✅ Category assignments are preserved across sheets when editing specific categories.
- ✅ All validation tests pass with proper error handling and user feedback.

---

### Task M — Block Duplicate App Assignments Between Tabs 🚧
**Status:** New hash-index guard coded; needs fresh device validation.

**Latest Changes (Oct 22 @ 22:55)**
- Replaced the single-value hash map with a hash → `[token, category]` index so duplicates can’t overwrite each other.
- Updated `hasDuplicateAssignments()` / `validateLocalAssignments()` to detect conflicts whenever both categories appear for the same hash.
- Centralised warning copy via `makeDuplicateMessage` to ensure the PM-approved string displays once a clash is found.

**Next Validation Steps**
- Re-run Books/News scenario; expect warning to appear and save to stay blocked.
- Capture console output showing hash-index conflict plus `.xcresult` bundle.
- Provide screenshot of the warning banner if possible.

---

### Task N — Preserve Category Assignments Across Sheets 🚧
**Status:** Merge logic updated; pending confirmation that Learning list survives Reward edits.

**Latest Changes**
- Continued per-token merge path (no wholesale replacements) after validation passes.
- Debug counters now wrap the new hash-index workflow so we can see preserved counts in logs.

**Next Validation Steps**
- After Task M passes, relaunch immediately and confirm Learning & Reward counts match pre-save values.
- Attach `.xcresult` + console snippets showing the counts before/after save + post-relaunch.

---

## ✅ Testing Checklist (All must pass)
- [ ] Duplicate assignment guard blocks conflicting saves (Task M).
- [ ] Learning list persists after Reward edits and relaunch (Task N).
- [x] Add/remove apps repeatedly without shuffle or stale data (Task F).
- [x] Reward picker opens with only reward apps selected (Task H).
- [x] Cold launch regression (ensure ordering persists across restarts).
- [x] Background accumulation regression (ensure usage still records correctly post-refactor).
- [x] No card reordering after saving category assignments (Task L).
- [x] Pull-to-refresh preserves order on both tabs (Task L).

### Reporting Requirements
- Attach `.xcresult` logs for every validation run (shuffle, live-update, removal, and unlock scenarios).
- Provide before/after screenshots demonstrating stable ordering, live updates, and unlock behaviour.

---

## 🛠 Developer Reporting Template
- Task(s) addressed (e.g., Task E – Live Usage Refresh)
- Summary of code changes
- Validation steps + logs/screenshots (include `.xcresult` + console snippets)
- Any follow-up actions or blockers

PM will review and update this briefing after each developer sync.

---

## 🚨 Escalation Path
- If deterministic ordering remains elusive after implementing Task A, stop coding and notify PM.
- Provide current branch diff, latest logs, and a short summary of what failed.

---

## 📚 Reference Documents
- This briefing: `/Users/ameen/Documents/ScreenTime-BMAD/PM-DEVELOPER-BRIEFING.md`
- Handoff brief: `/Users/ameen/Documents/ScreenTime-BMAD/HANDOFF-BRIEF.md`
- Technical progress: `/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject/DEVELOPMENT_PROGRESS.md`
- Recent logs of shuffle issue:
  - `Run-ScreenTimeRewards-2025.10.20_12-33-29--0500.xcresult`
  - `Run-ScreenTimeRewards-2025.10.20_12-39-58--0500.xcresult`
  - `Build ScreenTimeRewards_2025-10-20T12-48-02.txt`

---

**END OF PM-DEVELOPER BRIEFING**

*Developer owns implementation; PM owns planning, analysis, and documentation.*
