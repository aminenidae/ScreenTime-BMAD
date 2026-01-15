import SwiftUI
import FamilyControls

struct AppDetailHeaderView: View {
    let snapshot: any AppIdentifiable // Now conforms to AppIdentifiable
    let appType: AppType
    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        appType == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.regular) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.8)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            } else {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 24))
                            .foregroundColor(accentColor)
                    )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                // App name
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 18, weight: .bold)) // Standardized with other titles
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .lineLimit(1)
                        .textCase(.uppercase)
                } else {
                    Text(snapshot.displayName) // Use displayName from snapshot
                        .font(.system(size: 18, weight: .bold)) // Standardized with other titles
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .lineLimit(1)
                        .textCase(.uppercase)
                }

                // Category badge
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: appType == .learning ? "book.fill" : "gift.fill")
                        .font(.system(size: 10))

                    Text(appType == .learning ? "LEARNING" : "REWARD")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                }
                .foregroundColor(appType == .learning ? AppTheme.brandedText(for: colorScheme) : accentColor)
                .padding(.horizontal, AppTheme.Spacing.regular)
                .padding(.vertical, AppTheme.Spacing.tiny)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.15))
                )
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.regular)
        .appCard(colorScheme)
    }
}
