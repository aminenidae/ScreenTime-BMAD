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
        VStack(spacing: 16) {
            // Large app icon
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(2.5)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }

            // App name
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(size: 24, weight: .bold))
                    //.tracking(1.5) // Tracking modifier not directly available on Label, would need to wrap or inspect
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
            } else {
                Text(appName.uppercased())
                    .font(.system(size: 24, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
            }

            // Status badge
            statusBadge

            // Time remaining display
            timeRemainingDisplay
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.playfulCoral.opacity(0.2), lineWidth: 2)
                )
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 14))
            Text(isUnlocked ? "UNLOCKED" : "LOCKED")
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
        }
        .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : AppTheme.playfulCoral)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill((isUnlocked ? AppTheme.vibrantTeal : AppTheme.playfulCoral).opacity(0.15))
        )
    }

    private var timeRemainingDisplay: some View {
        VStack(spacing: 4) {
            Text("\(remainingMinutes)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(timeColor)

            Text("MINUTES LEFT TODAY")
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }

    private var timeColor: Color {
        guard totalDailyLimit > 0 else { return AppTheme.playfulCoral }
        let percentage = Double(remainingMinutes) / Double(totalDailyLimit)
        if percentage > 0.5 { return AppTheme.vibrantTeal }
        if percentage > 0.2 { return AppTheme.sunnyYellow }
        return AppTheme.playfulCoral
    }
}
