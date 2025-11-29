import SwiftUI

/// A picker for setting daily time limits (weekday/weekend or per-day)
struct DailyLimitsPicker: View {
    @Binding var dailyLimits: DailyLimits
    @Binding var useAdvancedConfig: Bool

    // Range: 0 to 8 hours (480 minutes) in 5-minute increments
    private let minMinutes = 0
    private let maxMinutes = 480
    private let stepSize = 5

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

            // Mode toggle
            HStack {
                Text(useAdvancedConfig ? "Per-day limits" : "Weekday/Weekend")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Spacer()

                Button(action: { useAdvancedConfig.toggle() }) {
                    Text(useAdvancedConfig ? "Simplify" : "Advanced")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }

            if useAdvancedConfig {
                advancedPicker
            } else {
                simplePicker
            }

            // Quick presets
            presetsRow
        }
    }

    // MARK: - Simple Picker (Weekday/Weekend)

    private var simplePicker: some View {
        VStack(spacing: 12) {
            // Weekday limit
            limitRow(
                title: "Weekdays",
                subtitle: "Mon - Fri",
                value: dailyLimits.weekdayLimit,
                onChange: { newValue in
                    dailyLimits = DailyLimits(weekdayMinutes: newValue, weekendMinutes: dailyLimits.weekendLimit)
                }
            )

            // Weekend limit
            limitRow(
                title: "Weekends",
                subtitle: "Sat - Sun",
                value: dailyLimits.weekendLimit,
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

            // Stepper with display
            HStack(spacing: 8) {
                Button(action: {
                    let newValue = max(minMinutes, value - stepSize)
                    onChange(newValue)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(value > minMinutes ? AppTheme.playfulCoral : ChallengeBuilderTheme.mutedText.opacity(0.3))
                }
                .disabled(value <= minMinutes)

                Text(formatMinutes(value))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(minWidth: 60)

                Button(action: {
                    let newValue = min(maxMinutes, value + stepSize)
                    onChange(newValue)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(value < maxMinutes ? AppTheme.vibrantTeal : ChallengeBuilderTheme.mutedText.opacity(0.3))
                }
                .disabled(value >= maxMinutes)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    // MARK: - Presets

    private var presetsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick presets")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            HStack(spacing: 8) {
                presetButton("30m", weekday: 30, weekend: 60)
                presetButton("1h", weekday: 60, weekend: 90)
                presetButton("2h", weekday: 120, weekend: 180)
                presetButton("No limit", weekday: 480, weekend: 480)
            }
        }
    }

    private func presetButton(_ title: String, weekday: Int, weekend: Int) -> some View {
        let isSelected = dailyLimits.weekdayLimit == weekday && dailyLimits.weekendLimit == weekend

        return Button(action: {
            dailyLimits = DailyLimits(weekdayMinutes: weekday, weekendMinutes: weekend)
            useAdvancedConfig = false
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : ChallengeBuilderTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AppTheme.vibrantTeal : ChallengeBuilderTheme.inputBackground)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 480 {
            return "8h+"
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
