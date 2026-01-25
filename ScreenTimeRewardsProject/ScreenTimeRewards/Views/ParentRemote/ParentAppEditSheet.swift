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
                            availableLearningApps: childLearningApps.filter { $0.category == "Learning" },
                            rewardAppIconURL: localConfig.iconURL,
                            rewardAppLogicalID: localConfig.logicalID
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
            .navigationTitle("Configure App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? AppTheme.lightCream : accentColor)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(localConfig)
                    }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(hasChanges ? (colorScheme == .dark ? AppTheme.lightCream : accentColor) : .gray)
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
        // Calculate estimated daily reward based on minimum learning requirements
        func estimatedRewardFor(_ app: LinkedLearningApp) -> Int {
            // (minutesRequired / ratioLearningMinutes) * rewardMinutesEarned
            guard app.ratioLearningMinutes > 0 else { return 0 }
            return (app.minutesRequired / app.ratioLearningMinutes) * app.rewardMinutesEarned
        }

        switch localConfig.unlockMode {
        case .all:
            return localConfig.linkedLearningApps.reduce(0) { $0 + estimatedRewardFor($1) }
        case .any:
            return localConfig.linkedLearningApps.map { estimatedRewardFor($0) }.max() ?? 0
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

                // Category badge
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: localConfig.isLearningApp ? "book.fill" : "gift.fill")
                        .font(.system(size: 10))

                    Text(localConfig.isLearningApp ? "Learning" : "Reward")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
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

                Text("Summary")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                // Usage/time limit summary lines (text only)
                ForEach(summaryLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)

                        Text(line)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                    }
                }

                // Unlock requirements with inline icons (reward apps only)
                if localConfig.isRewardApp {
                    unlockSummaryView
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
        let timeRange = timeWindow.isFullDay ? "Anytime" : "between \(formatTime(hour: timeWindow.startHour, minute: timeWindow.startMinute)) and \(formatTime(hour: timeWindow.endHour, minute: timeWindow.endMinute))"

        if limits.weekdayLimit == limits.weekendLimit {
            return [formatFullLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange)]
        } else {
            return [
                "Weekdays (Mon-Fri): \(formatUsageLine(limits.weekdayLimit, timeWindow: timeWindow, timeRange: timeRange))",
                "Weekends (Sat-Sun): \(formatUsageLine(limits.weekendLimit, timeWindow: timeWindow, timeRange: timeRange))"
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
            let timeRange = window.isFullDay ? "Anytime" : "between \(formatTime(hour: window.startHour, minute: window.startMinute)) and \(formatTime(hour: window.endHour, minute: window.endMinute))"
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
            let timeRange = window.isFullDay ? "Anytime" : "between \(formatTime(hour: window.startHour, minute: window.startMinute)) and \(formatTime(hour: window.endHour, minute: window.endMinute))"
            return [formatFullLine(limits.limit(for: 2), timeWindow: window, timeRange: timeRange)]
        }

        if allWeekdaysSame && weekendSame {
            return [
                "Weekdays (Mon-Fri): \(summaryFor(weekday: 2))",
                "Weekends (Sat-Sun): \(summaryFor(weekday: 7))"
            ]
        }

        var lines: [String] = []
        if allWeekdaysSame {
            lines.append("Weekdays (Mon-Fri): \(summaryFor(weekday: 2))")
        } else {
            for weekday in 2...6 {
                lines.append("\(dayName(for: weekday)): \(summaryFor(weekday: weekday))")
            }
        }

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
            return "Unlimited"
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

    // MARK: - Unlock Summary View (with inline icons)

    /// Helper to find a learning app by logical ID
    private func learningAppFor(logicalID: String) -> FullAppConfigDTO? {
        childLearningApps.first { $0.logicalID == logicalID }
    }

    /// Rich view for unlock requirements with inline app icons
    @ViewBuilder
    private var unlockSummaryView: some View {
        let linkedApps = localConfig.linkedLearningApps

        if linkedApps.isEmpty {
            EmptyView()
        } else if linkedApps.count <= 4 {
            // Show each app on separate line with icon
            ForEach(linkedApps, id: \.logicalID) { app in
                if let learningApp = learningAppFor(logicalID: app.logicalID) {
                    unlockAppRow(app: app, learningApp: learningApp)
                }
            }
        } else {
            // Summarize for 5+ apps
            let modeText = localConfig.unlockMode == .all ? "all" : "any"
            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                Text("•")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
                Text("Complete \(modeText) \(linkedApps.count) apps goal to unlock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
            }
        }
    }

    /// Single row for an unlock app requirement with inline icons
    private func unlockAppRow(app: LinkedLearningApp, learningApp: FullAppConfigDTO) -> some View {
        let periodText = app.goalPeriod == .daily ? "Day" : "Week"
        return HStack(alignment: .center, spacing: 4) {
            Text("•")
                .font(.system(size: 11))
                .foregroundColor(accentColor)

            // Learning app icon (CachedAppIcon or fallback)
            if let iconURL = learningApp.iconURL, !iconURL.isEmpty {
                CachedAppIcon(
                    iconURL: iconURL,
                    identifier: learningApp.logicalID,
                    size: 24,
                    fallbackSymbol: "book.fill"
                )
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(AppTheme.vibrantTeal.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.vibrantTeal)
                    )
            }

            Text("\(app.minutesRequired) minutes / \(periodText) to automatically unlock")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))

            // Reward app icon (CachedAppIcon or fallback)
            if let iconURL = localConfig.iconURL, !iconURL.isEmpty {
                CachedAppIcon(
                    iconURL: iconURL,
                    identifier: localConfig.logicalID,
                    size: 24,
                    fallbackSymbol: "gift.fill"
                )
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
            }
        }
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
