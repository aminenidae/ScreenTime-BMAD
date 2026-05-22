# Shield Subscription Race Fix (2026-05-21)

## Symptom

A parent reported that all reward apps were unshielded for their child mid-day
on 2026-05-21 even though the day's learning goal had not been met. Opening
the parent's main app re-shielded everything. The parent confirmed this is
"not the first time" — a recurring, intermittent issue.

## Evidence (ext-log-2026-05-21.log)

| Time      | Event                                                                                                              |
| --------- | ------------------------------------------------------------------------------------------------------------------ |
| 00:00:09  | Day rollover — extension's `checkAndBlockIfRewardTimeExhausted` confirms shields present in iOS                    |
| (silent)  | iOS reports 277 min cumulative usage on reward app `06909776` by 19:12, proving shields were OFF for hours         |
| 19:02:07  | Extension restart after parent opened main app at 19:01:39                                                         |
| 19:12:27 → 19:18:13 | Extension's per-event check finds shields present each minute                                            |
| 19:17:20  | Main app opened a second time                                                                                      |
| 19:18:13 → 19:19:11 | **Shields disappear from iOS in a 58-second window**                                                     |
| 19:19:11  | Extension's per-event recovery fires `LEARNING_GOAL_BLOCK` + `DAILY_ZERO_BLOCK` for all 14 reward apps — re-applying them |
| 19:23:06  | Parent opens main app — `AppUsageViewModel.init` boot reconcile re-applies again                                   |
| 19:28:50  | Learning goal hits 15 min — legitimate goal-met unshield                                                           |

The 58-second window between the last confirmed-shielded check and the
extension's re-apply matches the 60-second `BlockingCoordinator` periodic
refresh cadence triggered by the 19:17:20 main-app open.

## Root cause

`BlockingCoordinator.swift` had two paths that called
`ScreenTimeService.clearAllShields()` — i.e.
`managedSettingsStore.shield.applications = nil` — whenever
`SubscriptionManager.shared.effectiveHasAccess` returned false:

- `startPeriodicRefresh()` (was line 1366)
- `refreshAllBlockingStates()` (was line 1399)

On child devices, `effectiveHasAccess` is sourced from
`ChildBackgroundSyncService.hasFullAccess`, which depends on CloudKit-fetched
parent-paired entitlement. A transient CloudKit hiccup, an in-flight re-fetch,
or any moment where the cache is briefly invalidated causes
`effectiveHasAccess` to flip false for 1-2 seconds. The 60-second refresh
timer can fire inside that window — wiping every reward shield in one shot.

Recovery is slow and incomplete:

- The extension's per-event safety net
  (`checkAndBlockIfRewardTimeExhausted` in
  `DeviceActivityMonitorExtension.swift:2445`) only runs when a threshold
  event fires for **any** tracked app. If the kid only uses reward apps, no
  learning-app event triggers the recovery.
- The fallback recovery — `AppUsageViewModel.init`'s boot reconcile — only
  fires when the parent next opens the main app, which could be hours.

## The wrong fix considered, then rejected

When asked "if the shield remains despite the subscription expired, what's
next?" the first instinct was to add subscription enforcement at the
unshield/credit paths on top of removing the wipe. That would create new
failure modes — e.g. a CloudKit blip exactly when the kid completes a goal
would cause "goal met but no reward time granted." The symptom moves; it
doesn't solve.

## The right fix

Remove the wipe. Subscription state should never destroy the safety state.
Enforcement happens naturally via:

- **Bank drain.** No new learning credit accrues without a valid
  subscription (gated elsewhere in the credit pipeline). The kid spends down
  the existing pool through normal play, then is permanently shielded.
- **Locked settings UI.** Parent cannot change reward-app selection,
  pairings, or goal configs without a valid subscription (handled in
  settings views).

Outcome:

- **Transient CloudKit blip** → no visible damage. The periodic refresh
  skips one tick; shields stay in place. Next tick recovers normally.
- **True subscription expiry** → kid still has earned bank time to spend
  (already paid for); once empty, every reward app stays shielded forever
  until renewal. Parent is hard-locked out of changing settings.

This is also the better business outcome: prior behavior gave an expired
subscriber's kid FREE access to every reward app the moment the system
noticed — the opposite of a renewal incentive.

## Code change

Both guards in `BlockingCoordinator.swift` retain the early-return on
`!effectiveHasAccess` but no longer call `clearAllShields()`. The shield set
is now only mutated by:

- `syncAllRewardApps()` — decision-driven block/unblock based on
  goal/limit/downtime state
- `AccountDeletionService` — intentional cleanup on account deletion
- The extension's per-event control flow (`checkAndUpdateShields` and
  `checkAndBlockIfRewardTimeExhausted`)

## Invariants restored

- **Shield state survives subscription-check transients.** Shields can only
  be removed by an explicit decision tied to goal/limit/downtime state, not
  by an entitlement signal.
- **Failure mode is fail-closed.** When uncertain, the safety control stays
  on. Removing safety on uncertainty is the wrong direction — especially in
  a parental-controls app where the cost of a false unshield is much higher
  than the cost of a stale shield.

## Follow-ups (not in this commit)

- Audit `AppUsageViewModel.swift:2370` for the other `clearAllShields()`
  callsite — confirm it's intentional cleanup, not another race surface.
- Consider adding an analytics event when `effectiveHasAccess` is false for
  more than N consecutive minutes, to surface true expiries vs transient
  noise.
- Consider a hard-lockout option ("block everything immediately on confirmed
  expiry") as a paid-tier business setting — separate decision from this
  safety fix, and should only be enabled after N consecutive failed checks,
  never a single tick.
