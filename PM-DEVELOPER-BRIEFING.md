# PM-Developer Briefing Document
**Project:** ScreenTime Rewards App
**Date:** 2025-10-25 (17:00 PM)
**PM:** GPT-5 (acting PM)
**Developer:** Code Agent (implementation only)

---

## 🎯 Upcoming Sprint Goal

**Implement the learning → reward point transfer flow so earned learning points can be converted into additional reward time.**

---

## 📊 Current State Snapshot

### What's Working ✅
- Category removal and picker stability verified on-device (Task M completed).
- Monitoring, persistence, and cross-category guards remain stable after the latest regression pass.
- Core documentation reduced to `CURRENT-STATUS.md`, `IMPLEMENTATION_PROGRESS_SUMMARY.md`, and this briefing for streamlined coordination.

### Risks & Unknowns ⚠️
- Point-transfer UX/process not yet defined (conversion rates, limits, confirmation flow, UI placement).
- Service-layer impact on monitoring thresholds and shield logic when reward time is extended.
- Need to confirm persistence schema changes (new fields for transferable balances) before coding.

---

## 📋 Developer Tasks – INITIAL DRAFT

### Task PT-1 — Define Point Transfer Requirements (IN DISCOVERY)
**Files:** `docs/` (new spec), `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

1. Capture required behaviours: conversion rate, minimum transfer amount, caps, UX triggers (manual button vs auto). 
2. Identify persistence updates (e.g. store `availableLearningPoints`, `transferredRewardMinutes`).
3. Confirm monitoring implications (does added reward time require reconfiguring events?).
4. Deliver short proposal (1–2 paragraphs) for PM sign-off.

**Deliverable:** Approved requirements note covering UX, data model, and service changes.

### Task PT-2 — Model & Persistence Updates (PENDING REQUIREMENTS)
_To be detailed once PT-1 is signed off._

### Task PT-3 — UI/Flow Implementation (PENDING REQUIREMENTS)
_To be detailed once PT-1 is signed off._

---

### Task PT-2 — All-Apps Selection Edge Case (IN PROGRESS 🚧)
**Issue:** When the user selects “All Apps” within the FamilyActivityPicker, the system returns a category-level selection. Our implementation only processes individual app tokens, so no apps appear in the assignment sheet after the picker dismisses.

**Analysis**
- FamilyControls collapses the selection to category tokens when “All Apps” is chosen. We currently ignore categories, so `familySelection.applications` stays empty.
- Logs show the picker returning zero app tokens while category assignments remain zero; the UI then appears blank.

**Proposed Fix Options**
1. **Fallback to Category Handling**: Detect category tokens on return and expand them to the known app list using the latest master selection/persistence. Requires a service method to enumerate all apps under that category.
2. **Prevent Category Selection**: Before presenting the picker, disable category rows or warn the user that only individual apps are supported.
3. **Mixed Approach**: Allow category selection but immediately prompt the user to confirm expansion into individual apps, then fetch and persist the expanded list.

**Next Steps**
- Decide which approach fits UX expectations (PM approval needed).
- If expanding categories, design a service helper to map category tokens to individual apps.
- Update picker handling logic and test with “All Apps” scenarios for both learning and reward flows.

**Deliverable:** Reward/Learning sheets show apps even when “All Apps” is picked; behaviour is documented and validated on device.

## Coordination Notes
- Keep logging instrumentation around picker and removal flows until point-transfer work is stable (helps detect regressions).
- Archive docs now live under `documentation_archive/2025-10-25/`; reintroduce only if required.
- Next sync: once PT-1 requirements draft is ready for review.

---

**End of Briefing**
