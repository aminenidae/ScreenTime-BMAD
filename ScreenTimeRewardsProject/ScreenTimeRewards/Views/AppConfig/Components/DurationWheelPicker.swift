import SwiftUI

/// A wheel-based duration picker for hours and minutes
struct DurationWheelPicker: View {
    @Binding var minutes: Int
    let maxMinutes: Int

    @State private var selectedHours: Int
    @State private var selectedMinutes: Int
    @State private var isPresented: Bool = false

    private var maxHours: Int {
        maxMinutes / 60
    }

    private var availableHours: [Int] {
        Array(0...maxHours)
    }

    private var availableMinutes: [Int] {
        // 5-minute increments
        let allMinutes = stride(from: 0, to: 60, by: 5).map { $0 }

        // If at max hours, limit the minutes
        if selectedHours >= maxHours {
            let remainingMinutes = maxMinutes % 60
            return allMinutes.filter { $0 <= remainingMinutes }
        }
        return allMinutes
    }

    init(minutes: Binding<Int>, maxMinutes: Int) {
        self._minutes = minutes
        self.maxMinutes = maxMinutes

        let hours = minutes.wrappedValue / 60
        let mins = (minutes.wrappedValue % 60 / 5) * 5 // Round to nearest 5
        _selectedHours = State(initialValue: hours)
        _selectedMinutes = State(initialValue: mins)
    }

    var body: some View {
        Button(action: { isPresented = true }) {
            HStack(spacing: 4) {
                Text(formatDuration(minutes))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ChallengeBuilderTheme.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.vibrantTeal.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            durationPickerSheet
        }
    }

    private var durationPickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Current selection display
                Text(formatDuration(selectedHours * 60 + selectedMinutes))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .padding(.top, 20)

                Text("per day")
                    .font(.system(size: 14))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
                    .padding(.bottom, 20)

                // Wheel pickers
                HStack(spacing: 0) {
                    // Hours picker
                    Picker("Hours", selection: $selectedHours) {
                        ForEach(availableHours, id: \.self) { hour in
                            Text("\(hour)h")
                                .tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    .clipped()
                    .onChange(of: selectedHours) { newHours in
                        // Adjust minutes if at max hours
                        if newHours >= maxHours {
                            let maxMins = maxMinutes % 60
                            if selectedMinutes > maxMins {
                                selectedMinutes = (maxMins / 5) * 5
                            }
                        }
                    }

                    // Minutes picker
                    Picker("Minutes", selection: $selectedMinutes) {
                        ForEach(availableMinutes, id: \.self) { minute in
                            Text("\(minute)m")
                                .tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    .clipped()
                }
                .padding(.horizontal, 40)

                // Quick presets
                quickPresets
                    .padding(.top, 20)

                Spacer()
            }
            .background(ChallengeBuilderTheme.background.ignoresSafeArea())
            .navigationTitle("Set Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Reset to original
                        selectedHours = minutes / 60
                        selectedMinutes = (minutes % 60 / 5) * 5
                        isPresented = false
                    }
                    .foregroundColor(AppTheme.playfulCoral)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        minutes = selectedHours * 60 + selectedMinutes
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var quickPresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick select")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if maxMinutes >= 15 {
                        presetButton("15m", hours: 0, mins: 15)
                    }
                    if maxMinutes >= 30 {
                        presetButton("30m", hours: 0, mins: 30)
                    }
                    if maxMinutes >= 60 {
                        presetButton("1h", hours: 1, mins: 0)
                    }
                    if maxMinutes >= 90 {
                        presetButton("1h 30m", hours: 1, mins: 30)
                    }
                    if maxMinutes >= 120 {
                        presetButton("2h", hours: 2, mins: 0)
                    }
                    if maxMinutes >= 180 {
                        presetButton("3h", hours: 3, mins: 0)
                    }
                    if maxMinutes >= 240 {
                        presetButton("4h", hours: 4, mins: 0)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func presetButton(_ title: String, hours: Int, mins: Int) -> some View {
        let isSelected = selectedHours == hours && selectedMinutes == mins

        return Button(action: {
            selectedHours = hours
            selectedMinutes = mins
        }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : ChallengeBuilderTheme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AppTheme.vibrantTeal : ChallengeBuilderTheme.inputBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ mins: Int) -> String {
        if mins >= 1440 {
            return "23h 59m"
        }
        let hours = mins / 60
        let minutes = mins % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }
}
