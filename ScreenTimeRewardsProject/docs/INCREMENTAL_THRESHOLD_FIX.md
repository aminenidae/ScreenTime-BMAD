# CRITICAL FIX: Incremental Thresholds for Continuous Tracking

## Problem Summary

The app increments usage time explosively (398 events in seconds, jumping from 0 to 23,880 seconds) after the first real minute of usage.

## Root Cause

**DeviceActivity tracks CUMULATIVE daily usage per ApplicationToken, not per-session usage.**

### What's Happening Now (BROKEN):

```
Timeline with FIXED 1-minute threshold:
─────────────────────────────────────────────────────────────
Time 0:00   Start monitoring with 1-min threshold
Time 1:00   User actually uses app for 1 minute
            → DeviceActivity total usage: 1 min
            → Threshold (1 min) reached → Fires ✅
            → Extension records 60s
            → Main app restarts monitoring with 1-min threshold again

Time 1:00   DeviceActivity checks: total usage (1 min) ≥ threshold (1 min)?
            → YES! → Fires IMMEDIATELY 🔴
            → Extension records another 60s
            → Main app restarts monitoring with 1-min threshold again

Time 1:00   DeviceActivity checks: total usage (1 min) ≥ threshold (1 min)?
            → YES! → Fires IMMEDIATELY AGAIN 🔴
            → INFINITE LOOP: 398 threshold events in seconds!
            → Phantom usage: 398 × 60s = 23,880 seconds recorded
```

**Why this happens:**
- DeviceActivity remembers cumulative usage for the day
- Each restart uses the SAME 1-minute threshold
- Since the app already has ≥1 minute usage, the threshold fires instantly
- Extension records the usage BEFORE main app's dedup filter runs
- Result: Endless loop of instant threshold fires

## The Solution: INCREMENTAL Thresholds

Track total expected usage and increment the threshold on EACH restart:

```
Timeline with INCREMENTAL thresholds:
─────────────────────────────────────────────────────────────
Time 0:00   Start monitoring, threshold = 60s (1 min)
Time 1:00   User actually uses app for 1 minute
            → DeviceActivity total: 60s ≥ threshold (60s) → Fires ✅
            → Extension records 60s
            → Restart with threshold = 120s (2 min cumulative)

Time 2:00   User uses app for another minute
            → DeviceActivity total: 120s ≥ threshold (120s) → Fires ✅
            → Extension records 60s
            → Restart with threshold = 180s (3 min cumulative)

Time 3:00   User uses app for another minute
            → DeviceActivity total: 180s ≥ threshold (180s) → Fires ✅
            → Extension records 60s
            → Restart with threshold = 240s (4 min cumulative)
```

**Key difference:** Each threshold is HIGHER than the last, so DeviceActivity must wait for ADDITIONAL usage before firing.

---

## Implementation Plan

### Option A: Incremental Thresholds (Recommended - Accurate)

Track cumulative expected usage and increment thresholds dynamically.

**File**: `ScreenTimeService.swift`

#### Step 1: Add Cumulative Usage Tracking

Add new properties (around line 30-60):

```swift
// Track cumulative expected usage per app (logicalID → total seconds we've accounted for)
private var cumulativeExpectedUsage: [String: TimeInterval] = [:]
private let incrementSeconds: TimeInterval = 60  // Track in 1-minute increments
private let cumulativeTrackingKey = "cumulativeExpectedUsage"
```

#### Step 2: Initialize on Monitoring Start

In `startMonitoring()` (around line 1112-1148):

```swift
func startMonitoring(completion: @escaping (Result<Void, ScreenTimeServiceError>) -> Void) {
    requestPermission { [weak self] result in
        guard let self else { return }
        switch result {
        case .success:
            // Load existing cumulative tracking (preserves across app restarts)
            self.loadCumulativeTracking()
            NSLog("[ScreenTimeService] 📂 Loaded cumulative tracking for \(self.cumulativeExpectedUsage.count) apps")

            do {
                try self.scheduleActivity()
                self.isMonitoring = true
                self.startMonitoringRestartTimer()
                self.startHealthMonitoring()

                // Persist monitoring state
                if let sharedDefaults = UserDefaults(suiteName: self.appGroupIdentifier) {
                    sharedDefaults.set(true, forKey: "wasMonitoringActive")
                    sharedDefaults.synchronize()
                }

                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.isMonitoring = false
                DispatchQueue.main.async {
                    completion(.failure(.monitoringFailed(error)))
                }
            }
        case .failure(let error):
            self.isMonitoring = false
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
}
```

#### Step 3: Use Cumulative Thresholds in Event Generation

Modify `regenerateMonitoredEvents()` (around line 1230-1268):

```swift
private func regenerateMonitoredEvents(refreshUsageCache: Bool) {
    guard !monitoredApplicationsByCategory.isEmpty else {
        NSLog("[ScreenTimeService] ⚠️ No monitored applications available to generate events")
        return
    }

    var eventIndex = 0

    monitoredEvents = monitoredApplicationsByCategory.reduce(into: [:]) { result, entry in
        let (category, applications) = entry
        guard !applications.isEmpty else { return }

        for app in applications {
            let logicalID = app.logicalID

            // Calculate CUMULATIVE threshold based on what we've already recorded
            let currentExpected = cumulativeExpectedUsage[logicalID] ?? 0
            let nextThreshold = currentExpected + incrementSeconds

            NSLog("[ScreenTimeService] 📊 Event for \(app.displayName):")
            NSLog("[ScreenTimeService]   Already expected: \(Int(currentExpected))s")
            NSLog("[ScreenTimeService]   Next threshold: \(Int(nextThreshold))s (cumulative)")

            // Use stable event names (no generation numbers needed)
            let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex)")
            eventIndex += 1

            result[eventName] = MonitoredEvent(
                name: eventName,
                category: category,
                threshold: DateComponents(second: Int(nextThreshold)),  // CUMULATIVE threshold!
                applications: [app]
            )
        }
    }

    NSLog("[ScreenTimeService] ✅ Generated \(monitoredEvents.count) events with INCREMENTAL thresholds")
    saveEventMappings()

    if refreshUsageCache {
        reloadAppUsagesFromPersistence()
    }
}
```

#### Step 4: Update Cumulative Tracking When Threshold Fires

Modify `handleEventThresholdReached()` (around line 1984-2011):

```swift
fileprivate func handleEventThresholdReached(_ event: DeviceActivityEvent.Name, timestamp: Date = Date()) {
    NSLog("[ScreenTimeService] ⏰ Event threshold reached: \(event.rawValue) at \(timestamp)")

    guard let configuration = monitoredEvents[event] else {
        NSLog("[ScreenTimeService] ❌ No configuration found for event \(event.rawValue)")
        return
    }

    NSLog("[ScreenTimeService] Found configuration for \(configuration.applications.count) apps")

    // Get the cumulative threshold that just fired
    let cumulativeThreshold = seconds(from: configuration.threshold)

    // Update cumulative tracking for each app
    for app in configuration.applications {
        let logicalID = app.logicalID
        let previousExpected = cumulativeExpectedUsage[logicalID] ?? 0

        // Set cumulative expected to the threshold that just fired
        cumulativeExpectedUsage[logicalID] = cumulativeThreshold

        NSLog("[ScreenTimeService] 📊 \(app.displayName) cumulative tracking:")
        NSLog("[ScreenTimeService]   Previous: \(Int(previousExpected))s")
        NSLog("[ScreenTimeService]   Current: \(Int(cumulativeThreshold))s")
        NSLog("[ScreenTimeService]   Increment: \(Int(cumulativeThreshold - previousExpected))s")
    }

    // Save cumulative tracking
    saveCumulativeTracking()

    // Record the INCREMENT (not the full threshold)
    lastEventTimestamp = timestamp
    recordUsage(for: configuration.applications, duration: incrementSeconds, endingAt: timestamp, eventTimestamp: timestamp)

    // Restart to set NEXT incremental threshold
    Task {
        await restartMonitoring()
    }
}
```

#### Step 5: Persist/Load Cumulative Tracking

Add these methods to `ScreenTimeService`:

```swift
private func saveCumulativeTracking() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
        NSLog("[ScreenTimeService] ⚠️ Cannot save cumulative tracking - no app group access")
        return
    }

    defaults.set(cumulativeExpectedUsage, forKey: cumulativeTrackingKey)
    defaults.synchronize()

    NSLog("[ScreenTimeService] 💾 Saved cumulative tracking:")
    for (logicalID, expected) in cumulativeExpectedUsage {
        NSLog("[ScreenTimeService]   \(logicalID): \(Int(expected))s")
    }
}

private func loadCumulativeTracking() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
          let saved = defaults.dictionary(forKey: cumulativeTrackingKey) as? [String: TimeInterval] else {
        NSLog("[ScreenTimeService] No cumulative tracking found, starting fresh")
        cumulativeExpectedUsage.removeAll()
        return
    }

    cumulativeExpectedUsage = saved

    NSLog("[ScreenTimeService] 📂 Loaded cumulative tracking:")
    for (logicalID, expected) in cumulativeExpectedUsage {
        NSLog("[ScreenTimeService]   \(logicalID): \(Int(expected))s")
    }
}

// Reset when stopping monitoring
func stopMonitoring() {
    deviceActivityCenter.stopMonitoring(activityNames)
    stopMonitoringRestartTimer()
    stopHealthMonitoring()
    pendingRestartWorkItem?.cancel()
    isMonitoring = false

    // DON'T reset cumulative tracking here - preserve it across monitoring sessions
    // Only reset on explicit user action (new day, reset button, etc.)

    if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
        sharedDefaults.set(false, forKey: "wasMonitoringActive")
        sharedDefaults.synchronize()
    }
}

// Add method to reset at start of new day
func resetDailyTracking() {
    cumulativeExpectedUsage.removeAll()
    saveCumulativeTracking()
    NSLog("[ScreenTimeService] 🔄 Reset cumulative tracking for new day")
}
```

#### Step 6: Reset Cumulative Tracking at Midnight

Add daily reset (call this from app delegate or similar):

```swift
// In AppDelegate or main app startup
private func setupMidnightReset() {
    NotificationCenter.default.addObserver(
        forName: .NSCalendarDayChanged,
        object: nil,
        queue: .main
    ) { _ in
        NSLog("[App] 🌅 New day started, resetting cumulative tracking")
        ScreenTimeService.shared.resetDailyTracking()
    }
}
```

---

### Option B: Extension-Side Timestamp Guard (Simpler, Less Accurate)

If incremental thresholds are too complex, prevent phantom usage in the extension itself:

**File**: `DeviceActivityMonitorExtension.swift`

Modify `recordUsageFromEvent()` (around line 362-383):

```swift
private nonisolated func recordUsageFromEvent(_ event: DeviceActivityEvent.Name) throws {
    NSLog("[EXTENSION] 📝 Reading event mapping for: \(event.rawValue)")
    let mapping = try readEventMapping(for: event)

    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
        NSLog("[EXTENSION] ❌ Cannot access app group")
        throw ExtensionMonitorError.appGroupUnavailable
    }

    // CHECK: When was this app last recorded?
    let lastRecordedKey = "lastRecorded_\(mapping.logicalID)"
    let lastRecorded = defaults.double(forKey: lastRecordedKey)
    let now = Date().timeIntervalSince1970
    let timeSinceLastRecord = now - lastRecorded

    // If recorded less than 55 seconds ago, skip (phantom threshold fire)
    if lastRecorded > 0 && timeSinceLastRecord < 55 {
        NSLog("[EXTENSION] ⏭️ SKIPPING \(mapping.displayName) - last recorded \(Int(timeSinceLastRecord))s ago (< 55s cooldown)")
        NSLog("[EXTENSION] This is a phantom threshold fire from DeviceActivity's cumulative tracking")
        return  // Don't record!
    }

    NSLog("[EXTENSION] ✅ Recording usage for \(mapping.displayName)")
    NSLog("[EXTENSION]   Last recorded: \(lastRecorded > 0 ? "\(Int(timeSinceLastRecord))s ago" : "never")")
    NSLog("[EXTENSION]   Logical ID: \(mapping.logicalID)")
    NSLog("[EXTENSION]   Threshold: \(mapping.thresholdSeconds)s")
    NSLog("[EXTENSION]   Reward points/min: \(mapping.rewardPointsPerMinute)")

    // Record usage
    usagePersistence.recordUsage(
        logicalID: mapping.logicalID,
        additionalSeconds: mapping.thresholdSeconds,
        rewardPointsPerMinute: mapping.rewardPointsPerMinute,
        displayName: mapping.displayName,
        category: mapping.category
    )

    // Update last recorded timestamp
    defaults.set(now, forKey: lastRecordedKey)
    defaults.synchronize()

    NSLog("[EXTENSION] ✅ Usage recorded to persistent storage!")
}
```

**Pros**:
- Simple, one function change
- Blocks phantom usage immediately
- Works with existing main app code

**Cons**:
- Less accurate (uses time-based cooldown vs. actual usage tracking)
- May miss legitimate usage if thresholds fire too quickly
- Doesn't prevent the DeviceActivity threshold spam (just ignores it)

---

## Recommendation

**Use Option A (Incremental Thresholds)** because:
1. ✅ Accurate - tracks exactly how much usage we've accounted for
2. ✅ Prevents the problem at the source (DeviceActivity won't fire instantly)
3. ✅ Scales properly (works for any app, any category)
4. ✅ No arbitrary cooldown timers

**Use Option B (Extension Guard)** only if:
- Option A is too complex to implement quickly
- You need a fast temporary fix
- Testing shows Option A doesn't work on all iOS versions

---

## Testing Instructions

### After implementing Option A:

1. **Reset state**:
   - Stop monitoring
   - Clear cumulative tracking in app group defaults
   - Delete all usage data
   - Start monitoring fresh

2. **Run learning app for 5 minutes continuously**

3. **Expected logs**:
```
[ScreenTimeService] ✅ Generated 11 events with INCREMENTAL thresholds
[ScreenTimeService] 📊 Event for Unknown App 2:
[ScreenTimeService]   Already expected: 0s
[ScreenTimeService]   Next threshold: 60s (cumulative)

... 1 minute passes ...

[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[EXTENSION]   Event: usage.app.2
[ScreenTimeService] ⏰ Event threshold reached: usage.app.2
[ScreenTimeService] 📊 Unknown App 2 cumulative tracking:
[ScreenTimeService]   Previous: 0s
[ScreenTimeService]   Current: 60s
[ScreenTimeService]   Increment: 60s
[ScreenTimeService] ✅ Monitoring restarted

[ScreenTimeService] 📊 Event for Unknown App 2:
[ScreenTimeService]   Already expected: 60s
[ScreenTimeService]   Next threshold: 120s (cumulative)  ← INCREMENTED!

... 1 minute passes ...

[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[ScreenTimeService] ⏰ Event threshold reached: usage.app.2
[ScreenTimeService] 📊 Unknown App 2 cumulative tracking:
[ScreenTimeService]   Previous: 60s
[ScreenTimeService]   Current: 120s
[ScreenTimeService]   Increment: 60s

... repeats every minute for 5 minutes total
```

4. **Verify in UI**:
   - Exactly 5 minutes recorded (300 seconds)
   - Exactly 50 points earned (5 × 10 points/min)
   - No phantom usage jumps

### After implementing Option B:

**Expected logs**:
```
[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[EXTENSION] ✅ Recording usage for Unknown App 2
[EXTENSION]   Last recorded: never

... 1 second later (phantom fire) ...

[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[EXTENSION] ⏭️ SKIPPING Unknown App 2 - last recorded 1s ago (< 55s cooldown)

... 1 second later (phantom fire) ...

[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[EXTENSION] ⏭️ SKIPPING Unknown App 2 - last recorded 2s ago (< 55s cooldown)

... continues skipping until 60 seconds pass ...

[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[EXTENSION] ✅ Recording usage for Unknown App 2
[EXTENSION]   Last recorded: 61s ago
```

---

## Success Criteria

✅ Exactly 5 threshold events fire (one per minute) for 5-minute test
✅ Usage increments by exactly 60 seconds per event
✅ Total usage = 300 seconds (5 minutes)
✅ No phantom usage jumps (23,880 seconds)
✅ Sequence numbers increment normally (1, 2, 3, 4, 5 - not 398!)

---

## Files to Modify

### Option A (Recommended):
- `ScreenTimeRewards/Services/ScreenTimeService.swift`
  - Add `cumulativeExpectedUsage` property
  - Modify `startMonitoring()` to load tracking
  - Modify `regenerateMonitoredEvents()` to use cumulative thresholds
  - Modify `handleEventThresholdReached()` to update tracking
  - Add `saveCumulativeTracking()` and `loadCumulativeTracking()`
  - Add `resetDailyTracking()`

### Option B (Simpler):
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
  - Modify `recordUsageFromEvent()` to check timestamp and skip if < 55s

---

## Timeline

**Option A**: 2-3 hours implementation + 1 hour testing
**Option B**: 30 minutes implementation + 30 minutes testing

**Recommend starting with Option B for quick fix, then implementing Option A for production.**
