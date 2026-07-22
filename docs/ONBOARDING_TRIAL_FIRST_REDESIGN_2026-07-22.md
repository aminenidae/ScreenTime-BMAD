# Onboarding Redesign — Trial-First "Finish Line" Flow

**Date**: 2026-07-22
**Status**: 📋 Spec — approved in principle, not yet built. Documented before coding.
**Supersedes the relevant parts of**: `docs/onboarding-redesign-plan.md`, `Marketing-Strategy/ONBOARDING_IMPROVEMENT_RECOMMENDATIONS.md` (P0 + UX-order sections)

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
- Analytics: events for finish-line shown/tapped, config-started, day-1 config completion.

**Next step:** turn this scope into an actual implementation plan (order of changes, what's verifiable at each step) before writing code.
