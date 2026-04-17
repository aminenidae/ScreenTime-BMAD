# Rating Prompt Wiring — Resume Notes

**Branch:** `feature/streamline-usage-recording`
**Date:** 2026-04-17
**Status:** Code wired, **build not verified**. Continue from verification step.

## Why

Brain Coinz approved 1.0.3(1) on 2026-04-17 with 0 reviews. Per Ariel Michaeli (Appfigures, 15+ yrs ASO): rating **volume** (not stars) is the primary App Store ranking lever for the first 30 days, and 75%+ of users are gone by day 2 — so the first-delight rating prompt must fire early and once. Source: `Marketing-Strategy/ASO/APPFIGURES_ASO_INSIGHTS.md` §5.

## What was wired

Single-shot system review prompt via `SKStoreReviewController` / `AppStore.requestReview(in:)`, gated by a UserDefaults flag in the shared app group `group.com.screentimerewards.shared`. Apple's own 3-per-365-day rate limit applies on top.

**New file:**
- `ScreenTimeRewards/Services/RatingPromptService.swift` — singleton with `requestReviewIfEligible(trigger:)` and `drainPendingIfNeeded()`. Queues via `rating_prompt_pending_v1` when triggered without an active foreground scene (e.g., extension-driven shield drop while app backgrounded); drains on next `.active` scenePhase. Fires flag `rating_prompt_fired_v1`.

**Call sites (3 total, 2 code paths, 1 shared flag):**
1. `Services/BlockingCoordinator.swift:1049` — child-side `.firstUnlock` at the end of the `!tokensToUnblock.isEmpty` branch in `syncAllRewardApps`. This is the real shield-drop event path (confirmed by tracing — `AppUsageViewModel.unlockRewardApp/s` both route through this coordinator).
2. `Views/ParentMode/ParentDashboardView.swift:60,65` — parent-side `.firstParentSuccess` on `.onAppear` (guard `earnedMinutes > 0`) and `.onChange(of: dataAdapter.earnedMinutes)`. Both share the same fired flag, so whichever trigger fires first consumes the slot.
3. `ScreenTimeRewardsApp.swift:109–112` — drain hook in the `scenePhase .active` handler for background-queued prompts.

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
   - Child flow: learning goal completes → shield drops → expect `DEBUG_LOG_RATING_PROMPT_FIRED: trigger=firstUnlock` on first unlock only.

3. **ASO-side verification (Day 14, 2026-05-01):** `mcp__astro__get_app_ratings(appId: "6753270211")` — any review count > 0 is working-as-intended.

## Known decisions (do not re-debate on resume)

- **Single flag, two triggers:** whichever trigger fires first wins; later trigger no-ops. Apple's global 3-per-365 limit applies anyway.
- **No custom "Rate us" UI.** Ariel: custom UI dilutes the system-prompt budget.
- **Child Apple ID eligibility risk accepted:** if the child device uses a Family Sharing managed Apple ID that can't submit reviews, the prompt fires but submits nothing. Many "child" devices are shared-family devices on a parent's Apple ID anyway. Not over-engineering detection.
- **No metadata edits** during the 14-day ASO measurement window (through 2026-05-01).

## Unrelated pending work (NOT in the rating-prompt commit)

- Uncommitted ASO doc updates: `ASO_EXECUTION_PLAN.md`, `ASTRO_COMPETITOR_INTELLIGENCE.md`, `APPFIGURES_ASO_INSIGHTS.md`, new `POST_APPROVAL_MOMENTUM_STRATEGY.md`, `CLAUDE.md`, etc. Commit separately when reviewed.
- ASA Visibility campaign setup — deferred (urgency dropped after +23 brand-rank jump on 1.0.3 approval day).
- Screenshot OCR audit — Week 2.
- Subscription group consolidation — tracked in `project_subscription_groups.md`.

## Key files to read on resume

- `ScreenTimeRewards/Services/RatingPromptService.swift` (new, full impl)
- `ScreenTimeRewards/Services/BlockingCoordinator.swift` line ~1030–1050 (`syncAllRewardApps`, child trigger)
- `ScreenTimeRewards/Views/ParentMode/ParentDashboardView.swift` lines 56–69 (parent triggers)
- `ScreenTimeRewards/ScreenTimeRewardsApp.swift` line ~109–112 (drain hook)
- Plan: `/Users/ameen/.claude/plans/i-wanna-start-a-happy-moth.md`
- ASO rationale: `Marketing-Strategy/ASO/APPFIGURES_ASO_INSIGHTS.md` §5
