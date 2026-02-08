# Hourly Usage Diagnostic Feature

**Date:** 2025-11-19  
**Status:** ✅ Implemented and Ready for Testing  
**Build Status:** ✅ BUILD SUCCEEDED

---

## Overview

Added a diagnostic dashboard card that displays hourly usage patterns for both Learning and Reward apps. This helps identify iOS Screen Time API overcounting patterns and track when threshold events fire throughout the day.

---

## Features

### 1. Hourly Usage Chart
- **Bar chart** showing usage minutes for each hour
- **Last 12 hours** of data displayed
- **Color-coded** by category (teal for learning, coral for reward)
- **Annotations** showing minute values on bars

### 2. Real-Time Statistics
- **Total Today:** Total minutes recorded today
- **Events Fired:** Number of successful threshold events
- **Rejected:** Number of events rejected by validation layers

### 3. Clear Button
- Allows resetting diagnostic data during testing
- Useful for starting fresh test runs

---

## Implementation Details

### Files Created

#### `HourlyUsageDiagnosticView.swift`
**Location:** `/Views/Diagnostic/HourlyUsageDiagnosticView.swift`

**Components:**
1. **HourlyUsageDiagnosticView:** SwiftUI view with Charts framework
2. **HourlyUsageDiagnosticData:** Observable data model tracking hourly usage

**Key Features:**
- Uses SwiftUI Charts (iOS 16+)
- Tracks data separately for learning and reward categories
- Listens to NotificationCenter for threshold events
- Auto-updates when events fire

### Files Modified

#### 1. `ScreenTimeService.swift`
**Lines Added: 1903-1907, 1923-1932**

**Changes:**
- Posts `ScreenTimeThresholdFired` notification when valid events fire
- Posts `ScreenTimeEventRejected` notification when events are rejected
- Includes category, duration, and timestamp in notifications

#### 2. `LearningTabView.swift`
**Lines Added: 41-46**

**Changes:**
- Added diagnostic chart after summary card
- Shows learning category data
- iOS 16+ availability check

#### 3. `RewardsTabView.swift`
**Lines Added: 21-26**

**Changes:**
- Added diagnostic chart before points summary
- Shows reward category data
- iOS 16+ availability check

---

## How It Works

### Data Flow

```
1. Threshold Event Fires
   ↓
2. ScreenTimeService validates event
   ↓
3. If VALID:
   - Records usage
   - Posts "ScreenTimeThresholdFired" notification
   ↓
4. If REJECTED:
   - Posts "ScreenTimeEventRejected" notification
   ↓
5. HourlyUsageDiagnosticData receives notification
   ↓
6. Updates hourly tracking by current hour
   ↓
7. SwiftUI chart auto-updates
```

### Notification Structure

#### ScreenTimeThresholdFired
```swift
NotificationCenter.default.post(
    name: NSNotification.Name("ScreenTimeThresholdFired"),
    object: nil,
    userInfo: [
        "category": "learning" or "reward",
        "duration": 60.0,  // seconds
        "timestamp": Date()
    ]
)
```

#### ScreenTimeEventRejected
```swift
NotificationCenter.default.post(
    name: NSNotification.Name("ScreenTimeEventRejected"),
    object: nil,
    userInfo: [
        "category": "learning" or "reward"
    ]
)
```

---

## Usage

### Viewing the Chart

1. **Learning Tab:**
   - Open the Learning Apps tab
   - Chart appears below the "Total Points per Minute" card
   - Shows teal-colored bars for learning app usage

2. **Rewards Tab:**
   - Open the Reward Apps tab
   - Chart appears at the top
   - Shows coral-colored bars for reward app usage

### Interpreting the Data

#### Normal Pattern
```
8am  [1m]
9am  [1m]
10am [1m]
11am [1m]
...
Total Today: 4m
Events Fired: 4
Rejected: 0
```
**Indicates:** Healthy tracking, one event per hour

#### Overcounting Pattern (Bug)
```
2pm  [28m]  ⚠️ Spike!
3pm  [0m]
4pm  [0m]
...
Total Today: 28m
Events Fired: 28
Rejected: 27
```
**Indicates:** iOS bug triggered, but protection working (27/28 rejected)

---

## Testing Checklist

### Before Test
- [ ] Build succeeded
- [ ] App deployed to device
- [ ] Learning and Reward apps selected

### During Test
- [ ] Open Learning tab - verify chart is visible
- [ ] Open Rewards tab - verify chart is visible
- [ ] Use learning app for >1 minute
- [ ] Check chart updates with new bar
- [ ] Monitor "Events Fired" counter
- [ ] Monitor "Rejected" counter (should stay 0 if no bugs)

### If Bug Occurs
- [ ] Chart should show spike in one hour
- [ ] "Rejected" counter should increase
- [ ] "Events Fired" should only increase by 1-2
- [ ] Total minutes should match single event (60-120s)

---

## Benefits for Debugging

### 1. Visual Pattern Recognition
- Quickly spot overcounting spikes
- See hourly usage distribution
- Identify when bugs occur

### 2. Real-Time Validation
- Confirm multi-layer protection working
- See rejected events counter increase
- Verify only valid events recorded

### 3. Test Documentation
- Screenshot chart during tests
- Share with support/debugging
- Track bug frequency

---

## Technical Notes

### Memory Impact
- **Minimal:** Only stores 24 integers per category (hour -> minutes)
- **Auto-clears:** Data resets on app restart
- **Manual clear:** "Clear" button available

### Performance
- **Negligible:** Simple dictionary lookups
- **Efficient:** NotificationCenter observers
- **No timers:** Event-driven updates only

### Compatibility
- **Requires:** iOS 16+ (for SwiftUI Charts)
- **Graceful degradation:** Wrapped in availability check
- **No impact:** Older iOS versions skip the view

---

## Example Screenshots

### Learning Tab - Normal Usage
```
┌────────────────────────────────────┐
│ 📊 Hourly Usage (Diagnostic)       │
│                             [Clear]│
├────────────────────────────────────┤
│     2m                             │
│ ┌─┐ 1m 1m                          │
│ │ │┌─┐┌─┐                          │
│ └─┘└─┘└─┘                          │
│ 8am 9am 10am 11am 12pm 1pm 2pm     │
├────────────────────────────────────┤
│ Total Today: 4m                    │
│ Events Fired: 4                    │
│ Rejected: 0                        │
└────────────────────────────────────┘
```

### Learning Tab - Bug Detected
```
┌────────────────────────────────────┐
│ 📊 Hourly Usage (Diagnostic)       │
│                             [Clear]│
├────────────────────────────────────┤
│         28m ⚠️                     │
│         ┌──┐                       │
│         │  │                       │
│         │  │                       │
│         └──┘                       │
│ 8am 9am 10am 11am 12pm 1pm 2pm     │
├────────────────────────────────────┤
│ Total Today: 28m ⚠️                │
│ Events Fired: 28                   │
│ Rejected: 27 ⚠️                    │
└────────────────────────────────────┘
```

---

## Next Steps

1. **Deploy to Test Device**
2. **Run Usage Tests**
3. **Monitor Charts**
4. **Document Findings**
5. **Share Results**

---

**Implementation Complete:** 2025-11-19  
**Ready for Testing:** ✅ Yes  
**Build Status:** ✅ BUILD SUCCEEDED
