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

**Primary win conditions:**
- `earn screen time` (Pop 5, Diff 45) → from 1000 into top 50
- `chore chart` (Pop 29, Diff 52) → from 1000 into top 200
- `homework tracker` (Pop 34, Diff 53) → from 1000 into top 200
- `study timer` (Pop 42, Diff 62) → from 1000 into top 300
- `reward chart` (Pop 8, Diff **23**) → from 1000 into top 100 (lowest-difficulty target)
- `brain coinz` holds or improves from rank 33

**Secondary:**
- `screen time rewards`, `kids rewards`, `learn to earn`, `earn play time` all indexing at any rank < 1000 (currently unranked)
- `play time` (Pop 40) entering top 300

**Rollback trigger:**
- If `brain coinz` rank drops below 150 AND no tracked keyword replaces it by day 21 → revert to baseline live metadata

## How to Re-run

```
mcp__astro__get_app_keywords(appId: "6753270211", store: "us")
```

Diff the `currentRanking` column against this snapshot at day 14 and day 21.
