# Usage Tracking Accuracy Guide
**Purpose:** Keep device-activity based usage totals correct and defensible across Shield, selection changes, and CloudKit sync.

## What “accurate usage” means
- Counts only real, unblocked foreground time; shield time must be skipped (`currentlyShielded` check in `recordUsage`).
- Records each logical app ID at most once per threshold event (deduped via `processedLogicalIDs`).
- Duration comes from the configured `DeviceActivityEvent` threshold; zero/negative durations are rejected.
- Points = `rewardPoints` × floor(duration / 60); stored alongside seconds in `UsagePersistence`.
- Persisted immediately after each event so UI and sync read the same source of truth.

## Pipeline that affects accuracy
1) **DeviceActivity threshold fires** → `handleEventThresholdReached` converts the `DateComponents` threshold to seconds.  
2) **Usage recording** → `recordUsage(for:duration:endingAt:)` skips shielded apps, dedupes logical IDs, and records/updates `AppUsage`.  
3) **Durable storage** → Persisted to `UsagePersistence` (shared defaults/Core Data) as soon as the in-memory model changes.  
4) **Sync trigger** → When paired, a threshold event immediately calls `ChildBackgroundSyncService.triggerImmediateUsageUpload()` to move the new records to the parent.  
5) **UI refresh** → `usageDidChangeNotification` broadcasts so view models redraw from persisted values.

## Safeguards in place
- Shield time guard: skip if `application.token` is in `currentlyShielded`.
- Duplicate-event guard: ignore repeat logical IDs within one threshold callback.
- Zero-duration guard: bail out when duration ≤ 0 (prevents negative deltas).
- Threshold fallback: if a misconfigured `DateComponents` is zeroed, `seconds(from:)` defaults to 60s to avoid missing data.
- Debug traces: verbose `[ScreenTimeService]` logs show which apps were recorded or skipped, plus total counts.

## Validation checklist
- Real usage: monitor a learning app for > threshold; expect +duration seconds and points, logs show `✅ Recording usage`.
- Shield exclusion: block reward apps, sit on shield for > threshold; expect zero usage, logs show `🛑 SKIPPING ... currently blocked`.
- Duplicate token: trigger an event containing the same logical ID multiple times; only one record should be created/updated.
- Mixed categories: unblocked learning + blocked reward; only learning increments, reward stays at 0.
- Midnight rollover: confirm interval end/start logs, then verify post-midnight usage accrues from a clean slate.
- Sync path: when paired, observe immediate upload log from ChildBackgroundSyncService after a threshold fires and verify new records on the parent device.

## Known differences to communicate
- iOS Settings → Screen Time may count shield time; our app intentionally does not. Side-by-side totals will diverge in that scenario.
- 1-minute granularity: durations come from threshold windows, not per-second timers; short foreground blips under the threshold will be rounded to the next event.

## Troubleshooting steps
- If numbers look high: check for shield status not being set; confirm the app tokens in `currentlyShielded`.
- If numbers look low: confirm thresholds are non-zero; check logs for “duration is 0 or negative” or skipped events.
- If a single app shows multiple increments per window: verify it is not being mapped to multiple logical IDs in `UsagePersistence`.
- If sync totals differ: ensure threshold fired (look for `Recording usage...` log) before checking CloudKit; uploads only happen after events. 

## Investigation: every-other-minute drop (2025-11-17/18)
- Observation: Running a learning app for 10 minutes produced only ~5 minutes recorded; usage increments every other minute.
- Logs at skip moments show: `⏰ Timer fired - restarting monitoring to reset events...` → stop monitoring → recreate DeviceActivity events → restart monitoring → immediate intervalDidEnd/intervalDidStart.
- Impact: The stop/start cycle appears to clear the running threshold, so the minute that triggers the restart is lost; the next minute records normally, resulting in a sawtooth pattern (record, skip, record...).
- Note: A CloudKit export event occurs in the same window, but the loss aligns with the deliberate monitoring restart rather than CK activity.

### Proposed solutions
1) Remove periodic monitoring restarts: allow DeviceActivity to run continuously; only restart on explicit failures or when the system interval day rolls over naturally.
2) If a restart is required, stagger it: wait until after the current threshold fires (or manually fire `recordUsage` with the elapsed duration) before stopping monitoring.
3) Add a guard to skip redundant restarts when monitoring is already active and events are present; ensure the timer driving restarts is disabled by default in production.
4) Instrument restart reasons: log whether the restart is timer-driven, error-driven, or midnight rollover, plus how many events were active, so we can confirm the restart path is the culprit.

### Plan to fix
1) Trace restart source: find the timer/logic that logs “Timer fired - restarting monitoring to reset events...” and document its intent; add debug counters to measure how often it fires vs. thresholds fired.  
2) Disable the periodic restart in a test build and rerun the 10-minute learning session to verify continuous per-minute recording (no gaps).  
3) If restarting remains necessary (e.g., recovery from failures), wrap it with: a) ensure last threshold is recorded, b) skip restart when monitoring is healthy, c) coalesce multiple restart requests.  
4) Add a regression test/runbook step: continuous 10-minute session should yield 10 increments; include log expectation that no stop/start occurred mid-session.  
5) Once validated, remove the timer-driven restart from production builds and keep only explicit recovery and midnight rollover handling. 
6) Implemented: replaced the periodic timer with an event-driven re-arm after each threshold fires (with a short delay to let simultaneous events finish). This keeps continuous minute-by-minute tracking without wiping in-progress minutes. 

### Apple limits and risk check
- Apple’s Screen Time monitoring is built to run all day (single schedule, repeating). There is no documented requirement to restart every few minutes or a cap on daily monitoring time.  
- Legitimate reasons to restart: device reboot, permission revoked, app reinstall/upgrade, extension crash, or explicit health check showing events stopped.  
- Risk mitigation: keep a “restart on fault” path, but drop the periodic timer; add a simple health check (e.g., expected use but no events for several minutes) before restarting. This keeps restarts rare and evidence-based.  
- Validation gate: prove in a 10-minute run that removing the timer yields 10/10 minutes recorded; watch logs to ensure no unplanned restarts occur. 
