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
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
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
