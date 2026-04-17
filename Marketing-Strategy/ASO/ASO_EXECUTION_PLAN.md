# Brain Coinz — ASO Execution Plan (1.0.3(1) Resubmission)

**Status:** ✅ Deployed 2026-04-17 — live in production. Awaiting Day 14 (2026-05-01) and Day 21 (2026-05-08) rank re-measures against `BASELINE_METRICS.md`.
**Target version:** 1.0.3(1) (replaces live 1.0.2(26))
**Snapshot date:** 2026-04-14 (metadata drafted); **deploy date:** 2026-04-17
**Positioning thesis:** Brain Coinz is the **kid version of Unrot/Unglue** — automated learn-to-earn screen time. NOT a parental-controls, chore-chart, or study-timer app.

Related files:
- `BASELINE_METRICS.md` — pre-deploy Astro ranks (re-check at day 14 and 21)
- `ASTRO_COMPETITOR_INTELLIGENCE.md` — Pop/Diff context + competitor landscape
- `APPFIGURES_ASO_INSIGHTS.md` — algorithm mechanics (OCR screenshots, 10x localization trick)

---

## Why Positioning-First

Astro data confirms two traps and one whitespace:

| Search | Top-15 incumbents | Reviews | Fit for Brain Coinz |
|---|---|---|---|
| `parental controls` | Bark, FamilyLink, Kidslox, OurPact, Qustodio, mSpy, AT&T | 8K–272K | ❌ All GPS/monitoring; intent mismatch → 1-star reviews |
| `chore chart` | Manual-task sticker/allowance apps | — | ❌ App isn't a chore tracker |
| `earn screen time` | Unrot, ScreenZen, BePresent (adult self-control) | 29K–43K | ⚠️ Adult apps, but only 1 kid-focused peer (ScreenEarn, 4 reviews) → **whitespace** |

Positioning-first means: pick keywords that match what the app actually does, even at lower volume. Feature-mismatched keywords pull in searchers whose expectations the app can't meet — and at 0 reviews those 1-stars compound fast.

---

## Final Metadata Package

### 1. App Name — 29/30

```
Brain Coinz: Earn Screen Time
```

Reclaims 18 chars vs the live `Brain Coinz` (11). Tokenizes `earn`, `screen`, `time` into the highest-weight ASO field. Directly captures the core positioning phrase.

### 2. Subtitle — 29/30

```
Reward Kids for Learning Apps
```

Tokens: `reward, kids, for, learning, apps`

Targets unlocked:
- `reward kids` — Pop 5 / Diff **21** ⭐ (lowest Diff in full 61-keyword tracked set)
- `kids rewards` — Pop 5 / Diff 47
- `learning` — Pop 54 / Diff 80 (aspirational)
- `educational app` — via `apps`
- `kids learning` — implicit phrase build

### 3. Keyword Field — US English (97/100)

```
motivate,positive,reinforcement,educational,limit,reduce,play,productivity,goal,game,daily,unlock
```

**No spaces after commas. Do not duplicate name or subtitle tokens.** Already covered by name + subtitle: `brain, coinz, earn, screen, time, reward, kids, for, learning, apps`.

Tokens and the positioning-fit keywords each unlocks:

| Token | Unlocks | Pop | Diff |
|---|---|---|---|
| `motivate` | motivate kids | 5 | 44 |
| `motivate` | educational motivation (live kw carryover) | — | — |
| `positive` + `reinforcement` | positive reinforcement | 5 | **39** ⭐ |
| `educational` | educational motivation, educational app, educational rewards | 5 | 75 (hard) |
| `limit` | limit screen time | **23** | 55 ⭐ |
| `limit` | screen time limit | 5 | 58 |
| `reduce` | reduce screen time | 7 | 57 |
| `play` | play time | **40** | 65 ⭐ |
| `play` | earn play time | 5 | 65 |
| `productivity` | kids productivity (live kw carryover) | — | — |
| `goal` | soft-fit adjacency for routine/learning goals | — | — |
| `game` | kids learning game, educational game | — | — |
| `daily` | daily rewards kids | — | — |
| `unlock` | unlock apps (mechanic) | — | — |

**Total winnable + positioning-fit targets: 12+.** Zero feature-mismatches.

**Carryover from current live keyword field:** `educational motivation`, `kids productivity`, `learning rewards` all continue to index via `educational`, `productivity`, plus `reward`+`learning` from the subtitle — minimizes rank-loss risk on own-brand and currently-indexing terms.

**Dropped from earlier drafts** (feature-fit audit, see Methodology Notes):
- `dopamine, detox` — pulls Opal/detox-program searchers; app doesn't run detox programs
- `habit, routine` — app isn't a habit tracker; no streaks, no daily routine structure
- `focus` — not a focus-timer/ADHD-focus tool
- `track` — pulls monitoring-parent intent, not learn-to-earn intent
- `app` — replaced by more specific `game`, `educational`

### 4. Keyword Field — Spanish (Mexico) (91/100)

```
app,blocker,lock,play,time,earn,learn,parent,kid,safe,mode,youtube,block,filter,browser,web
```

Uses the 10x-localization trick (Apple indexes MX locale keywords for US App Store; `APPFIGURES_ASO_INSIGHTS.md`). Apple does **NOT** merge tokens across locales, so high-Pop stretch-term pairs are co-located WITHIN MX.

Stretch targets (higher Pop, higher Diff — reachable via free 10x slot, not fightable in the 100-char EN_US budget):

| Pair | Keyword | Pop | Diff |
|---|---|---|---|
| app + blocker | app blocker | **50** | 60 |
| app + lock | app lock | **55** | 63 |
| play + time | play time | **40** | 65 |
| parent + app | parent app | **33** | 63 |
| filter + apps (via `app`) | filter apps | **23** | 78 |
| play + time + earn | earn play time | 5 | 65 |
| learn + earn | learn to earn | 5 | 59 |
| block + apps (via `app`) | block apps | 9 | 63 |
| lock + apps (via `app`) | lock apps | 9 | 59 |
| block + youtube | block youtube | 5 | 63 |
| safe + kid (stems to `kids`) | safe kids | 5 | 58 |
| kid + mode | kid mode | 5 | 61 |
| web + filter | web filter | — | — (not yet tracked) |
| safe + browser | safe browser | — | — (not yet tracked) |
| kid + browser | kids browser | — | — (not yet tracked) |

**Why the swap from earlier draft:** replaced `allowance,adhd,timer` (Pop 5 long-tails) with `filter,browser,web` (2026-04-14 feature audit). Brain Coinz has app blocking + browser blocking + adult-content filtering — these tokens honestly reflect the mechanic set and unlock the Pop **23** `filter apps` baseline keyword plus untracked `web filter` / `safe browser` / `kids browser` cluster. `parental,control` deliberately NOT added — top-50 review moat (7K–272K) blocks any realistic ranking, and ~48% of `parental control` searchers want GPS (1-star-review risk at 0 reviews).

**Rejected for this slot:** competitor-name conquest (`qustodio, bark, aura, life360, kidslox`). Rationale: 1.0.3(1) has a binary change → already one review-reject surface. Apple has tightened Guideline 2.3.7/2.3.10 enforcement on competitor references. Stage as a metadata-only update in a DIFFERENT locale (e.g., Spanish-ES or French) after 1.0.3(1) is approved.

### 5. Promotional Text — keep live, no change (158/170)

```
End screen time battles with a system kids actually want to use. Earn rewards through learning, unlock apps automatically. Try free for 14 days.
```

Emotional hook → mechanism → offer. No change needed; aligns with positioning.

### 6. Description

Starting point: current live description (already positioning-aligned). Apply these targeted edits before pasting into App Store Connect:

1. **DELETE** the line near the top: `"Full access requires a Brain Coinz subscription. A free trial is available."` — conversion killer above the fold, already repeated at the bottom.
2. **ADD** disambiguation sentence near the top: `"Brain Coinz controls iOS apps on your child's iPhone or iPad — not gaming consoles (Nintendo Switch, Xbox) or GPS location."` Addresses the `nintendo switch parental controls` Pop 59 intent-trap.
3. **MOVE** privacy claim up to the FIRST KEY FEATURES bullet: `"🔒 Privacy First: All usage data stays on-device. No ads. No data selling. Built on Apple's native frameworks."`
4. **CHANGE** `"iPad time"` → `"screen time"` in the opening sentence (broader device framing).

Final open-paragraph template:

> Stop fighting over screen time.
>
> Brain Coinz is an automated app blocker that turns screen time into a proven "Learn-to-Play" reward system. Brain Coinz controls iOS apps on your child's iPhone or iPad — not gaming consoles (Nintendo Switch, Xbox) or GPS location. The app automatically tracks the time your child spends on educational apps and instantly unlocks their entertainment apps. No manual tracking, no arguments.
>
> **How does this app blocker work?**
> A parent creates a simple rule: "30 minutes of Khan Academy unlocks 60 minutes of YouTube." That's it. Brain Coinz monitors educational app usage natively. The instant the timer hits the goal, reward apps are unlocked. When earned time runs out, the apps lock again.
>
> **Why is this different from existing parental controls?**
> Unlike legacy timers that rely on punishing restrictions, Brain Coinz motivates kids to *want* to learn through positive reinforcement. Unlike chore apps that require parent approval, Brain Coinz is fully automated.
>
> **What are the key features?**
> * 🔒 **Privacy First:** All usage data stays on-device. No ads. No data selling. Built on Apple's native frameworks.
> * 🤖 **Automated App Blocker:** Real educational app usage unlocks real rewards.
> * 🕊️ **Zero Parent Intervention:** Set the limits once, and the system runs itself 24/7.
> * 📚 **Bring Your Own Apps:** Khan Academy, Duolingo, Prodigy — you choose what counts.
> * ⚖️ **Configurable Limits:** You decide exactly how much learning earns how much play time.
> * 🛡️ **Custom Shields:** Visual themes explain to your kids why an app is locked.
>
> Full access requires a Brain Coinz subscription. Includes a 14-day trial.
>
> Terms of Use: https://i6dev.ca/braincoinz/terms.html
> Privacy Policy: https://i6dev.ca/braincoinz/privacy.html

---

## Methodology Notes

### Positioning-fit filter

Applied BEFORE Pop/Diff ranking. Each candidate keyword answered: *does the app's actual mechanic match what a searcher for this term expects?*

**Dropped** (mid-Pop, looked juicy, actually feature-mismatches):
- `chore chart` (Pop 29) — app isn't a chore tracker; implies manual parent approval
- `homework tracker` (Pop 34) — app doesn't track homework content
- `study timer` (Pop 42) — not a timer
- `sticker chart` / `behavior chart` — not parent-assigned stars
- `reward chart` (Pop 8, Diff 23) — chart framing implies manual scoring, not auto-unlock

**Kept** (genuine mechanic fit):
- `limit screen time` (Pop 23) — app IS a conditional limiter
- `reduce screen time` (Pop 7) — net effect of gated reward model
- `play time` / `earn play time` (Pop 40 / 5) — core positioning phrase (subtitle of live 1.0.2)
- `reward kids / positive reinforcement / motivate kids` — core behavioral-mechanism fit
- `educational motivation / kids productivity / learning rewards` — live keyword carryover

**Also dropped** (round 3 audit — adjacency trap despite low Diff):
- `dopamine detox` — pulls detox-program searchers; app does the opposite (continued use, gated)
- `habit tracker kids`, `kid routine` — app isn't a habit/routine tracker
- `kids focus` — not a focus-timer/ADHD-focus tool
- `track screen time` — pulls monitoring-parent intent

### Why the fit set is Pop-5-dominant

The app's true niche (automated learn-to-earn for kids) doesn't have Pop 20+ searches with matching intent. Accepting Pop 5 at Diff 21–49 is the correct tradeoff vs Pop 29+ at Diff 52 with feature mismatch. The MX slot absorbs higher-Pop mechanic-adjacent terms (`app blocker` Pop 50, `app lock` Pop 55) where those mechanics are honestly part of the app.

### Apple tokenizer rules applied

- Name + subtitle + EN_US keyword field tokens all combine within the EN_US locale to form phrases
- MX tokens do NOT combine with EN_US tokens (Apple does not merge across locales)
- Within MX, any two tokens can combine into a phrase — hence co-locating pairs like `app,blocker` and `play,time` in MX
- Apple de-duplicates tokens across the name + subtitle + keyword field — do not repeat

---

## Execution Checklist

- [ ] **App Store Connect → App Information → Name:** `Brain Coinz: Earn Screen Time`
- [ ] **App Store Connect → 1.0.3(1) → Subtitle (English-US):** `Reward Kids for Learning Apps`
- [ ] **App Store Connect → 1.0.3(1) → Keywords (English-US):** `motivate,positive,reinforcement,educational,limit,reduce,play,productivity,goal,game,daily,unlock`
- [ ] **App Store Connect → Add Language → Spanish (Mexico)**, then paste Keywords: `app,blocker,lock,play,time,earn,learn,parent,kid,safe,mode,youtube,block,filter,browser,web`
  - Subtitle (MX): copy English subtitle or translate minimally — subtitle content doesn't affect US ranking, but MX must have SOME subtitle value
  - App Name (MX): `Brain Coinz: Earn Screen Time` (same; acceptable)
- [ ] **Promo Text (English-US):** keep current live text (no change)
- [ ] **Description (English-US):** apply the 4 edits listed above
- [ ] **Submit 1.0.3(1) for Apple Review**
- [ ] **Day 14:** re-run `mcp__astro__get_app_keywords(appId: "6753270211", store: "us")` and diff against `BASELINE_METRICS.md`
- [ ] **Day 21:** re-run and diff again

## Success Criteria (day 14 and 21)

- `earn screen time` (Pop 5, Diff 45): 1000 → top 50
- `play time` (Pop **40**, Diff 65): 1000 → top 300 (stretch target)
- `limit screen time` (Pop 23, Diff 55): 1000 → top 300
- `positive reinforcement` (Pop 5, Diff 39): 1000 → top 200
- `motivate kids` (Pop 5, Diff 44): 1000 → top 200
- `reward kids` (Pop 5, Diff 21): 1000 → top 100
- `educational motivation`, `kids productivity`, `learning rewards` (live-keyword carryover): hold or improve
- `brain coinz`: hold #33 or better

**Rollback trigger:** `brain coinz` drops below 150 AND no tracked keyword replaces it by day 21 → revert to live 1.0.2 metadata.

## Out of Scope for this Submission

- **Review prompt strategy** — 0 reviews is the #1 conversion ceiling. Needs in-app prompt timed to first successful earning cycle. Code change; separate PR.
- **Screenshot OCR captions** — per `APPFIGURES_ASO_INSIGHTS.md`, Apple now OCR-indexes screenshot text. Current screenshots likely leak signal. Use the `aso-appstore-screenshots` skill to audit + replace captions with `reward kids`, `earn screen time`, `learning apps`.
- **Custom Product Pages (CPPs)** — map 2–3 intent clusters (earn / reward / ADHD-focus) to dedicated landing pages with targeted screenshots.
- **Post-approval competitor-conquest metadata** — separate metadata-only submission putting `qustodio,bark,aura,life360,kidslox` into a Spanish-ES or French locale keyword field (NOT MX, now used for stretch terms).
