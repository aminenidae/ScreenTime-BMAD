import SwiftUI

/// Sheet for parent to edit a child's app configuration remotely.
/// This mirrors the child's AppConfigurationSheet structure exactly.
struct ParentAppEditSheet: View {
    @Binding var config: MutableAppConfigDTO?
    let childLearningApps: [FullAppConfigDTO]  // Available learning apps on child
    let onSave: (MutableAppConfigDTO) -> Void
    let onCancel: () -> Void

    @State private var localConfig: MutableAppConfigDTO
    @State private var isFullDayAccess: Bool

    @Environment(\.colorScheme) var colorScheme

    init(
        config: Binding<MutableAppConfigDTO?>,
        childLearningApps: [FullAppConfigDTO] = [],
        onSave: @escaping (MutableAppConfigDTO) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._config = config
        self.childLearningApps = childLearningApps
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize local state from the config
        if let existingConfig = config.wrappedValue {
            _localConfig = State(initialValue: existingConfig)
            _isFullDayAccess = State(initialValue: existingConfig.scheduleConfig?.allowedTimeWindow.isFullDay ?? true)
        } else {
            _localConfig = State(initialValue: MutableAppConfigDTO.empty)
            _isFullDayAccess = State(initialValue: true)
        }
    }

    private var accentColor: Color {
        localConfig.isLearningApp ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    private var hasChanges: Bool {
        localConfig.hasChanges
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    // App header (matches child styling)
                    appHeader

                    // Summary card (matches child)
                    configSummarySection

                    divider

                    // Time Window Section
                    if let scheduleConfig = localConfig.scheduleConfig {
                        TimeWindowPicker(
                            timeWindow: Binding(
                                get: { scheduleConfig.allowedTimeWindow },
                                set: { newValue in
                                    localConfig.scheduleConfig?.allowedTimeWindow = newValue
                                }
                            ),
                            dailyTimeWindows: Binding(
                                get: { scheduleConfig.dailyTimeWindows },
                                set: { newValue in
                                    localConfig.scheduleConfig?.dailyTimeWindows = newValue
                                }
                            ),
                            useAdvancedConfig: Binding(
                                get: { scheduleConfig.useAdvancedTimeWindowConfig },
                                set: { newValue in
                                    localConfig.scheduleConfig?.useAdvancedTimeWindowConfig = newValue
                                }
                            ),
                            isFullDay: $isFullDayAccess
                        )
                        .onChange(of: isFullDayAccess) { newValue in
                            if newValue {
                                localConfig.scheduleConfig?.allowedTimeWindow = .fullDay
                                localConfig.scheduleConfig?.dailyTimeWindows = .allFullDay
                                localConfig.scheduleConfig?.useAdvancedTimeWindowConfig = false
                                // Smart default for learning apps: set to unlimited when full day
                                if localConfig.isLearningApp {
                                    localConfig.scheduleConfig?.dailyLimits = .unlimited
                                }
                            }
                        }

                        divider

                        // Daily Limits Section
                        DailyLimitsPicker(
                            dailyLimits: Binding(
                                get: { scheduleConfig.dailyLimits },
                                set: { newValue in
                                    localConfig.scheduleConfig?.dailyLimits = newValue
                                }
                            ),
                            useAdvancedConfig: Binding(
                                get: { scheduleConfig.useAdvancedDayConfig },
                                set: { newValue in
                                    localConfig.scheduleConfig?.useAdvancedDayConfig = newValue
                                }
                            ),
                            maxAllowedMinutes: scheduleConfig.allowedTimeWindow.durationInMinutes,
                            dailyTimeWindows: scheduleConfig.dailyTimeWindows,
                            useAdvancedTimeWindows: scheduleConfig.useAdvancedTimeWindowConfig
                        )
                    }

                    // Reward-specific sections
                    if localConfig.isRewardApp {
                        divider

                        // Linked Learning Apps
                        ParentLinkedAppsPicker(
                            linkedApps: $localConfig.linkedLearningApps,
                            unlockMode: $localConfig.unlockMode,
                            availableLearningApps: childLearningApps.filter { $0.category == "Learning" }
                        )

                        divider

                        // Streak Settings (using shared component)
                        StreakSettingsPicker(
                            streakSettings: $localConfig.streakSettings,
                            estimatedDailyReward: estimatedReward
                        )
                    }

                    // Note about remote limitations (parent-specific)
                    limitationsNote

                    Spacer(minLength: 40)
                }
                .padding(AppTheme.Spacing.large)
            }
            .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
            .navigationTitle("CONFIGURE APP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        onCancel()
                    }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? AppTheme.lightCream : accentColor)
                    .textCase(.uppercase)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") {
                        onSave(localConfig)
                    }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(hasChanges ? (colorScheme == .dark ? AppTheme.lightCream : accentColor) : .gray)
                    .textCase(.uppercase)
                    .disabled(!hasChanges)
                }
            }
            .toolbarBackground(AppTheme.background(for: colorScheme), for: .navigationBar)
        }
        .onAppear {
            // Sync localConfig from binding after view appears
            if let existingConfig = config {
                localConfig = existingConfig
                isFullDayAccess = existingConfig.scheduleConfig?.allowedTimeWindow.isFullDay ?? true
            }
            // Ensure schedule config exists
            if localConfig.scheduleConfig == nil {
                localConfig.scheduleConfig = localConfig.isRewardApp
                    ? .defaultReward(logicalID: localConfig.logicalID)
                    : .defaultLearning(logicalID: localConfig.logicalID)
            }
        }
    }

    // MARK: - Computed Properties

    private var estimatedReward: Int {
        switch localConfig.unlockMode {
        case .all:
            return localConfig.linkedLearningApps.reduce(0) { $0 + $1.rewardMinutesEarned }
        case .any:
            return localConfig.linkedLearningApps.map { $0.rewardMinutesEarned }.max() ?? 0
        }
    }

    // MARK: - App Header (matches child styling)

    private var appHeader: some View {
        HStack(spacing: AppTheme.Spacing.regular) {
            // App icon - show styled fallback if no icon URL
            if let iconURL = localConfig.iconURL, !iconURL.isEmpty {
                CachedAppIcon(
                    iconURL: iconURL,
                    identifier: localConfig.logicalID,
                    size: 56,
                    fallbackSymbol: localConfig.isLearningApp ? "book.fill" : "gamecontroller.fill"
                )
            } else {
                // Styled fallback icon
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: localConfig.isLearningApp ? "book.fill" : "gamecontroller.fill")
                        .font(.system(size: 28))
                        .foregroundColor(accentColor)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                // App name
                Text(localConfig.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .lineLimit(1)
                    .textCase(.uppercase)

                // Category badge
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: localConfig.isLearningApp ? "book.fill" : "gift.fill")
                        .font(.system(size: 10))

                    Text(localConfig.isLearningApp ? "LEARNING" : "REWARD")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, AppTheme.Spacing.regular)
                .padding(.vertical, AppTheme.Spacing.tiny)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.15))
                )
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.regular)
        .appCard(colorScheme)
    }

    // MARK: - Config Summary Section (matches child)

    private var configSummarySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.tiny) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)

                Text("SUMMARY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                ForEach(summaryLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)

                        Text(line)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                            .textCase(.uppercase)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var summaryLines: [String] {
        guard let scheduleConfig = localConfig.scheduleConfig else {
            return ["No schedule configured"]
        }

        let limits = scheduleConfig.dailyLimits
        let useAdvancedTime = scheduleConfig.useAdvancedTimeWindowConfig
        let useAdvancedLimits = scheduleConfig.useAdvancedDayConfig

        // If either time windows or limits are per-day, use smart grouping
        if useAdvancedTime || useAdvancedLimits {
            return buildSmartSummary(scheduleConfig: scheduleConfig)
        }

        // Simple mode
        let timeWindow = scheduleConfig.allowedTimeWindow
        let timeRange = timeWindow.isFullDay ? "ANYTIME" : "BETWEEN \(formatTime(hour: timeWindow.startHour, minute: timeWindow.startMinute)) AND \(formatTime(hour: timeWindow.endHour, minute: timeWindow.endMinute))"

        if limits.weekdayLimit == limits.weekendLimit {
            return [formatFullLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange)]
        } else {
            return [
                "WEEKDAYS (MON-FRI): \(formatUsageLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange))",
                "WEEKENDS (SAT-SUN): \(formatUsageLine(limits.weekendLimit, timeWindow: timeWindow, timeRange: timeRange))"
            ]
        }
    }

    private func buildSmartSummary(scheduleConfig: AppScheduleConfiguration) -> [String] {
        let limits = scheduleConfig.dailyLimits
        let useAdvancedTime = scheduleConfig.useAdvancedTimeWindowConfig

        func configKey(for weekday: Int) -> String {
            let window = useAdvancedTime ? scheduleConfig.dailyTimeWindows.window(for: weekday) : scheduleConfig.allowedTimeWindow
            let limit = limits.limit(for: weekday)
            return "\(window.startHour):\(window.startMinute)-\(window.endHour):\(window.endMinute)|\(limit)"
        }

        func summaryFor(weekday: Int) -> String {
            let window = useAdvancedTime ? scheduleConfig.dailyTimeWindows.window(for: weekday) : scheduleConfig.allowedTimeWindow
            let limitMinutes = limits.limit(for: weekday)
            let timeRange = window.isFullDay ? "ANYTIME" : "BETWEEN \(formatTime(hour: window.startHour, minute: window.startMinute)) AND \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return formatUsageLine(limitMinutes, timeWindow: window, timeRange: timeRange)
        }

        let weekdayKeys = (2...6).map { configKey(for: $0) }
        let allWeekdaysSame = Set(weekdayKeys).count == 1
        let satKey = configKey(for: 7)
        let sunKey = configKey(for: 1)
        let weekendSame = satKey == sunKey

        let allKeys = (1...7).map { configKey(for: $0) }
        if Set(allKeys).count == 1 {
            let window = useAdvancedTime ? scheduleConfig.dailyTimeWindows.window(for: 2) : scheduleConfig.allowedTimeWindow
            let timeRange = window.isFullDay ? "ANYTIME" : "BETWEEN \(formatTime(hour: window.startHour, minute: window.startMinute)) AND \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return [formatFullLine(limits.limit(for: 2), timeWindow: window, timeRange: timeRange)]
        }

        if allWeekdaysSame && weekendSame {
            return [
                "WEEKDAYS (MON-FRI): \(summaryFor(weekday: 2))",
                "WEEKENDS (SAT-SUN): \(summaryFor(weekday: 7))"
            ]
        }

        var lines: [String] = []
        if allWeekdaysSame {
            lines.append("WEEKDAYS (MON-FRI): \(summaryFor(weekday: 2))")
        } else {
            for weekday in 2...6 {
                lines.append("\(dayName(for: weekday)): \(summaryFor(weekday: weekday))")
            }
        }

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
        if minutes >= 1440 || (minutes >= timeWindow.durationInMinutes && !timeWindow.isFullDay) {
            return timeRange
        } else {
            return "\(formatDuration(minutes)) \(timeRange)"
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

    // MARK: - Limitations Note (parent-specific)

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Remote Configuration Note")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text("Changes will apply when the child's device syncs. New apps can only be added from the child's device due to Apple privacy requirements.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
            .frame(height: 1)
    }
}
