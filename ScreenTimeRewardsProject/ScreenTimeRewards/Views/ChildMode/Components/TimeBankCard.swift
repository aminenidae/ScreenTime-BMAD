import SwiftUI

/// Hero card displaying the child's reward time "bank balance"
/// Shows earned, used, and remaining time in a playful wallet metaphor
struct TimeBankCard: View {
    let earnedMinutes: Int
    let usedMinutes: Int

    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false

    private var remainingMinutes: Int {
        max(earnedMinutes - usedMinutes, 0)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection

            // Balance Ring
            TimeBalanceRing(
                earnedMinutes: earnedMinutes,
                usedMinutes: usedMinutes
            )

            // Breakdown chips
            breakdownSection
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xLarge)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.vibrantTeal,
                            AppTheme.vibrantTeal.opacity(0.8),
                            AppTheme.playfulCoral.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(isAnimating ? 0 : -10))
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3), value: isAnimating)

            Text("YOUR TIME BANK")
                .font(.system(size: 18, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white)

            Image(systemName: "banknote.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(isAnimating ? 0 : 10))
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3), value: isAnimating)
        }
    }

    private var breakdownSection: some View {
        HStack(spacing: 16) {
            // Earned chip
            balanceChip(
                value: earnedMinutes,
                label: "earned",
                color: AppTheme.sunnyYellow
            )

            // Divider
            Text("-")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.6))

            // Used chip
            balanceChip(
                value: usedMinutes,
                label: "used",
                color: AppTheme.playfulCoral
            )
        }
        .scaleEffect(isAnimating ? 1 : 0.9)
        .opacity(isAnimating ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4), value: isAnimating)
    }

    private func balanceChip(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())

            Text("min \(label)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(color.opacity(0.3))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview("Full Balance") {
    VStack {
        TimeBankCard(earnedMinutes: 45, usedMinutes: 0)
    }
    .padding()
    .background(AppTheme.background(for: .light))
}

#Preview("Partial Balance") {
    VStack {
        TimeBankCard(earnedMinutes: 45, usedMinutes: 20)
    }
    .padding()
    .background(AppTheme.background(for: .light))
}

#Preview("Low Balance") {
    VStack {
        TimeBankCard(earnedMinutes: 45, usedMinutes: 42)
    }
    .padding()
    .background(AppTheme.background(for: .light))
}

#Preview("Dark Mode") {
    VStack {
        TimeBankCard(earnedMinutes: 45, usedMinutes: 20)
    }
    .padding()
    .background(AppTheme.background(for: .dark))
    .preferredColorScheme(.dark)
}
