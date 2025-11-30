import SwiftUI

/// A picker for selecting allowed time windows (simple or per-day)
struct TimeWindowPicker: View {
    @Binding var timeWindow: AllowedTimeWindow          // Simple mode: same for all days
    @Binding var dailyTimeWindows: DailyTimeWindows     // Advanced mode: per-day
    @Binding var useAdvancedConfig: Bool                // false = simple, true = per-day
    @Binding var isFullDay: Bool                        // Toggle for "Available all day"

    @State private var startTime: Date
    @State private var endTime: Date

    init(
        timeWindow: Binding<AllowedTimeWindow>,
        dailyTimeWindows: Binding<DailyTimeWindows>,
        useAdvancedConfig: Binding<Bool>,
        isFullDay: Binding<Bool>
    ) {
        self._timeWindow = timeWindow
        self._dailyTimeWindows = dailyTimeWindows
        self._useAdvancedConfig = useAdvancedConfig
        self._isFullDay = isFullDay

        // Initialize state from simple mode binding
        let window = timeWindow.wrappedValue
        _startTime = State(initialValue: Self.dateFrom(hour: window.startHour, minute: window.startMinute))
        _endTime = State(initialValue: Self.dateFrom(hour: window.endHour, minute: window.endMinute))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allowed Hours")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)

                    Text("When can this app be used?")
                        .font(.system(size: 13))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                }

                Spacer()

                Toggle("", isOn: $isFullDay)
                    .labelsHidden()
                    .tint(AppTheme.vibrantTeal)
            }

            // Full Day label
            HStack {
                Image(systemName: isFullDay ? "clock.fill" : "clock")
                    .foregroundColor(isFullDay ? AppTheme.vibrantTeal : ChallengeBuilderTheme.mutedText)

                Text(isFullDay ? "Available all day" : "This App Will Be Available...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isFullDay ? AppTheme.vibrantTeal : ChallengeBuilderTheme.text)
            }

            // Time pickers (only shown when not full day)
            if !isFullDay {
                // Mode toggle (Simple vs Per-day)
                HStack {
                    Text(useAdvancedConfig ? "Per-day hours" : "Same every day")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.text)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            useAdvancedConfig.toggle()
                            if useAdvancedConfig {
                                // Copy simple mode to all days when switching to advanced
                                dailyTimeWindows = DailyTimeWindows(weekday: timeWindow, weekend: timeWindow)
                            }
                        }
                    }) {
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
            }
        }
        .onChange(of: isFullDay) { newValue in
            if newValue {
                timeWindow = .fullDay
                dailyTimeWindows = .allFullDay
                useAdvancedConfig = false
            } else {
                updateTimeWindow()
            }
        }
    }

    // MARK: - Simple Picker (same for all days)

    private var simplePicker: some View {
        VStack(spacing: 12) {
            // Start time
            HStack {
                Text("From")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(width: 50, alignment: .leading)

                DatePicker(
                    "",
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: startTime) { _ in
                    updateTimeWindow()
                }
            }

            // End time
            HStack {
                Text("Until")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(width: 50, alignment: .leading)

                DatePicker(
                    "",
                    selection: $endTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: endTime) { _ in
                    updateTimeWindow()
                }
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
        let window = dailyTimeWindows.window(for: weekday)

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(dayName(for: weekday))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                // Start time picker
                DatePicker(
                    "",
                    selection: Binding(
                        get: { Self.dateFrom(hour: window.startHour, minute: window.startMinute) },
                        set: { newDate in
                            let cal = Calendar.current
                            var updatedWindow = window
                            updatedWindow.startHour = cal.component(.hour, from: newDate)
                            updatedWindow.startMinute = cal.component(.minute, from: newDate)
                            dailyTimeWindows.setWindow(updatedWindow, for: weekday)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(width: 90)

                Text("-")
                    .foregroundColor(ChallengeBuilderTheme.mutedText)

                // End time picker
                DatePicker(
                    "",
                    selection: Binding(
                        get: { Self.dateFrom(hour: window.endHour, minute: window.endMinute) },
                        set: { newDate in
                            let cal = Calendar.current
                            var updatedWindow = window
                            updatedWindow.endHour = cal.component(.hour, from: newDate)
                            updatedWindow.endMinute = cal.component(.minute, from: newDate)
                            dailyTimeWindows.setWindow(updatedWindow, for: weekday)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(width: 90)
            }

            // Warning if invalid
            if !isValidTimeRange(window) {
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
            Text("End time must be after start time")
                .font(.system(size: 12))
        }
        .foregroundColor(.orange)
    }

    private var timeWarningSmall: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text("Invalid range")
                .font(.system(size: 10))
        }
        .foregroundColor(.orange)
    }

    private func isValidTimeRange(_ window: AllowedTimeWindow) -> Bool {
        let startMinutes = window.startHour * 60 + window.startMinute
        let endMinutes = window.endHour * 60 + window.endMinute
        return endMinutes > startMinutes
    }

    private func updateTimeWindow() {
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: startTime)
        let startMin = calendar.component(.minute, from: startTime)
        let endHour = calendar.component(.hour, from: endTime)
        let endMin = calendar.component(.minute, from: endTime)

        timeWindow = AllowedTimeWindow(
            startHour: startHour,
            startMinute: startMin,
            endHour: endHour,
            endMinute: endMin
        )
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
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
