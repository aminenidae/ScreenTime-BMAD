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
            sectionHeader("Challenge Basics", subtitle: "Give your challenge a clear name and optional description.")

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

            sectionHeader("Goal Type", subtitle: "Choose what success looks like. Tap for details.")

            VStack(spacing: 12) {
                ForEach(goalTypeDescriptors, id: \.type) { descriptor in
                    GoalTypeHelpCard(
                        content: GoalTypeHelpCard.Content(
                            emoji: descriptor.emoji,
                            title: descriptor.title,
                            subtitle: descriptor.subtitle,
                            example: descriptor.example
                        ),
                        isSelected: data.goalType == descriptor.type,
                        onTap: {
                            data.goalType = descriptor.type
                        }
                    )
                }
            }

            Divider().background(ChallengeBuilderTheme.border)

            sectionHeader("Goal Target", subtitle: "Set the amount to complete for the selected goal type.")

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
        let configuration = data.activeGoalConfiguration
        let value = data.activeGoalValue

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Target")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
                Spacer()
                Text("\(value) \(configuration.unit)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.primary)
            }

            if data.goalType == .streak {
                Stepper(
                    value: Binding(
                        get: { data.activeGoalValue },
                        set: { data.setActiveGoalValue($0) }
                    ),
                    in: configuration.range,
                    step: configuration.step
                ) {
                    Text("Consecutive days")
                        .font(.system(size: 15))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ChallengeBuilderTheme.inputBackground)
                )
            } else {
                Slider(
                    value: Binding(
                        get: { Double(data.activeGoalValue) },
                        set: { newValue in
                            data.setActiveGoalValue(Int(newValue))
                        }
                    ),
                    in: Double(configuration.range.lowerBound)...Double(configuration.range.upperBound),
                    step: Double(configuration.step)
                )
                .accentColor(ChallengeBuilderTheme.primary)

                HStack {
                    Text("\(configuration.range.lowerBound) \(configuration.unit)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                    Spacer()
                    Text("\(configuration.range.upperBound) \(configuration.unit)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)
                }
            }

            Text("Adjust later if needed. This keeps the challenge achievable.")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(ChallengeBuilderTheme.inputBackground.opacity(0.5))
        )
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ChallengeBuilderTheme.text)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
    }

    private struct GoalDescriptor {
        let type: ChallengeGoalType
        let emoji: String
        let title: String
        let subtitle: String
        let example: String
    }

    private var goalTypeDescriptors: [GoalDescriptor] {
        [
            GoalDescriptor(
                type: .dailyMinutes,
                emoji: "📅",
                title: "Daily Minutes",
                subtitle: "Complete a set amount each day.",
                example: "“Read 30 minutes daily.”"
            ),
            GoalDescriptor(
                type: .weeklyMinutes,
                emoji: "📊",
                title: "Weekly Minutes",
                subtitle: "Hit a total minutes target each week.",
                example: "“Learn for 120 minutes this week.”"
            ),
            GoalDescriptor(
                type: .specificApps,
                emoji: "📱",
                title: "Specific Apps",
                subtitle: "Track time in selected learning apps.",
                example: "“Use Duolingo for 20 minutes.”"
            ),
            GoalDescriptor(
                type: .streak,
                emoji: "🔥",
                title: "Streak",
                subtitle: "Keep activity going for consecutive days.",
                example: "“Practice math 7 days in a row.”"
            ),
            GoalDescriptor(
                type: .pointsTarget,
                emoji: "⭐️",
                title: "Points Target",
                subtitle: "Reach a points goal in supported apps.",
                example: "“Earn 500 points this week.”"
            )
        ]
    }
}
