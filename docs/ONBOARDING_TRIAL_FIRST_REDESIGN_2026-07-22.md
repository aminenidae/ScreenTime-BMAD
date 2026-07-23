# Onboarding Redesign — Trial-First "Finish Line" Flow

**Date**: 2026-07-22
**Status**: ✅ Implemented on `fix/onboarding-ux` — builds clean, pending on-device validation. The original spec (below) is preserved; see **Implementation status (as built)** immediately after for what actually shipped, including deviations.
**Supersedes the relevant parts of**: `docs/onboarding-redesign-plan.md`, `Marketing-Strategy/ONBOARDING_IMPROVEMENT_RECOMMENDATIONS.md` (P0 + UX-order sections)

---

## Implementation status — AS BUILT (2026-07-22)

### Final flow (both paths)
Shared front: **merged welcome (problem-led) → value slides (3, skippable) → "see it work" aha animation → one device question ("Whose phone are you setting up?")**. Then the fork:
- **Child's phone** → finish line ("You're all set", no-card trial auto-starts) → optional **Personalize** (config) or **Explore**.
- **Own phone** → parent welcome → install guide → pair (or **"I'll pair later"**) → parent finish line → dashboard.

No paywall anywhere in onboarding on either path — everyone enters on the no-card 14-day Family trial (auto-created by `SubscriptionManager`). A dismissible **trial banner** shows post-entry on both dashboards (parent-device + solo child-device, the latter guarded to unpaired only).

### Built vs. spec — key decisions & deviations
- **Welcome + Problem merged** into one problem-led screen; original 4-bullet emotional arc kept.
- **Value slides moved ahead of the device question** (both paths see them), **trimmed 5→3**, **sentence-cased + decoupled from ASO** (keyword screenshots produced separately), **skippable**.
- **New "see it work" aha animation** (canned, looping, respects Reduce Motion): learning earns time → reward unlocks → time drains → app **re-locks automatically**. Headline: "You set it up once. The app handles the rest."
- **Notification permission** asked on app entry (not bundled with Screen Time).
- **Screen Time permission coaching screen removed** — fires raw in-context at first app-pick (CEO chose speed over coaching; this is the one recommendation deliberately not followed).
- Coaching cards dropped from the finish line.
- **Parent paywall removed entirely** (not just relocated); conversion relies on the in-app trial banner + Settings + child-device lockout at trial end.
- **Design polish:** full sentence-case pass; parent path homogenized (install screen was stock-iOS styled); nav chrome + back buttons unified (shared `OnboardingBackButton`, rule: every screen except the first and the finish lines); front-of-funnel progress bar; dark-mode text-contrast fix (`AppTheme.accentText`).
- **Analytics:** `funnel_version` stamp on all onboarding events; new v2 events added; authorization events re-homed to the picker (`source=first_app_pick`); tutorial events re-scoped; screen-name maps rewritten.

### Still open (not built)
- **Primary success metric NOT wired:** `config_day1_completed`, `first_learning_app_added`, `first_reward_app_added` — enum cases exist, 0 firing sites; need hooking into the app-config save path.
- Social proof near the paywall (needs real ratings/testimonials); personalization quiz; palette refresh + illustration/icon-style unification; broader accessibility (Dynamic Type).
- BigQuery funnel dashboards need rebuild + split on `funnel_version`.
- On-device validation of the picker, pairing, purchase sheet, and trial-banner state.

---

## The bet, in one paragraph

Today onboarding keeps the parent in the role of a **prospect** the whole way — every screen is another "do I want to continue?", and quitting feels free because in her head she never really started. This redesign moves the **point of commitment earlier**: get the parent into the app as fast as possible, cross a clear **finish line** ("your app is installed, your free trial has started"), and only *then* invite her to configure. Crossing that line flips her from prospect to **owner**. Owners tinker; prospects abandon. We are deliberately trading a *guaranteed-configured* app for a *frictionless entry plus a psychological reason to keep going*.

This is a **conversion hypothesis**, and it is measurable (see Success Metrics).

---

## What changes vs. today

| | Today | New flow |
|---|---|---|
| Device questions | **Two** (app-mode question early, solo/family question late) | **One** (app-mode only) |
| Solo vs Family plan | Chosen during onboarding, drives which paywall shows | **Deferred** — everyone starts a Family-tier trial; plan chosen later, at conversion |
| Paywall | Hard gate mid-onboarding (Solo path) + separate parent hard-gate paywall | **Removed from onboarding entirely** — trial-first, no card |
| Screen Time permission | Dedicated onboarding screen, before config | **No dedicated screen** — requested in-context the first time the parent adds apps (code already does this) |
| Config (pick apps + goal) | Mandatory 18-step guided tutorial mid-onboarding | **Optional, post-entry** — offered at the finish line, reachable later from Settings |
| Where "setup complete" feels | Never — it just ends at a paywall | **Explicit celebration screen** before config |

---

## The new flow

1. **Welcome + Problem** (merged into one screen) — the promise.
2. **Value slides** — the existing solution slides. (Trim to ~3 + a "Skip" is recommended but optional — CEO's call.)
3. **One device question** — "Whose phone are you setting up right now?" → *my child's phone (set up here)* / *my own phone (manage remotely)*. This is the **only** question, and it sets the **app mode**, nothing else.
4. **Enter the app + auto-start the 14-day Family trial** — no card, no paywall, both paths.
5. **Finish-line celebration screen** (see below) — the psychological pivot.
6. **Optional config** — "Personalize my app" launches the ~30-second setup (pick reward app, pick learning app, set goal). "I'll explore on my own" drops them into the app with an empty-state nudge waiting.

Solo-vs-Family pricing is asked **later**, only when the trial is converting to paid — inside the app, when the parent is actually in buying mode.

---

## The finish-line screen (the crux)

The entire bet rests on this moment being framed as **completion + ownership**, not "you're done — now do a chore." Saying "setup complete!" and then immediately demanding required work reads as a bait and cancels the effect. Config must be framed as something an owner *gets to* do, not something they still *have to* do.

> 🎉 **You're all set.**
> Your app is live and your 14-day free trial has started.
>
> **[ Personalize my app → ]**  → launches the 30-second setup (pick child's first reward app, etc.)
> *I'll explore on my own*  → drops into the app; empty-state nudge waiting

- **Primary button owns the moment** and pulls the parent straight into the app picker — which is exactly where the iOS Screen Time permission prompt naturally fires.
- **Quiet secondary escape** for the curious; they still land somewhere that leads to a configured app.
- Copy leads with **"you're all set / it's live"** (ownership) and treats config as **personalization**, never as remaining required work.
- The trial disclosure ("14-day free trial has started") doubles as honest, up-front transparency — good for trust and for App Store review.

---

## Architecture implications

Verified against current code:

1. **The solo/family question (`SetupPathSelectionView`) is deletable from onboarding.** Its only two jobs are set in `OnboardingStateManager` — `shouldShowPaywall = (selectedPath == .solo)` and tier selection. Trial-first kills the paywall job; deferring pricing to conversion kills the tier job. Nothing else in onboarding needs `selectedPath`. Everyone starts on the **Family trial** tier.

2. **The one device question stays and keeps its real job.** `DeviceSelectionView` sets `selectedMode` = `.childDevice` / `.parentDevice`, which routes into the child-app mode vs. the parent-remote-dashboard mode. That is a genuine functional fork (not pricing) and must remain. **Plan = Family trial for everyone; app mode = still driven by this question. Keep the two decoupled.**

3. **The Screen Time permission does NOT need a dedicated onboarding screen.** `AppUsageViewModel.requestAuthorizationAndOpenPicker()` already checks `AuthorizationCenter.authorizationStatus` and requests authorization on demand before presenting the app picker. So the permission prompt fires the first time the parent adds apps (from the finish-line setup or from Settings). Removing `Screen4_AuthorizationView` from the onboarding sequence breaks nothing.

4. **The "tutorial" is the actual config, not a walkthrough.** `GuidedTutorialContainerView` is where learning apps, reward apps, and the goal/ratio get chosen. Making it optional is fine; making the *config it performs* impossible-to-reach is not — hence the finish-line prompt + the Settings-tab entry point + the home-screen empty-state nudge.

5. **The parent branch's hard-gate paywall (`ParentPaywallView`, `onSkip: nil`) is removed too.** Same trial-first logic dissolves it — the parent path also enters the app on a no-card Family trial.

---

## Safety nets (because curiosity alone is a weak driver)

An entry with zero configured apps shows off nothing, so the trial can burn with no "aha." Three nets, in priority order:

1. **The finish-line "Personalize my app" primary button** — the main funnel into setup.
2. **Home-screen empty-state card** — unmissable "Pick your child's first reward app →" for anyone who skipped the prompt. This is the one net that turns "curiosity *might* lead them there" into "the app *leads* them there."
3. **Settings-tab entry** — the tutorial/config is reachable from Settings whenever no apps are configured yet.

---

## Analytics / Firebase events — MUST be re-mapped (not optional)

The onboarding funnel in Firebase/BigQuery keys off per-screen events, and several of them point at screens this redesign **deletes or reorders**. If we ship the flow changes without updating the events, the funnel silently corrupts: deleted-screen events stop firing (dashboards show a cliff that isn't real), and the numeric `screen_name` map emits **wrong labels** for the screens that remain. Every flow change below has a matching analytics change.

### Current onboarding events (verified in `Analytics/AppAnalytics.swift` + firing sites)

**Child path** — driven by `OnboardingStateManager`, which fires `onboarding_screen_viewed` / `onboarding_cta_tapped` with a `screen_name` from a numeric map (`screenName(for:)`):

| screen # | current `screen_name` | fate in new flow |
|---|---|---|
| 1 | `problem` | merges with welcome — relabel |
| 2 | `solution` | keep (may shrink to ~3 sub-steps) |
| 3 | `path_selection` | **DELETED** |
| 4 | `authorization` | **DELETED as a screen** (permission moves in-app) |
| 5 | `tutorial` | **removed from sequence** (becomes optional, post-entry) |
| 6 | `paywall` | **DELETED** |
| 7 | `activation` | replaced by the finish-line screen |

Plus, fired directly:
- `onboarding_attempt_started`, `onboarding_welcome_viewed`, `onboarding_welcome_cta_tapped`
- `onboarding_device_selection_viewed`, `onboarding_device_type_selected` (param `device_mode`: parent/child)
- `onboarding_path_selected` (param `path`: solo/family) — **retire**
- `onboarding_screen2_step{0..4}_advanced` (solution sub-steps)
- `authorization_requested` / `authorization_granted` / `authorization_denied`
- `onboarding_tutorial_step` / `onboarding_tutorial_dropped` / `tutorial_completed`
- `paywall_viewed` / `paywall_plan_selected` / `paywall_purchase_*` / `paywall_dismissed` / `paywall_user_cancelled`
- `onboarding_freemium_offer_shown` / `_accepted` / `_declined`
- `onboarding_completed`, `onboarding_skip_tapped`, `onboarding_skip_confirmed`

**Parent path** — `ParentOnboardingCoordinator.screenName(for:)`: `parent_welcome`, `parent_paywall`, `parent_setup_guide`, `parent_pairing`.

### Events to RETIRE (stop firing — their screens are gone from onboarding)

- `onboarding_path_selected` — the solo/family question is deleted.
- All in-onboarding `paywall_*` events — no paywall in onboarding. (The paywall events still exist for the *in-app* conversion paywall later; scope them so onboarding-time vs. conversion-time are distinguishable.)
- `onboarding_freemium_offer_shown/_accepted/_declined` — the freemium rescue lived on the onboarding paywall; gone.
- `parent_paywall` screen_name — the parent hard-gate paywall is removed.
- `onboarding_tutorial_*` / `tutorial_completed` fired as a *mandatory onboarding step* — these move to the optional post-entry config (see new events); don't delete the event names, **re-scope** them so they're attributable to the optional flow, not the onboarding funnel.

### `screen_name` map — MUST be rewritten

`OnboardingStateManager.screenName(for:)` and `ParentOnboardingCoordinator.screenName(for:)` must be rewritten to match the new sequence. Do **not** leave the old numeric→label map in place with screens removed — it will mislabel every remaining step. Recommendation: add a `funnel_version` (or `onboarding_version`) param to every onboarding event so pre/post cohorts never get silently averaged together in BigQuery.

### NEW events to ADD

| Event | When | Why |
|---|---|---|
| `trial_started` (or reuse `subscription_started`, tier=`family`, status=`trial`) | On app entry, auto-start | Trial no longer implied by a purchase; must be logged explicitly at entry for both paths |
| `onboarding_finish_line_shown` | Finish-line celebration screen appears | Marks the new commitment point |
| `onboarding_finish_line_personalize_tapped` | "Personalize my app" tapped | Primary funnel into config |
| `onboarding_finish_line_explore_tapped` | "I'll explore on my own" tapped | Measures how many defer config |
| `config_started` | Config/app-picker opened (from finish-line, empty-state, or Settings), with `source` param | Entry into setup, by source |
| `first_learning_app_added` / `first_reward_app_added` | First app of each type selected | Building blocks of the primary metric |
| `config_day1_completed` | ≥1 learning **and** ≥1 reward configured within 24h | **The primary success metric** — the real proxy for "saw it work" |
| `empty_state_nudge_shown` / `_tapped` | Home-screen "pick first reward" card | Measures the safety net |
| `settings_config_entry_tapped` | Config opened from Settings tab | Measures the fallback net |

### Permission events change *context*, not name

`authorization_requested/granted/denied` still fire — but now at **first app-pick**, not on a dedicated onboarding screen. Add a `source` param (e.g. `first_app_pick`) so grant-rate can be compared against the old onboarding-screen grant rate. `AppUsageViewModel.requestAuthorizationAndOpenPicker()` (and `Screen4`'s existing calls) are the emit sites to reconcile.

### Definition change to flag loudly

`onboarding_completed` **changes meaning**: today it fires at activation *after* the paywall; in the new flow it should fire at **app entry** (finish line), because that's where onboarding now ends. This is a redefinition — historical "completion rate" is not comparable across the cut. Document the cutover date and use `funnel_version` so dashboards can split the cohorts.

---

## Success metrics (how we know the bet paid off)

Pull from the existing Firebase/BigQuery onboarding funnel; add events where missing.

- **Primary:** % of trial starters who configure **≥1 learning app + ≥1 reward app within 24h** of entry. This is the real proxy for "saw it work."
- Screen Time permission **grant rate** (expected to rise — asked in-context, post-commitment, vs. cold mid-onboarding).
- **Onboarding completion → app entry** rate (expected to rise sharply — far fewer screens, no permission wall, no paywall wall).
- Trial → paid **conversion** (the ultimate test; slower signal).
- Guardrail: watch that the faster entry doesn't just move the drop-off to "entered app, never configured, never converted."

If the day-1 configuration rate is healthy, the bet was right. If it sags, make the empty-state nudge louder before touching anything upstream.

---

## Open questions / decisions still to make

- **Value slides:** keep all five, or trim to ~3 + a "Skip"? (Recommendation: trim; CEO's call.)
- **Where exactly the solo/family pricing choice surfaces at conversion** — dedicated screen vs. pre-selected-from-device-answer default. (Leaning: ask at conversion, when they're in buying mode.)
- **Notification permission** — currently piggybacks on the (soon-removed) authorization screen. Needs a new home (or its own small in-context moment).
- **Progress indicator** — add one consistent "Step X of Y" across the shortened flow? Low cost, worth it.

---

## Rough build scope (for the follow-up planning pass — not yet estimated)

Likely touched:
- `Views/Onboarding/OnboardingFlowView.swift` — merge Welcome+Problem, reroute after the single device question.
- `Views/Onboarding/Screens/OnboardingContainerView.swift` — remove path-selection, authorization, and mandatory-tutorial steps from the sequence; add the finish-line screen.
- `Views/Onboarding/Screens/SetupPathSelectionView.swift` — remove from flow (keep file or delete — TBD).
- `Views/Onboarding/Screens/Screen4_AuthorizationView.swift` — remove from flow.
- `Views/Onboarding/Screens/OnboardingStateManager.swift` — drop `selectedPath`/`shouldShowPaywall` gating; everyone → Family trial.
- Parent branch (`ParentOnboardingCoordinator`, `ParentPaywallView`) — remove the hard-gate paywall; enter on trial.
- New: finish-line celebration screen + home-screen empty-state nudge + Settings-tab config entry.
- Trial start: auto-start the no-card Family trial on app entry for both paths.
- Analytics (see the dedicated section above — this is required, not a nice-to-have):
  - `Analytics/AppAnalytics.swift` — add the new event cases; re-scope tutorial/paywall events; add `funnel_version` + `source` params.
  - `OnboardingStateManager.screenName(for:)` and `ParentOnboardingCoordinator.screenName(for:)` — rewrite the maps to the new sequence (retire `path_selection`, `authorization`, `paywall`, `parent_paywall`).
  - Emit `trial_started`, finish-line events, config/first-app events, empty-state + settings-entry events.
  - Reconcile `authorization_*` emit sites (`AppUsageViewModel.requestAuthorizationAndOpenPicker`, `Screen4`) with the new in-context `source`.
  - Update the BigQuery funnel dashboards to the new step definitions; split cohorts on `funnel_version`.

**Next step:** turn this scope into an actual implementation plan (order of changes, what's verifiable at each step) before writing code.
