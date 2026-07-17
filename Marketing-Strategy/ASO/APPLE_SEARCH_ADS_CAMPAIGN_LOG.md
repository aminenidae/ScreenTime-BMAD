# Apple Search Ads — Campaign Log

**Live document. Newest entries at the top of the log. Update after every settings change or data review.**

---

## Current State (as of 2026-07-17)

| Setting | Value |
|---|---|
| Campaigns | Canada_2026.07.14_v1.0.8 (ID 2144267261) · US_2026.07.15_v1.0.8 (ID 2144282313) |
| US ad group | United States (ID 2149812181) |
| Currency / TZ | CAD / America/Winnipeg |
| Daily budget (US) | **$20/day** |
| Exact "parental control" bid | **$5.00** |
| Broad "parental control" bid | **$2.00** |
| Negatives round 1 (2026-07-16) | parent square, parentsquare, parentvue, infinite campus, school communication, nintendo switch |
| Negatives round 2 (2026-07-17) | **parent portal** (catch-all for all school portals), parent vue, tikcotech, google family link, learning genie, roblox, qustodio, bright canary — all BROAD |

### The strategy in one paragraph
We are NOT scaling — we are running a **$20/day funnel test**. Question being answered: *can Tic Lock convert a genuinely interested parent (high-intent "parental control" searcher) into a free trial?* Exact match at $5 gets first claim on the budget (quality installs); broad at $2 catches leftovers as a discovery net, now cleaned by negatives. The $20 cap is the risk control, so bids only decide WHO we buy, not how much we spend.

### KILL LINE (agreed, do not renegotiate casually)
**~40–50 total relevant installs with ZERO trials → PAUSE all ads.** At that point the problem is inside the app (onboarding/paywall/expectation mismatch), and no ad spend fixes it. Installs before the 2026-07-16 negatives count only partially — 6 of the first 9 US search-term installs were school-app seekers (see below), not real funnel tests.

### Scoreboard to maintain
| Date | Spend | Installs | Trials | Notes |
|---|---|---|---|---|
| 2026-07-13 (CA) | $1.52 | 0 | 0 | 114 imps, 1 tap |
| 2026-07-15 (US) | $113.93 (finalized) | 15 | **0** | Pre-negatives; ~11 of 15 installs were school-app pollution (parent square alone: 9). CPA $7.59 |
| 2026-07-16 (US) | $20.50 | 4 | **?** | Budget cap kicked in; negatives added mid-day so ~2 of 4 still school leakage. CPA $5.12 |
| _(2026-07-17 = first fully-clean day — watch this one)_ | | | | |

---

## Next Actions

1. **HIGHEST VALUE — onboarding UX audit (in progress 2026-07-17):** device-selection screen (~42% quit) + Screen Time permission (denials) are the leaks. Audit views end-to-end against the ad→screenshot→onboarding expectation chain; propose fixes. DONE: funnel diagnosis (see 2026-07-17 reframe entry).
2. **Jul 20 & Jul 28:** the ONLY 2 real trials (Finland, Belgium) expire — check RevenueCat for conversion. First real trial→paid signal.
3. **RevenueCat dashboard TODO (user-only):** flip on Apple Search Ads integration (Project Settings → Integrations → Apple Ads). Code side is done but uncommitted; ships next build.
4. **Watch Jul 17 ad data** — first fully-clean ad day. Judge ads on onboarding-completion rate (via Firebase), not same-day trials.
5. **~Jul 30:** Re-pull US Search Terms — LOW_VOLUME mask lifting; promote winners to exact, add new negatives.
6. **Parked:** US product-page monitoring-vs-rewards mismatch review. (US metadata frozen for organic baseline — reconcile before editing anything in ASC.)

---

## Log

### 2026-07-17 — THE REFRAME: onboarding funnel is the problem, not ads/paywall/price
Full BigQuery funnel analysis (Firebase Analytics export `analytics_518672259`, complete funnel valid from 2026-07-03 when welcome/device-selection events shipped):
- **Jul 3–16, all users:** 24 saw welcome → 17 reached "parent or child?" → 14 picked → 11 hit Screen Time permission → 7 granted (3 denied) → **4 reached paywall decision → 3 tapped "Not Now" → ALL 3 accepted the freemium trial rescue** → 1 purchase (Winnipeg = own sandbox test).
- **Design intent confirmed by CEO:** paywall-FIRST; the no-card free trial is an exit-intent rescue behind the "Not Now" button — NOT a default trial for everyone. The mechanic works: 3/3 acceptance.
- **Fake conversions identified:** the 4 `subscription_started` (Jul 1–3) = `rc_promo_Family_lifetime` grant + own Canada sandbox Solo purchase. Zero real revenue ever.
- **Only 2 real humans have ever started a trial:** Helsinki, Finland (Jul 6 → expires ~Jul 20) and Belgium (Jul 14 → expires ~Jul 28). Both European; Belgium = French-localization target. These 2 trials are the first real trial→paid test.
- **~83% of app-openers die before the paywall.** Killers: device-selection screen ("parent or child?", ~42% quit at/before it — consistent across 2 weeks) and Screen Time permission (3 of 11 denied, 1 abandoned).
- **No ad-driven install (Jul 15–16) has EVER reached the paywall.** Last onboarding completion was Jul 14, pre-ads.
- **Decision: priority shifts from ad tuning to onboarding UX.** Kill-line logic revised: trials lag installs (paywall is at END of onboarding, and the freemium rescue means "trial" ≠ "payment intent"); judge ads on onboarding-completion rate, not same-day trials.
- **Access note:** Firebase/BigQuery access confirmed working via `bq` CLI (gcloud project `screentimerewards`), Analytics dataset `analytics_518672259`, intraday table available same-day.

### 2026-07-17 — Negatives round 2 + budget cap confirmed working
July 16 data proved the round-1 negatives + $20 cap worked: spend crashed $113.93 → $20.50, CPA $7.59 → $5.12, parent square $60 → ~$2.50, parentvue/nintendo → ~$0. Small residual leaks were timing (negatives added mid-day Jul 16). New leaks surfaced → round-2 negatives added (all BROAD):
- **parent portal** — catch-all: blocks any search with "parent" + "portal" (focus parent portal, infinite campus parent portal, + all future school portals in one entry).
- parent vue (two-word gap past "parentvue"), tikcotech, google family link, learning genie, roblox, qustodio, bright canary.
- **Rule established:** use BROAD negatives to kill a *category*; exact only to block one phrase while keeping variants (rare).
- **2026-07-17 is the first fully-clean test day** — first day $20 buys only genuine parental-control searchers.

### 2026-07-17 — RevenueCat attribution wired (code) + "customers" list explained
- **Code change (uncommitted):** added `Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()` in `SubscriptionManager.swift` configureRevenueCat(). Enables Apple Search Ads → RevenueCat keyword-level trial/subscriber attribution. First-party, no ATT prompt. Verified method exists in RC 5.56.1 SDK source. Ships in next build; cannot backfill existing installs. **Still TODO:** flip on Apple Search Ads integration in RevenueCat dashboard (Project Settings → Integrations), + ship build.
- **App already has (discovered):** RevenueCat fully configured (Solo/Individual/Family, 14-day trial); Firebase Analytics (`AppAnalytics.swift`) with FULL onboarding→paywall→purchase funnel events + install-week cohorts. The onboarding-checkpoint tracking I worried was missing is already built.
- **RevenueCat "Customers" list = app OPENERS, not payers.** A record is created on app launch (configure + logIn deviceID). CSV export (new_customers.csv) showed ~47 records back to Jun 20, ALL with blank status/store/product = zero subscriptions/trials. Count inflated by anonymous+identified duplicate pairs (same device, same timestamp). **Key insight:** zero conversions across a month of ORGANIC users too — not just ad traffic. Points to app funnel (onboarding/paywall/trial mechanics), not ad targeting, as the conversion problem. → Firebase onboarding funnel is now the highest-value diagnostic.

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
