# Silent-Push Monitoring Refresh — Plan

**Status:** Planned, not implemented. Decisions pending.
**Created:** 2026-05-12

## Why this exists

The DeviceActivityMonitor extension can go silent for hours without anyone noticing. Today (May 12) showed a 4+ hour gap where iOS stopped delivering events to our extension; recovery only happened because the parent manually opened the app and toggled Screen Time.

Apple's two scheduler-based wake-ups (BGAppRefreshTask, BGProcessingTask) have both proven unreliable on the device class we tested:

- `monitoring-refresh` BGAppRefreshTask was removed Mar 31 (commit `14bdb0b`) after iOS scheduled it **0 times in 8 days**.
- The replacement — `performMonitoringMaintenanceIfNeeded()` piggybacked on the usage-upload BGProcessingTask — also failed to fire during the May 12 incident window (07h gap).

We've now seen Apple's scheduler deprioritize both task types on this device class. The Apple-provided lever is empirically unreliable.

## The fix in one sentence

**Server-triggered silent push** — when our backend notices a child device has gone quiet, it wakes the device with a content-available push, which calls `ScreenTimeService.shared.restartMonitoring()`. We control the trigger, not Apple.

## What's already in place

| Piece | State | Location |
|---|---|---|
| iOS APNs registration | ✅ Working | `AppDelegate.swift:35` |
| Device-token receive handler | ✅ Receives token, but does NOT upload it anywhere | `AppDelegate.swift:299–306` ("Store token if needed for custom push" — TODO) |
| Silent-push receive handler | ✅ Exists | `AppDelegate.swift:315–327` — routes only to CloudKit sync; no monitoring-refresh routing |
| Extension heartbeat | ✅ Written every event cycle | UserDefaults key `extension_heartbeat` |
| Firebase Functions backend | ✅ Operational | `firebase-functions/src/` — pairing, family, subscription, webhooks, diagnostic |
| APNs auth key in Firebase | ❌ Not configured | One-time admin step |
| Architecture intent already documented | ✅ | `ChildBackgroundSyncService.swift:459` comment: "24 hours (safety net for missed silent pushes)" — original design anticipated silent push as primary |

## What needs to be built

| # | Piece | What it does | Where it lives |
|---|---|---|---|
| 1 | **Token persistence + upload** | Save APNs device token to Firestore alongside the child device record | iOS (AppDelegate) + new Firestore field |
| 2 | **Heartbeat upload to Firebase** | Child device periodically writes "alive at HH:MM" to its Firestore record | iOS (background, or piggyback on existing sync paths) |
| 3 | **Silence detector (Cloud Function)** | Scheduled function (every 5–10 min) scans child devices, finds stale heartbeats during active hours, sends silent push | `firebase-functions/src/monitoring.ts` (new) |
| 4 | **Push handler routes to monitoring restart** | When silent push of type `monitoring-refresh` arrives, call `ScreenTimeService.shared.restartMonitoring()` | iOS (AppDelegate) — extend existing handler |
| 5 | **APNs auth key uploaded to FCM** | Firebase Cloud Messaging can send pushes on our behalf | Firebase console (one-time) |

## Design decisions — PENDING

These need to be settled before implementation starts.

### 1. Silence threshold — how long is "too quiet"?

**Recommendation:** 20 minutes of no heartbeat during the kid's active window (default 7am–10pm device-local).

- **<20 min:** Risks false positives during normal background-task gaps. iOS may throttle us for sending too aggressively.
- **>30 min:** Too much usage loss accumulates before recovery fires.

### 2. Rate limit per device

**Recommendation:** Max 3 silent pushes per hour per child device.

- iOS throttles silent pushes if an app sends too many or fails to do meaningful work on receipt. Being throttled hurts every push, not just the excess ones.
- Track `last_silent_push_sent_at` in Firestore per device; skip if last push was <20 min ago.

### 3. Failure fallback

**Recommendation:** If 2 consecutive silent pushes don't restore heartbeat (still silent 5 min after each push), send a **visible notification to the parent's phone** — "Your child's monitoring may need attention, please open the app."

- This is the human-in-the-loop safety net for when even silent push gets throttled or dropped.
- Requires the parent device to also be registered for push.

### 4. Quiet hours

**Recommendation:** No pushes between 10pm and 7am device-local.

- Kid is asleep — no monitoring need.
- Respect the parent's configured allowed-window schedule if set; otherwise use the default.

## Reliability estimate

| Layer | Reliability |
|---|---|
| BGAppRefreshTask (removed Mar 31) | ~0% on the device class tested |
| BGProcessingTask piggyback (current) | Unreliable — May 12 confirmed 7h+ silence |
| **Silent push (proposed)** | **~95%+**; remaining 5% is iOS throttling |
| Parent-notification fallback (proposed) | Covers the throttled 5% |

## Phasing

1. **Phase 1 — iOS client (≈1 day):** Token upload, heartbeat upload to Firestore, silent-push handler routes to `restartMonitoring`. Reversible; no behavior change until server side fires.
2. **Phase 2 — Server (≈1 day):** Silence-detector Cloud Function, deploy in **log-only mode** for 24h. Logs "would have sent push to X" without actually sending. Validate trigger logic against real data.
3. **Phase 3 — Go live (≈½ day):** Flip detector to live mode. Watch a few hours of production logs.
4. **Phase 4 — Parent fallback (≈½ day):** Add the parent-notification escalation when silent push fails twice.

**Estimated total:** 2–3 focused days.

## Risks and unknowns

- **APNs auth key admin step.** Requires Apple Developer account access, generates a `.p8` key, uploaded once to Firebase. One-time but blocking.
- **Heartbeat upload path.** Child device must be able to write to Firestore. Need to confirm current Firebase Auth state on child devices, or route heartbeat via CloudKit-as-relay (parent device occasionally relays the heartbeat).
- **iOS silent-push throttling.** Apple does not document exact thresholds. We may need to tune Decision #2 based on observed behavior.
- **Time zone handling.** "Active hours" is device-local; the silence detector must know each device's time zone (already captured? confirm during Phase 1).

## Open questions to resolve before Phase 1

- Does the child device already authenticate to Firebase? If not, heartbeat upload needs an auth path.
- Where is the child device's record in Firestore today? (Pairing flow creates it — verify the schema and which document to extend.)
- Is the parent device also registered for push, for Decision #3?

## Related work and history

- `docs/SMART_THRESHOLD_FILTERING.md` § "May 12, 2026" — the incident that motivated this plan.
- Commit `14bdb0b` (Mar 31) — removal of the original `monitoring-refresh` BGAppRefreshTask after 0 firings in 8 days.
- `ChildBackgroundSyncService.swift:459` — comment confirming the architecture always intended silent push as primary, BGTask as safety net.

---

## Implementation status — built 2026-05-31, server live 2026-06-02

Branch: `feat/credit-on-arrival-no-buffer`. Motivated by Ali's 2026-05-31 blackout (Roblox overran its 120-min daily limit by ~60 min during a 3-hour iOS-side extension blackout under low battery — proven iOS-side, not a window-registration bug).

### Design decisions locked (with CEO)
- Server **checks every 10 min**; **pokes only a device that is silent AND last reported a reward app unlocked**. (Unconditional 10-min pushes rejected — would get the app APNs-throttled app-wide.)
- The phone reports a **single gate flag** — "is any reward app playable right now" (a reward token not in the live iOS shield set). Folds in empty-bank / unmet-goal / daily-limit / outside-hours at once. (Extension requires `pool>0` to unshield, so empty bank ⇒ shielded ⇒ no poke automatically.)
- Idle / learning-only / empty-bank phones are never poked. Accepted tradeoff: a blackout during *pre-goal learning* isn't poked → earned credit lands late (safe, recovers on catch-up).
- **Log-only first**, then go live. Guards: quiet hours (device-local 7–22), min 20 min between pokes, max 3/hr, parent-notification fallback after 2 failed pokes.
- **Send route = FCM** (the `.p8` upload enables this). FCM needs the phone's **FCM token**, not the raw APNs token.

### Status — ✅ SERVER LIVE (2026-06-02)

**Phone (done):**
- `AppDelegate`: persists APNs token to app group; forwards it to FirebaseMessaging (`Messaging.messaging().apnsToken`); `MessagingDelegate.didReceiveRegistrationToken` stores the FCM token to app-group `fcm_token`; routes silent push `type=="monitoring-refresh"` → `ScreenTimeService.restartMonitoring`.
- `ScreenTimeService.anyRewardAppCurrentlyAccessible()` — the gate flag (reward tokens minus the live iOS shield set).
- `FirebaseValidationService.sendHeartbeat(rewardUnlocked:)` → callable `childHeartbeat` (payload: deviceId, familyId, rewardUnlocked, timezone, `fcmToken`, `extensionLastActive`). Child-only, best-effort.
- Call sites: app foreground (`.active`) + `ChildBackgroundSyncService.performMonitoringMaintenanceIfNeeded` (~30-min cycle).
- SPM: `FirebaseMessaging` product added to `ScreenTimeRewards.xcodeproj` (same firebase-ios-sdk package).

**Server (deployed live):**
- `firebase-functions/src/heartbeat.ts` — `childHeartbeat` onCall → merges `lastHeartbeat`/`fcmToken`/`timezone`/`rewardUnlocked`/`extensionLastActive` into `devices/{id}`.
- `firebase-functions/src/monitoring.ts` — `monitoringSilenceDetector`, `functions.pubsub.schedule('every 10 minutes')`. **`LOG_ONLY=false` (live).** Pokes when silent ≥10min AND `rewardUnlocked` AND device-local active hours 7–22, with min-poke-interval 20min + max 3/hr. Live send: `admin.messaging().send({token, apns:{content-available:1}, data:{type:'monitoring-refresh'}})`.
- **SDK upgraded** firebase-functions 4.9 → v6; all 7 function files import `firebase-functions/v1` (v1 API preserved); `functions.config().revenuecat.webhook_secret` → `process.env.REVENUECAT_WEBHOOK_SECRET` (value in gitignored `firebase-functions/.env`, auto-loaded by v6). Cloud Scheduler API auto-enabled on deploy.

**⚠ Deploy gotcha (cost hours — remember):** the deploy kept failing with `User code failed to load. Cannot determine backend specification. Timeout` — the discovery helper got `ECONNREFUSED` on `localhost:8443` (helper never started). It was **NOT** firebase-tools version (13/15), Node version (20/22), SDK version (4.9/6), or DNS order — all ruled out. Root cause: in-place `npm i firebase-functions@latest` left an inconsistent dependency tree. **Fix: `rm -rf node_modules package-lock.json && npm install` then deploy.**

### Remaining
1. **Ship a TestFlight build** with the iOS changes — until devices report `fcmToken`, the detector logs "no fcmToken" and sends nothing. Verify via the `monitoringSilenceDetector` function logs.
2. **Tune from real data:** `SILENCE_THRESHOLD_MIN`, active hours, rate caps — adjust off the live logs.
3. **Parent-notification fallback** after 2 failed pokes (intentionally deferred per CEO).

No shared-engine behavior changed (additive child-server hooks + one read-only helper) → no `ENGINE_SYNC_FROM_TICLOCK.md` port entry needed.

---

## Production validation — 2026-06-02 (first real-world test: it never fired)

The same failure the feature was built to fix recurred one day after the server went live. Ali's device (Xcode/debug build) blacked out 20:20–23:01 device-local: Roblox tracked 93 min vs iOS's 112 (19 min lost, daily limit unenforced for ~2h40m). The silent-push net **did not wake the device** — and the server logs show it has **never successfully poked any device**.

### What the logs showed
- `firebase functions:log --only monitoringSilenceDetector`: **`poked=0` across all 70 logged runs** — never once succeeded.
- Every send attempt to a device that *had* an `fcmToken` failed with:
  `messaging/third-party-auth-error: Request is missing required authentication credential. Expected OAuth 2 access token, login cookie or other valid authentication credential.`
- At least one reward-unlocked silent device also had **no `fcmToken` on record** (`noToken`) — server has nothing to aim at.

### Root cause (confirmed) — empty Development APNs auth key slot
The error CODE `third-party-auth-error` is, by Firebase's definition, an **Apple-side (third-party) push-credential failure** — despite the misleading Google-OAuth-flavored message *text*. (Note for future debugging: do **not** over-read that message text into a Google-side theory — see "ruled out" below. Trust the error code.)

The test devices (Ali, Imane) are **Xcode/debug installs → Development/sandbox APNs environment**. Firebase's **"APNs Authentication Key"** section has **separate Development and Production slots** — and even though a `.p8` is technically environment-agnostic, Firebase still requires the slot matching the device's environment to be populated. Only **Production** was filled; **Development was empty**. So every push to a sandbox (debug) device bounced.

### Google/server side — VERIFIED HEALTHY (do not re-chase)
Checked via `gcloud` (project `screentimerewards`):
- `fcm.googleapis.com` and `iamcredentials.googleapis.com` both **enabled**.
- Function `monitoringSilenceDetector` runs as `screentimerewards@appspot.gserviceaccount.com` — **exists, not disabled, has `roles/editor`** (covers FCM send).
- Firestore reads succeed in the same function (`scanned=5` every run), proving ADC works.

There is **no API, service-account, or permission problem.** The only variable was the Apple credential.

### Fix applied (awaiting confirmation)
User filled **both** the Development and Production "APNs Authentication Key" slots with the same `.p8` (Key ID `M5GX3F9H3Z`, Team ID `KQ5KZR3DQ5`). APNs **Certificates** section left empty — correct, the key method is in use. **Leave both slots populated.**

### ⚠ Confirmation still pending
Logs continued to show `poked=0` *after* the fix only because it was **after 10pm device-local** → `ACTIVE_HOUR_END=22` makes `candidates=0` (no send is even attempted during quiet hours). This is NOT evidence the fix failed.

**To confirm (before 10pm device-local):** let a debug device sit idle ~15 min with a reward app unlocked (so it's flagged silent), then re-pull `monitoringSilenceDetector` logs. Success signals:
1. `third-party-auth-error` **gone**
2. run summary shows **`poked≥1`**
3. a `MONITORING_RESTART` (reason involving the push) appears in **that device's own extension log** shortly after — proves the wake-up landed and re-armed tracking. ← the real prize; first proof the recovery net works end-to-end.

### ✅ Confirmed server-side — 2026-06-03
CEO unlocked reward apps and left a debug phone idle. Detector logs flipped:
- **`third-party-auth-error`: 0 occurrences** in the last 100 runs (was: every send).
- **`poked=1` on 11 runs** this morning (15:39, 16:09, 16:39, 17:09, 17:39 UTC … every ~30 min, with `rate:1` skips in between — exactly the 20-min min-interval / 3-per-hr design). Prior to the fix: **70 consecutive runs at `poked=0`.**

So signals #1 and #2 are met — the Apple-credential fix works and FCM now accepts/sends every poke. **Signal #3 (last mile) still pending:** `poked=1` only proves Google *sent* the push, not that iOS *delivered* it to the phone and re-armed tracking (a background push can still be dropped device-side). Need the debug phone's extension log to find `MONITORING_RESTART` with a push reason near the poke times. Until then, treat the end-to-end recovery as proven-on-server, unproven-on-device.

### ❌ Last mile FAILED on first device test — 2026-06-03 (Alex log, INCONCLUSIVE cause)
Pulled Alex's extension log for the same morning. Server poked at 10:39/11:09/11:39/12:09/12:39 device-local (CDT). The device was genuinely silent at those times — extension activity gaps 10:37→11:25 and 11:32→12:50, every poke inside a gap. **But ZERO `silent-push monitoring refresh` restarts appear.** Only restart all day was 10:27 (app-launch, `post-flood-recovery`). The device resumed on its own (natural usage at 11:25/12:50), not from a push. So: server sent 5 pushes, **iOS delivered 0** — while the phone was *charging (34%)*, with correct `remote-notification` background mode and the handler present (AppDelegate.swift:343, calls `restartMonitoring(reason:"silent-push monitoring refresh")`; restartMonitoring always logs a RESTART or MONITORING_ALIVE line, so absence = not delivered, not a silent early-return).

**Cause UNRESOLVED:** CEO unsure whether the app was force-quit (swiped away). iOS NEVER delivers silent/background pushes to a force-quit app — that alone would explain 0/5 and make this test non-representative. **Clean re-test needed:** open app once → press Home/lock (do NOT swipe away) → reward app unlocked → idle ~30–40 min during active hours → check both logs for the push-reason restart.

If a clean (not-force-quit) re-test ALSO shows 0 delivery → it's the real iOS background-push throttling wall (silent push is best-effort, droppable, budget-limited) and silent-push-alone is insufficient → escalate to the **Phase 4 parent-visible-notification fallback** (alert push, priority 10, delivered far more reliably than `content-available` priority 5). Config levers already exhausted: API enabled, SA `roles/editor`, both APNs keys, `remote-notification` mode, handler wired — nothing left to fix client/server-side; the gap is Apple's delivery layer.

### ✅ DEFINITIVE root cause — 2026-06-04 (Console.app device-log bisect)
Plugged the test phone into the Mac, watched live device logs in Console.app while firing manual FCM pushes (read fcmToken from Firestore `devices/632C8BA5...`, sent via FCM v1 REST with the same shape as the server). The device-level logs settle it conclusively — the failure is iOS's **`dasd` (Duet Activity Scheduler) refusing to LAUNCH a suspended app** to handle the background push:

- **Push ALWAYS reaches the phone.** SpringBoard logs `Received remote notification ... pushType: Background` every time. Apple delivery is not the problem.
- **Suspended app → `dasd Decision: AMNP`** (App May Not Proceed). iOS queues a `pushLaunch` activity, scores it against policies, and declines to launch the app. Handler never runs. Scoring shows a **Thermal Policy** penalty (`thermalLevel > 10` — phone was warm from charging) and a low **Application Policy** score for the suspended app.
- **Foreground app → `dasd Decision: AMP`** (App May Proceed). With `Application Policy response: {200, 1.00, [{[appIsForeground]}]}`, iOS allows it, logs `Allowing background launch`, and delivers `UISHandleRemoteNotificationAction` to the app's scene. Immediately after, the app re-registered its DeviceActivity schedule (UsageTrackingAgent re-listed all thresholds) — i.e. `restartMonitoring` ran and re-armed tracking.

**Conclusion:** the entire pipeline (server→FCM→APNs→device→handler→restartMonitoring) is correct and works **when the app is alive**. The sole failure is `dasd` declining to wake a *suspended* app under thermal/low-priority conditions — exactly the blackout scenario (warm charging phone, long-idle app). Silent push is therefore **best-effort only** and cannot be the safety net. Caveat for future debugging: the handler's `print("[AppDelegate] Received remote notification…")` does NOT appear in Console (print→stdout, not unified log); rely on `UISHandleRemoteNotificationAction` + threshold re-registration as proof of receipt.

**Decision:** keep silent push as an opportunistic best-effort layer; build the **parent-visible alert-notification fallback** (Phase 4) as the dependable recovery — an alert push is shown by SpringBoard without needing dasd to launch the app; the parent tapping it foregrounds the app (→ AMP → restart). This is now the priority work item for blackout recovery.

### Related blackout mechanics (independent of the push fix)
The same Ali log showed *why* recovery is needed and why the other two arms also failed:
- **Window exhaustion → 2h40m blackout.** Roblox hit its sliding-window top at 8:19pm; tracking went dark until the app was manually opened at 11:03pm.
- **Main-app rebuild arm dead:** extension posted a Darwin "restart" notification + persistent flag, but Darwin notifications are dropped for a suspended app; the flag wasn't processed until manual app launch 2h40m later.
- **Extension self-rebuild arm dead:** extension logged `EXT_REBUILD_SUCCESS` (Roblox 90-threshold window 34–123) but iOS does not honor ephemeral-extension `startMonitoring` re-registration when cumulative usage already exists — it delivered a burst of out-of-order catch-ups, then fired nothing. The window was never truly armed.
- Net: all three recovery paths failed together → silent push is the load-bearing one, and it must actually work.
