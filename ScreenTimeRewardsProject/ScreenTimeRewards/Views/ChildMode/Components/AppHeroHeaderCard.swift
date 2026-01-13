import SwiftUI
import FamilyControls
import ManagedSettings

struct AppHeroHeaderCard: View {
    let appName: String
    let token: ManagedSettings.ApplicationToken
    let isUnlocked: Bool
    let remainingMinutes: Int
    let totalDailyLimit: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // App icon (44x44)
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.4)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
            }

            // App name (from token, single line)
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            } else {
                Text(appName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            }

            // Status icon only (no text badge)
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 16))
                .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : AppTheme.playfulCoral)

            Spacer()

            // Time remaining (compact)
            Text("\(remainingMinutes) min")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(timeColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.playfulCoral.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var timeColor: Color {
        guard isUnlocked else { return AppTheme.textSecondary(for: colorScheme) }
        guard totalDailyLimit > 0 else { return AppTheme.playfulCoral }
        let percentage = Double(remainingMinutes) / Double(totalDailyLimit)
        if percentage > 0.5 { return AppTheme.vibrantTeal }
        if percentage > 0.2 { return AppTheme.sunnyYellow }
        return AppTheme.playfulCoral
    }
}
