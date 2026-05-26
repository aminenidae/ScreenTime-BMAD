# Screenshot OCR Audit — Tic Lock 1.0.4

**Status:** FINAL (2026-05-26)
**Applies to:** `/Users/ameen/Downloads/New ASC - SC/iphone/` (7 screenshots) + `/Users/ameen/Downloads/New ASC - SC/ipad/` (7 screenshots)

Apple indexes text visible in App Store screenshots via OCR. This audit documents every text string on each screenshot and maps the keyword coverage against the 1.0.4 metadata package (see `1.0.4_METADATA_DRAFT.md`).

---

## Current Screenshot Text — iPhone 6.7"

| # | Headline | Bottom text |
|---|---|---|
| SC1 | Screen Time Kids Earn | *(none)* |
| SC2 | Manage Screen Time. No Battles. | Set daily limits. The app does the rest. |
| SC3 | Learn first. Play after. | Complete learning goals to unlock favorite apps. |
| SC4 | Track every minute. | Earned. Used. Remaining. All in one place. |
| SC5 | Apps stay locked until goals are met. | No workarounds. No negotiations. |
| SC6 | Daily Limit Reached. Apps Lock. | Automatic screen time limits. Just balance. |
| SC7 | Safe browsing. Built in. | Harmful websites blocked automatically. |

## Current Screenshot Text — iPad 13"

| # | Headline | Bottom text |
|---|---|---|
| SC1 | Screen Time Kids Earn | *(none)* |
| SC2 | Manage Screen Time. No Battles. | Set learning goals. The app does the rest. |
| SC3 | Learn first. Play after. | Complete learning goals to unlock favorite apps. |
| SC4 | Track every minute. | Earned. Used. Remaining. All in one place. |
| SC5 | Apps stay locked until goals are met. | No workarounds. No negotiations. |
| SC6 | Lock Apps Automatically. | Automatic screen time limit. Just balance. |
| SC7 | Safe browsing. Built in. | Harmful websites blocked automatically. |

## iPhone vs iPad Differences

The two sets vary text in SC2 and SC6. This is intentional — different text across device classes means Apple indexes a wider set of keyword tokens.

| Slot | iPhone | iPad | Extra tokens from variation |
|---|---|---|---|
| SC2 bottom | "Set **daily limits**…" | "Set **learning goals**…" | iPhone adds `daily`, `limits`; iPad adds `learning`, `goals` |
| SC6 headline | "**Daily Limit Reached. Apps Lock.**" | "**Lock Apps Automatically.**" | iPhone reinforces `daily`, `limit`; iPad adds `automatically` in headline |
| SC6 bottom | "…screen time **limits**" | "…screen time **limit**" | Minor plural variation |

---

## Keyword Token Coverage

### Metadata token pool (from 1.0.4 as-submitted)

| Field | Tokens |
|---|---|
| **Name** | `tic`, `lock`, `parental`, `control`, `app` |
| **Subtitle** | `kids`, `lock`, `app`, `reward`, `chart` |
| **KW EN_US** | `parenting`, `kids`, `mode`, `games`, `child`, `family`, `ipad`, `chore`, `screen`, `time`, `homework`, `school`, `math`, `education`, `reading` |
| **KW ES_MX** | mirrors EN_US — `parenting`, `kids`, `mode`, `games`, `child`, `family`, `ipad`, `chore`, `screen`, `time`, `homework`, `school`, `math`, `education`, `reading` |

> **No-redundancy principle:** The KW field deliberately excludes tokens already in the Name/Subtitle (`lock`, `control`, `app`, `reward`, `chart`, `parental`). The ASO community reports that repeating tokens across these fields wastes character budget and can hurt ranking. Freed characters were invested in the educational niche (`homework`, `school`, `math`, `education`, `reading`) and device targeting (`ipad`, `games`).
>
> **All 5 locales (EN_US, EN_CA, EN_GB, EN_AU, ES_MX) use the same keyword string.** The 10x-trick separate ES_MX payload was not used for this submission. This means tokens like `blocker`, `brainrot`, `block`, `filter`, `browser`, `play`, `earn`, `learn` are no longer in any keyword field — some are partially recovered via screenshot OCR.

### NEW tokens contributed by screenshot OCR

These tokens appear in screenshot text but are NOT in the Name, Subtitle, or any keyword field:

| Token | Source screenshot(s) | Search value |
|---|---|---|
| `manage` | SC2 (both) | "manage screen time" — parent intent phrase |
| `daily` | SC2 (iPhone), SC6 (iPhone) | "daily screen time limit" — common search |
| `limit` / `limits` | SC2 (iPhone), SC6 (both) | "screen time limit" Pop 11, "limit screen time" Pop 23 |
| `learning` | SC2 (iPad), SC3 (both) | "learning apps", "learning goals" |
| `goals` | SC2 (iPad), SC3 (both), SC5 (both) | "learning goals" |
| `unlock` | SC3 (both) | Core app mechanic — dropped from KW in Apr 27 swap |
| `track` | SC4 (both) | "track screen time" — parent intent phrase |
| `locked` | SC5 (both) | Reinforces `lock` from Name + Subtitle |
| `automatic` / `automatically` | SC6 (both), SC7 (both) | "automatic screen time limit" |
| `balance` | SC6 (both) | "screen time balance" |
| `safe` | SC7 (both) | "safe browsing" — real feature, real search |
| `browsing` | SC7 (both) | Pairs with `safe` |
| `websites` | SC7 (both) | "block websites" |
| `blocked` | SC7 (both) | Reinforces `block` from ES_MX |

**Total: 14 new tokens** added to the search surface via screenshot OCR alone.

### Tokens still not covered anywhere (metadata + screenshots)

| Token | Potential value | Why it's missing |
|---|---|---|
| `monitor` | "monitor kids phone" — high parent intent | No natural fit in current screenshot copy |
| `web` | "web filter" — pairs with ES_MX `filter` | SC7 uses "browsing" instead of "web" |
| `usage` | "app usage", "screen time usage" | SC4 could say "app usage" but "every minute" is stronger for conversion |
| `restrict` | "restrict apps" — parental control adjacent | Would feel negative in marketing copy |
| `dashboard` | Visible in SC4 UI but not in overlay text | Niche — not worth a headline change |

> Note: `homework`, `school`, `math`, `education`, `reading` are now covered via the KW field (May 26 rebuild). `educational` (dropped from old KW) is covered by `education` in the new field.

---

## Search Phrases Enabled by OCR

The screenshot text unlocks these multi-token search phrases that couldn't form from metadata alone:

| Phrase | Tokens from | Est. value |
|---|---|---|
| manage screen time | OCR `manage` + metadata `screen` `time` | High — direct parent intent |
| daily limit | OCR `daily` + OCR `limit` | High — common restriction phrase |
| screen time limits | metadata `screen` `time` + OCR `limits` | High — Pop 11+ |
| learning goals | OCR `learning` + OCR `goals` | Medium — educational parent niche |
| track screen time | OCR `track` + metadata `screen` `time` | Medium — monitoring intent |
| safe browsing | OCR `safe` + OCR `browsing` | Medium — real feature, real search |
| unlock apps | OCR `unlock` + metadata `app`/`apps` | Medium — core mechanic |
| automatic screen time limit | OCR `automatic` + metadata `screen` `time` + OCR `limit` | Medium — hands-off positioning |
| apps locked | metadata `app` + OCR `locked` | Low-medium — reinforcement |
| block websites | metadata `block` + OCR `websites` | Low-medium — web safety niche |

---

## Verdict

The current 7-screenshot set covers the metadata gaps well. The iPhone/iPad text variation is the right call — it widens the OCR surface without any extra design work. The 14 new tokens fill the biggest holes left by the Apr 27 keyword swap (where `limit`, `unlock`, `educational`, and others were dropped to make room for the reward-chart niche).

The one remaining high-value tweak — if a re-render is ever on the table — would be changing SC7's headline from "Safe browsing" to "Safe web filter" to pick up the `web` token (forming "web filter" with ES_MX's `filter`). But this is marginal, not blocking.
