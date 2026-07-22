# Tic-Lock: Distribution Strategy
## Assessment → Channels → 90-Day Plan

**Date**: July 2, 2026
**Budget**: $250–400/month (ad spend only; tools ≤$30/month on top)
**Founder time**: ~20 hours/week for organic marketing
**Status**: Agreed strategy. ASO metadata changes pending Astro keyword workshop (desktop session).

---

## 1. WHERE WE ARE (Honest Baseline)

- **App**: "Parental Control App: Tic-Lock" (App Store ID 6753270211), live in US, CA, UK, AU, MX
- **Traction**: ~12 downloads total; 2 trial starts, both canceled; no active usage in Firebase
- **Web footprint**: zero — the listing is not indexed by Google, no reviews, no mentions
- **Ratings**: below the 11-rating threshold, so no stars display on the listing
- **ASO progress**: title restructure moved "parental control app" rank from 96 → 30 (keep this momentum)
- **Pricing**: Individual $7.99/mo, Family $12.99/mo, freemium + trial

### The core diagnosis

This is not yet a "pour money into channels" situation. The funnel after install is
unvalidated (both trials canceled, zero retained usage). At this stage, ad spend has one
job: **buy learning data** — a steady trickle of real parents through listing → onboarding
→ paywall → trial → usage, so we can find and fix the leaks. Scale comes after the funnel
holds.

### Unit economics guardrails

- Apple Small Business Program (15% cut) assumed — verify enrollment
- Subscriber retained ~4 months ≈ **$27–44 LTV**
- Industry data: cost-per-subscriber runs 4–5× cost-per-install
- **Max affordable cost per paying subscriber: ~$15–25**
- At ~$2–3 CPI this requires install→paid near 10% — which is why onboarding conversion
  (see `Marketing-Strategy/`) is the multiplier on every ad dollar

---

## 2. PAID CHANNEL VERDICT

| Channel | Verdict | Rationale |
|---|---|---|
| **Apple Ads (search results)** | ✅ Primary — ~90% of budget | Highest-intent traffic available: parents typing category terms in the App Store. Exact-match keywords = full cost control at $8–13/day. US CPT for this category ~$1.50–3.50; CA/UK/AU 30–50% cheaper. Doubles as keyword research for ASO. |
| **Meta (FB/IG)** | ⏸️ Not yet — revisit Month 3+ | Audience fit is real (emotional "daily battle" hook, video-friendly). But $13/day is below Meta's learning-phase needs; you pay tourist prices. Becomes the scale channel only after funnel converts AND budget can flex. |
| **Google App Campaigns** | ❌ Skip | Weak for iOS-only apps (SKAdNetwork limits), no placement control at small budgets. |
| **TikTok (paid)** | ❌ Skip | Wrong economics at this budget. Organic short-form is in scope (see playbook). |

**Geographic sequencing**: validate on cheap English traffic first — Canada, UK, Australia —
then move budget to the US once conversion holds. MX is a localization play (es-MX metadata),
not an ad-spend market.

---

## 3. FREE TRAFFIC (ASO + ORGANIC)

### A. App Store listing

1. **Title stays as-is for now.** "Parental control app" rank momentum (96→30) is worth
   protecting. Any title/subtitle change happens only in the Astro data workshop.
2. **Keyword field: duplicates VERIFIED functional — keep them.** The duplicated
   title/subtitle words exist to enable Custom Product Page keyword assignment (CPP
   keywords are selectable only from the keyword field), and live App Analytics data
   (19/23 daily impressions CPP-attributed, no ads running) confirms the routing works.
   Load-bearing words: `parental`, `control`, `app`, `kids`, `lock`, `mode`. Mechanic
   keywords (`earn`, `reward`, `limit`, `timer`, `study`, `reading`, `routine`) enter via
   the ~6 chars from unused `games`, any weak native terms Astro disqualifies (`kit`?),
   and above all the localized keyword fields. See `ASO_WORKSHEET.md`.
3. **Localization multiplier**: the US storefront also indexes es-MX metadata — a second
   free keyword field for the US. en-GB/en-AU/en-CA variants are near copy-paste.
4. **Screenshots sell the mechanic in the first 3 frames**: ① the daily battle ends
   ② learning unlocks rewards automatically ③ parent does nothing — it just works.
5. **Ratings engine**: SKStoreReviewController prompt after the first automatic reward
   unlock ("magic moment"). Crossing 11 ratings so stars display is a near-term KPI.
6. **Free Apple surfaces**: In-App Events (appear in search), Custom Product Pages
   (one per ad keyword theme), Product Page Optimization for screenshot A/B tests.

### B. Organic engine (20 h/week — detail in `WEEKLY_EXECUTION_PLAYBOOK.md`)

- **Community** (Reddit, Facebook parent groups, Quora): genuinely answer
  "how do I get my kid off the iPad without a fight" threads; disclosed founder replies
  convert well in this category and compound via search.
- **Content/SEO**: articles on i6dev.ca/screentimerewards targeting long-tail parent
  queries ("how to make screen time a reward", "screen time contract for kids").
- **Short-form video** (TikTok/Reels/Shorts): 2–3 per week; the mechanic demos well
  (kid finishes reading app → game unlocks on its own).
- **PR/outreach**: pitch SafeWise, Tom's Guide, allaboutcookies.org roundups with the
  privacy angle — *"the parental app that can't see your kid's data"* — plus parenting
  newsletters and podcasts.

---

## 4. THE 90-DAY PLAN

### Month 1 — Foundation & instrumentation (ad spend ~$100–150)
- Astro keyword workshop → final keyword field + subtitle decision (desktop session)
- Keyword-field dedupe + es-MX / en-GB / en-AU / en-CA metadata localizations
- Funnel analytics events: install → onboarding steps → paywall view → trial → paid → D1/D7 usage
- Review prompt shipped; Small Business Program verified
- Apple Ads Advanced: discovery campaign, $5/day, CA+AU, to harvest real parent search terms
- Website live with 2 articles; organic cadence starts
- **Exit gate**: clean analytics + ≥50 installs of real funnel data

### Month 2 — High-intent validation (ad spend $250–350)
- Kill discovery; exact-match campaigns on proven terms (expect 5–15 keywords), CA/UK/AU
  first, US on the 2–3 best converters
- Custom Product Page per keyword theme; weekly 30-min bid/keyword pruning
- **Exit gate**: install→trial ≥ 8% AND trials show real usage (if trials start but usage
  stays flat, pause spend — the problem is onboarding/setup friction, fix that first)
- **Kill criteria**: any keyword with 40+ taps and 0 trials dies; if cost-per-trial > ~$20
  after $300 spent, stop and fix conversion before spending more

### Month 3 — Double down or fix
- **Gates passed**: full $400 into proven exact-match, expand US, push PR outreach,
  optionally test Meta at $10/day with one video creative (battle → unlock)
- **Gates failed**: drop to ~$100 maintenance spend; effort goes to the conversion fix
  (likely the interactive-demo onboarding in `Marketing-Strategy/`)

### Budget shape (steady state)
| Item | Monthly |
|---|---|
| Apple Ads | $250–370 |
| Tools (Astro already owned; optional Appfigures ~$9) | $0–30 |
| **Total** | **≤ $400** |

---

## 5. KPIs

| Metric | Now | 90-day target |
|---|---|---|
| Impressions → product page view | unknown | measure, then +20% |
| Product page → install (CVR) | unknown | ≥ 25–30% |
| Install → trial | ~0% | ≥ 8% |
| Trial → paid | 0% | ≥ 30% |
| Trials with real D7 usage | 0 | majority |
| Ratings count | <11 | ≥ 11 (stars visible) |
| "parental control app" rank | 30 | hold or improve |
| Organic installs/month | ~0 | 50+ |

---

## 6. OPEN ITEMS (desktop session)

1. Astro MCP keyword workshop: validate dedupe replacements, subtitle wording
   ("Kids Lock App, Learning, Games" — `lock`/`app` duplicate title words), and
   long-tail targets around the earn/reward mechanic
2. Confirm Small Business Program enrollment
3. Confirm current trial length (docs conflict: 30 days vs shorter) — trial length is a
   major conversion lever worth an experiment later
