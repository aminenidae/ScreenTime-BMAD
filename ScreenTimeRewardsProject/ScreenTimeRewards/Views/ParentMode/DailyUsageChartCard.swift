import SwiftUI
import Charts

struct DailyUsageChartCard: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedPeriod: TimePeriod = .daily
    @State private var selectedDate: Date?

    enum TimePeriod: String, CaseIterable, Identifiable {
        case hourly = "Hourly"
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"

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
        VStack(spacing: AppTheme.Spacing.regular) { // Use AppTheme spacing
            // Header
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("USAGE TREND")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)

                Spacer()

                // Time period picker (dropdown)
                Menu {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                                .textCase(.uppercase)
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.tiny) { // Use AppTheme spacing
                        Text(selectedPeriod.rawValue.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small) // Use AppTheme corner radius
                            .fill(AppTheme.vibrantTeal.opacity(0.1))
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.6))
                    .frame(height: 200)
            }

            // Legend
            HStack(spacing: 32) {
                legendItem(
                    color: AppTheme.vibrantTeal,
                    label: String(localized: "Learning"),
                    value: totalLearningMinutes
                )

                legendItem(
                    color: AppTheme.playfulCoral,
                    label: String(localized: "Reward"),
                    value: totalRewardMinutes
                )
            }
        }
        .padding(AppTheme.Spacing.regular) // Use AppTheme spacing
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large) // Use AppTheme corner radius
                .fill(AppTheme.card(for: colorScheme)) // Use AppTheme card color
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large) // Use AppTheme corner radius
                        .stroke(AppTheme.border(for: colorScheme), lineWidth: 1) // Use AppTheme border
                )
        )
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
            case .hourly: return String(localized: "Hour")
            case .daily: return String(localized: "Day")
            case .weekly: return String(localized: "Week")
            case .monthly: return String(localized: "Month")
            }
        }()

        // Calculate max Y value to lock the scale (prevents rescaling when annotation appears)
        let maxLearning = learningData.map { $0.minutes }.max() ?? 0
        let maxReward = rewardData.map { $0.minutes }.max() ?? 0
        let maxY = max(Double(maxLearning + maxReward), 1) * 1.15  // 15% padding for annotation

        // Lock X-axis domain to prevent chart shifting on selection
        // Each period's end extends +1 unit so the last bar isn't clipped
        let xDomain: ClosedRange<Date> = {
            let calendar = Calendar.current
            let now = Date()
            switch selectedPeriod {
            case .hourly:
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .hour, value: 24, to: start)!
                return start...end
            case .daily:
                let today = calendar.startOfDay(for: now)
                let start = calendar.date(byAdding: .day, value: -6, to: today)!
                let end = calendar.date(byAdding: .day, value: 1, to: today)!
                return start...end
            case .weekly:
                if let first = learningData.first?.date ?? rewardData.first?.date,
                   let last = learningData.last?.date ?? rewardData.last?.date {
                    let end = calendar.date(byAdding: .weekOfYear, value: 1, to: last)!
                    return first...end
                }
                let start = calendar.date(byAdding: .weekOfYear, value: -3, to: now)!
                return start...now
            case .monthly:
                if let first = learningData.first?.date ?? rewardData.first?.date,
                   let last = learningData.last?.date ?? rewardData.last?.date {
                    let end = calendar.date(byAdding: .month, value: 1, to: last)!
                    return first...end
                }
                let start = calendar.date(byAdding: .month, value: -5, to: now)!
                return start...now
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

            // Selection indicator
            if let selectedDate = selectedDate {
                let learningMin = learningData.first(where: { Calendar.current.isDate($0.date, equalTo: selectedDate, toGranularity: xAxisUnit) })?.minutes ?? 0
                let rewardMin = rewardData.first(where: { Calendar.current.isDate($0.date, equalTo: selectedDate, toGranularity: xAxisUnit) })?.minutes ?? 0

                RuleMark(x: .value("Selected", selectedDate, unit: xAxisUnit))
                    .foregroundStyle(AppTheme.vibrantTeal.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 2]))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedDateLabel(for: selectedDate))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(AppTheme.vibrantTeal)
                                    .frame(width: 6, height: 6)
                                Text("Learning")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                                Spacer(minLength: 6)
                                Text("\(learningMin)m")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.vibrantTeal)
                            }
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(AppTheme.playfulCoral)
                                    .frame(width: 6, height: 6)
                                Text("Reward")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                                Spacer(minLength: 6)
                                Text("\(rewardMin)m")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.playfulCoral)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.card(for: colorScheme))
                                .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                        )
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisUnit, count: isHourly ? 3 : 1)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(xAxisLabel(for: date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.vibrantTeal.opacity(0.15))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text("\(minutes)m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.vibrantTeal.opacity(0.15))
            }
        }
        .chartLegend(.hidden) // We have our own legend
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...maxY)
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium) // Use AppTheme corner radius
                        .fill(AppTheme.vibrantTeal.opacity(0.03))
                )
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let xPos = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: xPos) {
                                    // Snap to nearest data point to avoid out-of-range dates
                                    let allDates = Array(Set(learningData.map(\.date) + rewardData.map(\.date))).sorted()
                                    if let closest = allDates.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }) {
                                        selectedDate = closest
                                    }
                                }
                            }
                            .onEnded { _ in
                                selectedDate = nil
                            }
                    )
            }
        }
    }

    private func selectedDateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedPeriod {
        case .hourly:
            formatter.dateFormat = "h a"
        case .daily:
            formatter.dateFormat = "EEE, MMM d"
        case .weekly:
            formatter.dateFormat = "'Week of' MMM d"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: date)
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
                print("[DailyUsageChartCard] Skipping \(logicalID): hourly date '\(storedDate ?? "nil")' != today '\(todayString)'")
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
                print("[DailyUsageChartCard] \(logicalID): \(totalForApp / 60)m total from hourly buckets")
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
                return String(localized: "Today")
            } else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                return String(localized: "Yest.")
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
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 12, height: 12)

            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                .textCase(.uppercase)

            Text("\(value)M") // Consistent formatting
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
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
        .background(Color(red: 0.96, green: 0.95, blue: 0.88))
}
