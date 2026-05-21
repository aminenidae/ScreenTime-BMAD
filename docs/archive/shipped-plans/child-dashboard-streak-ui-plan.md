# Child Dashboard Streak UI Component Implementation Plan (Per-App Streak Architecture)

## Overview
Create an engaging, child-friendly streak display component for the Child Dashboard that shows **aggregate streak progress across all reward apps**, motivates daily engagement, and celebrates milestone achievements. This plan has been updated to support the per-app streak system where each reward app tracks its own independent streak.

## ⚠️ Architecture Note
This plan has been updated to support **per-app streaks** (see `/Users/ameen/Documents/ScreenTime-BMAD/docs/streak-rewards-implementation-plan.md`). The UI now displays aggregate data while maintaining the original visual design and UX patterns.

## Design Goals
- **Motivational**: Encourage children to maintain their learning streak
- **Child-Friendly**: Use playful colors, animations, and clear visuals
- **Non-Intrusive**: Complement existing Time Bank card without overwhelming the dashboard
- **Progressive**: Show progress toward next milestone
- **Celebratory**: Reward streak achievements with visual feedback
- **Informative**: Provide clear, visual progress indicators for learning goals
- **Engaging**: Use dedicated detail views for deeper exploration of app-specific progress

---

## Design Specifications

### Visual Design
Following the existing child dashboard patterns:
- **Color Palette**:
  - Primary: `AppTheme.sunnyYellow` (flame/streak theme)
  - Secondary: `AppTheme.vibrantTeal` (progress)
  - Accent: `AppTheme.playfulCoral` (at-risk state)
- **Shape**: Rounded rectangle card (20px corner radius) matching TimeBankCard
- **Spacing**: 16px padding, consistent with dashboard grid
- **Typography**:
  - Header: System font, size 14, semibold, 1.5pt tracking
  - Streak count: System font, size 36-48, bold, rounded design
  - Labels: System font, size 11, medium, 1pt tracking

### Animation Pattern
Following TimeBalanceRing and TimeBankCard patterns:
- **Spring animations**: `response: 0.5-0.8, dampingFraction: 0.6-0.7`
- **Delays**: Stagger animations (0.2s, 0.3s, 0.4s)
- **Entrance**: Scale from 0.9 to 1.0, opacity 0 to 1
- **Celebration**: Confetti/sparkle effect on milestone achievement
- **Pulse**: Subtle glow when close to milestone

---

## Component Structure

### Primary Component: `ChildStreakCard`

**File: `ScreenTimeRewards/Views/ChildMode/Components/ChildStreakCard.swift`** (NEW)

**⚠️ Updated for Per-App Streak Architecture**

```swift
struct ChildStreakCard: View {
    // Per-app streak support: aggregate data across all apps
    let aggregateStreak: (current: Int, longest: Int, isAtRisk: Bool)
    let appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)]
    let nextMilestone: Int?
    let progress: Double
    let hasAnyStreaksEnabled: Bool

    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    @State private var showDetailView = false  // NEW: for multi-app detail view

    var body: some View {
        // Only show if any app has streaks enabled and aggregate streak > 0
        if hasAnyStreaksEnabled && aggregateStreak.current > 0 {
            VStack(spacing: 16) {
                headerSection
                streakDisplay
                milestoneProgress

                // NEW: Show detail button when multiple apps have streaks
                if appStreaks.count > 1 {
                    detailButton
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .onAppear { animateEntrance() }
            .sheet(isPresented: $showDetailView) {
                StreakDetailView(appStreaks: appStreaks)
            }
        }
    }

    // NEW: Detail view button
    private var detailButton: some View {
        Button(action: { showDetailView = true }) {
            HStack {
                Text("View All \(appStreaks.count) Streaks")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .foregroundColor(AppTheme.vibrantTeal)
        }
    }
}
```

**Key Changes from Original**:
- `currentStreak/longestStreak/isAtRisk` → `aggregateStreak` tuple (highest across all apps)
- `isEnabled` → `hasAnyStreaksEnabled` (any app has streaks enabled)
- Added `appStreaks` array for detail view
- Added `progress` for pre-calculated milestone progress
- Added detail view sheet for multi-app streak display

#### Subcomponents

**1. Header Section**
```swift
private var headerSection: some View {
    HStack(spacing: 8) {
        Image(systemName: "flame.fill")
            .font(.system(size: 18))
            .foregroundColor(AppTheme.sunnyYellow)
            .rotationEffect(.degrees(isAnimating ? 0 : -10))
            .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3),
                      value: isAnimating)

        Text("DAILY STREAK")
            .font(.system(size: 14, weight: .semibold))
            .tracking(1.5)
            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

        Spacer()

        // Longest streak badge (using aggregate data)
        if aggregateStreak.longest > aggregateStreak.current {
            bestStreakBadge
        }
    }
}
```

**Note**: Uses `aggregateStreak.longest` and `aggregateStreak.current` instead of separate parameters.

**2. Streak Display (Central Focus)**
```swift
private var streakDisplay: some View {
    HStack(spacing: 20) {
        // Flame icon ring (using pre-calculated progress)
        ZStack {
            Circle()
                .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 8)
                .frame(width: 80, height: 80)

            Circle()
                .trim(from: 0, to: progress)  // Using passed-in progress value
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.sunnyYellow, AppTheme.vibrantTeal],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 80, height: 80)
                .animation(.spring(response: 0.6, dampingFraction: 0.7),
                          value: progress)

            Image(systemName: "flame.fill")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.sunnyYellow)
                .shadow(color: AppTheme.sunnyYellow.opacity(0.3), radius: 8)
        }

        // Streak count (using aggregate data)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(aggregateStreak.current)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.sunnyYellow)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: aggregateStreak.current)

            Text(aggregateStreak.current == 1 ? "DAY" : "DAYS")
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }
    .scaleEffect(isAnimating ? 1 : 0.9)
    .opacity(isAnimating ? 1 : 0)
    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4),
              value: isAnimating)
}
```

**Note**: Progress ring now uses the passed-in `progress` value (calculated by StreakService), and streak count uses `aggregateStreak.current`.

**3. Milestone Progress**
```swift
private var milestoneProgress: some View {
    if let nextMilestone = nextMilestone {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .frame(height: 6)

                    // Progress fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal, AppTheme.sunnyYellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progressToNextMilestone,
                               height: 6)
                }
            }
            .frame(height: 6)

            // Milestone text
            HStack {
                Image(systemName: "target")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("\(daysUntilMilestone) more \(daysUntilMilestone == 1 ? "day" : "days") to \(nextMilestone)-day bonus!")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()
            }
        }
    }
}
```

**4. Best Streak Badge**
```swift
private var bestStreakBadge: some View {
    HStack(spacing: 4) {
        Image(systemName: "crown.fill")
            .font(.system(size: 10))
            .foregroundColor(AppTheme.sunnyYellow)

        Text("\(aggregateStreak.longest)")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(AppTheme.sunnyYellow)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
        Capsule()
            .fill(AppTheme.sunnyYellow.opacity(0.15))
    )
}
```

**Note**: Uses `aggregateStreak.longest` instead of separate parameter.

**5. At-Risk State Indicator**
```swift
// Add overlay when any app streak is at risk
.overlay {
    if aggregateStreak.isAtRisk {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                Text("Complete a goal today to keep your streak!")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(AppTheme.playfulCoral)
            .padding(8)
            .background(
                Capsule()
                    .fill(AppTheme.playfulCoral.opacity(0.1))
            )
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
```

**Note**: Uses `aggregateStreak.isAtRisk` which is `true` if **any** app streak is at risk.

---

## Celebration Component: `StreakMilestoneCelebration`

**File: `ScreenTimeRewards/Views/ChildMode/Components/StreakMilestoneCelebration.swift`** (NEW)

**⚠️ Updated for Per-App Streak Architecture** - Now shows which app achieved the milestone.

```swift
struct StreakMilestoneCelebration: View {
    let milestone: Int
    let bonusMinutes: Int
    let appName: String  // NEW: Show which app achieved the milestone
    @Binding var isPresented: Bool

    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Celebration card
            VStack(spacing: 24) {
                // Trophy/flame icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppTheme.sunnyYellow.opacity(0.3),
                                    AppTheme.sunnyYellow.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 64))
                        .foregroundColor(AppTheme.sunnyYellow)
                        .shadow(color: AppTheme.sunnyYellow.opacity(0.5), radius: 20)
                }

                // Milestone text (updated to show app name)
                VStack(spacing: 8) {
                    Text("\(milestone) DAY STREAK")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(2)
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("FOR \(appName.uppercased())!")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(AppTheme.vibrantTeal)

                    Text("You earned \(bonusMinutes) bonus minutes!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: .light))
                        .padding(.top, 4)
                }

                // Awesome button
                Button {
                    isPresented = false
                } label: {
                    Text("AWESOME!")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(AppTheme.vibrantTeal)
                        )
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
            )
            .padding(24)
            .confettiCannon(counter: $confettiTrigger, num: 50, radius: 300)
        }
        .onAppear {
            confettiTrigger += 1
        }
    }
}
```

**Key Changes**:
- Added `appName` parameter
- Updated milestone text to show: "7 DAY STREAK FOR YOUTUBE!"
- Makes it clear which app's streak achieved the milestone

**Note**: Requires adding `ConfettiSwiftUI` package or custom confetti implementation.

---

## StreakDetailView Component (NEW)

**File: `ScreenTimeRewards/Views/ChildMode/Components/StreakDetailView.swift`** (NEW)

Shows individual app streaks when multiple apps are being tracked:

```swift
import SwiftUI

struct StreakDetailView: View {
    let appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)]
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(appStreaks, id: \.appName) { streak in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(streak.appName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            if streak.isAtRisk {
                                Text("At Risk - Complete a goal today!")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.playfulCoral)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(AppTheme.sunnyYellow)
                            Text("\(streak.currentStreak)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("All Streaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
    }
}
```

**When to Show**: Automatically appears as a sheet when the "View All X Streaks" button is tapped in ChildStreakCard (only shown when `appStreaks.count > 1`).

---

## Child App Detail View (NEW - Comprehensive Reward App View)

**File: `ScreenTimeRewards/Views/ChildMode/ChildAppDetailView.swift`** (NEW)

### Overview
A full-screen detail view that appears when a child taps on a reward app card. This view provides comprehensive information about the app including learning requirements, streak progress, time remaining, and usage statistics - all presented in a child-friendly, visual manner.

### Navigation Entry Point
**From:** `RewardAppListSection.swift` - Make each reward app row tappable
**Method:** Sheet presentation with `@State` binding

### Component Structure

The detail view is organized into distinct cards, each providing specific information:

---

### 1. App Hero Header Card 🎮

**Purpose:** Immediately identify which app and show current status

```swift
struct AppHeroHeaderCard: View {
    let appName: String
    let token: ApplicationToken
    let isUnlocked: Bool
    let remainingMinutes: Int
    let totalDailyLimit: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            // Large app icon
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(2.5)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }

            // App name
            Text(appName.uppercased())
                .font(.system(size: 24, weight: .bold))
                .tracking(1.5)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            // Status badge
            statusBadge

            // Time remaining display
            timeRemainingDisplay
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.playfulCoral.opacity(0.2), lineWidth: 2)
                )
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 14))
            Text(isUnlocked ? "UNLOCKED" : "LOCKED")
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
        }
        .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : AppTheme.playfulCoral)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill((isUnlocked ? AppTheme.vibrantTeal : AppTheme.playfulCoral).opacity(0.15))
        )
    }

    private var timeRemainingDisplay: some View {
        VStack(spacing: 4) {
            Text("\(remainingMinutes)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(timeColor)

            Text("MINUTES LEFT TODAY")
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }

    private var timeColor: Color {
        let percentage = Double(remainingMinutes) / Double(totalDailyLimit)
        if percentage > 0.5 { return AppTheme.vibrantTeal }
        if percentage > 0.2 { return AppTheme.sunnyYellow }
        return AppTheme.playfulCoral
    }
}
```

---

### 2. Learning Progress Card 📚 (Primary Card)

**Purpose:** Show which learning apps need to be completed to unlock this reward app

```swift
struct LearningProgressCard: View {
    let linkedLearningApps: [LinkedLearningApp]
    let learningProgress: [String: (used: Int, required: Int, goalMet: Bool)] // Key: logicalID
    let unlockMode: UnlockMode
    let isUnlocked: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection

            // Progress bars for each linked app
            ForEach(linkedLearningApps, id: \.logicalID) { linkedApp in
                learningAppProgressRow(for: linkedApp)
            }

            // Unlock mode explanation
            if !isUnlocked {
                unlockModeExplanation
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.vibrantTeal)

            Text(isUnlocked ? "YOU'VE EARNED THIS TIME BY:" : "COMPLETE THESE TO UNLOCK")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()
        }
    }

    private func learningAppProgressRow(for linkedApp: LinkedLearningApp) -> some View {
        let progress = learningProgress[linkedApp.logicalID] ?? (0, linkedApp.minutesRequired, false)
        let percentage = Double(progress.used) / Double(progress.required)

        return VStack(alignment: .leading, spacing: 8) {
            // App name and status
            HStack {
                // Icon placeholder (would use actual app token in real implementation)
                Circle()
                    .fill(AppTheme.vibrantTeal.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.vibrantTeal)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("LEARNING APP NAME") // Would be resolved from logicalID
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("\(linkedApp.goalPeriod.displayName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                if progress.goalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .frame(height: 24)

                    // Filled progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: progress.goalMet
                                    ? [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)]
                                    : [AppTheme.sunnyYellow, AppTheme.vibrantTeal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(percentage, 1.0), height: 24)

                    // Progress text overlay
                    HStack {
                        Spacer()
                        Text("\(progress.used) / \(progress.required) MIN")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.trailing, 8)
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.vertical, 4)
    }

    private var unlockModeExplanation: some View {
        HStack(spacing: 8) {
            Image(systemName: unlockMode == .all ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.playfulCoral)

            Text(unlockMode == .all ? "Complete ALL apps above" : "Complete ANY ONE app above")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.playfulCoral.opacity(0.08))
        )
    }
}
```

---

### 3. App-Specific Streak Card 🔥

**Purpose:** Show streak progress for THIS specific reward app

```swift
struct AppStreakCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let nextMilestone: Int?
    let bonusMinutesEarned: Int
    let progress: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("YOUR STREAK FOR THIS APP")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            HStack(spacing: 24) {
                // Flame icon with ring
                ZStack {
                    Circle()
                        .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AppTheme.sunnyYellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 60, height: 60)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.sunnyYellow)
                }

                // Streak stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("\(currentStreak)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.sunnyYellow)

                        Text(currentStreak == 1 ? "DAY" : "DAYS")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .offset(y: 8)
                    }

                    if let nextMilestone = nextMilestone {
                        Text("\(nextMilestone - currentStreak) more to \(nextMilestone)-day bonus!")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Spacer()
            }

            // Bonus earned
            if bonusMinutesEarned > 0 {
                HStack {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 12))
                    Text("+\(bonusMinutesEarned) bonus minutes earned from streaks!")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AppTheme.sunnyYellow)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.sunnyYellow.opacity(0.1))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }
}
```

---

### 4. Time Bank Visualization Card ⏱️

**Purpose:** Visual representation of time available vs. daily limit

```swift
struct TimeBankVisualizationCard: View {
    let remainingMinutes: Int
    let dailyLimit: Int
    let usedMinutes: Int
    @Environment(\.colorScheme) var colorScheme

    private var percentage: Double {
        Double(remainingMinutes) / Double(dailyLimit)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ringColor)

                Text("TIME AVAILABLE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 20)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor, ringColor.opacity(0.6)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 140)

                VStack(spacing: 4) {
                    Text("\(remainingMinutes)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(ringColor)

                    Text("of \(dailyLimit) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            // Helper text
            Text("Resets at midnight")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private var ringColor: Color {
        if percentage > 0.5 { return AppTheme.vibrantTeal }
        if percentage > 0.2 { return AppTheme.sunnyYellow }
        return AppTheme.playfulCoral
    }
}
```

---

### 5. Usage Today Card 📊 (Optional - If Unlocked)

**Purpose:** Show usage stats for today in an encouraging way

```swift
struct UsageTodayCard: View {
    let usedMinutes: Int
    let previousDayUsage: Int?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("TODAY'S USAGE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Big number
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(usedMinutes)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("MINUTES USED")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            // Comparison to yesterday
            if let previousDayUsage = previousDayUsage {
                comparisonRow(current: usedMinutes, previous: previousDayUsage)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private func comparisonRow(current: Int, previous: Int) -> some View {
        let difference = current - previous
        let isMore = difference > 0

        return HStack(spacing: 6) {
            Image(systemName: isMore ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(isMore ? AppTheme.playfulCoral : AppTheme.vibrantTeal)

            Text("\(abs(difference)) minutes \(isMore ? "more" : "less") than yesterday")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((isMore ? AppTheme.playfulCoral : AppTheme.vibrantTeal).opacity(0.08))
        )
    }
}
```

---

### 6. Quick Stats Card ⭐ (Optional - Encouraging Stats)

**Purpose:** Fun, motivational statistics

```swift
struct QuickStatsCard: View {
    let daysUsedThisWeek: Int
    let longestSessionMinutes: Int
    let totalEarnedThisMonth: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("FUN STATS")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Stats grid
            VStack(spacing: 12) {
                statRow(icon: "calendar", label: "Used this week", value: "\(daysUsedThisWeek) days")
                statRow(icon: "timer", label: "Longest session", value: "\(longestSessionMinutes) min")
                statRow(icon: "gift", label: "Total earned this month", value: "\(totalEarnedThisMonth) min")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.sunnyYellow)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }
}
```

---

### Full Detail View Implementation

```swift
struct ChildAppDetailView: View {
    let snapshot: RewardAppSnapshot
    let unlockedApp: UnlockedRewardApp?
    let linkedLearningApps: [LinkedLearningApp]
    let learningProgress: [String: (used: Int, required: Int, goalMet: Bool)]
    let unlockMode: UnlockMode
    let streakData: (current: Int, longest: Int, nextMilestone: Int?, progress: Double, bonusEarned: Int)?
    let dailyLimit: Int
    let previousDayUsage: Int?

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var isUnlocked: Bool {
        unlockedApp != nil
    }

    private var remainingMinutes: Int {
        unlockedApp?.remainingMinutes ?? 0
    }

    private var usedMinutes: Int {
        Int(snapshot.totalSeconds / 60)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Hero Header
                    AppHeroHeaderCard(
                        appName: snapshot.displayName,
                        token: snapshot.token,
                        isUnlocked: isUnlocked,
                        remainingMinutes: remainingMinutes,
                        totalDailyLimit: dailyLimit
                    )

                    // 2. Learning Progress (Most Important!)
                    LearningProgressCard(
                        linkedLearningApps: linkedLearningApps,
                        learningProgress: learningProgress,
                        unlockMode: unlockMode,
                        isUnlocked: isUnlocked
                    )

                    // 3. Streak Progress (if enabled for this app)
                    if let streakData = streakData {
                        AppStreakCard(
                            currentStreak: streakData.current,
                            longestStreak: streakData.longest,
                            nextMilestone: streakData.nextMilestone,
                            bonusMinutesEarned: streakData.bonusEarned,
                            progress: streakData.progress
                        )
                    }

                    // 4. Time Bank Visualization
                    if isUnlocked {
                        TimeBankVisualizationCard(
                            remainingMinutes: remainingMinutes,
                            dailyLimit: dailyLimit,
                            usedMinutes: usedMinutes
                        )
                    }

                    // 5. Usage Today (if unlocked)
                    if isUnlocked && usedMinutes > 0 {
                        UsageTodayCard(
                            usedMinutes: usedMinutes,
                            previousDayUsage: previousDayUsage
                        )
                    }

                    // 6. Quick Stats (optional)
                    if isUnlocked {
                        QuickStatsCard(
                            daysUsedThisWeek: 4, // Would be calculated
                            longestSessionMinutes: 25, // Would be calculated
                            totalEarnedThisMonth: 180 // Would be calculated
                        )
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("BACK")
                                .font(.system(size: 14, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundColor(AppTheme.playfulCoral)
                    }
                }
            }
        }
    }
}
```

---

### Navigation Integration

**Update RewardAppListSection.swift:**

```swift
// Add state for detail view
@State private var selectedApp: RewardDetailData?

private struct RewardDetailData: Identifiable {
    let snapshot: RewardAppSnapshot
    let unlockedApp: UnlockedRewardApp?
    let config: AppScheduleConfiguration?
    var id: String { snapshot.id }
}

// Make reward app rows tappable
private func rewardAppRow(snapshot: RewardAppSnapshot, unlockedApp: UnlockedRewardApp?) -> some View {
    // ... existing row content ...
    .contentShape(Rectangle())
    .onTapGesture {
        let config = scheduleService.getSchedule(for: snapshot.logicalID)
        selectedApp = RewardDetailData(
            snapshot: snapshot,
            unlockedApp: unlockedApp,
            config: config
        )
    }
}

// Add sheet presentation
.sheet(item: $selectedApp) { detailData in
    ChildAppDetailView(
        snapshot: detailData.snapshot,
        unlockedApp: detailData.unlockedApp,
        linkedLearningApps: detailData.config?.linkedLearningApps ?? [],
        learningProgress: calculateLearningProgress(for: detailData.config),
        unlockMode: detailData.config?.unlockMode ?? .all,
        streakData: getStreakData(for: detailData.snapshot.logicalID),
        dailyLimit: detailData.config?.dailyLimits.todayLimit ?? 60,
        previousDayUsage: nil // Would fetch from historical data
    )
}
```

---

## Integration with ChildDashboardView

**File: `ScreenTimeRewards/Views/ChildDashboardView.swift`** (MODIFY)

**⚠️ Updated for Per-App Streak Architecture**

### Changes Required:

**1. Add State for Streak Data**
```swift
// After line 10
@StateObject private var streakService = StreakService.shared
@State private var showMilestoneCelebration = false
@State private var achievedMilestone: Int = 0
@State private var milestoneBonus: Int = 0
@State private var milestoneAppName: String = ""  // NEW: Track which app achieved milestone
```

**2. Add Streak Card to ScrollView (Updated for Per-App)**
```swift
// After TimeBankCard (after line 64), before LearningAppListSection
let deviceID = DeviceModeManager.shared.deviceID
let aggregateStreak = streakService.getAggregateStreak(for: deviceID)

// Build app-specific streak list for detail view
let appStreaks = viewModel.rewardSnapshots.compactMap { snapshot -> (String, Int, Bool)? in
    guard let record = streakService.streakRecords[snapshot.logicalID] else { return nil }
    return (snapshot.displayName, Int(record.currentStreak), record.isAtRisk)
}

// Get settings for next milestone calculation (from app with highest streak)
let highestAppID = streakService.streakRecords
    .max(by: { $0.value.currentStreak < $1.value.currentStreak })?
    .key

let streakSettings = highestAppID.flatMap { appID in
    viewModel.rewardSnapshots.first(where: { $0.logicalID == appID })?.config?.streakSettings
}

ChildStreakCard(
    aggregateStreak: aggregateStreak,
    appStreaks: appStreaks,
    nextMilestone: streakSettings?.milestones
        .filter { $0 > aggregateStreak.current }
        .sorted().first,
    progress: streakService.progressToNextMilestone(
        current: aggregateStreak.current,
        settings: streakSettings ?? .defaultSettings
    ),
    hasAnyStreaksEnabled: !streakService.streakRecords.isEmpty
)
```

**3. Add Celebration Overlay (Updated with App Name)**
```swift
// At the end of body, before closing ZStack
.overlay {
    if showMilestoneCelebration {
        StreakMilestoneCelebration(
            milestone: achievedMilestone,
            bonusMinutes: milestoneBonus,
            appName: milestoneAppName,  // NEW: Show which app
            isPresented: $showMilestoneCelebration
        )
        .transition(.scale.combined(with: .opacity))
        .zIndex(999)
    }
}
```

**4. Add Notification Observer (Updated to Extract App Name)**
```swift
.onReceive(NotificationCenter.default.publisher(for: .streakMilestoneAchieved)) { notification in
    if let milestone = notification.userInfo?["milestone"] as? Int,
       let bonus = notification.userInfo?["bonusMinutes"] as? Int,
       let appLogicalID = notification.userInfo?["appLogicalID"] as? String {  // NEW

        achievedMilestone = milestone
        milestoneBonus = bonus

        // Get app name from logicalID
        if let appName = viewModel.rewardSnapshots
            .first(where: { $0.logicalID == appLogicalID })?.displayName {
            milestoneAppName = appName
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showMilestoneCelebration = true
        }
    }
}
```

---

## Data Flow

### StreakService Extensions Needed

**File: `ScreenTimeRewards/Services/StreakService.swift`** (MODIFY)

**⚠️ Updated for Per-App Streak Architecture**

Add helper methods (updated signatures):
```swift
extension StreakService {
    /// Get aggregate streak across all apps
    func getAggregateStreak(for childDeviceID: String) -> (current: Int, longest: Int, isAtRisk: Bool) {
        guard !streakRecords.isEmpty else {
            return (current: 0, longest: 0, isAtRisk: false)
        }

        let current = streakRecords.values.map { Int($0.currentStreak) }.max() ?? 0
        let longest = streakRecords.values.map { Int($0.longestStreak) }.max() ?? 0
        let isAtRisk = streakRecords.values.contains { $0.isAtRisk }

        return (current: current, longest: longest, isAtRisk: isAtRisk)
    }

    /// Get the next uncompleted milestone for a specific current streak value
    func getNextMilestone(for currentStreak: Int, settings: AppStreakSettings) -> Int? {
        return settings.milestones
            .filter { $0 > currentStreak }
            .sorted()
            .first
    }

    /// Calculate progress toward next milestone (0.0 to 1.0)
    func progressToNextMilestone(current: Int, settings: AppStreakSettings) -> Double {
        guard let next = getNextMilestone(for: current, settings: settings) else { return 0.0 }

        // Find previous milestone or 0
        let previous = settings.milestones
            .filter { $0 < current }
            .sorted()
            .last ?? 0

        let range = Double(next - previous)
        let progress = Double(current - previous)

        return range > 0 ? min(progress / range, 1.0) : 0.0
    }

    /// Post notification when milestone achieved (includes app context)
    func notifyMilestoneAchieved(milestone: Int, bonusMinutes: Int, appLogicalID: String) {
        NotificationCenter.default.post(
            name: .streakMilestoneAchieved,
            object: nil,
            userInfo: [
                "milestone": milestone,
                "bonusMinutes": bonusMinutes,
                "appLogicalID": appLogicalID  // NEW: Include app context
            ]
        )
    }
}

// Add notification name
extension Notification.Name {
    static let streakMilestoneAchieved = Notification.Name("streakMilestoneAchieved")
}

// Extension for StreakRecord to support isAtRisk
extension StreakRecord {
    var isAtRisk: Bool {
        guard let lastDate = lastActivityDate else { return false }
        return !Calendar.current.isDateInToday(lastDate) && currentStreak > 0
    }
}
```

**Key Changes**:
- `getAggregateStreak()` - NEW: Calculates aggregate across all app streaks
- `getNextMilestone(for:settings:)` - Updated to take current streak value and settings as parameters
- `progressToNextMilestone(current:settings:)` - Updated to take current streak value and settings
- `notifyMilestoneAchieved(milestone:bonusMinutes:appLogicalID:)` - Updated to include app context

---

## Component States & Behaviors

### Display States

| State | Condition | Visual Treatment |
|-------|-----------|------------------|
| **Active Streak** | `currentStreak > 0, !isAtRisk` | Normal display with yellow flame, progress ring |
| **At Risk** | `isAtRisk == true` | Add coral warning banner at bottom |
| **Near Milestone** | `currentStreak >= nextMilestone - 2` | Subtle pulse glow on flame icon |
| **Hidden** | `!isEnabled || currentStreak == 0` | Component not rendered |
| **Milestone Achieved** | Just hit milestone | Trigger celebration overlay |

### Animations

**Entrance Animation:**
```swift
func animateEntrance() {
    withAnimation(.easeOut(duration: 0.6)) {
        isAnimating = true
    }
}
```

**Streak Increment:**
- Number changes with `contentTransition(.numericText())`
- Progress ring animates smoothly with spring
- Optional: Brief scale pulse (1.0 → 1.05 → 1.0)

**Near Milestone Pulse:**
```swift
.overlay {
    if isNearMilestone {
        Circle()
            .stroke(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 3)
            .scaleEffect(1.2)
            .opacity(0.5)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isNearMilestone
            )
    }
}
```

---

## Accessibility

### VoiceOver Support
```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("Daily streak: \(currentStreak) \(currentStreak == 1 ? "day" : "days")")
.accessibilityHint(nextMilestone != nil
    ? "\(daysUntilMilestone) more days until \(nextMilestone!)-day bonus"
    : "Keep learning daily to maintain your streak")
```

### Dynamic Type
- Support larger text sizes with `@ScaledMetric`
- Ensure minimum touch target size (44x44 points)

### Color Contrast
- Yellow flame on white background: Meets WCAG AA
- All text colors use AppTheme contrast-safe colors

---

## Edge Cases

1. **No Streak Data**: Hide component entirely
2. **Streak Just Started (Day 1)**: Show encouraging message "Great start!"
3. **No Next Milestone**: Show "Keep going!" message instead of progress bar
4. **Multiple Milestones Same Day**: Only show celebration for highest
5. **Streak Reset**: Briefly show "Streak reset - start fresh!" then hide

---

## Files Summary

**⚠️ Updated for Per-App Streak Architecture + Child App Detail View**

### New Files (10)
1. `ScreenTimeRewards/Views/ChildMode/Components/ChildStreakCard.swift` - Main streak display card (with per-app support)
2. `ScreenTimeRewards/Views/ChildMode/Components/StreakMilestoneCelebration.swift` - Milestone celebration (with app name)
3. `ScreenTimeRewards/Views/ChildMode/Components/StreakDetailView.swift` - Multi-app streak detail view
4. `ScreenTimeRewards/Views/ChildMode/ChildAppDetailView.swift` - **NEW**: Full reward app detail view
5. `ScreenTimeRewards/Views/ChildMode/Components/AppHeroHeaderCard.swift` - **NEW**: App detail hero section
6. `ScreenTimeRewards/Views/ChildMode/Components/LearningProgressCard.swift` - **NEW**: Visual progress bars for learning requirements
7. `ScreenTimeRewards/Views/ChildMode/Components/AppStreakCard.swift` - **NEW**: Per-app streak display in detail view
8. `ScreenTimeRewards/Views/ChildMode/Components/TimeBankVisualizationCard.swift` - **NEW**: Circular time remaining visualization
9. `ScreenTimeRewards/Views/ChildMode/Components/UsageTodayCard.swift` - **NEW**: Today's usage stats with comparison
10. `ScreenTimeRewards/Views/ChildMode/Components/QuickStatsCard.swift` - **NEW**: Fun motivational statistics

### Modified Files (3)
1. `ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift` - Add streak card with aggregate data and celebration overlay
2. `ScreenTimeRewards/Services/StreakService.swift` - Add helper methods for aggregation and per-app calculations
3. `ScreenTimeRewards/Views/ChildMode/Components/RewardAppListSection.swift` - **NEW**: Make reward app rows tappable with sheet presentation

### Optional Additions
1. Confetti animation library or custom implementation
2. Sound effects for milestone achievements
3. Haptic feedback on milestone

---

## Testing Checklist

**⚠️ Updated for Per-App Streak Architecture**

### Aggregate Display Tests
- [ ] Streak card displays correct aggregate (highest) across multiple apps
- [ ] Aggregate current streak calculated correctly (max of all app streaks)
- [ ] Aggregate longest streak calculated correctly (max of all app streaks)
- [ ] At-risk indicator shows when **any** app streak is at risk
- [ ] Component hidden when no apps have streaks enabled or all streaks = 0

### Multi-App Features
- [ ] "View All X Streaks" button appears when `appStreaks.count > 1`
- [ ] Detail button hidden when only one app has a streak
- [ ] StreakDetailView opens correctly and displays all app streaks
- [ ] Individual app names displayed correctly in detail view
- [ ] At-risk indicator shown per-app in detail view
- [ ] StreakDetailView dismisses properly on "Done" tap

### Visual & Animation Tests
- [ ] Progress ring animates smoothly when streak increments
- [ ] Milestone progress bar shows correct percentage for highest streak
- [ ] Celebration overlay appears on milestone achievement
- [ ] Celebration shows correct app name (e.g., "7 DAY STREAK FOR YOUTUBE!")
- [ ] VoiceOver announces aggregate streak information correctly
- [ ] Dark mode colors are readable and on-brand
- [ ] Animations perform smoothly on older devices
- [ ] Best streak badge displays when aggregate current < aggregate longest

### Data Integration Tests
- [ ] Aggregate calculation updates when any app streak changes
- [ ] Notification payload includes appLogicalID correctly
- [ ] App name resolved from logicalID in celebration
- [ ] Next milestone calculated from app with highest streak
- [ ] Progress calculated using correct app's settings

---

## Implementation Order

1. **Phase 1**: Create `ChildStreakCard.swift` with basic layout and static data
2. **Phase 2**: Add animations (entrance, progress ring, pulse)
3. **Phase 3**: Integrate with ChildDashboardView
4. **Phase 4**: Add StreakService helper methods
5. **Phase 5**: Create `StreakMilestoneCelebration.swift`
6. **Phase 6**: Wire up notification system for celebrations
7. **Phase 7**: Add at-risk state and edge case handling
8. **Phase 8**: Polish animations and test on device

---

## Design Inspiration

The design follows these principles from the existing child dashboard:
- **Playful but not childish**: Clean, modern design with fun colors
- **Clear hierarchy**: Large numbers, small labels
- **Progressive disclosure**: Show only what's relevant
- **Encouraging**: Positive language and visual rewards
- **Consistent**: Matches TimeBankCard style and patterns

---

## Future Enhancements (Post-MVP)

- Streak freeze/shield power-up (use one to protect streak)
- Weekly streak summary view
- Share streak achievement with parent
- Streak leaderboard (if multi-child family)
- Custom streak goals beyond default milestones
- Animated flame that grows with longer streaks
