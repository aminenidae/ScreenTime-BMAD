import SwiftUI

/// A picker for selecting an allowed time window (start and end times)
struct TimeWindowPicker: View {
    @Binding var timeWindow: AllowedTimeWindow
    @Binding var isFullDay: Bool

    @State private var startTime: Date
    @State private var endTime: Date

    init(timeWindow: Binding<AllowedTimeWindow>, isFullDay: Binding<Bool>) {
        self._timeWindow = timeWindow
        self._isFullDay = isFullDay

        // Initialize state from binding
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

                Text(isFullDay ? "Available all day" : "Custom hours")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isFullDay ? AppTheme.vibrantTeal : ChallengeBuilderTheme.text)
            }

            // Time pickers (only shown when not full day)
            if !isFullDay {
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
                        .onChange(of: startTime) { newValue in
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
                        .onChange(of: endTime) { newValue in
                            updateTimeWindow()
                        }
                    }

                    // Warning if end is before start
                    if !isValidTimeRange {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text("End time must be after start time")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(ChallengeBuilderTheme.inputBackground)
                )
            }
        }
        .onChange(of: isFullDay) { newValue in
            if newValue {
                timeWindow = .fullDay
            } else {
                updateTimeWindow()
            }
        }
    }

    private var isValidTimeRange: Bool {
        let startMinutes = timeWindow.startHour * 60 + timeWindow.startMinute
        let endMinutes = timeWindow.endHour * 60 + timeWindow.endMinute
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
}
