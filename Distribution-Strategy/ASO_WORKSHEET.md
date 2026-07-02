# ASO Worksheet — Current State & Astro Workshop Agenda

**Status**: PENDING — no metadata changes until the Astro MCP keyword workshop
(desktop session). This file records the audit and the questions to answer with data.

---

## Current metadata (as of July 2, 2026)

| Field | Value |
|---|---|
| Title | `Parental Control App: Tic-Lock` |
| Subtitle | `Kids Lock App, Learning, Games` |
| Keyword field | `child,safe,kit,parental,control,kids,mode,chore,chart,lock,app,games,family,homework,screen,time` |
| Storefronts | US, CA, UK, AU, MX |
| Known ranks | "parental control app": 30 (was 96 before title restructure) |

**Decision already made (respect it)**: title leads with "parental control app"
deliberately, based on Astro keyword research, and the rank jump validates it.
Do not relitigate without new data.

---

## Audit finding 1: ~43 duplicated keyword-field characters — CONDITIONAL

For **ranking**, Apple indexes title + subtitle + keyword field as one pool; repeating a
word adds no weight. However, the duplicates here are deliberate: they exist so Custom
Product Pages can be assigned to title-phrase searches ("parental control app"), because
CPP search keywords are selectable **only from the keyword field** (no free-text entry).

**Unresolved question**: ASO sources (Phiture, AppTweak, Yodel) report that title/subtitle
phrases are *ignored* by the CPP keyword system even when duplicated into the field. If
true, the duplication buys nothing on either front.

**Verification status (July 2, 2026 — evidence favors KEEPING the duplicates)**:
Sample day: 23 unique impressions, 19 attributed to CPPs, 4 to the default page. With no
ads running, CPP impressions can only come from organic searches on assigned keywords —
so CPP keyword routing is demonstrably firing. Per-CPP breakdown is hidden until a CPP
reaches ~5 downloads, so which assignments fire is not yet confirmed.

**To disambiguate (no metadata risk):**
1. By construction — each keyword combo maps to exactly one CPP; if all assigned keywords
   are title-duplicated terms, the 19 impressions are already proof.
2. Rotation test — unassign all CPPs except the title-phrase one for a week (~150
   impressions of signal at current traffic); if CPP-attributed share holds ~80%, the
   title-term assignment works. Reassign afterward.

**Decision**: keep duplicates until the rotation test says otherwise.

Duplicates in the keyword field:

| Duplicate | Already in | Chars wasted (incl. comma) |
|---|---|---|
| `parental` | title | 9 |
| `control` | title | 8 |
| `app` | title & subtitle | 4 |
| `lock` | title & subtitle | 5 |
| `kids` | subtitle | 5 |
| `games` | subtitle | 6 |
| **Total** | | **~37–43** |

Unique terms actually working today: `child, safe, kit, mode, chore, chart, family,
homework, screen, time` (~56 chars).

## Audit finding 2: subtitle self-duplication

`Kids Lock App, Learning, Games` — `lock` and `app` are already indexed from the title,
so they buy no new indexing (they may still aid phrase perception/conversion; judgment
call for the workshop). Net-new indexed words from the subtitle: `kids`, `learning`,
`games`.

## Audit finding 3: `kit` looks like an outlier

Verify in Astro what combination it was targeting (e.g., "child safe kit"). If it has no
volume, it's 4 reclaimable characters.

---

## Candidate replacement terms (validate volume/difficulty in Astro)

Mechanic terms (differentiator): `earn`, `reward`, `points`, `allowance`, `unlock`
Category long-tail: `limit`, `timer`, `blocker`, `monitor`, `tracker`, `downtime`
Education intent: `study`, `reading`, `math`, `education`, `learn` (check stemming vs
subtitle's `Learning`)
Behavior/routine: `routine`, `focus`, `habit`, `bedtime`

Combination logic reminder: Apple matches across the pool, so `earn` + existing
`screen,time` covers "earn screen time"; `reward` + `chart` covers "reward chart";
`kids` + `timer` covers "kids timer", etc. Prioritize words that create the most
valuable *new combinations*, not just solo volume.

---

## Localization plan (free indexing multipliers)

| Locale | Effect | Effort |
|---|---|---|
| es-MX | Second keyword field indexed for the **US** storefront + covers MX | Translate metadata only (~1 h with care) |
| en-GB | Covers UK; separate keyword field | Copy-adjust |
| en-AU | Covers AU | Copy-adjust |
| en-CA | Covers CA | Copy-adjust |

Each locale gets its own 30-char title/subtitle + 100-char keyword field — do NOT mirror
the US field; use it for terms that didn't fit.

---

## CPP keyword mechanics (reference)

- CPP search keywords: select-only from the 100-char keyword field of the latest approved
  version; ASC errors on terms not in the field
- Each unique keyword combination can map to only one CPP
- CPP is searchable only once approved and set to visible
- At low volume, CPP analytics are sparse (privacy thresholds) — don't spend indexing
  characters on measurement before there's traffic to measure
- Native fit: CPPs for keyword-field terms (e.g., an "earn screen time" CPP whose
  screenshots lead with the reward mechanic), not for title terms

---

## Conversion finding: the page leaks harder than the traffic lacks

Baseline (July 2026): ~23 unique impressions/day ≈ 700/month, vs ~12 lifetime downloads.
At the category-typical 3–5% impression→download rate, this traffic should produce
~20–30 downloads/month. It doesn't — the product page itself is the leak (no rating
stars below 11 ratings; screenshot story doesn't sell the mechanic). Screenshot narrative
+ ratings prompt are therefore the highest-yield items in the whole plan: they multiply
traffic that already exists, before any ad spend.

---

## Workshop agenda (desktop session with Astro MCP)

0. Review CPP disambiguation (finding 1): map current keyword→CPP assignments; run the
   rotation test if ambiguous. Default: duplicates stay.
1. Pull volume/difficulty/current-rank for every current + candidate term
2. Decide final 100-char US keyword field (informed by the CPP test; choose replacements)
3. Subtitle decision: keep `Kids Lock App, Learning, Games` vs. reclaim `lock`/`app`
   chars for mechanic terms — measure risk to current ranks first
4. Fill es-MX + en-GB/AU/CA fields
5. Set up rank tracking list for the weekly ASO block
6. Screenshot narrative review (first 3 frames = the earn mechanic story)
