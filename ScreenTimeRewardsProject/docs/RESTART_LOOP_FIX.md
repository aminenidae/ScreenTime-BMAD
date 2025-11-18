# Restart Loop Fix - Continuous Tracking Implementation

## Problem Statement

The app only records 1-2 minutes of usage time instead of continuous tracking during a 5-minute test session.

### Observed Symptoms

1. **Restart triggered but not completing**: Logs show `🔁 Restarting monitoring after usage notification (continuous loop)` but NO completion logs (`✅ Monitoring restarted`)
2. **No extension logs**: No `[EXTENSION]` logs appear in Console.app after the first threshold event
3. **Deduplication occurring**: `⚠️ Deduped Unknown App 2 - last event 37.48s ago` suggests events are firing but being filtered
4. **Only 1-2 threshold events total**: Expected 5 events (one per minute), got only 1-2

### User's Test Scenario
- Ran 1 learning app for 5 minutes
- Expected: 5 minutes recorded (5 separate 1-minute threshold events)
- Actual: Only 1-2 minutes recorded

---

## Root Cause Analysis

### ✅ RESOLVED: Task Execution (Was Issue #1)

**Status**: FIXED by adding logging - Task IS executing correctly

**Evidence from latest logs**:
```
[ScreenTimeService] 🔁 INSIDE restart Task - executing...
[ScreenTimeService] 🔁 restartMonitoring() called
[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: manual
```
Task execution is working! Moving to next issue...

---

### 1. Authorization Check Failing (NEW PRIMARY ISSUE) 🔴

**Location**: `ScreenTimeService.swift:1330-1348` (executeMonitorRestart)

**Problem**: The restart Task executes successfully BUT fails authorization check:

**Evidence from logs**:
```
[ScreenTimeService] 🔁 INSIDE restart Task - executing...
[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: manual
[ScreenTimeService] ❌ Authorization not granted, cannot restart  ← CRITICAL FAILURE
[ScreenTimeService] 🔁 restartMonitoring() completed
```

**Root Cause**: The `authorizationGranted` boolean property is `false` when restart attempts, even though:
- Monitoring was initially started (requires authorization)
- First threshold fired successfully
- App is still running

**Why this happens**:
1. `authorizationGranted` is a simple `@Published var authorizationGranted = false` property
2. It gets set to `true` only when `requestPermission()` succeeds during initial monitoring start
3. It's NOT re-verified or persisted across app lifecycle events
4. Something is resetting it to `false` (app backgrounding, view reloading, or instance recreation)
5. When restart runs, the guard fails and monitoring never restarts

**Impact**:
- Restart loop breaks completely
- No new monitoring sessions can start
- Only the FIRST threshold event can fire (initial session)
- Subsequent minutes never get tracked

### 2. Event Generation Number Mismatch

**Location**: `ScreenTimeService.swift:1238-1257`

```swift
restartGeneration &+= 1  // Increments on every restart
var eventIndex = 0

monitoredEvents = monitoredApplicationsByCategory.reduce(into: [:]) { result, entry in
    // ...
    let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex).gen.\(restartGeneration)")
    // ...
}
```

**Problem**: Each restart creates NEW event names:
- First monitoring session: `usage.app.0.gen.1`, `usage.app.1.gen.1`, etc.
- After restart #1: `usage.app.0.gen.2`, `usage.app.1.gen.2`, etc.
- After restart #2: `usage.app.0.gen.3`, `usage.app.1.gen.3`, etc.

**Issue**: Extension might fire old event names (gen.1) that no longer exist in the event mappings, causing them to be ignored.

### 3. High Memory Pressure

**Location**: Extension Diagnostics shows `19.8 MB / 6 MB limit`

**Problem**: Extension using 3x the allowed memory
- iOS may be killing the extension process
- Explains why no `[EXTENSION]` logs appear after first event
- Extension can't fire subsequent thresholds if it's been terminated

### 4. Async Timing Issues

**Flow Analysis**:
1. Extension fires threshold event
2. Posts Darwin notification → Main app
3. Main app processes shared usage data
4. Main app triggers restart (`Task { await restartMonitoring() }`)
5. ❌ Task may not execute before function returns
6. No restart actually happens
7. No new threshold events can fire

---

## Implementation Plan

### Fix 1: Remove Authorization Check from Restart (CRITICAL - Top Priority) 🔴

**Problem**: The `authorizationGranted` boolean is unreliable and blocks restarts

**File**: `ScreenTimeService.swift:1330-1348` (executeMonitorRestart)

**Current Code**:
```swift
private func executeMonitorRestart(reason: String) async {
    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: \(reason)")

    guard authorizationGranted else {
        NSLog("[ScreenTimeService] ❌ Authorization not granted, cannot restart")
        return
    }

    // ... rest of restart logic
}
```

**Fix - Option A (RECOMMENDED): Verify authorization status instead of using cached boolean**

```swift
private func executeMonitorRestart(reason: String) async {
    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: \(reason)")

    // Check actual authorization status instead of relying on cached boolean
    let authStatus = AuthorizationCenter.shared.authorizationStatus
    NSLog("[ScreenTimeService] 🔐 Current authorization status: \(authStatus.rawValue)")

    guard authStatus == .approved else {
        NSLog("[ScreenTimeService] ❌ Authorization status not approved: \(authStatus.rawValue)")
        NSLog("[ScreenTimeService] ❌ Cannot restart monitoring without authorization")
        return
    }

    NSLog("[ScreenTimeService] ✅ Authorization verified, proceeding with restart")

    pendingRestartWorkItem?.cancel()
    NSLog("[ScreenTimeService] 🔁 Stopping current monitoring...")
    deviceActivityCenter.stopMonitoring(activityNames)
    NSLog("[ScreenTimeService] ✅ Monitoring stopped")

    // ... rest of restart logic
}
```

**Fix - Option B (SIMPLER): Remove the guard entirely**

Since monitoring is already running (proven by threshold events firing), authorization MUST be granted. Remove the check:

```swift
private func executeMonitorRestart(reason: String) async {
    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: \(reason)")

    // Skip authorization check - if we're restarting, authorization was already granted
    // (Monitoring couldn't have started in the first place without it)
    NSLog("[ScreenTimeService] 🔁 Assuming authorization (restart only called when monitoring active)")

    pendingRestartWorkItem?.cancel()
    NSLog("[ScreenTimeService] 🔁 Stopping current monitoring...")
    deviceActivityCenter.stopMonitoring(activityNames)
    NSLog("[ScreenTimeService] ✅ Monitoring stopped")

    NSLog("[ScreenTimeService] 🔁 Regenerating monitored events...")
    regenerateMonitoredEvents(refreshUsageCache: false)
    NSLog("[ScreenTimeService] ✅ Events regenerated")

    do {
        NSLog("[ScreenTimeService] 🔁 Scheduling new activity...")
        try scheduleActivity()
        NSLog("[ScreenTimeService] ✅ Activity scheduled successfully")
        NSLog("[ScreenTimeService] ✅ Monitoring restarted (\(reason))")
    } catch {
        NSLog("[ScreenTimeService] ❌ Failed to restart monitoring (\(reason)): \(error)")
        NSLog("[ScreenTimeService] ❌ Error type: \(type(of: error))")
        NSLog("[ScreenTimeService] ❌ Error details: \(String(describing: error))")
    }

    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() EXIT")
}
```

**Recommendation**: Use **Option B** (simpler) because:
1. If monitoring is running, authorization MUST have been granted
2. The restart is only called when `isMonitoring == true`
3. Removes dependency on unreliable `authorizationGranted` property
4. Simpler code path

**Additional Safety Check** (Optional):

If you want to keep a safety check, update `authorizationGranted` on app foreground:

**File**: `ScreenTimeService.swift:819-827` (handleAppDidBecomeActive)

```swift
@objc private func handleAppDidBecomeActive() {
    // Re-verify authorization status when app becomes active
    let authStatus = AuthorizationCenter.shared.authorizationStatus
    authorizationGranted = (authStatus == .approved)
    NSLog("[ScreenTimeService] 🔐 App active - authorization status: \(authStatus.rawValue), granted: \(authorizationGranted)")

    processSharedUsageData(reason: "app_active")

    // Restart monitoring when app becomes active (catches return from background or termination)
    if isMonitoring {
        NSLog("[ScreenTimeService] 🔁 App became active - restarting monitoring to reset thresholds")
        Task {
            await restartMonitoring()
        }
    }
}
```

---

### Fix 2: ✅ COMPLETED - Task Execution Logging

**Status**: Already implemented and working

**File**: `ScreenTimeService.swift:1047-1052`

**Current Code**:
```swift
if reason == "usage_notification" && isMonitoring {
    NSLog("[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)")
    Task {
        await restartMonitoring()
    }
}
```

**Fix**: Add comprehensive logging and ensure execution:

```swift
if reason == "usage_notification" && isMonitoring {
    NSLog("[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)")
    NSLog("[ScreenTimeService] 🔁 Creating restart Task...")

    Task { @MainActor in
        NSLog("[ScreenTimeService] 🔁 INSIDE restart Task - executing...")
        await restartMonitoring()
        NSLog("[ScreenTimeService] 🔁 Restart Task completed")
    }

    NSLog("[ScreenTimeService] 🔁 Restart Task created")
}
```

**Alternative (More Reliable)**:
```swift
if reason == "usage_notification" && isMonitoring {
    NSLog("[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)")

    // Use detached task with explicit error handling
    Task.detached { [weak self] in
        guard let self = self else {
            NSLog("[ScreenTimeService] ❌ Self deallocated before restart")
            return
        }
        NSLog("[ScreenTimeService] 🔁 Executing restart...")
        await self.restartMonitoring()
        NSLog("[ScreenTimeService] 🔁 Restart completed successfully")
    }
}
```

### Fix 3: ✅ COMPLETED - Detailed Logging Throughout Restart Chain

**Status**: Already implemented and working

**File**: `ScreenTimeService.swift:1168-1170`

**Current Code**:
```swift
func restartMonitoring() async {
    await executeMonitorRestart(reason: "manual")
}
```

**Fix**:
```swift
func restartMonitoring() async {
    NSLog("[ScreenTimeService] 🔁 restartMonitoring() called")
    await executeMonitorRestart(reason: "manual")
    NSLog("[ScreenTimeService] 🔁 restartMonitoring() completed")
}
```

**File**: `ScreenTimeService.swift:1330-1348`

**Current Code**:
```swift
private func executeMonitorRestart(reason: String) async {
    guard authorizationGranted else { return }
    pendingRestartWorkItem?.cancel()
    NSLog("[ScreenTimeService] 🔁 Restarting monitoring (\(reason))")
    deviceActivityCenter.stopMonitoring(activityNames)
    regenerateMonitoredEvents(refreshUsageCache: false)

    do {
        try scheduleActivity()
        // ...
        NSLog("[ScreenTimeService] ✅ Monitoring restarted (\(reason))")
    } catch {
        NSLog("[ScreenTimeService] ❌ Failed to restart monitoring (\(reason)): \(error)")
    }
}
```

**Fix**: Add more granular logging:

```swift
private func executeMonitorRestart(reason: String) async {
    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: \(reason)")

    guard authorizationGranted else {
        NSLog("[ScreenTimeService] ❌ Authorization not granted, cannot restart")
        return
    }

    pendingRestartWorkItem?.cancel()
    NSLog("[ScreenTimeService] 🔁 Stopping current monitoring...")
    deviceActivityCenter.stopMonitoring(activityNames)
    NSLog("[ScreenTimeService] ✅ Monitoring stopped")

    NSLog("[ScreenTimeService] 🔁 Regenerating monitored events...")
    regenerateMonitoredEvents(refreshUsageCache: false)
    NSLog("[ScreenTimeService] ✅ Events regenerated (generation: \(restartGeneration))")

    do {
        NSLog("[ScreenTimeService] 🔁 Scheduling new activity...")
        try scheduleActivity()
        NSLog("[ScreenTimeService] ✅ Activity scheduled successfully")

        // DISABLED: Timer-based restarts don't work reliably in background
        // Using lifecycle-based restarts instead (app foreground + usage notifications)
        // if isMonitoring {
        //     startMonitoringRestartTimer()
        // }
        NSLog("[ScreenTimeService] ✅ Monitoring restarted (\(reason))")
    } catch {
        NSLog("[ScreenTimeService] ❌ Failed to restart monitoring (\(reason)): \(error)")
        NSLog("[ScreenTimeService] ❌ Error type: \(type(of: error))")
        NSLog("[ScreenTimeService] ❌ Error details: \(String(describing: error))")
    }

    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() EXIT")
}
```

### Fix 4: Prevent Concurrent Restarts (Optional - Not Critical)

**File**: `ScreenTimeService.swift` (add new property)

Add a flag to prevent multiple concurrent restarts:

```swift
// Add to class properties
private var isRestarting = false
private let restartQueue = DispatchQueue(label: "com.screentimerewards.restart", qos: .userInitiated)
```

**File**: `ScreenTimeService.swift:1330-1348`

Wrap restart logic with synchronization:

```swift
private func executeMonitorRestart(reason: String) async {
    NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: \(reason)")

    guard authorizationGranted else {
        NSLog("[ScreenTimeService] ❌ Authorization not granted, cannot restart")
        return
    }

    // Prevent concurrent restarts
    if isRestarting {
        NSLog("[ScreenTimeService] ⚠️ Restart already in progress, skipping duplicate request")
        return
    }

    isRestarting = true
    defer {
        isRestarting = false
        NSLog("[ScreenTimeService] 🔓 Restart lock released")
    }

    NSLog("[ScreenTimeService] 🔒 Restart lock acquired")

    // ... rest of the implementation ...
}
```

### Fix 5: Restore Generation-Based Event Names (CRITICAL REVISION)

**Problem**: Stable event names (`usage.app.X`) cause DeviceActivity to replay cached usage immediately after each restart. The OS never forgets that `usage.app.5` already hit 60 seconds earlier in the day, so it fires again instantly—even with the learning app closed.

**Solution**: Reintroduce generation numbers so every restart uses unique event identifiers, forcing DeviceActivity to treat each session as new. Preserve mappings for the previous generation to avoid extension misses during transitions.

**Implementation**:

1. **Re-add generation suffixes**
    ```swift
    restartGeneration &+= 1
    var eventIndex = 0

    let currentGeneration = restartGeneration
    monitoredEvents = monitoredApplicationsByCategory.reduce(into: [:]) { result, entry in
        let (category, applications) = entry
        guard !applications.isEmpty else { return }
        let threshold = currentThresholds[category] ?? defaultThreshold

        for app in applications {
            let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex).gen.\(currentGeneration)")
            eventIndex += 1
            result[eventName] = MonitoredEvent(
                name: eventName,
                category: category,
                threshold: threshold,
                applications: [app]
            )
        }
    }
    ```

2. **Dual-generation mappings**
    - When saving event mappings, keep entries for the most recent two generations.
    - Structure: `{ "usage.app.5.gen.42": { ... }, "usage.app.5.gen.41": { ... } }`
    - On regenerate, drop anything older than the previous generation.
    - Store the current `restartGeneration` in the shared defaults so both app and extension know which generation is “active.”

3. **Extension safeguards**
    - Read the `currentRestartGeneration` value from app group defaults.
    - If an incoming event’s generation is older than `currentGeneration - 1`, log and skip it instead of writing phantom minutes.
    - Optionally add a warning log (`"[EXTENSION] ⚠️ Stale event generation, skipping"`).

**Why this helps**:
- Each restart now creates fresh event identities, so DeviceActivity waits for real usage before firing.
- Keeping the prior generation’s mappings prevents the extension from failing during the restart window.
- Skipping stale generations blocks leftover notifications from re-crediting usage.

---

## ⚠️ NEW FINDINGS AFTER IMPLEMENTING GENERATION SUFFIXES

Despite the generation-specific identifiers, the minute counter still explodes immediately after the first learning minute. Logs show:

- First usage notification processed with `currentSequence = 398` while `lastReceivedSequence = 0`, meaning the extension had already emitted ~398 threshold events before the app synced at all.
- Every event handler reports `⚠️ Deduped Unknown App 2 - last event 0.xs ago`, proving that DeviceActivity fires the next threshold almost instantly after each restart.
- The extension persists each event **before** the main app dedup runs, so Unknown App 2’s total jumps from 0 → 23 880 s even though the handler records “0 apps”.
- Stale notifications (`usage.app.5.gen.6`, `.gen.8`, etc.) still arrive long after the main app advances to `.gen.10+`, and there are no `[EXTENSION] ⚠️ Skipping stale event` logs. This indicates the extension either never reads `currentRestartGeneration` or the guard isn’t triggering, so it continues crediting obsolete generations.

### Updated Diagnosis

1. **DeviceActivity doesn’t reset usage per token even with new event names.** Once a token accrues 1 minute in a day, every subsequent monitoring session fires immediately unless the extension refuses to write.
2. **Extension skips aren’t active.** Without rejecting stale events, the shared usage store keeps receiving 60‑second deltas on every restart loop, and `usageNotificationSequence` skyrockets (398, 399, …).
3. **Main app dedup is too late.** Even when the handler “records 0 apps,” the UI still shows new minutes because `processSharedUsageData` merges whatever the extension already persisted.

### Next Steps (Not yet implemented)

1. **Verify extension guard:** ensure `currentRestartGeneration` is written before the extension fires, and add explicit logging inside the check so we can confirm when events are skipped vs. processed.
2. **Implement per-token “cooldown” in the extension:** even if DeviceActivity fires immediately, the extension should refuse to write if the last recorded timestamp for that logical ID is < 55 s ago.
3. **Reconsider DeviceActivity strategy:** if the framework truly replays the cached minute for every restart, we may need to adopt the alternative approach (poll-based tracking or using BackgroundTasks) to avoid phantom increments.

### Fix 6: Reduce Extension Memory Usage (Lower Priority)

**File**: `DeviceActivityMonitorExtension.swift:159-180`

**Current Issue**: Extension using 19.8 MB (3x the 6 MB limit)

**Optimizations**:

1. **Reduce Heartbeat Frequency**:
```swift
private nonisolated func startHeartbeatTimer() {
    heartbeatTimer?.invalidate()
    // Changed from 30s to 60s to reduce overhead
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.writeHeartbeat()
    }
    writeHeartbeat()
}
```

2. **Remove Debug Logging in RELEASE**:
```swift
override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    #if DEBUG
    NSLog("[EXTENSION] ⏰ eventDidReachThreshold FIRED!")
    NSLog("[EXTENSION]   Event: \(event.rawValue)")
    NSLog("[EXTENSION]   Activity: \(activity.rawValue)")
    #endif

    writeHeartbeat()
    let memoryMB = getMemoryUsageMB()

    #if DEBUG
    NSLog("[EXTENSION]   Memory: \(String(format: "%.1f", memoryMB)) MB")
    #endif

    // ... rest of implementation
}
```

3. **Lazy Load Event Mappings** (if needed):
Only read event mappings when needed, don't cache them in memory.

### Fix 7: ✅ COMPLETED - Darwin Notification Flow Logging

**Status**: Already implemented and working

**File**: `ScreenTimeService.swift:995-1014`

Ensure usage notifications are being received properly:

```swift
private func handleUsageSequenceNotification(sharedDefaults: UserDefaults) {
    NSLog("[ScreenTimeService] 📨 Received usage sequence notification")

    let currentSequence = sharedDefaults.integer(forKey: "usageNotificationSequence")
    NSLog("[ScreenTimeService] 📨 Current sequence: \(currentSequence), Last received: \(lastReceivedSequence)")

    if currentSequence > 0 && lastReceivedSequence > 0 {
        let missedCount = currentSequence - lastReceivedSequence - 1
        NSLog("[ScreenTimeService] 📨 Sequence check: missed \(missedCount) notifications")

        if missedCount > 0 {
            NSLog("[ScreenTimeService] ⚠️ Detected \(missedCount) missed usage notifications")
            NotificationCenter.default.post(
                name: .missedUsageNotifications,
                object: nil,
                userInfo: ["missed_count": missedCount]
            )
            recordNotificationGap(missedCount: missedCount)
        }
    }

    lastReceivedSequence = currentSequence
    NSLog("[ScreenTimeService] 📨 Processing shared usage data...")
    processSharedUsageData(reason: "usage_notification")
    NSLog("[ScreenTimeService] 📨 Usage notification processed")
}
```

---

## Testing Instructions

### 1. Build and Install
```bash
# Clean build
rm -rf ~/Library/Developer/Xcode/DerivedData/ScreenTimeRewards-*
xcodebuild clean -project ScreenTimeRewardsProject/ScreenTimeRewards.xcodeproj

# Build and install
xcodebuild -project ScreenTimeRewardsProject/ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards -configuration Debug -sdk iphoneos -destination 'platform=iOS' build
```

### 2. Test Continuous Tracking

1. **Reset state**:
   - Stop monitoring
   - Clear all usage data
   - Start monitoring fresh

2. **Run learning app for 5 minutes continuously**

3. **Collect logs**:
   - Console.app: Filter for `ScreenTimeService` AND `EXTENSION`
   - Look for these key log patterns:

**Expected Success Pattern** (After Fix 1 Applied):
```
[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)
[ScreenTimeService] 🔁 Creating restart Task...
[ScreenTimeService] 🔁 Restart Task created
[ScreenTimeService] 🔁 INSIDE restart Task - executing...
[ScreenTimeService] 🔁 restartMonitoring() called
[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: manual
[ScreenTimeService] 🔁 Assuming authorization (restart only called when monitoring active)  ← NEW (Fix 1)
[ScreenTimeService] 🔁 Stopping current monitoring...
[ScreenTimeService] ✅ Monitoring stopped
[ScreenTimeService] 🔁 Regenerating monitored events...
[ScreenTimeService] ✅ Events regenerated  ← Should appear now!
[ScreenTimeService] 🔁 Scheduling new activity...
[ScreenTimeService] ✅ Activity scheduled successfully  ← Should appear now!
[ScreenTimeService] ✅ Monitoring restarted (manual)  ← Should appear now!
[ScreenTimeService] 🔁 executeMonitorRestart() EXIT
[ScreenTimeService] 🔁 restartMonitoring() completed
[ScreenTimeService] ⏰ Restart Task completed

[EXTENSION] ⏰ eventDidReachThreshold FIRED!
[EXTENSION]   Event: usage.app.2
[EXTENSION] ✅ Successfully recorded usage for event: usage.app.2

[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)
... (repeats every minute for 5 minutes = 5 total threshold events)
```

**Current Failure Pattern** (Before Fix 1):
```
[ScreenTimeService] 🔁 INSIDE restart Task - executing...
[ScreenTimeService] 🔁 restartMonitoring() called
[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: manual
[ScreenTimeService] ❌ Authorization not granted, cannot restart  ← PROBLEM
[ScreenTimeService] 🔁 restartMonitoring() completed
[ScreenTimeService] ⏰ Restart Task completed
```
No more threshold events fire after this!

4. **Verify in UI**:
   - Check that all 5 minutes are recorded
   - Verify points awarded correctly

### 3. Monitor Memory Usage

Check Extension Diagnostics view:
- Memory usage should be < 6 MB
- Heartbeat should update regularly
- No errors in error log

---

## Success Criteria

✅ **5 threshold events fire** (one per minute for 5-minute test)
✅ **All restart completion logs appear** (`✅ Monitoring restarted`)
✅ **Extension logs continue appearing** throughout test
✅ **Extension memory < 6 MB**
✅ **5 minutes recorded in UI** (not just 1-2)

---

## Rollback Plan

If issues persist after these fixes:

1. **Add Option C: Poll-Based Tracking**
   - Instead of relying on threshold events + restarts
   - Use a background timer to poll DeviceActivity usage every minute
   - More reliable but higher battery usage

2. **Investigate Apple Bug**
   - File feedback with Apple about DeviceActivityEvent threshold firing only once
   - Consider if this is an iOS bug or intended behavior

---

## Additional Notes

### Why Restarts Are Needed

Apple's `DeviceActivityEvent` thresholds **only fire ONCE per monitoring session**:
- When you start monitoring with a 1-minute threshold
- The threshold fires after 1 minute
- **It will NEVER fire again** until you restart monitoring

This is why continuous tracking requires:
1. Start monitoring (1-min threshold)
2. Wait 1 minute → threshold fires
3. **Restart monitoring** (reset threshold)
4. Wait 1 minute → threshold fires again
5. Repeat...

### Alternative Architecture Considered

**Background Task + DeviceActivityReport API**:
- Use Background Task to wake app periodically
- Query DeviceActivityReport for actual usage
- More accurate, no restart loop needed
- Downside: Requires iOS 17.4+, more complex

This could be explored if restart loop approach proves unreliable.

---

## Files Modified

### Critical Fix (Must Implement):

1. `ScreenTimeRewards/Services/ScreenTimeService.swift`
   - **Lines 1330-1348**: Remove/bypass `authorizationGranted` check in `executeMonitorRestart()` (FIX 1 - CRITICAL)

### Already Completed (From Previous Implementation):

1. `ScreenTimeRewards/Services/ScreenTimeService.swift`
   - Lines 1047-1052: Task execution logging ✅
   - Lines 1168-1170: restartMonitoring() logging ✅
   - Lines 995-1014: Usage notification logging ✅

### Optional Improvements (Lower Priority):

1. `ScreenTimeRewards/Services/ScreenTimeService.swift`
   - Lines 1238-1257: Remove generation numbers (Fix 5 - optional)
   - Lines 819-827: Re-verify authorization on app active (Fix 1 optional safety)
   - Add concurrency lock for restarts (Fix 4 - optional)

2. `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
   - Lines 232-235: Reduce heartbeat frequency (Fix 6)
   - Throughout: Wrap debug logs in #if DEBUG (Fix 6)

---

## Timeline

**Estimated Implementation**: 1-2 hours
**Testing**: 30 minutes
**Total**: 2-3 hours

---

## Questions for User

1. Do you prefer **Option A** (remove generation numbers) or **Option B** (use logical IDs) for stable event names?
2. Should we implement the concurrency lock (Fix 3) or is it overkill?
3. After these fixes, should we still explore the polling-based approach as a backup?
