import SwiftUI
import Charts

/// Detailed view for an app in the parent dashboard
/// Shows comprehensive app information including usage history, schedule, and unlock requirements
struct ParentAppDetailView: View {
    let config: FullAppConfigDTO
    var shieldState: ShieldStateDTO?
    var appHistory: [DailyUsageHistoryDTO]
    var childLearningApps: [FullAppConfigDTO] = []  // For linked apps picker
    var onConfigUpdated: ((FullAppConfigDTO) -> Void)?  // Callback to update ViewModel

    @State private var selectedTimeRange: TimeRange = .daily
    @State private var isEditSheetPresented = false
    @State private var editingConfig: MutableAppConfigDTO?
    @State private var syncStatus: ConfigSyncStatus = .idle
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    enum ConfigSyncStatus {
        case idle, sending, success, failed
    }

    enum TimeRange: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"

        var days: Int {
            switch self {
            case .daily: return 7
            case .weekly: return 28
            case .monthly: return 180
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

        // Create lookup for existing history
        var historyByDate: [Date: DailyUsageHistoryDTO] = [:]
        for record in appHistory {
            let dayStart = calendar.startOfDay(for: record.date)
            historyByDate[dayStart] = record
        }

        // Generate entries for all days in range
        var result: [DailyUsageHistoryDTO] = []
        for dayOffset in 0..<selectedTimeRange.days {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                if let existing = historyByDate[date] {
                    result.append(existing)
                } else {
                    // Create placeholder with 0 usage
                    result.append(DailyUsageHistoryDTO(
                        deviceID: config.deviceID,
                        logicalID: config.logicalID,
                        displayName: config.displayName,
                        date: date,
                        seconds: 0,
                        category: config.category,
                        syncTimestamp: nil
                    ))
                }
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    var totalSeconds: Int {
        filteredHistory.reduce(0) { $0 + $1.seconds }
    }

    var todaySeconds: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appHistory.first { calendar.isDate($0.date, inSameDayAs: today) }?.seconds ?? 0
    }

    /// Get today's hourly data from synced history
    var todayHourlySeconds: [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let todayRecord = appHistory.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) else {
            return Array(repeating: 0, count: 24)
        }
        return todayRecord.hourlySeconds
    }

    /// Aggregated chart data based on selected time range
    var chartData: [(date: Date, minutes: Int)] {
        switch selectedTimeRange {
        case .daily:
            return filteredHistory.map { (date: $0.date, minutes: $0.seconds / 60) }
        case .weekly:
            return getWeeklyData()
        case .monthly:
            return getMonthlyData()
        }
    }

    private func getWeeklyData() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        var weeklyData: [Date: Int] = [:]

        for item in filteredHistory {
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: item.date)?.start {
                weeklyData[weekStart, default: 0] += item.seconds / 60
            }
        }

        return weeklyData
            .sorted { $0.key < $1.key }
            .suffix(4)
            .map { (date: $0.key, minutes: $0.value) }
    }

    private func getMonthlyData() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        var monthlyData: [Date: Int] = [:]

        for item in filteredHistory {
            if let monthStart = calendar.dateInterval(of: .month, for: item.date)?.start {
                monthlyData[monthStart, default: 0] += item.seconds / 60
            }
        }

        return monthlyData
            .sorted { $0.key < $1.key }
            .suffix(6)
            .map { (date: $0.key, minutes: $0.value) }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Streak Bonus (if enabled) - right below header
                    if let streak = config.streakSettings, streak.isEnabled {
                        streakBonusSection(streak)
                    }

                    // Usage Summary
                    usageSummaryCard

                    // Today's Hourly Usage Chart
                    if #available(iOS 16.0, *) {
                        HourlyUsageChartCard(
                            hourlySeconds: todayHourlySeconds,
                            accentColor: categoryColor
                        )
                    }

                    // Usage Chart
                    usageChartSection

                    // Schedule (if configured)
                    if config.scheduleConfig != nil {
                        scheduleSection
                    }

                    // Unlock Requirements (Reward apps only)
                    if config.category == "Reward" && !validLinkedLearningApps.isEmpty {
                        unlockRequirementsSection
                    }

                    // Bottom padding for FAB
                    Color.clear.frame(height: 80)
                }
                .padding()
            }

            // Floating Configure Button
            configureButton
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditSheetPresented) {
            ZStack {
                ParentAppEditSheet(
                    config: $editingConfig,
                    childLearningApps: childLearningApps.filter { $0.category == "Learning" },
                    onSave: { updatedConfig in
                        Task {
                            await sendConfigUpdate(updatedConfig)
                        }
                    },
                    onCancel: {
                        isEditSheetPresented = false
                        editingConfig = nil
                    }
                )

                // Saving overlay
                if syncStatus == .sending {
                    SavingConfigOverlayView(appName: config.displayName)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: syncStatus)
        }
        .alert(syncStatus == .success ? "Changes Sent" : "Sync Error", isPresented: $showingSyncAlert) {
            Button("OK") {
                if syncStatus == .success {
                    isEditSheetPresented = false
                    editingConfig = nil
                }
            }
        } message: {
            Text(syncAlertMessage)
        }
    }

    // MARK: - Floating Configure Button
    private var configureButton: some View {
        VStack(spacing: 0) {
            // Gradient overlay for smooth transition
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
                editingConfig = MutableAppConfigDTO(from: config)
                isEditSheetPresented = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("Configure")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(categoryColor)
                )
                .shadow(color: categoryColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
        }
    }

    // MARK: - Edit Actions

    private func sendConfigUpdate(_ updatedConfig: MutableAppConfigDTO) async {
        syncStatus = .sending

        let payload = FullConfigUpdatePayload(
            from: updatedConfig,
            parentDeviceID: DeviceModeManager.shared.deviceID
        )

        do {
            // Send command directly to CloudKit shared zone (not via Core Data)
            try await CloudKitSyncService.shared.sendConfigCommandToSharedZone(
                deviceID: updatedConfig.deviceID,
                payload: payload
            )

            await MainActor.run {
                syncStatus = .success
                syncAlertMessage = "Changes have been sent to the child's device. They will apply when the device syncs."
                showingSyncAlert = true

                // Optimistic update: update ViewModel immediately
                let updatedFullConfig = config.applying(changes: updatedConfig)
                onConfigUpdated?(updatedFullConfig)
            }
        } catch {
            await MainActor.run {
                syncStatus = .failed
                syncAlertMessage = "Failed to send changes: \(error.localizedDescription)"
                showingSyncAlert = true
            }
        }
    }

    // MARK: - Header Section (matches AppDetailHeaderView style)

    private var headerSection: some View {
        HStack(spacing: AppTheme.Spacing.regular) {
            // App icon using CachedAppIcon
            ZStack(alignment: .bottomTrailing) {
                // Icon with background for visibility
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 56, height: 56)

                    CachedAppIcon(
                        iconURL: config.iconURL,
                        identifier: config.logicalID,
                        size: 56,
                        fallbackSymbol: config.category == "Learning" ? "book.fill" : "gamecontroller.fill"
                    )
                }

                // Shield state indicator
                if let state = shieldState {
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(state.isUnlocked ? .green : .red)
                        .padding(3)
                        .background(Circle().fill(Color(UIColor.systemBackground)))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                // App name
                Text(displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .lineLimit(1)

                // Category badge
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: config.category == "Learning" ? "book.fill" : "gift.fill")
                        .font(.system(size: 10))

                    Text(config.category == "Learning" ? "Learning" : "Reward")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)

                    // Status Badge (for reward apps)
                    if let state = shieldState {
                        Text("•")
                            .font(.system(size: 10))
                        Text(state.isUnlocked ? "Unlocked" : "Blocked")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(state.isUnlocked ? .green : .red)
                    }
                }
                .foregroundColor(config.category == "Learning" ? AppTheme.brandedText(for: colorScheme) : categoryColor)
                .padding(.horizontal, AppTheme.Spacing.regular)
                .padding(.vertical, AppTheme.Spacing.tiny)
                .background(
                    Capsule()
                        .fill(categoryColor.opacity(0.15))
                )
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }

    // MARK: - Usage Summary Card

    private var usageSummaryCard: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor)

                Text("Usage Summary")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()
            }

            HStack(spacing: 20) {
                // Last N Days
                VStack(spacing: 4) {
                    Text(TimeFormatting.formatSeconds(totalSeconds))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(categoryColor)
                    Text("Last \(selectedTimeRange.days) days")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(AppTheme.border(for: colorScheme))
                    .frame(width: 1, height: 40)

                // Today
                VStack(spacing: 4) {
                    Text(TimeFormatting.formatSeconds(todaySeconds))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Text("Today")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(categoryColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Usage Chart Section (matches AppUsageChart style)

    private var usageChartSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.regular) {
            HStack {
                Text("Usage History")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Menu {
                    Picker("Period", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.tiny) {
                        Text(selectedTimeRange.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.5)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .padding(.horizontal, AppTheme.Spacing.regular)
                    .padding(.vertical, AppTheme.Spacing.tiny)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                    )
                }
            }

            if chartData.isEmpty {
                VStack(spacing: AppTheme.Spacing.regular) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))

                    Text("No usage data yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            } else {
                UsageBarChart(
                    data: chartData,
                    timeRange: selectedTimeRange,
                    categoryColor: categoryColor,
                    colorScheme: colorScheme
                )
                .frame(height: 180)
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor)

                Text("Schedule")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()
            }

            if let schedule = config.scheduleConfig {
                VStack(spacing: 12) {
                    // Time Window
                    HStack {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor)
                            .frame(width: 24)
                        Text("Allowed Time")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(schedule.todayTimeWindow.isFullDay ? "All Day" : schedule.todayTimeWindow.displayString)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    }

                    Rectangle()
                        .fill(AppTheme.border(for: colorScheme))
                        .frame(height: 1)

                    // Daily Limit
                    HStack {
                        Image(systemName: "timer")
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor)
                            .frame(width: 24)
                        Text("Daily Limit")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(schedule.dailyLimits.displaySummary)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(categoryColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Unlock Requirements Section

    /// Get icon URL for a linked learning app by looking it up in childLearningApps
    private func iconURLForLinkedApp(_ logicalID: String) -> String? {
        childLearningApps.first { $0.logicalID == logicalID }?.iconURL
    }

    /// Get display name for a linked learning app by looking it up in childLearningApps
    private func displayNameForLinkedApp(_ linkedApp: LinkedLearningApp) -> String {
        // Helper to check if a name is valid (not empty, not "Unknown App" variants)
        func isValidDisplayName(_ name: String?) -> Bool {
            guard let name = name, !name.isEmpty else { return false }
            return !name.hasPrefix("Unknown App") && name != "Unknown"
        }

        // 1. Try the stored displayName from the linked app
        if isValidDisplayName(linkedApp.displayName) {
            return linkedApp.displayName!
        }

        // 2. Try looking up from childLearningApps
        if let childApp = childLearningApps.first(where: { $0.logicalID == linkedApp.logicalID }),
           isValidDisplayName(childApp.displayName) {
            return childApp.displayName
        }

        // 3. Final fallback
        return "Learning App"
    }

    /// Filter linked apps to only include those that exist in childLearningApps
    private var validLinkedLearningApps: [LinkedLearningApp] {
        config.linkedLearningApps.filter { linkedApp in
            childLearningApps.contains { $0.logicalID == linkedApp.logicalID }
        }
    }

    private var unlockRequirementsSection: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Unlock Requirements")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()

                // Unlock mode badge
                Text(config.unlockMode == .all ? "ALL" : "ANY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(config.unlockMode == .all ? Color.orange : AppTheme.vibrantTeal)
                    .cornerRadius(8)
            }

            VStack(spacing: 8) {
                ForEach(validLinkedLearningApps, id: \.logicalID) { linkedApp in
                    HStack(spacing: 12) {
                        // App icon - look up from childLearningApps
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.vibrantTeal.opacity(0.15))
                                .frame(width: 32, height: 32)

                            CachedAppIcon(
                                iconURL: iconURLForLinkedApp(linkedApp.logicalID),
                                identifier: linkedApp.logicalID,
                                size: 32,
                                fallbackSymbol: "book.fill"
                            )
                        }

                        Text(displayNameForLinkedApp(linkedApp))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                            .lineLimit(1)

                        Spacer()

                        Text("\(linkedApp.minutesRequired) min")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.vibrantTeal.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Streak Bonus Section (matches AppStreakCard style)

    private func streakBonusSection(_ streak: AppStreakSettings) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Streak Settings")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .tracking(1)

                Spacer()

                // Bonus badge
                HStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.sunnyYellow)
                    Text(streak.bonusType == .percentage ? "+\(streak.bonusValue)%" : "+\(streak.bonusValue)m")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.sunnyYellow.opacity(0.15))
                .clipShape(Capsule())
            }

            // Streak cycle info
            HStack(alignment: .center, spacing: 16) {
                // Flame icon with ring
                ZStack {
                    Circle()
                        .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.sunnyYellow)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(streak.streakCycleDays)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.sunnyYellow)
                    +
                    Text(" Day Cycle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    Text("Earn bonus after \(streak.streakCycleDays) consecutive days")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()
            }

            // Milestone dots preview
            HStack(spacing: 6) {
                ForEach(0..<min(streak.streakCycleDays, 7), id: \.self) { index in
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.2))
                        .frame(height: 10)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.vibrantTeal, lineWidth: 1)
                                .opacity(0.3)
                        )
                        .frame(maxWidth: .infinity)
                }
                if streak.streakCycleDays > 7 {
                    Text("...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Usage Bar Chart

private struct UsageBarChart: View {
    let data: [(date: Date, minutes: Int)]
    let timeRange: ParentAppDetailView.TimeRange
    let categoryColor: Color
    let colorScheme: ColorScheme

    var body: some View {
        if #available(iOS 16.0, *) {
            chartView
        } else {
            Text("Charts require iOS 16+")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }

    private var xAxisUnit: Calendar.Component {
        switch timeRange {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }

    @available(iOS 16.0, *)
    private var chartView: some View {
        let sortedData = data.sorted { $0.date < $1.date }

        return Chart {
            ForEach(sortedData, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: xAxisUnit),
                    y: .value("Minutes", item.minutes)
                )
                .foregroundStyle(categoryColor.gradient)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisUnit)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(xAxisLabel(for: date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(categoryColor.opacity(0.15))
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
                    .foregroundStyle(categoryColor.opacity(0.15))
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(categoryColor.opacity(0.03))
                )
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        switch timeRange {
        case .daily:
            let today = calendar.startOfDay(for: Date())
            if calendar.isDate(date, inSameDayAs: today) {
                return "Today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(date, inSameDayAs: yesterday) {
                return "Yest."
            } else {
                formatter.dateFormat = "EEE"
                return String(formatter.string(from: date).prefix(3))
            }

        case .weekly:
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)

        case .monthly:
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Hourly Usage Chart Card

@available(iOS 16.0, *)
private struct HourlyUsageChartCard: View {
    let hourlySeconds: [Int]
    let accentColor: Color

    @Environment(\.colorScheme) private var colorScheme

    private var hourlyData: [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<24).compactMap { hour in
            guard let hourDate = calendar.date(byAdding: .hour, value: hour, to: today) else { return nil }
            let seconds = hour < hourlySeconds.count ? hourlySeconds[hour] : 0
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

                Text("Today's Hourly Usage")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Text("\(totalMinutes)m total")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
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
                                Text("\(minutes)m")
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
                                .fill(accentColor.opacity(0.03))
                        )
                }
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.regular) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))

            Text("No usage recorded today")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
    }

    private func hourLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return String(format: "%02d", hour)
    }
}

// MARK: - Saving Config Overlay

private struct SavingConfigOverlayView: View {
    let appName: String
    @Environment(\.colorScheme) var colorScheme
    @State private var iconScale: CGFloat = 1.0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Saving card
            VStack(spacing: 20) {
                // Animated gear/upload icon
                ZStack {
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .scaleEffect(iconScale)

                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .scaleEffect(iconScale)
                }
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        iconScale = 1.1
                    }
                }

                VStack(spacing: 8) {
                    Text("Saving Changes...")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("Sending configuration to child's device")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }

                // Animated progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(AppTheme.vibrantTeal)
                            .frame(width: 10, height: 10)
                            .scaleEffect(isAnimating ? 1.0 : 0.5)
                            .opacity(isAnimating ? 1.0 : 0.3)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            isAnimating = true
        }
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
