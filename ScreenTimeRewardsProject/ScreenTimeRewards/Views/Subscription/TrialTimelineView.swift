import SwiftUI

struct TrialTimelineView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                Text("Free Trial")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            VStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)
                Text("DAY 13")
                    .font(.system(size: 10, weight: .bold))
                Text("Reminder")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            VStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Text("DAY 15")
                    .font(.system(size: 10, weight: .bold))
                Text("First Charge")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2, x: 0, y: 1)
        )
    }
}
