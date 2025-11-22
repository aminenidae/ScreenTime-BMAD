# Reward Timer System

## Summary

Replace threshold-based tracking for **reward apps only** with a countdown timer system.

**Learning apps:** Keep current 240 static thresholds (working accurately)
**Reward apps:** Timer-based countdown (no thresholds)

---

## How It Works

### Current Flow (Threshold-based)
```
1. Kid earns reward time via learning apps
2. Reward apps have 240 thresholds each
3. Track usage minute-by-minute
4. Deduct from balance based on thresholds
```

### New Flow (Timer-based)
```
1. Kid earns reward time via learning apps (unchanged)
2. Kid wants to play → starts reward session
3. Timer counts down from available balance
4. When timer expires → re-shield reward apps
5. No thresholds needed for reward apps!
```

---

## Benefits

| Aspect | Threshold-based | Timer-based |
|--------|-----------------|-------------|
| Events per reward app | 240 | 0 |
| Accuracy | ~1 min granularity | Exact seconds |
| Complexity | High (extension tracking) | Low (simple timer) |
| Background reliability | Depends on iOS | Timer + background task |
| User experience | Invisible tracking | Visible countdown |

---

## Data Model

### RewardSession
```swift
struct RewardSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let initialDurationSeconds: Int    // How much time they started with
    var remainingSeconds: Int          // Current remaining
    var isPaused: Bool
    var pausedAt: Date?

    var isExpired: Bool {
        remainingSeconds <= 0
    }
}
```

### RewardBalance (existing, may need updates)
```swift
struct RewardBalance {
    var earnedMinutes: Int        // From learning apps
    var spentMinutes: Int         // Used in reward sessions
    var availableMinutes: Int {   // What's left
        earnedMinutes - spentMinutes
    }
}
```

---

## RewardTimerService

```swift
@MainActor
class RewardTimerService: ObservableObject {
    static let shared = RewardTimerService()

    // Published state
    @Published var activeSession: RewardSession?
    @Published var remainingSeconds: Int = 0
    @Published var isRunning: Bool = false

    // Timer
    private var timer: Timer?

    // MARK: - Public API

    /// Start a reward session with given duration
    func startSession(durationMinutes: Int) {
        // 1. Create session
        // 2. Unshield reward apps
        // 3. Start countdown timer
        // 4. Persist session state
    }

    /// Pause the current session
    func pauseSession() {
        // 1. Stop timer
        // 2. Save remaining time
        // 3. Keep apps unshielded (paused, not ended)
    }

    /// Resume paused session
    func resumeSession() {
        // 1. Restart timer from remaining time
    }

    /// End session early (voluntary or timer expired)
    func endSession() {
        // 1. Stop timer
        // 2. Re-shield reward apps
        // 3. Deduct used time from balance
        // 4. Clear session state
    }

    /// Called when timer ticks
    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            endSession()
        }
    }

    // MARK: - Background Support

    /// Save state when app backgrounds
    func saveState() {
        // Persist activeSession to UserDefaults
    }

    /// Restore state when app foregrounds
    func restoreState() {
        // Load session, calculate elapsed time, update remaining
    }
}
```

---

## Integration Points

### 1. ScreenTimeService
- Remove reward apps from threshold creation
- Only create thresholds for learning apps
- Keep shield/unshield methods (used by timer)

### 2. AppUsageViewModel
- Add `startRewardSession(minutes:)`
- Add `endRewardSession()`
- Show timer state in UI

### 3. Child Mode UI
- Add "Start Reward Time" button
- Show countdown when session active
- Add pause/end controls

### 4. Persistence
- Save active session to survive app restart
- Handle background → foreground time calculation

---

## UI Design

### Before Starting Session
```
┌─────────────────────────────────────────┐
│  🎮 Reward Time Available               │
├─────────────────────────────────────────┤
│                                          │
│         45 minutes                       │
│                                          │
│    [Start 15 min]  [Start 30 min]       │
│                                          │
│           [Start All 45 min]            │
│                                          │
└─────────────────────────────────────────┘
```

### During Session
```
┌─────────────────────────────────────────┐
│  🎮 Reward Time                         │
├─────────────────────────────────────────┤
│                                          │
│            ⏱️ 23:45                      │
│         remaining                        │
│                                          │
│      [Pause]    [End Early]             │
│                                          │
└─────────────────────────────────────────┘
```

### Session Ended
```
┌─────────────────────────────────────────┐
│  ⏰ Time's Up!                          │
├─────────────────────────────────────────┤
│                                          │
│   Great job! You used 30 minutes        │
│   of reward time.                        │
│                                          │
│   Remaining balance: 15 minutes         │
│                                          │
│            [OK]                          │
│                                          │
└─────────────────────────────────────────┘
```

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| App killed during session | Restore on next launch, calculate elapsed |
| Phone restarts | Session ends, time is lost (or save checkpoint) |
| Kid switches apps | Timer keeps running (reward apps stay unshielded) |
| Timer at 0 | Auto-shield, show "time's up" message |
| Parent ends session | Force end via parent mode |

---

## Implementation Steps

### Step 1: RewardTimerService
- [ ] Create RewardTimerService.swift
- [ ] Implement start/pause/resume/end
- [ ] Add timer logic
- [ ] Add persistence for active session

### Step 2: ScreenTimeService Changes
- [ ] Skip reward apps in threshold creation
- [ ] Expose shield/unshield for timer use
- [ ] Update event count logging

### Step 3: UI Integration
- [ ] Add timer display to ChildModeView
- [ ] Add start session controls
- [ ] Add pause/end controls
- [ ] Add "time's up" alert

### Step 4: Background Support
- [ ] Save state on `scenePhase` change
- [ ] Restore and recalculate on foreground
- [ ] Handle app termination gracefully

### Step 5: Testing
- [ ] Test timer accuracy
- [ ] Test background → foreground
- [ ] Test app kill → restart
- [ ] Test shield/unshield timing

---

## Questions Resolved

| Question | Decision |
|----------|----------|
| Learning app tracking | Keep 240 static thresholds |
| Reward app tracking | Timer-based (no thresholds) |
| Partial reward sessions | Can pause and resume |
| Multiple reward apps | All unlock together during session |

---

*Created: November 22, 2024*
*Status: Ready for implementation*
