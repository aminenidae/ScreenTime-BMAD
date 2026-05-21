# Phantom Event & Usage Inflation: Lessons Learned

**Date:** February 1, 2026
**Status:** Reverted to commit `ab3826e`
**Session Goal:** Fix usage recording stopping after phantom events

---

## 1. Problem Statement

### Primary Issue
After "phantom events" occur (iOS catch-up threshold events), the app stops recording new legitimate usage. Users can use learning apps for extended periods with no usage being recorded.

### Observed Behavior
1. App launches or monitoring restarts
2. iOS sends a flood of "catch-up" threshold events (phantom events)
3. These events are correctly filtered by `CASE_2 SKIP_RAPID` logic
4. **However**, after the phantom flood, iOS stops sending NEW threshold events
5. Result: Real usage goes unrecorded

### Secondary Issue (Discovered During Fix)
Any fix involving monitoring restart caused **usage inflation** - usage numbers increased on every app build/launch even without actual app usage.

---

## 2. Root Cause Analysis

### Why iOS Stops Sending Events After Phantom Flood

iOS's DeviceActivityMonitor has a fundamental behavior:
- **Each threshold event is sent ONLY ONCE per monitoring session**
- Example: `min.1`, `min.2`, `min.3`... each fires exactly once
- When phantom events flood in, they "consume" these thresholds
- iOS marks them as "already delivered" even though we filtered them
- New real usage won't trigger events because iOS thinks they were already sent

### The Threshold State Problem

```
Timeline:
1. User uses app for 5 min → iOS sends min.1, min.2, min.3, min.4, min.5 ✓
2. App restarts (rebuild, background kill, etc.)
3. iOS sends catch-up: min.1, min.2, min.3, min.4, min.5 (phantom flood)
4. Our code filters these correctly (SKIP_RAPID)
5. User continues using app → min.6, min.7, min.8...
6. iOS does NOT send these because it already "used up" thresholds 1-5
7. Result: No new usage recorded
```

### Why Restart Causes Inflation

When monitoring restarts:
1. iOS sends catch-up events for ALL accumulated usage
2. Our `lastThreshold` tracking gets out of sync with `currentToday`
3. Example state: `lastThreshold=120` but `currentToday=840`
4. Catch-up event with `threshold=180` passes check (`180 > 120`)
5. Event gets recorded as +60s even though it's not new usage
6. Each restart triggers another round of this inflation

---

## 3. Attempted Solutions

### Solution A: Extension-Based Monitoring Restart

**Approach:**
- Detect phantom flood in extension (5+ rapid events in 60s)
- Have extension directly call `DeviceActivityCenter.stopMonitoring()` then `startMonitoring()`
- This should reset iOS's "thresholds already fired" state

**Implementation:**
1. Added `trackPhantomEvent()` function to count rapid-fire events
2. Added `signalMonitoringRestartNeeded()` to restart monitoring from extension
3. Added `saveMonitoringTokens()` in main app to store ApplicationToken data for extension
4. Added phantom recovery check in `AppUsageViewModel.startMonitoring()`

**Result:** FAILED - Caused usage inflation on every restart

### Solution B: Grace Period After Restart

**Approach:**
- Add 30-second grace period after restart
- Skip phantom detection during grace period to prevent infinite restart loop

**Implementation:**
- Track `phantom_last_restart_time` timestamp
- Skip `trackPhantomEvent()` if within 30s of last restart

**Result:** FAILED - Still caused inflation (grace period didn't address root cause)

### Solution C: Manual Revert of Restart Logic

**Approach:**
- Remove all restart-related code additions
- Return to just filtering phantom events without restart

**Files Modified:**
- `DeviceActivityMonitorExtension.swift` - Removed `trackPhantomEvent()` call and both functions
- `ScreenTimeService.swift` - Removed `saveMonitoringTokens()` call and function
- `AppUsageViewModel.swift` - Removed phantom recovery check

**Result:** FAILED - Inflation still occurred (uncommitted changes discarded)

---

## 4. Why Each Solution Failed

### Extension Restart Approach
- **Problem:** Restarting monitoring triggers iOS to send catch-up events
- **Root Issue:** The `lastThreshold` vs `currentToday` mismatch means catch-up events with thresholds higher than `lastThreshold` get incorrectly recorded
- **Example:**
  - `lastThreshold = 120` (2 min seen)
  - `currentToday = 840` (14 min recorded)
  - Catch-up event `min.3` (threshold=180) arrives
  - Check: `180 > 120` → PASSES → records +60s (WRONG!)

### Grace Period Approach
- **Problem:** Grace period only prevents infinite restart loops
- **Doesn't Fix:** The underlying inflation issue where catch-up events pass threshold checks

### Manual Revert Approach
- **Problem:** By time we reverted, there were other phantom-related changes in the codebase
- **Commits Involved:**
  - `2c317a5` - First phantom protection (moved before threshold comparison)
  - `111f65c` - Threshold corruption fix
  - `ab3826e` - Current state
- **Result:** The existing phantom protection code still interacts with restart in ways that cause inflation

---

## 5. Key Insights

### iOS DeviceActivity Behavior
1. **Threshold events fire ONCE per session** - This is fundamental and cannot be changed
2. **Catch-up events are sent on reconnect** - iOS tries to "sync" state after extension reconnects
3. **Restarting monitoring resets threshold state** - But also triggers new catch-up flood

### Our Architecture Constraints
1. **Extension has no persistent memory** - State must be in UserDefaults
2. **`lastThreshold` and `currentToday` can desync** - Especially during restarts
3. **INCREMENT semantics compound errors** - Each +60s event is cumulative

### The Core Dilemma
- **To record new usage:** iOS needs to send new threshold events
- **iOS won't send new events:** Because it thinks thresholds were already delivered
- **To reset iOS state:** Must restart monitoring
- **Restarting causes:** Catch-up flood that inflates usage

---

## 6. Recommended Next Steps

### Option A: Eliminate lastThreshold/currentToday Mismatch

Before any restart logic, ensure these stay in sync:
```swift
// On day rollover or restart, set lastThreshold = currentToday / 60 * 60
// This way, catch-up events won't pass the threshold > lastThreshold check
```

### Option B: Use SET Semantics Instead of INCREMENT

Instead of `currentToday + 60`, use:
```swift
// Calculate expected usage from threshold
let expectedUsage = thresholdMinutes * 60
// Only update if it would increase usage (not decrease or stay same)
if expectedUsage > currentToday {
    currentToday = expectedUsage  // SET, not INCREMENT
}
```

This makes catch-up events idempotent - receiving `min.3` when you already have 180s recorded does nothing.

### Option C: Smarter Phantom Detection

Instead of counting rapid events, detect phantom floods by:
1. Check if `threshold < lastThreshold` (going backwards = catch-up)
2. If multiple "backwards" events in sequence, it's a phantom flood
3. After flood ends (no events for 5+ seconds), consider resetting

### Option D: Accept Phantom Event Consumption

Perhaps the solution isn't to restart monitoring, but to:
1. Accept that phantom events consume thresholds
2. Increase threshold count from 60 to 240 (cover 4 hours)
3. Let the natural "session reset" at day rollover clear the state

---

## 7. Files Involved

| File | Purpose |
|------|---------|
| `DeviceActivityMonitorExtension.swift` | Extension handling threshold events |
| `ScreenTimeService.swift` | Main app monitoring setup |
| `AppUsageViewModel.swift` | ViewModel coordinating monitoring |

### Key Functions
- `setUsageToThreshold()` - Core usage recording logic
- `CASE_1` - Duplicate detection
- `CASE_2` - Threshold decreased (catch-up filter)
- `CASE_3` - Normal progression (record +60s)

---

## 8. Current State

**Commit:** `ab3826e` ("Remove SQLite audit log, keep phantom filtering")

**What's Active:**
- Early phantom blocking (55s window after restart)
- SKIP_RAPID filter for rapid-fire events
- Threshold sanity check (reset if `lastThreshold > currentToday`)

**What's NOT Active:**
- Extension-based restart logic (reverted/never committed)
- SQLite audit log (removed)

---

## 9. Testing Protocol for Next Fix

1. **Clean Install:** Delete app, reinstall
2. **Setup:** Configure learning app with monitoring
3. **Baseline:** Note initial usage = 0
4. **Test A - Normal Usage:** Use learning app for 3 min, verify ~180s recorded
5. **Test B - Rebuild:** Rebuild app in Xcode, launch, verify NO inflation
6. **Test C - Background Kill:** Force kill app, relaunch, verify NO inflation
7. **Test D - Post-Phantom Usage:** After phantom events, use app 2 more min, verify usage increases

**Success Criteria:**
- Test A: Usage = ~180s
- Test B: Usage still = ~180s (no inflation)
- Test C: Usage still = ~180s (no inflation)
- Test D: Usage = ~300s (+120s recorded)
