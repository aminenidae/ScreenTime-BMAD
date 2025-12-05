# App Detail View Redesign

## Overview
Redesign the app detail view (displayed when tapping an app card in Learning/Rewards tabs) with modern UI, improved typography, and usage charts.

## Goals
- Modern card layout with better spacing, shadows, and visual hierarchy
- Improved typography with better sizing and weights
- Simplified structure (remove placeholder "Ideas to Explore" section)
- Add usage charts showing daily, weekly, and monthly patterns

## File to Modify
- `ScreenTimeRewards/Views/ParentMode/AppUsageDetailViews.swift`

## Reference Files
- `ScreenTimeRewards/Views/ParentMode/DailyUsageChartCard.swift` - Existing chart implementation to follow
- `ScreenTimeRewards/Shared/UsagePersistence.swift` - Data model with `dailyHistory`

---

## Implementation Steps

### Step 1: Remove Placeholder Content
Remove the `extraIdeasCard` view:
- Delete the `extraIdeasCard` computed property
- Remove `extraIdeasCard` from `AppUsageDetailContent` body

### Step 2: Create Usage Chart Component
Add a new private struct `AppUsageChart` inside the file:

```swift
@available(iOS 16.0, *)
private struct AppUsageChart: View {
    let dailyHistory: [UsagePersistence.DailyUsageSummary]
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPeriod: ChartPeriod = .daily

    enum ChartPeriod: String, CaseIterable {
        case daily = "7 Days"
        case weekly = "4 Weeks"
        case monthly = "6 Months"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with period picker
            HStack {
                Text("Usage History")
                    .font(.headline)
                Spacer()
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(ChartPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Bar chart
            Chart {
                ForEach(chartData, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: xAxisUnit),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(accentColor.gradient)
                }
            }
            .frame(height: 180)
            .chartXAxis { ... }
            .chartYAxis { ... }
        }
        .padding(20)
        .background(...)
    }
}
```

**Chart Features:**
- Bar chart using Swift Charts (iOS 16+)
- Segmented picker for period selection (7 Days / 4 Weeks / 6 Months)
- Gradient fill using app's accent color
- Minutes on Y-axis, dates on X-axis
- Graceful fallback for iOS < 16

### Step 3: Update AppUsageDetailContent Body
Replace the current body structure:

```swift
var body: some View {
    ScrollView {
        VStack(spacing: 20) {
            // NEW: Usage chart (primary visual)
            if #available(iOS 16.0, *) {
                usageChartCard
            }

            // Existing: Quick stats (daily/weekly/monthly pills)
            usageBreakdownCard

            // Existing: Insights (streamlined)
            insightsCard

            // REMOVED: extraIdeasCard
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 100) // Space for Configure button
    }
    .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
}
```

### Step 4: Create usageChartCard Computed Property
Add to `AppUsageDetailContent`:

```swift
@available(iOS 16.0, *)
private var usageChartCard: some View {
    AppUsageChart(
        dailyHistory: dailyHistory,
        accentColor: accentColor
    )
}
```

### Step 5: Streamline Insights Card
Reduce insights to essential items only:
- Points earned today
- Total time ever
- Total points ever
- First used (keep)
- Remove "Last Updated" and "Last Reset" (less important)

### Step 6: Typography Improvements
Apply consistent typography:
- Card headers: `.font(.headline)`
- Primary values: `.font(.system(size: 28, weight: .bold))`
- Secondary labels: `.font(AppTheme.Typography.caption)`
- Use `AppTheme.textPrimary` and `AppTheme.textSecondary` consistently

---

## Visual Layout

```
┌─────────────────────────────────┐
│  [Toolbar: App Icon + Done]     │
├─────────────────────────────────┤
│                                 │
│  ┌───────────────────────────┐  │
│  │  Usage History            │  │
│  │  [7 Days|4 Weeks|6 Months]│  │
│  │  ┌─────────────────────┐  │  │
│  │  │  Bar Chart          │  │  │
│  │  │  ████ ██ ████ █ ███ │  │  │
│  │  └─────────────────────┘  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Today   │  Week   │ Month │  │
│  │  45m    │  3.2h   │  12h  │  │
│  │  90pts  │ 384pts  │ 1.4k  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Insights                  │  │
│  │ ⚡ Points today: 90 pts   │  │
│  │ ⏱ Total time: 24h        │  │
│  │ ⭐ Total points: 2,880    │  │
│  │ 📅 First used: Nov 15     │  │
│  └───────────────────────────┘  │
│                                 │
│  ╔═══════════════════════════╗  │
│  ║     Configure Button      ║  │
│  ╚═══════════════════════════╝  │
└─────────────────────────────────┘
```

---

## Technical Notes

1. **Data Source**: `dailyHistory: [UsagePersistence.DailyUsageSummary]` already passed to view

2. **Chart Data Aggregation**:
   - Daily: Use last 7 entries from `dailyHistory`
   - Weekly: Group by `weekOfYear` for last 4 weeks
   - Monthly: Group by month for last 6 months

3. **Color Scheme**:
   - Learning apps: `AppTheme.vibrantTeal`
   - Reward apps: `AppTheme.playfulCoral`

4. **iOS Compatibility**:
   - Charts require iOS 16+ - use `@available(iOS 16.0, *)`
   - Show fallback text for older iOS

5. **Shared Component**: Keep `AppUsageDetailContent` shared between `LearningAppDetailView` and `RewardAppDetailView`

---

## Testing Checklist
- [ ] Chart displays with real usage data
- [ ] Period switching works (7 Days → 4 Weeks → 6 Months)
- [ ] Empty state handled gracefully (no data yet)
- [ ] Dark mode appearance correct
- [ ] iPad layout works properly
- [ ] Configure button still functional
- [ ] "Ideas to Explore" section removed
- [ ] Both Learning and Reward detail views updated
