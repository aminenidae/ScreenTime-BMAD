# CK Resync BGTask — Child→Parent Periodic Sync

**Branch:** `fix/pairing-subscription-sync`
**Date:** 2026-04-22
**Files:**
- `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ChildCKResyncService.swift` (NEW)
- `ScreenTimeRewardsProject/ScreenTimeRewards/AppDelegate.swift` (+5 lines)
- `ScreenTimeRewardsProject/ScreenTimeRewards/Info.plist` (+1 BGTask identifier)
- `ScreenTimeRewardsProject/ScreenTimeActivityExtension/ExtensionCloudKitSync.swift` (diagnostic logs)

---

## Problem

Parent dashboard shows stale (or zero) usage on days when:
- The child's main app is not opened, AND
- The kid uses tracked apps but never crosses one of the extension's 10 hard-coded "slot boundaries" while a reward app is actively running.

### Why
`ExtensionCloudKitSync.syncUsageToParent` only runs from `eventDidReachThreshold` in the DeviceActivity extension. Inside that function, a slot-token gate suppresses all calls except the **first** event in each of 10 fixed daily windows (06:00, 08:00, 10:00, 12:00, 14:00, 16:00, 18:00, 20:00, 22:00, 23:59).

If no threshold event fires inside a slot window (kid stops using a tracked app before the window opens, or only uses learning apps that don't fire reward-app thresholds), **that slot's sync silently never happens**. There is no timer, no catch-up, no replay.

The main-app foreground path (`uploadDailyUsageHistoryToParent` in `CloudKitSyncService`) works correctly — but only when the child opens the app.

### Discovery sequence (Apr 22)
1. Extension log showed `Couldn't get container configuration … "iCloud.com.i6dev.ScreenTimeRewards"` — turned out to be pre-fix binary log lines mixed with post-fix ones.
2. Added 5 diagnostic log points to `ExtensionCloudKitSync.swift` (entry, slot decision, App Group state, prepared records, structured failure with `CKError` code).
3. At 19:59:38 the next `RECORDED` event landed — log showed `slot decision min=1199 currentSlot=1080 lastToken=…1080 currentToken=…1080`. Translation: the function fired at 19:59 (one minute before the 20:00 boundary), so it correctly took the "already synced" branch.
4. Kid stopped using the app at 19:59 → no event crossed 20:00 → 20:00 slot was silently skipped.
5. Confirmed the slot system is event-gated, not time-gated. This is the root design flaw, not a bug in the slot math.

---

## Implemented fix (Option B — strict redline: zero monitoring touch)

A new **dedicated, single-purpose** BGTask: `com.screentimerewards.ck-resync`.

### Why a new BGTask, not bootstrap of the existing `usage-upload`?
Three options were on the table:

| Option | What | Monitoring impact |
|---|---|---|
| A | Bootstrap existing `com.screentimerewards.usage-upload` (1-line `AppDelegate` add) | Indirect: handler calls `performMonitoringMaintenanceIfNeeded` → may call `restartMonitoring` every 30 min |
| **B** | **New dedicated `com.screentimerewards.ck-resync` task — pure CK upload, never touches monitoring** | **None** |
| C | (A) plus stripping monitoring maintenance from the existing handler | Permanently disables that monitoring refresh path (also a touch) |

User redline: "**don't touch ANYTHING related to usage tracking and monitoring**." → **Chose B**.

### What `ChildCKResyncService` does
- Identifier: `com.screentimerewards.ck-resync`
- Registered in `AppDelegate.didFinishLaunching` immediately after `ChildBackgroundSyncService.registerBackgroundTasks()`
- Bootstrapped on every cold launch (idempotent — same-identifier `submit` replaces any pending request)
- First fire: ~60s after launch
- Cadence: every ~30 min, self-rescheduling
- Reschedules **before** running uploads so a thrown error can't break the chain
- Skips silently if `DevicePairingService.hasValidPairing()` returns false
- Calls only:
  1. `CloudKitSyncService.shared.uploadDailyUsageHistoryToParent()`
  2. `CloudKitSyncService.shared.uploadShieldStatesToParent()`

### What it deliberately does NOT do
- Never reads or rebuilds extension App Group `ext_usage_*` keys
- Never calls `restartMonitoring`, `performMonitoringMaintenanceIfNeeded`, `readExtensionUsageData`, `refreshFromExtension`, or anything in `ScreenTimeService`
- Never touches Core Data `UsageRecord` rows or the offline queue
- Never modifies threshold scheduling, sliding window, or shield checks
- Does not bootstrap `com.screentimerewards.usage-upload` — that task remains exactly as it was (still un-bootstrapped, still dormant, zero behavior change)

---

## Honest caveats — read before evaluating test results

### 1. "Every 30 min" is a request, not a guarantee
`BGProcessingTaskRequest.earliestBeginDate` is the **earliest** iOS may run the task. Actual fire time depends on:
- Background App Refresh enabled (system-wide and per-app)
- Power state (Low Power Mode delays)
- Network availability (we set `requiresNetworkConnectivity = true`)
- Recent BG budget for this app

Typical when conditions are favorable: a few minutes after the earliest date. Worst case: hours, or skipped until next launch.

### 2. The data uploaded is whatever `UsagePersistence` last persisted
`uploadDailyUsageHistoryToParent` reads from `UsagePersistence.loadAllApps()`. The **main app** writes that snapshot via `ScreenTimeService.readExtensionUsageData()` (monitoring code, off-limits per redline). The extension itself does not write to `UsagePersistence`.

**Implication:** if the main app hasn't been opened in 4 hours and the extension has been recording, the BGTask uploads the 4-hour-old snapshot, not the live extension data.

### 3. What's actually improved vs. before

| Scenario | Before | After |
|---|---|---|
| Kid uses reward app crossing slot boundaries | Extension sync fires (already worked) | Same |
| Kid uses tracked app, no event crosses a slot, main app never opens | No sync | **No new info** — BGTask uploads stale `UsagePersistence` snapshot |
| Main app opened recently, then closed; kid keeps using apps | Snapshot uploaded once on foreground, then static | **BGTask re-uploads same snapshot every ~30 min** (no new info) |
| Main app opened today | Foreground upload succeeds (today) | Foreground upload succeeds + periodic re-confirms |
| Shield state changes silently in extension | Lost until main app opens | **BGTask uploads shield state every ~30 min** |

The BGTask is genuinely useful for **shield state freshness** and **safety-net re-uploads**. It does **not**, by itself, deliver "real-time usage every 30 min on the parent." Achieving that would require the extension to push fresh data — see "Future options" below.

### 4. Diagnostics
- BGTask handler uses `print` (not extension `debugLog`) — visible in Xcode console while the device is debugged. Look for `[ChildCKResyncService]` lines.
- Extension diagnostic logs added during this session remain in `ExtensionCloudKitSync.swift` and continue to write to `extension_debug_log` in App Group.

### 5. Add-to-target reminder
The new file `ChildCKResyncService.swift` was created on disk but Xcode won't compile it until added to the `ScreenTimeRewards` target in the project navigator. Right-click `ScreenTimeRewards/Services/` → Add Files → select `ChildCKResyncService.swift` → ensure only `ScreenTimeRewards` target is checked.

---

## Future options (NOT implemented — discussed Apr 22)

### Option F1 — Tighten extension slots from 2h to 15 or 30 min
1-line edit in `ExtensionCloudKitSync.swift`: replace the 10-element `slotMinutes` array with a 96- or 48-element array.

| Pros | Cons |
|---|---|
| Real-time-ish | Still event-gated — same dead-zone problem if kid isn't actively using a tracked app |
| No code-architecture change | More CK calls per active hour |
| No monitoring touch | Doesn't help when the kid simply isn't using the device |

### Option F2 — Replace slot gate with a time throttle (RECOMMENDED if F1 not enough)
Replace `lastSlotToken == currentSlotToken` check with: "skip if last successful sync < N minutes ago, where N = 3."

| Pros | Cons |
|---|---|
| Real-time feel during active use | Up to ~480 CK saves/day (vs. 70 today) — still inside iCloud per-user limits |
| Failed sync naturally retries on next event | Still event-gated (no event = no sync) |
| No monitoring touch | None significant |

### Option F3 — Fire on every threshold event (NOT RECOMMENDED)
Delete the slot gate entirely.

| Pros | Cons |
|---|---|
| Maximum freshness | ~10,000 CK saves/day per child → real risk of `CKError.requestRateLimited` and downstream throttling |
| | Per-event synchronous prep adds 1–5 ms × every event → soft risk of iOS perceiving the extension callback as too slow → reduced wake budget |
| | Failure cases turn into hot retry loops (chews battery + data) |
| | Extension memory pressure under flood scenarios — need an `OperationQueue` cap to mitigate |

### Option F4 — Allow ONE small monitoring-adjacent call in the BGTask: `ScreenTimeService.shared.refreshFromExtension()`
Reads `ext_usage_*` into `UsagePersistence` without touching threshold/sliding-window state. Would close the "BGTask uploads stale data" gap.

| Pros | Cons |
|---|---|
| BGTask becomes meaningfully real-time | Touches monitoring code (off-limits per current redline) |
| One function call, well-isolated | Need explicit user re-approval of redline |

---

## Test plan (next session)

1. Install new build on child device. Confirm `[ChildCKResyncService] Registered com.screentimerewards.ck-resync` appears at launch.
2. Confirm `[ChildCKResyncService] Scheduled next CK resync in 60s` appears.
3. Lock the device, leave it overnight (BGTasks fire more reliably during low-activity windows).
4. Reopen Xcode console next morning — count `===== CK Resync task started =====` occurrences. Each represents one BGTask fire.
5. Check parent dashboard timestamp granularity vs. previous behavior.
6. Compare against `extension_debug_log` to see whether the extension's own slot-based sync also fired in parallel (both paths are independent and both are valid).

If BGTask cadence is satisfactory but data freshness is not → discuss F2 or F4.
If BGTask cadence is too sparse (iOS deferring it) → no app-side fix; iOS BG budget is the constraint.
