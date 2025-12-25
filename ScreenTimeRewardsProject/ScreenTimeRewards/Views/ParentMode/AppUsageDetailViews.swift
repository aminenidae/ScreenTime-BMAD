import SwiftUI
import FamilyControls
import ManagedSettings
import Charts

// Protocol for app snapshots to share common properties for AppDetailHeaderView
protocol AppIdentifiable {
    var token: ApplicationToken { get }
    var displayName: String { get }
    var logicalID: String { get }
}

extension LearningAppSnapshot: AppIdentifiable {}
extension RewardAppSnapshot: AppIdentifiable {}

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
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        // App Header Card
                        AppDetailHeaderView(snapshot: snapshot, appType: .learning)

                        // Hourly usage chart (today's breakdown)
                        if #available(iOS 16.0, *) {
                            HourlyUsageChartCard(logicalID: snapshot.logicalID, accentColor: AppTheme.vibrantTeal)
                        }

                        // Historical usage chart
                        if #available(iOS 16.0, *) {
                            AppUsageChart(
                                dailyHistory: history,
                                accentColor: AppTheme.vibrantTeal
                            )
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(AppTheme.Spacing.large)
                }

                // Floating Configure Button
                configureButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 18, weight: .bold)) // Standardized button font size
                        .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color
                        .textCase(.uppercase)
                }
            }
            .toolbarBackground(AppTheme.background(for: colorScheme), for: .navigationBar) // Use AppTheme background
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

    private var configureButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.background(for: colorScheme).opacity(0),
                    AppTheme.background(for: colorScheme)
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
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                    Text("CONFIGURE")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(1)
                        .textCase(.uppercase) // Added textCase for consistency
                }
                .foregroundColor(AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppTheme.vibrantTeal)
                )
                .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, AppTheme.Spacing.regular)
            .padding(.bottom, AppTheme.Spacing.regular)
            .background(AppTheme.background(for: colorScheme))
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
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        // App Header Card
                        AppDetailHeaderView(snapshot: snapshot, appType: .reward)

                        // Hourly usage chart (today's breakdown)
                        if #available(iOS 16.0, *) {
                            HourlyUsageChartCard(logicalID: snapshot.logicalID, accentColor: AppTheme.playfulCoral)
                        }

                        // Historical usage chart
                        if #available(iOS 16.0, *) {
                            AppUsageChart(
                                dailyHistory: history,
                                accentColor: AppTheme.playfulCoral
                            )
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(AppTheme.Spacing.large)
                }

                // Floating Configure Button
                configureButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 18, weight: .bold)) // Standardized button font size
                        .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color
                        .textCase(.uppercase)
                }
            }
            .toolbarBackground(AppTheme.background(for: colorScheme), for: .navigationBar) // Use AppTheme background
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

    private var configureButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.background(for: colorScheme).opacity(0),
                    AppTheme.background(for: colorScheme)
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
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                    Text("CONFIGURE")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(1)
                        .textCase(.uppercase) // Added textCase for consistency
                }
                .foregroundColor(AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppTheme.playfulCoral)
                )
                .shadow(color: AppTheme.playfulCoral.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, AppTheme.Spacing.regular)
            .padding(.bottom, AppTheme.Spacing.regular)
            .background(AppTheme.background(for: colorScheme))
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

    @Environment(\.colorScheme) private var colorScheme

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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.regular) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(accentColor)

                Text("TODAY'S HOURLY USAGE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)

                Spacer()

                Text("\(totalMinutes)M TOTAL")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .textCase(.uppercase)
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
                        .cornerRadius(AppTheme.CornerRadius.small)
                    }
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(hourLabel(for: date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes)M")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                                .fill(AppTheme.vibrantTeal.opacity(0.03))
                        )
                }
            }
        }
        .padding(AppTheme.Spacing.regular)
        .appCard(colorScheme)
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.regular) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))

            Text("NO USAGE RECORDED TODAY")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                .textCase(.uppercase)
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



    @Environment(\.colorScheme) private var colorScheme // Added for AppTheme.background



    enum ChartPeriod: String, CaseIterable {

        case daily = "7 DAYS"

        case weekly = "4 WEEKS"

        case monthly = "6 MONTHS"

    }



    var body: some View {

        VStack(alignment: .leading, spacing: AppTheme.Spacing.regular) { // Use AppTheme.Spacing

            HStack {

                Text("USAGE HISTORY")

                    .font(.system(size: 12, weight: .semibold))

                    .tracking(1)

                    .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color

                    .textCase(.uppercase)



                Spacer()



                Menu {

                    Picker("PERIOD", selection: $selectedPeriod) {

                        ForEach(ChartPeriod.allCases, id: \.self) { period in

                            Text(period.rawValue).tag(period)

                                .textCase(.uppercase)

                        }

                    }

                } label: {

                    HStack(spacing: AppTheme.Spacing.tiny) { // Use AppTheme.Spacing

                        Text(selectedPeriod.rawValue.uppercased())

                            .font(.system(size: 11, weight: .medium))

                            .tracking(0.5)

                        Image(systemName: "chevron.down")

                            .font(.system(size: 10, weight: .medium))

                    }

                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6)) // Use AppTheme color

                    .padding(.horizontal, AppTheme.Spacing.regular) // Use AppTheme.Spacing

                    .padding(.vertical, AppTheme.Spacing.tiny) // Use AppTheme.Spacing

                    .background(

                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small) // Use AppTheme corner radius

                            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1)) // Use AppTheme color

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

                        .cornerRadius(AppTheme.CornerRadius.small) // Use AppTheme corner radius

                    }

                }

                .frame(height: 180)

                .chartXAxis {

                    AxisMarks(values: .stride(by: xAxisUnit)) { value in

                        if let date = value.as(Date.self) {

                            AxisValueLabel {

                                Text(xAxisLabel(for: date))

                                    .font(.system(size: 10, weight: .medium))

                                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5)) // Use AppTheme color

                            }

                        }

                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))

                            .foregroundStyle(AppTheme.brandedText(for: colorScheme).opacity(0.1)) // Use AppTheme color

                    }

                }

                .chartYAxis {

                    AxisMarks { value in

                        AxisValueLabel {

                            if let minutes = value.as(Int.self) {

                                Text("\(minutes)M") // Changed to M for consistency.

                                    .font(.system(size: 10, weight: .medium))

                                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5)) // Use AppTheme color

                            }

                        }

                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))

                            .foregroundStyle(AppTheme.brandedText(for: colorScheme).opacity(0.1)) // Use AppTheme color

                    }

                }

                .chartPlotStyle { plotArea in

                    plotArea

                        .background(

                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small) // Use AppTheme corner radius

                                .fill(AppTheme.brandedText(for: colorScheme).opacity(0.03)) // Use AppTheme color

                        )

                }

            }

        }

        .padding(AppTheme.Spacing.regular) // Use AppTheme spacing

        .appCard(colorScheme) // Use AppTheme appCard styling

    }



    private var emptyStateView: some View {

        VStack(spacing: AppTheme.Spacing.regular) { // Use AppTheme spacing

            Image(systemName: "chart.bar.xaxis")

                .font(.system(size: 32))

                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3)) // Use AppTheme color



            Text("NO USAGE DATA YET")

                .font(.system(size: 13, weight: .medium))

                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5)) // Use AppTheme color

                .textCase(.uppercase)

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
