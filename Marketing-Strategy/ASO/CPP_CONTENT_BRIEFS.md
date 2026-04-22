# Brain Coinz — 5 Custom Product Page (CPP) Content Briefs

**Drafted:** 2026-04-21
**Owner:** Ameen
**Target go-live:** 2026-04-30 (1 day before 1.0.4 flips)
**Status:** Briefs only — ASC creation pending

---

## What CPPs are and why we're using them

CPPs are **alternate product pages** for the same app, accessed via unique URLs. Each CPP can override the main product page's:
- Screenshots (1–10 images)
- Promo text (170 chars)
- App preview videos (optional)

CPPs **cannot** change the app Name, Subtitle, Keyword field, Description, category, or pricing. Those stay global.

**Why we're creating 5 for 1.0.4:**
1. **Attribution.** Each CPP URL is a tracking parameter — when we push traffic from TikTok or a parenting blog, we know exactly where the install came from in ASC Analytics → Source Type → "Product Page - Custom".
2. **Creative-match per audience.** A parent scrolling TikTok after yelling at their kid responds to different screenshots than a parent reading an ADHD blog.
3. **A/B signal.** With 5 CPPs running concurrently + the default page, we get 6 creative variants measured against the same keyword traffic. The best-performing screenshot order informs the next main-page refresh.

**Timeline to be live by May 1:**
- 2026-04-21 → 2026-04-23: Finalize briefs (this doc)
- 2026-04-24 → 2026-04-26: Create 5 CPPs in ASC, submit each for review
- 2026-04-28 → 2026-04-30: All 5 approved (~24–48h mini-review each)
- 2026-05-01: 1.0.4 + all CPPs live, URLs distributed to their respective channels

---

## The 10-screenshot pool (from `screenshots/1.0.4/en-US/final/`)

All CPPs draw from this set. Each CPP picks 3–10 and reorders for its audience.

| Slot | File | Content | Dominant tone |
|---|---|---|---|
| 1 | `01-parents-set-goals.png` | PARENTS SET / LEARNING GOALS (coral) | Step 1, cooperative |
| 2 | `02-kids-earn-screen-time.png` | KIDS EARN / SCREEN TIME (amber) | Step 2, reward |
| 3 | `03-earn-to-play.png` | EARN TO PLAY / LEARN BEFORE GAMING (orange hero) | Positioning |
| 4 | `04-unlock-apps.png` | UNLOCK APPS / AUTOMATICALLY (teal) | Step 3, magic moment |
| 5 | `05-unlock-apps.png` | UNLOCK APPS (orange hero, device UI) | Proof — real app |
| 6 | `06-track-time.png` | TRACK TIME EARNED (blue dashboard) | Proof — data viz |
| 7 | `07-limit-screen-time.png` | LIMIT SCREEN TIME, / AUTOMATICALLY (navy) | Step 5, control |
| 8 | `08-lock-apps.png` | LOCK APPS AUTOMATICALLY (purple) | Proof — enforcement |
| 9 | `09-setup-once.png` | SETUP ONCE / APP HANDLES THE REST (green) | Reassurance |
| 10 | `10-kids-play-guilt-free.png` | KIDS PLAY / GUILT-FREE (pink) | Emotional payoff |

---

## CPP 1 — TikTok parent-hook ("End-the-battle")

**CPP Name in ASC:** `Brain Coinz - TikTok`
**Reference name (internal):** `tiktok-battle`
**Audience:** Parents scrolling TikTok after a screen-time meltdown. Likely tired, emotional, 30–45 years old, looking for permission to stop fighting. High emotional resonance > feature comparison.
**Primary acquisition channel:** Organic TikTok (task #12 — 5 TikTok videos batch)
**Success metric:** PPV → Install CVR ≥ 8% (higher than default page, because traffic is pre-qualified)

### Screenshot order (5 slots, max emotional arc, no device-UI screenshots)
1. Slot 10 — KIDS PLAY GUILT-FREE (pink) — **lead with payoff, not problem**. TikTok viewers already have the problem. Show them the destination.
2. Slot 1 — PARENTS SET LEARNING GOALS (coral) — how it starts
3. Slot 4 — UNLOCK APPS AUTOMATICALLY (teal) — the magic moment
4. Slot 7 — LIMIT SCREEN TIME AUTOMATICALLY (navy) — the hands-off promise
5. Slot 9 — SETUP ONCE / APP HANDLES THE REST (green) — close with reassurance

**Rationale:** TikTok CVR data from 2024–2026 (Adam Lyttle, Appfigures) shows screenshots-as-hook outperform feature-stuffing 2–3x for social traffic. Stick to the 5 cream/narrative frames; drop the device-UI proof frames (5, 6, 8) — they don't translate at thumbnail scale on mobile web.

### Promo text (170 char)
> Stop yelling. Stop negotiating. Your kid sets the goal. Learning unlocks screen time. Apps lock themselves when time is up. You're not the bad guy anymore. Free 14 days.

(169 chars)

### Video
Optional. If task #12 produces a 15–30s TikTok cut, attach the same cut as the App Preview video.

### URL distribution
- TikTok bio link
- First-pin comment on every TikTok upload
- DM response template

---

## CPP 2 — Apple editorial / "New Apps We Love" pitch

**CPP Name in ASC:** `Brain Coinz - Editorial`
**Reference name (internal):** `editorial`
**Audience:** Apple editorial team reviewing for Today tab, App Store collections, "Apps We Love" features. Secondary: press/blogger traffic from editorial coverage.
**Primary acquisition channel:** Task #13 — Apple editorial pitch letter (uses this CPP URL as the "preview" link in the pitch)
**Success metric:** Editorial placement. Conversion rate is secondary — the pitch letter is the goal.

### Screenshot order (10 slots, full narrative, polished)
Use the full locked 1.0.4 set 1-10 in order. Editorial reviewers read all 10; they reward craft and coherence. The current sequence (promise/proof pairing) is specifically tuned for this.

### Promo text (170 char)
> Thoughtfully designed by indie developers for families. No yelling. No monitoring. No guilt. Kids earn screen time by learning; apps unlock and lock automatically. Try it free.

(170 chars)

### Video
Optional. If produced: a 20s "hero cut" showing the learn → unlock → play loop. Narration-free, music-led. Apple editorial prefers understated.

### URL distribution
- Direct link in the editorial pitch email (`pitch@apple.com`)
- Press kit page on brain-coinz.com (if one exists)
- Submission to Appfigures "Top Apps of the Week" roundup

---

## CPP 3 — Parenting communities / Reddit ("What finally worked")

**CPP Name in ASC:** `Brain Coinz - Community`
**Reference name (internal):** `community-evidence`
**Audience:** Parents on r/Parenting, r/ScreenTime, Facebook parenting groups, parenting blog comment sections. These parents have tried the iOS built-in Screen Time, Bark, Qustodio, etc. and found them lacking. They want evidence, not emotion.
**Primary acquisition channel:** Task #15 — organic posts in 3 parenting communities, always linking this CPP.
**Success metric:** PPV → Install CVR ≥ 5% (cold but qualified traffic); community-post engagement ratio

### Screenshot order (8 slots, evidence-first, proof frames dominate)
1. Slot 3 — EARN TO PLAY / LEARN BEFORE GAMING (orange hero) — the thesis statement
2. Slot 6 — TRACK TIME EARNED (blue dashboard) — data visualization, builds credibility
3. Slot 5 — UNLOCK APPS (orange hero device UI) — real app UI proof
4. Slot 8 — LOCK APPS AUTOMATICALLY (purple) — proof of enforcement
5. Slot 1 — PARENTS SET LEARNING GOALS (coral) — the cooperative frame
6. Slot 4 — UNLOCK APPS AUTOMATICALLY (teal) — the mechanism
7. Slot 7 — LIMIT SCREEN TIME AUTOMATICALLY (navy) — enforcement frame
8. Slot 9 — SETUP ONCE / APP HANDLES THE REST (green) — close

**Rationale:** Community parents are skeptical. Lead with proof frames (3, 6, 5, 8) before the narrative frames. They scroll to see if it's "real software or just marketing." Drop slots 2 and 10 — emotional framing reads as marketing-speak to this audience.

### Promo text (170 char)
> Kids earn screen time by hitting real learning goals you agree on together. Reward apps unlock when goals are met; they lock when time is up. No nagging. 14 days free.

(169 chars)

### Video
Skip. Communities link to CPPs; videos hurt load time and this audience reads over watches.

### URL distribution
- r/Parenting — 1 post explaining the method, CPP link in body
- r/ADHD / r/ADHDparents — 1 post focused on executive-function angle (or use CPP 5 instead)
- r/ScreenTime — 1 post comparing to iOS built-in Screen Time
- 2 parenting blog / newsletter placements

---

## CPP 4 — Indie App Santa (holiday discovery)

**CPP Name in ASC:** `Brain Coinz - Indie Santa`
**Reference name (internal):** `indie-santa`
**Audience:** Users browsing the annual Indie App Santa promotion (December). App enthusiasts, early adopters, design-conscious, willing to support indie devs. Less price-sensitive but want craft signal.
**Primary acquisition channel:** Task #14 — Indie App Santa submission (December window)
**Success metric:** Install volume spike during promotion window; Twitter/indie community mentions

### Screenshot order (6 slots, craft-first)
1. Slot 3 — EARN TO PLAY / LEARN BEFORE GAMING (orange hero) — strong visual opener
2. Slot 10 — KIDS PLAY GUILT-FREE (pink) — emotional payoff
3. Slot 1 — PARENTS SET LEARNING GOALS (coral) — the cooperative promise
4. Slot 6 — TRACK TIME EARNED (blue dashboard) — craft/data viz
5. Slot 4 — UNLOCK APPS AUTOMATICALLY (teal) — the mechanism
6. Slot 9 — SETUP ONCE / APP HANDLES THE REST (green) — close

**Rationale:** The coloured-hero illustration set is itself a craft signal. Indie enthusiasts notice when screenshots are visually coherent. 6 slots instead of 10 — indie viewers skim, reward confidence.

### Promo text (170 char)
> Made by indie parents tired of screen-time fights. A system kids actually want to use — they earn screen time by learning, apps unlock automatically. Free 14 days.

(168 chars)

### Video
Optional; if Indie Santa requires video, a 15s "indie hand-drawn aesthetic" cut.

### URL distribution
- Indie App Santa submission form
- Twitter/X thread announcing Indie Santa inclusion
- indiedev / indieapps Slack communities

---

## CPP 5 — ADHD / executive-function audience

**CPP Name in ASC:** `Brain Coinz - ADHD`
**Reference name (internal):** `adhd-focus`
**Audience:** Parents of neurodivergent children, especially ADHD. They've read about dopamine-reward loops, executive function, behavioral modification. They respond to language about *how the brain works*, not just "screen time."
**Primary acquisition channel:** Mix — ADHD subreddits (r/ADHDparents, r/ADHD), ADHD parenting blogs, Caroline Maguire newsletters, Dr Russell Barkley content comments. Also the `adhd timer` Astro keyword (Pop 5, Diff 65 — stretch target).
**Success metric:** Stable PPV → Install CVR ≥ 6%; traffic attribution from ADHD-specific sources

### Screenshot order (7 slots, dopamine-reward emphasized)
1. Slot 2 — KIDS EARN SCREEN TIME (amber) — the reward-earning frame, dopamine forward
2. Slot 4 — UNLOCK APPS AUTOMATICALLY (teal) — immediate reinforcement
3. Slot 6 — TRACK TIME EARNED (blue dashboard) — progress visibility (critical for ADHD executive function)
4. Slot 5 — UNLOCK APPS (orange hero device UI) — real app proof
5. Slot 1 — PARENTS SET LEARNING GOALS (coral) — shared agency
6. Slot 7 — LIMIT SCREEN TIME AUTOMATICALLY (navy) — structural limits (external scaffolding)
7. Slot 10 — KIDS PLAY GUILT-FREE (pink) — reduced guilt/shame, important for ADHD families

**Rationale:** Lead with the dopamine-reward loop (slots 2, 4, 6). ADHD parents immediately recognize this as positive-reinforcement architecture. The Slot 6 dashboard is load-bearing here — ADHD kids need external progress visibility; showing the tracking view validates the product's fit.

### Promo text (170 char)
> Built-in positive reinforcement for ADHD families. Clear goals, immediate rewards, visible progress, automatic limits. Reduces screen-time conflict and parental burnout. 14 days free.

(179 → trim to 170)

**Trimmed:**
> Positive reinforcement for ADHD families. Clear goals, instant rewards, visible progress, automatic limits. Cuts screen-time conflict. Try free for 14 days.

(163 chars)

### Video
Skip. This audience reads.

### URL distribution
- r/ADHDparents, r/ADHD (adult kids discussion)
- Additude Magazine sponsored post (if budget permits — see post-launch)
- Caroline Maguire newsletter collab (if responsive)
- Comments under ADHD TikTok parent creators

---

## Implementation checklist (for ASC creation, 2026-04-24 → 2026-04-26)

For each of the 5 CPPs:

- [ ] App Store Connect → Brain Coinz → Custom Product Pages → Create
- [ ] Set Reference Name (internal) per brief
- [ ] Set Localization = English (U.S.) primary
- [ ] Upload the specified screenshot set in the specified order (pull from `screenshots/1.0.4/en-US/final/`)
- [ ] Paste Promo Text per brief
- [ ] Attach App Preview Video if applicable
- [ ] Submit CPP for review (~24–48h each)
- [ ] Once approved, copy the unique URL (format: `https://apps.apple.com/us/app/brain-coinz/id6753270211?ppid=...`)
- [ ] Log URL in this doc per CPP
- [ ] Distribute URL to the specified channels

### CPP URL tracking (fill in after ASC approval)

| CPP | ASC ID | URL | Approved date |
|---|---|---|---|
| 1. TikTok | _____ | _____ | _____ |
| 2. Editorial | _____ | _____ | _____ |
| 3. Community | _____ | _____ | _____ |
| 4. Indie Santa | _____ | _____ | _____ |
| 5. ADHD | _____ | _____ | _____ |

---

## Measurement

Day 14 post-launch (2026-05-15) and Day 21 (2026-05-22), pull ASC Analytics → Acquisition → filter Source Type = "Product Page - Custom". Compare per-CPP:

- Impressions (how many times each CPP was viewed)
- Downloads
- Impression → Install CVR
- Retention D1 / D7 (if enough volume)

**Decision rule:** Any CPP with CVR below the default page's CVR for ≥ 2 weeks → either fix the creative or retire the CPP and consolidate traffic to a better-performing variant.

---

## Cross-references

- `1.0.4_METADATA_DRAFT.md` — main page metadata (Name / Subtitle / KW field) that CPPs inherit
- `MAY_1_MEASUREMENT_CHECKLIST.md` — overall release timeline
- `POST_APPROVAL_MOMENTUM_STRATEGY.md` — why channel-matched creative matters for the first-weeks algorithm window
- `screenshots/1.0.4/en-US/final/` — the 10-slot screenshot pool
