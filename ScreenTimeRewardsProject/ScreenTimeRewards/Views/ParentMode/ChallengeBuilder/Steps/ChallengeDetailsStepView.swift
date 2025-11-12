import SwiftUI

struct ChallengeDetailsStepView: View {
    @Binding var data: ChallengeBuilderData
    @FocusState private var focusedField: Field?

    enum Field {
        case title
        case description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Challenge Basics", subtitle: "Give your challenge a clear name and optional description.", icon: "pencil.circle.fill", color: AppTheme.sunnyYellow)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Challenge Name")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.text)

                    TextField("e.g., Weekday Reading Goal", text: $data.title)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                        .padding(14)
                        .background(ChallengeBuilderTheme.inputBackground)
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.text)

                    TextField("Add details to motivate your learner…", text: $data.description, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(2...4)
                        .padding(14)
                        .background(ChallengeBuilderTheme.inputBackground)
                        .cornerRadius(12)
                }
            }

            Divider().background(ChallengeBuilderTheme.border)

            sectionHeader("Daily Goal", subtitle: "Set the learning minutes to complete each day.", icon: "target", color: AppTheme.vibrantTeal)

            goalValueControl()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
        )
    }

    @ViewBuilder
    private func goalValueControl() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("Daily Minutes Goal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(data.dailyMinutesGoal)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.vibrantTeal)

                    Text("min/day")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(data.dailyMinutesGoal) },
                    set: { newValue in
                        data.setDailyMinutesGoal(Int(newValue))
                    }
                ),
                in: Double(ChallengeBuilderData.dailyMinutesRange.lowerBound)...Double(ChallengeBuilderData.dailyMinutesRange.upperBound),
                step: 5.0
            )
            .accentColor(ChallengeBuilderTheme.primary)

            HStack {
                Text("\(ChallengeBuilderData.dailyMinutesRange.lowerBound) min")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
                Spacer()
                Text("\(ChallengeBuilderData.dailyMinutesRange.upperBound) min")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }

            Text("This is the amount of learning time your child needs to complete each day.")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(ChallengeBuilderTheme.inputBackground.opacity(0.5))
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
