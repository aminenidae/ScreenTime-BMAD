# Goal-Based Tracking Architecture

## Executive Summary

Replace minute-by-minute threshold tracking with a goal-based system that:
1. Uses **minimal thresholds** for earning rewards (4-8 per app)
2. Uses **DeviceActivityReport** for detailed parent visibility
3. Uses **timer-based countdown** for reward app time spending

---

## Current Architecture Problems

| Issue | Impact |
|-------|--------|
| 240 thresholds per app | Potential iOS API limits with many apps |
| Complex restart logic | Source of bugs (cascade, counter reset) |
| Real-time minute tracking | Distracting for kids |

---

## Proposed Architecture

### 1. Learning Apps: Goal-Based Thresholds

**Parent configures:** "30 min Khan Academy = 30 min reward time"

**Implementation:**
```
Threshold 1: 30 min → fires → credit 30 min reward
Threshold 2: 60 min → fires → credit 30 min reward
Threshold 3: 90 min → fires → credit 30 min reward
Threshold 4: 120 min → fires → credit 30 min reward
```

**Benefits:**
- 4 thresholds per app (vs 240)
- Clear goal completion for kids
- Gamification opportunity

### 2. Parent Dashboard: DeviceActivityReport

Apple's built-in SwiftUI component shows real usage:
- Per-app breakdown with exact minutes
- Works when app is in foreground
- No custom tracking needed

**Already exists in app:** `HiddenUsageReportView.swift`

### 3. Reward Apps: Timer-Based Countdown

When kid unlocks reward time:
1. Start countdown timer (e.g., 30 minutes)
2. Show remaining time in UI
3. Re-shield apps when timer expires
4. No thresholds needed for reward apps!

---

## Data Model Changes

### New: GoalConfiguration
```swift
struct GoalConfiguration: Codable {
    let learningAppID: String
    let goalMinutes: Int           // e.g., 30
    let rewardMinutes: Int         // e.g., 30
    let maxGoalsPerDay: Int        // e.g., 4 (2 hours max)
}
```

### New: GoalProgress
```swift
struct GoalProgress: Codable {
    let appID: String
    let date: Date                 // Today's date
    let goalsCompleted: Int        // 0, 1, 2, 3, 4
    let currentProgress: Int       // Minutes toward next goal
    let rewardMinutesEarned: Int   // Total earned today
}
```

### New: RewardSession
```swift
struct RewardSession: Codable {
    let startTime: Date
    let durationMinutes: Int
    let remainingMinutes: Int
    var isActive: Bool
}
```

---

## Component Changes

### ScreenTimeService.swift
- [ ] Add `GoalConfiguration` storage
- [ ] Change threshold creation: 4 per app at goal intervals
- [ ] Add goal completion handler
- [ ] Remove 240-threshold logic

### New: GoalTrackingService.swift
- [ ] Manage goal progress per app
- [ ] Calculate reward minutes earned
- [ ] Handle day rollover
- [ ] Sync with persistence

### New: RewardTimerService.swift
- [ ] Countdown timer for reward sessions
- [ ] Background timer support
- [ ] Auto-shield when timer expires
- [ ] Pause/resume functionality

### UI Changes
- [ ] Parent: Goal configuration screen
- [ ] Parent: Progress dashboard (uses DeviceActivityReport)
- [ ] Child: Goal progress view (not minute-by-minute)
- [ ] Child: Reward countdown timer display

---

## Threshold Math

### Learning App Thresholds

| Goal Size | Thresholds for 4hr max | Total Events |
|-----------|------------------------|--------------|
| 10 min    | 10, 20, 30... 240      | 24 per app   |
| 15 min    | 15, 30, 45... 240      | 16 per app   |
| 20 min    | 20, 40, 60... 240      | 12 per app   |
| 30 min    | 30, 60, 90... 240      | 8 per app    |
| 60 min    | 60, 120, 180, 240      | 4 per app    |

**Recommendation:** Default 30-min goals (8 thresholds per app)

### Total Events Calculation

| Scenario | Learning Apps | Reward Apps | Total Events |
|----------|---------------|-------------|--------------|
| Light (2+2) | 2 × 8 = 16 | 0 | 16 |
| Medium (4+4) | 4 × 8 = 32 | 0 | 32 |
| Heavy (8+8) | 8 × 8 = 64 | 0 | 64 |

**Compare to current:** 8 apps × 240 = 1,920 events

---

## Parent UX Flow

### Setup Flow
```
1. Select learning apps
2. For each app, set goal:
   "How much [App Name] time earns reward?"
   [15 min] [30 min] [45 min] [60 min]

3. Set exchange rate:
   "Reward time earned per goal:"
   [Same as goal] [Half of goal] [Custom]

4. Select reward apps (no thresholds needed)
```

### Dashboard View
```
┌─────────────────────────────────────────┐
│  Today's Learning Progress              │
├─────────────────────────────────────────┤
│  Khan Academy                           │
│  ████████████░░░░░░░░ 24/30 min         │
│  Goals: ✓ ✓ ○ ○  (2 of 4 completed)     │
│                                          │
│  Duolingo                               │
│  ██████░░░░░░░░░░░░░░ 12/30 min         │
│  Goals: ○ ○ ○ ○  (0 of 4 completed)     │
├─────────────────────────────────────────┤
│  Reward Time                            │
│  Earned today: 60 min                   │
│  Spent today: 25 min                    │
│  Available: 35 min                      │
└─────────────────────────────────────────┘
```

---

## Child UX Flow

### Learning Mode
```
┌─────────────────────────────────────────┐
│  🎯 Current Goal                        │
├─────────────────────────────────────────┤
│                                          │
│     Khan Academy                        │
│                                          │
│     ████████████████░░░░  80%           │
│     24 of 30 minutes                    │
│                                          │
│     6 more minutes to earn              │
│     🎮 30 min of game time!             │
│                                          │
└─────────────────────────────────────────┘
```

### Reward Mode
```
┌─────────────────────────────────────────┐
│  🎮 Reward Time                         │
├─────────────────────────────────────────┤
│                                          │
│     Time Remaining                      │
│                                          │
│         ⏱️ 23:45                        │
│                                          │
│     Playing: Minecraft                  │
│                                          │
│     [Pause] [End Early]                 │
│                                          │
└─────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Core Goal Tracking (MVP)
- [ ] GoalConfiguration data model
- [ ] GoalProgress persistence
- [ ] Modify ScreenTimeService for goal thresholds
- [ ] Goal completion detection
- [ ] Basic reward minutes calculation

### Phase 2: Reward Timer
- [ ] RewardTimerService implementation
- [ ] Background timer support
- [ ] Auto-shield on expiry
- [ ] Timer UI for child mode

### Phase 3: Parent Dashboard
- [ ] Goal configuration UI
- [ ] DeviceActivityReport integration
- [ ] Progress visualization
- [ ] Goal history/streaks

### Phase 4: Child Experience
- [ ] Goal progress UI
- [ ] Reward countdown UI
- [ ] Achievements/celebrations
- [ ] Motivational messaging

---

## Migration Plan

### From Current System
1. Keep existing usage data
2. Convert to goal-based on next app update
3. Default: 30-min goals for existing learning apps
4. Parent can customize after update

### Backward Compatibility
- Existing challenges continue working
- Earned points/rewards preserved
- Only tracking mechanism changes

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| DeviceActivityReport not updating | Fallback to threshold-based progress |
| Timer not surviving background | Use BackgroundTasks framework |
| Goal too hard/easy | Parent-adjustable goal sizes |
| Kids gaming the system | Goals are cumulative (can't pause/restart) |

---

## Success Metrics

- [ ] < 100 total threshold events (vs 1000+)
- [ ] No cascade/restart bugs
- [ ] Parents can see detailed usage
- [ ] Kids understand goal system
- [ ] Reward timer works reliably

---

## Questions to Resolve

1. **Partial progress:** If kid uses 25/30 min, does progress carry to tomorrow?
   - Option A: Reset daily (stricter)
   - Option B: Carry over (more forgiving)

2. **Multiple learning apps:** Shared goal or per-app goals?
   - Option A: Per-app (current plan)
   - Option B: Combined "30 min ANY learning app"

3. **Reward app selection:** Can kid choose which reward app to use?
   - Option A: All reward apps unlocked together
   - Option B: Kid picks one app per session

---

*Created: November 22, 2024*
*Status: Planning*
