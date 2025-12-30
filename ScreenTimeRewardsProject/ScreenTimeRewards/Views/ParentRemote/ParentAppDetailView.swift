import SwiftUI

/// Detailed view for an app in the parent dashboard
/// Shows comprehensive app information including usage history, schedule, and unlock requirements
struct ParentAppDetailView: View {
    let config: FullAppConfigDTO
    var shieldState: ShieldStateDTO?
    var appHistory: [DailyUsageHistoryDTO]

    @State private var selectedTimeRange: TimeRange = .week
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
    }

    // MARK: - Computed Properties

    var displayName: String {
        if !config.displayName.isEmpty && !config.displayName.hasPrefix("Unknown") {
            return config.displayName
        }
        let appNumber = abs(config.logicalID.hashValue) % 100
        return "Privacy Protected \(config.category) App #\(appNumber)"
    }

    var categoryColor: Color {
        config.category == "Learning" ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    var filteredHistory: [DailyUsageHistoryDTO] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -selectedTimeRange.days, to: today)!
        return appHistory.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    var totalSeconds: Int {
        filteredHistory.reduce(0) { $0 + $1.seconds }
    }

    var todaySeconds: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appHistory.first { calendar.isDate($0.date, inSameDayAs: today) }?.seconds ?? 0
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Usage Summary
                usageSummaryCard

                // Usage Chart
                usageChartSection

                // Schedule (if configured)
                if config.scheduleConfig != nil {
                    scheduleSection
                }

                // Unlock Requirements (Reward apps only)
                if config.category == "Reward" && !config.linkedLearningApps.isEmpty {
                    unlockRequirementsSection
                }

                // Streak Bonus (if enabled)
                if let streak = config.streakSettings, streak.isEnabled {
                    streakBonusSection(streak)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Large App Icon
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: config.category == "Learning" ? "book.fill" : "gamecontroller.fill")
                            .font(.system(size: 36))
                            .foregroundColor(categoryColor)
                    )

                // Shield state indicator
                if let state = shieldState {
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(state.isUnlocked ? .green : .red)
                        .padding(6)
                        .background(Circle().fill(Color(UIColor.systemBackground)))
                        .offset(x: 6, y: 6)
                }
            }

            // App Name
            Text(displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)

            // Category Badge + Status
            HStack(spacing: 12) {
                // Category Badge
                Text(config.category)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(categoryColor)
                    .cornerRadius(12)

                // Status Badge (for reward apps)
                if let state = shieldState {
                    Text(state.isUnlocked ? "UNLOCKED" : "BLOCKED")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(state.isUnlocked ? Color.green : Color.red)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.vertical)
    }

    // MARK: - Usage Summary Card

    private var usageSummaryCard: some View {
        VStack(spacing: 12) {
            Text("Usage Summary")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                // Last N Days
                VStack(spacing: 4) {
                    Text(TimeFormatting.formatSeconds(totalSeconds))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(categoryColor)
                    Text("Last \(selectedTimeRange.days) days")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 40)

                // Today
                VStack(spacing: 4) {
                    Text(TimeFormatting.formatSeconds(todaySeconds))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Text("Today")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Usage Chart Section

    private var usageChartSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Usage History")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
            }

            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.largeTitle)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Text("No usage data")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            } else {
                UsageBarChart(
                    history: filteredHistory,
                    categoryColor: categoryColor,
                    colorScheme: colorScheme
                )
                .frame(height: 150)
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(spacing: 12) {
            Text("Schedule")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let schedule = config.scheduleConfig {
                VStack(spacing: 8) {
                    // Time Window
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(categoryColor)
                        Text("Allowed Time")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(schedule.todayTimeWindow.isFullDay ? "All Day" : schedule.todayTimeWindow.displayString)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }

                    Divider()

                    // Daily Limit
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(categoryColor)
                        Text("Daily Limit")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(schedule.dailyLimits.displaySummary)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Unlock Requirements Section

    private var unlockRequirementsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Unlock Requirements")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Unlock mode badge
                Text(config.unlockMode == .all ? "Complete ALL" : "Complete ANY")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(config.unlockMode == .all ? Color.orange : Color.blue)
                    .cornerRadius(8)
            }

            VStack(spacing: 8) {
                ForEach(config.linkedLearningApps, id: \.logicalID) { linkedApp in
                    HStack {
                        Image(systemName: "book.fill")
                            .foregroundColor(AppTheme.vibrantTeal)
                            .frame(width: 24)

                        Text(linkedApp.displayName ?? "Learning App")
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        Spacer()

                        Text("\(linkedApp.minutesRequired) min/day")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Streak Bonus Section

    private func streakBonusSection(_ streak: AppStreakSettings) -> some View {
        VStack(spacing: 12) {
            Text("Streak Bonus")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(streak.bonusType == .percentage ? "\(streak.bonusValue)% bonus" : "\(streak.bonusValue) min bonus")
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Earned for maintaining daily streaks")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Usage Bar Chart

private struct UsageBarChart: View {
    let history: [DailyUsageHistoryDTO]
    let categoryColor: Color
    let colorScheme: ColorScheme

    var maxSeconds: Int {
        history.map { $0.seconds }.max() ?? 1
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(4, (geometry.size.width - CGFloat(history.count - 1) * 4) / CGFloat(history.count))
            let maxHeight = geometry.size.height - 30 // Space for labels

            VStack(spacing: 0) {
                // Bars
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(history, id: \.id) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(categoryColor)
                                .frame(
                                    width: barWidth,
                                    height: max(4, CGFloat(day.seconds) / CGFloat(maxSeconds) * maxHeight)
                                )
                        }
                    }
                }
                .frame(height: maxHeight)

                // Date labels (show first, middle, last)
                HStack {
                    if let first = history.first {
                        Text(formatShortDate(first.date))
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                    if let last = history.last {
                        Text(formatShortDate(last.date))
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .frame(height: 20)
            }
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

struct ParentAppDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Preview would need mock data
            Text("Preview requires mock FullAppConfigDTO")
        }
    }
}
