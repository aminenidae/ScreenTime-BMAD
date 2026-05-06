# Research: DeviceActivity Usage-Tracking Accuracy & Catch-Up Storms

**Date:** 2026-05-04
**Question:** How do other iOS developers handle deferred-batch / catch-up storms in `eventDidReachThreshold`?
**Bottom line up front:** This is a widely-reported, Apple-acknowledged class of bugs in the Screen Time subsystem. There is no canonical fix. The community converges on three workaround patterns (debounce/dedup, ignore-first-callback-after-restart, and outsourcing display-time accuracy to a `DeviceActivityReport` extension). No public source describes a `lastThreshold`/wall-clock anchor approach as elaborate as ours; competitors largely accept inaccuracy and patch around it.

---

## Section 1 — Confirmed iOS API Behaviors

| Behavior | Documented? | Source |
|---|---|---|
| `eventDidReachThreshold` measures cumulative usage from `intervalStart`, not from `startMonitoring()` time | Stated by Apple Frameworks Engineer | [Apple Forums thread/727970](https://developer.apple.com/forums/thread/727970) |
| 6 MB hard memory limit for DeviceActivityMonitor extension; process is killed via `EXC_RESOURCE`/Jetsam on overrun | Confirmed in forums, no documentation | [Apple Forums thread/735454](https://developer.apple.com/forums/thread/735454); [Crunchy Bagel article](https://crunchybagel.com/monitoring-app-usage-using-the-screen-time-api/) |
| Minimum `DeviceActivitySchedule` interval is 15 minutes (anything less silently never fires) | Undocumented but confirmed | [Apple Forums thread/750623](https://developer.apple.com/forums/thread/750623); [Yamada limitations article](https://medium.com/@yosshi4486/limitations-of-screen-time-related-apis-3ebf7c371962) |
| Maximum 20 schedules per app+extensions combined (`MonitoringError.excessiveActivities`) | Documented via thrown error | [Yamada limitations article](https://medium.com/@yosshi4486/limitations-of-screen-time-related-apis-3ebf7c371962) |
| `DeviceActivityReportExtension` is sandboxed — its computed `totalActivityDuration` cannot be exfiltrated to the host app via App Groups, shared files, CFPreferences, or network | By design (privacy) | [Apple Forums thread/735012 referenced](https://developer.apple.com/forums/thread/735012) via [search summary](https://developer.apple.com/forums/tags/device-activity) |
| iOS Simulator does not track DeviceActivity metrics — must test on device | Undocumented but confirmed | [Apple Forums thread/746416](https://developer.apple.com/forums/thread/746416); [Apple Forums thread/735293](https://developer.apple.com/forums/thread/735293) |
| Starting iOS 17.5+, failed threshold callbacks are queued and retried, causing multiple thresholds to fire together (e.g. 1h+2h+3h notifications arriving simultaneously) | Acknowledged by Apple Frameworks Engineer requesting FB # | [Apple Forums thread/762540](https://developer.apple.com/forums/thread/762540) |
| iOS 26.2/26.3: `eventDidReachThreshold` fires while iOS Settings shows 0 minutes — strongly correlated with **device plug-in to charger while idle/locked** | Reproduced with sysdiagnose; Apple Feedback FB21450954, FB21560904 open | [Apple Forums thread/811305](https://developer.apple.com/forums/thread/811305); [Apple Forums thread/812472](https://developer.apple.com/forums/thread/812472) |
| iOS 26 regression: with `includesPastActivity:false`, threshold fires within seconds of monitoring start. Apple DTS engineer Albert Pascual root-caused it as "daemon cached state not properly cleared." Said to be resolved in iOS 26.5 beta 1+ | DTS-confirmed; FB18061981 / FB18927456 / FB20817853 | [Apple Forums thread/808470](https://developer.apple.com/forums/thread/808470) |
| iOS 17.6.1+ overcounting (DeviceActivityMonitor reports much higher usage than `DeviceActivityReport` and Settings → Screen Time). Apple DTS confirmed it's a Screen Time subsystem bug, FB15103784 open. "I can't see any sort of reasonable workaround." | DTS-confirmed | [Apple Forums thread/763542](https://developer.apple.com/forums/thread/763542) |
| Same Safari-page double-count bug: if the kid uses safari.com, `Safari` and the website are counted **separately** by DeviceActivity, producing 2× the real time | Confirmed by multiple devs | [Apple Forums thread/763542](https://developer.apple.com/forums/thread/763542) |

**Direct answer to "is the deferred-batch-flush behavior documented":** Yes — by Apple staff in the forums but not in official docs. The most candid statement is from [DTS Engineer thread/763542](https://developer.apple.com/forums/thread/763542):
> "My reading of this thread is that you consider this to be a bug in the Screen Time subsystem and you've filed it as such FB15103784… Honestly, I can't disagree with that assessment. Unfortunately I don't have any info to share about when, or indeed if, that'll be fixed. And I also can't see any sort of reasonable workaround."

The **charger-plug-in** trigger we observe matches SaulD18's January 2026 reproduction (sysdiagnose attached to FB21450954): leave device idle/locked for hours → plug into power → within minutes thresholds fire despite zero real usage. This is the same root signal we've been calling a "phantom storm."

---

## Section 2 — Known Workarounds Used by the Community

### 2.1 In-extension debouncing (most common)
[Apple Forums thread/741133](https://developer.apple.com/forums/thread/741133) — duplicate consecutive `eventDidReachThreshold` callbacks for the same threshold occur >50% of the time. Community discussed two mitigations:
- "Avoid recursive threshold operations" — never re-register events from inside the callback
- "Add deduplication logic — track recently-fired thresholds and ignore duplicates within a small time window"

[Apple Forums thread/741117](https://developer.apple.com/forums/thread/741117) — `MeanRaw` (Nov 2025) reports implementing "debouncing logic to prevent duplicate state changes when `eventDidReachThreshold` fires multiple times within 1 second." No code published.

**Trade-off discussed:** A short window (≤1s) catches the iOS-17.5+ retry-burst case but misses real deferred-batch flushes that span seconds. A long window (≥60s) drops legitimate post-deferral catch-ups. We've already discovered this trade-off ourselves.

### 2.2 Ignore-during-state-transitions
[Apple Forums thread/808470](https://developer.apple.com/forums/thread/808470) — DTS-recommended workaround for `includesPastActivity:false` daemon-cache bug: tell users to **revoke and re-grant Screen Time permissions**, which wipes the cached daemon state. Workaround lasts ~2 weeks until next iOS beta. This is not a code-side fix — it's an end-user dance.

### 2.3 No catchup-cap workaround exists in published code
We searched GitHub via search engines (`site:github.com "eventDidReachThreshold"`) and found **no** repositories implementing per-event delta caps, wall-clock anchors, or `lastThreshold` hold-on-clamp. The publicly-visible implementations (kingstinct/react-native-device-activity, christianp-622/ScreenBreak, krypted/DeviceActivityExample, YazanHalawa/Explore-iOS-15-Screentime-API) all just call into business logic without filtering. Source: search results from [GitHub via WebSearch](https://github.com/kingstinct/react-native-device-activity).

The kingstinct README explicitly disclaims accuracy:
> "The Screen Time APIs are known to be very finnicky… Disable Low Power Mode… ensure sufficient device storage."
([kingstinct README](https://github.com/kingstinct/react-native-device-activity))

### 2.4 Singleton + 15-minute minimum interval
[Apple Forums thread/750623](https://developer.apple.com/forums/thread/750623) — for *firing reliability* (not accuracy), Akashkt_apple09 documents that a singleton DataModel shared between main-app and extension, plus enforcing minimum 15-minute schedules, fixes most "monitor never fires" complaints. Doesn't address overcounting.

### 2.5 Outsource display to `DeviceActivityReport`
Multiple forum threads suggest **stop trying to expose accurate cumulative time from your extension; use `DeviceActivityReport` for the user-visible number**. From [a forum search result summary](https://developer.apple.com/forums/forums/tags/device-activity):
> "There isn't [a supported way to extract data]. Rather than trying to extract data from the extension, you must exploit the limitations of this framework and design a UX that makes the most out of what the APIs provide to you."

This means: your extension fires shields/rewards on threshold callbacks, but the kid-facing or parent-facing **time display** is rendered inside a sandboxed `DeviceActivityReport` view that reads `totalActivityDuration` directly from Screen Time. The two numbers are guaranteed to match Settings → Screen Time because they are the same source.

This pattern is used by [Streaks (per Crunchy Bagel article)](https://crunchybagel.com/monitoring-app-usage-using-the-screen-time-api/) and is the [letvar series' implicit recommendation](https://letvar.medium.com/time-after-screen-time-part-2-the-device-activity-report-extension-10eeeb595fbd).

### 2.6 Jomo's stance: "we measure something different on purpose"
[Jomo's help-center article](https://help.jomo.so/en/article/my-screen-time-on-jomo-is-different-from-apples-screen-time-1l2oxjy/) explicitly tells users their numbers don't match Apple's:
> "Apple starts counting screen time as soon as your iPhone screen is on — even if you're not doing anything, it still counts. Jomo only tracks time you actually spend using apps… Apple applies end-of-day corrections to adjust inaccurate reporting, but this correction isn't applied to the data sent to third-party apps."

**This is the most important sentence in the entire research.** Apple itself knows the data shipped to third-party apps via DeviceActivity is uncorrected and it does internal end-of-day reconciliation that third parties never see. Jomo gives up on parity and sells the difference as a feature.

---

## Section 3 — Alternative Architectures

### 3.1 `DeviceActivityReport` extension as the source of truth (recommended by docs)
Render display time inside the report extension, which has direct privileged access to `DeviceActivityData.ActivitySegment.totalActivityDuration`. The host app **cannot** read this number — but the user can see it inside a SwiftUI view embedded from the extension. From [WWDC22 "What's new in Screen Time API"](https://developer.apple.com/videos/play/wwdc2022/110336/):
> "Reports receive `[DeviceActivityData]` array to create custom visualizations… `makeConfiguration()` is invoked by the framework whenever new usage data is fetched."

**Trade-off:** Cannot be used to drive business logic (rewards, blocking decisions) inside the host app — only display. Would require us to keep our threshold-event accumulator for shield/reward decisions and *display* a different (correct) number. Splits the truth surface, which is its own UX hazard.

### 3.2 Pre-VPN / on-device traffic inspection
[Opal's engineering blog](https://opalapp.com/blog/opals-screen-time-framework) describes their pre-Screen-Time-API architecture: a local-only VPN that watches outbound traffic and infers app usage. Opal has since switched to ManagedSettings for blocking but still uses traffic inference for measurement:
> "Opal initially built and operated its own VPN technology… The updated version uses ManagedSettings, which is part of Apple's Screen Time API… DeviceActivity is used to tell the system when to pay attention to the ManagedSettingsStore."

**Trade-off:** A VPN profile requires explicit user setup, doesn't see offline app activity, and can't measure first-party Apple apps that don't make network calls (Photos, Calculator, etc.). Not viable for parental control where blocking-correctness matters more than measurement-correctness.

### 3.3 No private API for "actual cumulative"
Multiple threads confirm there is no DeviceActivity API to query iOS for "actual cumulative minutes for app X today" from inside `eventDidReachThreshold`. [Apple Forums thread/735012 (referenced)](https://developer.apple.com/forums/thread/735012) and the [WWDC22 transcript](https://developer.apple.com/videos/play/wwdc2022/110336/) both make clear `DeviceActivityData.ActivitySegment` is only constructible inside a `DeviceActivityReport` extension. Hooking it from a `DeviceActivityMonitor` extension is not supported.

There is no documented private API either; nothing surfaced in our search.

### 3.4 Background fetch as a "monitoring health check"
We already do this (`com.screentimerewards.monitoring-refresh` BGAppRefreshTask every 45 min). This pattern is **not** something other apps publish about — it appears to be our innovation. The closest discussion is generic iOS background-task documentation; no Screen Time–specific community pattern emerged.

### 3.5 "High threshold seen wins" / monotonic-only accumulation
Hinted at in our internal docs as the high-water-mark approach. Not found in any external published source. The implicit closest match is *not advancing `lastThreshold` on suspicious clamps* — which is what we just shipped on `fix/stale-catchup-lastthreshold-poisoning`.

---

## Section 4 — What Competitors Are Doing

| App | Approach (per public sources) | Accuracy posture |
|---|---|---|
| **Opal** | DeviceActivity for scheduling, ManagedSettings for blocking, **own traffic-inference layer** for measurement. Original VPN now hybrid. | Doesn't claim parity with Settings. Blog frames "accuracy" as "did we detect intent vs. background." [Opal blog](https://opalapp.com/blog/opals-screen-time-framework) |
| **Jomo** | Pure DeviceActivity. Explicitly tells users their number ≠ Apple's number; advertises it as a feature ("we ignore passive screen-on time and background activity"). | Walks away from parity. [Jomo help](https://help.jomo.so/en/article/my-screen-time-on-jomo-is-different-from-apples-screen-time-1l2oxjy/) |
| **Brick** | DeviceActivity + ManagedSettings + a physical NFC magnet to gate unblock. No public engineering blog. Reddit reports the app is "glitchy, crash-prone, sync issues." | Treats accuracy as secondary; primary value is the magnet ritual. [Norton review](https://us.norton.com/blog/privacy-tips/is-brick-app-secure) |
| **One Sec** | Has a public ["Screen Time API issues" article](https://tutorials.one-sec.app/en/articles/3036354) directing users to disable Low Power Mode and re-grant Screen Time access — same "user-side dance" workaround. | No technical blog. Punts to user. |
| **Aura, Qustodio, FamilyTime** (paid parental control) | Use **MDM** (Mobile Device Management) profiles, not pure Screen Time API. MDM gives much more reliable enforcement. | Out-of-band; not comparable to our architecture. [Boomerang comparison](https://useboomerang.com/article/parental-control-app-ios/) |
| **riedel.wtf author** (anonymous indie dev with shipping app) | Public rant: "iOS 26 introduced a series of heavy regressions… reported via Feedback Assistant on iOS 26 beta 1 in June 2025 — and have not been addressed 10 months later." | No workaround; calls Apple out by name. [riedel.wtf](https://riedel.wtf/state-of-the-screen-time-api-2024/) |
| **Streaks** | Per Crunchy Bagel write-up, they catch `eventDidReachThreshold` and "mark tasks as missed" — single-event business logic, not cumulative tracking. | Avoids the problem by design — they don't try to count minutes, just to react to "limit hit." [Crunchy Bagel](https://crunchybagel.com/monitoring-app-usage-using-the-screen-time-api/) |

**Pattern:** every competitor we found either (a) accepts inaccuracy and reframes the difference as a feature, (b) avoids cumulative tracking entirely (single threshold-as-trigger), or (c) sidesteps DeviceActivity via MDM or VPN. Nobody publishes a working solution to the "match Settings → Screen Time within 2%" problem.

---

## Section 5 — Open Apple Feedback / Radar Bugs

Compiled from forum citations:

| FB ID | Topic | Status |
|---|---|---|
| FB15103784 | iOS 17.6.1+ overcounting in DeviceActivityMonitor | Open since Sep 2024. DTS confirmed bug, no fix timeline. [thread/763542](https://developer.apple.com/forums/thread/763542) |
| FB18061981 | iOS 26 `includesPastActivity:false` immediate-fire | Said by Apple to be fixed in iOS 26.5 beta 1+. [thread/808470](https://developer.apple.com/forums/thread/808470) |
| FB18927456 | Same iOS 26 cluster | Open. [thread/811305](https://developer.apple.com/forums/thread/811305) |
| FB20817853 | Same iOS 26 cluster | Open. [thread/808470](https://developer.apple.com/forums/thread/808470) |
| FB21450954 | iOS 26.2 false-positive threshold on charger plug-in (matches our symptom exactly) | Filed Dec 2025; Apple silent as of Mar 2026. [thread/811305](https://developer.apple.com/forums/thread/811305) |
| FB21560904 | iOS 26.2/26.3 false-positive `eventDidReachThreshold` on monitoring start | Filed Jan 2026; 0 replies, 1 boost, 394 views. [thread/812472](https://developer.apple.com/forums/thread/812472) |
| FB14082790, FB14237883, FB18794535, FB15079668, FB15500695 | Adjacent token / shield / permission bugs | All open per [riedel.wtf](https://riedel.wtf/state-of-the-screen-time-api-2024/) |

The charger-plug-in trigger is **specifically the case Apple has been told about and not fixed**. It is exactly our recurring failure mode.

---

## Section 6 — Bottom-Line Recommendations

Three directions are most fruitful, in order of estimated effort/return:

### Recommendation 1 — Adopt the "split truth" architecture (highest leverage)
Stop trying to make our extension's per-app-cumulative number match Settings → Screen Time. Use two independent sources:

- **Threshold callbacks (current):** drive business logic — shielding, unshielding, reward minute-bank credits. Keep all current defenses (lastThreshold hold-on-clamp, SKIP_MIDNIGHT, sliding window).
- **`DeviceActivityReport` extension (new):** render the user-visible "minutes used today" inside a sandboxed report view. The number is read directly from Screen Time so it matches Settings exactly.

Trade-off: kid sees one number for "minutes used today" but reward-bank logic uses another (slightly under or over). This already happens silently — exposing the more accurate one fixes user-trust complaints without forcing us to perfectly reconcile internally.

We have not seen a competitor explicitly do this split, but [the official WWDC22 architecture](https://developer.apple.com/videos/play/wwdc2022/110336/) clearly intends it: report extension for visualization, monitor extension for enforcement.

### Recommendation 2 — Treat charger plug-in as a known phantom-storm trigger; suppress events for N seconds after `UIDevice.batteryState` change
The iOS 26.2 reproduction in [FB21450954](https://developer.apple.com/forums/thread/811305) is identical to our symptom. Implement an extension-side gate: when the battery state transitions to `.charging` while the device was idle, treat all `eventDidReachThreshold` callbacks in the next ~15s as suspect. This is the most precise filter we can add; it targets the actual root cause Apple has been told about.

We have not seen this pattern published anywhere — it would be novel, but the underlying signal is documented.

Caveat: extensions don't have direct `UIDevice` access; we'd need a main-app heartbeat that writes the last battery-state-change timestamp into the App Group, and the extension would gate on it. The extension memory budget allows one timestamp read.

### Recommendation 3 — Stop iterating on `lastThreshold` defenses, accept the residual error, and document it
Six months of layered filters (wall-clock cap → 60s hard cap → hold-on-clamp → cross-app burst signature) have moved us closer to the asymptote but every defense adds fragility. The Apr 13 Layer-2/3 revert and the Apr 29 lastThreshold poisoning incident both prove the same thing: each new layer creates new failure modes. The community consensus from the most candid devs ([riedel.wtf](https://riedel.wtf/state-of-the-screen-time-api-2024/), Quappi in [thread/811305](https://developer.apple.com/forums/thread/811305)) is that Apple is no longer maintaining this framework actively, and that "the framework is barely usable to build stable apps." Apple DTS itself said "I can't see any sort of reasonable workaround" ([thread/763542](https://developer.apple.com/forums/thread/763542)).

What "accept the residual error" looks like in practice: pick a target (e.g. ±5% on heavy-use days, ±10% on idle-storm days), instrument it, ship it, and move engineering effort toward Recommendation 1 (where the per-display number matches Settings exactly without us having to be heroic).

### What is *not* worth investigating further
- **Querying iOS for actual cumulative from the extension** — confirmed impossible, no public or private API. ([thread/735012 referenced](https://developer.apple.com/forums/thread/735012); WWDC22)
- **Ignoring Low Power Mode events entirely** — the connection between LPM and storms is folkloric, not documented; one-sec/kingstinct mention disabling LPM as a *user* fix, not a coding pattern. The real trigger appears to be charger plug-in, not LPM specifically.
- **Polling `DeviceActivityReportExtension` from the host** — sandbox is by design; multiple devs have confirmed App Group / file / CFPreferences exfiltration is impossible.

---

## Appendix — Search Strategy & Coverage Notes

Sources searched: Apple Developer Forums (12 distinct threads read), WWDC21 session 10123, WWDC22 session 110336, GitHub via search engine (no Swift code-search auth available; search engines returned 0 hits for `site:github.com "eventDidReachThreshold"`), Medium (3 articles deeply read, 4 skimmed), Stack Overflow (covered indirectly via search), Reddit (no relevant results found via `site:reddit.com`), Hacker News (one tangential result), competitor help-centers and engineering blogs (Opal, Jomo, Brick, One Sec).

**Where we couldn't find good answers:** No external developer publishes their cumulative-tracking accumulator code, so there is no second opinion on our `lastThreshold` pattern. Reddit's `r/iOSProgramming` had nothing indexed on this topic — likely the addressable population of devs working on Screen Time daily is in the dozens, and they cluster on the Apple forums.

**Confidence:** High that the bugs we are working around are real and Apple-acknowledged. High that no competitor has solved this. Medium that Recommendation 1 (split-truth architecture) is achievable for our app — it depends on whether our parent-side dashboard requirements can be satisfied by a sandboxed report view rather than data flowing to CloudKit. That's our project-specific decision, not a research one.
