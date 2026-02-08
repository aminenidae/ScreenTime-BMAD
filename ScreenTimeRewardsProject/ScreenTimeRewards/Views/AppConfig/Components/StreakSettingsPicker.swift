import SwiftUI

struct StreakSettingsPicker: View {
    @Binding var streakSettings: AppStreakSettings?
    var estimatedDailyReward: Int = 0 // Context for percentage calculation
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

                // 1. Streak Cycle (Recurring)
                cycleSection(settings: settings)
                
                Divider()

                // 2. Bonus Type & Value
                bonusSection(settings: settings)
                
                Divider()
                
                // 3. Summary
                summarySection(settings: settings)
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

                Text("Streak Rewards")
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

            Text("Grant bonus time for consistent learning habits")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }
    
    // MARK: - Sections

    private func summarySection(settings: AppStreakSettings) -> some View {
        let days = settings.streakCycleDays
        let value = settings.bonusValue
        
        let message: String
        if settings.bonusType == .fixedMinutes {
            // e.g. 5 min * 7 days = 35 min
            let total = value * days
            message = "Your child will earn \(total) minutes bonus at completion of \(days)-day streak."
        } else {
            // e.g. 10% * 7 days = 70%
            let totalPercent = value * days
            let percentStr = "\(totalPercent)% of daily reward"
            
            if estimatedDailyReward > 0 {
                 let minutes = Int(Double(estimatedDailyReward) * Double(totalPercent) / 100.0)
                 message = "Your child will earn \(minutes) minutes bonus at completion of \(days)-day streak."
            } else {
                 message = "Your child will earn \(percentStr) bonus at completion of \(days)-day streak."
            }
        }

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.vibrantTeal)
                .padding(.top, 2)
            
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(AppTheme.vibrantTeal.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Sections

    private func cycleSection(settings: AppStreakSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streak Cycle")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            
            HStack {
                Text("Reward every")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                
                Spacer()
                
                // Custom Stepper for Days (Min: 3)
                CustomStepper(
                    value: Binding(
                        get: { settings.streakCycleDays },
                        set: { newValue in
                            if var newSettings = streakSettings {
                                newSettings.setStreakCycle(newValue)
                                streakSettings = newSettings
                            }
                        }
                    ),
                    range: 3...365,
                    suffix: "Days"
                )
            }
        }
    }

    private func bonusSection(settings: AppStreakSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bonus Reward")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            // Bonus Type Picker
            Picker("Bonus Type", selection: Binding(
                get: { settings.bonusType },
                set: { newValue in
                    if var newSettings = streakSettings {
                        newSettings.bonusType = newValue
                        streakSettings = newSettings
                    }
                }
            )) {
                ForEach(StreakBonusType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Value Input
            HStack {
                Text("Bonus Amount")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                
                Spacer()
                
                // Custom Stepper for Bonus (Min: 5)
                CustomStepper(
                    value: Binding(
                        get: { settings.bonusValue },
                        set: { newValue in
                            if var newSettings = streakSettings {
                                newSettings.setBonusValue(newValue)
                                streakSettings = newSettings
                            }
                        }
                    ),
                    range: 5...999, // Min 5% or 5 min
                    suffix: settings.bonusType == .percentage ? "%" : "min",
                    prefix: settings.bonusType == .fixedMinutes ? "+" : ""
                )
            }
        }
    }

    // MARK: - Helper Views

    private struct CustomStepper: View {
        @Binding var value: Int
        let range: ClosedRange<Int>
        let suffix: String
        var prefix: String = ""
        @Environment(\.colorScheme) var colorScheme
        
        var body: some View {
            HStack(spacing: 0) {
                // Decrement Button
                Button(action: {
                    if value > range.lowerBound {
                        value -= 1
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .foregroundColor(value > range.lowerBound ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme).opacity(0.3))
                        .background(AppTheme.vibrantTeal.opacity(0.1))
                }
                .disabled(value <= range.lowerBound)
                
                // Value Display
                HStack(spacing: 2) {
                    if !prefix.isEmpty {
                        Text(prefix)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                    
                    Text("\(value)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .frame(minWidth: 20)
                    
                    Text(suffix)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(minWidth: 80)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AppTheme.background(for: colorScheme))
                
                // Increment Button
                Button(action: {
                    if value < range.upperBound {
                        value += 1
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .foregroundColor(value < range.upperBound ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme).opacity(0.3))
                        .background(AppTheme.vibrantTeal.opacity(0.1))
                }
                .disabled(value >= range.upperBound)
            }
            .background(AppTheme.background(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
            )
        }
    }
}
