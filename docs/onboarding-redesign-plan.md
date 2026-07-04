# Onboarding Redesign — Conversion & App Store Funnel Alignment

**Date**: 2026-07-03
**Status**: 🔄 In progress — Welcome ✅ shipped; Device Selection & Problem this pass; later screens pending
**Affected files**:
- `Views/Onboarding/OnboardingFlowView.swift` (`OnboardingWelcomeStep`, `ConfirmationLine`)
- `Views/DeviceSelection/DeviceSelectionView.swift`
- `Views/Onboarding/Screens/Screen1_ProblemView.swift`
- `Theme/AppTheme.swift` (design tokens — reference only)

---

## Why we're doing this

This is a **conversion** effort, not a cosmetic refresh. Onboarding is the continuation of the App Store funnel: a parent sees the store screenshots, decides to try it, installs — and the first thing they meet should feel like the same product they were just sold. Two leaks dominate today:

1. Some users **don't get past the very first screen**.
2. Most users **stop at the iOS Screen Time permission prompt** and never finish setup.

The goal of the redesign is to make the whole onboarding read as **one calm, confident funnel** that carries the store's promise all the way to the permission ask, so fewer people drop off.

---

## The north star — our App Store voice

The store screenshots (`screenshots/1.0.7/SC1–SC7`) already define the brand voice. Every onboarding screen should sound like them.

| # | Screenshot line |
|---|---|
| SC1 | **Automated Parental Control** |
| SC2 | **No Battles. The App Handles Everything** |
| SC3 | **Learn first. Play after.** — _Complete learning goals to unlock favorite apps._ |
| SC4 | **Track every minute.** — _Earned. Used. Remaining. All in one place._ |
| SC5 | **Apps stay locked until goals are met.** |
| SC6 | **Daily Limit Reached. Apps Lock.** |
| SC7 | **Safe browsing. Built in.** — _Harmful websites blocked automatically._ |

**Voice rules distilled from the above:**
- Short **two-beat lines**, Title/sentence case, **with periods**. (e.g. "Learn first. Play after.")
- Calm and benefit-first — **not** all-caps with wide letter-spacing (the old onboarding tone).
- Reuse the store's exact promise phrases inside onboarding so the handoff feels seamless.

---

## The onboarding design system (from the shipped Welcome screen)

The redesigned Welcome screen (`OnboardingWelcomeStep`) is the reference pattern for every later screen. Tokens live in `AppTheme.swift`.

- **Captioned hero card**: image + gradient overlay (`.clear → .black 0.5`, top→bottom) + bottom-left caption. Caption = **uppercase bold label** (`tracking ~1.5`) over a **sentence-case** sub in `white.opacity(0.9)`. Corner radius 20.
- **Headline**: `AppTheme.textPrimary(for:)` (navy in light, cream in dark — stays readable in both themes), uppercase, `tracking(1)`, ~28pt.
- **Confirmation lines**: a 6pt `vibrantTeal` dot + text in `textPrimary(for:).opacity(0.7)`, medium weight, ~15pt. Reusable shape: `ConfirmationLine` in `OnboardingFlowView.swift`.
- **Primary button (CTA)**: full-width `vibrantTeal`, white bold, `CornerRadius.medium`.

Colors (`AppTheme`): `vibrantTeal` #007373 · `deepNavy` #073B4C · `lightCream` #F5F3E1.

**Casing note:** onboarding headlines use uppercase (established on the Welcome screen), while the App Store creative uses Title case with periods. We keep uppercase headlines for internal consistency across onboarding and echo the store's exact _phrases_ in the sub-copy and lines. A future pass could revisit headline casing app-wide.

---

## Screen-by-screen status

| Pos | Screen | File | Status | Notes |
|---|---|---|---|---|
| 1 | Welcome | `OnboardingFlowView.swift` → `OnboardingWelcomeStep` | ✅ Shipped | Hero card + caption, "Real Parental Control. Zero Arguments.", teal-dot lines, "Show Me How". |
| 2 | Device Selection | `DeviceSelectionView.swift` | ✅ This pass | Calmer tone; cards echo the store — parent "Track every minute.", child "Learn first. Play after."; name field kept; CTA "Continue". |
| 3 | Problem | `Screen1_ProblemView.swift` | ✅ This pass | Calmed tracking, sentence-case lines, faster reveal; payoff echoes SC2: "No more battles. The app handles it." |
| 4 | Solution (5-step carousel) | `Screen2_SolutionStepView.swift` | Future | ASO-tuned carousel; align voice later. |
| — | Setup path (Solo/Family) | `SetupPathSelectionView.swift` | Future | Selection screen. |
| 6 | **Permissions (iOS Screen Time)** | `Screen4_AuthorizationView.swift` | ✅ This pass | **Biggest funnel leak.** Reworked into a priming screen: shows an annotated screenshot of Apple's real prompt (teal ring + "Tap Allow" on the Allow button), sets the passcode expectation, calms privacy fears, and adds a friendly deny-recovery with "Open Settings". Asset: `system_permission_preview` (cropped from `System Permission.png`). |
| 7 | Paywall (Solo) | `Screen6_TrialPaywallView.swift` | ✅ This pass | Tone/conversion pass only — **all compliance untouched** (post-trial price, auto-renew terms, Terms/Privacy links, Restore, dynamic RevenueCat pricing, trial timeline). Calmed the all-caps (incl. fine print + prices), added a "Try it free for 14 days" headline, store-echo value props, and softened the skip link ("Not now", honest that setup restarts). |
| 8 | Activation ("System is live") | `Screen7_ActivationView.swift` | ✅ This pass | Completion screen calmed to the design system: added a success mark, dropped tracking(3)→1, sentence-cased the subhead + card subtitles, faster card reveal (1.0s→0.4s). |

Parent-device flow (`ParentOnboardingCoordinator` and its screens) is out of scope for now.

---

## What changed this pass

### Screen 2 — Device Selection (`DeviceSelectionView.swift`)
Kept the layout, the two picture cards, and the name field (user decision). Tone + copy only:
- Headline "WHO WILL BE USING THIS DEVICE?" → **"WHOSE DEVICE IS THIS?"**, `tracking(3)` → `tracking(1)`.
- Explanation → sentence case: _"The app does a different job on each device. Pick the one you're setting up."_
- Nudge → sentence case "Tap one to begin".
- Card subtitles echo the store: parent **"Track every minute — from anywhere."**, child **"Learn first. Play after."** Card subtitle no longer all-caps.
- Name label + placeholder → sentence case ("Child's name", "e.g. Sam, Emma, Alex").
- Pulsing tap glow toned down (gentler, slower — less "casino").
- CTA "Get Started" → **"Continue"** (behavior unchanged).

### Screen 3 — Problem (`Screen1_ProblemView.swift`)
- Headline tracking `3` → `1`.
- Bullets rewritten into a tight story landing on the SC2 echo:
  1. Your child begs for more.
  2. You give in — or you're the bad guy.
  3. Either way, everyone loses.
  4. **No more battles. The app handles it.** _(payoff — teal + semibold)_
- Bullet rows restyled to match `ConfirmationLine` (sentence case, `textPrimary` @ 0.7, top-aligned dot).
- Hero caption sub → sentence case: _"Screen-time negotiations don't have to be this hard."_
- Bullet reveal sped up (per-line delay `1.0s` → `0.4s`) so the payoff lands in ~1.2s instead of ~3s.

No behavior or analytics changes on either screen — same `onDeviceSelected` callback and `onboarding.advanceScreen()`; only text and styling.

---

## Changelog

- **2026-07-03** — Welcome screen redesigned and shipped. Device Selection + Problem aligned to the new design system and App Store voice (this doc created).
- **2026-07-03** — Permission screen (Screen 4) reworked into a priming screen with an annotated screenshot of Apple's real prompt + passcode heads-up + deny-recovery ("Open Settings").
- **2026-07-03** — Paywall (Screen 6) tone/conversion pass: calmed all-caps, "free"-first headline, store-echo value props, softened skip link. No compliance or purchase-logic changes.
- **2026-07-03** — Paywall "Not now" now opens an exit-intent **freemium save screen** (`TrialSaveOfferView`) offering the no-card 14-day trial; keeps setup on decline (no more `resetSetup()` wipe). Reuses the existing local-trial system — no new trial engine.
- **2026-07-03** — Freemium take-rate wired to Firebase (`onboarding_freemium_offer_shown` / `_accepted` / `_declined` via `AppAnalytics`).
- **2026-07-03** — Activation screen (Screen 7) calmed to the design system + success mark + faster reveal. **Child onboarding flow now fully aligned end-to-end.**
- **2026-07-03** — **Bug fix:** freemium "Not now" was promising "14 days free" then locking the user out when their local trial was already expired. Now gated on `subscriptionManager.hasAccess` — offer only when the trial is active; otherwise honest "trial ended" alert.

## Decisions

- **2026-07-03 — Freemium as an exit-intent save, not a front-door option.** Priority is card capture (the Apple card-on-file trial via the paywall). The no-card trial must NOT be visible on the paywall (it would cannibalise card capture). Instead, tapping "Not now" now shows a **last-card save screen** (`TrialSaveOfferView`) offering the no-card 14-day trial — keeping the user + their setup instead of losing them.
  - **Key finding:** the app *already* runs a no-card 14-day local trial (`SubscriptionManager.createTrialSubscription()`, keychain-backed, `trial`/`grace`/`expired` states; `hasAccess` true during trial). Expiry lock is enforced safely — `blockRewardApps` refuses to apply *new* shields when access is gone but does **not** clear existing shields (fail-closed; child's apps stay blocked). App-entry lock: `ScreenTimeRewardsApp` shows `SubscriptionLockoutView` on child devices when `!effectiveHasAccess`.
  - **Behaviour now:** "Not now" is **gated on `subscriptionManager.hasAccess`** (i.e. the local trial is still active). If active → show the save offer; Accept → keep setup, `advanceScreen()` into the app on the active trial. If the trial is **already used up** (expired — e.g. a reinstall after the keychain trial ran out) → show an honest "Your free trial has ended" alert and keep them on the paywall (no false "free" promise). Decline → keep setup saved (no `resetSetup()`), return to paywall. `resetSetup()` is now unused (left in place as a utility).
  - **⚠️ Do not un-gate this.** Without the `hasAccess` gate, accepting the freemium offer just `advanceScreen()`s into the app and the app-entry lock (`SubscriptionLockoutView`) immediately catches an expired trial — a broken "14 days free" promise. Confirmed on a dev device 2026-07-03 (its keychain trial expired months ago).
  - **Family path is correct by design (NOT a leak):** payment for a Family plan happens on the **parent device**, never the child device. The child device's automatic 14-day trial is an intentional **bridge** — it keeps the child device working while the parent installs the app and subscribes on their own device; afterwards the child's access flows from the paired parent's entitlement (`effectiveHasAccess` = paired-parent access). So the child device must never show a paywall. The exit-intent freemium here applies to the **Solo** path only (the single self-pay device).
  - **Take-rate analytics (Firebase):** three real Firebase events fire via `AppAnalytics` — `onboarding_freemium_offer_shown` (denominator), `onboarding_freemium_offer_accepted` (win), `onboarding_freemium_offer_declined`, each with a `tier` param. Take-rate = accepted ÷ shown. (Replaced the earlier DEBUG-only `logEvent` logging.)

- **2026-07-03 — Guided tutorial stays mandatory.** Evaluated making Screen 5 (the 18-step "tutorial") optional. It is not a tour — it's the actual setup (pick learning apps → pick reward apps → configure → set goal/ratio → start monitoring, via `GuidedTutorialContainerView` + `TutorialModeManager`). Skipping it leaves a non-functional app. Decision: keep mandatory for now; a future option is to shorten it to the ~6 essential steps using smart defaults. Not doing that this pass.

## Maintenance notes

- **`system_permission_preview` asset is a real screenshot** — it's English-only and shows the current app icon + the "Allow with Passcode" button variant. **Re-capture it** if the app icon/name changes, if you localize onboarding, or if Apple changes the dialog. The annotation position (`allowCenterY` etc. in `SystemPromptPreview`) assumes the 1206×2210 crop; re-measure if the crop changes.
- The button label varies by device ("Allow with Passcode" vs "Allow"/"Continue" when no passcode is set) — the annotation and copy say "Allow", which reads correctly for the common passcode case.
