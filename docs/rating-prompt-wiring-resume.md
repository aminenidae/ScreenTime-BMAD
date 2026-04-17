# Rating Prompt Wiring — Resume Notes

**Branch:** `feature/streamline-usage-recording`
**Date:** 2026-04-17
**Status:** Code wired, **build not verified**. Continue from verification step.

## Why

Brain Coinz approved 1.0.3(1) on 2026-04-17 with 0 reviews. Per Ariel Michaeli (Appfigures, 15+ yrs ASO): rating **volume** (not stars) is the primary App Store ranking lever for the first 30 days, and 75%+ of users are gone by day 2 — so the first-delight rating prompt must fire early and once. Source: `Marketing-Strategy/ASO/APPFIGURES_ASO_INSIGHTS.md` §5.

## What was wired

Single-shot system review prompt via `SKStoreReviewController` / `AppStore.requestReview(in:)`, gated by a UserDefaults flag in the shared app group `group.com.screentimerewards.shared`. Apple's own 3-per-365-day rate limit applies on top. **Parent-authenticated context only** — never fires for a child-facing session.

**File:**
- `ScreenTimeRewards/Services/RatingPromptService.swift` — singleton with `requestReviewIfEligible(trigger:)`. Three guards before firing: (1) not already fired (App Group flag `rating_prompt_fired_v1`), (2) `SessionManager.shared.isParentAuthenticated == true`, (3) `activeForegroundScene()` returns a foreground-active scene. Whole method is `@MainActor` to safely read `SessionManager`.

**Call sites (2, both parent-side):**
1. `Views/ParentMode/ParentDashboardView.swift:60` — `.firstParentSuccess` on `.onAppear` (guard `earnedMinutes > 0`).
2. `Views/ParentMode/ParentDashboardView.swift:65` — `.firstParentSuccess` on `.onChange(of: dataAdapter.earnedMinutes)`.

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
   - Fresh install → complete parent onboarding → paywall → parent dashboard shows earned minutes > 0 → expect system rating prompt + console line `DEBUG_LOG_RATING_PROMPT_FIRED: trigger=firstParentSuccess`.
   - Second launch → same flow → expect `DEBUG_LOG_RATING_PROMPT_SKIPPED: already_fired` and no prompt.
   - Child-device flow: learning goal completes → shield drops → expect NO prompt (child context, parent not authenticated). PIN-enter to parent mode on child device, open dashboard with earned minutes > 0 → expect prompt to fire.
   - Parent-session locked (e.g., app backgrounded on child device, returns without re-auth) → dashboard appears → expect `DEBUG_LOG_RATING_PROMPT_SKIPPED: parent_not_authenticated`.

3. **ASO-side verification (Day 14, 2026-05-01):** `mcp__astro__get_app_ratings(appId: "6753270211")` — any review count > 0 is working-as-intended.

## Known decisions (do not re-debate on resume)

- **Parent-authenticated context only.** Prompt is guarded by `SessionManager.shared.isParentAuthenticated`. Revised 2026-04-17 after recognizing three child-context failure modes: (1) kid-retaliation 1-star reviews as payback for screen-time restrictions, (2) under-13 child Apple IDs may have In-App Ratings & Reviews disabled → prompt fires but submits nothing and burns the single slot, (3) Kids-Category / COPPA prompting-kids concerns. The child-side `.firstUnlock` call site in `BlockingCoordinator.swift` was removed.
- **Single flag, dashboard-only triggers.** Both `onAppear` and `onChange` call sites on `ParentDashboardView` share `rating_prompt_fired_v1`; first successful fire consumes the slot. Apple's global 3-per-365 limit applies on top.
- **No custom "Rate us" UI.** Ariel: custom UI dilutes the system-prompt budget.
- **No metadata edits** during the 14-day ASO measurement window (through 2026-05-01).

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
