# Production Usage Tracking - Diagnosis and Implementation Plan

## Date: November 21, 2024

---

## Executive Summary

The app has two competing implementations for usage tracking:
1. **Original (81e901c)**: Continuous minute-by-minute tracking with JSON persistence (~16-21MB memory)
2. **Memory-Optimized (25a617b+)**: Threshold-based tracking with primitive key-value storage (<6MB memory)

The memory optimization inadvertently broke continuous tracking by switching to a sparse threshold system that only records usage at specific intervals (1, 5, 15, 60 minutes).

**Goal**: Combine the memory-efficient storage format with the continuous tracking mechanism.

---

## Part 1: Diagnosis

### 1.1 Original Implementation (81e901c) - Working Continuous Tracking

**Extension Architecture:**
```
DeviceActivityMonitorExtension
├── ExtensionUsagePersistence (embedded struct)
│   ├── PersistedApp (Codable struct)
│   ├── loadAllApps() → JSON decode from UserDefaults
│   └── saveAllApps() → JSON encode to UserDefaults
├── eventDidReachThreshold() → records 60s per event
└── Uses persistedApps_v3 key for storage
```

**How Continuous Tracking Works:**
1. ScreenTimeService sets up 1-minute threshold events for each app
2. When threshold fires, extension records 60s of usage
3. After recording, the system re-arms with a new threshold at (current + 1 minute)
4. This creates minute-by-minute tracking

**Memory Problem:**
- JSON encoding/decoding loads entire app dictionary into memory
- Codable structs with multiple fields consume significant memory
- Peak usage: 16-21MB (iOS limit is ~6MB for extensions)
- Result: Extension crashes on memory-constrained devices

### 1.2 Memory-Optimized Implementation (25a617b+) - Broken Tracking

**Extension Architecture:**
```
DeviceActivityMonitorExtension
├── No embedded structs (memory savings)
├── Direct UserDefaults access with primitive keys:
│   ├── map_{eventName}_id → app logical ID
│   ├── map_{eventName}_inc → increment seconds
│   ├── usage_{appID}_total → total seconds
│   └── usage_{appID}_today → today's seconds
└── eventDidReachThreshold() → reads primitives, updates counters
```

**What Went Wrong:**
1. Changed from continuous 1-minute thresholds to sparse [1, 5, 15, 60] minute thresholds
2. No re-arm mechanism after threshold fires
3. Threshold system designed for "milestone" tracking, not continuous tracking
4. Result: Only records at 1, 5, 15, 60 minute marks (massive gaps)

**Memory Success:**
- No JSON parsing = minimal memory allocation
- Primitive types only = predictable memory usage
- Target: <6MB achieved

### 1.3 Root Cause Analysis

| Aspect | Original | Memory-Optimized | Problem |
|--------|----------|------------------|---------|
| Storage Format | JSON (persistedApps_v3) | Primitives (map_*, usage_*) | Incompatible formats |
| Threshold Strategy | 1-min continuous | [1,5,15,60] sparse | Lost continuous tracking |
| Re-arm Mechanism | ✅ After each event | ❌ None | No follow-up tracking |
| Memory Usage | 16-21MB | <6MB | Original too heavy |

---

## Part 2: Implementation Plan

### 2.1 Design Goals

1. **Memory Efficient**: Stay under 6MB using primitive key-value storage
2. **Continuous Tracking**: Record usage every minute
3. **Re-arm Mechanism**: Automatically set next threshold after each event
4. **Backward Compatible**: Work with existing ScreenTimeService infrastructure

### 2.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main App                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  ScreenTimeService                        │   │
│  │  - Sets initial 1-minute thresholds for each app         │   │
│  │  - Stores mappings: map_{eventName}_id, map_{eventName}_inc │
│  │  - Reads usage: usage_{appID}_total, usage_{appID}_today  │   │
│  │  - Handles re-arm requests from extension                 │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ UserDefaults (App Group)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DeviceActivityMonitor Extension               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            eventDidReachThreshold()                       │   │
│  │  1. Read map_{eventName}_id → get appID                  │   │
│  │  2. Read map_{eventName}_inc → get increment (60s)       │   │
│  │  3. Update usage_{appID}_total += increment              │   │
│  │  4. Update usage_{appID}_today += increment              │   │
│  │  5. Write rearm_{appID}_requested = true                 │   │
│  │  6. Send Darwin notification to main app                 │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Darwin Notification
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Main App                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              handleUsageNotification()                    │   │
│  │  1. Read usage data from UserDefaults                    │   │
│  │  2. Check rearm_{appID}_requested flags                  │   │
│  │  3. For each flagged app:                                │   │
│  │     - Calculate new threshold (current + 1 minute)       │   │
│  │     - Update DeviceActivityCenter events                 │   │
│  │     - Clear rearm flag                                   │   │
│  │  4. Update UI                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Implementation Steps

#### Step 1: Modify DeviceActivityMonitorExtension.swift

Keep the memory-optimized structure but add re-arm signaling:

```swift
private nonisolated func recordUsageEfficiently(for eventName: String) {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

    // 1. Get mapping (existing code)
    guard let appID = defaults.string(forKey: "map_\(eventName)_id") else { return }
    let increment = defaults.integer(forKey: "map_\(eventName)_inc")
    guard increment > 0 else { return }

    // 2. Update usage counters (existing code)
    incrementUsage(appID: appID, seconds: increment)

    // 3. NEW: Signal re-arm request
    defaults.set(true, forKey: "rearm_\(appID)_requested")
    defaults.set(Date().timeIntervalSince1970, forKey: "rearm_\(appID)_time")
    defaults.synchronize()

    // 4. Notify main app (existing code)
    notifyMainApp()
}
```

#### Step 2: Modify ScreenTimeService.swift

Add re-arm handling in the notification handler:

```swift
func handleOptimizedUsageNotification() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

    // 1. Read updated usage data (existing)
    readOptimizedUsageData()

    // 2. NEW: Check for re-arm requests
    for (logicalID, _) in appUsages {
        if defaults.bool(forKey: "rearm_\(logicalID)_requested") {
            // Clear the flag
            defaults.set(false, forKey: "rearm_\(logicalID)_requested")

            // Re-arm with new threshold
            rearmThreshold(for: logicalID)
        }
    }

    defaults.synchronize()

    // 3. Update UI (existing)
    // ...
}

private func rearmThreshold(for logicalID: String) {
    // Get current usage
    let currentMinutes = getCurrentDailyUsageMinutes(for: logicalID)

    // Set new threshold at current + 1 minute
    let newThresholdMinutes = currentMinutes + 1

    // Update the event in DeviceActivityCenter
    // ... (implementation details)
}
```

#### Step 3: Modify Initial Threshold Setup

Change from [1, 5, 15, 60] sparse thresholds to single 1-minute threshold:

```swift
// BEFORE (broken):
let smartThresholds = [
    currentDailyUsageMinutes + 1,
    currentDailyUsageMinutes + 5,
    currentDailyUsageMinutes + 15,
    currentDailyUsageMinutes + 60
]

// AFTER (continuous):
let initialThreshold = currentDailyUsageMinutes + 1  // Just 1 minute ahead
```

### 2.4 Key Considerations

#### Memory Budget
- Extension memory limit: ~6MB
- Current optimized usage: ~3-4MB
- Re-arm flag storage: ~100 bytes per app
- Total with 50 apps: ~5KB additional
- **Verdict**: Well within budget

#### Re-arm Latency
- Darwin notification delivery: ~100ms
- Main app processing: ~50ms
- DeviceActivityCenter update: ~200ms
- **Total latency**: ~350ms (acceptable for minute-level tracking)

#### Edge Cases
1. **App in background**: Darwin notifications still delivered
2. **App force-closed**: Re-arm won't happen until app reopens, but extension continues recording
3. **Multiple apps firing**: Process re-arm requests in batch
4. **Day rollover**: Reset today counters, continue tracking

### 2.5 Testing Plan

1. **Unit Tests**
   - Verify extension writes re-arm flag
   - Verify main app reads and clears flag
   - Verify threshold updates correctly

2. **Integration Tests**
   - Use app for 5 minutes continuously
   - Verify 5 threshold events fire
   - Verify 300s (5 min) recorded

3. **Memory Tests**
   - Monitor extension memory via Instruments
   - Verify stays under 6MB during heavy usage
   - Test with 20+ monitored apps

4. **Edge Case Tests**
   - Force-close app, verify tracking continues
   - Day rollover during usage
   - Multiple apps used simultaneously

---

## Part 3: File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `DeviceActivityMonitorExtension.swift` | Modify | Add re-arm flag writing |
| `ScreenTimeService.swift` | Modify | Add re-arm handling, change threshold setup |
| `ScreenTimeService_MemoryOptimizations.swift` | Modify | Update notification handler |

---

## Part 4: Rollback Plan

If issues arise:
1. Revert to commit `81e901c` (working continuous tracking, heavy memory)
2. Or revert to commit `b8c7162` (working threshold tracking, light memory)

---

## Appendix: Key UserDefaults Keys

### Event Mapping (set by main app, read by extension)
- `map_{eventName}_id` - Logical app ID
- `map_{eventName}_inc` - Increment in seconds (always 60)
- `map_{eventName}_config` - Configuration timestamp

### Usage Counters (written by extension, read by main app)
- `usage_{appID}_total` - Total seconds all time
- `usage_{appID}_today` - Seconds today
- `usage_{appID}_reset` - Last reset timestamp
- `usage_{appID}_modified` - Last update timestamp

### Re-arm Signaling (NEW)
- `rearm_{appID}_requested` - Boolean flag for re-arm request
- `rearm_{appID}_time` - Timestamp of request

### Extension Health
- `extension_initialized_flag` - Extension loaded successfully
- `extension_heartbeat` - Last heartbeat timestamp
- `extension_debug_log` - Debug log entries

---

*Document created: November 21, 2024*
*Ready for implementation*
