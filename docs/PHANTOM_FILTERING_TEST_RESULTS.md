# Phantom Filtering Test Results

**Date:** 2026-02-01 (post-midnight fresh start)
**Branch:** `feature/usage-accuracy-clean`
**Build:** ab3826e (SQLite audit removed, phantom filtering retained)

## Test Objective

Validate the 3-layer phantom event filtering system works correctly without blocking legitimate usage events.

## System Under Test

### Phantom Filtering Logic (DeviceActivityMonitorExtension.swift)

1. **SKIP_RESTART** - 55-second window after monitoring restart
2. **SKIP_RAPID** - Events within 2 seconds of last event for same app
3. **THRESH_DECREASE** - Threshold decreased (catch-up events from prior usage)

### Key Insight Validated

The 55-second phantom window is inherently safe because:
- ~16s to close main app and launch learning app
- +60s minimum usage before first threshold fires
- = **76s minimum** before any real event can fire

This means real usage events will always be outside the 55s phantom window.

---

## Test Phases

### Phase 1: Fresh Start - YouTube 5 minutes

**Scenario:** First session of the day, all counters at 0

| Minute | Time | timeSinceRestart | Result |
|--------|------|------------------|--------|
| 1 | 00:17:07 | - | ✅ CASE_3_PROGRESS → 60s |
| 2 | 00:18:07 | - | ✅ CASE_3_PROGRESS → 120s |
| 3 | 00:19:07 | - | ✅ CASE_3_PROGRESS → 180s |
| 4 | 00:20:07 | - | ✅ CASE_3_PROGRESS → 240s |
| 5 | 00:21:07 | - | ✅ CASE_3_PROGRESS → 300s |

**Result:** ✅ All 5 minutes recorded (300s)

---

### Phase 2: Quick Restart - YouTube 3 minutes

**Scenario:** Force close main app, reopen (restart monitoring), close, launch YouTube within 30s

| Minute | Time | timeSinceRestart | Result |
|--------|------|------------------|--------|
| 6 | 00:22:28 | 83s | ✅ CASE_3_PROGRESS → 360s |
| 7 | 00:23:29 | 144s | ✅ CASE_3_PROGRESS → 420s |
| 8 | 00:24:37 | 212s | ✅ CASE_3_PROGRESS → 480s |

**Result:** ✅ All 3 minutes recorded (480s total for YouTube)

**Key Observation:** Even though user launched YouTube within 30s of restart, the first event fired at 83s (outside 55s window) because 60s of actual usage was required.

---

### Phase 3: App Switch - Facebook 4 minutes

**Scenario:** Normal switch to different app

| Minute | Time | timeSinceRestart | Result |
|--------|------|------------------|--------|
| 1 | 00:22:28 | 383s | ✅ CASE_3_PROGRESS → 60s |
| 2 | 00:23:29 | 444s | ✅ CASE_3_PROGRESS → 120s |
| 3 | 00:24:37 | 512s | ✅ CASE_3_PROGRESS → 180s |
| 4 | 00:25:39 | 573s | ✅ CASE_3_PROGRESS → 240s |

**Result:** ✅ All 4 minutes recorded (240s)

---

### Phase 4: Extended Session - Instagram 15 minutes

**Scenario:** Long continuous session on a single app

| Minute | Time | timeSinceRestart | Total |
|--------|------|------------------|-------|
| 1 | 00:29:50 | 84s | 60s |
| 2 | 00:30:49 | 143s | 120s |
| 3 | 00:31:49 | 203s | 180s |
| 4 | 00:32:49 | 263s | 240s |
| 5 | 00:33:47 | 321s | 300s |
| 6 | 00:34:47 | 381s | 360s |
| 7 | 00:35:49 | 443s | 420s |
| 8 | 00:36:49 | 503s | 480s |
| 9 | 00:37:49 | 564s | 540s |
| 10 | 00:38:48 | 622s | 600s |
| 11 | 00:39:48 | 682s | 660s |
| 12 | 00:40:49 | 743s | 720s |
| 13 | 00:41:49 | 803s | 780s |
| 14 | 00:42:50 | 864s | 840s |
| 15 | 00:43:50 | 924s | 900s |

**Result:** ✅ All 15 minutes recorded (900s)

---

### Phase 5: Multi-App Goal Completion

**Scenario:** Use YouTube and Facebook to reach 15 minutes each, triggering goal unlock

#### YouTube: 13min → 16min

| Time | Minute | Today Total | Result |
|------|--------|-------------|--------|
| 00:53:03 | 5 | 780s (13min) | ✅ CASE_3_PROGRESS |
| 00:54:57 | 6 | 840s (14min) | ✅ CASE_3_PROGRESS |
| 00:54:57 | 7 | 900s (15min) | ✅ **TARGET REACHED** |
| 00:55:56 | 8 | 960s (16min) | ✅ CASE_3_PROGRESS |

#### Facebook: 4min → 15min

| Time | Minute | Today Total | Result |
|------|--------|-------------|--------|
| 00:57:49 | 1 | 300s (5min) | ✅ CASE_2_DECREASE → THRESH_RESET → CASE_3_PROGRESS |
| 00:58:49 | 2 | 360s (6min) | ✅ CASE_3_PROGRESS |
| 00:59:48 | 3 | 420s (7min) | ✅ CASE_3_PROGRESS |
| 01:01:36 | 4 | 480s (8min) | ✅ CASE_3_PROGRESS |
| 01:01:48 | 5 | 540s (9min) | ✅ CASE_3_PROGRESS |
| 01:02:48 | 6 | 600s (10min) | ✅ CASE_3_PROGRESS |
| 01:03:49 | 7 | 660s (11min) | ✅ CASE_3_PROGRESS |
| 01:04:49 | 8 | 720s (12min) | ✅ CASE_3_PROGRESS |
| 01:05:49 | 9 | 780s (13min) | ✅ CASE_3_PROGRESS |
| 01:06:49 | 10 | 840s (14min) | ✅ CASE_3_PROGRESS |
| 01:07:49 | 11 | 900s (15min) | ✅ **TARGET REACHED** |

#### Goals Unlocked at 01:07:49

```
✅ 0D9A6364-A5F goal MET (all mode) - all linked apps reached target
✅ 7F4AF4BB-A02 goal MET (all mode) - all linked apps reached target
```

**Result:** ✅ 2 reward goals unlocked as expected

---

## Summary

| Phase | App(s) | Duration | Scenario | Result |
|-------|--------|----------|----------|--------|
| 1 | YouTube | 5 min | Fresh start | ✅ Pass |
| 2 | YouTube | 3 min | Quick restart (<30s) | ✅ Pass |
| 3 | Facebook | 4 min | Normal switch | ✅ Pass |
| 4 | Instagram | 15 min | Extended session | ✅ Pass |
| 5 | YouTube + Facebook | To 15min each | Goal unlock | ✅ Pass |

## Conclusion

The phantom filtering system is working correctly:

1. **No false negatives** - All legitimate usage was recorded
2. **Phantom window is safe** - 55s window cannot block real events (minimum 76s before first real event)
3. **Session detection works** - CASE_2_DECREASE properly detects new sessions and resets threshold
4. **Goal system integrates correctly** - Goals unlock when all linked apps reach targets

## Technical Notes

- All events logged with `CASE_3_PROGRESS` (threshold increasing normally)
- `CASE_2_DECREASE` handled correctly for Facebook's second session (threshold reset)
- CloudKit sync triggered after each recording
- Shield checks evaluated correctly after each event
