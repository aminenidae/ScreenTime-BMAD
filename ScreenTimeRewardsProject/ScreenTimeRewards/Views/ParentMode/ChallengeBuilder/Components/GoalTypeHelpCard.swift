import SwiftUI

struct GoalTypeHelpCard: View {
    struct Content {
        let emoji: String
        let title: String
        let subtitle: String
        let example: String
    }

    let content: Content
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text(content.emoji)
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(content.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ChallengeBuilderTheme.text)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ChallengeBuilderTheme.primary)
                        }
                    }

                    Text(content.subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)

                    Text(content.example)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ChallengeBuilderTheme.inputBackground.opacity(0.8))
                        )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? ChallengeBuilderTheme.primary.opacity(0.08) : ChallengeBuilderTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? ChallengeBuilderTheme.primary : ChallengeBuilderTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
