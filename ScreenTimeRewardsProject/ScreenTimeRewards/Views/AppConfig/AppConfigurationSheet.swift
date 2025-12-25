import SwiftUI
import FamilyControls
import ManagedSettings

/// Section identifiers for scroll-to-section functionality
enum AppConfigSection: String {
    case summary = "config_summary_section"
    case timeWindow = "config_time_window_section"
    case dailyLimits = "config_daily_limits_section"
    case linkedApps = "config_linked_apps_section"
    case save = "config_save_section"
}

/// Sheet for configuring per-app schedule and time limits
struct AppConfigurationSheet: View {
    let token: ApplicationToken
    let appName: String
    let appType: AppType
    let learningSnapshots: [LearningAppSnapshot]  // For reward apps: available learning apps to link
    @Environment(\.colorScheme) private var colorScheme // Added for AppTheme.background and AppTheme.appCard

    @Binding var configuration: AppScheduleConfiguration
    let onSave: (AppScheduleConfiguration) -> Void
    let onCancel: () -> Void

    /// Optional binding to trigger scrolling to a specific section
    @Binding var scrollToSection: AppConfigSection?

    @State private var localConfig: AppScheduleConfiguration
    @State private var isFullDayAccess: Bool

    init(
        token: ApplicationToken,
        appName: String,
        appType: AppType,
        learningSnapshots: [LearningAppSnapshot] = [],  // Default to empty for learning apps
        configuration: Binding<AppScheduleConfiguration>,
        scrollToSection: Binding<AppConfigSection?> = .constant(nil),
        onSave: @escaping (AppScheduleConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.token = token
        self.appName = appName
        self.appType = appType
        self.learningSnapshots = learningSnapshots
        self._configuration = configuration
        self._scrollToSection = scrollToSection
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize local state
        _localConfig = State(initialValue: configuration.wrappedValue)
        _isFullDayAccess = State(initialValue: configuration.wrappedValue.allowedTimeWindow.isFullDay)
    }

    private var accentColor: Color {
        appType == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) { // Use AppTheme.Spacing
                        // App header
                        appHeader

                        // Summary card (moved to top for visibility)
                        configSummarySection
                            .id("config_summary_section")
                            .tutorialTarget("config_summary")

                        // Divider
                        Rectangle()
                            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1)) // Use AppTheme color
                            .frame(height: 1)

                        // Time Window Section
                        TimeWindowPicker(
                            timeWindow: $localConfig.allowedTimeWindow,
                            dailyTimeWindows: $localConfig.dailyTimeWindows,
                            useAdvancedConfig: $localConfig.useAdvancedTimeWindowConfig,
                            isFullDay: $isFullDayAccess
                        )
                        .id(AppConfigSection.timeWindow.rawValue)
                        .tutorialTarget("config_time_window")
                        .onChange(of: isFullDayAccess) { newValue in
                            if newValue {
                                localConfig.allowedTimeWindow = .fullDay
                                localConfig.dailyTimeWindows = .allFullDay
                                localConfig.useAdvancedTimeWindowConfig = false
                                // Smart default for learning apps: set to unlimited when full day
                                if appType == .learning {
                                    localConfig.dailyLimits = .unlimited
                                }
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1)) // Use AppTheme color
                            .frame(height: 1)

                        // Daily Limits Section
                        DailyLimitsPicker(
                            dailyLimits: $localConfig.dailyLimits,
                            useAdvancedConfig: $localConfig.useAdvancedDayConfig,
                            maxAllowedMinutes: localConfig.allowedTimeWindow.durationInMinutes,
                            dailyTimeWindows: localConfig.dailyTimeWindows,
                            useAdvancedTimeWindows: localConfig.useAdvancedTimeWindowConfig
                        )
                        .id(AppConfigSection.dailyLimits.rawValue)
                        .tutorialTarget("config_daily_limits")

                        // Unlock Requirements Section (reward apps only)
                        if appType == .reward {
                            Rectangle()
                                .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1)) // Use AppTheme color
                                .frame(height: 1)

                            LinkedLearningAppsPicker(
                                linkedApps: $localConfig.linkedLearningApps,
                                unlockMode: $localConfig.unlockMode,
                                learningSnapshots: learningSnapshots
                            )
                            .id(AppConfigSection.linkedApps.rawValue)
                            .tutorialTarget("config_linked_apps")

                            // Streak Rewards Section (reward apps only)
                            Rectangle()
                                .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                                .frame(height: 1)

                            let estimatedReward: Int = {
                                switch localConfig.unlockMode {
                                case .all:
                                    return localConfig.linkedLearningApps.reduce(0) { $0 + $1.rewardMinutesEarned }
                                case .any:
                                    return localConfig.linkedLearningApps.map { $0.rewardMinutesEarned }.max() ?? 0
                                }
                            }()

                            StreakSettingsPicker(
                                streakSettings: $localConfig.streakSettings,
                                estimatedDailyReward: estimatedReward
                            )
                            .id("config_streak_section")
                            .tutorialTarget("config_streak")
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(AppTheme.Spacing.large) // Use AppTheme.Spacing
                }
                .onChange(of: scrollToSection) { section in
                    if let section = section {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(section.rawValue, anchor: .top)
                        }
                        // Reset after scrolling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            scrollToSection = nil
                        }
                    }
                }
            }
            .background(AppTheme.background(for: colorScheme).ignoresSafeArea()) // Use AppTheme background
            .navigationTitle("CONFIGURE APP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        onCancel()
                    }
                    .font(.system(size: 18, weight: .bold)) // Standardized button font size
                    .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color
                    .textCase(.uppercase)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") {
                        onSave(localConfig)
                    }
                    .font(.system(size: 18, weight: .bold)) // Standardized button font size
                    .foregroundColor(accentColor)
                    .textCase(.uppercase)
                    .tutorialTarget("config_save")
                }
            }
            .toolbarBackground(AppTheme.background(for: colorScheme), for: .navigationBar) // Use AppTheme background
        }
    }

    // MARK: - Config Summary Section

    private var configSummarySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) { // Use AppTheme.Spacing
            HStack(spacing: AppTheme.Spacing.tiny) { // Use AppTheme.Spacing
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)

                Text("SUMMARY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) { // Use AppTheme.Spacing
                ForEach(summaryLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: AppTheme.Spacing.small) { // Use AppTheme.Spacing
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)

                        Text(line)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8)) // Use AppTheme color
                            .textCase(.uppercase)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.regular) // Use AppTheme.Spacing
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large) // Use AppTheme.CornerRadius
                .fill(accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large) // Use AppTheme.CornerRadius
                        .stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var summaryLines: [String] {
        let limits = localConfig.dailyLimits
        let useAdvancedTime = localConfig.useAdvancedTimeWindowConfig
        let useAdvancedLimits = localConfig.useAdvancedDayConfig

        // If either time windows or limits are per-day, use smart grouping
        if useAdvancedTime || useAdvancedLimits {
            return buildSmartSummary(limits: limits, useAdvancedTime: useAdvancedTime)
        }

        // Simple mode
        let timeWindow = localConfig.allowedTimeWindow
        let timeRange = timeWindow.isFullDay ? "ANYTIME" : "BETWEEN \(formatTime(hour: timeWindow.startHour, minute: timeWindow.startMinute)) AND \(formatTime(hour: timeWindow.endHour, minute: timeWindow.endMinute))"

        if limits.weekdayLimit == limits.weekendLimit {
            // 1 line - same for all days
            return [formatFullLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange)]
        } else {
            // 2 lines - weekday vs weekend
            return [
                "WEEKDAYS (MON-FRI): \(formatUsageLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange))",
                "WEEKENDS (SAT-SUN): \(formatUsageLine(limits.weekendLimit, timeWindow: timeWindow, timeRange: timeRange))"
            ]
        }
    }

    /// Build smart summary that groups days with identical settings
    private func buildSmartSummary(limits: DailyLimits, useAdvancedTime: Bool) -> [String] {
        // Helper to get config key for a day (combines time window + limit)
        func configKey(for weekday: Int) -> String {
            let window = useAdvancedTime ? localConfig.dailyTimeWindows.window(for: weekday) : localConfig.allowedTimeWindow
            let limit = limits.limit(for: weekday)
            return "\(window.startHour):\(window.startMinute)-\(window.endHour):\(window.endMinute)|\(limit)"
        }

        // Helper to format a day's summary
        func summaryFor(weekday: Int) -> String {
            let window = useAdvancedTime ? localConfig.dailyTimeWindows.window(for: weekday) : localConfig.allowedTimeWindow
            let limitMinutes = limits.limit(for: weekday)
            let timeRange = window.isFullDay ? "ANYTIME" : "BETWEEN \(formatTime(hour: window.startHour, minute: window.startMinute)) AND \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return formatUsageLine(limitMinutes, timeWindow: window, timeRange: timeRange)
        }

        // Check if all weekdays (Mon-Fri: 2-6) are the same
        let weekdayKeys = (2...6).map { configKey(for: $0) }
        let allWeekdaysSame = Set(weekdayKeys).count == 1

        // Check if both weekend days (Sat: 7, Sun: 1) are the same
        let satKey = configKey(for: 7)
        let sunKey = configKey(for: 1)
        let weekendSame = satKey == sunKey

        // Check if everything is the same
        let allKeys = (1...7).map { configKey(for: $0) }
        if Set(allKeys).count == 1 {
            // All 7 days identical - show 1 line
            let window = useAdvancedTime ? localConfig.dailyTimeWindows.window(for: 2) : localConfig.allowedTimeWindow
            let timeRange = window.isFullDay ? "ANYTIME" : "BETWEEN \(formatTime(hour: window.startHour, minute: window.startMinute)) AND \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return [formatFullLine(limits.limit(for: 2), timeWindow: window, timeRange: timeRange)]
        }

        // Check if weekdays same AND weekends same (classic pattern)
        if allWeekdaysSame && weekendSame {
            return [
                "WEEKDAYS (MON-FRI): \(summaryFor(weekday: 2))",
                "WEEKENDS (SAT-SUN): \(summaryFor(weekday: 7))"
            ]
        }

        var lines: [String] = []

        // Weekdays: show grouped or individual
        if allWeekdaysSame {
            lines.append("WEEKDAYS (MON-FRI): \(summaryFor(weekday: 2))")
        } else {
            // Show individual weekdays
            for weekday in 2...6 {
                lines.append("\(dayName(for: weekday)): \(summaryFor(weekday: weekday))")
            }
        }

        // Weekend: show grouped or individual
        if weekendSame {
            lines.append("WEEKENDS (SAT-SUN): \(summaryFor(weekday: 7))")
        } else {
            lines.append("SATURDAY: \(summaryFor(weekday: 7))")
            lines.append("SUNDAY: \(summaryFor(weekday: 1))")
        }

        return lines
    }

    private func formatFullLine(_ minutes: Int, timeWindow: AllowedTimeWindow, timeRange: String) -> String {
        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            if timeWindow.isFullDay {
                return "YOUR CHILD CAN USE THIS APP ANYTIME"
            } else {
                return "YOUR CHILD CAN USE THIS APP \(timeRange)"
            }
        } else {
            return "YOUR CHILD CAN USE THIS APP FOR \(formatDuration(minutes)) \(timeRange)"
        }
    }

    private func formatUsageLine(_ minutes: Int, timeWindow: AllowedTimeWindow, timeRange: String) -> String {
        var modifiedTimeRange = timeRange
        modifiedTimeRange = modifiedTimeRange.replacingOccurrences(of: "between", with: "BETWEEN")
        modifiedTimeRange = modifiedTimeRange.replacingOccurrences(of: "and", with: "AND")

        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            return modifiedTimeRange
        } else {
            return "\(formatDuration(minutes)) \(modifiedTimeRange)"
        }
    }

    private func dayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "SUNDAY"
        case 2: return "MONDAY"
        case 3: return "TUESDAY"
        case 4: return "WEDNESDAY"
        case 5: return "THURSDAY"
        case 6: return "FRIDAY"
        case 7: return "SATURDAY"
        default: return ""
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 1440 {
            return "UNLIMITED"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)H \(mins)M"
        } else if hours > 0 {
            return "\(hours)H"
        } else {
            return "\(mins)M"
        }
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        if minute == 0 {
            return "\(displayHour):00 \(period)"
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: AppTheme.Spacing.regular) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.8)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)) // Use AppTheme.CornerRadius
            } else {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium) // Use AppTheme.CornerRadius
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 24))
                            .foregroundColor(accentColor)
                    )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) { // Use AppTheme.Spacing
                // App name
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 18, weight: .bold)) // Standardized with other titles
                        .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color
                        .lineLimit(1)
                        .textCase(.uppercase)
                } else {
                    Text(appName)
                        .font(.system(size: 18, weight: .bold)) // Standardized with other titles
                        .foregroundColor(AppTheme.brandedText(for: colorScheme)) // Use AppTheme color
                        .lineLimit(1)
                        .textCase(.uppercase)
                }

                // Category badge
                HStack(spacing: AppTheme.Spacing.tiny) { // Use AppTheme.Spacing
                    Image(systemName: appType == .learning ? "book.fill" : "gift.fill")
                        .font(.system(size: 10))

                    Text(appType == .learning ? "LEARNING" : "REWARD")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, AppTheme.Spacing.regular) // Use AppTheme.Spacing
                .padding(.vertical, AppTheme.Spacing.tiny) // Use AppTheme.Spacing
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.15))
                )
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.regular) // Use AppTheme.Spacing
        .appCard(colorScheme) // Using the global appCard styling
    }

}

// MARK: - Preview

#if DEBUG
struct AppConfigurationSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available - requires ApplicationToken")
    }
}
#endif
