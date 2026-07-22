# Onboarding Improvement Recommendations

**Companion to** `ONBOARDING_COMPETITOR_ANALYSIS.md` (6 competitors + our-flow read). Written 2026-07-22.

**Framing:** our onboarding is half-excellent, half-self-inflicted. The child-device path is already competitive; the parent-device path has one decisive flaw. And across both, the *look* lags the market — competitors feel friendlier and cleaner than we do. Recommendations below are ordered by money impact, with a separate design section since design needs its own pass.

Every recommendation is tagged **P0 / P1 / P2** (priority) and marked **[verified in code]** where it's grounded in our actual source, or **[needs visual review]** where it should be confirmed against rendered screens.

---

## FIRST: prove where they actually quit (do this in parallel, costs nothing)

We already emit a full per-screen funnel (`onboardingWelcomeViewed`, `onboardingDeviceSelectionViewed`, `onboardingPathSelected`, `authorizationRequested/Granted/Denied`, `paywallViewed`, `paywallPurchaseCompleted`, etc.) into Firebase/BigQuery. **[verified in code]**

Before changing anything, pull the drop-off between each step. It will tell us in an afternoon whether people quit on the welcome screen, at device selection, at the permission ask, or at the paywall — and which path (parent vs child) bleeds. Every recommendation below is a hypothesis; this data confirms which ones matter. The claim "sometimes they quit on the first screen" is directly checkable: `onboardingWelcomeViewed` vs `onboardingWelcomeCtaTapped`.

---

## P0 — The one change that's costing money right now

### Move the parent-path paywall AFTER pairing, and give the same no-card trial. **[updated 2026-07-22 after seeing it rendered]**

**Correction to my earlier claim:** I said this paywall was "trial-less." Having now seen it rendered (`~/Downloads/Onboarding v1.0.9/Parent/`), that's wrong — it *does* offer a 14-day free trial, with a clean trial timeline (Today → Day 13 reminder → Day 15 first charge), clear pricing ($79.99/yr = "$1.54/week"), Family preselected. **As a paywall, it's well-made.** The problem is narrower but still decisive:

- It's a **gate with no escape** (`ParentPaywallView`, `onSkip: nil`) — no "Not now," no "pair first."
- The trial **requires a card** (Apple trial auto-charging Day 15) — unlike the child path's **no-card** trial.
- It's shown **before pairing or any value** — the parent commits a card before connecting a device or seeing a reward unlock.
- It **contradicts the screen before it**, whose card says "Pair whenever you're ready — no pressure to finish right now."
- **Unverified functional risk:** the prior ad investigation found the trial intro offer may be configured only on **Monthly**, while this paywall **defaults to Annual** — so the "Start 14-Day Free Trial" button may not actually grant a trial on the default plan. Verify in live StoreKit/ASC before trusting it.

This is still where all 5 ad parents died (`project_parent_paywall_conversion_wall`). **The fix (in priority order):** (1) move the paywall to *after* the parent has paired and seen it work; (2) match the child path's **no-card** trial so there's no card commitment to explore; (3) add a real "explore first / not now" escape. Keep the paywall's good craft (trial timeline, pricing clarity) — just change *when* it appears and *whether* it traps.

This is the single biggest lever in the entire document. If only one thing ships, ship this.

---

## P1 — Flow & structure

1. **Make the "free trial" mean the same thing on both paths.** **[updated after rendered review]** Both paths now offer a 14-day trial, but they're *different* trials: child path = no card, explore first; parent path = card required, gated before pairing. To the parent that reads as a bait-and-switch. Pick one trial model (ideally no-card everywhere) and honor it on both paths.

2. **Add "set it up later" to the pairing step.** **[verified in code — parent pairing has skip; make it prominent]** Getting the child's device in hand is the universal graveyard of this category. OurPact ("Pair later") and FlashGet ("Not now") both let the parent keep their account and momentum and finish tonight. Make our skip obvious, not buried.

3. **Keep permissions coached and un-bundled.** **[verified in code]** Our Screen Time permission screen is genuinely best-in-class (see design note below). One caveat: we request notification permission silently right after Screen Time authorization (`Screen4`). Consider giving notifications its own tiny "why" moment rather than piggybacking, so a denied Screen Time prompt doesn't take notifications down with it.

4. **Protect the 3-minute promise.** **[needs visual review]** We tell parents setup takes ~3 minutes. Walk the real flow on a device end-to-end and time it. If any step stalls (app-picker load, sync spinner, tutorial length), trim it — a broken time promise is its own abandonment cause.

---

## P1 — Copy & positioning: say our two hidden advantages out loud

We have two real advantages that appear **nowhere** in the onboarding copy:

1. **"No profile installed on your child's phone."** **[verified in code — we never install an MDM profile]** Four of six competitors force a scary Apple "device management profile" onto the kid's phone, complete with warnings that the administrator "may collect personal data." We don't. That's a genuine trust advantage for a privacy-nervous parent — and we never mention it. Put it on the welcome screen.

2. **Reward-for-learning as the emotional hook.** **[needs visual review of final copy]** Five of six competitors sell surveillance (cameras, microphones, message-reading). We're the positive one — kids *earn* the fun by doing the good stuff. OurPact's strongest screen closes on the *relationship* ("build a stronger relationship with you"). Ours should too. Lead with the outcome and the relationship, not the mechanics.

---

## P2 — UI & Design (now grounded in the rendered v1.0.9 child-path screens, reviewed 2026-07-22)

**Correction to my earlier code-based read:** I had guessed we used "darkened stock photos." Seeing the actual screens, that's wrong — **our hero illustrations are a genuine strength.** Warm, Pixar-style, positive, on-brand for "earn your fun," and competitive with or better than the field. Do **not** replace them. The real problems are elsewhere:

1. **Finish the ALL-CAPS cleanup — it's half-done and now inconsistent.** **[confirmed on the corrected child flow, 2026-07-22]** The updated screenshots reveal the app is *mid-migration*: the two device/rules screens are already in clean **sentence case** ("Where does your child spend screen time?", "Where will you manage the rules?", "On this device," "From my own phone") — and they look markedly more modern. But the welcome, problem, all five solution slides, and buttons are still bold uppercase ("REAL PARENTAL CONTROL. ZERO ARGUMENTS," "KIDS EARN SCREEN TIME," "START SETUP," "SHOW ME HOW," "STEP 1 OF 5"). So right now the flow flips between two typographic voices screen to screen. This *strengthens* the recommendation: you've already proven sentence case works and looks better on the device screens — finish the job across welcome, problem, solution slides, and buttons so the whole flow is consistent. Still the single cheapest, highest-visibility fix.

2. **Fix the visual inconsistency — we look like three different apps.** **[confirmed on screen]** Marketing/tutorial screens use beautiful Pixar illustrations; the path-selection screen ("How would you like to monitor your child?") is plain and flat with small icons and lots of empty space; the in-app tutorial uses a third style — 3D/claymation tab icons. Three unrelated visual languages in one flow. Pick one and apply it everywhere. The jump from polished illustrated slides to the bland path-selection screen right before the paywall makes the product feel unfinished.

3. **The palette is muted and slightly muddy.** **[confirmed on screen]** Everything sits on a desaturated cream/beige background with dark-teal text and teal buttons — warm but low-contrast and dated next to competitors' crisp white + one confident accent. Consider cleaner whites and a more vibrant, intentional accent to feel premium.

4. **Device-selection card legibility — FIXED, retracting my earlier criticism.** **[corrected 2026-07-22]** I previously flagged white ALL-CAPS labels sitting on busy illustrations. The corrected child flow has already replaced those with clean text-only cards (sentence-case title + subtitle + a radio selector on white). This is resolved and is a good template for the rest of the flow — no further action needed here.

5. **One accent color, used sparingly.** **[confirmed on screen]** Teal is on buttons, bullets, links, icons, highlight rings, and step pills all at once. Reserve the strong accent for the one primary action per screen.

6. **The marketing carousel is long and has no Skip.** **[confirmed on screen]** After welcome + device selection, the parent taps through the problem screen plus five near-identical "boy in a room" solution slides — six pure-marketing screens with no interaction, no way to skip ahead. Trim the solution flow to ~3 slides or add a persistent "Skip." Repetition reads as work.

7. **Keep the permission screen exactly as-is — it's excellent.** **[confirmed on screen]** "One tap to turn it on" shows a mock of Apple's real Screen Time dialog with a green "👆 Tap Allow" pill pointing at the highlighted button, plus two reassurance lines. Best-in-class, matches the very best competitors. Only change: sentence-case the headline.

**Net:** design isn't broadly broken — the illustrations and the permission screen are real assets. The "feels dated" impression comes almost entirely from (a) relentless ALL-CAPS, (b) three clashing visual styles, and (c) a muted palette. Fix those three and the app jumps a tier without touching the good art.

### Parent-path design findings (added 2026-07-22, rendered `~/Downloads/Onboarding v1.0.9/Parent/`)

8. **The Parent Welcome screen is the worst ALL-CAPS offender AND has a truncation bug.** **[confirmed on screen]** The entire screen is uppercase — including the *body paragraph* ("THIS DEVICE BECOMES YOUR REMOTE MONITOR…"), which is genuinely hard to read. Worse, the benefit-card titles are cut off mid-word: "MONITOR FROM ANYW…", "CREATE MEANINGFUL…", and the body "…NO PRESSURE TO FINISH RIGHT…". That's a real layout bug (text doesn't fit its container), not just a style choice. Fix the truncation and sentence-case it.

9. **A FOURTH visual style — the inconsistency is worse than first thought.** **[confirmed on screen]** The parent screens use iOS-native blue navigation ("‹ Back", "PARENT ONBOARDING" header) while the child flow uses a custom teal "‹ BACK" pill. So across the whole product: Pixar illustrations, flat path-selection cards, 3D-clay tab icons, *and* two different back-button/nav styles. Unify the navigation chrome too.

10. **The parent paywall itself is well-designed — don't rebuild it, relocate it.** **[confirmed on screen]** Trial timeline, Family-popular default, annual-savings framing, weekly price, no-commitment reassurance — all solid paywall craft, and mostly sentence-cased already. The only change it needs *as a screen* is the ALL-CAPS "CHOOSE YOUR PLAN" header. Its real problem is position (before pairing) and the missing escape — see P0, not here.

---

## P1 — UX & the ORDER of the screens (added 2026-07-22 after a proper flow review)

My first pass critiqued screens individually and took the sequence as given. Reviewing the actual order, there are real structural problems — bigger than any single screen's styling.

### The current child-path order (10 screens before the app opens)

1. Welcome (promise) → 2. **Device question #1** ("Where does your child spend screen time?" — *this device* / *their own device*) → 3. Problem → 4–8. Solution ×5 slides → 9. **Device question #2** ("How would you like to monitor your child?" — *On This Device Only* / *From a Parent Device*) → 10. Permission → 11. Tutorial (add apps) → 12. Paywall (Solo) / trial (Family) → 13. Activation.

### Headline problem: we ask the same device question twice, and they partly contradict

**[re-confirmed on the corrected child flow, 2026-07-22 — and it's even clearer now]** The two questions are almost the same sentence:

- **Screen 2:** "**Where does your child spend screen time?**" → *On this device* / *On their own device*. Picking "On this device" routes into the child flow.
- **Screen 9** (six screens later, after the problem + five solution slides): "**Where will you manage the rules?**" → *Right here on this device* / *From my own phone*.
- These are the same "this device vs. my own phone" decision, worded two slightly different ways, and they partly **contradict**: a parent who said "my child uses this device" on screen 2 is offered "From my own phone" again on screen 9, as if the first answer never happened.
- Technically they drive two different things (which app mode vs. which price tier), but the parent can't see that — they just feel asked the same thing twice. This is confusing, redundant, and sits right before the money. **Collapse it to ONE decision, asked once, that drives both routing and tier.** (Note: both screens are now clean sentence-case cards — the styling improved, but the redundancy is untouched.)

### Second problem: six marketing slides in the middle, with no "Skip"

After the parent has already committed by picking a device, they must tap through the problem screen plus five near-identical solution slides — six pure-pitch screens, no interaction, no way to skip. A parent who's already sold (they downloaded the app) is forced to sit through the sales pitch anyway. Trim to ~3 slides and add a persistent "Skip."

### Third problem: we ask for money before the parent ever sees it work

The paywall (Solo path) lands after the tutorial but before the "aha" — the parent pays before they've seen a single app actually unlock when a goal is met. Every strong competitor (Qustodio, FlashGet) gets the parent into a *working* product on a trial first, then asks. We tell, but never show, before charging.

### Fourth problem: the onboarding is serving two masters — the parent AND the App Store

The 5 solution slides are explicitly built to double as App Store screenshot sources, and their ALL-CAPS titles are deliberately keyword-loaded for Apple's search indexing ("points," "unlock apps," "limit screen time"). **[verified in code — `Screen2_SolutionStepView` comments]** That's a smart ASO trick, but it means these screens are optimized for Apple's algorithm, not for the parent's conversion. The best onboarding copy and the best ASO-keyword copy are rarely the same words. This is a strategic call for you: **should these screens convert parents, or feed the App Store?** They can't do both well. My recommendation — decouple them: design the onboarding for conversion, and produce dedicated ASO screenshots separately.

### Proposed reordered flow (~7 screens, gets to value faster)

1. **Welcome / promise** — keep, sentence-case.
2. **Tight value pitch** — 3 slides max, with "Skip." Keep the three strongest (earn time by learning → apps unlock automatically → time's up, it locks).
3. **One device/context question** — "Whose phone are you setting up right now?" → *My child's phone (set up here)* / *My own phone (manage remotely)*. This single answer drives both app mode and price tier. Remove the duplicate.
4. **Permission** — keep exactly as-is (it's excellent).
5. **Setup** — add learning apps, reward apps, goal.
6. **See it work** — one moment showing a reward unlocking when the goal is hit (the aha). Even a canned preview.
7. **Trial-first money** — start the no-card 14-day trial for *everyone* (not just the Family path), enter the app, and surface paid plans later as an in-app countdown banner rather than a hard gate.

Add one consistent progress indicator across the whole flow ("Step 3 of 6") so the parent always knows how far is left.

---

## Systematic UI/UX audit (measured against standard heuristics — honest scoring)

This is the checklist my first pass skipped. Scope: child-path rendered screens + code for the rest. I have **not** seen the parent-path or the paywall rendered.

**Nielsen usability heuristics**
- Visibility of system status — **Partial.** Solution slides have dots, the tutorial has a bar, but there's no single global progress indicator.
- Consistency & standards — **Fail.** Three visual styles; the device question asked two different ways; ALL-CAPS everywhere against platform norms.
- Recognition over recall — **Partial.** The duplicate device question forces the parent to remember and compare.
- User control & freedom — **Partial.** Back buttons exist; no "Skip" on the pitch; the Solo paywall is a hard gate.
- Flexibility & efficiency — **Fail.** No fast path for a parent who's already decided.
- Aesthetic & minimalist design — **Partial.** Lovely illustrations, undercut by 6 pitch slides, dense text, muted palette.
- Error prevention — **Pass.** Continue is disabled until a choice is made; the name field is optional.
- Help & documentation — **Pass.** Reassurance lines and "here's the screen you'll see" are good.

**Visual design principles**
- Hierarchy — **Weak** (ALL-CAPS flattens emphasis).
- Contrast / accessibility — **Issue.** White ALL-CAPS over busy illustrations (device cards) likely fails WCAG AA; verify teal-on-cream for body text. Check Dynamic Type and reduced-motion support (there are staggered bullet animations).
- Color discipline — **Fail.** One accent used on everything.
- Consistency — **Fail** (three styles).
- Whitespace / balance — **Partial.** Path-selection screen has large dead space; pitch slides run dense.
- Dark mode — **Pass** (handled in code).

**Onboarding-specific best practices**
- Permissions asked late and in context — **Pass** (a real strength).
- Time to first value / show the "aha" — **Fail.** The product is never shown working before the ask.
- Trial-first / defer the paywall — **Partial** (Family good; Solo hard gate; parent path fails hard — see P0).
- Reduce steps / progressive disclosure — **Fail-ish.** ~10 screens with a redundant decision; the tier question is asked too early and too abstractly.
- Social proof / trust signals — **Missing.** No ratings, testimonials, or "trusted by N families" near the paywall — a proven conversion lever top subscription apps use.
- Personalization / investment (questionnaire pattern) — **Missing / opportunity.** Many top-grossing subscription apps open with a short personalization quiz ("How old is your child?", "What causes the most screen-time fights?"). It builds investment (endowed-progress effect) and lets you tailor both setup and pitch. Worth A/B testing — we even have a skill scaffolded for it (`app-onboarding-questionnaire`).

---

## Suggested sequence

1. **Pull the funnel data** (afternoon, no code) — confirm the real drop points and which path bleeds.
2. **P0: unify the paywall to trial-first on the parent path** — the money fix.
3. **P2 quick design wins** (ALL-CAPS → sentence case, unify the three clashing visual styles, freshen the muted palette) — cheap, visible, and they land right on the first screens where abandonment happens. Keep the illustrations and the permission screen — they're assets.
4. **P1 flow + copy** (prominent "pair later," say the no-profile + rewards advantages out loud).
5. **Re-pull the funnel** and compare — the same analytics tell us if it worked.

**If you do nothing else:** the funnel pull (to know the truth) and the P0 paywall fix (to stop the bleeding). Those two are 80% of the value.

**But the two UX-order fixes are nearly as cheap and high-impact:** (a) collapse the duplicated device question into one, and (b) stop asking for money before the parent sees the product work. Both attack abandonment directly and are more fundamental than any styling change.
