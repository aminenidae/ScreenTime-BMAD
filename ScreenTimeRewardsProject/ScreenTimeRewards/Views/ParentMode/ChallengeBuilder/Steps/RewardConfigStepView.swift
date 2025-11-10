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
            bonusSection
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
                subtitle: "Set how much reward time is earned per learning time."
            )

            HStack(spacing: 12) {
                ratioInputField(
                    title: "Learning",
                    value: $learningInput,
                    focus: .learning,
                    onCommit: applyLearningInput
                )

                Text("=")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)

                ratioInputField(
                    title: "Reward",
                    value: $rewardInput,
                    focus: .reward,
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
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

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

    // MARK: - Bonus Section
    private var bonusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bonus Percentage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
                Spacer()
                Text("+\(data.bonusPercentage)%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.primary)
            }

            Slider(
                value: Binding(
                    get: { Double(data.bonusPercentage) },
                    set: { data.setBonusPercentage(Int($0)) }
                ),
                in: Double(ChallengeBuilderData.bonusRange.lowerBound)...Double(ChallengeBuilderData.bonusRange.upperBound),
                step: 1
            )
            .accentColor(ChallengeBuilderTheme.primary)

            Picker("Bonus Percentage", selection: Binding(
                get: { data.bonusPercentage },
                set: { data.setBonusPercentage($0) }
            )) {
                ForEach(bonusOptions, id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Preview Card
    private var previewCard: some View {
        let learningMinutes = previewLearningMinutes
        let baseReward = data.learningToRewardRatio.rewardMinutes(forLearningMinutes: learningMinutes)
        let totalReward = data.learningToRewardRatio.rewardMinutes(forLearningMinutes: learningMinutes, bonusPercentage: data.bonusPercentage)

        return VStack(alignment: .leading, spacing: 12) {
            Text("📊 Reward Calculation")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(ChallengeBuilderTheme.text)

            Text("\(learningMinutes) minutes of learning = \(formattedMinutes(baseReward)) minutes reward")
                .font(.system(size: 15))
                .foregroundColor(ChallengeBuilderTheme.text)

            Text("+\(data.bonusPercentage)% bonus = \(formattedMinutes(totalReward)) total reward minutes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ChallengeBuilderTheme.primary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(ChallengeBuilderTheme.inputBackground.opacity(0.8))
        )
    }

    private var previewLearningMinutes: Int {
        max(30, data.activeGoalValue)
    }

    private func formattedMinutes(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ChallengeBuilderTheme.text)
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
