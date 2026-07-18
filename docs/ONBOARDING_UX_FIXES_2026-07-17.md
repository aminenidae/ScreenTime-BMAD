# Onboarding UX Fixes — 2026-07-17

## Why (funnel evidence, Firebase BigQuery `analytics_518672259`, Jul 3–16)

24 saw welcome → 17 reached device selection → 14 picked a device → 11 hit Screen Time
permission → 7 granted → 4 reached paywall → 3 tapped "Not Now" → **all 3 accepted the
freemium trial rescue**. Zero real purchases (the only "purchase" was our own sandbox test).

Conclusion: paywall + freemium rescue work. The leaks are **upstream**:
- **Welcome screen:** ~29% quit (re-sells instead of advancing; no expectations set).
- **Device-selection screen ("WHOSE DEVICE IS THIS?"):** biggest killer (~42% quit at/before
  it). The buyer — a parent alone on her own phone at night — cannot answer it truthfully:
  it's not her kid's device, and "Parent's Device" implies a child device already exists.
  Then a **mandatory child-name field** (red border when empty) blocks Continue.
- **Screen Time permission:** 3 of 11 denied. Partly the upstream own-phone confusion
  (picking "Child's Device" on the parent's own phone means the permission would lock down
  HER phone — denying is rational).

Marketing contract being broken: ads + screenshots promise "Automated Parental Control" /
"No Battles. The App Handles Everything" — then the app opens with an architecture question
and a personal-data demand before showing any value.

## Fixes (all approved by CEO 2026-07-17)

### 1. Device-selection reframe — `Views/DeviceSelection/DeviceSelectionView.swift`
- Headline "WHOSE DEVICE IS THIS?" → **"Where does your child spend screen time?"**
  (sentence case) — a question the parent can answer regardless of whose phone she's holding.
- Cards re-labeled by *situation*, not device ownership:
  - **"On this device"** (→ child flow, image unchanged): "Set up learning goals and app
    locks right here."
  - **"On their own device"** (→ parent flow, image unchanged): "Turn this phone into your
    remote dashboard."
- Subtext adds the two reassurances: **~3-minute setup** + **"you can add the other device
  later"** (kills the wasted-effort dread).
- **Name field becomes optional**: "(optional)" in label, no red border on empty, Continue
  enabled as soon as a card is picked. Empty name defaults to localized "Child" / "Parent"
  (name is display-only: Settings, pairing labels, dashboards — all handle any string).
- Mode mapping semantics unchanged: childDevice = this device is controlled;
  parentDevice = remote monitor. No logic changes beyond the name default.

### 2. Welcome screen — `Views/Onboarding/OnboardingFlowView.swift`
- Add expectation line above CTA: "Setup takes about 3 minutes — start on your phone or
  your child's." (moves the promise from Screen 3, where it was wasted, to the front door).
- Body bullets: drop ALL-CAPS (`.textCase(.uppercase)` removed from ConfirmationLine).
  Headline + buttons keep brand caps.
- CTA "Show Me How" → "Start Setup" (advance, don't re-sell).

### 3. Screen Time permission — `Views/Onboarding/Screens/Screen4_AuthorizationView.swift`
- Audit correction: privacy reassurance rows already exist ("never see messages, photos,
  or browsing" + "turn it off anytime"). Only change: add **"location"** to the never-see
  list — the #1 surveillance fear for this category.

### 4. Localization impact (French — `feat/french-localization-prep`)
Changed/new English literals create new string-catalog keys. **DONE (e964de9):** French
translations added for all 13 new keys directly in Localizable.xcstrings. Also wrapped the
name-label/placeholder ternaries in String(localized:) — plain ternary literals inside
Text()/TextField() bypass the catalog at runtime (latent issue inherited from the old labels).
Still pending: native-speaker review alongside the rest of the 1.0.8 French strings.

## Verification
- Build in Xcode (CEO/dev machine) — no automated iOS build available in this environment.
- Watch Firebase funnel (same BigQuery queries) for: welcome→device-selection pass-through,
  device-selection→picked rate, authorization grant rate. Baseline above; first clean ad
  traffic starts Jul 17.
- Success = device-selection pass-through (viewed→picked) moving from ~60–80% toward 90%+,
  and onboarding completion rate (welcome→trial start) moving from ~17% toward 30%+.

## Branch / commits
- Base: `feat/french-localization-prep` (1.0.8 release line; French strings live here).
- Work branch: `fix/onboarding-ux`.
- Related but separate: RevenueCat AdServices attribution (SubscriptionManager.swift)
  committed directly on the release branch — independent of these UX fixes.
