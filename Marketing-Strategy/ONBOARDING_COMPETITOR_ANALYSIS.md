# Onboarding Competitor Analysis

**Why this doc exists:** Our onboarding is losing users at the very first screens. We have downloads, but people quit before they ever reach the product. This doc walks through competitors' onboarding flows screen-by-screen to find what they do differently, and what we should test.

**Status:** Started 2026-07-21 with AirDroid Parental Control. More competitors to be added as screenshots come in.

---

## Competitor 1: AirDroid Parental Control

Source: 15 screenshots in `~/Downloads/Airdroid - Parental Control Competitor/` (parent device + child device), captured 2026-07-21.

### Their flow, step by step (with real timestamps from the screenshots)

| Time | Screen | What happens |
|------|--------|--------------|
| 21:41 | First launch | Intro screen appears. iOS notification permission pops up immediately on top of it. |
| 21:42 | Slides 1–5 | Optional swipe-through carousel: monitor remotely, track location, set app limits, see notifications, social content alerts. |
| 21:43 | Slides 6–7 | Website restrictions, promo video. Then user taps "Sign up". |
| 21:43 | Create account | Email+password form, or one tap with Apple / Google. |
| 21:44 | Google sign-in | Standard system dialog. Account created. |
| 21:44 | "Whose device is this?" | Two big cards: **Mine** (I manage my child's device) vs **My Child's** (supervise this device). |
| 21:45 | Terms + Agree | One screen, checkboxes pre-checked, single "Agree" button. |
| 21:45 | Pairing screen | QR code + download link + a 9-digit code that "is always valid". "Check binding status" link to see if the child device connected. |
| 21:47 | Child device | Scans QR → App Store → installs "AirDroid Kids" → enters the code. |

**Total: about 4 minutes from first open to "waiting for child device to connect." No payment screen anywhere in this flow.**

### What they do well (and we should learn from)

1. **The very first screen is an exit ramp, not a gate.** Sign-up buttons (Apple / Google / email) are visible on screen 1 and stay pinned on every slide. The 7-slide carousel is browsable but 100% optional — there's also a "Skip" in the corner. A motivated parent can be past sign-up in two taps without reading anything. Nobody is forced to sit through a presentation.

2. **One idea per slide, written as a parent benefit.** "Track your child's location." "Set downtime and app limits." Five words, one picture, done. No feature lists, no settings, no decisions to make. Slides ask nothing of the user — every decision (device role, permissions, setup) comes *after* the account exists.

3. **The commitment ladder is ordered by cost.** Look → one-tap sign-up → pick device role → agree to terms → pair. Each step is slightly bigger than the last, and the expensive one (getting the *child's* device and installing a second app) comes last, after the parent has already invested 3 minutes. By then quitting feels like wasting work.

4. **No paywall in onboarding at all.** They let the parent get fully set up and paired before any money conversation. This is the single biggest structural difference from our flow — we ask for ~$75/year before the parent has seen anything work.

5. **Pairing is designed to survive interruptions.** The 9-digit code "is always valid" (no 5-minute expiry pressure), there's a QR *and* a typed code *and* a shareable link, and a "check binding status" button so the parent isn't staring at a screen wondering if anything happened. They also float a customer-support chat bubble on the sign-up and pairing screens — right where people get stuck.

6. **Terms screen is one tap.** Checkboxes pre-checked, one "Agree" button. Legal is a speed bump, not a wall.

### What they do badly (don't copy)

1. **Notification permission fires the instant the app opens** — before the app has said a single word about itself. That's the first thing a new user sees. Asking for something before giving anything is exactly the mistake that causes first-screen abandonment.
2. **Their promise is surveillance-heavy.** "Check surroundings via camera and microphone of the child's device" on slide 1. That will scare off a chunk of mainstream parents (and it's the opposite of our reward-based positioning — a differentiation opportunity, not something to imitate).
3. **The child-side app is where they bleed.** AirDroid Kids sits at **1.4 stars**. Their parent-side onboarding is smooth, but the kid-device experience is hated. Confirms the pattern: in this category the pairing/child step is where products die.

### What this suggests about OUR first-screen abandonment

Users quitting on screen 1–2 means the first screens are either **asking for something** (money, account, permission, a decision) or **not promising anything** before asking. Ideas to test, in order of expected impact:

1. **Move the paywall out of the setup path.** Already identified as the root cause of zero ad conversions (see `project_parent_paywall_conversion_wall`). AirDroid proves the category norm is: set up first, pay later. A parent who has paired a child device and seen the dashboard has a reason to pay; a parent on screen 1 does not.
2. **Make screen 1 a promise, not a task.** One sentence about the outcome ("Your kid earns screen time by learning") + a way to start immediately. If our first screen currently asks the user to make a choice or grant something, that's the leak.
3. **Let impatient users skip ahead from every intro screen.** Persistent "get started" action + Skip, like their pinned sign-up buttons.
4. **Delay permissions until they're needed and explained.** Never on first launch.
5. **Order steps so the expensive ask (child device in hand, Screen Time permission) comes last**, after the parent has invested a few minutes.

### Open questions to check against other competitors

- Where (if anywhere) do others put the paywall — before pairing, after pairing, after first value?
- Do others require an account before showing the product, or allow anonymous exploration?
- How do others handle the "you need your child's device now" moment?
- Slide count on intro carousels (AirDroid: 7, all optional).

---

## Competitor 2: Kidslox

Source: 15 screenshots in `~/Downloads/Kidslox/` (parent device + child device), captured 2026-07-21.

### Their flow, step by step (with real timestamps from the screenshots)

**Parent device:**

| Time | Screen | What happens |
|------|--------|--------------|
| 10:31 | First screen | "Whose iPhone is this?" — Parent iPhone (monitor *from* this device) vs Child iPhone (supervise *this* device). Two big illustrated cards. No intro slides, no pitch — this IS screen 1. |
| 10:32 | Sign in | Apple / Google / Email. One-line tagline: "protects children online". |
| 10:37 | Choose your role | Mother / Father / Guardian / Grandparent / Other. |
| 10:38 | Your details | Name (pre-filled from sign-in), role, optional photo. |
| 10:38 | Set parent PIN | 4-digit PIN "to stop your child from accessing the Kidslox app". |
| 10:39 | Notification warm-up | Their OWN screen before the iOS popup: "Allow notifications for secure Kidslox protection" + expandable "See why" with 4 concrete reasons (SOS alerts, blocked-site attempts, tamper alerts, geo-zones). Has Skip. |
| 10:40 | **PAYWALL** | "Protect your child from addiction!" over a video of a child in bed with a phone. Family $69.99/yr pre-selected as "best value", Basic $49.99/yr below, long feature-comparison table. **Has an X to close.** No visible free-trial wording. |

~9 minutes from first open to paywall, with account, PIN, and notification opt-in already done.

**Child device (pairing):**

| Time | Screen | What happens |
|------|--------|--------------|
| 10:33 | "Do you have a Kidslox account on a parent device?" | "I have an account → ENTER SAFETY KEY" or "I'm new here → CREATE ACCOUNT" (can start on child device directly). |
| 10:34 | Enter safety key | 6-digit code shown on the parent device. |
| 10:43 | Expectation-setting | "You need your child to be present, or you should know their device passcode" — explains Face ID will be needed, and the passcode fallback trick. |
| 10:44 | Screen Time permission coaching | A fake mock of the iOS dialog with a finger pointing at the correct button ("Continue"), THEN the real iOS dialog fires. |
| 10:46 | MDM profile explanation | "It's a little complicated, but we will walk you through the steps." Then a long, honest list of what data the profile collects, per Apple policy. |
| 10:47 | Safari profile download | Browser opens with a 3-step overlay ("tap Allow, tap Close, tap the cross") over the iOS "download configuration profile?" dialog. |
| 10:48 | Final steps checklist | Illustrated: Settings → Profile Downloaded → Install → return to Kidslox. "Can't find downloaded profile?" rescue link. |
| 10:49 | iOS install + warning | Apple's own screen: "The administrator may collect personal data, add/remove accounts and restrictions…" — genuinely scary system text they can't control. |

### What they do well (and we should learn from)

1. **Permission coaching is best-in-class.** Before every scary iOS popup they show their own screen that (a) explains why in parent-benefit terms, and (b) literally shows a picture of the upcoming dialog with a finger pointing at the right button. Nobody faces an Apple permission cold. This is directly copyable for our Screen Time permission step.
2. **Honest expectation-setting before hard steps.** "It's a little complicated, but we will walk you through the steps" + "You need your child to be present, or know their passcode." Telling the parent *before* they start what they'll need (the child, Face ID, a few minutes) prevents mid-flow abandonment and lets them come back prepared.
3. **Notification warm-up screen with reasons + Skip** — the anti-pattern AirDroid got wrong, done right.
4. **Rescue paths everywhere in pairing:** "I don't have a safety key", "Can't find downloaded profile?", "Download the profile again", help icon on every screen.
5. **Even their paywall respects the order: invest first, ask later.** It appears ~9 minutes in, after account + PIN + notifications, and it has a close button. And note the pricing anchor: Family $69.99/yr framed as $5.83/month.

### What they do badly (don't copy)

1. **Screen 1 asks a question before making any promise.** "Whose iPhone is this?" with zero value statement — the only pitch is a 4-word tagline on screen 2. If a parent isn't already sold from the App Store page, nothing here sells them.
2. **A form-heavy start:** role → name → photo → PIN is four screens of admin work before anything interesting happens. Feels like a government form, not a product.
3. **The child-device path is brutal.** MDM profile via Safari, Settings app, an Apple warning about "the administrator collecting personal data" — they mitigate it well with coaching, but it's a wall of scary. (Our Screen Time approach avoids the MDM profile entirely — that's a real competitive advantage worth saying out loud in our marketing.)
4. **Fear-based paywall imagery** (child in bed with phone, "addiction!") — on-brand for them, off-brand for us.
5. **"Time rewards" is a paid Family-plan feature for them.** Rewards is our core concept — for us it's the product, not an upsell line item. Differentiation opportunity.

---

## Competitor 3: Qustodio

Source: 8 screenshots in `~/Downloads/Qustodio/` (parent side), captured 2026-07-21.

### Their flow, step by step (with real timestamps from the screenshots)

| Time | Screen | What happens |
|------|--------|--------------|
| 22:11 | First launch | Clean welcome: friendly doodle hugging a heart, "Digital parenting made easy — Supervise your kids' screen time on all their devices, from a single dashboard." One button: "Get started" (+ Log in link). iOS notification popup fires immediately on top (same mistake as AirDroid). |
| 22:12 | Create account | "Welcome! Create your account and enjoy a **free trial of our Premium features**." Name + email + password form. Notably NO Apple/Google one-tap — email only, plus a terms checkbox and reCAPTCHA. |
| 22:13 | Confirm role | "Welcome, Amine — Please confirm this is your own device and you want to manage your child's online activity from here." One "Confirm" button + escape hatch: "Not what you were expecting? Try Kids App instead." They *assume* parent and ask to confirm — no two-card choice screen. |
| 22:13 | **DASHBOARD** | The real product. "Good evening!" greeting, pink banner "Your trial ends in 3 days — Upgrade now!", and an empty-state card: "Protect your family's devices — Add your first device and start monitoring straight away → Get started." |
| 22:53 | Add a child | Name, gender, birth year. Avatar auto-generated from initial. |
| 22:54 | Protect a device | "Which device does your child use?" dropdown: Android / iOS / Windows. |
| 22:54 | iOS instructions | 3 numbered steps: open the App Store on the child's iPhone, download "Kids App Qustodio", log in and confirm. |

**~2 minutes from first open to the real dashboard. Premium trial auto-started with no payment info. No paywall screen anywhere — just a dismissible countdown banner.**

### What they do well (and we should learn from)

1. **Trial-first, not paywall-first.** The account creation screen *promises* a free trial ("enjoy a free trial of our Premium features"), the trial starts automatically with no card, and the money conversation is reduced to a slim "Your trial ends in 3 days — Upgrade now!" banner *inside* the product. The parent explores a full-featured app under a countdown instead of hitting a wall. Of the three competitors, this is the cleanest answer to "where does the paywall go?" — nowhere; a trial does its job.
2. **Fastest time-to-product of all three.** Welcome → account → one confirm → dashboard. Two minutes. Compare AirDroid (~4 min to pairing screen) and Kidslox (~9 min to paywall).
3. **"Confirm, don't ask."** Instead of a "whose device is this?" decision screen, they assume it's the parent's device and ask for one confirmation, with a "Try Kids App instead" escape link. One less decision for a tired parent at 10pm.
4. **The dashboard itself onboards.** Empty states do the guiding ("Add your first device and start monitoring straight away"), shortcuts are visible but inert until setup. The product is the tutorial — setup tasks feel like using the app, not like a gate before the app.
5. **Even the pitch is calm.** One sentence, one warm doodle, zero fear imagery. The single-dashboard promise is concrete and believable.

### What they do badly (don't copy)

1. **Notification popup the instant the app opens** — third competitor, second one making this mistake (Kidslox is the only one that warms it up properly).
2. **No Apple/Google sign-in.** Typing name + email + password + captcha on a phone is real friction, and it's the one place their flow is heavier than AirDroid's two-tap account.
3. **The child-device handoff is just text instructions** — "open the App Store on your child's phone, download, log in." No QR code, no status indicator, no support presence. Weakest pairing start of the three (AirDroid's QR + always-valid code + binding status remains the best).

---

## Competitor 4: OurPact

Source: 12 screenshots in `~/Downloads/OurPact/` (parent side), captured 2026-07-21. Closest competitor to our positioning — their pitch is habits/relationship, not surveillance, and their slide art even shows a "2-hour allowance" concept.

### Their flow, step by step (with real timestamps from the screenshots)

| Time | Screen | What happens |
|------|--------|--------------|
| 22:07 | Slides 1–3 | 4-slide carousel, Skip in corner. "Encourage healthy screen time habits" → "Peace of mind with flexible tools to manage your child's routines" (art shows a homework schedule, a **2-hour allowance**, TikTok blocked, YouTube on a timer) → "Give your child freedom and keep them safe." |
| 22:07 | Slide 4 | The closer: "OurPact helps your child develop better habits **and build a stronger relationship with you**." → Get Started. |
| 22:08 | Sign in | Continue with Apple / Continue with Google / email. One screen for login+signup. |
| 10:58 | My Family (empty) | "Let's get started by adding your child → ADD CHILD." The iOS notification popup fires HERE — after account, inside the app — not at first launch. (Still a raw uncoached popup, but better timed than AirDroid/Qustodio.) |
| 10:59 | Add child | Two fields: name, age. Done. |
| 10:59 | Pair device | "Sami has been created! Pair to start managing… **PAIR LATER**." Honest choice: **Full Pair** (needs a computer + cable, all features) vs **Quick Pair** (no computer, basic features), with a feature-comparison table (web filter, app rules, etc. are Full-Pair-only). |
| 11:00 | Full Pair path | Download "OurPact Connect" on a computer, plug the child's device in with a cable, follow instructions. |
| 11:01 | Quick Pair path | Scan QR on the child's iPhone to get "OurPact Jr.", enter a 6-character pairing code. |

**No payment screen appears anywhere in the captured flow.** (OurPact has a free tier; monetization presumably comes later in-app — not verified from these screenshots.)

### What they do well (and we should learn from)

1. **The only competitor selling a positive outcome.** "Develop better habits," "build a stronger relationship with you," freedom + safety. No cameras, no addiction imagery, no fear. This is OUR corner of the market, and their final slide — the *relationship* — is the emotional note our rewards concept deserves to end on too.
2. **"PAIR LATER" — every hard step is deferrable.** The single most abandonment-prone step (getting the child's device) has an explicit skip, so the parent keeps their account, child profile, and momentum, and can come back tonight. Nobody else offered this.
3. **Honest tiered pairing.** Full Pair (computer + cable) vs Quick Pair (phone only) with a plain comparison table of what each unlocks. They let the parent choose their effort level instead of forcing the maximal setup — and they're upfront that more effort = more features.
4. **Add-child is two fields** (name, age). Kidslox wanted role + name + photo + gender + birth year across multiple screens.
5. **Notification permission asked in context** — after sign-in, on the family screen, at the moment the app could plausibly need it — not blasted at first launch.

### What they do badly (don't copy)

1. **Full Pair requires a computer and a USB cable** — in 2026. It's the price of their deep iOS control, but it's a brutal ask; many parents don't have a laptop handy (or at all). Same lesson as Kidslox's MDM: the deep-control apps all pay a heavy setup tax on the child device. We don't.
2. **The carousel is still a gate.** Unlike AirDroid, sign-in buttons aren't on the slides — you swipe (or Skip) through 4 slides before seeing "Get Started." Mild, but it's one more screen between the store and the product.
3. **Raw notification popup** — right timing, but still no explanation of why (Kidslox's warm-up remains the model).

---

## Competitor 5: Kroha (Parental Control Kroha)

Source: 21 screenshots in `~/Downloads/Kroha/` (parent + child device), captured 2026-07-21. The most surveillance-heavy and permission-hungry flow examined so far.

### Their flow, step by step (with real timestamps from the screenshots)

**Parent device:**

| Time | Screen | What happens |
|------|--------|--------------|
| 23:04 | First launch | An 8-slide feature carousel starts — and Apple's **ad-tracking permission dialog** ("Allow Kroha to track your activity across other companies' apps?") fires on top of slide 1, at second zero. Worst first impression in the study. |
| 23:05–23:07 | Slides 1–8 | Sounds Around (listen through the child's microphone), App Blocker, Location Tracker, YouTube Control, **Eye Protection** (warns the child if the screen is too close to their eyes — genuinely novel), Web Control, Messengers History ("view child's messages in 11 messengers"), Screenshots of the child's screen. Skip available; every slide has "Learn more". |
| 23:07 | "Who uses this device?" | Child / Parent cards + Next. |
| 23:08 | Sign in | Email + password, or Apple / Google / Facebook. Plus a genuinely good extra: **"Link another parent by code"** — a second parent joins the existing family account without new credentials. |
| 23:08 | Loading | "Waiting for data synchronization. It can take some time…" + Refresh devices. |
| 23:09 | Create a PIN | 4-digit, "required to prevent the child from logging into the parent account." |
| 23:09 | Popup pile-up | Landing on the home screen triggers the iOS notification dialog AND a "Help — write to our support team" tooltip at the same time, stacked on top of the setup content. Three competing messages at once. |
| 23:10 | Parent home / pairing | "Add the child's device!" — 6-character code in big tiles, "**Code valid until 2026-07-26**" (5 days), a "**Send code to your child**" share button, and a "**See how it works**" video link. |

**Child device:**

| Time | Screen | What happens |
|------|--------|--------------|
| 23:11 | Permission checklist | One screen listing Location (always-on), Photos, Contacts, Notifications as toggles, each with a one-line reason, "you can always update these later in Settings." Then the real iOS dialogs fire one by one. |
| 23:12 | MDM profile explanation | Numbered steps + "Watch tutorial" video link. |
| 23:13 | Data & Privacy | Expandable sections (Children's Privacy, Data from MDM) + Accept/Decline. |
| 23:14 | iOS Install Profile | "Parental Control MDM" certificate screen — same scary Apple territory as Kidslox. |

**No paywall anywhere in the captured flow. That's now 5 out of 5.**

### What they do well (worth stealing)

1. **The pairing code screen is the best-labeled of all five.** Big readable 6-character code, an explicit expiry date ("valid until 2026-07-26" — 5 days, not 5 minutes), a "Send code to your child" button that shares it via any messenger (acknowledging the child's device is often not in the same room), and a "See how it works" video right on the screen.
2. **"Link another parent by code."** Two-parent households are the norm and nobody else in the study handles the second parent this cleanly — one code, no shared passwords. (We should check what our story for parent #2 even is.)
3. **Child-side permission checklist before the popups.** One calm screen lists everything they'll ask for with a one-line reason each and "you can change this later" — then fires the dialogs. Not as polished as Kidslox's finger-pointing mockups, but the same right instinct: never fire an Apple dialog cold.
4. **Eye Protection is smart differentiation** — a health feature parents instantly get, and it gives their App Store listing a hook no one else has. A reminder that one distinctive, easily-explained feature can carry a listing.

### What they do badly (don't copy)

1. **An ad-tracking permission at second zero.** Before the app says hello, Apple asks the parent to let a parental-control app "track your activity across other companies' apps." For a privacy-sensitive audience, that's poison — and it's there purely for their ad attribution.
2. **Eight slides.** Longest carousel in the study, and by slide 8 the features have blurred together. AirDroid's rule (one benefit, five words) beats volume.
3. **Popup pile-up on arrival** — notification dialog + support tooltip simultaneously on top of the setup screen. Each popup steals attention from the other; the parent dismisses both without reading either.
4. **The surveillance stack is the deepest yet** — listening through the microphone, reading messages in 11 apps, screenshotting the child's screen, browsing their photos and contacts. Even more than AirDroid, this is the segment we should position *against*.
5. **MDM profile on the child device again** (5th competitor, 3rd MDM user) — with the added irony of a Data & Privacy screen needed to explain everything the profile collects.

---

## Competitor 6: FlashGet Kids (+ FlashGet Kidsafe child app)

Source: 12 screenshots in `~/Downloads/flashget/` (parent app) + 13 in `~/Downloads/flashget kidsafe/` (child app), captured 2026-07-21. The most complete capture in the study — full parent flow AND the entire child-side setup, end to end. FlashGet ships **two separate apps**: "FlashGet Kids" (parent) and "FlashGet Kidsafe" (child).

### Parent app flow (with timestamps)

| Time | Screen | What happens |
|------|--------|--------------|
| 23:18 | Slides 1–3 | 3-slide carousel: real-time location + geofence alerts → sync child's app notifications → **remote screen viewing + camera + microphone**. "Next"/"Got it". Surveillance-heavy by slide 3. |
| 23:19 | Sign up | Email + password + confirm password + nickname — a 4-field form, no Apple/Google button. |
| 23:20 | Email verification | 6-digit code emailed, 298s resend timer — but there's a **"Skip"** in the top corner (verification isn't a hard gate). |
| 23:20 | "Whose device is this?" | Parents' devices (filled primary button) / Kids' devices. |
| 23:21 | Supervise Child's Device | Agreement text + **Agree / "Not now"** (deferrable). |
| 23:21 | Add New Device (pairing) | 3-step progress bar. QR code + `flashget.app` link + a **9-digit binding code (775 663 543)** + "Check binding status" button + floating support-chat bubble. |
| 23:30 | Dashboard (post-pair) | Child device shows "Online, 100%". "Enable Full Mode" prompt, a "**Subscribe now and enjoy free use for at most 14 days!**" banner, then the notification permission popup fires here. Usage Report, Screen Mirroring (PRO), Block All Apps, Live Location. |
| 23:31 | Dashboard (trial running) | Same screen with "**Time left: 3 day(s) 0 hour(s)**" — a non-blocking trial countdown, exactly the Qustodio pattern. |

### Child app flow — "FlashGet Kidsafe" (with timestamps)

| Time | Screen | What happens |
|------|--------|--------------|
| 23:23 | "Whose device is this?" | On the CHILD app the primary button is flipped to **"Kids' devices"** (parent app defaults to parent, child app defaults to child — smart). Notification popup fires immediately. |
| 23:24 | Wrong-app guardrail | Tapping "Parents' devices" opens a sheet: "this app is for the child… if this is the parent's device, Download Now" → sends them to the correct app. Prevents the classic "installed the wrong one" dead-end. |
| 23:24 | Welcome to Kidsafe | Agreement + expandable "Data collected by MDM" + Agree. |
| 23:26 | Enter binding code | 9-digit code from the parent + "How to acquire a binding code?" help. |
| 23:26 | Binding Confirmation | "Your device will be bound to: **aminenidae@gmail.com**" + Confirm — shows the child exactly which account they're joining (transparency). |
| 23:27 | Location Access | Explainer + numbered coaching ("1. first pop-up tap Allow While Using, 2. second pop-up tap Change to Always Allow") → THEN the real iOS dialog fires, pre-explained. |
| 23:27 | Enable Microphone | Explainer before the real permission. |
| 23:28 | Enable Child Device Management | "Standard Mode" feature list: Screen Mirroring, Live Location, Geofence, Route History, Screen Time Limits, Content Management. |
| 23:28 | Enable Standard Mode | MDM profile: **"Download the profile" + "Not now"** (deferrable) with a mock of the iOS Install Profile sheet. |
| 23:28 | Install the profile | 4 numbered steps, each with a mock screenshot and a finger pointing at the exact button, ending with the "Profile installation successful" notification. **Best-in-class MDM coaching** — matches or beats Kidslox. "Profile installation failed?" rescue link. |
| 23:29 | Child home | "Supervision Mode — Your parents have not set a screen time limit, so you can schedule your device usage yourself." Amber warnings for features not yet enabled. Footer: "Your device is protected by your parents (aminenidae@gmail.com)." |

### What they do well (worth stealing)

1. **Trial-first, non-blocking — the Qustodio pattern confirmed a second time.** 14-day free trial, no card at signup, a countdown banner on the dashboard ("Time left: 3 days 0 hours") rather than a wall. Two of six competitors now use exactly this structure, and both are among the smoothest flows in the study.
2. **The child app defaults to "child," the parent app defaults to "parent."** Same "whose device?" screen, opposite primary button per app — the likely answer is pre-highlighted. Plus a **wrong-app guardrail**: pick the wrong role and it walks you to the correct app instead of dead-ending.
3. **MDM coaching is the best in the entire study.** Four numbered steps, each with a picture of the real iOS screen and a finger on the exact button, then the success notification. If we ever face a scary system screen, this is the template.
4. **Binding transparency for the child.** "Your device will be bound to [parent's email]" — the child sees who's supervising. Good for trust, and good for our reward framing where the child is a willing participant, not a target.
5. **Everything hard is deferrable** ("Not now" on the agreement, on the MDM profile) and pairing has QR + link + code + "check binding status" + support chat — the full AirDroid-grade pairing kit.

### What they do badly (don't copy)

1. **Heaviest signup in the study:** email + password + confirm + nickname + a 6-digit email verification, and no Apple/Google shortcut. That's a lot of typing before anything happens (the "Skip" on verification is a tacit admission it's too heavy).
2. **Surveillance-forward again** — slide 3 leads with remote screen viewing, camera, and microphone; the child app has an "Enable Microphone → listen to your child's surroundings" step. Same segment we should position against.
3. **Two separate apps to find and install** (Kids vs Kidsafe) — a naming-confusion tax they have to spend the wrong-app guardrail to paper over.
4. **MDM profile on the child device** — 4th of six competitors to require it.
5. **Notification popup fires uncoached** on both apps (parent: on the post-pair dashboard; child: at launch).

---

## Cross-competitor comparison (updated as competitors are added)

| Question | AirDroid | Kidslox | Qustodio | OurPact | Kroha | FlashGet | Us (today) |
|---|---|---|---|---|---|---|---|
| What's on screen 1? | Value slide + one-tap sign-up + Skip | "Whose iPhone?" role Q, no pitch | Promise + "Get started" | Benefit slide (4-slide + Skip) | Feature slide (8-slide) + **ad-tracking popup at sec 0** | Benefit slide (3-slide) | Un-skippable paywall path early (known issue) |
| Paywall in onboarding? | **None at all** | Yes, ~9 min, closable, after investment | **None — trial + banner** | **None visible** | **None visible** | **None — 14-day trial + countdown banner** | Immediate, un-skippable, before value |
| Time to real product | ~4 min to pairing | ~9 min to paywall | **~2 min to dashboard** | ~2 min to My Family | ~6 min to pairing | ~2 min to pairing | — |
| Account before value? | 2 taps (Apple/Google) | Yes + role/name/photo/PIN | Email form (no Apple/Google) | 2 taps (Apple/Google) | Email or Apple/Google/FB | **Email+pw+confirm+nickname+verify (heaviest)** | — |
| Device-role question | After account | Screen 1 | Assumed parent + confirm | Not asked | After slides | After account (per-app default flipped) | Early (`fix/onboarding-ux`) |
| Permission timing | Popup at launch (bad) | **Warm-up + mock-dialog coaching (best)** | Popup at launch (bad) | Raw popup, in-context (mid) | Ad-track + notif popups pile up (worst) | Coached on child app, raw on parent | — |
| Pairing design | QR + always-valid code + status + chat | Safety key + coached MDM + rescue | Text instructions only | Tiered + **PAIR LATER** | Code + 5-day expiry + "Send to child" + video | QR + link + code + status + chat + wrong-app guard | — |
| Child-side burden | Second app (1.4★) | MDM + Apple scare screens | Second app, parent login | Second app / computer+cable | MDM + Location/Photos/Contacts | Second app + MDM (**best coaching**) | No MDM — advantage to shout about |
| Positioning tone | Surveillance (cam/mic) | Fear ("addiction!") | Calm, neutral | **Positive: habits + relationship** | Deepest surveillance (mic, 11 msg apps) | Surveillance (cam/mic) | Rewards for learning (unique) |

**Pattern after 6 competitors — the verdict is now overwhelming:**

- **0 of 6 put a hard paywall in front of an uninvested parent.** Three (AirDroid, OurPact, Kroha) show no paywall in onboarding at all; two (Qustodio, FlashGet) run a **non-blocking free trial with a countdown banner** inside the product; one (Kidslox) waits ~9 minutes and keeps it closable. Our immediate, un-skippable paywall is the lone outlier across the entire field, and it's the prime suspect for first-screen abandonment.
- **The trial-first + countdown-banner model is the emerging best practice** (Qustodio and FlashGet), and both are among the fastest, smoothest flows. This is the most directly copyable structure for us.
- **Winning screen 1 = one promise + one button.** Never a form, a price, or (worst of all, Kroha) an ad-tracking permission at second zero.
- **Two-tap Apple/Google account is the norm.** The two heaviest signups (Qustodio email-only, FlashGet 4-field + email verification) both bolt on a "Skip" or are visibly clunky — a tell that they know it costs them.
- **Permission coaching is rare and valuable.** Only Kidslox and FlashGet's child app pre-explain iOS dialogs with mock screens + finger pointing; everyone else fires them cold. This is our single biggest UX opportunity for the Screen Time permission moment.
- **Every deep-control competitor pays a heavy child-device tax** (MDM profile in 4 of 6, or computer+cable, or a 1.4★ kids app). We avoid all of it and have never said so.
- **The child-device step is the universal graveyard.** OurPact's "Pair later," FlashGet's "Not now," and everyone's rescue links all exist to survive it.

**The assembled best-practice flow** (every piece proven in a live competitor): Qustodio/FlashGet's trial-first skeleton (promise → 2-tap account → straight to product with a trial running, paywall replaced by a countdown banner) + AirDroid's sign-up ergonomics and QR pairing with status check + Kidslox/FlashGet's mock-dialog permission coaching + OurPact's "pair later" escape and relationship-first message + our own structural advantage of no MDM profile on the child's phone. Positioning-wise, 5 of 6 lean surveillance; OurPact is the only one near our lane — our reward-for-learning angle is genuinely differentiated and should be the emotional close, not a buried feature.

---

## OUR FLOW vs the field (read from code, 2026-07-21, branch `fix/onboarding-ux`)

**Important structural fact:** we don't have one onboarding — we have **two, and they split at the second screen.** Which one you get decides everything, and only one of them has the problem.

### The shared opening (both paths)

1. **Welcome** — "Real Parental Control. Zero Arguments." Hero image + three benefit lines ("You decide what's safe — enforced automatically" / "Learning apps earn real time on the apps they love" / "No timers to manage. No fights to referee.") + the line "Setup takes about 3 minutes — start on your phone or your child's." One button: "Start Setup." **This is a promise-first screen, done right.**
2. **Device selection** — "Where does your child spend screen time?" → *On this device* (child path) vs *On their own device* (parent path). Text-only cards, optional name field, repeats the 3-minute expectation. Recently reworked and solid.

### Path A — child's device ("On this device") → the 7-screen flow

Problem → Solution → Setup-path (Solo/Family) → **Authorization** → Tutorial → **Paywall (conditional)** → Activation.

- **Screen 1 is a promise, not a task** ("The 'five more minutes' battle can end today"). No account, no price, no permission. ✅ Matches the field's best openers.
- **The Screen Time permission screen is best-in-class.** It shows a real screenshot of Apple's dialog with a highlight ring and a "👆 Tap Allow" callout over the exact button, plus reassurance ("Private by design… turn it off anytime"). This is the Kidslox / FlashGet mock-dialog coaching pattern — we already do it. ✅
- **The paywall is deferred and escapable.** It only appears on the *Solo* sub-path, after the parent has done the setup and tutorial; the *Family* sub-path skips it entirely and starts a **no-card 14-day trial**. Even on Solo, "Not now" opens a save-offer that grants the no-card trial. ✅ This is the Qustodio/FlashGet trial-first model.
- **Verdict: Path A is genuinely competitive** — arguably better than most of the field on permission coaching, and on-pattern for paywall placement.

### Path B — child's own device ("On their own device") → the parent flow

Welcome → Device selection → **Parent Welcome** → **PAYWALL** → Installation guide → Pairing.

**CORRECTION (2026-07-22, after seeing the parent path rendered — `~/Downloads/Onboarding v1.0.9/Parent/`):** I earlier claimed from the code that this paywall was "trial-less." **That was wrong.** The rendered "Choose Your Plan" screen *does* offer a 14-day free trial, and it's actually well-built:

- Clear value props (monitor remotely, track learning, control apps, up to 2 parent devices), Individual vs **Family "POPULAR"** (preselected), Monthly vs **Annual "Save ~56%"** (preselected).
- A best-practice **trial timeline**: *Today — Free Trial → Day 13 — Reminder → Day 15 — First Charge.* This is exactly the Apple-endorsed "no surprise charge" trust pattern.
- Pricing **$79.99/year framed as "just $1.54/week,"** button **"Start 14-Day Free Trial,"** "No commitment. Cancel anytime." As a *paywall*, this is competently designed.

So the accurate criticism is narrower but still real:

1. **It's a gate, not a step.** There is no "Not now," skip, or "pair first" escape (`ParentPaywallView` is invoked with `onSkip: nil`). The parent cannot pair a device or see anything work without first starting the trial.
2. **The trial requires a card.** It's an Apple free trial that auto-charges on Day 15 — a bigger ask than the child/Family path, which gives a **no-card** trial (explore now, pay later). That asymmetry is the real inconsistency: same company, two trials, very different friction.
3. **It's shown before pairing/value.** The paywall is screen 4 of the parent flow — before the install guide and before any pairing. The parent commits a card before they've connected a device or seen a reward unlock.
4. **A broken promise one screen earlier.** The Parent Welcome screen's third card literally says *"Pair whenever you're ready — no pressure to finish right [now]"* — and the very next screen is a card-required paywall gate. The copy promises no pressure; the flow applies it immediately.

This is still the screen documented as the root cause of **0 ad conversions** in `project_parent_paywall_conversion_wall` (all 5 ad parents died here). But the fix is more precise than "add a trial" (there is one): **let the parent pair and see it work first**, and/or **offer the same no-card trial the child path gives**, and/or **add a real escape** — rather than gating a card-required trial before any value.

### Side-by-side: our two paths vs the field

| Dimension | Field norm (6 competitors) | Our Path A (child device) | Our Path B (parent device) |
|---|---|---|---|
| Screen 1 | Promise or role question | Promise ✅ | Promise (welcome) then gate |
| Paywall placement | Never a hard gate pre-value; trial or deferred | Deferred + no-card trial ✅ | **Card-required trial GATE, pre-pairing ❌** |
| Free trial offered? | Yes (5 of 6, or no paywall) | Yes, 14-day, **no card** ✅ | Yes, 14-day, **card required, no escape** ⚠️ |
| Paywall craft (as a paywall) | Varies | Good | **Good — trial timeline, clear pricing ✅** |
| Permission coaching | Rare (only Kidslox, FlashGet) | **Mock-dialog + finger callout ✅ (top-tier)** | n/a on this path |
| Time-to-value | 2–4 min to product/pairing | ~3 min to activation ✅ | Blocked at paywall until card entered ❌ |
| Positioning | 5 of 6 surveillance | Rewards-for-learning ✅ (differentiated) | Rewards-for-learning ✅ |
| Child-device tax | MDM profile in 4 of 6 | No MDM profile ✅ | No MDM profile ✅ |

### The honest bottom line

Our onboarding is **not uniformly broken — it's half excellent and half self-inflicted.** The child-device path is competitive with or better than the field. The parent-device paywall is *well-crafted as a paywall* — the flaw is its **position and lack of escape**: a card-required trial gate shown before the parent can pair a device or see a single reward unlock, contradicting the "no pressure" promise one screen earlier. It's the one spot where we ask for a card before delivering any value — precisely where our ad traffic lands. Meanwhile two real strengths (best-in-class permission coaching, no MDM profile) go unspoken in marketing, and the **two-trials asymmetry** (no-card on the child path, card-required on the parent path) means "start free" means two different things depending on a choice the parent barely understands.

That's the gap to close. Recommendations to follow.

---

## Competitor 3: (to be added)
