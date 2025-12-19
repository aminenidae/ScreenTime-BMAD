import SwiftUI
import FamilyControls
import Charts

// Design colors matching ModeSelectionView
private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
private let accentYellow = Color(red: 0.98, green: 0.80, blue: 0.30)

// Combined struct to prevent race condition in sheet presentation
private struct LearningDetailConfigData: Identifiable {
    let snapshot: LearningAppSnapshot
    var config: AppScheduleConfiguration
    var id: String { snapshot.id }
}

struct LearningAppDetailView: View {
    let snapshot: LearningAppSnapshot
    @State private var persistedUsage: UsagePersistence.PersistedApp?
    @State private var history: [UsagePersistence.DailyUsageSummary] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private let service = ScreenTimeService.shared

    // Configuration sheet state (combined to prevent race condition)
    @StateObject private var scheduleService = AppScheduleService.shared
    @State private var configSheetData: LearningDetailConfigData?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                creamBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // App Header Card
                    appHeaderCard

                    // Content
                    ScrollView {
                        VStack(spacing: 16) {
                            // Hourly usage chart (today's breakdown)
                            if #available(iOS 16.0, *) {
                                HourlyUsageChartCard(logicalID: snapshot.logicalID, accentColor: tealColor)
                            }

                            // Historical usage chart
                            if #available(iOS 16.0, *) {
                                AppUsageChart(
                                    dailyHistory: history,
                                    accentColor: tealColor
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                }

                // Floating Configure Button
                configureButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tealColor)
                }
            }
            .toolbarBackground(creamBackground, for: .navigationBar)
        }
        .onAppear {
            loadUsageData()
        }
        .sheet(item: $configSheetData) { data in
            AppConfigurationSheet(
                token: data.snapshot.token,
                appName: data.snapshot.displayName,
                appType: .learning,
                configuration: Binding(
                    get: { data.config },
                    set: { newConfig in
                        configSheetData = LearningDetailConfigData(snapshot: data.snapshot, config: newConfig)
                    }
                ),
                onSave: { savedConfig in
                    try? scheduleService.saveSchedule(savedConfig)
                    BlockingCoordinator.shared.refreshAllBlockingStates()
                    configSheetData = nil
                },
                onCancel: {
                    configSheetData = nil
                }
            )
        }
    }

    private var appHeaderCard: some View {
        HStack {
            // App Icon only
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.3)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tealColor.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 20))
                            .foregroundColor(tealColor)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(tealColor.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var configureButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [
                    creamBackground.opacity(0),
                    creamBackground
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                let existingConfig = scheduleService.schedules[snapshot.logicalID]
                    ?? AppScheduleConfiguration.defaultLearning(logicalID: snapshot.logicalID)
                configSheetData = LearningDetailConfigData(snapshot: snapshot, config: existingConfig)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("CONFIGURE")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(creamBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tealColor)
                )
                .shadow(color: tealColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(creamBackground)
        }
    }

    private func loadUsageData() {
        let tokenHash = service.usagePersistence.tokenHash(for: snapshot.token)
        if let logicalID = service.usagePersistence.logicalID(for: tokenHash) {
            persistedUsage = service.usagePersistence.app(for: logicalID)
            history = persistedUsage?.dailyHistory ?? []
        }
    }
}

// Combined struct to prevent race condition in sheet presentation
private struct RewardDetailConfigData: Identifiable {
    let snapshot: RewardAppSnapshot
    var config: AppScheduleConfiguration
    var id: String { snapshot.id }
}

struct RewardAppDetailView: View {
    let snapshot: RewardAppSnapshot
    @EnvironmentObject var viewModel: AppUsageViewModel
    @State private var persistedUsage: UsagePersistence.PersistedApp?
    @State private var history: [UsagePersistence.DailyUsageSummary] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private let service = ScreenTimeService.shared

    // Configuration sheet state (combined to prevent race condition)
    @StateObject private var scheduleService = AppScheduleService.shared
    @State private var configSheetData: RewardDetailConfigData?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                creamBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // App Header Card
                    appHeaderCard

                    // Content
                    ScrollView {
                        VStack(spacing: 16) {
                            // Hourly usage chart (today's breakdown)
                            if #available(iOS 16.0, *) {
                                HourlyUsageChartCard(logicalID: snapshot.logicalID, accentColor: lightCoral)
                            }

                            // Historical usage chart
                            if #available(iOS 16.0, *) {
                                AppUsageChart(
                                    dailyHistory: history,
                                    accentColor: lightCoral
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                }

                // Floating Configure Button
                configureButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tealColor)
                }
            }
            .toolbarBackground(creamBackground, for: .navigationBar)
        }
        .onAppear {
            loadUsageData()
        }
        .sheet(item: $configSheetData) { data in
            AppConfigurationSheet(
                token: data.snapshot.token,
                appName: data.snapshot.displayName,
                appType: .reward,
                learningSnapshots: viewModel.learningSnapshots,
                configuration: Binding(
                    get: { data.config },
                    set: { newConfig in
                        configSheetData = RewardDetailConfigData(snapshot: data.snapshot, config: newConfig)
                    }
                ),
                onSave: { savedConfig in
                    try? scheduleService.saveSchedule(savedConfig)
                    viewModel.blockRewardApps()
                    configSheetData = nil
                },
                onCancel: {
                    configSheetData = nil
                }
            )
        }
    }

    private var appHeaderCard: some View {
        HStack {
            // App Icon only
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.3)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(lightCoral.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 20))
                            .foregroundColor(lightCoral)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(lightCoral.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var configureButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [
                    creamBackground.opacity(0),
                    creamBackground
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                let existingConfig = scheduleService.schedules[snapshot.logicalID]
                    ?? AppScheduleConfiguration.defaultReward(logicalID: snapshot.logicalID)
                configSheetData = RewardDetailConfigData(snapshot: snapshot, config: existingConfig)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("CONFIGURE")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(creamBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(lightCoral)
                )
                .shadow(color: lightCoral.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(creamBackground)
        }
    }

    private func loadUsageData() {
        let tokenHash = service.usagePersistence.tokenHash(for: snapshot.token)
        if let logicalID = service.usagePersistence.logicalID(for: tokenHash) {
            persistedUsage = service.usagePersistence.app(for: logicalID)
            history = persistedUsage?.dailyHistory ?? []
        }
    }
}

// MARK: - Hourly Usage Chart

@available(iOS 16.0, *)
private struct HourlyUsageChartCard: View {
    let logicalID: String
    let accentColor: Color

    private var hourlyData: [(date: Date, minutes: Int)] {
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: now)

        let storedDate = defaults.string(forKey: "ext_usage_\(logicalID)_hourly_date")
        guard storedDate == todayString else {
            return (0..<24).compactMap { hour in
                guard let hourDate = calendar.date(byAdding: .hour, value: hour, to: today) else { return nil }
                return (date: hourDate, minutes: 0)
            }
        }

        return (0..<24).compactMap { hour in
            guard let hourDate = calendar.date(byAdding: .hour, value: hour, to: today) else { return nil }
            let seconds = defaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
            return (date: hourDate, minutes: seconds / 60)
        }
    }

    private var totalMinutes: Int {
        hourlyData.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(accentColor)

                Text("TODAY'S HOURLY USAGE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(tealColor)

                Spacer()

                Text("\(totalMinutes)M TOTAL")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tealColor.opacity(0.6))
            }

            if totalMinutes == 0 {
                emptyStateView
            } else {
                Chart {
                    ForEach(hourlyData, id: \.date) { item in
                        BarMark(
                            x: .value("Hour", item.date, unit: .hour),
                            y: .value("Minutes", item.minutes)
                        )
                        .foregroundStyle(accentColor.gradient)
                        .cornerRadius(3)
                    }
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(hourLabel(for: date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(tealColor.opacity(0.5))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(tealColor.opacity(0.1))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes)m")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(tealColor.opacity(0.5))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(tealColor.opacity(0.1))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tealColor.opacity(0.03))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(tealColor.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundColor(tealColor.opacity(0.3))

            Text("NO USAGE RECORDED TODAY")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tealColor.opacity(0.5))
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
    }

    private func hourLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return String(format: "%02d", hour)
    }
}

// MARK: - Usage History Chart

@available(iOS 16.0, *)
private struct AppUsageChart: View {
    let dailyHistory: [UsagePersistence.DailyUsageSummary]
    let accentColor: Color
    @State private var selectedPeriod: ChartPeriod = .daily

    enum ChartPeriod: String, CaseIterable {
        case daily = "7 DAYS"
        case weekly = "4 WEEKS"
        case monthly = "6 MONTHS"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("USAGE HISTORY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(tealColor)

                Spacer()

                Menu {
                    Picker("PERIOD", selection: $selectedPeriod) {
                        ForEach(ChartPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedPeriod.rawValue.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.5)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(tealColor.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tealColor.opacity(0.1))
                    )
                }
            }

            if chartData.isEmpty {
                emptyStateView
            } else {
                Chart {
                    ForEach(chartData, id: \.date) { item in
                        BarMark(
                            x: .value("Date", item.date, unit: xAxisUnit),
                            y: .value("Minutes", item.minutes)
                        )
                        .foregroundStyle(accentColor.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisUnit)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(xAxisLabel(for: date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(tealColor.opacity(0.5))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(tealColor.opacity(0.1))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes)m")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(tealColor.opacity(0.5))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(tealColor.opacity(0.1))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tealColor.opacity(0.03))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(tealColor.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundColor(tealColor.opacity(0.3))

            Text("NO USAGE DATA YET")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tealColor.opacity(0.5))
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }

    private var chartData: [(date: Date, minutes: Int)] {
        switch selectedPeriod {
        case .daily:
            return getDailyData()
        case .weekly:
            return getWeeklyData()
        case .monthly:
            return getMonthlyData()
        }
    }

    private var xAxisUnit: Calendar.Component {
        switch selectedPeriod {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }

    private func getDailyData() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        return dailyHistory
            .filter { $0.date >= sevenDaysAgo }
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, minutes: $0.seconds / 60) }
    }

    private func getWeeklyData() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date())!

        var weeklyData: [Date: Int] = [:]

        for item in dailyHistory where item.date >= fourWeeksAgo {
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: item.date)?.start {
                weeklyData[weekStart, default: 0] += item.seconds / 60
            }
        }

        return weeklyData
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, minutes: $0.value) }
    }

    private func getMonthlyData() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date())!

        var monthlyData: [Date: Int] = [:]

        for item in dailyHistory where item.date >= sixMonthsAgo {
            if let monthStart = calendar.dateInterval(of: .month, for: item.date)?.start {
                monthlyData[monthStart, default: 0] += item.seconds / 60
            }
        }

        return monthlyData
            .sorted { $0.key < $1.key }
            .suffix(6)
            .map { (date: $0.key, minutes: $0.value) }
    }

    private func xAxisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        switch selectedPeriod {
        case .daily:
            let today = calendar.startOfDay(for: Date())
            if calendar.isDate(date, inSameDayAs: today) {
                return "Today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(date, inSameDayAs: yesterday) {
                return "Yest."
            } else {
                formatter.dateFormat = "EEE"
                return formatter.string(from: date)
            }

        case .weekly:
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)

        case .monthly:
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
    }
}
