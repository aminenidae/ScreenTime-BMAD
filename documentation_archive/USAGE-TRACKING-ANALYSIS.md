# Usage Tracking Analysis
**Date:** 2025-10-25
**Issue:** App counting usage time even when reward app is open but not actively being used

---

## 🔍 Current Implementation

### How Usage Tracking Works

**Location:** `ScreenTimeRewards/Services/ScreenTimeService.swift`

1. **Threshold Configuration** (Line 83):
   ```swift
   private let defaultThreshold = DateComponents(minute: 1)
   ```
   - Default threshold is **1 minute**
   - This means every 1 minute of "usage" triggers an event

2. **Event Creation** (Lines 570-586):
   ```swift
   let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex)")
   result[eventName] = MonitoredEvent(
       name: eventName,
       category: category,
       threshold: threshold,  // 1 minute
       applications: [app]
   )
   ```
   - Creates individual events for each app
   - Each event has a 1-minute threshold

3. **DeviceActivity Monitoring** (Lines 945-967):
   ```swift
   let events = monitoredEvents.reduce(into: [:]) { result, entry in
       result[entry.key] = entry.value.deviceActivityEvent()
   }
   try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)
   ```
   - Starts monitoring with DeviceActivityCenter
   - Events fire when threshold is reached

4. **Continuous Tracking** (Lines 893-926):
   ```swift
   private let restartInterval: TimeInterval = 120  // 2 minutes

   monitoringRestartTimer = Timer.scheduledTimer(withTimeInterval: restartInterval, repeats: true) {
       try self.scheduleActivity()  // Restart monitoring to reset events
   }
   ```
   - Timer restarts monitoring every **2 minutes**
   - This resets the events so they can fire again
   - Enables tracking beyond the first 1-minute threshold

5. **Usage Recording** (DeviceActivityMonitorExtension.swift, Lines 159-219):
   ```swift
   override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
       recordUsageFromEvent(event)  // Records thresholdSeconds to persistence
   }
   ```
   - When threshold is reached, extension records usage
   - Records the threshold amount (1 minute = 60 seconds)

---

## ⚠️ THE PROBLEM: Apple's Screen Time API Limitation

### What DeviceActivity Actually Tracks

According to Apple's DeviceActivity framework documentation and observed behavior:

**DeviceActivityEvent tracks "SCREEN TIME" (foreground time), NOT "active usage"**

#### What counts as "screen time":
✅ App is visible on screen and user is actively using it
✅ App is open on screen but user is NOT touching it (idle)
✅ App is in split-screen view (counts even if user is using other app)
✅ App is visible while user is looking at something else
✅ App is in foreground while screen is on (even if locked afterwards)

#### What this means for reward apps:
- User opens reward app → timer starts
- User stops interacting but leaves app open → **timer continues**
- User switches to another app in split-view → **both apps count time**
- User puts phone down with app visible → **timer continues**
- Every 1 minute of foreground time → event fires → usage recorded
- Every 2 minutes → monitoring restarts → more events can fire

---

## 🔬 Root Cause Analysis

### Why The Current Implementation Counts Background Time

**File:** `ScreenTimeService.swift`

```
Flow:
1. Reward app opens → enters foreground
2. DeviceActivity starts tracking foreground time
3. After 1 minute of foreground time (not interaction) → eventDidReachThreshold fires
4. Extension records 60 seconds of usage
5. Main app consumes points based on that usage
6. After 2 minutes total → monitoring restarts
7. Another 1 minute of foreground time → event fires again
8. Cycle repeats...
```

**The API has NO built-in way to distinguish:**
- App visible + user interacting ❌ Cannot detect
- App visible + user idle ❌ Cannot detect
- App in focus vs background app ✅ Can detect (foreground/background)

### Apple's Screen Time Definition

From iOS Screen Time settings, "usage" = **time app is visible on screen**, which includes:
- Active use
- Passive viewing
- Idle time with app open
- Split-screen time

This is Apple's design - Screen Time is meant to track "exposure" to apps, not just active interaction.

---

## 🚨 Impact on Reward System

### Current Behavior (INCORRECT for your use case):

**Scenario:**
1. User earns 375 points from learning apps
2. User redeems 75 points (15 min) for reward app
3. User opens reward app and actively plays for 2 minutes
4. User **leaves app open** and walks away for 8 minutes
5. Total foreground time: **10 minutes**

**What happens:**
- Event fires at minute 1 → 5 points consumed ✓
- Event fires at minute 2 → 5 points consumed ✓ (correct - was actually playing)
- Monitoring restarts at minute 2
- Event fires at minute 3 → 5 points consumed ✗ (user not playing)
- Event fires at minute 4 → 5 points consumed ✗ (user not playing)
- ...and so on
- **Total consumed: 50 points** instead of expected 10 points

**Result:** User only got 2 minutes of actual play but was charged for 10 minutes.

---

## 📊 Why This Happens

### The DeviceActivity API Design

Apple's `DeviceActivityEvent` with `threshold` parameter:

```swift
DeviceActivityEvent(
    applications: Set<ApplicationToken>,
    threshold: DateComponents  // Triggers after X time in FOREGROUND
)
```

**Documentation (paraphrased):**
> "The event fires when the specified applications have been used for the threshold duration."

**"Used" in Apple's definition = "in foreground"**, not "actively interacting"

This is the same metric used for:
- iOS Screen Time reports
- Parental controls time limits
- App usage statistics

It's designed for **time management and limiting exposure**, not for tracking **active engagement**.

---

## 🔍 Alternative Approaches (Not Currently Implemented)

### 1. **Interaction-Based Detection** (Requires App-Side Monitoring)
- Monitor touch events, gestures, button presses
- ❌ Problem: Can't monitor from DeviceActivity extension
- ❌ Problem: Doesn't work when app is in background
- ❌ Problem: User could "fake" interaction

### 2. **Motion/Gyroscope Detection**
- Detect device movement as proxy for active use
- ❌ Problem: User could be watching video (passive)
- ❌ Problem: Doesn't distinguish between apps
- ❌ Problem: Requires CoreMotion permissions

### 3. **Heuristic Time Windows**
- Only count usage in short bursts (e.g., 30-second windows)
- Reset if no screen change detected
- ❌ Problem: Complex logic, prone to edge cases
- ❌ Problem: Still relies on foreground time

### 4. **Manual User Confirmation**
- Require user to "check in" periodically
- ❌ Problem: Poor user experience
- ❌ Problem: Gameable (user can cheat)

### 5. **Audio/Video Analysis**
- Detect if media is playing
- ❌ Problem: Privacy concerns
- ❌ Problem: Doesn't cover all app types (games, social media)
- ❌ Problem: High battery drain

---

## 📝 Recommendations

### Option A: Accept Screen Time Definition (Simplest)
**Keep current implementation**, but:
- Document that "usage" = "time app is visible on screen"
- Educate users that leaving apps open counts as usage
- Add UI warnings: "Close reward apps when not actively using them"

**Pros:**
- Uses standard iOS Screen Time metrics
- Consistent with Apple's ecosystem
- No additional implementation needed

**Cons:**
- Users charged for idle time
- Not truly "active usage"

---

### Option B: Increase Threshold (Reduce Sensitivity)
**Change from 1-minute to longer intervals:**
```swift
private let defaultThreshold = DateComponents(minute: 5)
```

**Pros:**
- Reduces number of events
- Less sensitive to brief idle periods

**Cons:**
- Less granular tracking
- Still counts foreground time
- Doesn't solve core issue

---

### Option C: Hybrid Approach (Most Accurate, Most Complex)
**Combine DeviceActivity + App-Level Monitoring:**

1. DeviceActivity tracks foreground time (as currently)
2. Main app tracks actual interaction when active:
   - UIApplication state changes
   - Scene activation
   - Touch events via UIResponder
3. Cross-reference both sources
4. Only count periods with both foreground + interaction

**Pros:**
- More accurate "active usage" detection
- Can distinguish idle from active

**Cons:**
- Complex implementation
- Only works when main app is active
- Requires careful state management
- Still has edge cases

---

### Option D: User-Initiated Sessions (Most Transparent)
**Require user to "start" and "stop" reward sessions:**

1. User taps "Start Playing" when they unlock reward app
2. Timer runs while session is active
3. User taps "Stop" when done, or auto-stop after inactivity
4. Only count time in active sessions

**Pros:**
- Most transparent to user
- Accurate active usage
- User controls billing

**Cons:**
- Extra steps for user
- Users might forget to stop
- Can be gameable

---

## 🎯 Conclusion

**Current Implementation Behavior:**
- ✅ Correctly implements Apple's DeviceActivity API
- ✅ Tracks "screen time" as Apple defines it
- ❌ Does NOT track "active usage" or "interaction"
- ❌ Counts foreground time even when user is idle

**The Issue:**
Apple's Screen Time API is designed for **time management and screen exposure**, not **active engagement tracking**. There is no built-in way to distinguish between an app being visible vs. actively used.

**Why This Matters for Your App:**
Your reward system charges points based on usage time. Users expect to be charged for **active play time**, not **time the app is visible**. The current implementation charges for both.

**Bottom Line:**
This is a **fundamental API limitation**, not a bug in your implementation. To fix this properly requires one of the alternative approaches above, each with significant tradeoffs.

---

**Recommendation:**
Start with **Option A** (document the behavior) + **Option B** (increase threshold to 5 minutes) as a quick mitigation. This reduces over-charging while staying within the Screen Time API capabilities.

For a true "active usage" solution, **Option C** (hybrid approach) would be needed, but requires significant additional development and still has limitations.
