# Usage Tracking Fix: Delta-Based Session Tracking

## Date: November 26, 2025 (v3 - Delta-Based)

---

## Problem History

### Original Issue
iOS thresholds are **SESSION-based**, not DAY-based. Each time iOS restarts monitoring, it fires thresholds 1, 2, 3... from scratch, regardless of prior usage that day.

### First Attempt (Failed): Simple ADD Mode
**Logic:** `if threshold <= currentUsage → ADD 60s`

**Problem:** Catch-up thresholds each added 60s, causing massive overcounting.

### Second Attempt (Failed): Day-Based Peak Threshold
**Logic:** `if threshold > peakThreshold → SET to threshold`

**Problem:** User had to exceed their existing peak before any new usage was recorded.

### Third Attempt (Failed): Session-Start Based
**Logic:** `newDayTotal = sessionStartTotal + threshold`

**Problem:** If `sessionStartKey` had a **stale value** from a previous session that was higher than current day total, usage would be inflated.

**Example bug:**
- Previous session: `sessionStart = 2000s`
- Today reset to `1080s`
- Threshold 60s fires: `newDayTotal = 2000 + 60 = 2060s` ← **INFLATED!**

---

## Solution: Delta-Based Calculation (v3)

**Key insight:** Don't rely on persisted `sessionStart`. Calculate delta directly.

### Logic
```swift
// delta = how much NEW session time (threshold - sessionPeak)
// newDayTotal = currentToday + delta

let delta = thresholdSeconds - sessionPeak
let newDayTotal = currentToday + delta
```

### Why This Works

The delta calculation is **self-correcting** because it only uses:
1. `thresholdSeconds` - current threshold (fresh from iOS)
2. `sessionPeak` - highest threshold in THIS session (reset on new session)
3. `currentToday` - current day total (fresh read)

No stale persisted values can cause inflation!

---

## Implementation Details

### File Modified
`ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`

### Key Data Keys (per app)
- `usage_{appID}_today` - Cumulative day usage in seconds
- `usage_{appID}_sessionPeak` - Highest threshold seen in current session
- `usage_{appID}_sessionLastThreshold` - Timestamp of last threshold event

**Note:** `sessionStartKey` is NO LONGER USED (removed to avoid stale value bugs).

### Session Detection
```swift
let timeSinceLastThreshold = nowTimestamp - lastThresholdTime
let isNewSession = timeSinceLastThreshold > 30.0 || lastThresholdTime == 0

if isNewSession {
    sessionPeak = 0  // Reset for new session
}
```

### Main Logic
```swift
// Check if this threshold is new for this SESSION
if thresholdSeconds <= sessionPeak {
    return false  // Already counted
}

// Calculate delta (new session time to add)
let delta = thresholdSeconds - sessionPeak

// Add delta to current day total
let newDayTotal = currentToday + delta

// Update
defaults.set(newDayTotal, forKey: todayKey)
defaults.set(thresholdSeconds, forKey: sessionPeakKey)
```

---

## Example Walkthrough

**Starting state:** today = 1080s

### Event 1 (threshold 60s):
- isNewSession = TRUE → sessionPeak = 0
- delta = 60 - 0 = **60s**
- newDayTotal = 1080 + 60 = **1140s** ✓

### Event 2 (threshold 120s):
- isNewSession = FALSE
- sessionPeak = 60
- delta = 120 - 60 = **60s**
- newDayTotal = 1140 + 60 = **1200s** ✓

### After 10 events:
- Final: 1080 + (60×10) = **1680s** ✓

---

## Log Messages to Watch

| Message | Meaning |
|---------|---------|
| `🆕 New session for {app}` | New session started, sessionPeak reset to 0 |
| `📊 RECORDED: +Xs (threshold=Ys - peak=Zs) → today=Ws` | Delta added to day total |
| `⏭️ SKIP: threshold=Xs <= sessionPeak=Ys` | Duplicate threshold ignored |

---

## Testing Plan

1. Note current "today" usage for an app (e.g., 1080s)
2. Use the app for 10 minutes
3. Expected: 1080 + 600 = **1680s**
4. Check logs show `+60s` deltas for each threshold

---

## Key Insight

**Use DELTA, not absolute values.**

```
delta = threshold - sessionPeak   // New time in session
newDayTotal = currentToday + delta  // Add to current
```

This is mathematically equivalent to the session-start approach but doesn't rely on any persisted value that could get stale.
