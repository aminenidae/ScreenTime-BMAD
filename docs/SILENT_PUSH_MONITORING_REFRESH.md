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
