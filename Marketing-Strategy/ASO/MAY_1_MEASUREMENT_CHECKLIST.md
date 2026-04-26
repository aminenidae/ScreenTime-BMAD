# May 1 Release + Measurement Checklist — Brain Coinz 1.0.3 → 1.0.4 Transition

**Drafted:** 2026-04-21
**Owner:** Ameen
**Release date:** 2026-05-01 (scheduled release of 1.0.4)
**Measurement gate:** 2026-05-01 (Day 14 of 1.0.3(1), reference-only) → 2026-05-15 (Day 14 of 1.0.4)

**Purpose:** Submit 1.0.4 this week with a scheduled release of 2026-05-01, capture a Day-14 reference read of 1.0.3 on May 1 for learning (not as a gate), then re-read at Day 14 + 21 post-1.0.4-live.

---

## Release strategy — why scheduled release, not "submit on May 1"

ASC supports three release modes for an approved version:
1. **Auto-release on approval** — unpredictable; tied to Apple review speed.
2. **Manual release** — approved version held, developer releases with one click when ready.
3. **Scheduled release** — approved version goes live automatically on a specified future date.

We are using **option 3, scheduled release = 2026-05-01.** Reasons:

| Factor | Submit on May 1 | Submit now + schedule May 1 |
|---|---|---|
| Apple review risk | On critical path (1–3 day variance) | Off critical path — approved well before May 1 |
| 1.0.4 Day-14 measurement date | Floating (~May 15–21 depending on approval) | **Locked: 2026-05-15** |
| May 1 workload | Measure + submit + hope | Measure + one-click gate |
| Metadata lock-in | Can tweak until May 1 | Locked the moment you submit |
| Can back out? | N/A | Yes — ASC allows cancel of scheduled release before it fires |

Clean, deterministic Day-14 math is the big win.

## Why the May 1 read is now a reference point, not a gate

Earlier drafts of this doc treated 1.0.3 Day-14 as a gate on whether to ship 1.0.4. That was wrong. The four post-read paths actually resolve like this:

| Path | 1.0.3 Day-14 diagnosis | What 1.0.4 does about it | Action |
|---|---|---|---|
| 1. Healthy | Metadata rewrite worked | Cascade amplifies wins | **Ship 1.0.4** |
| 2. Partial | 1–2 primaries moved | Fuller token pool + Name change may push the rest | **Ship 1.0.4** |
| 3. Broken canaries | Likely locale-routing (EN_CA primary not serving US) | **1.0.4 literally fixes this** by adding a dedicated EN_US locale | **Ship 1.0.4** |
| 4. True rollback | `brain coinz` < 150 AND nothing replaced it | Only case where current 1.0.4 payload is wrong. Action is to **edit 1.0.4's metadata to a rollback payload and re-release** — NOT stay on 1.0.3. | Cancel scheduled release → edit metadata to 1.0.2 Name/Subtitle → re-release |

Staying on 1.0.3 is never the answer: if 1.0.3 worked, 1.0.4 extends it; if it didn't, 1.0.4 has different metadata and structural locale fix; if it hurt us, we ship rollback **as** 1.0.4. So for 3 of 4 paths, 1.0.4 ships as drafted. Only the rare Path 4 triggers cancel-and-swap.

---

## Section A — Pre-submit checklist (execute this week, 2026-04-21 → 2026-04-25)

All items must be ✅ before clicking Submit. Goal: 1.0.4 in Apple's review queue by end of week, approved and scheduled by April 27–28.

### A1. Metadata (per `1.0.4_METADATA_DRAFT.md`)
- [x] Name locked: `Brain Coinz: Parental Control` (set at App Information level)
- [x] Subtitle locked per locale: `Limit screen time, differently`
- [x] EN_US KW field locked (100/100): `motivate,positive,reinforcement,educational,limit,reduce,play,unlock,brainrot,parenting,control,lock`
- [x] EN_CA / EN_GB / EN_AU KW fields mirror EN_US
- [x] ES_MX KW field locked (10x-trick payload)
- [x] Promo Text locked (158/170)
- [x] What's New locked (bug-fix scope, 210 chars)
- [x] Description copied across all 5 locales

### A2. Screenshots (EN_US primary set)
- [x] 10 screenshots uploaded to EN_US at 1290×2796
- [x] **Clone same 10 images in same order to EN_CA**
- [x] **Clone same 10 images in same order to EN_GB**
- [x] **Clone same 10 images in same order to EN_AU**
- [x] **Clone same 10 images in same order to ES_MX**

### A3. Binary
- [ ] 1.0.4 binary archived in Xcode
- [ ] Version number = 1.0.4, build number = next unused integer
- [ ] Build uploaded to ASC (Transporter or Xcode Organizer)
- [ ] Build processed by ASC (green checkmark, usable from the Version screen)

### A4. Review Information
- [ ] Reviewer notes pasted from `app-review-notes.md` — MUST include the "In-App Controls / Parental Controls = None" guidance that resolved the 2.3.6 rejection on 1.0.3. Apple re-reads this on every submission.
- [ ] Demo parent account credentials (if required — 1.0.3 used none because PIN is device-local; re-confirm for 1.0.4)
- [ ] Contact info current

### A5. Settings inherited from 1.0.3 (verify unchanged)
- [ ] Age rating: unchanged
- [ ] Primary category: unchanged
- [ ] Secondary category: unchanged
- [ ] App Privacy questionnaire: unchanged (no new tracking added in 1.0.4)
- [ ] Export compliance: No (unchanged)
- [ ] Content rights: Yes, do not contain third-party content (unchanged)

### A6. Release configuration
- [ ] **Release mode = Scheduled release**
- [ ] **Release date = 2026-05-01** (local store timezone — confirm ASC's display timezone)
- [ ] Phased release: optional decision. Phased release rolls out to 1/2/5/10/20/50/100% over 7 days. Pros: limits damage if bugs emerge. Cons: slows velocity signal to Apple's ranking algorithm. **Recommendation for 1.0.4: OFF** (want full velocity signal for the Day-14 measurement). Confirm:
  - [ ] Phased release: OFF

### A7. TestFlight smoke test (before submitting to review)
- [ ] Install 1.0.4 TestFlight build on physical device
- [ ] Verify parent onboarding (Solo + Family path)
- [ ] Verify pairing flow end-to-end
- [ ] Verify subscription flow (trial + paid tier)
- [ ] Verify child-side app unlock/lock behavior
- [ ] Verify rating prompt fires on parent device at the expected trigger
- [ ] Verify no debug UI is visible (Skip-to-Paywall button should be hidden — UserDefaults gate applied 2026-04-20)
- [ ] No crashes on cold launch, pairing, subscription purchase, or Screen Time authorization

### A8. Submit
- [ ] Click "Submit for Review" in ASC
- [ ] Record submit timestamp: _______
- [ ] Record approval timestamp: _______ (expected 24–72h later)

---

## Section B — Items NOT blocking 1.0.4 submission (parallel work)

These are deliberately deferred. They can happen during or after Apple review.

### Custom Product Pages (CPPs) — task #9
CPPs are independent of the version submission. They are their own mini-review (~24–48h each) and exist as alternate product pages accessible via unique URLs, targeted at specific traffic sources (TikTok, editorial, parenting communities).

**Timeline to have CPPs live on May 1:**
- 2026-04-21 → 2026-04-23: Draft 5 CPP content briefs (task #9)
- 2026-04-24 → 2026-04-26: Create CPPs in ASC; submit for review
- 2026-04-28 → 2026-04-30: CPPs approved, URLs ready to distribute
- 2026-05-01: 1.0.4 goes live + CPPs live = full attribution stack on Day 1

Not a submit blocker, but a parallel track worth starting now.

### Subscription group consolidation
MEMORY flags this as "CRITICAL PENDING: 3 separate groups (Solo/Individual/Family) must be consolidated into 1 'Brain Coinz' group before production launch." 1.0.3 shipped without it, so it is not a hard blocker for 1.0.4 either. Deferring to 1.0.5 unless there is a specific reason to bundle it now. If you decide to do it for 1.0.4, flag immediately — it affects StoreKit product IDs and ASC pricing structure, and would need a separate review cycle of its own.

### Content/community work (tasks #12–#15)
TikTok batch, Apple editorial pitch, Indie App Santa, parenting communities — all happen after 1.0.4 is live. Not submit blockers.

---

## Section C — April 30 pre-read (Day −1, 2026-04-30 evening)

Prep for the May 1 reference read. 30 minutes.

- [ ] Verify `brain coinz` is still the only ranked term on Astro. If another keyword has entered top-1000 ahead of schedule, note the date/pop/diff — early movement is signal.
- [ ] Screenshot (for the record) the App Store Connect **Analytics → Sources → App Store Search** panel for the past 14 days. Save to `Marketing-Strategy/ASO/evidence/2026-04-30_asc_search_14d.png`.
- [ ] Confirm no new reviews have appeared on the Live version. If they have, note star + date.
- [ ] Confirm 1.0.4 is approved + scheduled release date = 2026-05-01. If approval still pending → alert user (may need to switch to manual release and hope for approval May 1 morning).

---

## Section D — May 1 reference read (Day 14 of 1.0.3, 2026-05-01 morning)

Run this **before** 1.0.4 flips live later that day (ASC scheduled releases typically fire around midnight store-timezone; run this read in the early morning US Pacific to catch pre-release state, OR in late afternoon to measure post-release — pick one, document which).

### D1. Astro keyword ranks
- [ ] Run `mcp__astro__get_app_keywords(appId: "6753270211", store: "us")`
- [ ] Save raw JSON response to `Marketing-Strategy/ASO/evidence/2026-05-01_astro_us.json`
- [ ] Diff `currentRanking` against `BASELINE_METRICS.md`. Flag: newly indexed (`1000 → rank < 1000`), deterioration (`rank dropped > 50`).

### D2. Primary-win verdict on 1.0.3 (reference only)
- [ ] `earn screen time` (Pop 5, Diff 45) → target top 50. Actual: _______
- [ ] `reward kids` (Pop 5, Diff 21) → target top 100. Actual: _______
- [ ] `positive reinforcement` (Pop 5, Diff 39) → target top 100. Actual: _______
- [ ] `motivate kids` (Pop 5, Diff 44) → target top 150. Actual: _______
- [ ] `limit screen time` (Pop 23, Diff 55) → target top 200. Actual: _______
- [ ] `brain coinz` → target hold/improve from 33. Actual: _______

### D3. Indexing canaries
- [ ] `time limit` (Pop 7, Diff 55). Actual: _______
- [ ] `app limit` (Pop 7, Diff 55). Actual: _______
- [ ] `screen limit` (Pop 6, Diff 56). Actual: _______
- [ ] `screen time limit` (Pop 11, Diff 55). Actual: _______

### D4. Path classification — does 1.0.4 still ship as drafted?
- [ ] Check Path 4 condition: `brain coinz` rank < 150 AND zero new indexed tokens.
  - **NO** (default expectation) → 1.0.4 ships as drafted. **No ASC action needed — scheduled release fires automatically.**
  - **YES** → cancel 1.0.4 scheduled release, edit metadata to rollback payload (restore 1.0.2 Name/Subtitle), re-release.

### D5. ASC Analytics funnel (14-day window, 2026-04-17 → 2026-04-30)
- [ ] Filter Analytics → Acquisition → Source Type = App Store Search, Territory = US.
- [ ] Impressions: _______
- [ ] Product Page Views: _______
- [ ] Impression → PPV CVR: _______%
- [ ] Total Downloads: _______
- [ ] PPV → Download CVR: _______%
- [ ] Impression → Download CVR (overall): _______%
- [ ] Also pull Source Type = App Store Browse — Impressions: _______ / Downloads: _______
- [ ] Export CSV to `Marketing-Strategy/ASO/evidence/2026-05-01_asc_analytics.csv`

### D6. Rating + review velocity
- [ ] Current rating count (US): _______
- [ ] Current average stars: _______
- [ ] New reviews since 2026-04-17: _______
- [ ] Star distribution of new reviews: _______

### D7. Archive 1.0.3 read
- [ ] Append findings to `BASELINE_METRICS.md` as "1.0.3 Day 14 read — 2026-05-01".
- [ ] Record in this checklist above.

---

## Section E — 1.0.4 Day 14 re-read (2026-05-15)

Execute the D1–D6 protocol against the 1.0.4 live state.

### E1. Success criteria for 1.0.4
Tighter than 1.0.3 because of stacked improvements (new Name anchors + EN_US locale + added KW tokens).

**Primary — anchored to 1.0.4 locked tokens:**
- [ ] `parental control app` (Pop 57, Diff 65) → top 300 — new Name anchor
- [ ] `parental control` (Pop 41, Diff 65) → top 200
- [ ] `control parental` (Pop 44, Diff 60) → top 200
- [ ] `limit screen time` (Pop 23, Diff 55) → top 100
- [ ] `brainrot` (Pop 55, Diff 48) → top 300
- [ ] `parenting` (Pop 23, Diff 57) → top 200
- [ ] `time control` (Pop 20, Diff 48) → top 200
- [ ] `motivate` (Pop 19, Diff 53) → top 150
- [ ] Hold all 1.0.3 wins (no regression > 50 positions)

**Secondary:**
- [ ] `screen time limit` (Pop 11) → top 150
- [ ] `positive reinforcement` (Pop 5, Diff 39) → top 50
- [ ] `reward kids` (Pop 5, Diff 21) → top 50
- [ ] `educational rewards` (Pop 5, Diff 23) → top 50

**Rollback trigger (1.0.5 decision):**
- [ ] `brain coinz` rank drops below 200 (was 33 at 1.0.3 baseline)
- [ ] Net new-ranked keyword count < 5
- [ ] Either → plan 1.0.5 with 1.0.3 metadata restored

---

## Section F — 1.0.4 Day 21 re-read (2026-05-22)

Lighter pass. Same queries, trajectory focus.

- [ ] Re-run D1 (Astro) and D5 (ASC Analytics) — save to `evidence/2026-05-22_*`.
- [ ] Compare Day 14 → Day 21 for each primary/secondary target.
- [ ] Note trend (up / flat / down) per keyword in `BASELINE_METRICS.md` trend column.
- [ ] Decision gate: if trajectory flat/declining on ≥ 4 primaries → plan 1.0.5 refinement (drop lowest-performing token, add verified replacement).

---

## Appendix — Exact commands + URLs

### Astro keyword dump
```
mcp__astro__get_app_keywords(appId: "6753270211", store: "us")
```

### Astro per-keyword rank check
```
mcp__astro__search_rankings(appId: "6753270211", keyword: "parental control", store: "us")
```

### ASC Analytics URL (requires login)
```
https://appstoreconnect.apple.com/analytics/app/d30/6753270211/metrics?m=impressions,impressionsUnique,pageViews,pageViewsUnique,installs&dimensionFilters=[{"key":"source","values":["Institutional_App_Store_Search"]},{"key":"storefront","values":["US"]}]
```

### Evidence storage
All raw exports + screenshots to `Marketing-Strategy/ASO/evidence/` with `YYYY-MM-DD_` prefix.

---

## Cross-references

- `BASELINE_METRICS.md` — 2026-04-14 baseline, the control we diff against.
- `1.0.4_METADATA_DRAFT.md` — locked 1.0.4 payload.
- `ASO_EXECUTION_PLAN.md` — broader strategy context.
- `POST_APPROVAL_MOMENTUM_STRATEGY.md` — Lyttle/Ariel source synthesis behind the 14-day window thesis.
- `app-review-notes.md` — reviewer notes block to paste on 1.0.4 submit (MUST re-paste every submission).
