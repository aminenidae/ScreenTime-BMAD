# Phantom Event Fix Attempts Tracker

**Created:** February 1, 2026
**Updated:** February 6, 2026
**Current Status:** 🔄 TESTING (Attempt 15 - Locked Reward App Filter)
**Target Issue:** Handle phantom events without losing real usage after monitoring restart

---

## Problem Statement

After phantom events (iOS catch-up threshold events) occur and are correctly filtered, **iOS stops sending NEW threshold events** for real usage. This is because:

1. iOS DeviceActivityMonitor sends each threshold event **ONLY ONCE** per monitoring session
2. When phantom events flood in, iOS marks those thresholds as "already delivered"
3. Even though we filter them, iOS won't re-send them
4. New real usage doesn't trigger events because iOS thinks thresholds 1-N were already sent

**Example Timeline:**
```
1. User uses app for 5 min → iOS sends min.1, min.2, min.3, min.4, min.5 ✓
2. App restarts (rebuild, background kill, etc.)
3. iOS sends catch-up: min.1, min.2, min.3, min.4, min.5 (phantom flood)
4. Our code filters these correctly (SKIP_RAPID, SKIP_CROSS_APP)
5. User continues using app → should trigger min.6, min.7, min.8...
6. iOS does NOT send these because it thinks thresholds 1-5 were already "used up"
7. Result: No new usage recorded
```

**Prerequisite (CONFIRMED FIXED):** Usage inflation on restart is now fixed.

---

## Current Protection Layers (Attempt 15)

| Layer | Filter Name | Condition | Action |
|-------|-------------|-----------|--------|
| 1 | MONITORING_GAP_BLOCK | `timeSinceRestart < 55s` | Block (can't have 60s usage in <55s) |
| 2 | CADENCE_BLOCK | `timeSinceLastRecorded < 55s` | Block (thresholds are 60s apart) |
| 3 | LOCKED_REWARD_BLOCK | Reward app is shielded | Block (can't use locked app) |
| 4 | DUPLICATE_SKIP | `threshold == lastThreshold` | Skip |
| 5 | Event Buffering | Passes filters 1-4 | Buffer → validate later |
| 6 | Flood Detection | 3+ rapid events after buffer | Discard buffer |
| 7 | Delayed Restart | Phantom flood + quiet period | Restart monitoring |

---

## Fix Attempts Log

### Attempt 1: ❌ FAILED (initially thought SUCCESS)
**Date:** February 1, 2026
**Approach:** Extension signals main app via Darwin notification to restart monitoring

**Hypothesis:** If we detect a phantom flood and restart monitoring, iOS will reset its "thresholds delivered" state and start sending new events.

**Implementation:**
1. Added `trackPhantomFloodForRestart()` function to extension
2. Called from THREE locations (bug fix: was missing PHANTOM_BLOCKED_EARLY):
   - **PHANTOM_BLOCKED_EARLY block** (line ~315) - catches bulk of phantom events
   - SKIP_CROSS_APP block (line ~206)
   - SKIP_RAPID block (line ~408)
3. Tracks phantom count in 60s window, signals restart when count >= 5
4. Posts Darwin notification `com.screentimerewards.phantomRestartNeeded`
5. Main app handles notification and calls `restartMonitoring()`
6. 2-minute throttle prevents restart loops

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Added `trackPhantomFloodForRestart()` function (lines ~43-77)
  - Added call in PHANTOM_BLOCKED_EARLY block (line ~315) **[BUG FIX]**
  - Added call in SKIP_CROSS_APP block (line ~206)
  - Added call in SKIP_RAPID block (line ~408)
- `ScreenTimeService.swift`:
  - Added `phantomRestartNotification` constant (line ~50)
  - Added to Darwin notification registration array (line ~1025)
  - Added handler case in switch (line ~1091)
  - Added `handlePhantomRestartRequest()` function (lines ~1097-1121)

**Test Observation (v1 - FAILED):**
- Phantom flood of 80+ events triggered by rebuild during active learning app use
- All events blocked by PHANTOM_BLOCKED_EARLY at timeSinceRestart=30-34s
- BUT tracking code wasn't called (only in SKIP_CROSS_APP/SKIP_RAPID)
- After 55s window passed, NO new events recorded - iOS consumed thresholds

**Bug Fix:** Added `trackPhantomFloodForRestart()` call to PHANTOM_BLOCKED_EARLY block

**Test Observation (v2 - SUCCESS):**
- Phantom flood triggered at 17:32:24-29 (80+ events blocked by PHANTOM_BLOCKED_EARLY)
- PHANTOM_FLOOD_DETECTED triggered after 5 phantom events counted
- Darwin notification sent to main app
- Main app received notification and called `restartMonitoring()`
- New monitoring session started (ID: A94F4BE6...)
- After 55s phantom window, fresh threshold events arrived: min.1 → min.2 → min.3...
- Usage recorded correctly: 3960s → 4020s → 4080s → 4140s → 4200s → 4260s → 4320s

**Result:** ❌ FAILED - Usage inflation still occurring in production

**Post-Production Analysis (Feb 2, 2026):**
- Log analysis showed 81 minutes of usage recorded in a single 60-minute hour (mathematically impossible)
- Unknown App 7: 1740s (29 min) in hour 9
- Unknown App 3: 3120s (52 min) in hour 9
- Root cause: CASE_3 (threshold increased) has NO rapid-fire protection
- Multiple events for same app arrive within milliseconds, each adding +60s
- The `THRESHOLD_SANITY_FIX` resets lastThreshold to 0, allowing all subsequent events to pass

---

### Attempt 2: Darwin Restart + Post-Restart Catch-up Filter
**Date:** February 2, 2026
**Approach:** Retry Attempt 1 with added POST_RESTART_CATCHUP filter to prevent inflation

**Result:** ❌ FAILED - POST_RESTART_CATCHUP only worked within 120s of restart. Log showed inflation continuing after that window due to THRESHOLD_SANITY_FIX and THRESH_RESET resetting lastThreshold to 0.

---

### Attempt 3: Universal Threshold Guard
**Date:** February 4, 2026
**Approach:** Replace time-limited POST_RESTART_CATCHUP with universal threshold guard

**Result:** ❌ PARTIAL - Blocked phantom inflation, but ALSO blocked legitimate post-restart usage because after iOS restarts monitoring, it sends min.1, min.2, min.3... which are all below currentToday.

---

### Attempt 4: ❌ FAILED (Cadence-Based Detection)
**Date:** February 4, 2026
**Approach:** Add exception for legitimate post-restart usage based on event cadence

**Root Cause Analysis:**
After monitoring restart, iOS sends min.1, min.2, min.3 but currentToday=3360s (from before restart).
The universal filter blocked ALL these because threshold (60s, 120s, 180s) <= currentToday (3360s).

**Key Insight - Distinguishing phantom from real:**
| Characteristic | Phantom Flood | Real Usage |
|----------------|---------------|------------|
| Timing | Milliseconds apart | ~60s apart |
| After restart | Within 55s | After 55s |
| Thresholds | Out-of-order | Sequential/increasing |

**Implementation:**
```swift
// === CATCH-UP FILTER WITH POST-RESTART EXCEPTION ===
if thresholdSeconds <= currentToday && currentToday > 0 {
    let isOutsidePhantomWindow = timeSinceRestart > phantomWindowSeconds
    let isNormalCadence = timeSinceLastEvent >= 50.0 || lastEventTime == 0
    let isIncreasingThreshold = thresholdSeconds > lastThreshold || lastThreshold == 0

    if isOutsidePhantomWindow && isNormalCadence && isIncreasingThreshold {
        // Legitimate post-restart usage - allow it
        debugLog("✅ POST_RESTART_USAGE...")
        // Fall through to CASE_3
    } else {
        // Phantom catch-up - block it
        debugLog("🛡️ SKIP_THRESHOLD_BELOW_CURRENT...")
        return false
    }
}
```

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Updated CATCH-UP FILTER with post-restart exception (lines 413-436)

**Test Result:** ❌ FAILED

**Failure Analysis:**
- Phantom flood was correctly blocked by PHANTOM_BLOCKED_EARLY (08:50:56-57)
- User used learning app for 3 more minutes
- NO events arrived at all - iOS had marked thresholds as "delivered"
- **Root cause:** Blocking events doesn't help because iOS considers them delivered regardless

**Key insight:** We cannot both block events AND expect iOS to continue sending new events.

---

### Attempt 5: SET Semantics ❌ FAILED
**Date:** February 4, 2026
**Approach:** Stop blocking events entirely - use SET semantics to make events idempotent

**Root Cause Analysis:**
All previous attempts (1-4) tried various BLOCKING strategies. The fundamental flaw:
- iOS sends each threshold event ONLY ONCE per monitoring session
- When we block events, iOS still considers them "delivered"
- iOS then refuses to send new events for real usage
- Result: No new usage recorded after phantom flood

**Solution: SET Semantics**
Instead of blocking phantom events (which doesn't work), make event processing idempotent:

```
OLD (INCREMENT): newToday = currentToday + 60   // Each event adds 60s → phantoms inflate
NEW (SET):       newToday = max(currentToday, thresholdSeconds)  // Idempotent → no inflation
```

**Why SET works:**
| Scenario | INCREMENT Result | SET Result |
|----------|------------------|------------|
| Normal: min.1, min.2, min.3 | 0→60→120→180 ✅ | max(0,60)→max(60,120)→max(120,180) = 180 ✅ |
| Phantom flood: min.1×10 | 0→60→120→...→600 ❌ | max(0,60)→max(60,60)→...→60 ✅ |
| Post-restart: min.1 when currentToday=3360 | 3360→3420 ❌ | max(3360,60) = 3360 ✅ |
| Real min.57 after restart | N/A | max(3360,3420) = 3420 ✅ |

**Implementation:**
```swift
// === SET SEMANTICS: Same day processing ===
let currentToday = defaults.integer(forKey: todayKey)

// Only update if threshold would increase our total
if thresholdSeconds <= currentToday {
    debugLog("📋 THRESHOLD_NOT_HIGHER: \(thresholdSeconds)s <= currentToday=\(currentToday)s → skip (idempotent)", defaults: defaults)
    return false
}

// Threshold is higher - SET usage to this threshold value
let newToday = thresholdSeconds  // SET semantics - use threshold directly
debugLog("📋 SET_USAGE: currentToday=\(currentToday)s → newToday=\(newToday)s", defaults: defaults)
defaults.set(newToday, forKey: todayKey)
```

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Removed PHANTOM_BLOCKED_EARLY filter (no longer needed)
  - Removed CASE_2 skip logic (no longer needed)
  - Removed CATCH-UP FILTER (no longer needed)
  - Changed recording from INCREMENT to SET semantics
  - Updated ext_ keys to use SET semantics
  - Updated hourly tracking to use SET semantics

**Test Result:** ❌ FAILED

**Failure Analysis:**
- SET semantics caused **under-counting** after monitoring restart
- iOS thresholds reset per monitoring SESSION, not per day
- After restart, iOS fires min.1, min.2, min.3... for NEW session usage
- But our currentToday remembered previous usage (e.g., 4920s = 82 min)
- SET semantics: 60s <= 4920s → SKIP (wrong!)
- **19 minutes of real usage NOT recorded!**

**Key insight:** iOS thresholds are per-session, not cumulative daily. SET semantics only works if thresholds are cumulative.

---

### Attempt 5b: Cadence-Based INCREMENT ❌ FAILED
**Date:** February 4, 2026
**Approach:** Return to INCREMENT (+60s per event), but protect against phantom floods using timing cadence

**Key Insight - Distinguishing phantom from real:**
| Characteristic | Phantom Flood | Real Usage |
|----------------|---------------|------------|
| Event spacing | Milliseconds | ~60 seconds |
| Pattern | Burst within seconds | Spread over minutes |

**Implementation:**
```swift
let isInPhantomWindow = timeSinceRestart < 60.0
let isRapidFire = timeSinceLastEvent < 10.0

if isInPhantomWindow && isRapidFire {
    debugLog("🛡️ PHANTOM_SKIP: rapid-fire within phantom window")
    return false  // Block phantom events
}

// Normal cadence - INCREMENT
let newToday = currentToday + 60
```

**Test Result:** ❌ FAILED

**Failure Analysis:**
- Phantom flood: 80+ events correctly blocked with `PHANTOM_SKIP`
- Real usage after flood: 3 minutes used → **0 minutes recorded**
- iOS stopped sending events after phantom flood

**Root cause:** Blocking phantom events doesn't help because iOS considers thresholds "delivered" regardless of whether we process them. iOS won't send new events for real usage.

---

### Attempt 6: Block + Re-arm ❌ FAILED
**Date:** February 4, 2026
**Approach:** Keep phantom blocking, but trigger monitoring restart after flood is detected

**Test Result:** ❌ FAILED

**Failure Analysis:**
- Phantom flood (200+ events) correctly blocked with PHANTOM_SKIP
- BUT restart was triggered IMMEDIATELY at t≈0s
- 2-minute throttle prevented subsequent restart requests
- New session's catch-up (t=49-53s) consumed all thresholds
- After flood: NO new events arrived for real usage
- **Root cause:** Restart during flood creates a loop - new session immediately gets its own catch-up flood

---

### Attempt 7: Delayed Restart ❌ PARTIAL (late phantom floods not blocked)
**Date:** February 4, 2026
**Approach:** Don't restart during flood - wait until phantom window ends + quiet period passes

**Core insight:** The restart must happen AFTER the phantom flood completes, not during it. Restarting during the flood creates a cycle where each new session triggers another catch-up flood.

**Key discovery:** Thresholds are static (min.1-60) configured at monitoring start. Once iOS "delivers" them in a phantom flood, NO more events fire until monitoring restarts. There's no dynamic re-arming.

**How it works:**
1. **Block phantom events** → PHANTOM_SKIP (same as before)
2. **Set flag, don't restart** → `phantom_flood_detected = true`
3. **Track last event time** → For quiet period detection
4. **Main app polls (30s timer)** → Checks for delayed restart conditions
5. **Restart when conditions met:**
   - Phantom window ended (> 60s since restart)
   - Quiet period passed (> 30s since last phantom event)
   - Not throttled (> 120s since last restart request)
6. **Fresh session starts** → min.1-60 thresholds available again

**Implementation:**

Extension - removed immediate Darwin notification:
```swift
// In trackPhantomFloodForRestart():
if phantomCount >= 5 {
    debugLog("🚨 PHANTOM_FLOOD_DETECTED: flagging for DELAYED restart")
    defaults.set(true, forKey: "phantom_flood_detected")
    defaults.set(now, forKey: "phantom_flood_last_event_time")
    // NOTE: Removed Darwin notification - main app polls instead
}
```

Main app - added polling timer:
```swift
private func checkForPendingPhantomRestart() {
    // Conditions: phantom detected + window ended (60s) + quiet period (30s) + not throttled (120s)
    if timeSinceRestart > 60.0 && timeSinceLastEvent > 30.0 && timeSinceLastRestartRequest > 120.0 {
        await restartMonitoring(reason: "delayed phantom recovery", force: true)
    }
}
```

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Modified `trackPhantomFloodForRestart()` - removed Darwin notification, just sets flags
  - Added `phantom_flood_last_event_time` tracking
- `ScreenTimeService.swift`:
  - Added `phantomCheckTimer` property
  - Added `startPhantomCheckTimer()`, `stopPhantomCheckTimer()`, `checkForPendingPhantomRestart()`
  - Timer starts when monitoring starts, stops when monitoring stops

**Expected Flow:**
```
1. App restart triggers phantom flood (t=0)
2. Extension blocks rapid-fire events (PHANTOM_SKIP)
3. Extension sets phantom_flood_detected=true (NO immediate restart)
4. Phantom flood ends around t=5-10s
5. Phantom window continues until t=60s
6. Main app timer checks at t=30, t=60, t=90...
7. At t=90+: conditions met, main app triggers restart
8. New session starts with fresh thresholds (min.1-60)
9. Any catch-up for new session blocked (rapid-fire in new phantom window)
10. After new phantom window (t=150s+), real usage generates events
11. Events recorded normally with INCREMENT
```

**Test Result:** ❌ PARTIAL

**Initial Success:**
- Phantom flood (111+ events) correctly blocked during phantom window (t=49-53s)
- `phantom_flood_detected` flag set, NO immediate restart
- Timer polled at t=90s (throttle not cleared), t=120s (all conditions met)
- Delayed restart triggered at t=120s with fresh 540 thresholds

**Production Failure (Feb 4, 2026 - 23:40):**
- Phantom flood arrived at t=126-131s (AFTER phantom window ended)
- `isInPhantomWindow=false` so events bypassed PHANTOM_SKIP filter
- All rapid-fire events (0-9s cadence) recorded with INCREMENT
- Usage inflated from 12060s to 12420s+ in seconds

**Root cause:** The filter required `isInPhantomWindow && isRapidFire`. Events outside the 60s window with rapid-fire cadence were not blocked.

---

### Attempt 8: Block All Rapid-Fire 🔄 TESTING
**Date:** February 4, 2026
**Approach:** Block rapid-fire events REGARDLESS of phantom window timing

**Key insight:** Real usage always arrives at ~60s cadence. Rapid-fire events (<10s apart) are ALWAYS phantom, no matter when they arrive.

**Implementation:**
```swift
// === RAPID-FIRE PHANTOM DETECTION ===
// Block rapid-fire events regardless of phantom window
// Real usage arrives at ~60s cadence; rapid-fire (<10s) is always phantom
if isRapidFire && timeSinceLastEvent >= 0 {
    let skipReason = isInPhantomWindow
        ? "PHANTOM_SKIP (in window)"
        : "LATE_PHANTOM_SKIP (outside window)"
    debugLog("🛡️ \(skipReason): rapid-fire (\(Int(timeSinceLastEvent))s cadence) at \(Int(timeSinceRestart))s since restart", defaults: defaults)
    defaults.set(nowTimestamp, forKey: lastEventTimeKey)
    trackPhantomFloodForRestart(defaults: defaults)
    return false
}
```

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Lines 354-367: Changed `isInPhantomWindow && isRapidFire` to just `isRapidFire`
  - Added LATE_PHANTOM_SKIP log message for events outside phantom window

**Test Result:** ✅ PARTIAL (blocks rapid-fire, but first phantom leaks)

---

### Attempt 9: Session Boundary Detection ✅ SUCCESS
**Date:** February 4, 2026
**Approach:** Block events with >100s gap during phantom window (session boundary = first phantom)

**Key insight:** The first phantom event of a flood has a large timeSinceLastEvent (>100s) because it's the first event after restart.

**Result:** ✅ Blocks first phantom events in most cases

---

### Attempt 10: Cross-App Phantom Detection ✅ SUCCESS
**Date:** February 4, 2026
**Approach:** Block events from different apps if <55s gap (user can't use multiple apps simultaneously)

**Implementation:** Track `last_recorded_appID` and block cross-app events within 55s.

**Result:** ✅ Blocks cross-app phantom events

---

### Attempt 11: Background Timer Fix ✅ SUCCESS
**Date:** February 5, 2026
**Approach:** Add `RunLoop.common` mode to phantom check timer so it runs when app is backgrounded

**Problem:** Delayed restart wasn't happening when app was backgrounded (1+ hour delay).

**Fix:** Added `RunLoop.current.add(timer, forMode: .common)` to `startPhantomCheckTimer()` in ScreenTimeService.swift.

**Result:** ✅ Timer now runs in background

---

### Attempt 12: Event Buffering with Flood Detection 🔄 TESTING
**Date:** February 5, 2026
**Approach:** Buffer events and wait to see if rapid-fire follows before recording

**Problem:** First phantom event of a flood still leaks because it looks legitimate (arrives after 55s with 92s gap - passes all filters).

**Key insight:** Phantom floods are characterized by rapid-fire events. The first phantom looks legitimate, but is always followed by rapid-fire. We can catch it retroactively.

**Solution:**
1. **Filter 1:** `timeSinceRestart < 55s` → BLOCK (can't have 60s usage in <55s)
2. **Filter 2:** `timeSinceLastRecordedEvent < 55s` → BLOCK (thresholds are 60s apart)
3. **Buffer:** Events passing filters 1&2 are buffered, not recorded immediately
4. **Validate:** If rapid-fire follows within 15s → discard buffer (phantom flood)
5. **Flush:** If no rapid-fire or INTERVAL_END → record buffer as legitimate

**Implementation:**
- Added buffer helper functions: `bufferEvent()`, `clearBuffer()`, `flushBufferedEvent()`
- Added `recordValidatedUsage()` - actual recording logic extracted
- Added `triggerPostRecordActions()` - re-arm, shields, CloudKit sync
- Modified `setUsageToThreshold()` - simplified to 2 filters + buffer system
- Modified `intervalDidEnd()` - flush buffer when monitoring ends
- Modified `recordUsageEfficiently()` - handle buffered events

**New UserDefaults Keys:**
- `phantom_buffer_appID` - buffered event's app
- `phantom_buffer_threshold` - buffered event's threshold
- `phantom_buffer_timestamp` - when event was buffered
- `phantom_buffer_eventName` - for re-arm signaling
- `last_recorded_timestamp` - for cadence check against recorded events

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Lines 101-110: `intervalDidEnd` flushes buffer
  - Lines 275-365: Simplified `setUsageToThreshold` with 2 filters + buffer
  - Lines 498-645: Added buffer functions and `recordValidatedUsage`

**Test Result:** ✅ SUCCESS (with refinements in Attempt 13)

---

### Attempt 13: Require 3+ Rapid Events Before Discarding Buffer ✅ SUCCESS
**Date:** February 6, 2026
**Approach:** Only discard buffered event when 3+ rapid-fire events follow (not just 1-2)

**Problem:** Buffer was being discarded after just 1 rapid-fire event. But sometimes iOS delivers events out-of-order (e.g., min.5 then min.4). This caused legitimate events to be discarded.

**Key insight:**
- 1-2 rapid events = could be out-of-order delivery
- 3+ rapid events = real phantom flood

**Implementation:**
```swift
// In CADENCE_BLOCK section:
if bufferTimestamp > 0 {
    let timeSinceBuffer = nowTimestamp - bufferTimestamp
    if timeSinceBuffer < 15.0 {
        let rapidCount = defaults.integer(forKey: "rapid_fire_count_since_buffer") + 1
        defaults.set(rapidCount, forKey: "rapid_fire_count_since_buffer")

        if rapidCount >= 3 {
            // 3+ rapid events = real flood, discard buffer
            debugLog("🚨 PHANTOM_FLOOD: \(rapidCount) rapid events - discarding buffer")
            clearBuffer(defaults: defaults)
        } else {
            // 1-2 rapid events = might be out-of-order, keep buffer
            debugLog("⚠️ RAPID_EVENT: count=\(rapidCount)/3 (keeping buffer)")
        }
    }
}
```

**New UserDefaults Key:**
- `rapid_fire_count_since_buffer` - counts rapid events since buffer was created

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Lines ~336-356: Added rapid-fire counting in CADENCE_BLOCK
  - Lines ~373-388: Added rapid-fire counting in buffer validation
  - `bufferEvent()`: Reset counter when new buffer created

**Test Result:** ✅ SUCCESS - Out-of-order events no longer cause buffer discard

---

### Attempt 14: Retry Logic for Monitoring Restart ✅ SUCCESS
**Date:** February 6, 2026
**Approach:** Add retry mechanism to `restartMonitoring()` with exponential backoff

**Problem:** After phantom flood detection triggered a monitoring restart, the restart could fail silently, leaving monitoring stopped permanently. User observed INTERVAL_END but no INTERVAL_START.

**Root Cause:** `scheduleActivity()` could throw an error, and there was no retry mechanism. Monitoring stayed stopped forever.

**Implementation:**
```swift
func restartMonitoring(reason: String, force: Bool = false) async {
    stopMonitoring()

    // Retry up to 3 times with exponential backoff
    var lastError: Error?
    for attempt in 1...3 {
        do {
            try scheduleActivity()
            isMonitoring = true
            return  // Success

        } catch {
            lastError = error
            print("[ScreenTimeService] ⚠️ Restart attempt \(attempt)/3 failed: \(error)")

            if attempt < 3 {
                // Wait before retry (exponential backoff: 1s, 2s)
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
    }

    // All retries failed - set flag for UI notification
    if let error = lastError {
        print("[ScreenTimeService] ❌ CRITICAL: Failed after 3 attempts: \(error)")
        defaults.set(true, forKey: "monitoring_restart_failed")
    }
}
```

**Files Modified:**
- `ScreenTimeService.swift`:
  - `restartMonitoring()`: Added retry loop with exponential backoff

**Test Result:** ✅ SUCCESS - Monitoring reliably restarts after phantom flood

---

### Performance: Faster Phantom Restart Timing
**Date:** February 6, 2026
**Approach:** Optimize delayed restart timing for faster recovery

**Problem:** After phantom flood ended, monitoring took ~85 seconds to restart (30s timer + 55s wait).

**Changes:**
| Setting | Before | After |
|---------|--------|-------|
| Timer interval | 30s | 15s |
| Quiet period | 30s | 20s |
| Throttle | 120s | 90s |
| **Max delay** | ~85s | **~35s** |

**Files Modified:**
- `ScreenTimeService.swift`:
  - `startPhantomCheckTimer()`: Changed interval from 30.0 to 15.0
  - `checkForPendingPhantomRestart()`: Changed quiet period from 30.0 to 20.0, throttle from 120.0 to 90.0

**Test Result:** ✅ SUCCESS - Restart happens within ~35s after flood ends

---

### Attempt 15: Block Phantom Usage for Locked Reward Apps 🔄 TESTING
**Date:** February 6, 2026
**Approach:** If a reward app is locked (shielded), any usage events are phantom

**Problem:** User observed reward apps getting usage recorded despite being LOCKED. This shouldn't happen - if an app is locked with a shield, the user cannot use it.

**Key insight:** If `managedSettingsStore.shield.applications` contains the app's token, it's locked. Any usage events for a locked app are phantom events from iOS catching up on old thresholds.

**Implementation:**
```swift
/// Check if a reward app is currently locked (shielded)
private nonisolated func isRewardAppLocked(appID: String, defaults: UserDefaults) -> Bool {
    // Check if this is a reward app
    let category = defaults.string(forKey: "map_\(appID)_category") ?? "Unknown"
    guard category == "Reward" else { return false }

    // Get token from extensionShieldConfigs and check if in shields
    guard let data = defaults.data(forKey: "extensionShieldConfigs"),
          let configs = try? JSONDecoder().decode(ExtensionShieldConfigsMinimal.self, from: data),
          let goalConfig = configs.goalConfigs.first(where: { $0.rewardAppLogicalID == appID }),
          let token = try? PropertyListDecoder().decode(ApplicationToken.self, from: goalConfig.rewardAppTokenData) else {
        return false
    }

    let currentShields = managedSettingsStore.shield.applications ?? Set()
    return currentShields.contains(token)
}

// In setUsageToThreshold(), after CADENCE_BLOCK:
if isRewardAppLocked(appID: appID, defaults: defaults) {
    debugLog("🔒 LOCKED_REWARD_BLOCK: \(appID.prefix(8))... is locked - usage is phantom")
    trackPhantomFloodForRestart(defaults: defaults)
    return false
}
```

**Filter Order (Updated):**
1. MONITORING_GAP_BLOCK - timeSinceRestart < 55s
2. CADENCE_BLOCK - timeSinceLastRecorded < 55s
3. **LOCKED_REWARD_BLOCK** - reward app is shielded (NEW)
4. DUPLICATE_SKIP - same threshold as last recorded
5. BUFFER/VALIDATE - queue event for validation

**Files Modified:**
- `DeviceActivityMonitorExtension.swift`:
  - Added `isRewardAppLocked()` helper function
  - Added LOCKED_REWARD_BLOCK filter in `setUsageToThreshold()`

**Test Result:** 🔄 PENDING

---

## Key Files Reference

| File | Path | Purpose |
|------|------|---------|
| Extension | `ScreenTimeRewardsProject/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | Threshold event handling |
| Service | `ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift` | Monitoring setup |
| ViewModel | `ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` | Monitoring coordination |

---

## Testing Protocol

1. **Clean Install:** Delete app, reinstall
2. **Setup:** Configure a learning app for monitoring
3. **Baseline:** Verify initial usage = 0
4. **Test A - Normal Usage:** Use learning app for 3 min → verify ~180s recorded
5. **Test B - Trigger Phantom:** Rebuild app in Xcode, launch
6. **Test C - Verify No Inflation:** Usage should still be ~180s
7. **Test D - Post-Phantom Usage:** Use app 2 more min
8. **Test E - Verify Recording Resumed:** Usage should be ~300s (+120s)

**Success Criteria:**
- Test C: No inflation → READY FOR TESTING (Universal Threshold Guard)
- Test E: Usage increases for genuinely new usage (threshold > currentToday) → READY FOR TESTING

---

## Current Solution: Multi-Layer Phantom Protection (Attempts 12-15)

**Core principle:** Multiple layers of protection with event buffering and locked app detection.

**Filter Hierarchy:**
| Priority | Filter | Condition | Action |
|----------|--------|-----------|--------|
| 1 | Monitoring Gap | `timeSinceRestart < 55s` | BLOCK immediately |
| 2 | Event Cadence | `timeSinceLastRecordedEvent < 55s` | BLOCK immediately |
| 3 | Locked Reward | Reward app is shielded | BLOCK immediately |
| 4 | Duplicate Skip | `threshold == lastThreshold` | SKIP |
| 5 | Buffer Check | Event passes 1-4 | Buffer → validate later |

**Buffer Validation:**
- If 3+ rapid-fire events follow within 15s → discard buffer (phantom flood)
- If 1-2 rapid-fire events → keep buffer (could be out-of-order)
- If no rapid-fire → flush buffer as legitimate
- On INTERVAL_END → flush buffer (monitoring ends = legitimate)

**Monitoring Restart:**
- Phantom flood detected → flag set, no immediate restart
- Main app polls every 15s for restart conditions
- Restart when: phantom detected + window ended (60s) + quiet period (20s)
- Retry up to 3 times with exponential backoff on failure

**Why previous approaches failed:**
| Attempt | Approach | Failure Mode |
|---------|----------|--------------|
| 1-4 | Block phantoms | iOS consumes thresholds, no new events |
| 5 | SET semantics | Under-counts (thresholds are per-session) |
| 5b | Cadence INCREMENT | iOS consumes thresholds, no new events |
| 6 | Block + Immediate Restart | Creates restart loop |
| 7 | Delayed Restart | Late phantom floods bypass window filter |
| 8-10 | Rapid-fire + boundaries | First phantom with 92s gap leaks |
| 11 | Background timer | Timer didn't run when backgrounded |
| 12 | Event buffering | Buffer discarded after 1 rapid event |

**Current protection (Attempts 12-15):**
1. Event buffering with flood detection (Attempt 12)
2. Require 3+ rapid events before discarding buffer (Attempt 13)
3. Retry logic for monitoring restart (Attempt 14)
4. Block phantom usage for locked reward apps (Attempt 15)

---

## Notes

- Thresholds are static (min.1-60), not dynamically re-armed
- Once iOS "delivers" min.1-60, no more events fire until restart
- Main app polls every 15s to detect when delayed restart is needed
- Restart conditions: phantom detected + window ended (60s) + quiet period (20s)
- Restart retry: up to 3 attempts with 1s, 2s exponential backoff
- Locked reward apps: any usage for shielded apps is blocked as phantom
