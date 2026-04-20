# Beginner-App ASO Research — 2026 Frontier Playbook

**Compiled:** 2026-04-19
**Scope:** External research synthesis for a new iOS subscription app at 0 reviews / 0 downloads in the parental-controls / screen-time / kids-learning niche.
**Source:** 5 parallel research agents — ASO-specialist framework + 4 web/YouTube research streams (200+ URLs reviewed, ~50 cited).
**Companion docs in this directory:** `ASO_EXECUTION_PLAN.md` (positioning + metadata), `BASELINE_METRICS.md` (rank baseline), `ASTRO_COMPETITOR_INTELLIGENCE.md` (competitor data), `APPFIGURES_ASO_INSIGHTS.md` (algorithm mechanics from Lyttle/Ariel transcripts), `POST_APPROVAL_MOMENTUM_STRATEGY.md` (week-by-week post-launch).

This doc covers what those don't: **the meta-question of which lever to pull first, what's changed in 2025–2026, and what indies actually do that works** — versus what conventional ASO content gets wrong.

---

## TL;DR — The Five Things That Actually Matter at 0 Reviews

1. **Rating velocity, not metadata, is the bottleneck.** Apple's algorithm reads *cadence over 30 days* — even if every review is 5★, sparse cadence won't elevate you. Per Ariel (Astro): "the actual value of the rating is completely irrelevant... over the course of about 30 days, the algorithm will learn." Target trajectory: 0 → 10 (Day 14) → 25 (Day 30) → 75 (Day 60) → 200 (Day 90).
2. **Screenshot caption text is now indexed for keyword ranking** (Apple, June 2025 algorithm shift). This is the single most under-exploited surface for new apps. Use the `aso-appstore-screenshots` skill — caption 1 must contain `earn screen time`.
3. **Custom Product Pages (CPPs) now appear in organic search**, not just paid traffic (Apple, October 2025). Limit doubled from 35 → 70 per app. Treat CPPs as 70 alternate landing pages indexed by keyword cluster — even at 0 reviews, ship 5–10 of them.
4. **Founder-led short-form video (TikTok) is the only repeatable indie distribution channel for this niche.** BePresent went from $0 → $20K MRR / 30K monthly downloads on this single channel. The format is selfie + text overlay + trending audio, NOT talking-head.
5. **The "new app boost" still exists but only ~48 hours.** Apple measures install velocity, retention, and complaint signals during this window. The classic 30-day honeymoon was nerfed in 2025. Binary updates re-trigger algorithmic re-evaluation; metadata-only updates do not.

---

## 1. The Cold-Start Flywheel — Where the Bottleneck Actually Is

The standard model: **keywords → rank → impressions → downloads → velocity signal → rank again** ([MobileAction](https://www.mobileaction.co/blog/app-store-ranking-factors/), [Appypie 2026](https://www.appypie.com/blog/app-store-optimization-guide)). For a new app, the bottleneck is asymmetric:

| Lever | Time to move | Controllability at 0 reviews |
|---|---|---|
| Conversion rate (product page) | Days | High (screenshots, captions, subtitle) |
| Ranking | 7–30+ days | Low — gated by review velocity |
| Downloads | Output of above two | Indirect |

The trap: founders A/B-test screenshots for "conversion" before they have impressions to convert. **You don't have a conversion problem yet — you have an impressions problem masquerading as one.** Industry median CVR is ~25% in the US App Store ([Adapty 2026](https://adapty.io/blog/app-store-conversion-rate/)) — benchmark before you optimize.

**Where Brain Coinz sits today:** 45/46 keywords unranked (`BASELINE_METRICS.md`). Impressions ceiling ≈ 0. Until rating cadence elevates rank, the conversion rate of the page is academic.

---

## 2. 2025–2026 Algorithm Changes That Matter for New Apps

### 2a. Screenshot OCR Indexing (June 2025) ⭐
- **What changed:** Apple's algorithm now indexes screenshot **caption** text for keyword ranking. Description text remains unindexed. ([AppFigures](https://appfigures.com/resources/guides/app-store-algorithm-update-2025))
- **Practical impact:** AppTweak measured *"up to a 22% boost in search visibility within 30 days"* for apps that added keyword captions to screenshots. The first 3 screenshots specifically — those appear in search results.
- **Implementation rules:**
  - Replace marketing copy ("Wake Up Refreshed") with keyword-rich captions ("Track Sleep Patterns")
  - High-contrast, large, non-stylized fonts for OCR readability
  - One keyword theme per screenshot — no repetition
  - Reverse-engineer competitor captions via AppFigures Keyword Inspector
- **Why it matters MORE for new apps:** Old advice was "screenshots = pure conversion." Many tutorials still teach this. As of June 2025, screenshots = discoverability AND conversion. New apps that haven't been told yet are leaving free signal on the table.

### 2b. Custom Product Pages Now Index Organically (October 2025) ⭐
- **What changed:** CPP limit doubled 35 → 70 per app. CPPs assigned keywords now appear in **organic** search results, not just paid traffic. iOS 18+ adds per-CPP deep links for the Open button. ([Apple Developer](https://developer.apple.com/app-store/custom-product-pages/), [Phiture](https://phiture.com/asostack/keyword-based-custom-product-pages-cpps-arrive-in-app-store-connect/))
- **Conversion-rate data:** CPPs hit 55.8% CVR in 2024, up from 42.1% in 2023. AppTweak documents 5.9–8% lift. ([AppTweak](https://www.apptweak.com/en/aso-blog/guide-to-custom-product-pages-cpp))
- **Implication for new apps:** Even at 0 reviews, ship 5–10 CPPs at launch targeting different keyword clusters (e.g., one for `earn screen time` intent, one for `reward kids`, one for `parental control` even if you can't rank in main listing). This is a free 2026 lever most indies haven't picked up.
- **Contradicts old wisdom:** "CPPs are only useful with paid traffic" — no longer true.

### 2c. The "New App Boost" Was Nerfed
- **Current consensus (2026):** ~48 hours of elevated visibility post-approval, during which Apple measures install velocity, retention, and complaint signals. ([Appskale 2026](https://www.appskale.ai/blog/how-to-launch-an-ios-app-in-2026), [RadASO](https://radaso.com/blog/how-to-boost-an-app-at-the-first-app-store-release-life-hacks-from-radaso))
- **Brain Coinz evidence:** The Apr 17 approval did NOT push us into autocomplete (`ASTRO_COMPETITOR_INTELLIGENCE.md` autocomplete check). The boost either didn't fire or is invisible at our traffic level. The Apr 17–18 rank 5 spike on `brain coinz` was the boost; Apr 19 rank 12 is decay.
- **What re-triggers visibility:**
  - **Binary updates with real feature improvement** (NOT metadata-only) — re-evaluates relevance signals
  - **In-App Events** — own discovery surface + event cards in search
  - **Featured-by-editorial nomination** — long shot but free
  - **Sustained 30-day rating cadence** — the real "extended boost" mechanism
- **Frontier tactic:** Ship 1.0.4 binary update around Day 21–30 with one real feature, not a metadata-only push.

### 2d. Reviews & Ratings Weight in 2026
- Apps below 3.5★ see "measurably reduced search visibility" ([Respectlytics 2026](https://respectlytics.com/blog/app-store-ranking-factors-2026/))
- Indie App Santa data: each half-star ≈ **20% higher download rate**
- **Realistic ranking ceilings by review count** (Brain Coinz benchmarks):
  - 0–50 reviews: Pop 5–15 / Diff <50 → realistic top 20 in 14–30 days
  - 50–200 reviews: Pop 30–40 / Diff 55–65 → realistic top 100–300
  - 200+ reviews: Long-tail variants of head terms (e.g., `screen time for kids` not `screen time`)
  - 500–1000+ reviews / 6+ months: Pop 50+ contention
- **Decision rule for our metadata:** at 0 reviews, treat any keyword Diff > 60 as aspirational; any keyword Pop > 40 as out of reach. Our 100-char EN_US budget is correctly allocated to Pop 5–23 fits. **Don't trade low-Diff slots for higher-Pop hopes.**

### 2e. App Store Tags (WWDC 2025)
- Apple now generates AI-derived browse-surface tags from your metadata for placement in category and Today-tab surfaces.
- Tactical implication: still being figured out by the community. Almost no public content yet on how to influence Apple's tag generation. Watch this space.

### 2f. Apple Search Ads Changes
- iOS 18 added Today-tab ads + Search-tab ads (separate from search results).
- The "halo effect" (paid ASA traffic boosting organic rank) remains debated. Sonar's playbook is the most concrete indie guidance ([Sonar](https://trysonar.app/blog/apple-search-ads-guide), updated March 2026).

---

## 3. The 30 / 60 / 90 Day Calendar

### Days 1–30 (now → 2026-05-17): Velocity & Coverage

| Day | Action | Reason |
|---|---|---|
| 1–7 | Ship the **ES_MX keyword field** (drafted but undeployed per `ASO_EXECUTION_PLAN.md` audit). Add `brainrot, parenting, control, points` to the existing draft. | Free 100-char locale slot. Highest single-action ROI. Doesn't disturb EN_US measurement. |
| 1–14 | Drive 10–25 ratings from any source: personal network, TestFlight-converted users, parenting Reddit/Discord. | Star value irrelevant per Ariel; cadence matters. |
| 7 | Verify rating-prompt wiring on TestFlight before relying on it organically. Confirm `firstParentSuccess` and `firstWeeklyWin` fire. | Code change just landed (commit `12b2069`); test before depending on it. |
| 7–14 | **Audit + redeploy screenshots with OCR-optimized captions.** Caption 1 = `earn screen time`; caption 2 = `reward kids`; caption 3 = `learning apps`. | June 2025 algorithm change; first 3 screenshots indexed. |
| 14 (May 1) | Re-pull Astro keyword diffs vs `BASELINE_METRICS.md`. Check the 4 indexing canaries (`time limit`, `app limit`, `screen limit`, `screen time limit`). | If canaries still 1000 with full token coverage, indexing is broken. |
| 21 (May 8) | Second re-measure. Begin building 5–10 CPPs in App Store Connect. | Locks in measurement window before binary update. |
| 28 | **Ship 1.0.4 binary update** with one real feature improvement. | Re-triggers Apple's freshness re-evaluation. Metadata-only won't. |

### Days 30–60 (May 17 → June 16): Conversion & Locale Expansion

- Enable **EN_AU + EN_CA locales** with the keyword payload from `POST_APPROVAL_MOMENTUM_STRATEGY.md` Day 21+ section. Each = free 100 chars.
- **Ship 2 CPPs minimum:** one for `earn screen time` intent, one for `reward kids` / positive-reinforcement intent. Assign keywords. They'll appear in organic search.
- Begin **scoped Apple Search Ads test** — $5/day brand defense + $50/day × 5 days on `earn screen time`. Get real CPA data. (See §5b.)
- **Begin TikTok content cadence** (see §4a). Founder-led, selfie format, batch-shoot.

### Days 60–90 (June 16 → July 16): Compound or Pivot

- **Decision gate at Day 60:** if `brain coinz` is #1 organically + ≥3 positioning keywords are top-100 + you have 25+ ratings → scale ASA, expand CPPs to 4–5. If not → execute name-flip experiment ("Earn Screen Time: Brain Coinz") per Ariel's keyword-first/brand-last advice.
- **Launch one In-App Event** tied to a back-to-school or summer-prep narrative. Events get a separate discovery surface + trigger fresh evaluation.
- **Stage competitor-conquest metadata** in FR_FR or DE locale (`qustodio,bark,aura,life360,kidslox`). Keep OUT of EN_US — Apple has tightened 2.3.7/2.3.10 enforcement.
- **First subscription-model review:** by Day 90 you have enough cohort data. If trial-to-paid <5%, the conversion problem moves upstream (paywall/onboarding) — not an ASO problem.

---

## 4. Channels — What Works for Indie Cold-Start

### 4a. Founder-Led Short-Form Video (TikTok) — The Single Channel That Works

**BePresent is the case study.** Two brothers, NYC, bootstrapped, 2022 launch → $20K MRR, 30K monthly downloads, 58M+ video views, profitable. Closest replicable indie playbook to Brain Coinz. ([Plutus](https://growwithplutus.com/blog/bepresent-app-tiktok-strategy), [Starter Story](https://www.starterstory.com/be-present-breakdown))

**Their stack:**
- 7 TikTok accounts + 2 Instagram Reels accounts
- @screentimejesus (Jack's personal): 4.4M views — the founder personal account dwarfed the brand account
- @bepresentbros (joint brand): 53.3M cumulative
- @chazwins (Charles): 147K
- @el.bepresent (UGC creator)

**Two formats that won:**
1. **Selfie + text overlay + trending audio (no talking).** Hooks like *"Signs you need a dopamine detox"* or *"How I reduced my screen time from 7h+ to 1h"* — multiple videos broke 7M views.
2. **Cover slideshow** — selfie hook on slide 1, app screenshots on subsequent slides. *"5 selfies can produce a week's worth of content."* Reused covers across multiple videos.

**What did NOT work:** Talking-head and reaction videos — abandoned.

**Hooks Brain Coinz could test (parent-pain framing):**
- "My 9-year-old got 4 hrs of screen time today and I didn't realize until bedtime"
- "I tried bribing my kids to do their homework. This worked instead."
- "POV: your kid earns Roblox time by doing Khan Academy"
- "Things that made me a better parent in 2026"

**Dev investment:** Founder time, batch shooting, free tools. No agency required. Highest-EV bet for first 90 days.

### 4b. Apple Search Ads on a Tiny Budget

**Sonar's published playbook ([trysonar.app](https://trysonar.app/blog/apple-search-ads-guide)):**
- **$10/day split:** $2 brand / $6 exact match / $2 discovery
- **$30/day split:** $5 / $20 / $5
- **Max CPT:** Brand $1.00–$2.00; exact match (SP under 40) start $0.50; discovery $0.30–$0.50
- **Keyword filter:** Search popularity 20–55 (avoids enterprise auctions)
- **Pipeline:** Discovery → review weekly Search Terms report → promote 40%+ conversion keywords into exact match → add as negatives in discovery
- **Stage budget:** Pre-launch $5–10/day for 30 days; growing $15–30/day; established $30–50/day
- **Brand defense is mandatory** even for unknown apps — competitors will bid on your brand name the moment you have any traffic

**For Brain Coinz specifically:** $5/day brand defense (capped) + $50/day × 5 days exact match on `earn screen time` to get real CPA data is the recommended first test. Wait until Day 30+ to give organic a fair shot first.

### 4c. Reddit + Communities

- **r/SideProject** is the safe first launch (developer audience, expects promo)
- **r/iosgaming, r/IndieApps** — moderate yield
- **r/Parenting, r/Mommit, r/daddit** — need mod permission, non-promotional frame ("I built this for my own kid, sharing in case useful"). High value if it lands; banned if it reads as ad
- **90-9-1 rule** (Indie App Santa, Nov 2025): 90% pure value posts / 9% soft mention / 1% direct promotion
- **Reality check:** Reddit drives initial validation, not scale. Don't expect it to replace TikTok.

### 4d. Indie App Santa ($140 — the best money an indie can spend)

- one sec used this exact mechanic to chart in top-100 alongside Duolingo and LinkedIn during a 24-hr free Pro window (Dec 2023). ([Indie App Santa tweet](https://x.com/indieappsanta/status/1730506452756779328))
- AnyTracker case study: €140 fee → 1,195 iOS + 703 Android downloads in 3 days, $4,098 revenue, **2,632% ROI** ([Shervin Koushan, Medium](https://shervinkoushan.medium.com/5-lessons-from-a-successful-indie-app-santa-promotion-a535f5ad4053))
- **Brain Coinz action:** Submit for Dec 2026 promotion. Free Pro window or extended trial as the offer.

### 4e. Apple Editorial Feature

- The single largest lever a small team can land. one sec, Forest, Jomo all credit Apple features for their inflection points.
- Pitch `app@apple.com` after a meaningful update. Lead with research-backed or social-good angles. Brain Coinz could lead with "first parental-controls app built on positive reinforcement, not restriction" + any user-outcome data once available.

### 4f. Product Hunt

- Mediocre for parenting niches (audience = builders). Drives installs, **not reviews**. Worth doing for press and backlinks; don't expect it to seed your review base.

### 4g. Influencers

- **Founder reach > paid influencer.** one sec was picked up by Ali Abdaal (organically) — that single Nov 2022 YouTube Short ([link](https://www.youtube.com/watch?v=XWgaOtLFQCM)) was a turning point.
- Endel went brand-collab route (Grimes, Alan Watts) — requires founder reach Brain Coinz won't have at zero.
- Micro-influencer sweet spot: 5K–50K followers, 3–5%+ engagement, offer premium access not cash.

---

## 5. The Review Velocity Playbook (the #1 lever)

### 5a. Apple-Enforced Mechanics

- **Hard cap:** 3 prompts / 365 days per user per app. Don't waste them.
- **Native prompt CVR:** ~13.5% to a star rating, ~0.07% to a written review ([RevenueCat](https://www.revenuecat.com/blog/engineering/how-to-hack-your-app-store-ratings/))
- **Pre-2017 custom prompts:** 0.8% CVR — native is ~17× better
- **Apptentive data:** apps adopting native saw 32× daily rating count, 90% saw 20%+ star-average lift ([Marketing Dive](https://www.marketingdive.com/news/study-apple-update-increases-app-ratings-by-15/445029/))
- **Average rating skews ~4.7** because tap-and-go users go 5★; complainers write 3-6× longer 1★ reviews

### 5b. The Trigger Recipe (RevenueCat-published)

Point-based "happiness engine," 14-day cooldown:
- App open = 1 pt
- Feature use = 5 pt
- Subscription = 10 pt
- **Threshold: 16 pt → fire prompt**

For Brain Coinz, translate this to:
- First successful reward redemption (the magic moment when learning unlocks a reward) = high-point trigger
- Day-3 of pairing = engagement trigger
- Day-3 post-FIRST-CHARGE (not trial start) = conversion trigger

### 5c. Subscription-App Specific Timing

- **Don't prompt at trial start** — no value delivered yet, 80% of trials start same-day as install
- **Best moment:** 2-4 days after FIRST CHARGE (actual paid conversion, not trial signup notification)
- **Never during cancel flow** — review-bombing risk
- **30-day renewal is an underused gold-mine moment** — user has paid twice, demonstrated retention

### 5d. Guideline Edges (Load-Bearing — Don't Get Banned)

- **Pre-prompt feedback gates that BIAS toward happy users → 5.6.1 violation** (review manipulation). Apple removed 143M ratings + 146K dev accounts in 2024 ([Apple Newsroom May 2025](https://www.apple.com/newsroom/2025/05/the-app-store-prevented-more-than-9-billion-usd-in-fraudulent-transactions/))
- **Neutral pre-prompts** with equal prominence on both paths are OK
- **Never incentivize.** No "get a free week of Pro for rating us." Period.
- **Custom UIs that mimic the native dialog were banned in June 2017** ([9to5Mac](https://9to5mac.com/2017/06/09/app-rating-custom-prompts-app-store-banned/))
- **Friend & family seeding is allowed** if usage is genuine and staggered. **Coordinated clusters trigger Apple's fraud detection.** Stagger over 2-3 weeks, not all on launch day.
- **TestFlight users CANNOT review.** They must reinstall the public build first.

### 5e. Bad-Review Recovery

- **Respond within 24-48h** — ~70% of users who get a response revise it (often upward)
- You CANNOT ask users to change/delete reviews directly — only via the public response
- Apple weighs developer responsiveness for editorial features ([AppFollow](https://appfollow.io/blog/why-app-stores-nudge-app-companies-to-respond-to-reviews))

### 5f. Priority Stack — Realistic 30-day target: 60–135 reviews

1. Wire `SKStoreReviewController` to fire on first reward redemption + Day-3 of pairing + Day-3 post-first-charge → **30–60 reviews**
2. Email TestFlight + waitlist staggered over 10 days → **15–30 reviews**
3. Respond to every review in 24h → compounding
4. Genuine Reddit engagement + r/SideProject launch → **5–15 reviews**
5. OneSignal Day-7 deep-link email → **10–20 reviews**
6. Product Hunt → **3–10 reviews**
7. Neutral pre-prompt → **+20–30% lift** on items 1 & 5

---

## 6. Indie Case Studies — Patterns Across Winners and Losers

### Winners

| App | Founder | Channel that scaled | Key insight |
|---|---|---|---|
| **one sec** | Frederik Riedel (solo → 14-person, no VC) | Single demo tweet → influencer pickup (Ali Abdaal) → press cycle (NYT, Verge, WSJ) | Commissioned a peer-reviewed PNAS study; weaponized "57% reduction" stat in screenshots and press |
| **BePresent** | Jack & Charles Winston (bootstrapped) | Founder-led TikTok at scale (7 accounts) | Selfie + text overlay + trending audio; killed talking-head |
| **Opal** | Kenneth Schlenker (VC-backed, $4.3M seed) | $400k/mo paid acquisition, 8-day ROAS as only KPI | Pivoted from Gen Z mental health to professional productivity — repositioning was the unlock |
| **Forest** | Seekrtech (Taiwan) | Apple "Best New Apps" feature + cause-tied (real trees planted) | iOS paid upfront ($1.99) — counter-conventional |
| **Jomo** | Laureline Couturier & Thomas Maherault | Apple editorial features (Top 15 Apps Created by Women 2023/24/25) | Slow compound, no viral moment, sustainable indie biz without TikTok |
| **ScreenZen** | Donation-supported indie | Anti-monetization stance IS the marketing | 500K MAU, NOT replicable for paid sub indies |

### Losers / Cautionary

- **Unrot** (June 2025 launch, Estonia): 1★ tsunami over hard paywall after long onboarding with no free trial. **Lesson for Brain Coinz: a 14-day trial is itself a competitive moat in this micro-niche.** Show the trial in screenshots and subtitle.
- **Opal's mental-health Gen Z positioning failed** before they pivoted. *"Improve your mental health"* is too soft; *"Get 75 min of your life back"* converts.
- **Generic Pomodoro apps** (Brain Focus etc.): saturated, low-ARPU, not sub-friendly.

### Closest Direct Competitor to Watch

**Achieve! — "Earn Your Screen Time"** ([App Store](https://apps.apple.com/us/app/achieve-earn-your-screen-time/id6466824356)) — solo indie, iOS 17.4+ only (uses ManagedSettings like us), small but ~5★. Quietly monitor weekly: review velocity, pricing changes, TikTok activity.

### Cross-Cutting Patterns

1. **Demo videos > talking-head.** The product shows itself.
2. **Charge from day 1, but make the trial frictionless.** Opal's "subscription as a discovery engine."
3. **Cause/credibility hook beats feature lists.** PNAS study, real trees, women-in-tech editorial.
4. **Subtitle is keyword real estate; name can be brand-led.** "one sec | screen time + focus" — non-keyword brand, keyword-loaded subtitle.
5. **iOS-only at first, US-only at first.** "When you have two [platforms], you're kind of stuck."
6. **Apple editorial feature is the largest single lever a small team can land.**
7. **Indie App Santa is the best $140 an indie can spend** in this niche.

---

## 7. Stop-Doing List — What Conventional ASO Wisdom Gets Wrong

**Don't waste time on:**
- **Description optimization beyond the first 3 lines.** Apple does not index the description for ranking ([Moburst](https://www.moburst.com/blog/app-store-ranking-factors/)). The first 3 lines (above the "more" fold) drive conversion; the rest is filler.
- **What's New text.** Almost no conversion impact at our traffic level. Write once per release.
- **A/B testing icons before ~1,000 weekly impressions.** No statistical significance. Wait until Day 60+.
- **Tracking 80+ keywords weekly.** Track 8–10 primary + 4 canaries. The other 70 are noise at 1000-rank baseline.
- **Bidding heavily on `brain coinz`.** Maximum $5/day until organic rank improves; defensive only.
- **Optimizing IAP display names for ranking.** Per `feedback_verify_aso_claims.md`, IAP names are not a confirmed indexed surface. Optimize for purchase-sheet clarity, not search.
- **Pre-prompt feedback gates that bias toward happy users.** Guideline 5.6.1 violation.
- **Prompting after every paywall conversion.** Wastes the 3/365 prompt budget on pre-value users.
- **Launching on Product Hunt expecting reviews.** PH drives installs, not reviews.
- **Asking TestFlight users to rate.** They literally can't — must reinstall public build first.
- **Coordinated friend launch-day reviews.** #1 fraud signal. Stagger over 2-3 weeks.

**Compounds heavily — do now:**
- **Rating cadence over 30 days.** Single highest-leverage lever.
- **Screenshot OCR captions.** Most under-exploited 2026 surface for new apps.
- **Token coverage across name + subtitle + EN_US KW + ES_MX KW + EN_AU/CA KW + screenshot OCR.** Each additional locale = free 100 chars.
- **CPPs as organic search landing pages.** 5–10 of them, even at 0 reviews.
- **Founder-led TikTok in BePresent format.** Selfie + text overlay + trending audio.
- **Positioning discipline.** Refusing tempting-but-mismatched keywords (`parental control`, `dopamine detox`) compounds into 4.5★ vs 3-star avg by Day 180.
- **Reply to every review within 24h.**

---

## 8. What's Notably MISSING from Public Content (Open Questions)

Worth investigating further or being first-mover on:

1. **Day-by-day playbook for first 30 days at 0 reviews.** Adam Wulf's [App Launch Guide](https://github.com/adamwulf/app-launch-guide) is closest but not time-sequenced.
2. **Honest case studies of apps that launched and got <100 downloads in month 1.** Survivorship bias is brutal — every published case study is a winner.
3. **Concrete subscription paywall numbers for niche/indie apps.** Sub Club episodes lean Mojo/Headspace-scale. There's no content on what CVR a brand-new parental-controls subscription app should expect.
4. **Review-velocity tactics for FamilyControls/parental-control apps.** Unique constraint: the parent is the buyer, the child is the user. The child can't show the rated app prompt. No public content addresses this — Brain Coinz's `firstParentSuccess` trigger is novel territory.
5. **2025 screenshot-caption indexing has not yet propagated into most YouTube tutorials.** Filter accordingly — anything pre-June 2025 on screenshots is partially stale.
6. **Custom Product Pages as organic levers.** Oct 2025 keyword-linking change is barely 6 months old. First-mover opportunity.
7. **App Store Tags (WWDC 2025 AI-generated browse labels).** Almost no tactical content yet on how to influence Apple's tag generation.
8. **Apple Search Ads on truly tiny budgets ($5/day) for a 0-review app.** Most ASA content assumes you already convert. The bid-to-install math when CVR is unknown is rarely covered.

---

## 9. Brain Coinz–Specific Recommendations (Synthesis)

In execution priority:

1. **Deploy ES_MX keyword field.** Drafted in `ASO_EXECUTION_PLAN.md` §4 but never shipped. Add `brainrot, parenting, control, points` from this session's Astro work. Free 100-char slot.
2. **Audit + redeploy screenshots with OCR-optimized captions.** Caption 1: `earn screen time`. Caption 2: `reward kids`. Caption 3: `learning apps`. Use the `aso-appstore-screenshots` skill.
3. **Verify rating prompt** wired in commit `12b2069` actually fires correctly on TestFlight.
4. **Launch founder-led TikTok cadence** in BePresent format. Selfie + text overlay + trending audio. Batch-shoot 5 selfies for a week of content. Hooks built around parent pain.
5. **Hold EN_US metadata** through May 1 (Day 14 measurement). Don't iterate during the measurement window — muddies signal.
6. **Build 5 CPPs** in App Store Connect targeting different keyword intents. Start drafting now, ship by Day 30.
7. **Day 28: ship 1.0.4 binary** with one real feature improvement to re-trigger Apple's freshness re-evaluation.
8. **Submit to Indie App Santa** for Dec 2026.
9. **Pitch Apple editorial** (`app@apple.com`) after a meaningful update. Lead with positive-reinforcement-first angle.
10. **Track Achieve!** weekly as closest direct comp.

**What we're explicitly NOT doing** (and the reason):
- Adding `parental control` to keywords (Pop 41, Diff 65 — top-50 incumbents have 8K–272K reviews; can't beat the moat at 0 reviews)
- Description rewrites (not indexed, not the bottleneck)
- Changing EN_US metadata before Day 14 measurement
- Heavy ASA spend (defer until organic gets a fair test)
- Product Hunt launch as a review-getting tactic (it isn't one)

---

## Source Index

### Apple Official
- [App Store Optimization (Apple Developer)](https://developer.apple.com/app-store/search/)
- [Custom Product Pages (Apple Developer)](https://developer.apple.com/app-store/custom-product-pages/)
- [SKStoreReviewController docs](https://developer.apple.com/documentation/storekit/skstorereviewcontroller)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [HIG: Ratings & Reviews](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews)
- [Apple Newsroom — $9B fraud prevention May 2025](https://www.apple.com/newsroom/2025/05/the-app-store-prevented-more-than-9-billion-usd-in-fraudulent-transactions/)

### Algorithm + Strategy
- [AppFigures — Algorithm Update 2025 Guide](https://appfigures.com/resources/guides/app-store-algorithm-update-2025)
- [AppFigures — Keyword Research 2025 video](https://www.youtube.com/watch?v=4_8f4vBlMzg)
- [Phiture — Keyword-Based CPPs](https://phiture.com/asostack/keyword-based-custom-product-pages-cpps-arrive-in-app-store-connect/)
- [AppTweak — CPP Guide](https://www.apptweak.com/en/aso-blog/guide-to-custom-product-pages-cpp)
- [MobileAction — CPPs Meet Organic Search](https://www.mobileaction.co/blog/custom-product-pages-meet-organic-search/)
- [MobileAction — Ranking Factors 2026](https://www.mobileaction.co/blog/app-store-ranking-factors/)
- [Respectlytics — Ranking Factors 2026](https://respectlytics.com/blog/app-store-ranking-factors-2026/)
- [Appskale — Launch Guide 2026](https://www.appskale.ai/blog/how-to-launch-an-ios-app-in-2026)
- [Adapty — Conversion Rate by Category 2026](https://adapty.io/blog/app-store-conversion-rate/)
- [Moburst — Ranking Factors](https://www.moburst.com/blog/app-store-ranking-factors/)

### Reviews / RevenueCat / Apptentive
- [RevenueCat — How to hack your App Store ratings](https://www.revenuecat.com/blog/engineering/how-to-hack-your-app-store-ratings/)
- [RevenueCat — State of Subscription Apps 2025](https://www.revenuecat.com/state-of-subscription-apps-2025/)
- [Phiture — iOS Rating Prompt data](https://phiture.com/asostack/unlocking-the-data-behind-the-ios-rating-prompt-8e942bfe9134/)
- [Critical Moments — SKStoreReviewController guide](https://criticalmoments.io/blog/skstorereviewcontroller_guide_with_examples)
- [9to5Mac — Custom prompts banned 2017](https://9to5mac.com/2017/06/09/app-rating-custom-prompts-app-store-banned/)
- [AppleInsider — 2024 fraud crackdown](https://appleinsider.com/articles/25/05/30/millions-of-apps-were-denied-by-apple-in-2024-amid-fraud-crackdown)
- [Marketing Dive — Apptentive 32× study](https://www.marketingdive.com/news/study-apple-update-increases-app-ratings-by-15/445029/)
- [AppFollow — Why respond to reviews](https://appfollow.io/blog/why-app-stores-nudge-app-companies-to-respond-to-reviews)

### Indie Case Studies
- [BePresent — Plutus TikTok strategy](https://growwithplutus.com/blog/bepresent-app-tiktok-strategy)
- [BePresent — Starter Story](https://www.starterstory.com/be-present-breakdown)
- [one sec — Origin story](https://one-sec.app/about/)
- [one sec — riedel.wtf 1M€](https://riedel.wtf/one-sec-one-year-ad-revenung-1000000/)
- [one sec — PNAS 2023 study](https://www.pnas.org/doi/10.1073/pnas.2213114120)
- [one sec — Slate Jun 2024](https://slate.com/life/2024/06/one-sec-app-smartphone-blocker-instagram-tiktok.html)
- [one sec — Indie App Santa promo (Dec 2023)](https://x.com/indieappsanta/status/1730506452756779328)
- [Ali Abdaal one sec YouTube Short](https://www.youtube.com/watch?v=XWgaOtLFQCM)
- [Opal — Speedinvest case study](https://www.speedinvest.com/knowledge/scaling-smart-how-opal-built-a-10m-arr-business-in-just-2-years)
- [Opal — RevenueCat / Sub Club Schlenker](https://www.revenuecat.com/blog/growth/kenneth-schlenker-opal-sub-club-podcast/)
- [Forest — AppSamurai case study](https://appsamurai.com/blog/mobile-app-success-story-forest-by-seekrtech/)
- [Jomo — This Too Shall Grow interview](https://thistooshallgrow.com/blog/better-screen-time-jomo)
- [Achieve! — App Store](https://apps.apple.com/us/app/achieve-earn-your-screen-time/id6466824356)
- [Endel — Sensor Tower overview](https://app.sensortower.com/overview/1346247457?country=US)

### Channels + Distribution
- [Sonar — Apple Search Ads Indie Guide (March 2026)](https://trysonar.app/blog/apple-search-ads-guide)
- [Apple Search Ads Tutorials playlist](https://www.youtube.com/playlist?list=PLGXZC1nQpK7d1FbdN2ykIJN07ELrJ_iC8)
- [Adam Wulf — App Launch Guide](https://github.com/adamwulf/app-launch-guide)
- [Indie App Santa — 12 Low Cost Strategies 2025](https://indieappsanta.com/2025/11/21/10349/)
- [Indie App Santa case study — Koushan Medium](https://shervinkoushan.medium.com/5-lessons-from-a-successful-indie-app-santa-promotion-a535f5ad4053)

### Sub Club / Paywalls
- [Sub Club — Mojo $1M MRR Paywall Experiments](https://subclub.com/episode/growing-to-1m-mrr-with-paywall-and-pricing-experiments-francescu-santoni-mojo)
- [Sub Club — WWDC 2025 for Subscription Apps](https://subclub.com/episode/wwdc-2025-what-subscription-apps-need-to-know)
- [Sub Club — Sylvain Gauchet on Paywalls](https://subclub.com/episode/how-to-build-more-successful-paywalls-sylvain-gauchet)
- [Superwall — 3 Indie Paywall Experiments](https://superwall.com/blog/3-proven-paywall-and-pricing-experiments-to-boost-indie-app-revenue/)

### Strategic / Authority Reads
- [Mobile Dev Memo — Post-Attribution Playbook (YouTube)](https://www.youtube.com/watch?v=0dZ-wwsNLWY)
- [App Masters — 7 New ASO Tactics 2025 (YouTube)](https://www.youtube.com/watch?v=79QGI8ow2lI)
- [Indie App Teardown w/ Steve P. Young](https://www.youtube.com/watch?v=OjU9N4mZpjs)
- [Astro — Find Profitable App Store Keywords 2025](https://www.youtube.com/watch?v=KJen21cgEIM)

---

**Note:** A 6th research thread on Apple algorithm specifics (iOS 18/19 details, In-App Events 2025-2026 mechanics, AI-related changes) was launched in background and may add detail to §2 once it returns. This document will be updated then.
