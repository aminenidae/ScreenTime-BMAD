import SwiftUI
import FamilyControls
import ManagedSettings

/// Sheet for configuring per-app schedule and time limits
struct AppConfigurationSheet: View {
    let token: ApplicationToken
    let appName: String
    let appType: AppType
    let learningSnapshots: [LearningAppSnapshot]  // For reward apps: available learning apps to link

    @Binding var configuration: AppScheduleConfiguration
    let onSave: (AppScheduleConfiguration) -> Void
    let onCancel: () -> Void

    @State private var localConfig: AppScheduleConfiguration
    @State private var isFullDayAccess: Bool

    init(
        token: ApplicationToken,
        appName: String,
        appType: AppType,
        learningSnapshots: [LearningAppSnapshot] = [],  // Default to empty for learning apps
        configuration: Binding<AppScheduleConfiguration>,
        onSave: @escaping (AppScheduleConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.token = token
        self.appName = appName
        self.appType = appType
        self.learningSnapshots = learningSnapshots
        self._configuration = configuration
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize local state
        _localConfig = State(initialValue: configuration.wrappedValue)
        _isFullDayAccess = State(initialValue: configuration.wrappedValue.allowedTimeWindow.isFullDay)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App header
                    appHeader

                    Divider()
                        .background(ChallengeBuilderTheme.border)

                    // Time Window Section
                    TimeWindowPicker(
                        timeWindow: $localConfig.allowedTimeWindow,
                        dailyTimeWindows: $localConfig.dailyTimeWindows,
                        useAdvancedConfig: $localConfig.useAdvancedTimeWindowConfig,
                        isFullDay: $isFullDayAccess
                    )
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

                    Divider()
                        .background(ChallengeBuilderTheme.border)

                    // Daily Limits Section
                    // Pass time window duration to cap limits for both Learning and Reward apps
                    DailyLimitsPicker(
                        dailyLimits: $localConfig.dailyLimits,
                        useAdvancedConfig: $localConfig.useAdvancedDayConfig,
                        maxAllowedMinutes: localConfig.allowedTimeWindow.durationInMinutes,
                        dailyTimeWindows: localConfig.dailyTimeWindows,
                        useAdvancedTimeWindows: localConfig.useAdvancedTimeWindowConfig
                    )

                    // Inline summary message
                    configSummarySection

                    // Unlock Requirements Section (reward apps only)
                    if appType == .reward {
                        Divider()
                            .background(ChallengeBuilderTheme.border)

                        LinkedLearningAppsPicker(
                            linkedApps: $localConfig.linkedLearningApps,
                            unlockMode: $localConfig.unlockMode,
                            learningSnapshots: learningSnapshots
                        )
                    }

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(ChallengeBuilderTheme.background.ignoresSafeArea())
            .navigationTitle("Configure App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(AppTheme.playfulCoral)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(localConfig)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
    }

    // MARK: - Config Summary Section

    private var configSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Summary")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(summaryLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.vibrantTeal)

                        Text(line)
                            .font(.system(size: 13))
                            .foregroundColor(ChallengeBuilderTheme.mutedText)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.vibrantTeal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.vibrantTeal.opacity(0.2), lineWidth: 1)
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
        let timeRange = timeWindow.isFullDay ? "anytime" : "between \(formatTime(hour: timeWindow.startHour, minute: timeWindow.startMinute)) and \(formatTime(hour: timeWindow.endHour, minute: timeWindow.endMinute))"

        if limits.weekdayLimit == limits.weekendLimit {
            // 1 line - same for all days
            return [formatFullLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange)]
        } else {
            // 2 lines - weekday vs weekend
            return [
                "Weekdays (Mon-Fri): \(formatUsageLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange))",
                "Weekends (Sat-Sun): \(formatUsageLine(limits.weekendLimit, timeWindow: timeWindow, timeRange: timeRange))"
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
            let timeRange = window.isFullDay ? "anytime" : "between \(formatTime(hour: window.startHour, minute: window.startMinute)) and \(formatTime(hour: window.endHour, minute: window.endMinute))"
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
            let timeRange = window.isFullDay ? "anytime" : "between \(formatTime(hour: window.startHour, minute: window.startMinute)) and \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return [formatFullLine(limits.limit(for: 2), timeWindow: window, timeRange: timeRange)]
        }

        // Check if weekdays same AND weekends same (classic pattern)
        if allWeekdaysSame && weekendSame {
            return [
                "Weekdays (Mon-Fri): \(summaryFor(weekday: 2))",
                "Weekends (Sat-Sun): \(summaryFor(weekday: 7))"
            ]
        }

        var lines: [String] = []

        // Weekdays: show grouped or individual
        if allWeekdaysSame {
            lines.append("Weekdays (Mon-Fri): \(summaryFor(weekday: 2))")
        } else {
            // Show individual weekdays
            for weekday in 2...6 {
                lines.append("\(dayName(for: weekday)): \(summaryFor(weekday: weekday))")
            }
        }

        // Weekend: show grouped or individual
        if weekendSame {
            lines.append("Weekends (Sat-Sun): \(summaryFor(weekday: 7))")
        } else {
            lines.append("Saturday: \(summaryFor(weekday: 7))")
            lines.append("Sunday: \(summaryFor(weekday: 1))")
        }

        return lines
    }

    private func formatFullLine(_ minutes: Int, timeWindow: AllowedTimeWindow, timeRange: String) -> String {
        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            if timeWindow.isFullDay {
                return "Your child can use this app anytime"
            } else {
                return "Your child can use this app \(timeRange)"
            }
        } else {
            return "Your child can use this app for \(formatDuration(minutes)) \(timeRange)"
        }
    }

    private func formatUsageLine(_ minutes: Int, timeWindow: AllowedTimeWindow, timeRange: String) -> String {
        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            return timeRange
        } else {
            return "\(formatDuration(minutes)) \(timeRange)"
        }
    }

    private func dayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return ""
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 1440 {
            return "unlimited"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
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
        HStack(spacing: 16) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.5)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ChallengeBuilderTheme.surface)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(ChallengeBuilderTheme.surface)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                // App name
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                } else {
                    Text(appName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                }

                // Category badge
                HStack(spacing: 6) {
                    Image(systemName: appType == .learning ? "book.fill" : "gift.fill")
                        .font(.system(size: 11))

                    Text(appType == .learning ? "Learning" : "Reward")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(appType == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((appType == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral).opacity(0.15))
                )
            }

            Spacer()
        }
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
