import SwiftUI

struct RewardConfigStepView: View {
    @Binding var data: ChallengeBuilderData
    @FocusState private var focusedField: Field?
    @State private var learningInput: String = ""
    @State private var rewardInput: String = ""

    private enum Field {
        case learning
        case reward
    }

    private let bonusOptions = [0, 10, 20, 30, 40, 50]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ratioSection
            presetButtons
            streakBonusSection
            previewCard
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
        )
        .onAppear(perform: syncInputsWithData)
        .onChange(of: data.learningToRewardRatio) { _ in
            syncInputsWithData()
        }
    }

    // MARK: - Ratio Section
    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Learning to Reward Ratio",
                subtitle: "Set how much reward time is earned per learning time.",
                icon: "scale.3d",
                color: AppTheme.playfulCoral
            )

            HStack(spacing: 12) {
                ratioInputField(
                    title: "Learning",
                    value: $learningInput,
                    focus: .learning,
                    color: AppTheme.vibrantTeal,
                    onCommit: applyLearningInput
                )

                Text("=")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)

                ratioInputField(
                    title: "Reward",
                    value: $rewardInput,
                    focus: .reward,
                    color: AppTheme.playfulCoral,
                    onCommit: applyRewardInput
                )
            }

            Text("Keep the learning number above zero. Reward minutes can be lower to encourage effort.")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
    }

    private func ratioInputField(
        title: String,
        value: Binding<String>,
        focus: Field,
        color: Color,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }

            TextField("0", text: value)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: focus)
                .padding(14)
                .background(ChallengeBuilderTheme.inputBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ChallengeBuilderTheme.border, lineWidth: 1)
                )
                .onChange(of: value.wrappedValue) { _ in
                    onCommit()
                }
                .overlay(
                    Text("min")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                        .padding(.trailing, 12),
                    alignment: .trailing
                )
        }
    }

    private func applyLearningInput() {
        let filtered = filteredInput(from: learningInput)
        if filtered != learningInput {
            learningInput = filtered
        }

        if let value = Int(filtered), value > 0 {
            data.setLearningRatioMinutes(value)
        }
    }

    private func applyRewardInput() {
        let filtered = filteredInput(from: rewardInput)
        if filtered != rewardInput {
            rewardInput = filtered
        }

        if let value = Int(filtered) {
            data.setRewardRatioMinutes(value)
        }
    }

    private func filteredInput(from string: String) -> String {
        let digitsOnly = string.filter { $0.isNumber }
        let trimmed = digitsOnly.prefix(4)
        return String(trimmed)
    }

    // MARK: - Presets
    private var presetButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Ratios")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ChallengeBuilderTheme.text)

            VStack(spacing: 8) {
                ratioRow(for: standardPresetRatios)
                ratioRow(for: reversePresetRatios)
            }
        }
    }

    private func ratioRow(for ratios: [LearningToRewardRatio]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(ratios.enumerated()), id: \.offset) { _, preset in
                Button {
                    data.applyRatioPreset(preset)
                } label: {
                    Text(ratioLabel(for: preset))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isCurrentPreset(preset) ? .white : ChallengeBuilderTheme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isCurrentPreset(preset) ? ChallengeBuilderTheme.primary : ChallengeBuilderTheme.inputBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var standardPresetRatios: [LearningToRewardRatio] {
        LearningToRewardRatio.presetRatios
    }

    private var reversePresetRatios: [LearningToRewardRatio] {
        [
            LearningToRewardRatio(learningMinutes: 30, rewardMinutes: 30), // 1:1
            LearningToRewardRatio(learningMinutes: 30, rewardMinutes: 60), // 1:2
            LearningToRewardRatio(learningMinutes: 30, rewardMinutes: 90), // 1:3
            LearningToRewardRatio(learningMinutes: 30, rewardMinutes: 120) // 1:4
        ]
    }

    private func ratioLabel(for ratio: LearningToRewardRatio) -> String {
        let gcdValue = gcd(ratio.learningMinutes, ratio.rewardMinutes)
        let left = ratio.learningMinutes / gcdValue
        let right = ratio.rewardMinutes / gcdValue
        return "\(left):\(right)"
    }

    private func isCurrentPreset(_ preset: LearningToRewardRatio) -> Bool {
        preset == data.learningToRewardRatio
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let temp = y
            y = x % temp
            x = temp
        }
        return max(1, x)
    }

    // MARK: - Streak Bonus Section
    private var streakBonusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Streak Bonus (Optional)",
                subtitle: "Reward consistency by granting bonus points for completing daily goals consecutively.",
                icon: "flame.fill",
                color: AppTheme.sunnyYellow
            )

            Toggle(isOn: $data.streakBonus.enabled) {
                HStack(spacing: 8) {
                    Image(systemName: data.streakBonus.enabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(data.streakBonus.enabled ? AppTheme.vibrantTeal : ChallengeBuilderTheme.mutedText)

                    Text("Enable Streak Bonus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }
            }
            .toggleStyle(.switch)
            .tint(AppTheme.vibrantTeal)

            if data.streakBonus.enabled {
                VStack(spacing: 16) {
                    // Streak Target Days
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.playfulCoral)

                                Text("Streak Target")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(ChallengeBuilderTheme.text)
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Text("\(data.streakBonus.targetDays)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppTheme.playfulCoral)

                                Text("days")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChallengeBuilderTheme.mutedText)
                            }
                        }

                        Slider(
                            value: Binding(
                                get: { Double(data.streakBonus.targetDays) },
                                set: { data.setStreakTargetDays(Int($0)) }
                            ),
                            in: Double(ChallengeBuilderData.StreakBonus.targetDaysRange.lowerBound)...Double(ChallengeBuilderData.StreakBonus.targetDaysRange.upperBound),
                            step: 1
                        )
                        .accentColor(ChallengeBuilderTheme.primary)

                        Text("Complete the daily goal for this many consecutive days to earn the bonus.")
                            .font(.system(size: 13))
                            .foregroundColor(ChallengeBuilderTheme.mutedText)
                    }

                    // Bonus Percentage
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.sunnyYellow)

                                Text("Bonus Points")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(ChallengeBuilderTheme.text)
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Text("+\(data.streakBonus.bonusPercentage)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppTheme.sunnyYellow)

                                Text("%")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChallengeBuilderTheme.mutedText)
                            }
                        }

                        Slider(
                            value: Binding(
                                get: { Double(data.streakBonus.bonusPercentage) },
                                set: { data.setStreakBonusPercentage(Int($0)) }
                            ),
                            in: Double(ChallengeBuilderData.StreakBonus.bonusRange.lowerBound)...Double(ChallengeBuilderData.StreakBonus.bonusRange.upperBound),
                            step: 5
                        )
                        .accentColor(ChallengeBuilderTheme.primary)

                        Text("Additional points earned when streak target is reached.")
                            .font(.system(size: 13))
                            .foregroundColor(ChallengeBuilderTheme.mutedText)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.sunnyYellow.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Preview Card
    private var previewCard: some View {
        let learningMinutes = previewLearningMinutes
        let baseReward = data.learningToRewardRatio.rewardMinutes(forLearningMinutes: learningMinutes)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Reward Calculation")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            HStack(spacing: 4) {
                Text("\(learningMinutes)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("min learning =")
                    .font(.system(size: 15))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Text("\(formattedMinutes(baseReward))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("min reward")
                    .font(.system(size: 15))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            if data.streakBonus.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.sunnyYellow)

                        Text("Streak Bonus:")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ChallengeBuilderTheme.text)

                        Text("Complete \(data.streakBonus.targetDays) days → +\(data.streakBonus.bonusPercentage)% points")
                            .font(.system(size: 14))
                            .foregroundColor(ChallengeBuilderTheme.mutedText)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.vibrantTeal.opacity(0.05),
                            AppTheme.playfulCoral.opacity(0.05),
                            AppTheme.sunnyYellow.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(AppTheme.vibrantTeal.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var previewLearningMinutes: Int {
        max(30, data.dailyMinutesGoal)
    }

    private func formattedMinutes(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private func sectionHeader(title: String, subtitle: String, icon: String, color: Color) -> some View {
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

    private func syncInputsWithData() {
        let learning = String(data.learningToRewardRatio.learningMinutes)
        if learningInput != learning {
            learningInput = learning
        }

        let reward = String(data.learningToRewardRatio.rewardMinutes)
        if rewardInput != reward {
            rewardInput = reward
        }
    }
}
