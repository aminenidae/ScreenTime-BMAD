import SwiftUI

struct QuickStatsCard: View {
    let daysUsedThisWeek: Int
    let longestSessionMinutes: Int
    let totalEarnedThisMonth: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("FUN STATS")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Stats grid
            VStack(spacing: 12) {
                statRow(icon: "calendar", label: "Used this week", value: "\(daysUsedThisWeek) days")
                statRow(icon: "timer", label: "Longest session", value: "\(longestSessionMinutes) min")
                statRow(icon: "gift", label: "Total earned this month", value: "\(totalEarnedThisMonth) min")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.sunnyYellow)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }
}
