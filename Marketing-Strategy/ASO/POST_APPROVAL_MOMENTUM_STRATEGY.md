# Post-Approval Momentum Strategy — Brain Coinz

**Version:** 1.4 (2026-04-17)
**Applies to:** Brain Coinz 1.0.3(1), approved 2026-04-17, 0 downloads, 0 reviews at writing.
**Companion docs:** `BASELINE_METRICS.md`, `ASO_EXECUTION_PLAN.md`, `APPFIGURES_ASO_INSIGHTS.md` (§5–12 are new 2026 Q&A findings)

---

## Headline Finding

The operating theory — **"the first days/weeks post-approval are deterministic for how Apple positions the app"** — is **supported by both Adam Lyttle (Nov 2025, verified transcript) AND Ariel Michaeli / Appfigures (Jan–Mar 2026, verified transcripts)**, but with different tactical implications. Key verbatim evidence:

> "The first few weeks of the app launch informs the App Store of everything it needs to know about your app, its target market, popularity, and where it will rank you in the next 6 months." — Adam Lyttle, `qaA23rN2lMw` (2025-11-28)

> "If you get [ratings] continually on and on every week over the course of about 30 days, the algorithm will learn that your app is something that it should elevate." — Ariel Michaeli, `2UID7_CPCi0` (2026-01-09)

The mechanism Ariel describes (30-day rating velocity → algorithm elevation) is the *same phenomenon* Lyttle describes as "the first few weeks set your 6-month trajectory." Not folklore — documented industry consensus from two independent expert sources.

**But:** the experts diverge sharply on one specific tactic — whether to bid on your own brand name in Apple Search Ads. Brain Coinz's current state (`brain coinz` ranked #33) puts us in the case where Lyttle is right and Ariel is wrong, but the decision reverses the moment we reach #1 organically for the brand term.

---

## Evidence Table (v1.2)

| Claim | Status | Source |
|---|---|---|
| First 2–4 weeks heavily influence 6-month ranking trajectory | Confirmed — two independent experts | Lyttle `qaA23rN2lMw` + Ariel `2UID7_CPCi0` |
| Rating VOLUME (not star value) drives ranking | **Confirmed** (new) | Ariel: *"The actual value of the rating is completely irrelevant"* — `2UID7_CPCi0` |
| Prompt for ratings EARLY — 75%+ users gone by day 2 | **Confirmed** (new) | Ariel `-8PrvZKx-VA` |
| Retention (D1/D7/D30) influences Apple ranking | **Disputed — reclassified from Consensus** | Ariel directly contradicts: *"On the Apple side of things... retention does not play into it"* — `cCwI5BgGhdw`. Industry teardowns say otherwise. Not load-bearing for Brain Coinz. |
| Download velocity in launch week is a ranking input | Confirmed developer observation | Lyttle `qaA23rN2lMw` |
| Impression → install conversion rate is a ranking input | Confirmed | Surfaced as primary dial in ASC Analytics |
| Screenshot OCR indexes text-on-image for keywords | Confirmed — two experts | Appfigures 2025 teardown + Ariel `cCwI5BgGhdw`: *"Apple did something really big and that is start reading the screenshots of apps with AI"* |
| Exact-match keyword in app title triggers "recommended search" boost for days | Confirmed developer observation | Lyttle `qaA23rN2lMw` — demonstrated with Swipe the Cat |
| **Keyword at BEGINNING of app name is load-bearing, brand at END** | **Confirmed** (new) | Ariel: Rain Alarm teardown (`qmtDVU9CLv8`) + *"Put brand name at the end. Make it very short."* (`2UID7_CPCi0`) |
| Don't duplicate keywords across name / subtitle / keyword list | Confirmed — two experts | Lyttle + Ariel (multiple) |
| Longtail keywords (2–3 word phrases) are the budget hack for small advertisers | **Confirmed** (new) | Ariel: *"the one hack that makes every campaign I've ever touched better"* — `9gzE3rmVXMI` |
| NEVER use Apple Search Ads "Search Match" feature | Confirmed — two experts | Lyttle `Z6DTKkfDqg4` + Ariel `qmtDVU9CLv8`: *"Never use search match, please. Search match is awful."* |
| Discovery campaigns only viable at $100k+ budgets | **Confirmed** (new) | Ariel `--DS9GWY8wM` |
| Kids/educational category has competitive ASA auctions | **Confirmed** (new) | Ariel `9gzE3rmVXMI`: *"at least two companies... bidding hard"* |
| Apple 2026 adds second in-line ad placement in search results | **Confirmed** (new) | Ariel `xNZCWApikus` — net effect: invest MORE in search, not less |
| Post-June-2025 new-app organic lag ("ASO nerf") | Confirmed developer observation | Lyttle `qaA23rN2lMw` + tweet |

---

## What This Means for Brain Coinz Specifically

Brain Coinz launched post-June-2025, so we are in the nerfed-organic cohort. `BASELINE_METRICS.md` confirms: 45/46 tracked keywords unranked, `brain coinz` at rank #33 (and drifting downward pre-deploy).

Six things follow from the combined Lyttle + Ariel evidence:

1. **Lyttle's brand-bid structure assumes pre-existing brand awareness we don't have.** His $66/7-day Visibility campaign only generated installs because his app already had word-of-mouth traffic searching his brand. Brain Coinz has zero brand awareness → bidding on `brain coinz` protects against an attack nobody is making. Revised play: either (a) skip ASA entirely in Week 1 and reinvest attention in rating volume, or (b) run a minimal defensive bid on `brain coinz` ($2 CPT, $5/day cap) and a scoped test of the category term `earn screen time` ($10 CPT, $50/day, 5 days) to get real CPA data before scaling. Flip the brand bid off once `brain coinz` reaches #1 organically.
2. **Rating VOLUME is the #1 ranking lever for the first 30 days.** Star value doesn't matter (Ariel); 1-star reviews still count toward the rating-velocity signal. Focus on getting ratings AT ALL, at an early and frequent prompt point.
3. **Start prompting for ratings early.** 75%+ users leave by day 2. A first-run prompt at the earliest delight moment (first successful unlock) beats a sophisticated later-stage prompt that 75% of users never see.
4. **Shift paid keyword strategy toward longtail.** Core single-word keywords (`screen time`, `parental control`) are uncompetitive for us in the first 30 days. Paid *and* organic should target 2–3 word phrases where competitors aren't already indexed.
5. **Do NOT rely on retention metrics as a ranking story.** If a teammate or stakeholder cites D7/D30 retention as critical for App Store ranking on Apple, that's disputed. It's still worth measuring for product health, just not for ASO attribution.
6. **The app name ordering is worth revisiting after Day 21.** Current: "Brain Coinz: Earn Screen Time" (brand first). Ariel's advice is keyword first, brand at end and short. A future rename to "Earn Screen Time: Brain Coinz" is a candidate — but NOT during the active 14-day measurement window.

---

## 2–4 Week Action List (v1.2)

Aligned with Day 14 (2026-05-01) and Day 21 (2026-05-08) re-measurements in `ASO_EXECUTION_PLAN.md`.

### Week 1 (2026-04-17 → 2026-04-24): Bridge the organic lag + kickstart rating velocity

1. **Decide on ASA posture — Lyttle's $1,000/day Visibility structure does NOT port over cleanly.** His structure assumed pre-existing brand awareness (people already searching his brand name). Brain Coinz has zero brand awareness, so a pure brand-term campaign will spend ~$0 and generate ~0 installs. Pick one:

   **Option A — Skip ASA in Week 1.** Reinvest attention into rating volume (action 3 below). Re-evaluate at Day 14 once organic data is in. Defensible, zero cash risk.

   **Option B — Minimal scoped ASA** (recommended if cash allows $250–$500 test budget):
   - **Campaign name:** "Visibility"
   - **Ad group 1 — Brand defense** (exact match): `brain coinz` only. **Max CPT $2, daily budget $5.** Pure insurance against competitor brand-bidding.
   - **Ad group 2 — Category test** (exact match): `earn screen time`. **Max CPT $10, daily budget $50, 5-day test.** After 5 days, compute CPA. Scale if sane; kill if not.
   - **Drop** `brain coinz earn screen time` — nobody types that.
   - **Search Match:** OFF (both experts unanimous).
   - **Discovery campaigns:** none. At our budget tier Ariel confirms 30% spend waste on broad-match ideas.
   - **Trigger to pause brand-defense group:** the day `brain coinz` reaches #1 organically and holds for 48h.
   - **Trigger to scale/kill category group:** CPA evaluation at end of Day 5.

2. **Verify the App Store recommended-search-list boost manually.** Open the iOS App Store, search each phrase in our app name/subtitle. If "Brain Coinz: Earn Screen Time" appears in the auto-suggestion dropdown before search results render, screenshot it — that window closes within days.

3. **Drive rating volume deliberately.** Target: ANY ratings across the first 14 days — volume matters, star value doesn't (per Ariel). Personal network asks should focus on "rate honestly" not "give 5 stars."

4. **Confirm SKStoreReviewController is wired at the earliest delight moment.** Per Ariel, 75% of users are gone by day 2. The first successful reward-app unlock is the right trigger — not onboarding, not first-open, but also not deep into day 2+.

5. **Start a keyword gap analysis against competitors.** Per Ariel's "first 30 days" answer: instead of chasing `screen time`, find 5–10 longtail keywords where our 3–5 direct competitors (from `ASTRO_COMPETITOR_INTELLIGENCE.md`) are NOT ranking. These are the early wins.

### Week 2 (2026-04-24 → 2026-05-01): OCR + longtail seeding

1. **Screenshot OCR audit.** Audit 8 live screenshots against the 1.0.3 keyword field. Any keyword with zero OCR coverage is a candidate for caption tweak on the next screenshot refresh.
2. **Keep name / subtitle / keyword field untouched.** Don't edit during the measurement window — we need 14 clean days for the diff against `BASELINE_METRICS.md`.
3. **Draft longtail keyword candidates.** From the gap analysis in Week 1, propose a 10x-localization expansion (per `APPFIGURES_ASO_INSIGHTS.md` §4) to be deployed AFTER Day 21 if the current metadata hasn't moved the needle.

### Day 14 (2026-05-01) and Day 21 (2026-05-08): Re-measure & decide

1. Re-run Astro against the 46 keywords in `BASELINE_METRICS.md`. Tag each: clear gain / clear loss / unchanged / still unranked.
2. Three decision branches:
   - **`brain coinz` climbed to #1 organically + ≥3 positioning keywords moved off rank 1000** → metadata works. Switch off Visibility ASA. Split budget into Launch + Experiment campaigns (per Ariel's separation rule). Begin shareable-moment design for retention of users that do install.
   - **`brain coinz` still rank-locked in the #30s + positioning keywords flat** → cohort-nerf hypothesis is load-bearing. Response: 10x-localization expansion with longtail keyword set, NOT another metadata rewrite.
   - **Mixed (brand climbed but category keywords flat)** → metadata direction right, but positioning keywords too competitive. Pivot keyword field to longtail candidates from gap analysis.
3. **Name-ordering decision gate.** If flat at Day 21, test renaming to "Earn Screen Time: Brain Coinz" in a subsequent submission — keyword first, brand last per Ariel. Do NOT attempt before Day 21; we'd invalidate the measurement.

---

## Open Gaps

1. ~~**Whether the App Store recommended-search-list boost actually triggered for Brain Coinz**~~ — **RESOLVED 2026-04-17: it did not.** Manual check showed Brain Coinz absent from the `earn screen time` autocomplete dropdown (9 competitors present, all using `[brand]: earn screen time` format) and the `brain coinz` brand search returned an empty dropdown. Apple's autocomplete has not indexed Brain Coinz yet — consistent with the post-June-2025 new-app organic lag. The boost window Lyttle described is either closed or was never opened for our cohort. See `ASTRO_COMPETITOR_INTELLIGENCE.md` → "2026-04-17 — 'Earn Screen Time' Dropdown Competitors".
2. ~~**Which specific longtail keywords competitors are NOT ranking for**~~ — **RESOLVED 2026-04-17** via `extract_competitors_keywords` run against the 9 dropdown competitors + top-50 `earn screen time` results. 32 of 36 surfaced keywords are NOT in our 46-keyword baseline; most are adult-productivity vocabulary (`brainrot`, `unrot`, `claim app`, `focus timer`). 5 viable longtail candidates identified for kids+earn fit: `time control`, `screen limit`, `time limit`, `chores` (standalone), `earn` (standalone). Parked for Week 2 consideration; not acting during the 14-day measurement window. See `ASTRO_COMPETITOR_INTELLIGENCE.md` → "Longtail Candidates for Brain Coinz".
3. **Whether a `brain coinz` → "Earn Screen Time: Brain Coinz" rename would outweigh the metadata-rewrite cost** — can't decide until we see Day 21 data.
4. **Whether Ariel's "retention not a ranking factor" claim is Apple-specific vs. cross-platform** — he's explicit it's Apple-only (Google does count it), but the broader ASO literature treats retention as cross-platform signal. Not critical for near-term decisions.
5. **Whether consolidating subscription groups (`project_subscription_groups.md`: Solo/Individual/Family → 1 "Brain Coinz" group) affects conversion rate as a ranking dial.** Open question for the next ASC submission.
6. **NEW: Whether Brain Coinz should compete for `earn screen time` (adult-productivity crowd) or only for the kids+earn intersection (ScreenEarn, ScreenCoach, Thrive — 19 reviews combined).** The phrase is dominated by adult self-control apps; our real competitive set is 3 small parental-controls apps. Revisit after Day 14.

---

## Sources

**Primary video sources (transcripts retrieved via YouTube Data v3 API, 2026-04-17):**

Lyttle (indie developer, $1.19M App Store revenue):
- `qaA23rN2lMw` — My $1.19M App Process: Launch & Marketing (Part 3) — 2025-11-28 — https://www.youtube.com/watch?v=qaA23rN2lMw
- `Z6DTKkfDqg4` — Beginner App Store Ad mistakes to avoid — 2025-10-03 — https://www.youtube.com/watch?v=Z6DTKkfDqg4
- Tweet: https://x.com/adamlyttleapps/status/2025113888207827100

Appfigures (Ariel Michaeli, 15+ years ASO, Appfigures co-founder/CEO):
- `qmtDVU9CLv8` — Your App Isn't Ranking, Here's Why: Live Keyword Teardown — 2026-03-05
- `9gzE3rmVXMI` — Apple Ads for Beginners in 2026: Live AMA — 2026-02-19
- `2UID7_CPCi0` — Is Your ASO Ready for 2026? App Store Optimization Q&A — 2026-01-09
- `cCwI5BgGhdw` — I have 15+ yrs of App Marketing Knowledge.. Ask me Anything — 2025-09-04
- Plus 6 Appfigures shorts (see `APPFIGURES_ASO_INSIGHTS.md` §5–12 table for full list)

**Internal:**
- `BASELINE_METRICS.md` — 46-keyword pre-deploy snapshot (2026-04-14)
- `ASO_EXECUTION_PLAN.md` — live 1.0.3 metadata, Day 14 / Day 21 re-measure dates
- `APPFIGURES_ASO_INSIGHTS.md` — OCR indexing, 10x localization, 2026 Q&A analysis (§5–12)
- `ASTRO_COMPETITOR_INTELLIGENCE.md` — keyword Pop/Diff and competitor landscape

---

## Changelog

- **v1.4 (2026-04-17):** Revised ASA Week 1 recommendation after recognizing Lyttle's brand-bid structure assumes pre-existing brand awareness Brain Coinz lacks. Replaced the "$1,000/day Visibility on brand" plan with two scoped options: (A) skip ASA in Week 1, or (B) minimal split — `$5/day` brand-defense on `brain coinz` + `$50/day × 5-day` category test on `earn screen time`. Dropped `brain coinz earn screen time` (no search volume). Annotated "Six things follow" item 1 with the same caveat.
- **v1.3 (2026-04-17):** Resolved Open Gaps #1 and #2 via Astro competitor analysis of the 9 `earn screen time` dropdown apps. Dropdown check confirmed Brain Coinz absent (autocomplete not yet indexed) — recommended-search-list boost did not fire. Keyword gap analysis surfaced 5 longtail candidates (parked for Week 2). Added Open Gap #6: the real competitive set for kids+earn is 3 small apps (ScreenEarn, ScreenCoach, Thrive), not the 9 adult-productivity apps in the dropdown. `earn screen time` added to Astro tracking set with Day-1 baseline rank 1000.
- **v1.2 (2026-04-17):** Incorporated transcript analysis of 4 long-form Appfigures Q&A/AMA videos + 6 shorts. Retention reclassified Consensus → **Disputed** (Ariel's direct contradiction). Rating volume (not star value) promoted to primary lever. Added longtail keyword strategy, keyword-gap analysis, and name-ordering decision gate. Reconciled Lyttle vs. Ariel on brand bidding — our case (rank #33) is Lyttle's; flip to Ariel's once we reach #1.
- **v1.1 (2026-04-17):** Lyttle transcripts verified via Data API. ASA Visibility moved from "after 10 reviews" to "day 1." Recommended-search-list boost added as Week 1 action.
- **v1.0 (2026-04-17):** Initial draft based on walk-back tweet only.
