# ASO — Brain Coinz

Single home for every App Store Optimization artifact: metadata, keyword research, competitor intel, screenshot specs, and submission notes. If a file relates to how Brain Coinz is listed, found, or ranked on the App Store, it lives here.

Non-ASO marketing (social, channel strategy, broad market research) stays in `Marketing-Strategy/` root. Production screenshot PNGs remain at `/screenshots/final/` — only the design/spec docs are here.

## Current Status

- **1.0.3 (1) approved 2026-04-17** after same-day 2.3.6 rejection. See `app-review-notes.md` for the verbatim Apple rejection, our reply, and the resolution path.
- ASO metadata batch 1 (subtitle, keywords, promo text, description) is live per `ASO_EXECUTION_PLAN.md`.
- **Pre-deploy baseline locked 2026-04-14** in `BASELINE_METRICS.md` — 14/21-day lift measurements pending.

## Files by Intent

### Execute (paste into App Store Connect)
- `1.0.6_METADATA_LIVE.md` — **current live metadata** (name, subtitle, keywords) as set for 1.0.6, 2026-06-25. Most recent as-shipped record.
- `ASO_EXECUTION_PLAN.md` — the live metadata package (name, subtitle, keywords, description, promo text). Deployed 2026-04-17.
- `app-review-notes.md` — versioned Notes-field block for ASC; paste on every submission

### Measure
- `BASELINE_METRICS.md` — pre-deploy Astro keyword ranks (46 keywords), the reference point for all lift measurements

### Research & Intelligence
- `POST_APPROVAL_MOMENTUM_STRATEGY.md` — research + tactics for the first 2–4 weeks after metadata approval; reconciles the "deterministic first-week" theory against Apple's June 2025 algo change
- `APPFIGURES_ASO_INSIGHTS.md` — algorithm mechanics: AI screenshot OCR, 10x localization, keyword duplication
- `ASTRO_COMPETITOR_INTELLIGENCE.md` — competitor landscape + Pop/Diff scores from Astro

### Creative (Screenshots)
- `APP_STORE_SCREENSHOT_PLAN.md` — 8-screenshot narrative arc, feature mapping
- `APP_STORE_SCREENSHOT_PROMPTS.md` — per-screenshot AI image generation prompts
- `SCREENSHOT_WORKSHOP.md` — executable playbook (1290×2796, Pillow, Lyttle skill)
- Final PNGs: `/screenshots/final/01-*.png … 08-*.png` (not here — asset folder stays at repo root)

### Archive
- `archive/aso-metadata.md` — superseded; references old "ScreenTime Rewards" naming
- `archive/Strategic_Architectures_ASO.md` — older comprehensive ASO framework (Feb 2025), kept for reference
- `archive/app-store-connect-guide.md` — pre-rebrand first-time-setup guide; app is already live and configured. Kept for subscription-group / age-rating reference only.

### Not in this folder (moved out)
- `../ADAM_LYTTLE_INSIGHTS.md` — paywall patterns, onboarding tiers, and ad strategies. Only Section 4 (product positioning) is ASO-adjacent; the rest is broader growth/monetization and belongs in `Marketing-Strategy/` root.

## Workflow for New ASO Work

1. New metadata iteration → update `ASO_EXECUTION_PLAN.md` (don't fork a new file; keep the single source of truth).
2. New keyword research round → update `BASELINE_METRICS.md` with a new dated section; keep history.
3. New competitor findings → append to `ASTRO_COMPETITOR_INTELLIGENCE.md` under a dated heading.
4. New screenshot iteration → update the three screenshot docs together; regenerate PNGs into `/screenshots/final/`.
5. New rejection/approval event → add a dated section to `app-review-notes.md`.
