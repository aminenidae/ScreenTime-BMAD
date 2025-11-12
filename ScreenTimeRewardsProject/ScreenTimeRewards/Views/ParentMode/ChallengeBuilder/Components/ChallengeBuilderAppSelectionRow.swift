import SwiftUI
import FamilyControls
import ManagedSettings

struct ChallengeBuilderAppSelectionRow: View {
    let token: ManagedSettings.ApplicationToken
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                iconView

                // App name
                VStack(alignment: .leading, spacing: 4) {
                    if #available(iOS 15.2, *) {
                        Label(token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChallengeBuilderTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(title.isEmpty ? "App" : title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChallengeBuilderTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(height: 88)
            .frame(maxWidth: 600)
            .background(isSelected ? ChallengeBuilderTheme.primary.opacity(0.1) : ChallengeBuilderTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? ChallengeBuilderTheme.primary : ChallengeBuilderTheme.border.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var iconView: some View {
        if #available(iOS 15.2, *) {
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.35)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                )
        }
    }
}
