import SwiftUI
import FamilyControls
import Charts

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
                AppUsageDetailContent(
                    title: snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName,
                    subtitle: "Learning app overview",
                    accentColor: AppTheme.vibrantTeal,
                    persistedUsage: persistedUsage,
                    pointsPerMinute: snapshot.pointsPerMinute,
                    dailyHistory: history
                )

                // Floating Configure Button
                configureButton(accentColor: AppTheme.learningPeach)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // App icon in center (principal position)
                ToolbarItem(placement: .principal) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(2.7)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        // Fallback for iOS < 15.2
                        Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                            .font(.headline)
                    }
                }

                // Keep existing Done button
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            // Load from persistence (single source of truth)
            let tokenHash = service.usagePersistence.tokenHash(for: snapshot.token)
            print("[LearningAppDetailView] 🔍 onAppear for '\(snapshot.displayName)'")
            print("[LearningAppDetailView] 🔍 tokenHash: \(tokenHash.prefix(32))...")
            if let logicalID = service.usagePersistence.logicalID(for: tokenHash) {
                print("[LearningAppDetailView] 🔍 logicalID: \(logicalID)")
                persistedUsage = service.usagePersistence.app(for: logicalID)
                if let usage = persistedUsage {
                    let startOfToday = Calendar.current.startOfDay(for: Date())
                    let isStale = usage.lastResetDate < startOfToday
                    print("[LearningAppDetailView] 🔍 persistedUsage found:")
                    print("    - todaySeconds: \(usage.todaySeconds)")
                    print("    - lastResetDate: \(usage.lastResetDate)")
                    print("    - startOfToday: \(startOfToday)")
                    print("    - isStale: \(isStale)")
                } else {
                    print("[LearningAppDetailView] 🔍 persistedUsage is nil")
                }
                history = persistedUsage?.dailyHistory ?? []
            } else {
                print("[LearningAppDetailView] 🔍 No logicalID found for tokenHash")
            }
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
                    configSheetData = nil
                },
                onCancel: {
                    configSheetData = nil
                }
            )
        }
    }

    private func configureButton(accentColor: Color) -> some View {
        VStack(spacing: 0) {
            // Gradient fade effect
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
                // Set combined data atomically to prevent race condition
                configSheetData = LearningDetailConfigData(snapshot: snapshot, config: existingConfig)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("Configure")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(accentColor)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
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
    @EnvironmentObject var viewModel: AppUsageViewModel  // For learningSnapshots in config sheet
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
                AppUsageDetailContent(
                    title: snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName,
                    subtitle: "Reward app overview",
                    accentColor: AppTheme.playfulCoral,
                    persistedUsage: persistedUsage,
                    pointsPerMinute: snapshot.pointsPerMinute,
                    dailyHistory: history
                )

                // Floating Configure Button
                configureButton(accentColor: AppTheme.playfulCoral)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // App icon in center (principal position)
                ToolbarItem(placement: .principal) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(2.7)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        // Fallback for iOS < 15.2
                        Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                            .font(.headline)
                    }
                }

                // Keep existing Done button
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            // Load from persistence (single source of truth)
            let tokenHash = service.usagePersistence.tokenHash(for: snapshot.token)
            if let logicalID = service.usagePersistence.logicalID(for: tokenHash) {
                persistedUsage = service.usagePersistence.app(for: logicalID)
                history = persistedUsage?.dailyHistory ?? []
            }
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
                    configSheetData = nil
                },
                onCancel: {
                    configSheetData = nil
                }
            )
        }
    }

    private func configureButton(accentColor: Color) -> some View {
        VStack(spacing: 0) {
            // Gradient fade effect
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
                // Set combined data atomically to prevent race condition
                configSheetData = RewardDetailConfigData(snapshot: snapshot, config: existingConfig)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("Configure")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(accentColor)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
        }
    }
}

// MARK: - Shared Content

private struct AppUsageDetailContent: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    let persistedUsage: UsagePersistence.PersistedApp?
    let pointsPerMinute: Int
    let dailyHistory: [UsagePersistence.DailyUsageSummary]
    @Environment(\.colorScheme) private var colorScheme

    /// FIX: Returns today's seconds only if lastResetDate is today, otherwise 0
    /// This prevents stale data from yesterday showing as today's usage
    private var currentDaySeconds: Int {
        guard let usage = persistedUsage else { return 0 }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        // If lastResetDate is before today, the data is stale
        if usage.lastResetDate < startOfToday {
            return 0
        }
        return usage.todaySeconds
    }

    /// FIX: Returns today's points only if lastResetDate is today, otherwise 0
    private var currentDayPoints: Int {
        guard let usage = persistedUsage else { return 0 }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        if usage.lastResetDate < startOfToday {
            return 0
        }
        return usage.todayPoints
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Usage chart (primary visual)
                if #available(iOS 16.0, *) {
                    usageChartCard
                }

                usageBreakdownCard
                insightsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 100) // Extra padding for Configure button
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }

    // MARK: - Usage Chart Card

    @available(iOS 16.0, *)
    private var usageChartCard: some View {
        AppUsageChart(
            dailyHistory: dailyHistory,
            accentColor: accentColor
        )
    }

    private var usageBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Breakdown")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            HStack(spacing: 12) {
                // FIX: Use currentDaySeconds which checks for stale data
                let dailySeconds = TimeInterval(currentDaySeconds)
                let weeklyUsage = calculateWeeklyUsage(from: dailyHistory) + dailySeconds  // Include today
                let monthlyUsage = calculateMonthlyUsage(from: dailyHistory) + dailySeconds  // Include today

                UsagePill(
                    title: "Daily",
                    minutes: minutesText(for: dailySeconds),
                    annotation: "\(currentDayPoints) pts",  // FIX: Use currentDayPoints to handle stale data
                    accent: accentColor
                )
                UsagePill(
                    title: "Weekly",
                    minutes: minutesText(for: weeklyUsage),
                    annotation: "\(pointsEarned(for: weeklyUsage)) pts",
                    accent: accentColor.opacity(0.9)
                )
                UsagePill(
                    title: "Monthly",
                    minutes: minutesText(for: monthlyUsage),
                    annotation: "\(pointsEarned(for: monthlyUsage)) pts",
                    accent: accentColor.opacity(0.7)
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 4)
        )
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: 12) {
                insightRow(
                    icon: "bolt.fill",
                    title: "Points Earned Today",
                    value: "\(currentDayPoints) pts"
                )

                insightRow(
                    icon: "clock.fill",
                    title: "Total Time Ever",
                    value: TimeFormatting.formatSecondsCompact(TimeInterval(persistedUsage?.totalSeconds ?? 0))
                )

                insightRow(
                    icon: "star.circle.fill",
                    title: "Total Points Ever",
                    value: "\(persistedUsage?.earnedPoints ?? 0) pts"
                )

                insightRow(
                    icon: "calendar.badge.clock",
                    title: "First Used",
                    value: persistedUsage?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "No data"
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 4)
        )
    }

    // MARK: - Helper Functions

    /// Calculate weekly usage from daily history
    private func calculateWeeklyUsage(from history: [UsagePersistence.DailyUsageSummary]) -> TimeInterval {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        return TimeInterval(history
            .filter { $0.date >= sevenDaysAgo }
            .reduce(0) { $0 + $1.seconds })
    }

    /// Calculate monthly usage from daily history
    private func calculateMonthlyUsage(from history: [UsagePersistence.DailyUsageSummary]) -> TimeInterval {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!

        return TimeInterval(history
            .filter { $0.date >= thirtyDaysAgo }
            .reduce(0) { $0 + $1.seconds })
    }

    private func usageDuration(for interval: TimeInterval) -> Int {
        Int(interval / 60)
    }

    private func minutesText(for interval: TimeInterval) -> String {
        let minutes = usageDuration(for: interval)
        return minutes >= 60
            ? String(format: "%.1fh", Double(minutes) / 60.0)
            : "\(minutes)m"
    }

    private func pointsEarned(for interval: TimeInterval) -> Int {
        let minutes = usageDuration(for: interval)
        return minutes * max(pointsPerMinute, 0)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remaining = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remaining)m"
        }
        return "\(max(1, minutes))m"
    }

    private func insightRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .background(accentColor.opacity(0.15))
                .foregroundColor(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Text(value)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct UsagePill: View {
    let title: String
    let minutes: String
    let annotation: String
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(accent.opacity(0.8))

            Text(minutes)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(annotation)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
    }
}

// MARK: - Usage History Chart

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
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Picker("Period", selection: $selectedPeriod) {
                    ForEach(ChartPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Chart
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
                                    .font(.caption2)
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
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppTheme.textSecondary(for: colorScheme).opacity(0.2))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.5))
                        )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 4)
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundColor(accentColor.opacity(0.5))

            Text("No usage data yet")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("Start using this app to see your history")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.7))
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart Data

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

    // MARK: - X-Axis Labels

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
