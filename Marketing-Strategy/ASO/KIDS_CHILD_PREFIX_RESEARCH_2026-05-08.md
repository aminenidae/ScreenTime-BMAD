# "Kids" / "Child" Prefix Keyword Research — 2026-05-08

**Goal.** Map the 2- and 3-token search universe for "kids ___" and "child ___" prefixed queries. Test the hypothesis that the audience descriptor is itself a high-volume search root for parental-control software.

**Method.** Tested 105 candidates on Astro (`add_keywords` against Brain Coinz, US store) split into 4 batches: 27 × 2-token "kids", 26 × 3-token "kids", 27 × 2-token "child", 25 × 3-token "child". Survivor filter: **Pop ≥ 6 AND Diff ≤ 70**. Cross-referenced surviving terms against `1.0.4_KEYWORD_DISCOVERY_2026-04-27.md` SERP intent audit.

**Outcome.** Hypothesis falsified. The "kids ___" / "child ___" 2-token search root is largely floor-volume (Pop 5). Survivors with both real demand AND genuine parent-target intent: zero new finds beyond what the locked 1.0.4 plan already indexes for via `kids` + Subtitle stems.

---

## Survivor table (filter: Pop ≥ 6, Diff ≤ 70)

| Keyword | Pop | Diff | Apr-27 Intent | Verdict |
|---|---|---|---|---|
| `kids phone` | 15 | 58 | **1/20 PARENT** (toddler-toy phone games) | ❌ LEAK — do not pursue |
| `kids chores` | 13 | 57 | (already tracked, positive-parenting niche fit) | ✅ already in scope |
| `child lock app` | 15 | 58 | 12/20 PARENT — borderline (app-locker noise) | 🟡 already tracked |
| `kids timer` | 7 | 45 | not yet classified | 🟡 needs SERP check |
| `child friendly` | 7 | 48 | not yet classified | 🟡 weak strategic fit (generic safe-app discovery, not parental-control) |

**Net new actionable finds from this exercise: 0.** Pop/Diff alone surfaced `kids phone` as the strongest 2-token candidate, but the Apr 27 intent audit had already classified it as a LEAK (19/20 toddler-phone-toy games dominate the SERP). My initial in-session recommendation was corrected by re-reading the existing audit.

---

## Floor-volume cohort (51 of 52 "child ___" + 49 of 53 "kids ___" = 100/105 at Pop 5)

The Pop 5 floor swept across both prefixes uniformly. Notable low-difficulty Pop=5 results that nevertheless have nothing to win:

| Keyword | Pop | Diff |
|---|---|---|
| `child reward` | 5 | **15** |
| `child reward system` | 5 | **15** |
| `kids habits` | 5 | **19** |
| `child habits` | 5 | **19** |
| `child safety` | 5 | **19** |
| `kids rewards` | 5 | 40 |
| `kids reward` | 5 | 45 |

`kids rewards` / `kids reward` are confirmed 19/20 PARENT in the Apr 27 audit and **are already in the locked 1.0.4 plan** via the proposed `+kids,+family,+reward,+chart,+behavior,+chore` swap. Pop 5 is acceptable there because the leverage comes from 3-token combos (`screen time kids`, `kids screen time`) where `screen` and `time` are already in the Subtitle.

The remaining low-Diff Pop=5 terms have no parallel leverage path — they'd index for one Pop=5 query and that's it.

---

## Why the prefix is dead air

Across 105 tests, only 4 keywords cleared the Pop≥6 / Diff≤70 filter, and 0 survived once intent was checked. The pattern is consistent with the Apr 27 finding:

> Parents searching the App Store for parental-control software almost universally drop the audience qualifier. They search by *function* — `parental control` (Pop 40), `screen time` (Pop 51), `app blocker` (Pop 50), `parent app` (Pop 33) — at 4–10× the volume of any "kids/child ___" 2-token term.

The exception is when the audience descriptor combines with a function token: `screen time kids` (Pop 5, 16/20 PARENT, Diff 70 — 5 direct competitors there) and `kids screen time` (Pop 5, Diff 68). These are already on the locked 1.0.4 plan via the `kids` keyword token + Subtitle's `screen`/`time`.

**Implication for metadata.** No edit suggested. The `+kids` token in the locked Apr-20 plan is doing the right work — unlocking 3-token PARENT-intent combos, not standalone 2-token "kids ___" queries. Adding the `child` token specifically would unlock `child friendly` (Pop 7, weak fit) and reinforce `child lock app` (already tracked, 12/20 PARENT borderline) — not enough leverage to justify displacing function tokens like `blocker`, `control`, `points`, `parenting` already on the plan.

---

## Astro hygiene

51 of 52 "child ___" results came back at Pop 5. Recommend bulk-delete in the Astro UI to keep the tracked-keyword view focused on indexable signal. (No delete tool is exposed via the Astro MCP.)

The "kids ___" floor results were already cleaned up manually during Batch 1 review on 2026-05-07.

---

## Cross-references

- `1.0.4_KEYWORD_DISCOVERY_2026-04-27.md` — Apr 27 intent audit; primary source for the SERP-PARENT classifications cited above
- `1.0.4_INTENT_AUDIT_2026-04-27.md` — same-day rubric definition (≥12/20 PARENT = FIT, 6–11 = MIXED, ≤5 = LEAK)
- `1.0.4_METADATA_DRAFT.md` — locked deployment plan including the `+kids,+family,+reward,+chart,+behavior,+chore` swap that captures the only "kids" leverage worth having
- `ASTRO_COMPETITOR_INTELLIGENCE.md` — Genie/ScreenTreat/Pezo/TimeBank/Thrive cohort that already ranks #10–#22 on `screen time kids` / `kids screen time` (the actual high-leverage terms)
