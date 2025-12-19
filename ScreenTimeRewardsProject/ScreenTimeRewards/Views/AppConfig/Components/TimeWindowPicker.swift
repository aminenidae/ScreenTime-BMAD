import SwiftUI

/// Custom toggle style with teal (OFF) and coral (ON) colors
struct TealCoralToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? AppTheme.playfulCoral : AppTheme.vibrantTeal)
                .frame(width: 50, height: 30)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}

/// A picker for selecting allowed time windows (simple or per-day)
struct TimeWindowPicker: View {
    @Binding var timeWindow: AllowedTimeWindow          // Simple mode: same for all days
    @Binding var dailyTimeWindows: DailyTimeWindows     // Advanced mode: per-day
    @Binding var useAdvancedConfig: Bool                // false = simple, true = per-day
    @Binding var isFullDay: Bool                        // Toggle for "Available all day"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header (no toggle)
            VStack(alignment: .leading, spacing: 4) {
                Text("ALLOWED HOURS")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Text("WHEN CAN THIS APP BE USED?")
                    .font(.system(size: 13))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }

            // Mode selector: All day / Same every day / Per-day
            HStack(spacing: 0) {
                modeButton(title: "ALL DAY", isSelected: isFullDay) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFullDay = true
                        useAdvancedConfig = false
                    }
                }

                modeButton(title: "SAME EVERY DAY", isSelected: !isFullDay && !useAdvancedConfig) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFullDay = false
                        useAdvancedConfig = false
                    }
                }

                modeButton(title: "PER-DAY", isSelected: !isFullDay && useAdvancedConfig) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFullDay = false
                        useAdvancedConfig = true
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ChallengeBuilderTheme.inputBackground)
            )

            // Time pickers (only shown when not full day)
            if !isFullDay {
                if useAdvancedConfig {
                    advancedPicker
                } else {
                    simplePicker
                }
            }
        }
        .onChange(of: isFullDay) { newValue in
            if newValue {
                timeWindow = .fullDay
                dailyTimeWindows = .allFullDay
            }
            // When toggling OFF full day, the current timeWindow value is preserved
            // and the inline Bindings in simplePicker will display it correctly
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

    // MARK: - Simple Picker (same for all days)

    private var simplePicker: some View {
        VStack(spacing: 12) {
            // Start time - use inline Binding to read/write directly from timeWindow
            HStack {
                Text("FROM")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(width: 50, alignment: .leading)

                DatePicker(
                    "",
                    selection: Binding(
                        get: {
                            Self.dateFrom(hour: timeWindow.startHour, minute: timeWindow.startMinute)
                        },
                        set: { newDate in
                            let cal = Calendar.current
                            timeWindow = AllowedTimeWindow(
                                startHour: cal.component(.hour, from: newDate),
                                startMinute: cal.component(.minute, from: newDate),
                                endHour: timeWindow.endHour,
                                endMinute: timeWindow.endMinute
                            )
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 13))
            }

            // End time - use inline Binding to read/write directly from timeWindow
            HStack {
                Text("UNTIL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(width: 50, alignment: .leading)

                DatePicker(
                    "",
                    selection: Binding(
                        get: {
                            Self.dateFrom(hour: timeWindow.endHour, minute: timeWindow.endMinute)
                        },
                        set: { newDate in
                            let cal = Calendar.current
                            timeWindow = AllowedTimeWindow(
                                startHour: timeWindow.startHour,
                                startMinute: timeWindow.startMinute,
                                endHour: cal.component(.hour, from: newDate),
                                endMinute: cal.component(.minute, from: newDate)
                            )
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 13))
            }

            // Warning if end is before start
            if !isValidTimeRange(timeWindow) {
                timeWarning
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    // MARK: - Advanced Picker (per-day)

    private var advancedPicker: some View {
        VStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                dayRow(for: weekday)
            }
        }
    }

    private func dayRow(for weekday: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(dayName(for: weekday))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                // Start time picker - read fresh from dailyTimeWindows to avoid stale captures
                DatePicker(
                    "",
                    selection: Binding(
                        get: {
                            let w = dailyTimeWindows.window(for: weekday)
                            return Self.dateFrom(hour: w.startHour, minute: w.startMinute)
                        },
                        set: { newDate in
                            let cal = Calendar.current
                            var updatedWindow = dailyTimeWindows.window(for: weekday)
                            updatedWindow.startHour = cal.component(.hour, from: newDate)
                            updatedWindow.startMinute = cal.component(.minute, from: newDate)
                            dailyTimeWindows.setWindow(updatedWindow, for: weekday)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 13))
                .frame(width: 90)

                Text("-")
                    .foregroundColor(ChallengeBuilderTheme.mutedText)

                // End time picker - read fresh from dailyTimeWindows to avoid stale captures
                DatePicker(
                    "",
                    selection: Binding(
                        get: {
                            let w = dailyTimeWindows.window(for: weekday)
                            return Self.dateFrom(hour: w.endHour, minute: w.endMinute)
                        },
                        set: { newDate in
                            let cal = Calendar.current
                            var updatedWindow = dailyTimeWindows.window(for: weekday)
                            updatedWindow.endHour = cal.component(.hour, from: newDate)
                            updatedWindow.endMinute = cal.component(.minute, from: newDate)
                            dailyTimeWindows.setWindow(updatedWindow, for: weekday)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 13))
                .frame(width: 90)
            }

            // Warning if invalid
            if !isValidTimeRange(dailyTimeWindows.window(for: weekday)) {
                HStack {
                    Spacer()
                    timeWarningSmall
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    // MARK: - Helpers

    private var timeWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text("END TIME MUST BE AFTER START TIME")
                .font(.system(size: 12))
        }
        .foregroundColor(.orange)
    }

    private var timeWarningSmall: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text("INVALID RANGE")
                .font(.system(size: 10))
        }
        .foregroundColor(.orange)
    }

    private func isValidTimeRange(_ window: AllowedTimeWindow) -> Bool {
        let startMinutes = window.startHour * 60 + window.startMinute
        let endMinutes = window.endHour * 60 + window.endMinute
        return endMinutes > startMinutes
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
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
}
