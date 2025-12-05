import SwiftUI
import Charts

struct DailyUsageChartCard: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedPeriod: TimePeriod = .daily

    enum TimePeriod: String, CaseIterable, Identifiable {
        case hourly = "Hourly Usage"
        case daily = "Daily Usage"
        case weekly = "Weekly Usage"
        case monthly = "Monthly Usage"

        var id: String { rawValue }

        var periodsToShow: Int {
            switch self {
            case .hourly: return 24  // Today's hours
            case .daily: return 7    // Last 7 days
            case .weekly: return 4   // Last 4 weeks
            case .monthly: return 6  // Last 6 months
            }
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Header
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Usage Trend")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Time period picker (dropdown)
                Menu {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedPeriod.rawValue)
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(AppTheme.textSecondary(for: colorScheme).opacity(0.1))
                    )
                }
            }

            // Chart
            if #available(iOS 16.0, *) {
                chartView
                    .frame(height: 200)
            } else {
                // Fallback for iOS < 16
                Text("Charts require iOS 16+")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(height: 200)
            }

            // Legend
            HStack(spacing: AppTheme.Spacing.large) {
                legendItem(
                    color: AppTheme.vibrantTeal,
                    label: "Learning",
                    value: totalLearningMinutes
                )

                legendItem(
                    color: AppTheme.playfulCoral,
                    label: "Reward",
                    value: totalRewardMinutes
                )
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    @available(iOS 16.0, *)
    private var chartView: some View {
        let learningData = getChartData(for: .learning)
        let rewardData = getChartData(for: .reward)
        let isHourly = selectedPeriod == .hourly
        let xAxisUnit: Calendar.Component = {
            switch selectedPeriod {
            case .hourly: return .hour
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            }
        }()
        let xAxisName: String = {
            switch selectedPeriod {
            case .hourly: return "Hour"
            case .daily: return "Day"
            case .weekly: return "Week"
            case .monthly: return "Month"
            }
        }()

        return Chart {
            // Learning bars - stacked for hourly, side-by-side otherwise
            ForEach(learningData, id: \.date) { item in
                if isHourly {
                    BarMark(
                        x: .value(xAxisName, item.date, unit: xAxisUnit),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(AppTheme.vibrantTeal.gradient)
                } else {
                    BarMark(
                        x: .value(xAxisName, item.date, unit: xAxisUnit),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(AppTheme.vibrantTeal.gradient)
                    .position(by: .value("Category", "Learning"))
                }
            }

            // Reward bars - stacked for hourly, side-by-side otherwise
            ForEach(rewardData, id: \.date) { item in
                if isHourly {
                    BarMark(
                        x: .value(xAxisName, item.date, unit: xAxisUnit),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(AppTheme.playfulCoral.gradient)
                } else {
                    BarMark(
                        x: .value(xAxisName, item.date, unit: xAxisUnit),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(AppTheme.playfulCoral.gradient)
                    .position(by: .value("Category", "Reward"))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisUnit, count: isHourly ? 3 : 1)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(xAxisLabel(for: date))
                            .font(AppTheme.Typography.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme).opacity(0.2))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text("\(minutes)m")
                            .font(AppTheme.Typography.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme).opacity(0.2))
            }
        }
        .chartLegend(.hidden) // We have our own legend
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.5))
                )
        }
    }

    // MARK: - Data Functions

    private func getChartData(for category: AppUsage.AppCategory) -> [(date: Date, minutes: Int)] {
        switch selectedPeriod {
        case .hourly:
            return getHourlyData(for: category)
        case .daily:
            return viewModel.getChartDataForCategory(category, lastDays: 7)
        case .weekly:
            return getWeeklyData(for: category)
        case .monthly:
            return getMonthlyData(for: category)
        }
    }

    private func getHourlyData(for category: AppUsage.AppCategory) -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        // Initialize all 24 hours with 0 minutes
        var hourlyData: [Date: Int] = [:]
        for hour in 0..<24 {
            if let hourDate = calendar.date(byAdding: .hour, value: hour, to: today) {
                hourlyData[hourDate] = 0
            }
        }

        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            return hourlyData.sorted { $0.key < $1.key }.map { (date: $0.key, minutes: $0.value) }
        }

        // Get today's date string for comparison
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: now)

        // Get all app logicalIDs for this category
        let logicalIDs: [String] = {
            if category == .learning {
                return viewModel.learningSnapshots.map { $0.logicalID }
            } else {
                return viewModel.rewardSnapshots.map { $0.logicalID }
            }
        }()

        // Read hourly data directly from extension's protected keys
        for logicalID in logicalIDs {
            // Check if hourly data is from today
            let storedDate = defaults.string(forKey: "ext_usage_\(logicalID)_hourly_date")

            guard storedDate == todayString else {
                #if DEBUG
                print("[DailyUsageChartCard] ⏭️ Skipping \(logicalID): hourly date '\(storedDate ?? "nil")' != today '\(todayString)'")
                #endif
                continue
            }

            // Read each hour's usage from extension's buckets (all 24 hours)
            for hour in 0..<24 {
                let seconds = defaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
                if seconds > 0 {
                    if let hourDate = calendar.date(byAdding: .hour, value: hour, to: today) {
                        hourlyData[hourDate, default: 0] += seconds / 60  // Convert to minutes
                    }
                }
            }

            #if DEBUG
            let totalForApp = (0..<24).reduce(0) { $0 + defaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\($1)") }
            if totalForApp > 0 {
                print("[DailyUsageChartCard] 📊 \(logicalID): \(totalForApp / 60)m total from hourly buckets")
            }
            #endif
        }

        return hourlyData
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, minutes: $0.value) }
    }

    private func getWeeklyData(for category: AppUsage.AppCategory) -> [(date: Date, minutes: Int)] {
        let dailyData = viewModel.getChartDataForCategory(category, lastDays: 28) // 4 weeks
        let calendar = Calendar.current

        // Group by week
        var weeklyData: [Date: Int] = [:]

        for item in dailyData {
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: item.date)?.start {
                weeklyData[weekStart, default: 0] += item.minutes
            }
        }

        return weeklyData
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, minutes: $0.value) }
    }

    private func getMonthlyData(for category: AppUsage.AppCategory) -> [(date: Date, minutes: Int)] {
        let dailyData = viewModel.getChartDataForCategory(category, lastDays: 180) // ~6 months
        let calendar = Calendar.current

        // Group by month
        var monthlyData: [Date: Int] = [:]

        for item in dailyData {
            if let monthStart = calendar.dateInterval(of: .month, for: item.date)?.start {
                monthlyData[monthStart, default: 0] += item.minutes
            }
        }

        return monthlyData
            .sorted { $0.key < $1.key }
            .suffix(6) // Last 6 months
            .map { (date: $0.key, minutes: $0.value) }
    }

    // MARK: - Label Functions

    private func xAxisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        switch selectedPeriod {
        case .hourly:
            let hour = calendar.component(.hour, from: date)
            return String(format: "%02d", hour)

        case .daily:
            let today = calendar.startOfDay(for: Date())
            if calendar.isDate(date, inSameDayAs: today) {
                return "Today"
            } else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                return "Yest."
            } else {
                formatter.dateFormat = "EEE" // Mon, Tue, etc.
                return formatter.string(from: date)
            }

        case .weekly:
            formatter.dateFormat = "MMM d" // Jan 15
            return formatter.string(from: date)

        case .monthly:
            formatter.dateFormat = "MMM" // Jan, Feb, etc.
            return formatter.string(from: date)
        }
    }

    private func legendItem(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("\(value)m")
                .font(AppTheme.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }

    // MARK: - Totals

    private var totalLearningMinutes: Int {
        getChartData(for: .learning)
            .reduce(0) { $0 + $1.minutes }
    }

    private var totalRewardMinutes: Int {
        getChartData(for: .reward)
            .reduce(0) { $0 + $1.minutes }
    }
}

// MARK: - Preview

#Preview {
    DailyUsageChartCard()
        .environmentObject(AppUsageViewModel())
        .padding()
        .background(Color.gray.opacity(0.1))
}
