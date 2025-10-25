# Current Status Summary
**Date:** 2025-10-24
**Project:** ScreenTime-BMAD / ScreenTimeRewards

---

## 🎯 Active Work

- **Reward removal cleanup** – Removing a reward app currently migrates it into the Learning tab and leaves stale usage/points; need to strip assignments and blocks cleanly.
- **Re-adding apps resets state** – Reintroducing a previously removed app pulls back prior usage/points data; expected behaviour is a clean slate.
- **Removal UX messaging** – Add confirmation copy warning that deleting an app clears its earned points and (for reward apps) lifts the shield.
- **Picker presentation flicker (Oct 24 evening)** – First launch still flashes the picker sheet; deferred unless a quick fix surfaces.

---

## 🔍 Latest Findings

- `Run-ScreenTimeRewards-2025.10.24_23-30-09--0500.xcresult` shows that deleting a reward app moves it into the Learning snapshots (`Learning snapshot logical IDs` now include the removed reward token) even though `ScreenTimeService` still stores it as Reward; UI now lists the removed reward alongside true Learning apps.
- The same run confirms shields are requested to drop (`ScreenTimeService] Shield removed from 1 apps`) but the reassigned Learning entry still carries the old logical ID/points, so persistence cleanup is incomplete.
- Re-adding a previously removed app still restores its prior usage/points state instead of starting at zero.
- Immediate post-picker sheet presentations display the expected apps, but the console still reports presentation warnings (`Attempt to present … while a presentation is in progress`) indicating the presentation flicker remains.

---

## ✅ What's Working

- Duplicate-prevention guard validated on-device; Reward flows can no longer claim Learning apps and vice versa.
- Learning and Reward tab snapshots refresh immediately after picker save, showing the correct apps without relaunches.
- Master selection merges persist across monitor restarts; blocking/unblocking still behaves as expected.
- Previous shuffle regression remains resolved — logical IDs stay unique for privacy-protected apps.
- Background monitoring loop (restart timer + Darwin notifications) continues to function after category changes.

---

## 🔧 Next Steps

1. Prevent removed reward apps from migrating into the Learning list; confirm category assignments shrink correctly.
2. Ensure shields drop and persistence clears when reward apps are deleted; retest on device.
3. Reset usage/points when re-adding a previously removed app; confirm persistence updates accordingly.
4. Add removal confirmation UX messaging covering point loss and shield release.
5. Timebox a spike on picker presentation sequencing; if the flicker fix is quick, land it, otherwise park for a later sprint.

Refer to `/Users/ameen/Documents/ScreenTime-BMAD/PM-DEVELOPER-BRIEFING.md` for task breakdowns and coordination notes.

---

**END OF CURRENT STATUS**
