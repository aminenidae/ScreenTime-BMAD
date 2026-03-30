# App Store Screenshot Plan for ScreenTime Rewards

## Overview
This plan outlines the 8 recommended screenshots for App Store submission, mapping your app's active features to proven patterns from competitor analysis (BePresent).

**Note:** Avatar, Collections, and Challenges features are abandoned/inactive and should NOT be included.

---

## Active Features Summary

**Child Mode (2 tabs):**
- Rewards tab - spend earned time on reward apps
- Learning tab - earn time through learning apps

**Parent Mode (4 sections):**
- Dashboard - usage overview, time bank, streaks
- Learning Apps - configure learning apps
- Reward Apps - configure reward apps
- Settings - pairing, subscription, web blocking

---

## Recommended Screenshot Sequence (Narrative Story Flow)

The screenshots tell a progressive story that explains the COMPLETE concept including enforcement:

**Story Arc:**
```
HOOK → EARN → BLOCKED (if not earned) → SPEND → TIME'S UP (auto-lock) → HABITS → PARENT → FAMILY
```

---

### Screenshot 1: THE HOOK
**Headline:** "REWARD Screen Time, Don't Restrict It"

**Story Purpose:** Trigger curiosity - "What does reward screen time mean?"

**Screen to Capture:** Child mode showing `TimeBankCard` with time balance

**Key Elements to Show:**
- Large circular `TimeBalanceRing` with available minutes (e.g., "45 MIN AVAILABLE")
- Game controller icon in center
- Yellow-to-teal gradient ring
- EARNED / USED breakdown visible

**File Path:** `Views/ChildMode/ChildDashboardView.swift`, `Views/ChildMode/Components/TimeBankCard.swift`

---

### Screenshot 2: THE EXPLANATION - How Kids Earn
**Headline:** "EARN Time with Learning Apps"

**Story Purpose:** Explain the "earn" concept - answer "How does it work?"

**Screen to Capture:** `LearningTabView` showing learning apps

**Key Elements to Show:**
- Learning apps list with TIME EARNED per app clearly visible
- Example: "Duolingo - 15 min earned today"
- Teal color theme
- Book icon header
- Shows the INPUT side of the equation

**File Path:** `Views/LearningTabView.swift`

---

### Screenshot 3: THE ENFORCEMENT - Learning Required Shield
**Headline:** "LEARN First, Play Later"

**Story Purpose:** Show what happens if they DON'T earn - "What if they skip learning?"

**Screen to Capture:** **LEARNING GOAL SHIELD** (system overlay)

**Key Elements to Show:**
- Teal background (#00A6A6)
- Book icon (`book.fill`)
- Title: "Learning Time First!"
- Message: "Complete 15 minutes of learning to unlock this app"
- Peach-colored button (#FFB4A3)
- Shows app is BLOCKED until learning is done

**Why Critical:** This shows the app actually ENFORCES the earn mechanic - not just tracking

**File Path:** `ShieldConfigurationExtension/ShieldConfigurationExtension.swift`
**Note:** This is a SYSTEM-LEVEL shield overlay, not an in-app view

---

### Screenshot 4: THE PAYOFF - How Kids Spend
**Headline:** "UNLOCK Your Favorite Apps"

**Story Purpose:** Show the reward - "What happens AFTER they learn?"

**Screen to Capture:** `RewardsTabView` showing reward apps (or app launching successfully)

**Key Elements to Show:**
- Reward apps list (games, YouTube, TikTok)
- TIME AVAILABLE displayed
- Coral color theme
- Gift icon header
- Shows apps are now UNLOCKED

**File Path:** `Views/RewardsTabView.swift`

---

### Screenshot 5: THE AUTO-LOCK - Time's Up Shield
**Headline:** "AUTO-LOCK When Time's Up"

**Story Purpose:** Show automatic enforcement - "What happens when time runs out?"

**Screen to Capture:** **REWARD TIME EXPIRED SHIELD** (system overlay)

**Key Elements to Show:**
- Orange background (#F5A623)
- Timer icon (`timer`)
- Title: "Reward Time Finished"
- Message: "You used 45 minutes of reward time. Complete more learning to earn more!"
- Shows app AUTOMATICALLY locks when time is consumed

**Why Critical:** This shows parents don't have to enforce limits - the app does it automatically

**File Path:** `ShieldConfigurationExtension/ShieldConfigurationExtension.swift`
**Note:** This is a SYSTEM-LEVEL shield overlay, not an in-app view

---

### Screenshot 6: THE MOTIVATION - Streaks Build Habits
**Headline:** "BUILD Healthy Screen Habits"

**Story Purpose:** Show long-term engagement - "What happens over time?"

**Screen to Capture:** Streaks display (in parent dashboard or streak card)

**Key Elements to Show:**
- Streak count (e.g., "7 Day Streak!")
- Flame/fire icon
- Progress indicators
- Positive reinforcement messaging

**File Path:** `Views/ParentMode/Components/StreaksSummarySection.swift`

---

### Screenshot 7: THE PARENT ANGLE - Stay in Control
**Headline:** "PARENTS Stay in Control"

**Story Purpose:** Address parent concern - "But what about ME?"

**Screen to Capture:** `ParentDashboardView` overview

**Key Elements to Show:**
- Usage overview at a glance
- Time earned vs time used summary
- Charts and analytics
- Shows parents have visibility and control

**File Path:** `Views/ParentMode/ParentDashboardView.swift`

---

### Screenshot 8: THE CLOSE - One App, Two Experiences
**Headline:** "ONE App for the Whole Family"

**Story Purpose:** Clarify audience - "Who is this for?"

**Screen to Capture:** `ModeSelectionView`

**Key Elements to Show:**
- Split screen: Parent Space / Child Space
- Lock icon for parents, person icon for kids
- Clean, inviting design
- Shows dual-purpose clearly

**File Path:** `Views/ModeSelectionView.swift`

---

## Screenshot Capture Checklist

### Device Setup
- [ ] Use iPhone 15 Pro Max simulator (6.7" - 1290 x 2796)
- [ ] Set time to 9:41 AM (Apple standard)
- [ ] Full battery or hide status bar
- [ ] Light mode (unless dark mode is your brand)

### Data Preparation
- [ ] Set realistic time values (45 min, not 999)
- [ ] Use 7-day streak (achievable, aspirational)
- [ ] Configure 3-4 learning apps with recognizable icons
- [ ] Configure 3-4 reward apps (games, social)

### Capture Commands
```bash
# Set simulator to exact resolution
xcrun simctl io booted screenshot ~/Desktop/screenshot_1_hero.png
```

---

## Design Template Recommendations

### Headline Style (Match BePresent)
- **Format:** [VERB] + benefit phrase
- **Font:** Bold, large, white text on colored background
- **Placement:** Top 20% of screenshot

### Color Rotation by Screenshot
| # | Background | Accent |
|---|------------|--------|
| 1 | Teal gradient | Yellow |
| 2 | Light blue | Teal |
| 3 | Teal | White |
| 4 | Orange/Yellow | White |
| 5 | Coral gradient | White |
| 6 | Blue | White |
| 7 | Coral | White |
| 8 | Teal split | Cream |

### Device Frame
- Use iPhone 15 Pro frame (titanium black or natural)
- Consistent across all screenshots
- No outdated device frames

---

## Differentiation from BePresent

| BePresent | ScreenTime Rewards |
|-----------|-------------------|
| Individual focus | Family focus |
| "Block apps" messaging | "Earn time" messaging |
| Partner brand rewards (Headspace, etc.) | Intrinsic time rewards |
| Adult-oriented design | Kid-friendly + parent dashboard |
| Leaderboards with strangers | Family-only features |
| Complex schedules | Simple learning/reward categories |

---

## Screenshots → Views Mapping (Quick Reference)

| # | Screenshot | File Path |
|---|------------|-----------|
| 1 | Time Bank (Hook) | `Views/ChildMode/ChildDashboardView.swift` |
| 2 | Learning Apps | `Views/LearningTabView.swift` |
| 3 | Learning Shield | `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` *(system overlay)* |
| 4 | Reward Apps | `Views/RewardsTabView.swift` |
| 5 | Time's Up Shield | `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` *(system overlay)* |
| 6 | Streaks | `Views/ParentMode/Components/StreaksSummarySection.swift` |
| 7 | Parent Dashboard | `Views/ParentMode/ParentDashboardView.swift` |
| 8 | Mode Selection | `Views/ModeSelectionView.swift` |

---

## File Tree

```
ScreenTimeRewardsProject/ScreenTimeRewards/
├── Views/
│   ├── ChildMode/
│   │   ├── ChildDashboardView.swift          ← Screenshot 1
│   │   └── Components/
│   │       ├── TimeBankCard.swift            ← Screenshot 1 (component)
│   │       └── TimeBalanceRing.swift         ← Screenshot 1 (component)
│   ├── LearningTabView.swift                 ← Screenshot 2
│   ├── RewardsTabView.swift                  ← Screenshot 4
│   ├── ModeSelectionView.swift               ← Screenshot 8
│   └── ParentMode/
│       ├── ParentDashboardView.swift         ← Screenshot 7
│       └── Components/
│           └── StreaksSummarySection.swift   ← Screenshot 6
└── ShieldConfigurationExtension/
    └── ShieldConfigurationExtension.swift    ← Screenshots 3 & 5 (system shields)
```

---

## Shield Capture Instructions

Screenshots 3 & 5 are **iOS system-level shields** (not SwiftUI views):

**To capture Screenshot 3 (Learning Shield):**
1. Configure a reward app (e.g., YouTube)
2. Ensure learning goal is NOT completed
3. Try to open the reward app
4. Shield appears with "Learning Time First!" message
5. Capture screenshot

**To capture Screenshot 5 (Time's Up Shield):**
1. Configure a reward app with time earned
2. Use up all available reward time
3. Try to open the reward app again
4. Shield appears with "Reward Time Finished" message
5. Capture screenshot

---

## Files to Review Before Capture

1. `Views/ChildMode/ChildDashboardView.swift` - Child dashboard
2. `Views/ChildMode/Components/TimeBankCard.swift` - Time balance ring
3. `Views/ChildMode/Components/TimeBalanceRing.swift` - Animated ring
4. `Views/ParentMode/ParentDashboardView.swift` - Parent dashboard
5. `Views/ParentMode/Components/StreaksSummarySection.swift` - Streaks
6. `Views/ModeSelectionView.swift` - Mode selector
7. `Views/RewardsTabView.swift` - Reward apps tab
8. `Views/LearningTabView.swift` - Learning apps tab
9. `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` - Shield overlays

---

## Next Steps

1. Set up simulator with test data
2. Capture raw screenshots from each view
3. Design marketing template in Figma/Sketch
4. Apply template to all 8 screenshots
5. Export at required resolutions (6.7" and 6.5")
6. Upload to App Store Connect
