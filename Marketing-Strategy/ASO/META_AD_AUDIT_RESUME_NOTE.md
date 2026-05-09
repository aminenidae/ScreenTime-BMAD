# Meta Ad Audit — Session Resume Note (2026-04-28)

**Use this to pick back up after restarting Antigravity.**

## Where we are

- **1.0.4 (build 7) was submitted to Apple review on 2026-05-01 then WITHDRAWN by user 2026-05-06** — serious bugs surfaced post-submit; build 8 now in development with additional fixes. Resubmit date TBD.
- Release mode = manual on build-8 approval (the original Apr 21 scheduled-May-1 plan was forfeited when submission slipped past the schedule date, then nullified by the build-7 withdrawal).
- Resumed marketing track. Decision: explore competitor ads, **starting with Meta** (TikTok next).
- Spawned an ASO subagent that produced `META_AD_AUDIT_2026-04-28.md` (216 lines) — but Meta Ad Library was JS-protected via WebFetch, so most "active ad" findings are *inferred* from third-party sources (iSpot.tv TV spots, SocialPeta 2021 data, competitor homepages, YouTube). Audit is more of a **positioning-cohort intel doc** than a verified ad inventory.

## What's verified ground truth

- ✅ OurPact owns the verbatim "Encourage balance without battles" — but buries it on a feature page (not a Meta hook). Direct fetch from `ourpact.com/cross-platform-parental-control-app`.
- ✅ Kidslox has a chore→screen-time reward feature listed on `kidslox.com/features/screen-time-limits` but does NOT market it on Meta. Closest competitor mechanic to Brain Coinz, invisible in their advertising.
- ✅ Bark anchors on threat-reveal + "7.3M children covered" + serious-incident counts. iSpot has 10+ TV creatives.
- ✅ Qustodio leads with "Over 9 million parents trust" + "Freedom for them, peace of mind for you" (homepage + YouTube).
- ✅ Family Link does not run discoverable Meta ads — Google promotes it via Search/YouTube/OS prompts only.

## What's still inferred (NOT verified)

- Active ad counts per competitor on Meta
- Specific Meta creative copy beyond search-snippet quotes
- Format mix (video/image %) — cited from a 2021 SocialPeta snapshot
- Whether Kidslox has any Meta creative at all (data point weakest in cohort)

## Plan that was about to execute when blocked

Use computer-use to drive Google Chrome (browsers are tier-"read" — screenshot only, no scroll/click) to capture Meta Ad Library above-the-fold pages for each competitor. URLs queued:

1. https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=US&q=bark+kids&search_type=keyword_unordered&media_type=all
2. https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=US&q=qustodio&search_type=keyword_unordered&media_type=all
3. https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=US&q=ourpact&search_type=keyword_unordered&media_type=all
4. https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=US&q=kidslox&search_type=keyword_unordered&media_type=all
5. https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=US&q=family+link&search_type=keyword_unordered&media_type=all

For each: open URL via `open <url>` from Bash → switch Chrome forward → screenshot above-the-fold → save to `Marketing-Strategy/ASO/evidence/2026-04-28_meta_<brand>.png` → note active-ad count + first 3 ads visible.

## Blocker that was active at restart

`mcp__computer-use__request_access` returned "macOS Accessibility and Screen Recording permission(s) not yet granted" repeatedly. Diagnosis: the **controlling process is Antigravity** (Claude Code runs inside it), and the permission grant requires Antigravity to be **fully quit (`Cmd+Q`) and reopened** before the new permission state is recognized.

User confirmed grants were added; restart pending.

## Resume steps (post-relaunch)

1. Re-call `mcp__computer-use__request_access` for `Google Chrome` — should succeed now.
2. For each of the 5 URLs above:
   - `open <url>` via Bash
   - Bring Chrome forward
   - `mcp__computer-use__screenshot` with `save_to_disk: true`
   - Note count + first ads
3. Update `META_AD_AUDIT_2026-04-28.md` with verified findings; convert "Limitations" section's inference flags to checked items where verified, or strengthen them where the screenshot disconfirms.
4. Then move to TikTok audit (TikTok Creative Center is publicly accessible and less JS-protected).

## After Meta + TikTok

Draft `META_CREATIVE_BRIEFS_BRAINCOINZ.md` — concrete ad concepts using:
- The "End screen time battles" empty hook slot (verified)
- Kid-POV unlock-mechanic demos (no competitor can match)
- "Works with Khan Academy, Duolingo" mechanism credibility (replaces social-proof scale Brain Coinz can't win)
- Counter-positioning vs. Bark surveillance frame ("we don't read your kid's texts")

## Reference files

- `Marketing-Strategy/ASO/META_AD_AUDIT_2026-04-28.md` — the 216-line audit doc
- `Marketing-Strategy/ASO/CPP_CONTENT_BRIEFS.md` — 5 CPP briefs (Apr 21, ASC creation pending)
- `Marketing-Strategy/ASO/MAY_1_MEASUREMENT_CHECKLIST.md` — Section A1 + E1 reflect as-submitted 1.0.4 metadata
- `Marketing-Strategy/ASO/1.0.4_METADATA_DRAFT.md` — updated 2026-04-28 with as-submitted Subtitle/Promo/KW/Description
- `~/.claude/projects/-Users-ameen-Documents-ScreenTime-BMAD/memory/project_1_0_4_as_submitted.md` — verbatim 1.0.4 fields in review

## One-line resume cue (if context is lost)

"Resume Meta Ad Library audit per `Marketing-Strategy/ASO/META_AD_AUDIT_RESUME_NOTE.md` — proceed from step 1 of Resume Steps."
