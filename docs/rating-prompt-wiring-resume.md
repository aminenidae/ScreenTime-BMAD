# Rating Prompt Wiring — Resume Notes

**Branch:** `feature/streamline-usage-recording`
**Date:** 2026-04-17
**Status:** Code wired, **build not verified**. Continue from verification step.

**2026-04-19 addendum:** Parent-device rating prompt wired in `ChildUsageDashboardView.ChildHomeTabView` (commit on `fix/pairing-subscription-sync`). Auth guard in `RatingPromptService` relaxed to also accept `SessionManager.shared.isParentDeviceAuthenticated`. Per-trigger flags are **per-device** (App Group UserDefaults don't sync across devices), so each paired install has up to 4 independent prompt opportunities (2 triggers × 2 devices) before Apple's 3/365 per-Apple-ID cap kicks in. See "2026-04-19: Parent-Device Wiring" section at the bottom of this file.

## Why

Brain Coinz approved 1.0.3(1) on 2026-04-17 with 0 reviews. Per Ariel Michaeli (Appfigures, 15+ yrs ASO): rating **volume** (not stars) is the primary App Store ranking lever for the first 30 days, and 75%+ of users are gone by day 2 — so the first-delight rating prompt must fire early and once. Source: `Marketing-Strategy/ASO/APPFIGURES_ASO_INSIGHTS.md` §5.

## What was wired

System review prompt via `SKStoreReviewController` / `AppStore.requestReview(in:)`, gated by **per-trigger** UserDefaults flags in the shared app group `group.com.screentimerewards.shared`. Each trigger fires at most once per install. Apple's own 3-per-365-day rate limit is the ultimate cap. **Parent-authenticated context only** — never fires for a child-facing session.

**File:**
- `ScreenTimeRewards/Services/RatingPromptService.swift` — singleton with `requestReviewIfEligible(trigger:)` + public `hasFired(trigger:) -> Bool`. Three guards before firing: (1) per-trigger flag `rating_prompt_fired_<trigger>_v1` not set, (2) `SessionManager.shared.isParentAuthenticated == true`, (3) `activeForegroundScene()` returns a foreground-active scene. Whole method is `@MainActor` to safely read `SessionManager`. One-time migration from the legacy `rating_prompt_fired_v1` single-flag to the `firstParentSuccess` per-trigger flag on first call.

**Triggers (Option B, 2026-04-17):**
- `.firstParentSuccess` — parent sees earnedMinutes > 0 on dashboard (first proof of value)
- `.firstWeeklyWin` — parent sees currentStreak >= 3 on dashboard (behavior-pattern proof, stronger emotional payoff)

**Call sites (3 in `Views/ParentMode/ParentDashboardView.swift`, all route through one helper):**
1. `.onAppear` → `tryFirePromptForCurrentState()`
2. `.onChange(of: dataAdapter.earnedMinutes)` → `tryFirePromptForCurrentState()`
3. `.onChange(of: dataAdapter.currentStreak)` → `tryFirePromptForCurrentState()`

Priority in `tryFirePromptForCurrentState`: stronger trigger wins. If `currentStreak >= 3`, try `.firstWeeklyWin`. Otherwise, if `earnedMinutes > 0` AND `.firstWeeklyWin` hasn't already fired, try `.firstParentSuccess`. Prevents the weaker trigger from firing on a streak-broken visit after the stronger already claimed a slot.

**Paywall isolation:** grep-verified zero references to `RatingPromptService` / `requestReview` / `SKStoreReviewController` / `AppStore.requestReview` under `Views/Onboarding/`. Apple rejects apps that prompt for reviews adjacent to a paywall.

## What's NOT done (resume from here)

1. **Build not verified.** Last attempt failed on a DerivedData disk I/O error (`build.db`), not a code issue. SourceKit false-positive errors surfaced during editing (e.g., `No such module 'UIKit'`, `Cannot find 'AppUsageViewModel'`) — these are macOS-SDK indexing artifacts because this is an Xcode 16+ `PBXFileSystemSynchronizedRootGroup` project where files under the synced folder are auto-included in the iOS target. A real iOS build should resolve them.
   - **Resume action:** from `ScreenTimeRewardsProject/`, run:
     ```
     xcodebuild -project ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards clean
     xcodebuild -project ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards -destination 'generic/platform=iOS' -configuration Debug build
     ```
   - If `DerivedData` locks persist: quit Xcode, retry `rm -rf ~/Library/Developer/Xcode/DerivedData/ScreenTimeRewards-*`, then rebuild.

2. **Runtime verification on TestFlight** — not yet done:
   - **Trigger 1 — firstParentSuccess.** Fresh install → complete parent onboarding → paywall → parent dashboard with earnedMinutes > 0 and currentStreak < 3 → expect system rating prompt + `DEBUG_LOG_RATING_PROMPT_FIRED: trigger=firstParentSuccess`. Second visit same conditions → `DEBUG_LOG_RATING_PROMPT_SKIPPED: already_fired`.
   - **Trigger 2 — firstWeeklyWin.** After several days of completed goals, parent dashboard shows currentStreak >= 3 → expect system rating prompt + `DEBUG_LOG_RATING_PROMPT_FIRED: trigger=firstWeeklyWin`. Apple's own 3/365 cap may silently suppress the second actual display if it's too close to the first, but the per-trigger flag still flips.
   - **Priority check.** Fresh install where currentStreak >= 3 immediately (e.g., backfilled data): expect only `firstWeeklyWin` to fire; `firstParentSuccess` flag stays unset.
   - **Child-device flow.** Learning goal completes → shield drops → expect NO prompt (child context, parent not authenticated). PIN-enter parent mode on child device, open dashboard meeting a trigger → expect prompt.
   - **Parent-session locked.** App backgrounded on child device → returns without re-auth → dashboard appears → expect `DEBUG_LOG_RATING_PROMPT_SKIPPED: parent_not_authenticated`.
   - **Legacy migration.** Install built before Option B that has `rating_prompt_fired_v1 = true` → first call after upgrade logs `DEBUG_LOG_RATING_PROMPT_MIGRATED: legacy_flag → firstParentSuccess`. That user gets `firstWeeklyWin` as a new chance but is not re-prompted for `firstParentSuccess`.

3. **ASO-side verification (Day 14, 2026-05-01):** `mcp__astro__get_app_ratings(appId: "6753270211")` — any review count > 0 is working-as-intended.

## Known decisions (do not re-debate on resume)

- **Parent-authenticated context only.** Prompt is guarded by `SessionManager.shared.isParentAuthenticated`. Revised 2026-04-17 after recognizing three child-context failure modes: (1) kid-retaliation 1-star reviews as payback for screen-time restrictions, (2) under-13 child Apple IDs may have In-App Ratings & Reviews disabled → prompt fires but submits nothing and burns the slot, (3) Kids-Category / COPPA prompting-kids concerns. The child-side `.firstUnlock` call site in `BlockingCoordinator.swift` was removed.
- **Per-trigger flags (Option B, 2026-04-17).** Replaced the single-flag scheme with `rating_prompt_fired_<trigger>_v1`. Each delight moment fires at most once per install; Apple's 3-per-365 cap is the ultimate guardrail. Rationale: fire-and-forget API means a single flag burned the only slot even when iOS silently suppressed the prompt or the user dismissed. Multiple per-trigger flags + priority logic give the user up to 3 independent chances at different emotional moments.
- **Trigger priority.** `firstWeeklyWin` (streak >= 3) preempts `firstParentSuccess` (earnedMinutes > 0) when both are eligible. Prevents the weaker trigger from consuming a slot after the stronger one has already fired on a subsequent streak-broken visit.
- **Legacy flag migration.** Old `rating_prompt_fired_v1` → new `rating_prompt_fired_firstParentSuccess_v1` on first call. Users upgraded from pre-Option-B builds aren't re-prompted for `firstParentSuccess` but do get `firstWeeklyWin` as a fresh chance.
- **No custom "Rate us" UI.** Ariel: custom UI dilutes the system-prompt budget.
- **No metadata edits** during the 14-day ASO measurement window (through 2026-05-01).
- **`firstStreakMilestone` deferred.** Planned as the third trigger (streak >= 7) but not wired until Day 14 data shows whether the first two triggers produce ratings.

## Unrelated pending work (NOT in the rating-prompt commit)

- Uncommitted ASO doc updates: `ASO_EXECUTION_PLAN.md`, `ASTRO_COMPETITOR_INTELLIGENCE.md`, `APPFIGURES_ASO_INSIGHTS.md`, new `POST_APPROVAL_MOMENTUM_STRATEGY.md`, `CLAUDE.md`, etc. Commit separately when reviewed.
- ASA Visibility campaign setup — deferred (urgency dropped after +23 brand-rank jump on 1.0.3 approval day).
- Screenshot OCR audit — Week 2.
- Subscription group consolidation — tracked in `project_subscription_groups.md`.

## Key files to read on resume

- `ScreenTimeRewards/Services/RatingPromptService.swift` (full impl — three guards: fired-flag, parent-auth, foreground-scene)
- `ScreenTimeRewards/Services/SessionManager.swift` (`isParentAuthenticated` is the load-bearing guard signal)
- `ScreenTimeRewards/Views/ParentMode/ParentDashboardView.swift` lines 56–69 (parent triggers)
- Plan: `/Users/ameen/.claude/plans/i-wanna-start-a-happy-moth.md`
- ASO rationale: `Marketing-Strategy/ASO/APPFIGURES_ASO_INSIGHTS.md` §5

## 2026-04-19: Parent-Device Wiring

### Why

Diagnostic on the child device (session 2026-04-19, branch `fix/pairing-subscription-sync`) confirmed `rating_prompt_fired_firstParentSuccess_v1 = true` — the slot had been burned silently by a prior TestFlight 1.0.4 install. `AppStore.requestReview(in:)` is a **no-op in the TestFlight environment** (Apple-documented), but our code flips the flag regardless because StoreKit's API is fire-and-forget and provides no callback indicating whether the sheet actually displayed.

Meanwhile the parent device had **zero rating-prompt call sites** — `grep -r RatingPromptService Views/ParentRemote/` came back empty. That's the wrong tradeoff for ASO rating volume: the parent device is the stronger surface because (1) the parent's Apple ID actually submits reviews (under-13 child Apple IDs may have In-App Ratings & Reviews disabled → silent burn), (2) no kid-retaliation 1-star risk, (3) paying user is already financially invested → higher delight at dashboard value-proof moments.

### What was wired

- **`ScreenTimeRewards/Services/RatingPromptService.swift:60-65`** — auth guard relaxed:
  ```swift
  let session = SessionManager.shared
  guard session.isParentAuthenticated || session.isParentDeviceAuthenticated else { … }
  ```
  `SessionManager` already tracks these as two independent states (`isParentAuthenticated` is set after PIN entry on the child device; `isParentDeviceAuthenticated` is set after PIN entry on the parent device). The header comment was updated to note both surfaces.

- **`ScreenTimeRewards/Views/ParentRemote/ChildUsageDashboardView.swift`** (`ChildHomeTabView`, lines ~332-386) — three hooks routing to a local `tryFirePromptForCurrentState()` helper that mirrors the child-side priority logic exactly:
  1. `.onAppear` → `tryFirePromptForCurrentState()`
  2. `.onChange(of: dataAdapter.earnedMinutes)` → `tryFirePromptForCurrentState()`
  3. `.onChange(of: dataAdapter.currentStreak)` → `tryFirePromptForCurrentState()`

  Priority: `firstWeeklyWin` (streak ≥ 3) preempts `firstParentSuccess` (earnedMinutes > 0). Same rule as child-side — prevents the weaker trigger from burning a slot after the stronger one already did.

- **`ScreenTimeRewards/Views/ParentMode/ParentDashboardView.swift:71-82`** — `[RatingDebug]` diagnostic print added at the top of `tryFirePromptForCurrentState()`. Matching line tagged `(parent-device)` added in the parent-side helper. Both log `earned`, `streak`, `fpsFlag`, `fwwFlag`, `legacyFlag` on every invocation.

### Per-device flags — clarification

App Group UserDefaults (`group.com.screentimerewards.shared`) live in the device-local App Group container. **No iCloud / CloudKit sync of the flag keys** (no `NSUbiquitousKeyValueStore`, no CKRecord mirroring). Each device maintains its own independent set of `rating_prompt_fired_<trigger>_v1` flags. Net result for a paired family install (parent device + child device): **up to 4 independent prompt opportunities** (2 triggers × 2 devices) before the ultimate guardrail of Apple's 3/365 per-Apple-ID cap kicks in.

### Diagnostic logs (intentionally left in)

`[RatingDebug] tryFire …` prints in both dashboards stay for now. They only fire on entry to the relevant dashboard surface, are tagged so you can tell which device emitted them, and cost effectively nothing at runtime. Remove once we have Day-14 ratings data (2026-05-01) and either surface has been verified to actually produce a review.

### Runtime verification still pending

- **Parent device — firstParentSuccess (the now-interesting case).** On a parent-device build where the App Group flag is unset, open the parent dashboard with `earnedMinutes > 0`. Expect: `[RatingDebug] tryFire(parent-device) earned=N streak=<3 fpsFlag=false …` immediately followed by `[RatingPromptService] DEBUG_LOG_RATING_PROMPT_FIRED: trigger=firstParentSuccess`. Second visit same conditions → `DEBUG_LOG_RATING_PROMPT_SKIPPED: already_fired`.
- **Cross-device independence.** After firing on the parent device, re-enter parent mode on the child device. The child-device flag state is unchanged by the parent-device fire; triggers on the child side still follow the child-device flag state.

### Known decisions from this addendum

- **Auth guard is OR, not a new role check.** We accept either `isParentAuthenticated` or `isParentDeviceAuthenticated` rather than introducing a `DeviceModeManager.shared.isParentDevice` branch, because both are already PIN-gated states — the "authenticated context only" invariant is preserved unchanged.
- **Per-device flags kept, not consolidated to iCloud.** Could have mirrored the flag via `NSUbiquitousKeyValueStore` to dedupe across devices. Deliberately did not: independent per-device slots are *favorable* for rating volume, and Apple's 3/365 per-Apple-ID cap is still the global ceiling. No spam risk.
- **No custom "Rate us" UI on parent device either.** Same reasoning as original — custom UI dilutes the system-prompt budget.
