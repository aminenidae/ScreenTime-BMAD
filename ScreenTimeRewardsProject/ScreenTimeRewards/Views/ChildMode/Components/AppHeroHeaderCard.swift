import SwiftUI
import FamilyControls
import ManagedSettings

struct AppHeroHeaderCard: View {
    let appName: String
    let token: ManagedSettings.ApplicationToken
    let isUnlocked: Bool
    let remainingMinutes: Int
    let totalDailyLimit: Int
    /// Today's used time. Surfaced when there's no allocated session — otherwise
    /// the right-side label shows "0 min" even when the child has been using the app.
    var usedMinutes: Int = 0
    /// True when there's a real timed session (manual unlock with allocation).
    /// When false, we display `usedMinutes` instead of `remainingMinutes`.
    var hasActiveSession: Bool = true
    @Environment(\.colorScheme) var colorScheme

    private var rightLabelValue: Int {
        hasActiveSession ? remainingMinutes : usedMinutes
    }

    private var rightLabelSuffix: String {
        hasActiveSession ? "min" : "min used"
    }

    private var showRightLabel: Bool {
        hasActiveSession || usedMinutes > 0
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon (64x64)
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(2.0)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28))
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

            // Right-side label: remaining time during an active session, otherwise
            // today's used time. "0 min" was misleading on goal-unlocked-no-session.
            if showRightLabel {
                Text("\(rightLabelValue) \(rightLabelSuffix)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(timeColor)
            }
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
        // No active session → right label is "X min used" — neutral color.
        guard hasActiveSession else { return AppTheme.textPrimary(for: colorScheme) }
        guard totalDailyLimit > 0 else { return AppTheme.playfulCoral }
        let percentage = Double(remainingMinutes) / Double(totalDailyLimit)
        if percentage > 0.5 { return AppTheme.vibrantTeal }
        if percentage > 0.2 { return AppTheme.sunnyYellow }
        return AppTheme.playfulCoral
    }
}
