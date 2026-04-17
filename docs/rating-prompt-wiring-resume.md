# Rating Prompt Wiring — Resume Notes

**Branch:** `feature/streamline-usage-recording`
**Date:** 2026-04-17
**Status:** Code wired, **build not verified**. Continue from verification step.

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
