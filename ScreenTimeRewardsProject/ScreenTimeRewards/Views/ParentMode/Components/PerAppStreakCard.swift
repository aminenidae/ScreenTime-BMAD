import SwiftUI
import ManagedSettings
import FamilyControls

/// Displays per-app streak information in a list format
/// Shows each reward app with streak enabled: App Name | X Days | Y days to go
struct PerAppStreakCard: View {
    let streaks: [PerAppStreakInfo]

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            headerSection

            ForEach(streaks) { streak in
                StreakRowView(streak: streak)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(AppTheme.card(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
            )
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("DAILY STREAKS")
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()
        }
    }
}

// MARK: - Streak Row View

private struct StreakRowView: View {
    let streak: PerAppStreakInfo

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // App icon - use token-based Label for local context, CachedAppIcon for remote
            if let token = streak.token {
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.35)
                        .frame(width: 36, height: 36)
                }
            } else {
                CachedAppIcon(
                    iconURL: streak.iconURL,
                    identifier: streak.appLogicalID,
                    size: 36,
                    fallbackSymbol: "gamecontroller.fill"
                )
            }

            // App name - use token-based Label for local context, Text for remote
            if let token = streak.token {
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } else {
                Text(streak.appName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            // Streak count with flame
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundColor(streak.isAtRisk ? .orange : AppTheme.sunnyYellow)

                Text("\(streak.currentStreak)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("days")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            // Days to next milestone
            Text("\(streak.daysToNextMilestone) to go")
                .font(.caption)
                .foregroundColor(AppTheme.vibrantTeal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.background(for: colorScheme).opacity(0.5))
        )
    }
}

// MARK: - Preview

#Preview("Per-App Streaks") {
    VStack {
        PerAppStreakCard(streaks: [
            PerAppStreakInfo(
                appLogicalID: "1",
                appName: "YouTube",
                iconURL: nil,
                token: nil,
                currentStreak: 5,
                daysToNextMilestone: 2,
                isAtRisk: false
            ),
            PerAppStreakInfo(
                appLogicalID: "2",
                appName: "Roblox",
                iconURL: nil,
                token: nil,
                currentStreak: 3,
                daysToNextMilestone: 4,
                isAtRisk: true
            ),
            PerAppStreakInfo(
                appLogicalID: "3",
                appName: "Minecraft",
                iconURL: nil,
                token: nil,
                currentStreak: 12,
                daysToNextMilestone: 2,
                isAtRisk: false
            )
        ])
    }
    .padding()
    .background(AppTheme.background(for: .light))
}

#Preview("Empty State") {
    PerAppStreakCard(streaks: [])
        .padding()
        .background(AppTheme.background(for: .light))
}
