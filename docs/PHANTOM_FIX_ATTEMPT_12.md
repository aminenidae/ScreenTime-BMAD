# Phantom Fix Attempt 12: Event Buffering with Flood Detection

## Problem Summary

Despite filters for rapid-fire (<10s), session boundary (>100s gap), and cross-app phantom events, some phantom events still leak through. The issue is that the **first phantom event** of a flood often looks legitimate (arrives after 55s from restart with a large gap).

**Key insight from user:** The defining characteristic of a phantom flood is the **rapid-fire pattern** - multiple events within seconds. We can use this to detect and discard the first phantom retroactively.

## Solution: Delayed Recording with Flood Detection

Instead of recording events immediately, **buffer them** and wait briefly to see if a phantom flood follows. If rapid-fire events arrive after the buffered event, it was phantom - discard it.

## Filter Hierarchy

| Priority | Filter | Condition | Action |
|----------|--------|-----------|--------|
| 1 | Monitoring Gap | `timeSinceRestart < 55s` | BLOCK immediately |
| 2 | Event Cadence | `timeSinceLastEvent < 55s` | BLOCK immediately |
| 3 | Buffered Flood | Event passes 1&2, but rapid-fire follows | Discard buffer |

**Rationale:**
- **Filter 1:** You cannot accumulate 60 seconds of app usage in less than 55 seconds after monitoring starts
- **Filter 2:** Threshold events fire every 60 seconds of usage - no legitimate event can fire within 55 seconds of the previous one
- **Filter 3:** If an event looks legitimate but is immediately followed by rapid-fire events, it was the first phantom of a flood

## Implementation Design

### State Variables (UserDefaults)

```swift
// Buffered event (waiting for flood check)
"phantom_buffer_appID"        // String: appID of buffered event
"phantom_buffer_threshold"    // Int: threshold seconds of buffered event
"phantom_buffer_timestamp"    // Double: when event was buffered
"phantom_buffer_eventName"    // String: original event name (for re-arm)

// Last recorded event (for cadence check)
"last_recorded_timestamp"     // Double: when last event was RECORDED (not received)
"last_recorded_appID"         // String: which app (already exists)
```

### Flow Diagram

```
Event arrives
    │
    ▼
┌─────────────────────────────────────┐
│ Filter 1: timeSinceRestart < 55s?   │
├──────────────┬──────────────────────┤
│ YES          │ NO                   │
│ BLOCK        │ Continue             │
└──────────────┴──────────┬───────────┘
                          ▼
┌─────────────────────────────────────┐
│ Filter 2: timeSinceLastEvent < 55s? │
│ (from last RECORDED event)          │
├──────────────┬──────────────────────┤
│ YES          │ NO                   │
│ BLOCK +      │ Continue             │
│ Check buffer │                      │
└──────────────┴──────────┬───────────┘
                          ▼
┌─────────────────────────────────────┐
│ Is there a buffered event?          │
├──────────────┬──────────────────────┤
│ YES          │ NO                   │
│              │                      │
│ How long     │ Buffer current event │
│ since buffer?│ (don't record yet)   │
│              │                      │
│ <15s = flood │                      │
│ discard both │                      │
│              │                      │
│ >=15s = OK   │                      │
│ record buffer│                      │
│ buffer new   │                      │
└──────────────┴──────────────────────┘
```

### Key Logic Changes

#### When Event is BLOCKED (Filter 1 or 2):

```swift
// If blocked as rapid-fire, check if there's a buffered event
if timeSinceLastEvent < 55.0 {
    // This is rapid-fire - might be phantom flood
    let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")
    if bufferTimestamp > 0 {
        let timeSinceBuffer = nowTimestamp - bufferTimestamp
        if timeSinceBuffer < 15.0 {
            // Rapid-fire within 15s of buffer = phantom flood!
            // Discard the buffered event
            debugLog("🚨 PHANTOM_FLOOD: discarding buffered event (rapid-fire \(Int(timeSinceBuffer))s after buffer)", defaults: defaults)
            clearBuffer(defaults: defaults)
        }
    }
    // Track for flood detection
    trackPhantomFloodForRestart(defaults: defaults)
    return false
}
```

#### When Event PASSES Filters:

```swift
// Event passed filters 1 and 2 - check buffer status
let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")

if bufferTimestamp > 0 {
    // There's a buffered event
    let timeSinceBuffer = nowTimestamp - bufferTimestamp

    if timeSinceBuffer < 15.0 {
        // New event too soon after buffer - both are phantom
        debugLog("🚨 PHANTOM_FLOOD: new event \(Int(timeSinceBuffer))s after buffer - discarding both", defaults: defaults)
        clearBuffer(defaults: defaults)
        // Buffer the new event (it might be legitimate if no flood follows)
        bufferEvent(appID: appID, threshold: thresholdSeconds, eventName: eventName, defaults: defaults)
        return false
    } else {
        // Buffer is old enough - record it as legitimate
        let bufferedAppID = defaults.string(forKey: "phantom_buffer_appID") ?? ""
        let bufferedThreshold = defaults.integer(forKey: "phantom_buffer_threshold")
        debugLog("✅ BUFFER_FLUSH: recording buffered event for \(bufferedAppID.prefix(8))... (\(Int(timeSinceBuffer))s ago)", defaults: defaults)
        recordBufferedEvent(defaults: defaults)
    }
}

// Buffer the current event (don't record yet)
bufferEvent(appID: appID, threshold: thresholdSeconds, eventName: eventName, defaults: defaults)
return false  // Will be recorded later when validated
```

#### On INTERVAL_END (Flush Remaining Buffer):

```swift
override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
    if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
        // Flush any buffered event - if monitoring ends without rapid-fire, it's legitimate
        let bufferTimestamp = defaults.double(forKey: "phantom_buffer_timestamp")
        if bufferTimestamp > 0 {
            debugLog("✅ INTERVAL_END_FLUSH: recording buffered event", defaults: defaults)
            recordBufferedEvent(defaults: defaults)
        }
        debugLog("INTERVAL_END activity=\(activity.rawValue) session=\(Self.sessionID)", defaults: defaults)
    }
}
```

### Helper Functions

```swift
/// Buffer an event for later validation
private nonisolated func bufferEvent(appID: String, threshold: Int, eventName: String, defaults: UserDefaults) {
    defaults.set(appID, forKey: "phantom_buffer_appID")
    defaults.set(threshold, forKey: "phantom_buffer_threshold")
    defaults.set(Date().timeIntervalSince1970, forKey: "phantom_buffer_timestamp")
    defaults.set(eventName, forKey: "phantom_buffer_eventName")
    debugLog("📦 BUFFERED: \(appID.prefix(8))... threshold=\(threshold)s", defaults: defaults)
}

/// Clear the buffer without recording
private nonisolated func clearBuffer(defaults: UserDefaults) {
    defaults.removeObject(forKey: "phantom_buffer_appID")
    defaults.removeObject(forKey: "phantom_buffer_threshold")
    defaults.removeObject(forKey: "phantom_buffer_timestamp")
    defaults.removeObject(forKey: "phantom_buffer_eventName")
}

/// Record the buffered event as legitimate usage
private nonisolated func recordBufferedEvent(defaults: UserDefaults) {
    guard let appID = defaults.string(forKey: "phantom_buffer_appID"),
          !appID.isEmpty else { return }

    let threshold = defaults.integer(forKey: "phantom_buffer_threshold")
    let eventName = defaults.string(forKey: "phantom_buffer_eventName") ?? ""

    // Record the usage (bypass filters - already validated)
    recordValidatedUsage(appID: appID, thresholdSeconds: threshold, eventName: eventName, defaults: defaults)

    // Clear buffer
    clearBuffer(defaults: defaults)

    // Update last recorded timestamp
    defaults.set(Date().timeIntervalSince1970, forKey: "last_recorded_timestamp")
}
```

## Edge Cases

### 1. User stops using app (buffer never validated)
**Solution:** Flush buffer on `INTERVAL_END`. If monitoring ends without rapid-fire, the buffered event was legitimate.

### 2. App backgrounded for long time, then resumed
**Solution:** If time since buffer > 15s when next event arrives, flush the buffer as legitimate.

### 3. First event of the day
**Solution:** Day rollover logic runs before buffering. First event still gets buffered but will be flushed as legitimate if no flood follows.

### 4. What if legitimate usage has 15s+ gaps?
**Answer:** That's fine! The 55s cadence filter ensures no event can fire within 55s of the previous. The 15s buffer window only applies to detecting phantom floods (which are rapid-fire by definition).

## Files to Modify

### `DeviceActivityMonitorExtension.swift`

1. **Add buffer helper functions** (around line 560):
   - `bufferEvent(appID:threshold:eventName:defaults:)`
   - `clearBuffer(defaults:)`
   - `recordBufferedEvent(defaults:)`
   - `recordValidatedUsage(appID:thresholdSeconds:eventName:defaults:)` - actual recording logic extracted

2. **Modify `setUsageToThreshold`** (lines 274-445):
   - Simplify phantom detection to just two filters:
     - `timeSinceRestart < 55s` → BLOCK
     - `timeSinceLastRecordedEvent < 55s` → BLOCK
   - Add buffer check/flush logic for events that pass filters
   - Events that pass filters get buffered, not recorded immediately

3. **Modify `intervalDidEnd`** (line 101-105):
   - Flush any buffered event when monitoring ends

4. **Add new UserDefaults keys**:
   - `phantom_buffer_appID`
   - `phantom_buffer_threshold`
   - `phantom_buffer_timestamp`
   - `phantom_buffer_eventName`
   - `last_recorded_timestamp`

## Verification Plan

### Test A: Normal Usage (No Phantom)
1. Start monitoring fresh
2. Use an app for 3+ minutes
3. **Expected:** First minute buffered, second minute flushes buffer + gets buffered, etc.
4. **Verify:** Usage accumulates correctly with ~15s delay

### Test B: Phantom Flood Detection
1. Trigger phantom flood (rebuild in Xcode while app in use)
2. **Expected:**
   - First phantom event buffered
   - Rapid-fire events trigger flood detection
   - Buffer discarded
   - Delayed restart flagged
3. **Verify:** No phantom usage recorded

### Test C: Edge Case - Buffer at INTERVAL_END
1. Use app for 1 minute
2. Stop using before second minute
3. Wait for INTERVAL_END
4. **Expected:** Buffered event flushed on INTERVAL_END
5. **Verify:** 1 minute recorded

### Test D: The 92s Leak Case
1. Simulate the scenario from the log (event at T+34s with 92s gap)
2. **Expected:** Blocked by Filter 1 (34s < 55s)
3. **Verify:** No leak

## Success Criteria

- [ ] No phantom events recorded during floods
- [ ] Legitimate usage recorded (with ~15s delay)
- [ ] First phantom event of flood is caught retroactively
- [ ] Buffer flushed correctly on INTERVAL_END
- [ ] Delayed restart still triggered for phantom floods
