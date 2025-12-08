import SwiftUI

/// A picker for setting daily time limits (weekday/weekend or per-day)
struct DailyLimitsPicker: View {
    @Binding var dailyLimits: DailyLimits
    @Binding var useAdvancedConfig: Bool
    let maxAllowedMinutes: Int?               // Simple mode: same max for all days
    let dailyTimeWindows: DailyTimeWindows?   // Advanced mode: per-day max from time windows
    let useAdvancedTimeWindows: Bool          // Whether time windows are in advanced mode

    /// The effective maximum for simple mode (same for all days)
    private var effectiveMax: Int {
        maxAllowedMinutes ?? 1440
    }

    /// Get the effective max for a specific weekday
    private func effectiveMax(for weekday: Int) -> Int {
        if useAdvancedTimeWindows, let windows = dailyTimeWindows {
            return windows.window(for: weekday).durationInMinutes
        }
        return effectiveMax
    }

    /// Check if limits are effectively "no limit" (all at max)
    private var isNoLimit: Bool {
        if useAdvancedTimeWindows, let windows = dailyTimeWindows {
            // Check if all days are at their max
            for weekday in 1...7 {
                let max = windows.window(for: weekday).durationInMinutes
                if dailyLimits.limit(for: weekday) < max {
                    return false
                }
            }
            return true
        } else {
            return dailyLimits.weekdayLimit >= effectiveMax && dailyLimits.weekendLimit >= effectiveMax
        }
    }

    init(
        dailyLimits: Binding<DailyLimits>,
        useAdvancedConfig: Binding<Bool>,
        maxAllowedMinutes: Int? = nil,
        dailyTimeWindows: DailyTimeWindows? = nil,
        useAdvancedTimeWindows: Bool = false
    ) {
        self._dailyLimits = dailyLimits
        self._useAdvancedConfig = useAdvancedConfig
        self.maxAllowedMinutes = maxAllowedMinutes
        self.dailyTimeWindows = dailyTimeWindows
        self.useAdvancedTimeWindows = useAdvancedTimeWindows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Limits")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Text("How much time per day?")
                    .font(.system(size: 13))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }

            // Mode selector: No limit / Weekday/Weekend / Per-day
            HStack(spacing: 0) {
                modeButton(title: "No limit", isSelected: isNoLimit && !useAdvancedConfig) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        setNoLimit()
                        useAdvancedConfig = false
                    }
                }

                modeButton(title: "Weekday/Weekend", isSelected: !isNoLimit && !useAdvancedConfig) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // If coming from no limit, set reasonable defaults
                        if isNoLimit {
                            setDefaultLimits()
                        }
                        useAdvancedConfig = false
                    }
                }

                modeButton(title: "Per-day", isSelected: useAdvancedConfig) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // If coming from no limit, set reasonable defaults
                        if isNoLimit && !useAdvancedConfig {
                            setDefaultLimits()
                        }
                        useAdvancedConfig = true
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ChallengeBuilderTheme.inputBackground)
            )

            // Show pickers when not "No limit"
            if !isNoLimit || useAdvancedConfig {
                if useAdvancedConfig {
                    advancedPicker
                } else {
                    simplePicker
                }
            }
        }
        // Auto-cap daily limits when allowed hours duration decreases below current limits
        // Note: We only cap when maxAllowedMinutes changes in simple mode
        // For advanced mode (per-day), capping is done when user toggles to Advanced in Daily Limits
        .onChange(of: maxAllowedMinutes) { _ in
            if !useAdvancedTimeWindows {
                capLimitsToMax()
            }
        }
    }

    // MARK: - Mode Button

    private func modeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : ChallengeBuilderTheme.mutedText)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AppTheme.vibrantTeal : Color.clear)
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Limit Helpers

    private func setNoLimit() {
        if useAdvancedTimeWindows, let windows = dailyTimeWindows {
            dailyLimits = DailyLimits(
                mon: windows.monday.durationInMinutes,
                tue: windows.tuesday.durationInMinutes,
                wed: windows.wednesday.durationInMinutes,
                thu: windows.thursday.durationInMinutes,
                fri: windows.friday.durationInMinutes,
                sat: windows.saturday.durationInMinutes,
                sun: windows.sunday.durationInMinutes
            )
        } else {
            dailyLimits = DailyLimits(weekdayMinutes: effectiveMax, weekendMinutes: effectiveMax)
        }
    }

    private func setDefaultLimits() {
        // Set reasonable default: 1 hour weekdays, 2 hours weekends (or max if lower)
        let weekdayDefault = min(60, effectiveMax(for: 2))
        let weekendDefault = min(120, effectiveMax(for: 7))
        dailyLimits = DailyLimits(weekdayMinutes: weekdayDefault, weekendMinutes: weekendDefault)
    }

    /// Cap all limits to their respective max durations
    private func capLimitsToMax() {
        if useAdvancedTimeWindows, let windows = dailyTimeWindows {
            // Per-day capping
            var newLimits = dailyLimits
            for weekday in 1...7 {
                let max = windows.window(for: weekday).durationInMinutes
                let current = dailyLimits.limit(for: weekday)
                if current > max {
                    newLimits.setLimit(max, for: weekday)
                }
            }
            if newLimits != dailyLimits {
                dailyLimits = newLimits
            }
        } else {
            // Simple mode capping
            let max = effectiveMax
            if dailyLimits.weekdayLimit > max || dailyLimits.weekendLimit > max {
                dailyLimits = DailyLimits(
                    weekdayMinutes: min(dailyLimits.weekdayLimit, max),
                    weekendMinutes: min(dailyLimits.weekendLimit, max)
                )
            }
        }
    }

    // MARK: - Simple Picker (Weekday/Weekend)

    private var simplePicker: some View {
        VStack(spacing: 12) {
            // Weekday limit - use Monday's max as representative
            limitRow(
                title: "Weekdays",
                subtitle: "Mon - Fri",
                value: dailyLimits.weekdayLimit,
                maxMinutes: effectiveMax(for: 2), // Monday
                onChange: { newValue in
                    dailyLimits = DailyLimits(weekdayMinutes: newValue, weekendMinutes: dailyLimits.weekendLimit)
                }
            )

            // Weekend limit - use Saturday's max as representative
            limitRow(
                title: "Weekends",
                subtitle: "Sat - Sun",
                value: dailyLimits.weekendLimit,
                maxMinutes: effectiveMax(for: 7), // Saturday
                onChange: { newValue in
                    dailyLimits = DailyLimits(weekdayMinutes: dailyLimits.weekdayLimit, weekendMinutes: newValue)
                }
            )
        }
    }

    // MARK: - Advanced Picker (Per-Day)

    private var advancedPicker: some View {
        VStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                limitRow(
                    title: dayName(for: weekday),
                    subtitle: nil,
                    value: dailyLimits.limit(for: weekday),
                    maxMinutes: effectiveMax(for: weekday),
                    onChange: { newValue in
                        var newLimits = dailyLimits
                        newLimits.setLimit(newValue, for: weekday)
                        dailyLimits = newLimits
                    }
                )
            }
        }
    }

    // MARK: - Limit Row

    private func limitRow(
        title: String,
        subtitle: String?,
        value: Int,
        maxMinutes: Int,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                }
            }
            .frame(minWidth: 80, alignment: .leading)

            Spacer()

            // Wheel picker for duration
            DurationWheelPicker(
                minutes: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                maxMinutes: maxMinutes
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        // Show actual time for full day (23h 59m for 1439, 24h for 1440)
        if minutes >= 1440 {
            return "23h 59m"
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
}
