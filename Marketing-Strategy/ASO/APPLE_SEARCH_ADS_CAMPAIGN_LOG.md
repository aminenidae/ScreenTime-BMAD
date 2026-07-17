# Apple Search Ads — Campaign Log

**Live document. Newest entries at the top of the log. Update after every settings change or data review.**

---

## Current State (as of 2026-07-16)

| Setting | Value |
|---|---|
| Campaigns | Canada_2026.07.14_v1.0.8 (ID 2144267261) · US_2026.07.15_v1.0.8 (ID 2144282313) |
| US ad group | United States (ID 2149812181) |
| Currency / TZ | CAD / America/Winnipeg |
| Daily budget (US) | **$20/day** |
| Exact "parental control" bid | **$5.00** |
| Broad "parental control" bid | **$2.00** |
| Negative keywords (added 2026-07-16) | parent square, parentsquare, parentvue, infinite campus, school communication, nintendo switch |

### The strategy in one paragraph
We are NOT scaling — we are running a **$20/day funnel test**. Question being answered: *can Tic Lock convert a genuinely interested parent (high-intent "parental control" searcher) into a free trial?* Exact match at $5 gets first claim on the budget (quality installs); broad at $2 catches leftovers as a discovery net, now cleaned by negatives. The $20 cap is the risk control, so bids only decide WHO we buy, not how much we spend.

### KILL LINE (agreed, do not renegotiate casually)
**~40–50 total relevant installs with ZERO trials → PAUSE all ads.** At that point the problem is inside the app (onboarding/paywall/expectation mismatch), and no ad spend fixes it. Installs before the 2026-07-16 negatives count only partially — 6 of the first 9 US search-term installs were school-app seekers (see below), not real funnel tests.

### Scoreboard to maintain
| Date | Spend | Installs | Trials | Notes |
|---|---|---|---|---|
| 2026-07-13 (CA) | $1.52 | 0 | 0 | 114 imps, 1 tap |
| 2026-07-15 (US) | $102.48 | 14 | **0** | Pre-negatives; ~6+ installs were school-app pollution |
| _(add rows as data lands)_ | | | | |

---

## Next Actions

1. **~Jul 17–18:** ASC analytics lag clears → check behavior of first US installs (opens, deletions, paywall reached?). Claude can pull this.
2. **~Jul 23:** 1-week check — are post-negative installs starting any trials? Update scoreboard.
3. **~Jul 30:** Re-pull US Search Terms report — LOW_VOLUME mask should be lifting; promote winners to exact keywords, add new negatives.
4. **Ongoing:** watch for the FIRST trial — it changes the question from "is the funnel broken?" to "what does a trial cost?"
5. **Parked (do NOT start yet):** review US product page for monitoring-vs-rewards expectation mismatch — searchers may expect a surveillance app and bounce at a rewards app. (US metadata is frozen for organic baseline — reconcile before editing anything in ASC.)

---

## Log

### 2026-07-16 — Bids reshaped for quality-first testing
- Exact "parental control" bid raised $2.50 → **$5.00** (back to day-1 level; auctions were clearing at ~$3.50/tap, producing installs at $5.77–$7.00 with 50–60% tap→install rates — our best traffic).
- Broad stays $2.00 as discovery net. Daily budget stays $20.
- Expectation: ~4–6 exact taps/day → 2–3 high-intent installs/day → kill line reached in ~2 weeks.

### 2026-07-16 — Negative keywords added (the "school app" discovery)
US day-1 Search Terms report showed **~65% of spend ($49 of $75)** went to school-portal searches: parent square ($33 across 4 variants), parentvue ($6.95), infinite campus ($2.11), nintendo switch ($6.83). These are parents looking for their kid's **school communication app** — broad match saw "parent" and overreached. 6 of 9 tracked installs came from these searches → almost certainly explains the zero trials (they never wanted this product).
- **Negatives added:** parent square, parentsquare, parentvue, infinite campus, school communication, nintendo switch.
- **Parked hypothesis:** "school-app parents" as deliberate collateral audience — IF the funnel proves itself, test later in a separate ~$5/day ad group. Decision was "not now," not "worthless."
- Best performer identified: **"parental control app" (exact)** — 5 taps → 3 installs (60%), $5.77/install.

### 2026-07-16 — Spend cut after zero-trial day 1
US day 1: $102.48 → 14 installs → 0 trials, 0 subscriptions. Decision: stop scaling, start diagnosing.
- Daily budget → $20. Exact bid → $2.50 (later reversed, see above). Kill line agreed.

### 2026-07-15 — US campaign day 1 (reference numbers)
| Match | Imps | Taps | Installs | Spend | CPA | TTR | CR |
|---|---|---|---|---|---|---|---|
| Exact | 105 | 6 | 3 | $21.00 | $7.00 | 5.7% | 50% |
| Broad | 5,565 | 63 | 11 | $81.48 | $7.41 | 1.1% | 17% |
| **Total** | **5,670** | **69** | **14** | **$102.48** | **$7.32** | | |

Lesson: exact and broad had near-identical cost/install, so CPA (not TTR/CR) is the day-to-day metric — BUT install quality differs (see school-app discovery), so the real north star is **cost per trial/subscriber**, measurable only once trials exist.

### 2026-07-13 — Canada campaign day 1
Tiny: 114 imps, 1 tap, $1.52, 0 installs. Mostly LOW_VOLUME (Apple privacy mask — lifts as term volume grows). One off-topic term ("pictonico!") cost $0. Healthy, just small.

---

## Working Rules (learned this week)

1. **You pay per tap, not per impression** — irrelevant impressions cost nothing; judge keywords by cost per install, later cost per trial.
2. **LOW_VOLUME ≠ irrelevant** — it's Apple's privacy mask; it breaks into real terms as volume grows. A long tail stays masked forever.
3. **Search Terms report cadence:** every ~2 weeks, sort by Spend → block money-wasters (negatives), promote cheap-install terms to exact keywords.
4. **Broad match = discovery engine** — expect weird matches; the feature is finding terms you'd never bid on. Clean it with negatives, don't fear it.
5. **A hard daily cap means bids allocate, not spend** — raising a bid changes who you buy, not the bill.
6. **Don't fiddle daily** — settings changes reset learning; touch the account on the 2-week cadence unless something is on fire.
7. **ASC analytics lag 24–48h** — never judge today's installs today.
