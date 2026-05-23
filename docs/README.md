# ScreenTime Rewards — Docs Index

_Last updated 2026-05-20. App is live on the App Store (1.0.3 approved 2026-04-17, 1.0.4 in flight)._

Everything in this folder is current work. Historical material — old App Review rejections, the phantom-usage investigation, plans whose work has already shipped — lives in [`archive/`](archive/) and is kept only for reference.

---

## Usage tracking (how the app counts screen time)

| Doc | What it's for |
|---|---|
| [USAGE_TRACKING_BIBLE.md](USAGE_TRACKING_BIBLE.md) | Plain-English overview of how usage is recorded end-to-end |
| [SMART_THRESHOLD_FILTERING.md](SMART_THRESHOLD_FILTERING.md) | **Source of truth.** Master log of every iOS quirk we've found and how we handle each one |
| [THREE_PHASE_RECORDING_ARCHITECTURE.md](THREE_PHASE_RECORDING_ARCHITECTURE.md) | The new recording model being rolled out |
| [UNIFIED_USAGE_COUNTER_PLAN.md](UNIFIED_USAGE_COUNTER_PLAN.md) | One counter, one bank function — refactor in progress |
| [EXTENSION_MEMORY_OPTIMIZATION_PLAN.md](EXTENSION_MEMORY_OPTIMIZATION_PLAN.md) | Keeping the iOS extension under its 6MB hard limit |
| [PATH_B_HIGHWATER_REDESIGN_PLAN.md](PATH_B_HIGHWATER_REDESIGN_PLAN.md) | Alternate recording design currently running in shadow mode |

## Parent dashboard & pairing

| Doc | What it's for |
|---|---|
| [PARENT_DASHBOARD_PERFORMANCE_2026-05-14.md](PARENT_DASHBOARD_PERFORMANCE_2026-05-14.md) | The May 14 overhaul (3 min load → 15 sec) |
| [PARENT_LAUNCH_CACHE.md](PARENT_LAUNCH_CACHE.md) | Cache-first render on parent launch |
| [PAIRING_AND_CONFIG_SYNC_FIXES_2026-04-26.md](PAIRING_AND_CONFIG_SYNC_FIXES_2026-04-26.md) | Bidirectional parent↔child config sync foundation |

## Open issues & pending work

| Doc | Status |
|---|---|
| [CATEGORY_FLIP_BANK_LOSS.md](CATEGORY_FLIP_BANK_LOSS.md) | Unfixed — flipping an app's category retroactively wipes bank credit |
| [SCHEDULE_VERSIONING_AND_BANK_FIX_PLAN.md](SCHEDULE_VERSIONING_AND_BANK_FIX_PLAN.md) | Three connected fixes around ratio versioning |
| [SILENT_PUSH_MONITORING_REFRESH.md](SILENT_PUSH_MONITORING_REFRESH.md) | Plan to replace failed BGTask with server-triggered push |
| [SUBSCRIPTION_RESTRUCTURE_PLAN.md](SUBSCRIPTION_RESTRUCTURE_PLAN.md) | Blocker — consolidate 3 subscription groups into 1 before production launch |

## Legal (live & published)

- [privacy-policy.md](privacy-policy.md) — published at `https://i6dev.ca/braincoinz/privacy.html`
- [terms-of-service.md](terms-of-service.md) — published at `https://i6dev.ca/braincoinz/terms.html`

---

## Archive

- [`archive/app-review/`](archive/app-review/) — past App Review rejections (all resolved by the 1.0.3 approval)
- [`archive/phantom-investigation/`](archive/phantom-investigation/) — the multi-month phantom-usage investigation (resolved 2026-04-30)
- [`archive/shipped-plans/`](archive/shipped-plans/) — design docs whose work is already in the app
