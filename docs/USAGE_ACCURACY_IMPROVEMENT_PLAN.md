# Usage Accuracy Improvement Plan

## Problem Statement

The current `DeviceActivityMonitorExtension.swift` on main branch has **NO phantom filtering or deduplication logic**. It simply records every threshold event directly, leading to:

1. **Over-counting** from parallel extension processes
2. **Phantom events** after monitoring restarts
3. **Catch-up events** being recorded as real usage
4. **Duplicate events** from Apple's API firing multiple times

## Current State Analysis

### Main Branch Extension (229 lines)
- Records usage directly in `recordUsageFromEvent()`
- No timestamp tracking
- No lastThreshold comparison
- No phantom window checking
- No rapid-fire detection

### What We Need (from SQLite branch learnings)

The SQLite branch had sophisticated filtering that worked correctly for single-session usage:
- **Case 1**: Duplicate threshold detection
- **Case 2**: Threshold decrease handling (catch-up vs new session)
- **Case 3**: Normal progression recording
- **Phantom window**: 55-second grace period after restart
- **Rapid-fire filter**: Skip events <30s apart for same app

---

## Implementation Plan

### Branch Name
`feature/usage-accuracy-filters`

### Files to Modify

| File | Action |
|------|--------|
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | MAJOR REWRITE |

### Core Logic to Implement

#### 1. Add State Tracking Keys

```swift
// Per-app keys in shared UserDefaults
ext_usage_{appID}_today      // Today's total seconds
ext_usage_{appID}_date       // Date string (yyyy-MM-dd)
ext_lastThreshold_{appID}    // Last recorded threshold in seconds
usage_{appID}_lastEventTime  // Unix timestamp of last event
```

#### 2. Add Session/Restart Tracking

```swift
// Extension-level keys
extension_session_id         // UUID generated on extension init
extension_restart_timestamp  // When monitoring was restarted
```

#### 3. Implement setUsageToThreshold() Function

The core filtering logic:

```swift
func setUsageToThreshold(appID: String, thresholdSeconds: Int, ...) -> Bool {
    // NEW DAY CHECK
    if storedDate != today {
        // Reset counters, record 60s
        return true
    }

    // CASE 1: Duplicate threshold (threshold == lastThreshold)
    if thresholdSeconds == lastThreshold {
        return false  // Skip duplicate
    }

    // CASE 2: Threshold decreased (catch-up OR new session)
    if thresholdSeconds < lastThreshold {
        // Check 1: Within phantom window of restart → SKIP
        if timeSinceRestart < phantomWindowSeconds {
            return false
        }
        // Check 2: Rapid fire (<30s since last event) → SKIP
        if timeSinceLastEvent < 30.0 {
            return false
        }
        // Both passed: new session, reset lastThreshold
        lastThreshold = 0
    }

    // CASE 3: Normal progression (threshold > lastThreshold)
    // Record +60s usage
    return true
}
```

#### 4. Phantom Window Configuration

```swift
let phantomWindowSeconds: Double = 55.0  // Grace period after restart
```

- Events firing within 55s of monitoring restart are likely catch-up
- After 55s, events are likely real new usage

#### 5. Early Phantom Check (Before Full Logic)

```swift
// Quick check: if ALL apps fire catch-up events at once after restart
if timeSinceRestart < phantomWindowSeconds && restartTimestamp > 0 {
    // This is catch-up from monitoring restart, skip
    return false
}
```

---

## Implementation Steps

### Step 1: Create Branch
```bash
git checkout -b feature/usage-accuracy-filters
```

### Step 2: Add Helper Properties

Add to extension class:
- `sessionID`: Static UUID for current session
- Date formatter for yyyy-MM-dd format
- UserDefaults helper methods

### Step 3: Implement setUsageToThreshold()

Port the filtering logic from SQLite branch (without SQLite parts):
- Day rollover handling
- Case 1/2/3 threshold logic
- Phantom window filtering
- Rapid-fire detection

### Step 4: Update recordUsageFromEvent()

Replace direct recording with:
```swift
if setUsageToThreshold(appID: logicalID, thresholdSeconds: thresholdSeconds, ...) {
    // Update ext_ keys
    // Update lastThreshold
    // Record to persistence
}
```

### Step 5: Track Interval Start/End

```swift
override func intervalDidStart(for activity: DeviceActivityName) {
    // Record restart timestamp
    defaults.set(Date().timeIntervalSince1970, forKey: "extension_restart_timestamp")
}
```

---

## Key Design Decisions

### 1. UserDefaults-Only (No SQLite)

SQLite was abandoned because:
- Its UNIQUE constraint blocked legitimate new sessions
- No better cross-process sync than UserDefaults (via CFPreferences)
- Added complexity without solving the core problem

### 2. Accept Minor Phantom Events

Perfect deduplication across parallel processes is not achievable. We aim for:
- **90%+ accuracy** in normal usage
- **Zero under-counting** (never miss real usage)
- **Minor over-counting acceptable** (5-10% phantom in edge cases)

### 3. Conservative Filtering

When uncertain, **record the usage**. Over-counting is better than under-counting for a rewards app.

---

## Verification Tests

### Test 1: Single Session
- Use learning app for 5 minutes
- Expected: Records exactly 5 minutes (300s)
- Check: `ext_usage_{appID}_today` = 300

### Test 2: Multiple Sessions Same Day
- Session 1: Use app for 5 minutes → 300s recorded
- Close app, wait 2 minutes
- Session 2: Use app for 3 minutes → Should add 180s
- Expected total: 480s (8 minutes)

### Test 3: Phantom Rejection
- Use app for 2 minutes
- Force monitoring restart (background/foreground the main app)
- Check logs for "SKIP_RESTART" or phantom rejection
- Usage should NOT double

### Test 4: Parallel Process Dedup
- Monitor logs for parallel session IDs
- Same minute threshold should not record multiple times
- Look for "CASE_1_DUP" in logs

---

## Success Criteria

1. **Single session accuracy**: ±60s (one threshold event)
2. **Multi-session support**: Each session records correctly
3. **Phantom rejection**: No massive over-counting after restarts
4. **Debug visibility**: Clear logs showing filter decisions

---

## Rollback Plan

If issues arise:
1. The filtering can be disabled by removing the `setUsageToThreshold()` call
2. Direct recording (current behavior) continues working
3. No database dependencies to clean up

---

## Timeline

- Phase 1: Implement core filtering logic
- Phase 2: Test with single learning app
- Phase 3: Test multi-session scenarios
- Phase 4: Monitor in production for edge cases
