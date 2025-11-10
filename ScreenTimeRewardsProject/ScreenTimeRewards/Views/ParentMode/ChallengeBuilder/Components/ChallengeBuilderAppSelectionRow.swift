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
                // Checkmark on the left
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(ChallengeBuilderTheme.primary)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 24))
                        .foregroundColor(ChallengeBuilderTheme.border.opacity(0.5))
                }

                iconView

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(height: 88)
            .frame(maxWidth: 600)
            .background(ChallengeBuilderTheme.surface)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var iconView: some View {
        if #available(iOS 15.2, *) {
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(2.4)
                .frame(width: 64, height: 64)
                .background(Color.clear)
                .cornerRadius(14)
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 28))
                        .foregroundColor(.gray)
                )
        }
    }
}
