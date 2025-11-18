# CRITICAL FIX: Monitoring Fails Near Midnight (intervalTooShort)

## Problem

Tracking works correctly but **stops after ~10 minutes when test runs near midnight** (23:38 PM in this case).

### Observed in Logs

```
✅ Success: 05:40 → 05:44 (10 minutes tracked)
05:44:52 → Schedule: hour: 23 minute: 44 second: 52  to hour: 23 minute: 59 second: 59
❌ Failed to restart monitoring (manual): intervalTooShort
```

**Cause**: Monitoring schedule tries to end at midnight (23:59:59), but when current time is after ~23:45, the interval becomes < 15 minutes, violating Apple's minimum requirement.

---

## Root Cause Code

**File**: `ScreenTimeService.swift` (around line 1286-1299)

```swift
private func startMonitoringActivity(_ activity: DeviceActivityName, offsetSeconds: Int) throws {
    let calendar = Calendar.current
    let startDate = Date().addingTimeInterval(TimeInterval(offsetSeconds))
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)

    let endLimit = calendar.startOfDay(for: startDate).addingTimeInterval(24 * 60 * 60 - 1)
    // ↑ This is MIDNIGHT (23:59:59)

    let endDate = min(startDate.addingTimeInterval(3600), endLimit)
    // ↑ Problem: When near midnight, endDate - startDate < 15 min → intervalTooShort

    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)
    // ...
}
```

---

## The Fix

Replace the interval calculation to use a minimum 20-minute interval OR extend to next day:

```swift
private func startMonitoringActivity(_ activity: DeviceActivityName, offsetSeconds: Int) throws {
    let calendar = Calendar.current
    let startDate = Date().addingTimeInterval(TimeInterval(offsetSeconds))
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)

    // Calculate end of current day
    let endOfCurrentDay = calendar.startOfDay(for: startDate).addingTimeInterval(24 * 60 * 60 - 1)

    // Use minimum 20-minute interval (Apple requires ~15 min, use 20 for safety)
    let minimumInterval: TimeInterval = 20 * 60  // 20 minutes
    let preferredInterval: TimeInterval = 60 * 60  // 1 hour

    // Calculate end date with fallback to next day if needed
    let preferredEndDate = startDate.addingTimeInterval(preferredInterval)
    let endDate: Date

    if preferredEndDate <= endOfCurrentDay {
        // Normal case: 1 hour interval fits within current day
        endDate = preferredEndDate
        NSLog("[ScreenTimeService] 📅 Using 1-hour interval within current day")
    } else {
        // Near midnight: Check if we have enough time for minimum interval
        let timeUntilMidnight = endOfCurrentDay.timeIntervalSince(startDate)

        if timeUntilMidnight >= minimumInterval {
            // We have at least 20 minutes until midnight
            endDate = endOfCurrentDay
            NSLog("[ScreenTimeService] 📅 Near midnight: using \(Int(timeUntilMidnight/60)) min until midnight")
        } else {
            // Less than 20 minutes until midnight: extend to next day
            let nextDayStart = calendar.startOfDay(for: startDate).addingTimeInterval(24 * 60 * 60)
            endDate = nextDayStart.addingTimeInterval(preferredInterval)
            NSLog("[ScreenTimeService] 📅 Too close to midnight: extending to next day")
            NSLog("[ScreenTimeService] 📅 Next schedule: \(calendar.component(.hour, from: nextDayStart)):\(calendar.component(.minute, from: nextDayStart)) to \(calendar.component(.hour, from: endDate)):\(calendar.component(.minute, from: endDate))")
        }
    }

    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)

    let schedule = DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: endComponents,
        repeats: false
    )

    // ... rest of existing code
}
```

---

## Alternative Simpler Fix (Recommended for Quick Implementation)

If extending to next day is too complex, just ensure minimum 20-minute interval:

```swift
private func startMonitoringActivity(_ activity: DeviceActivityName, offsetSeconds: Int) throws {
    let calendar = Calendar.current
    let startDate = Date().addingTimeInterval(TimeInterval(offsetSeconds))
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)

    // Use minimum 20-minute interval (Apple requires ~15 min minimum)
    let minimumInterval: TimeInterval = 20 * 60  // 20 minutes
    let preferredInterval: TimeInterval = 60 * 60  // 1 hour

    // Calculate end date ensuring minimum interval
    let endDate = startDate.addingTimeInterval(max(minimumInterval, preferredInterval))

    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)

    NSLog("[ScreenTimeService] 📅 Monitoring schedule:")
    NSLog("[ScreenTimeService]   Start: \(startComponents.hour ?? 0):\(startComponents.minute ?? 0):\(startComponents.second ?? 0)")
    NSLog("[ScreenTimeService]   End: \(endComponents.hour ?? 0):\(endComponents.minute ?? 0):\(endComponents.second ?? 0)")
    NSLog("[ScreenTimeService]   Interval: \(Int(endDate.timeIntervalSince(startDate) / 60)) minutes")

    let schedule = DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: endComponents,
        repeats: false
    )

    // ... rest of existing code
}
```

This simpler approach:
- ✅ Removes the `endLimit` (midnight) restriction
- ✅ Always ensures at least 20-minute interval
- ✅ Allows schedules to extend past midnight naturally
- ✅ Fixes the `intervalTooShort` error

---

## Testing Verification

After implementing the fix:

1. **Test near midnight**: Run the app at 23:50 PM and verify monitoring continues past midnight
2. **Test normal hours**: Run at 14:00 and verify normal 1-hour intervals work
3. **Expected logs**:
```
[ScreenTimeService] 📅 Monitoring schedule:
[ScreenTimeService]   Start: 23:50:30
[ScreenTimeService]   End: 0:50:30  (next day)
[ScreenTimeService]   Interval: 60 minutes
[ScreenTimeService] ✅ Monitoring started successfully
```

---

## Impact

**Before fix**: Tracking fails when within 15 minutes of midnight
**After fix**: Tracking continues seamlessly across midnight boundary

This explains why the user's 7-minute test only recorded a portion - the test ran at 23:38 PM, and by 23:45 PM, monitoring hit `intervalTooShort` errors repeatedly.

---

## Summary for Dev Agent

**CRITICAL**: Remove the `endLimit = midnight` restriction in `startMonitoringActivity()`. Use the simpler fix that ensures a minimum 20-minute interval without capping at midnight. This will allow monitoring to extend past midnight naturally and fix the `intervalTooShort` errors.
