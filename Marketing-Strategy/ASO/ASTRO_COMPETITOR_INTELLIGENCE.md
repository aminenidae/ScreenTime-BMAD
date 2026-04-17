# Astro Competitor Keyword Intelligence Report

**Target Apps Researched:**
1. Carrots&Cake (AppStore ID: 1589481560)
2. Qustodio Parental Control (AppStore ID: 1501720596)
3. Bark - Parental Controls (AppStore ID: 1477619146)
4. OurPact (AppStore ID: 954029412)

After running a deep AI extraction on Astro against these top competitor apps, I cross-referenced the keyword suggestions to find the overlapping high-intent search terms that parents are universally using across this entire App Store category. 

Here is the careful breakdown of the true search landscape:

## 1. The "Brand Search" Phenomenon is Massive
The data reveals that a huge percentage of parents don't search for generic terms at all; they search directly for the major brands they saw on Facebook or Google. 
*   **"family link"** — Popularity: 65, Difficulty: 70
*   **"life360"** — Popularity: 69, Difficulty: 64
*   **"aura"** — Popularity: 66, Difficulty: 57
*   **"qustodio"** — Popularity: 53, Difficulty: 39 *(Golden Opportunity: High Pop, Very Low Diff!)*
*   **"bark"** — Popularity: 61, Difficulty: 53

*Astro Insights:* You cannot put competitor brand names in your visible App Name or Subtitle (Apple will reject the app). However, we can sneak these into the backend iOS keyword fields—particularly the Spanish (Mexico) localization slot—to legally siphon traffic from parents searching for Qustodio and Bark.

## 2. Universal "Pain Point" Keywords
When parents do use generic searches to find these apps, they coalesce around specific control mechanisms rather than "screen time" alone. 
*   **"screen time control"** — Popularity: 50, Difficulty: 63
*   **"app lock"** — Popularity: 55, Difficulty: 63
*   **"parental controls"** — Popularity: 32-41, Difficulty: 65-67
*   **"family safety"** / **"protection"** — (Often associated with GPS tracking apps like Bark and Life360, but still heavily searched).
*   **"nintendo switch parental controls"** — Popularity: 59, Difficulty: 62. *(Fascinatingly high volume, proving parents are trying to lock down consoles. We must ensure our marketing clarifies we control iOS, not Nintendo).*

## 3. High Volume, But Irrelevant to Brain Coinz (Avoid these)
The Astro competitor extraction highlighted several high-volume keywords that these apps rank for, but which Brain Coinz *should not* target because it causes a feature-mismatch:
*   **"GPS / Family Locator"** — Parents searching for Qustodio are often looking for GPS tracking. Brain Coinz does not do this.
*   **"Nanny Cam" / "Baby Monitor"** — Showing up in Bark's profile.
*   **"Call blocking app"** — Parents trying to block predators. Brain Coinz doesn't do this. 

## Strategic Conclusion
Based on this careful competitor indexing, our previously established strategy holds strong, but we have uncovered a massive new opportunity: **Competitor Brand conquesting.**

By updating our backend keyword string to include terms like `qustodio,bark,aura,life360,family,link`, we can appear as the "smart, automated alternative" right below Bark and Qustodio in the search results when parents who are fed up with complex GPS trackers look for a solution.

---

## 2026-04-17 — "Earn Screen Time" Dropdown Competitors

**Trigger:** On 2026-04-17 (same day as 1.0.3 approval) the iOS App Store autocomplete for `earn screen time` returned 9 suggestions, all using the `[brand]: earn screen time` format. Brain Coinz was absent. Searching `brain coinz` returned an empty dropdown — Apple's autocomplete has not indexed the app yet (post-June-2025 new-app delay).

**Brain Coinz Day-1 baseline on this phrase:** rank **1000 (unranked)**, Pop 5, Diff 45 (via `search_rankings`). This baseline is the diff point for Day 14 (2026-05-01) and Day 21 (2026-05-08) re-measurement.

### Competitor Table

All 9 dropdown apps now tracked in Astro (added 2026-04-17). Rank column = position in top-50 App Store results for the phrase `earn screen time` on 2026-04-17.

| # | Name | App Store ID | Genre | Reviews | Subtitle | Rank |
|---|---|---|---|---|---|---|
| 1 | MoveMore: Earn Screen Time | 6761498763 | Health & Fitness | 0 | Exercise to unlock your apps | >50 |
| 2 | Blocus: Earn Screen Time | 6758338291 | Productivity | 74 | Blocker, Focus & Timer | 35 |
| 3 | Fitblock: Earn Screen Time | 6755742199 | Productivity | 47 | Fitness, App Blocker & AI Reps | 37 |
| 4 | LockedIn: Earn Screen Time | 6747677872 | Productivity | 38 | Habittracker & Focus | 26 |
| 5 | Merite: Earn Screen Time | 6757801429 | Productivity | 9 | Complete tasks to unlock apps | 18 |
| 6 | MindfulBytes: Earn Screen Time | 6686407678 | Productivity | 0 | Health goals, then scroll | >50 |
| 7 | One Life — Earn Screen Time | 6752967648 | Productivity | 61 | #1 Screen Claim App | 4 |
| 8 | One Thing: Earn Screen Time | 6748092391 | Productivity | 817 | App Blocker & Habit Builder | 16 |
| 9 | Study Lock: Earn Screen Time | 6758857561 | Education | 1 | AI Flashcards, App Blocker | 33 |

### Category Read — Kids+Earn Intersection is Still Whitespace

**All 9 dropdown apps target adult self-control, not kids/family.** Genre distribution: 7 Productivity, 1 Health & Fitness, 1 Education. Subtitles describe habit-building, fitness challenges, or study focus — aimed at the user of the phone, not a parent managing a child's phone.

Within the top-50 `earn screen time` search results, only 3 apps target parents/kids:

- **#9 ScreenEarn: Parental Control** (ID `6746706699`) — 3 reviews, "Do chores, unlock screen time"
- **#32 ScreenCoach - Parental Control** (ID `1509516221`) — 16 reviews, "Screen Time, Chores + Rewards"
- **#45 Thrive - Smarter screen time** (ID `6502852840`) — 0 reviews, "Screen time that kids earn"

These three — not the 9 dropdown apps — are the real direct competitors for Brain Coinz. Collective review count: **19**. None dominate.

**Implication:** the *phrase* `earn screen time` is crowded by adult-productivity apps, but the (kids) × (earn screen time) intersection is contested only by ScreenEarn, ScreenCoach, and Thrive. This holds the whitespace thesis, but narrows its scope — we're not the only parental-controls app playing the earn-time mechanic; we're the 4th entrant, and the other three combined have ~19 reviews and low visibility.

### Keyword Footprint — Extracted via `extract_competitors_keywords`

36 keywords surfaced from the apps ranking for `earn screen time` (Pop > 5). Columns show competitor-surfaced popularity.

| Keyword | Pop | In 46-keyword baseline? |
|---|---|---|
| phone | 68 | No |
| app | 66 | No |
| life | 63 | No |
| timer | 63 | No |
| focus | 62 | No (we have `focus app`) |
| apps | 61 | No |
| claim app | 59 | No |
| brainrot | 55 | No |
| control | 54 | No |
| time | 52 | No |
| screen time | 51 | **Yes** |
| brain | 50 | No |
| app blocker | 50 | **Yes** |
| unrot | 49 | No (brand — skip) |
| habits | 42 | No |
| claim | 41 | No |
| screen | 37 | No |
| achieve | 27 | No (brand-adjacent) |
| time control | 20 | No |
| time app | 19 | No |
| limit | 17 | No |
| screen blocker | 13 | No |
| life time | 12 | No |
| focus timer | 9 | No |
| app timer | 9 | No |
| chores | 9 | No (we have `kids chores`, `chore chart`) |
| block apps | 9 | **Yes** |
| blocker | 8 | No |
| app limit | 7 | No |
| screen app | 7 | No |
| focus app | 7 | **Yes** |
| earn | 7 | No |
| time limit | 7 | No |
| screen limit | 6 | No |
| clearspace | 6 | No (brand — skip) |
| timer app | 6 | No |

### Gap Analysis — What Competitors Index that We Don't

**32 of 36 surfaced keywords are NOT in our 46-keyword baseline.** Most are too generic (`app`, `phone`, `time`, `control`) or adult-productivity-coded (`brainrot`, `dopamine detox`, `focus timer`, `claim app`). The signal: competitors rank on broad self-control vocabulary; our baseline is tuned to parental/kids vocabulary. Different game.

### Longtail Candidates for Brain Coinz (Match Our Positioning)

Filtered to 2–3 word phrases with competitor popularity > 5 AND semantic fit for kids+earn mechanic:

| Phrase | Pop | Fit | Notes |
|---|---|---|---|
| `time control` | 20 | Medium | Parent-adjacent — "who controls my kid's time" |
| `screen limit` | 6 | Medium | Direct parental-controls vocabulary |
| `time limit` | 7 | Medium | Same as above |
| `chores` | 9 | High | We already have `kids chores` + `chore chart` but not the standalone word |
| `earn` | 7 | High | Standalone — we have `earn play time` + `earn screen time` but not the single-word stem |

**Explicitly NOT candidates:** `brainrot`, `claim app`, `focus timer`, `habits`, `unrot`, `clearspace`, `achieve` — these code for adult self-control or are competitor brands. Attempting these would misalign Brain Coinz with the wrong search intent.

**Do not act now.** The 14-day measurement window (through 2026-05-01) must run on the current metadata untouched. Park these 5 candidates for Week 2 consideration.

### What This Changes

- `earn screen time` is now a tracked keyword (was missing from the 46-keyword baseline — partial blind spot now closed).
- Whitespace thesis in `ASO_EXECUTION_PLAN.md` holds at the kids intersection, but the `earn screen time` phrase itself is more crowded than previously documented.
- The 9 dropdown apps are **not our competitive set**. The real competitive set for kids+earn is ScreenEarn (3 reviews), ScreenCoach (16), Thrive (0). Small players — a reachable beachhead.
- No metadata changes from this analysis. Re-evaluate at Day 14 / Day 21.
