import SwiftUI

struct TimeBankVisualizationCard: View {
    let remainingMinutes: Int
    let dailyLimit: Int
    let usedMinutes: Int
    @Environment(\.colorScheme) var colorScheme

    private var percentage: Double {
        guard dailyLimit > 0 else { return 0 }
        return Double(remainingMinutes) / Double(dailyLimit)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ringColor)

                Text("TIME AVAILABLE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 20)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor, ringColor.opacity(0.6)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 140)

                VStack(spacing: 4) {
                    Text("\(remainingMinutes)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(ringColor)

                    Text("of \(dailyLimit) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            // Helper text
            Text("Resets at midnight")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private var ringColor: Color {
        if percentage > 0.5 { return AppTheme.vibrantTeal }
        if percentage > 0.2 { return AppTheme.sunnyYellow }
        return AppTheme.playfulCoral
    }
}
