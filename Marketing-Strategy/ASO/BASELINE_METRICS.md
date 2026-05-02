# Brain Coinz — ASO Baseline Metrics

**Snapshot Date:** 2026-04-14
**App:** Brain Coinz (appId 6753270211)
**Store:** US
**Platform:** iPhone
**Live version:** 1.0.2(26)

## Purpose

Baseline keyword ranks captured BEFORE deploying the positioning-first metadata rewrite alongside the 1.0.3(1) resubmission. Re-run the same query at 14 and 21 days post-approval to measure lift.

## Headline

- **45 of 46 tracked keywords are unranked (rank 1000).**
- Only `brain coinz` ranks (#33), down from #29 (-4) — own-brand erosion.
- All category terms (`parental control`, `screen time`, `app blocker`, `chore chart`, `homework tracker`, `study timer`, etc.) are invisible.

This means any meaningful movement after redeploy is measurable lift. The bar is low.

## Live Metadata at Baseline

- **Name:** Brain Coinz (11/30)
- **Subtitle:** Earn Play Time by Learning (26/30)
- **Keywords:** `brain coinz,learning rewards,educational motivation,earn to play,kids motivation,kids productivity` (98/100)
- **Promo text:** "End screen time battles with a system kids actually want to use. Earn rewards through learning, unlock apps automatically. Try free for 14 days." (158/170)
- **Rating:** 0 reviews

## All 46 Tracked Keywords (sorted by popularity, desc)

| Keyword | Popularity | Difficulty | Rank | Apps |
|---|---|---|---|---|
| parental control app | 57 | 65 | 1000 | 223 |
| app lock | 55 | 63 | 1000 | 215 |
| learning | 54 | 80 | 1000 | 231 |
| screen time | 52 | 63 | 1000 | 237 |
| app blocker | 50 | 60 | 1000 | 234 |
| control parental | 44 | 60 | 1000 | 232 |
| study timer | 42 | 62 | 1000 | 243 |
| parental control | 41 | 65 | 1000 | 226 |
| play time | 40 | 65 | 1000 | 206 |
| study app | 39 | 76 | 1000 | 242 |
| homework tracker | 34 | 53 | 1000 | 225 |
| parent app | 33 | 63 | 1000 | 235 |
| chore chart | 29 | 52 | 1000 | 222 |
| limit screen time | 23 | 55 | 1000 | 243 |
| filter apps | 23 | 78 | 1000 | 223 |
| dopamine detox | 20 | 49 | 1000 | 232 |
| kids app | 17 | 86 | 1000 | 226 |
| kids chores | 13 | 57 | 1000 | 225 |
| block apps | 9 | 63 | 1000 | 240 |
| lock apps | 9 | 59 | 1000 | 226 |
| focus app | 9 | 60 | 1000 | 238 |
| screentime | 8 | 57 | 1000 | 238 |
| reward chart | 8 | 23 | 1000 | 202 |
| screen time app | 7 | 64 | 1000 | 245 |
| reduce screen time | 7 | 57 | 1000 | 238 |
| brain coinz | 5 | 60 | **33** (was 29, −4) | 229 |
| earn screen time | 5 | 45 | 1000 | 238 |
| ipad parental controls | 5 | 66 | 1000 | 220 |
| screen time rewards | 5 | 57 | 1000 | 231 |
| screen time limit | 5 | 58 | 1000 | 241 |
| limit apps | 5 | 65 | 1000 | 229 |
| track screen time | 5 | 57 | 1000 | 232 |
| kids rewards | 5 | 47 | 1000 | 224 |
| lock ipad | 5 | 62 | 1000 | 220 |
| child block | 5 | 63 | 1000 | 209 |
| safe kids | 5 | 58 | 1000 | 201 |
| kid mode | 5 | 61 | 1000 | 228 |
| adhd timer | 5 | 65 | 1000 | 244 |
| allowance app | 5 | 55 | 1000 | 215 |
| block youtube | 5 | 63 | 1000 | 216 |
| limit games | 5 | 79 | 1000 | 245 |
| learn to earn | 5 | 59 | 1000 | 207 |
| learning reward | 5 | 67 | 1000 | 226 |
| kids screentime | 5 | 62 | 1000 | 206 |
| earn play time | 5 | 65 | 1000 | 137 |
| by learning | 5 | 64 | 1000 | 242 |

## Success Criteria (re-check at day 14 and day 21)

> **2026-04-18 revision (audit correction):** Previous primary list included `chore chart`, `homework tracker`, `study timer`, `reward chart` — all of which `ASO_EXECUTION_PLAN.md` §"Dropped from earlier drafts" explicitly removed as feature-mismatches. Those tokens are in NO field and will never rank; measuring against them guaranteed false failure. Primary list below is now aligned with the tokens actually deployed in 1.0.3(1).

**Primary win conditions** (aligned with deployed 1.0.3(1) metadata):
- `earn screen time` (Pop 5, Diff 45) → from 1000 into top 50 — core name phrase
- `reward kids` (Pop 5, Diff **21** — lowest Diff in set) → from 1000 into top 100 — subtitle core
- `positive reinforcement` (Pop 5, Diff **39**) → from 1000 into top 100 — keyword-field combo
- `motivate kids` (Pop 5, Diff 44) → from 1000 into top 150
- `limit screen time` (Pop **23**, Diff 55) → from 1000 into top 200
- `brain coinz` holds or improves from rank 33

**Secondary:**
- `play time` (Pop 40, Diff 65) → entering top 300 — requires ES_MX slot to be deployed (see audit note)
- `reduce screen time`, `screen time limit`, `kids rewards`, `screen time rewards`, `earn play time` all indexing at any rank < 1000

**Rollback trigger:**
- If `brain coinz` rank drops below 150 AND no tracked keyword replaces it by day 21 → revert to baseline live metadata

**Audit note (2026-04-18):** The ES_MX keyword field documented in `ASO_EXECUTION_PLAN.md` §4 (`app,blocker,lock,play,time,...`) was drafted but **never deployed**. Keywords that require the ES_MX slot (`app blocker` Pop 50, `app lock` Pop 55, `play time` Pop 40, `parent app` Pop 33) cannot be expected to move at Day 14/21 unless that slot is deployed as a metadata-only update first.

## How to Re-run

```
mcp__astro__get_app_keywords(appId: "6753270211", store: "us")
```

Diff the `currentRanking` column against this snapshot at day 14 and day 21.

---

## 2026-04-19 Pop>5 / Diff<60 Watchlist Additions

Added 14 candidate keywords to Astro tracking; 9 survived the **Pop > 5 AND Diff < 60** filter and are tagged `pop>5-diff<60-watchlist` (green). Dropped from tracking in spirit (kept registered, but excluded from priority): `app timer` (Diff 68), `time app` (Diff 73), `chore app` (Diff 72), `chores` (Diff 68), `rewards` (Diff 84).

**Subsequently added (same session):** `screen time limit` (Pop 11 / Diff 55) — qualifies, tagged. 4th indexing-pipeline canary (all three tokens already in deployed metadata).

### Survivors at baseline (all rank 1000)

| Keyword | Pop | Diff | Token coverage in deployed 1.0.3(1) | Day 14 hypothesis |
|---|---|---|---|---|
| brainrot | 55 | 48 | ❌ `brainrot` missing | Stay 1000 — needs ES_MX add |
| claim app | 59 | 50 | ⚠️ `app` covered, `claim` missing | Stay 1000 — investigate intent before adding `claim` |
| parenting | 23 | 57 | ❌ `parenting` missing | Stay 1000 — needs ES_MX add |
| time control | 20 | 48 | ⚠️ `time` ✓, `control` missing | Stay 1000 — needs ES_MX add |
| screen blocker | 13 | 52 | ⚠️ `screen` ✓, `blocker` missing | Stay 1000 — needs ES_MX add |
| points | 9 | 58 | ❌ `points` missing | Stay 1000 — needs ES_MX add |
| **time limit** | 7 | 55 | ✅ `time` (name) + `limit` (KW field) | **Should index** — if 1000 by 2026-05-01, indexing pipeline broken. OurPact ranks #12 here. |
| **app limit** | 7 | 55 | ✅ `app` (subtitle stem) + `limit` (KW) | **Should index** by Day 14 |
| **screen limit** | 6 | 56 | ✅ `screen` (name) + `limit` (KW) | **Should index** by Day 14 |
| **screen time limit** | 11 | 55 | ✅ `screen` + `time` (name) + `limit` (KW) | **Should index** by Day 14 |

### Action implications

- **Day 14 (2026-05-01) verification:** `time limit`, `app limit`, `screen limit` are the indexing-pipeline canaries. If they're still 1000 with all-token coverage, something is wrong with the deploy or the screenshot OCR is overriding signal.
- **6 partial/missing tokens flagged for ES_MX deploy:** `brainrot`, `claim`, `parenting`, `control`, `blocker`, `points`. None of these are in the drafted ES_MX field per `ASO_EXECUTION_PLAN.md` §4 — that draft predates this session. When ES_MX is finally deployed, expand the draft to include these 6 tokens (or the highest-fit subset; `claim` carries crypto/refund-traffic risk worth gating).
- All 9 carry an Astro keyword note explaining the rationale and Day 14 target.

### How to re-pull this watchlist

```
mcp__astro__get_app_keywords(appId: "6753270211", store: "us")
```

Filter the result to entries where the `tag` is `pop>5-diff<60-watchlist` (or equivalently, where Pop > 5 AND Diff < 60).

---

## 2026-05-02 — 1.0.3 Day-16 Reference Read (Section D of MAY_1_MEASUREMENT_CHECKLIST.md)

**Captured:** 2026-05-02 (planned for May 1; submission slipped, captured Day 16 instead of Day 14)
**Live version at capture:** 1.0.3 (1) — live since 2026-04-17 (15 days live)
**Why captured now:** 1.0.4 (build 7) is in Apple review (submitted 2026-05-01) but has NOT been released. This is the last clean read of 1.0.3 metadata in isolation. After 1.0.4 release click, the read window closes forever.
**Raw evidence:** `evidence/2026-05-02_astro_us.json`

### Headline

- **2 of 38 tracked keywords ranked.** 36 unranked (1000).
- `brain coinz`: rank **1** (was #33 at baseline 2026-04-14, hit #1 sustained from 2026-04-22 onward). +32 positions vs baseline. ✅
- `earn play time`: rank **135** (was 1000 at baseline; first entered top-1000 on 2026-04-22 at #134). New indexing. ✅
- All other 36 keywords still 1000 — including 4 of 4 indexing-pipeline canaries that should have indexed by Day 14.

### Brain Coinz rank trajectory (own-brand)

| Date | Rank | Note |
|---|---|---|
| 2026-04-13 | 29 | Pre-1.0.3 baseline |
| 2026-04-14 | 33 | Baseline doc captured |
| 2026-04-17 | 5 | 1.0.3 (1) approved + live |
| 2026-04-18 | 5 | |
| 2026-04-19 | 12 | |
| 2026-04-20 | 4 | |
| 2026-04-21 | 13 | |
| 2026-04-22 → 2026-05-02 | **1** (sustained 11 days) | Own-brand consolidated |

### `earn play time` trajectory (only non-brand keyword to enter top-1000)

| Date | Rank | Note |
|---|---|---|
| 2026-04-17 | 1000 | 1.0.3 live |
| 2026-04-18 → 04-21 | 1000 | Indexing not yet active |
| 2026-04-22 | 134 | First-ever rank — entered top-1000 at Day 5 post-1.0.3 |
| 2026-04-23 → 05-01 | 133–142 | Stable band |
| 2026-05-02 | **135** | +7 vs prev day (142 → 135) |

### Indexing-pipeline canaries — diagnostic

The 4 canaries from the Apr 19 watchlist (Pop>5, Diff<60, ALL tokens covered by deployed 1.0.3 metadata) are ALL still rank 1000 at Day 16:

| Canary | Pop | Diff | Token coverage | Rank | Verdict |
|---|---|---|---|---|---|
| `time limit` | 9 | 58 | `time` (Name) + `limit` (KW) | 1000 | ❌ FAIL — should rank |
| `screen limit` | 6 | 56 | `screen` (Name) + `limit` (KW) | 1000 | ❌ FAIL |
| `app limit` | 7 | 51 | `app` (Subtitle stem) + `limit` (KW) | 1000 | ❌ FAIL |
| `screen time limit` | 11 | 51 | `screen` + `time` (Name) + `limit` (KW) | 1000 | ❌ FAIL |

**Result: 4-of-4 canary failure** at Day 16 — beyond the Day-14 deadline these were set against.

### Path classification (Section D4 of MAY_1_MEASUREMENT_CHECKLIST.md)

→ **PATH 3 — Broken canaries / locale-routing failure.**

The Apr 18 BASELINE_METRICS audit anticipated this: Brain Coinz primary language = English (Canada). The 1.0.3 KW string sits in the EN_CA slot. US App Store searchers receive that metadata only via primary-fallback, and the 4-of-4 canary failure indicates that fallback is NOT routing US queries to the EN_CA pool reliably (or only partially — `earn play time` did route).

### Action

**Per Section D4 Path 3:** "1.0.4 literally fixes this by adding a dedicated EN_US locale → release 1.0.4 on approval."

→ **Ship 1.0.4 (build 7) the moment Apple approves. No metadata changes. No rollback.**

### Implications for 1.0.4 Day-14 measurement (Section E)

The unranked-canary baseline gives 1.0.4 enormous headroom. If the EN_US locale fix works, expect:
- 4 indexing canaries to enter top-200 within 7–14 days post-live
- Reward-chart niche tokens (added in May-1 KW swap) to enter from cold
- `parental control` SERP (Name-driven) to enter top-300
- `brain coinz` to hold #1 (low risk — already saturated)

If the canaries STILL fail after 1.0.4 ships with EN_US locale → indexing pipeline is broken at the Apple side, not metadata. Escalate to Apple Developer Support.

### CSV row for trend-tracking

```
date,version,days_live,brain_coinz_rank,earn_play_time_rank,canaries_indexed_of_4,total_ranked_of_tracked
2026-04-14,1.0.2(26),pre,33,1000,0/4,1/46
2026-05-02,1.0.3(1),15,1,135,0/4,2/38
```

(Will append 1.0.4 rows at live+14 and live+21.)
