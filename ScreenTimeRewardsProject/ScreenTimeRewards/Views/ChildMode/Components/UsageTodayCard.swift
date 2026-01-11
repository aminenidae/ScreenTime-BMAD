import SwiftUI

struct UsageTodayCard: View {
    let usedMinutes: Int
    let previousDayUsage: Int?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("TODAY'S USAGE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Big number
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(usedMinutes)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("MINUTES USED")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            // Comparison to yesterday
            if let previousDayUsage = previousDayUsage {
                comparisonRow(current: usedMinutes, previous: previousDayUsage)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private func comparisonRow(current: Int, previous: Int) -> some View {
        let difference = current - previous
        let isMore = difference > 0

        return HStack(spacing: 6) {
            Image(systemName: isMore ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(isMore ? AppTheme.playfulCoral : AppTheme.brandedText(for: colorScheme))

            Text("\(abs(difference)) minutes \(isMore ? "more" : "less") than yesterday")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((isMore ? AppTheme.playfulCoral : AppTheme.vibrantTeal).opacity(0.08))
        )
    }
}
