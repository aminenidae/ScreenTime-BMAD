import SwiftUI

struct StreakSettingsPicker: View {
    @Binding var streakSettings: AppStreakSettings?
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded: Bool = false

    private let availableMilestones = [7, 14, 30, 60, 90]
    private let bonusOptions = [5, 10, 15, 20, 25]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with toggle
            headerSection

            if isExpanded, let settings = streakSettings {
                Divider()

                // Bonus percentage picker
                bonusSection(settings: settings)

                // Milestones selection
                milestonesSection(settings: settings)
            }
        }
        .padding(16)
        .appCard(colorScheme)
        .onAppear {
            if let settings = streakSettings {
                isExpanded = settings.isEnabled
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("STREAK REWARDS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { streakSettings?.isEnabled ?? false },
                    set: { enabled in
                        if streakSettings == nil {
                            streakSettings = .defaultSettings
                        }
                        streakSettings?.isEnabled = enabled
                        isExpanded = enabled
                    }
                ))
                .tint(AppTheme.vibrantTeal)
            }

            Text("Grant bonus time when daily learning goals are met consistently")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }

    private func bonusSection(settings: AppStreakSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BONUS REWARD")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Picker("Bonus Percentage", selection: Binding(
                get: { settings.bonusPercentage },
                set: { streakSettings?.setBonusPercentage($0) }
            )) {
                ForEach(bonusOptions, id: \.self) { percent in
                    Text("+\(percent)%").tag(percent)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }

    private func milestonesSection(settings: AppStreakSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MILESTONES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            ForEach(availableMilestones, id: \.self) { days in
                Toggle(isOn: Binding(
                    get: { settings.milestones.contains(days) },
                    set: { isSelected in
                        if isSelected {
                            if !(streakSettings?.milestones.contains(days) ?? false) {
                                streakSettings?.milestones.append(days)
                                streakSettings?.milestones.sort()
                            }
                        } else {
                            streakSettings?.milestones.removeAll { $0 == days }
                        }
                    }
                )) {
                    HStack {
                        Text("\(days) Days")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        if settings.earnedMilestones.contains(days) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(AppTheme.sunnyYellow)
                                .font(.caption)
                        }
                    }
                }
                .tint(AppTheme.vibrantTeal)

                if days != availableMilestones.last {
                    Divider()
                }
            }
        }
    }
}
