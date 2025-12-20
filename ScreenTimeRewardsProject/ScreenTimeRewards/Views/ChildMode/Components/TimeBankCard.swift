import SwiftUI

/// Hero card displaying the child's reward time "bank balance"
/// Shows earned, used, and remaining time in a playful wallet metaphor
struct TimeBankCard: View {
    let earnedMinutes: Int
    let usedMinutes: Int

    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false

    // Design colors
    
    
    
    

    private var remainingMinutes: Int {
        max(earnedMinutes - usedMinutes, 0)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection

            // Balance Ring
            // Note: TimeBalanceRing might need update too, but for now we keep it
            // Assuming TimeBalanceRing handles its own colors or we can pass them if modified
            TimeBalanceRing(
                earnedMinutes: earnedMinutes,
                usedMinutes: usedMinutes
            )

            // Breakdown chips
            breakdownSection
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
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
                .font(.system(size: 18))
                .foregroundColor(AppTheme.vibrantTeal)
                .rotationEffect(.degrees(isAnimating ? 0 : -10))
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3), value: isAnimating)

            Text("TIME BANK")
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(AppTheme.vibrantTeal)

            Spacer()
        }
    }

    private var breakdownSection: some View {
        HStack(spacing: 16) {
            // Earned chip
            balanceChip(
                value: earnedMinutes,
                label: "EARNED",
                color: AppTheme.vibrantTeal
            )

            // Divider
            Text("-")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.vibrantTeal.opacity(0.4))

            // Used chip
            balanceChip(
                value: usedMinutes,
                label: "USED",
                color: AppTheme.playfulCoral
            )
        }
        .scaleEffect(isAnimating ? 1 : 0.9)
        .opacity(isAnimating ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4), value: isAnimating)
    }

    private func balanceChip(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)

            Text("MIN \(label)")
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
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
