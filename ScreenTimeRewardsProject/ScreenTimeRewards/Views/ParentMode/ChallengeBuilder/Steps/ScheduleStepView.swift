import SwiftUI

struct ScheduleStepView: View {
    @Binding var schedule: ChallengeBuilderData.Schedule

    private let dayItems: [(Int, String)] = [
        (1, "Mon"),
        (2, "Tue"),
        (3, "Wed"),
        (4, "Thu"),
        (5, "Fri"),
        (6, "Sat"),
        (7, "Sun")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Schedule", subtitle: "Define when this challenge is active.", icon: "calendar.circle.fill", color: AppTheme.vibrantTeal)
            dateRangeSection
            repeatSection
            daySelectionSection
            timeSection
            helperCard
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
        )
    }

    // MARK: - Date Range
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("Date Range")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            DatePicker(
                "Start Date",
                selection: Binding(
                    get: { schedule.startDate },
                    set: { newDate in
                        schedule.startDate = newDate
                        schedule.enforceDateConsistency()
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)

            Toggle(isOn: Binding(
                get: { schedule.hasEndDate },
                set: { newValue in
                    schedule.hasEndDate = newValue
                    schedule.enforceDateConsistency()
                }
            )) {
                Text("Specify End Date")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }
            .toggleStyle(SwitchToggleStyle(tint: ChallengeBuilderTheme.primary))

            if schedule.hasEndDate {
                DatePicker(
                    "End Date",
                    selection: Binding(
                        get: { schedule.endDate ?? schedule.startDate },
                        set: { newDate in
                            schedule.endDate = newDate
                            schedule.enforceDateConsistency()
                        }
                    ),
                    in: schedule.startDate...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
            }
        }
    }

    // MARK: - Repeat Section
    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $schedule.repeatWeekly) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repeat Weekly")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                    Text("Keeps the challenge active on selected days each week.")
                        .font(.system(size: 13))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: ChallengeBuilderTheme.primary))
        }
    }

    // MARK: - Day Selection
    private var daySelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.vibrantTeal)

                    Text("Active Days")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }

                Spacer()

                Button("Clear") {
                    schedule.activeDays.removeAll()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.playfulCoral)
            }

            FlexibleDayGrid(
                items: dayItems,
                selected: schedule.activeDays,
                onToggle: toggleDay
            )

            Text(schedule.activeDays.isEmpty ? "Select at least one day." : "Tap to toggle individual days.")
                .font(.system(size: 13))
                .foregroundColor(schedule.activeDays.isEmpty ? .red : ChallengeBuilderTheme.mutedText)
        }
    }

    private func toggleDay(_ day: Int) {
        if schedule.activeDays.contains(day) {
            schedule.activeDays.remove(day)
        } else {
            schedule.activeDays.insert(day)
        }
    }

    // MARK: - Time Section
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { schedule.isFullDay },
                set: { newValue in
                    schedule.setFullDay(newValue)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Day")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                    Text("Disable to set a custom time window.")
                        .font(.system(size: 13))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: ChallengeBuilderTheme.primary))

            if schedule.usesCustomTimeRange {
                VStack(spacing: 12) {
                    timePicker(title: "Start Time", selection: $schedule.startTime)
                    timePicker(title: "End Time", selection: $schedule.endTime)

                    if schedule.startTime >= schedule.endTime {
                        Text("End time must be after start time.")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private func timePicker(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ChallengeBuilderTheme.text)
            DatePicker("", selection: selection, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
        }
    }

    // MARK: - Helper Card
    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Scheduling Tips")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text("Use Full Day for simple goals. Custom times work best for after-school or evening routines.")
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.sunnyYellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func sectionHeader(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
    }
}

// MARK: - Flexible Day Grid
private struct FlexibleDayGrid: View {
    let items: [(Int, String)]
    let selected: Set<Int>
    let onToggle: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(items, id: \.0) { item in
                Button(action: { onToggle(item.0) }) {
                    Text(item.1)
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(selected.contains(item.0) ? .white : ChallengeBuilderTheme.text)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selected.contains(item.0) ? ChallengeBuilderTheme.primary : ChallengeBuilderTheme.inputBackground)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
