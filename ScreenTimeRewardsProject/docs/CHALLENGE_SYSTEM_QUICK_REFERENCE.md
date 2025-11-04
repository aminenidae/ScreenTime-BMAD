# Challenge System - Quick Reference

**Status:** Ready for Implementation
**Priority:** HIGH
**Estimated Time:** 4 weeks
**Documentation Complete:** ✅

---

## What is the Challenge System?

A comprehensive gamification feature that motivates children to use learning apps through:
- **Challenges:** Goals set by parents (e.g., "60 min/day → +10% bonus points")
- **Streaks:** Consecutive day tracking with multipliers
- **Badges:** Achievement unlocks for milestones
- **Progress Bars:** Visual feedback with animations

---

## User Flow

### Parent (Challenge Creator)
1. Open **Challenges tab** (4th tab in Parent Mode)
2. Choose **template** or **create custom** challenge
3. Configure:
   - Goal type (daily/weekly/specific apps/streak)
   - Target value (minutes or days)
   - Bonus percentage (5-50%)
   - Duration
4. Save → **Syncs to child device via CloudKit**

### Child (Challenge Participant)
1. See **summary card** on dashboard
2. Open **Challenges tab** (3rd tab in Child Mode)
3. View **progress bars** updating in real-time
4. Complete challenge → **Earn bonus points + celebration animation**
5. Unlock **badges** for achievements
6. Build **streaks** for consecutive days

---

## Key Features

### 🎯 Challenge Types
- **Daily Dynamo:** 60 min/day → +10% points
- **Weekend Warrior:** 180 min over weekend → +15% points
- **App Master:** 5 hours in specific app → +20% points
- **Streak Champion:** 7-day streak → +25% points
- **Quick Start:** 15 min/day (beginner) → +5% points

### 🔥 Streak System
- Track consecutive days meeting daily goals
- **Multiplier:** +5% bonus per week of streak
- Visual: Fire emoji with counter
- At-risk warning if streak endangered

### 🏆 Badge System
- **First Steps:** Complete first challenge
- **Week Warrior:** 7-day streak
- **Month Master:** 30-day streak
- **Learning Legend:** 100 hours total
- **Point Collector:** 10,000 points earned
- **Challenge Champion:** 10 challenges completed

### 📊 Progress Tracking
- **Real-time updates** as child uses learning apps
- **Animated progress bars** (blue → green → gold)
- **Percentage display** with completion indicator
- **Celebration animations** when goals achieved

---

## Technical Architecture

### Data Models
```
Challenge          → Challenge configuration (parent creates)
ChallengeProgress  → Real-time tracking (child's progress)
Badge              → Achievement definitions
StreakRecord       → Consecutive day tracking
```

### Services
```
ChallengeService   → Core business logic
  ├─ Challenge CRUD
  ├─ Progress tracking
  ├─ Bonus calculation
  ├─ Badge unlocks
  └─ Streak management
```

### UI Components
```
Parent Mode:
├─ ParentChallengesTabView (4th tab)
├─ ChallengeBuilderView (create/edit)
├─ ChallengeTemplateCard (quick select)
└─ ChallengeDetailView (view child progress)

Child Mode:
├─ ChildChallengesTabView (3rd tab)
├─ ChildChallengeCard (progress display)
├─ BadgeGridView (achievements)
└─ CompletionCelebrationView (animations)
```

### Integration Points
```
ScreenTimeService    → Hook usage tracking
  └─ Notify ChallengeService on learning app usage

AppUsageViewModel    → Apply bonus points
  └─ calculateBonusPoints() from ChallengeService

CloudKit             → Automatic sync (NSPersistentCloudKitContainer)
  ├─ Parent creates → Child receives
  └─ Child progress → Parent views
```

---

## Implementation Phases

### Phase 1: Core Foundation (Week 1)
- ✅ Create data models
- ✅ Add Core Data entities
- ✅ Build ChallengeService
- ✅ Integrate with ScreenTimeService
- ✅ Add AppUsageViewModel properties

### Phase 2: Parent UI (Week 2)
- ✅ Add Challenges tab to Parent Mode
- ✅ Create challenge builder with templates
- ✅ Template cards with quick select
- ✅ Active challenges list
- ✅ CloudKit sync setup

### Phase 3: Child Experience (Week 3)
- ✅ Add challenge summary to child dashboard
- ✅ Create Challenges tab for Child Mode
- ✅ Challenge cards with progress bars
- ✅ Real-time progress updates
- ✅ Streak display

### Phase 4: Gamification (Week 4)
- ✅ Badge system implementation
- ✅ Streak tracking with multipliers
- ✅ Completion celebrations
- ✅ Badge grid UI
- ✅ Polish & bug fixes

---

## Files to Create (31 files)

### Models (6 files)
- `Models/Challenge.swift`
- `Models/ChallengeProgress.swift`
- `Models/Badge.swift`
- `Models/StreakRecord.swift`
- `Models/ChallengeTemplate.swift`
- `Models/BadgeDefinitions.swift`

### Services (1 file)
- `Services/ChallengeService.swift`

### ViewModels (1 file)
- `ViewModels/ChallengeViewModel.swift`

### Views - Parent (5 files)
- `Views/ParentMode/ParentChallengesTabView.swift`
- `Views/ParentMode/ChallengeBuilderView.swift`
- `Views/ParentMode/ChallengeDetailView.swift`
- `Views/ParentMode/ChallengeTemplateCard.swift`
- `Views/ParentMode/ParentChallengeCard.swift`

### Views - Child (4 files)
- `Views/ChildMode/ChildChallengesTabView.swift`
- `Views/ChildMode/ChildChallengeCard.swift`
- `Views/ChildMode/BadgeGridView.swift`
- `Views/ChildMode/StreakDisplayView.swift`

### Views - Shared (2 files)
- `Views/Shared/AnimatedProgressBar.swift`
- `Views/Shared/CompletionCelebrationView.swift`

---

## Files to Modify (5 files)

- `ScreenTimeRewards.xcdatamodeld/...` - Add 4 new entities
- `Views/MainTabView.swift` - Add Challenges tabs
- `Services/ScreenTimeService.swift` - Hook challenge updates
- `ViewModels/AppUsageViewModel.swift` - Apply bonuses
- `Views/ChildMode/ChildDashboardView.swift` - Add summary card

---

## Key Decisions Made

1. **Bonus Type:** Bonus **points** (not time) - easier to implement
2. **Progress Tracking:** **Real-time** updates for instant gratification
3. **Child View:** **Both** dashboard summary + dedicated tab
4. **Gamification:** **All** elements (progress bars, streaks, badges, levels)
5. **CloudKit:** Use **NSPersistentCloudKitContainer** (automatic sync)
6. **Animations:** SwiftUI native animations + confetti for celebrations

---

## Success Metrics

- **Engagement:** 80% of children check Challenges tab daily
- **Motivation:** +30% increase in learning app usage
- **Completion Rate:** 70%+ challenges completed
- **Streak Retention:** Average 5+ day streaks
- **Parent Adoption:** 90% of parents create challenges

---

## Documentation

- **Full Spec:** `CHALLENGE_SYSTEM_IMPLEMENTATION_SPEC.md`
- **Dev Tasks:** `DEV_AGENT_TASKS_CHALLENGE_SYSTEM.md`
- **Quick Ref:** This document

---

## Example Usage

### Parent Creates Challenge
```
1. Open Challenges tab
2. Tap "Daily Dynamo" template
3. Adjust: 60 min → 45 min, +10% → +15%
4. Select child device
5. Save → Challenge syncs to child
```

### Child Completes Challenge
```
1. Uses learning apps for 45 minutes
2. Progress bar fills: 0% → 50% → 100%
3. Challenge completes:
   - 🎉 Celebration animation
   - +15% bonus points awarded
   - Badge "First Steps" unlocked
   - Streak increments to 3 days
4. Next day: New challenge starts
```

---

## Testing Strategy

### Unit Tests
- Challenge validation
- Progress calculation
- Bonus point math
- Streak logic

### Integration Tests
- CloudKit sync (parent ↔ child)
- Real-time updates
- Multi-challenge bonuses
- Badge unlock triggers

### UI Tests
- Challenge builder flow
- Progress bar rendering
- Animations
- Tab navigation

### Manual Testing
- End-to-end challenge creation → completion
- Multiple active challenges
- Streak building/breaking
- Badge collection
- Parent viewing child progress

---

## Known Limitations

1. **Offline Behavior:** Challenges sync when online (CloudKit)
2. **Badge Backfill:** Existing stats won't retroactively unlock badges
3. **Streak Recovery:** 1-day grace period only
4. **Challenge Overlap:** Multiple challenges can be active simultaneously

---

## Future Enhancements

- **Cooperative Challenges:** Family/sibling challenges
- **Leaderboards:** Compare with friends (opt-in)
- **Custom Badges:** Parent creates custom achievements
- **Challenge Notifications:** Reminders and progress alerts
- **Export/Share:** Share achievements on social media
- **AI Recommendations:** Suggest challenges based on child's habits

---

**Ready to implement! Start with Phase 1.**

🚀 **Dev Agent:** See `DEV_AGENT_TASKS_CHALLENGE_SYSTEM.md` for step-by-step implementation guide.
