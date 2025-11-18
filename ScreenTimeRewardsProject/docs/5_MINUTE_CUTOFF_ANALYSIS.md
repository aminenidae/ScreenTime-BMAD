# 5-Minute Tracking Cutoff Analysis

## Problem
App tracks usage correctly for 5 minutes, then stops tracking even though the learning app continues running for 7 minutes total.

## Most Likely Causes

### Cause 1: Monitoring Interval Ends at 5 Minutes 🔴 (MOST LIKELY)

**Hypothesis**: The DeviceActivitySchedule interval is ending after 5 minutes instead of continuing.

**Check in code** (`ScreenTimeService.swift` around line 1286-1299):

```swift
private func startMonitoringActivity(_ activity: DeviceActivityName, offsetSeconds: Int) throws {
    let calendar = Calendar.current
    let startDate = Date().addingTimeInterval(TimeInterval(offsetSeconds))
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)
    let endLimit = calendar.startOfDay(for: startDate).addingTimeInterval(24 * 60 * 60 - 1)
    // Use 1 hour interval (Apple requires minimum ~15 minutes, 70 seconds causes intervalTooShort error)
    let endDate = min(startDate.addingTimeInterval(3600), endLimit)  // ← 3600 = 1 hour
    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)

    // ...
}
```

**Problem**: If the monitoring session is created with a specific end time (1 hour), but the **last threshold exceeds that end time**, DeviceActivity won't fire it.

**Example**:
```
Start time: 10:00:00
End time: 10:00:00 + 3600s = 11:00:00
Thresholds: 60s, 120s, 180s, 240s, 300s, 360s, 420s

10:01:00 → Threshold 60s fires ✅
10:02:00 → Threshold 120s fires ✅
10:03:00 → Threshold 180s fires ✅
10:04:00 → Threshold 240s fires ✅
10:05:00 → Threshold 300s fires ✅
10:06:00 → Threshold 360s fires ✅ (if session still running)
10:07:00 → Threshold 420s fires ✅ (if session still running)
```

But if there's an issue with the monitoring session restarting, it might stop after 5 events.

---

### Cause 2: Incremental Threshold Calculation Bug 🟡

**Hypothesis**: The cumulative threshold calculation stops incrementing after 5 minutes.

**Possible bugs**:
1. `cumulativeExpectedUsage` not being updated correctly
2. Thresholds reaching a maximum value and stopping
3. Logic error in threshold increment calculation

**Check**: Look for these patterns in logs:
```
[ScreenTimeService] 📊 Event for Unknown App X:
[ScreenTimeService]   Already expected: 240s
[ScreenTimeService]   Next threshold: 300s (cumulative)
→ Fires at 5 minutes ✅

[ScreenTimeService] 📊 Event for Unknown App X:
[ScreenTimeService]   Already expected: 300s
[ScreenTimeService]   Next threshold: 360s (cumulative)
→ Should fire at 6 minutes, but doesn't ❌
```

**Potential code issues**:

1. **Not saving cumulative tracking after threshold fires**:
```swift
// In handleEventThresholdReached - might be missing saveCumulativeTracking()
for app in configuration.applications {
    cumulativeExpectedUsage[logicalID] = cumulativeThreshold
}
saveCumulativeTracking()  // ← Is this being called?
```

2. **Threshold calculation uses wrong value**:
```swift
// Should be:
let nextThreshold = currentExpected + incrementSeconds  // 300 + 60 = 360

// But might be:
let nextThreshold = currentExpected  // 300 (not incrementing!)
```

---

### Cause 3: Restart Loop Stops After 5 Iterations 🟡

**Hypothesis**: The restart mechanism stops working after 5 successful restarts.

**Possible reasons**:
1. Async race condition after 5 restarts
2. Resource exhaustion (too many Tasks created)
3. Authorization check starts failing again
4. `isMonitoring` flag gets set to `false`

**Check logs for**:
```
After 5th threshold:
[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)
[ScreenTimeService] 🔁 Creating restart Task...
[ScreenTimeService] 🔁 INSIDE restart Task - executing...
[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: manual
[ScreenTimeService] ❌ Authorization not granted, cannot restart  ← Fails again?
```

Or:
```
After 5th threshold:
[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)
... but no "Creating restart Task" log appears ← Task not being created
```

---

### Cause 4: Extension Timestamp Guard Too Aggressive 🟢 (Unlikely)

**Hypothesis**: If Option B (extension timestamp guard) was implemented, the 55-second cooldown might be blocking legitimate usage.

**Check in extension**:
```swift
// If this code exists in DeviceActivityMonitorExtension.swift:
if lastRecorded > 0 && timeSinceLastRecord < 55 {
    NSLog("[EXTENSION] ⏭️ SKIPPING - last recorded \(Int(timeSinceLastRecord))s ago")
    return
}
```

**Problem**: After 5 thresholds, something might cause the extension to start skipping all events.

---

### Cause 5: Event Mapping Not Updated After 5th Restart 🟡

**Hypothesis**: Event mappings stop being saved/updated correctly after a certain number of restarts.

**Check**:
```
After 5th restart:
[ScreenTimeService] ✅ Generated 11 events with INCREMENTAL thresholds
[ScreenTimeService] 💾 Saving X event mappings for extension:
... mappings listed ...

After 6th restart (if it happens):
[ScreenTimeService] ✅ Generated 11 events with INCREMENTAL thresholds
[ScreenTimeService] 💾 Saving X event mappings for extension:
... are mappings still being saved? ←
```

If event mappings aren't saved, the extension can't map event names to apps, so it silently fails.

---

## Diagnostic Steps

### Step 1: Get Console.app Logs

Filter for `ScreenTimeService` AND `EXTENSION` during the 7-minute test.

Look for:
1. How many threshold events actually fired (should be 7)
2. Cumulative threshold values (60, 120, 180, 240, 300, 360, 420)
3. Any errors after the 5th minute
4. Whether restarts are still happening after minute 5
5. Extension logs - are they still firing or silent after minute 5?

### Step 2: Check Cumulative Tracking Values

Add this logging to `regenerateMonitoredEvents`:

```swift
NSLog("[ScreenTimeService] 📊 CUMULATIVE TRACKING DUMP:")
for (logicalID, expected) in cumulativeExpectedUsage {
    NSLog("[ScreenTimeService]   \(logicalID): \(Int(expected))s expected")
}
```

Verify the values are: 0 → 60 → 120 → 180 → 240 → 300 → 360 → 420

### Step 3: Verify Monitoring Interval Doesn't End

Check logs for:
```
[EXTENSION] intervalDidEnd for activity: ScreenTimeTracking.primary
```

If this appears after 5 minutes, the monitoring session is ending prematurely.

---

## Likely Fixes

### Fix A: Ensure Cumulative Tracking Persists

**Problem**: `saveCumulativeTracking()` might not be called after threshold fires.

**Fix**: In `handleEventThresholdReached`, ensure we save:

```swift
fileprivate func handleEventThresholdReached(_ event: DeviceActivityEvent.Name, timestamp: Date = Date()) {
    // ... existing code ...

    // Update cumulative tracking
    for app in configuration.applications {
        let logicalID = app.logicalID
        cumulativeExpectedUsage[logicalID] = cumulativeThreshold
        NSLog("[ScreenTimeService] 📊 Updated cumulative for \(app.displayName): \(Int(cumulativeThreshold))s")
    }

    // CRITICAL: Save to persistent storage
    saveCumulativeTracking()  // ← MUST be called here!

    // Record usage
    recordUsage(for: configuration.applications, duration: incrementSeconds, endingAt: timestamp, eventTimestamp: timestamp)

    // Restart
    Task {
        await restartMonitoring()
    }
}
```

### Fix B: Extend Monitoring Interval

**Problem**: 1-hour interval might be ending early due to time calculations.

**Fix**: Use a longer interval or make it extend to end of day:

```swift
private func startMonitoringActivity(_ activity: DeviceActivityName, offsetSeconds: Int) throws {
    let calendar = Calendar.current
    let startDate = Date().addingTimeInterval(TimeInterval(offsetSeconds))
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)

    // End at midnight instead of +1 hour
    let endLimit = calendar.startOfDay(for: startDate).addingTimeInterval(24 * 60 * 60 - 1)
    let endDate = endLimit  // ← Go until midnight, not just +1 hour

    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)

    let schedule = DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: endComponents,
        repeats: false
    )
    // ...
}
```

### Fix C: Add Logging to Diagnose Restart Failures

**Problem**: Restarts might be failing silently after 5 iterations.

**Fix**: Add comprehensive logging:

```swift
private func processSharedUsageData(reason: String = "manual") {
    // ... existing code ...

    if didUpdateUsage {
        NSLog("[ScreenTimeService] 🔄 Synced usage from shared defaults (\(reason))")
        notifyUsageChange()

        if reason == "usage_notification" && isMonitoring {
            NSLog("[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)")
            NSLog("[ScreenTimeService] 🔁 isMonitoring: \(isMonitoring)")
            NSLog("[ScreenTimeService] 🔁 authorizationGranted: \(authorizationGranted)")
            NSLog("[ScreenTimeService] 🔁 Creating restart Task...")

            Task {
                NSLog("[ScreenTimeService] 🔁 INSIDE restart Task - executing...")
                await restartMonitoring()
                NSLog("[ScreenTimeService] 🔁 Restart Task completed")
            }

            NSLog("[ScreenTimeService] 🔁 Restart Task created")
        } else {
            NSLog("[ScreenTimeService] ℹ️ Not restarting - reason: \(reason), isMonitoring: \(isMonitoring)")
        }
    }
}
```

### Fix D: Check for Maximum Threshold Limit

**Problem**: There might be a maximum threshold value in the code.

**Fix**: Search for any threshold limits:

```bash
grep -n "threshold.*max\|max.*threshold" ScreenTimeService.swift
```

Remove any artificial limits:
```swift
// Bad:
if nextThreshold > 300 {  // ← Artificial 5-minute limit!
    return
}

// Good:
let nextThreshold = currentExpected + incrementSeconds  // No limit
```

---

## Expected Behavior After Fix

For a 7-minute test:

```
Minute 1: Threshold 60s fires, cumulative = 60s, restart with threshold 120s
Minute 2: Threshold 120s fires, cumulative = 120s, restart with threshold 180s
Minute 3: Threshold 180s fires, cumulative = 180s, restart with threshold 240s
Minute 4: Threshold 240s fires, cumulative = 240s, restart with threshold 300s
Minute 5: Threshold 300s fires, cumulative = 300s, restart with threshold 360s
Minute 6: Threshold 360s fires, cumulative = 360s, restart with threshold 420s
Minute 7: Threshold 420s fires, cumulative = 420s, restart with threshold 480s

Total usage: 420 seconds (7 minutes)
Total points: 70 points (7 × 10 points/min)
```

---

## Immediate Next Steps

1. **Get Console.app logs** for the 7-minute test
2. **Count threshold events** - should be 7, probably only 5
3. **Check cumulative values** - last value should be 300s (5 minutes)
4. **Look for interval end** - `intervalDidEnd` message
5. **Verify restart logs** - do restarts continue after minute 5?

Based on the logs, we can determine which fix to apply.

---

## Most Likely Root Cause (Prediction)

Based on the symptom "stops after exactly 5 minutes", I predict:

**Cause 2: Cumulative tracking not persisting correctly**

The cumulative threshold calculation works for the first 5 minutes, but then either:
- `saveCumulativeTracking()` stops being called
- The loaded value gets corrupted
- The threshold calculation breaks after reaching 300s

**Quick Test**: Add this to the top of `regenerateMonitoredEvents`:

```swift
NSLog("[ScreenTimeService] 🔍 DIAGNOSTIC: Cumulative tracking state:")
for (logicalID, expected) in cumulativeExpectedUsage {
    NSLog("[ScreenTimeService]   \(logicalID): \(Int(expected))s")
}
NSLog("[ScreenTimeService] 🔍 Total apps tracked: \(cumulativeExpectedUsage.count)")
```

If the 6th regeneration shows cumulative values stuck at 300s instead of incrementing to 360s, we've found the bug.
