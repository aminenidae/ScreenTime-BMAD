# 1.0.3 → 1.0.4 Release + Measurement Checklist — Brain Coinz

**Drafted:** 2026-04-21
**Updated:** 2026-05-06 (build 7 withdrawn by user; build 8 in progress)
**Owner:** Ameen
**Submit history:** Build 7 submitted 2026-05-01 evening → **WITHDRAWN by user 2026-05-06** before approval (serious bugs surfaced post-submit). Build 8 in development.
**Resubmit date:** TBD (depends on build 8 fix scope)
**Release date:** TBD on Apple approval of build 8; release mode = manual one-click on approval
**Measurement gate:** Day-14 anchored to 1.0.4 LIVE date (approval + release), not approval date alone — clock has not started yet

**Purpose:** Capture a Day-14 reference read of 1.0.3 (1) once the actual data window closes, then re-read at Day 14 + 21 post-1.0.4-live to score the metadata rewrite.

---

## Release strategy — what changed vs. the original plan

**Original plan (Apr 21 draft):** submit early, scheduled release pinned to 2026-05-01 — Day-14 measurement locked to 2026-05-15.

**What actually happened:**
1. Last-mile fixes pushed submission from Apr 28 to evening of **2026-05-01** as build 7.
2. **2026-05-06 — build 7 withdrawn by user.** Serious bugs surfaced post-submit. Build 8 now in development with additional fixes.
3. Resubmission date TBD on build-8 readiness. The "scheduled release for May 1" trick is gone; the May-15 Day-14 target is also gone.

**Implications:**
- 1.0.4 Day-14 measurement floats. Anchor it to LIVE date (= approval date + manual release click) of **build 8**, not build 7.
- Apple review for 1.0.4 ranges 1–3 days typical, but can extend. Plan a window, not a point.
- The 2026-05-02 reference-read of 1.0.3 (Section D below) is preserved as-is — captured Day 16 of 1.0.3 in isolation, still our last clean baseline before any 1.0.4 flip. Re-read is unnecessary unless build 8 takes >2 weeks to ship.
- Decision: **manual release on build-8 approval** (not scheduled).

## Why the 1.0.3 Day-14 read is a reference point, not a gate

Earlier drafts of this doc treated 1.0.3 Day-14 as a gate on whether to ship 1.0.4. That was wrong. The four post-read paths actually resolve like this:

| Path | 1.0.3 Day-14 diagnosis | What 1.0.4 does about it | Action |
|---|---|---|---|
| 1. Healthy | Metadata rewrite worked | Cascade amplifies wins | **Release 1.0.4 on approval** |
| 2. Partial | 1–2 primaries moved | Fuller token pool + Name change may push the rest | **Release 1.0.4 on approval** |
| 3. Broken canaries | Likely locale-routing (EN_CA primary not serving US) | **1.0.4 literally fixes this** by adding a dedicated EN_US locale | **Release 1.0.4 on approval** |
| 4. True rollback | `brain coinz` < 150 AND nothing replaced it | Only case where current 1.0.4 payload is wrong. Action is to **edit 1.0.4's metadata to a rollback payload before clicking release** — NOT stay on 1.0.3. | Hold release → edit metadata to 1.0.2 Name/Subtitle → re-submit (new review cycle) |

Staying on 1.0.3 is never the answer: if 1.0.3 worked, 1.0.4 extends it; if it didn't, 1.0.4 has different metadata and structural locale fix; if it hurt us, we ship rollback **as** 1.0.4. So for 3 of 4 paths, 1.0.4 ships as drafted. Only the rare Path 4 triggers a hold-and-swap (which now costs another review cycle, since metadata edits to a build under review require resubmission).

---

## Section A — Pre-submit checklist (build 7 SUBMITTED 2026-05-01 then WITHDRAWN 2026-05-06; package re-rides build 8)

Status: ⚠️ Build 7 was submitted then withdrawn. Metadata package below is staged for build 8 unchanged. **Re-verify** the ASC fields (esp. "In-App Controls / Parental Controls" questionnaire — see `app-review-notes.md`) before resubmitting build 8 — ASC silently re-opens the questionnaire on resubmit.

### A1. Metadata (staged for build 8 = as-submitted in withdrawn build 7)
- [x] Name: `Brain Coinz: Parental Control` (set at App Information level)
- [x] Subtitle per locale: `Limit screen time, reward kids` (30/30) — Apr 28 swap from `…, differently` to anchor reward-chart niche
- [x] EN_US KW field (98/100): `parenting,control,lock,kids,family,reward,chart,behavior,tasks,chore,positive,reinforcement,brainrot` — Apr 27–28 swap applied
- [x] EN_CA / EN_GB / EN_AU KW fields mirror EN_US
- [x] ES_MX KW field locked (10x-trick payload)
- [x] Promo Text: `Parental Control Reinvented! End screen time battles…` (new copy)
- [x] What's New (bug-fix scope, 210 chars)
- [x] Description: new Q&A format ("Stop fighting over screen time")

### A2. Screenshots (EN_US primary set)
- [x] 10 screenshots uploaded to EN_US at 1290×2796
- [x] **Clone same 10 images in same order to EN_CA**
- [x] **Clone same 10 images in same order to EN_GB**
- [x] **Clone same 10 images in same order to EN_AU**
- [x] **Clone same 10 images in same order to ES_MX**

### A3. Binary
- [x] 1.0.4 binary archived in Xcode
- [x] Version number = 1.0.4, build number = 7
- [x] Build uploaded to ASC
- [x] Build processed by ASC

### A4. Review Information
- [x] Reviewer notes pasted from `app-review-notes.md` (incl. "In-App Controls / Parental Controls = None")
- [x] Demo parent account credentials provided as required
- [x] Contact info current

### A5. Settings inherited from 1.0.3 (verify unchanged)
- [x] Age rating: unchanged
- [x] Primary category: unchanged
- [x] Secondary category: unchanged
- [x] App Privacy questionnaire: unchanged (no new tracking added in 1.0.4)
- [x] Export compliance: No (unchanged)
- [x] Content rights: Yes, do not contain third-party content (unchanged)

### A6. Release configuration
- [x] **Release mode = Manual release on approval** (changed from "Scheduled 2026-05-01" — submission slipped past the schedule date)
- [x] Phased release: OFF (full velocity signal for Day-14 measurement)

### A7. TestFlight smoke test (before submitting to review)
- [x] Install 1.0.4 TestFlight build on physical device
- [x] Verify parent onboarding (Solo + Family path)
- [x] Verify pairing flow end-to-end
- [x] Verify subscription flow (trial + paid tier)
- [x] Verify child-side app unlock/lock behavior
- [x] Verify rating prompt fires on parent device at the expected trigger
- [x] Verify no debug UI is visible
- [x] No crashes on cold launch, pairing, subscription purchase, or Screen Time authorization

### A8. Submit
- [x] Click "Submit for Review" in ASC
- [x] Submit timestamp: 2026-05-01 (evening — exact time TBD, fill on approval email diff)
- [ ] Record approval timestamp: _______ (expected 2026-05-04 to 2026-05-08 based on 1.0.3 history)
- [ ] Record release timestamp (when "Release Now" clicked): _______

---

## Section B — Items NOT blocking 1.0.4 submission (parallel work)

These are deliberately deferred. They can happen during or after Apple review.

### Custom Product Pages (CPPs) — task #9
CPPs are independent of the version submission. They are their own mini-review (~24–48h each) and exist as alternate product pages accessible via unique URLs, targeted at specific traffic sources (TikTok, editorial, parenting communities).

**Timeline to have CPPs live on 1.0.4 release day:**
- 2026-04-21 → 2026-04-23: Draft 5 CPP content briefs (task #9) — DONE per `CPP_CONTENT_BRIEFS.md`
- TBD: Create CPPs in ASC; submit for review (~24–48h mini-review each, can run in parallel with binary review)
- Goal: CPPs approved before 1.0.4 release click, so attribution stack is live on Day 1

Not a submit blocker, but a parallel track to execute during the 1.0.4 review wait.

### Subscription group consolidation
MEMORY flags this as "CRITICAL PENDING: 3 separate groups (Solo/Individual/Family) must be consolidated into 1 'Brain Coinz' group before production launch." 1.0.3 shipped without it, so it is not a hard blocker for 1.0.4 either. Deferring to 1.0.5 unless there is a specific reason to bundle it now. If you decide to do it for 1.0.4, flag immediately — it affects StoreKit product IDs and ASC pricing structure, and would need a separate review cycle of its own.

### Content/community work (tasks #12–#15)
TikTok batch, Apple editorial pitch, Indie App Santa, parenting communities — all happen after 1.0.4 is live. Not submit blockers.

---

## Section C — Pre-release state snapshot (SUPERSEDED)

Originally scoped as "Day −1 prep on Apr 30 evening" before the May 1 scheduled release. Submission slipped to May 1, so this section is no longer needed as a separate step — the snapshot is now folded into Section D and run while 1.0.4 is awaiting review.

---

## Section D — 1.0.3 reference read (Day 16+ of 1.0.3, run BEFORE 1.0.4 release click)

**When to run:** TODAY (2026-05-02) or any day before Apple approves and we click "Release Now" on 1.0.4. Do NOT run after the flip — this read measures the 1.0.3 metadata package on its own merits, and any post-flip data is contaminated by 1.0.4 metadata cascade.

The read is now Day 16+ of 1.0.3(1) (was planned as Day 14), but the additional 2-day window does not change the diagnostic value — keyword ranks at Day 14 vs Day 16 differ by noise, not signal.

### D1. Astro keyword ranks
- [ ] Run `mcp__astro__get_app_keywords(appId: "6753270211", store: "us")`
- [ ] Save raw JSON response to `Marketing-Strategy/ASO/evidence/<YYYY-MM-DD>_astro_us.json` (use the actual run date)
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
  - **NO** (default expectation) → 1.0.4 ships as drafted. **Click "Release This Version" in ASC the moment Apple approves.**
  - **YES** → hold release on 1.0.4, edit metadata to rollback payload (restore 1.0.2 Name/Subtitle) — NOTE: editing metadata on an in-review build forces resubmission and a new ~24–72h review cycle. Decide if rollback urgency justifies the extra week.

### D5. ASC Analytics funnel (14-day window ending the day before this read)

> ⚠️ **Tooling blocker (2026-05-02):** the local patched `appstore-connect-mcp-patched` does NOT expose a `list_analytics_report_requests` endpoint. App's analytics report request already exists (server returns "You already have such an entity" on `create_analytics_report_request`), but the MCP can't retrieve its ID to call `list_analytics_reports`. Two unblock paths:
>   1. **Manual ASC web capture** (5 min) — log in → Analytics → Sources → App Store Search → set 14d window → screenshot + export CSV.
>   2. **Patch the MCP** — add a list-analytics-report-requests handler in `~/.local/lib/appstore-connect-mcp-patched/src/handlers/analytics.ts` (calls `GET /v1/apps/{appId}/analyticsReportRequests`), rebuild, restart MCP. Permanent fix.
>
> Until one is done, fill the fields below manually.

- [ ] Filter Analytics → Acquisition → Source Type = App Store Search, Territory = US.
- [ ] Impressions: _______
- [ ] Product Page Views: _______
- [ ] Impression → PPV CVR: _______%
- [ ] Total Downloads: _______
- [ ] PPV → Download CVR: _______%
- [ ] Impression → Download CVR (overall): _______%
- [ ] Also pull Source Type = App Store Browse — Impressions: _______ / Downloads: _______
- [ ] Export CSV to `Marketing-Strategy/ASO/evidence/<YYYY-MM-DD>_asc_analytics.csv`

### D6. Rating + review velocity
- [ ] Current rating count (US): _______
- [ ] Current average stars: _______
- [ ] New reviews since 2026-04-17: _______
- [ ] Star distribution of new reviews: _______

### D7. Archive 1.0.3 read
- [ ] Append findings to `BASELINE_METRICS.md` as "1.0.3 Day 14 read — 2026-05-01".
- [ ] Record in this checklist above.

---

## Section E — 1.0.4 Day 14 re-read (LIVE-date + 14 days)

**When to run:** 14 calendar days after 1.0.4 actually goes live (= the day "Release This Version" was clicked in ASC, NOT submit date or approval date). Fill the live-date the moment the release click happens; the Day-14 read date is `<live-date> + 14`.

| Milestone | Target/actual date |
|---|---|
| Submit | 2026-05-01 ✅ |
| Approval | TBD — fill on Apple email |
| Release click | TBD — fill same day approval lands |
| Day 14 re-read | live-date + 14 days |
| Day 21 re-read | live-date + 21 days |

Execute the D1–D6 protocol against the 1.0.4 live state.

### E1. Success criteria for 1.0.4
Tighter than 1.0.3 because of stacked improvements (new Name anchors + EN_US locale + Apr 28 KW swap into reward-chart niche).

**Primary — anchored to AS-SUBMITTED 1.0.4 token pool (Name + Subtitle + EN_US KW):**

Parental-control SERP (Name-driven):
- [ ] `parental control app` (Pop 57, Diff 65) → top 300 — Name anchor
- [ ] `parental control` (Pop 41, Diff 65) → top 200
- [ ] `parental controls` (Pop 32, Diff 67) → top 200 (stem)
- [ ] `parent control` (Pop 32, Diff 64) → top 200

Subtitle-driven (`Limit screen time, reward kids`):
- [ ] `limit screen time` (Pop 23, Diff 55) → top 100
- [ ] `screen time limit` (Pop 11, Diff 55) → top 150
- [ ] `reward kids` (Pop 5, Diff 17) → top 50 — lowest-Diff parent target found
- [ ] `kids reward` / `kids rewards` (Pop 5, Diff 39) → top 50

Reward-chart niche (Apr 28 KW swap, untouched by competitor cohort):
- [ ] `reward chart` (Pop 8, Diff 19) → top 25 — easiest open-runway win
- [ ] `behavior chart` (untracked) → enter rank
- [ ] `kids tasks` (Pop 5, Diff 46) → top 100
- [ ] `screen time tasks` (Pop 5, Diff 50) → top 100
- [ ] `reward tasks` (Pop 5, Diff 45) → top 100
- [ ] `family screen time` (Pop 5, Diff 65) → top 100
- [ ] `screen time kids` (Pop 5, Diff 70) → top 50

Held from 1.0.3:
- [ ] `brainrot` (Pop 55, Diff 48) → top 300
- [ ] `parenting` (Pop 23, Diff 57) → top 200
- [ ] `positive reinforcement` (Pop 5, Diff 41) → top 50
- [ ] `positive parenting` (Pop 5, Diff 37) → top 50
- [ ] `earn screen time` (Pop 9, Diff 40) — defend #93 vs Thrive #91
- [ ] Hold all 1.0.3 wins (no regression > 50 positions)

**Regression watch (tokens dropped on Apr 28):**
- [ ] `motivate` (was Pop 19) — expected to fall, not a concern
- [ ] `educational` (Pop 27) — expected to fall, not a concern
- [ ] `reduce screen time`, `time limit`, `screen limit` — expected to fall, were LEAK-classified anyway

**Rollback trigger (1.0.5 decision):**
- [ ] `brain coinz` rank drops below 200 (was 33 at 1.0.3 baseline)
- [ ] Net new-ranked keyword count < 5 from the Tier-A list above
- [ ] Either → plan 1.0.5 with prior-metadata restored

---

## Section F — 1.0.4 Day 21 re-read (LIVE-date + 21 days)

Lighter pass. Same queries, trajectory focus.

- [ ] Re-run D1 (Astro) and D5 (ASC Analytics) — save to `evidence/<YYYY-MM-DD>_*`.
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
