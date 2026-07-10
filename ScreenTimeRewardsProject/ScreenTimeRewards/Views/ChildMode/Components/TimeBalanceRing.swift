import SwiftUI

/// Hero display for the child's spendable reward-time balance.
///
/// Earlier this component was a horizontal progress bar (hence the "Ring" name),
/// but a balance has no fixed target — there's nothing to fill toward — so the
/// bar communicated nothing. This version makes the number itself the hero,
/// sitting on a soft halo. Low-balance state pulses the hero coral instead of
/// the old separate stroke overlay.
struct TimeBalanceRing: View {
    let availableMinutes: Int   // Cumulative available (rollover + today)
    let todayEarned: Int        // Today's earned (kept for API compatibility, no longer drives layout)

    @Environment(\.colorScheme) var colorScheme
    @State private var pulse: Bool = false

    init(availableMinutes: Int, todayEarned: Int) {
        self.availableMinutes = availableMinutes
        self.todayEarned = todayEarned
    }

    /// Legacy initializer for backward compatibility
    init(earnedMinutes: Int, usedMinutes: Int) {
        self.availableMinutes = max(earnedMinutes - usedMinutes, 0)
        self.todayEarned = earnedMinutes
    }

    private var isLowBalance: Bool {
        availableMinutes > 0 && availableMinutes < 5
    }

    /// Formats available time as "Xh Ym" when >= 60 minutes, otherwise just the number.
    private var formattedAvailableTime: String {
        if availableMinutes >= 60 {
            let hours = availableMinutes / 60
            let mins = availableMinutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
        return "\(availableMinutes)"
    }

    private var timeLabel: String {
        availableMinutes >= 60 ? String(localized: "AVAILABLE") : String(localized: "MIN AVAILABLE")
    }

    /// Primary hero color — coral when low-balance to draw the eye, brand teal otherwise.
    private var heroColor: Color {
        isLowBalance
            ? AppTheme.playfulCoral
            : AppTheme.brandedText(for: colorScheme)
    }

    private var haloColor: Color {
        isLowBalance ? AppTheme.playfulCoral : AppTheme.vibrantTeal
    }

    var body: some View {
        ZStack {
            // Soft circular halo behind the hero — adds visual character without
            // implying "progress toward a goal" the way a bar does.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            haloColor.opacity(colorScheme == .dark ? 0.32 : 0.20),
                            haloColor.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)

            // Hero content
            HStack(spacing: 18) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(heroColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedAvailableTime)
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(heroColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: availableMinutes)

                    Text(timeLabel)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(heroColor.opacity(0.75))
                }
            }
            .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .onAppear {
            startPulseIfNeeded()
        }
        .onChange(of: isLowBalance) { _ in
            startPulseIfNeeded()
        }
    }

    private func startPulseIfNeeded() {
        if isLowBalance {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                pulse = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Healthy Balance") {
    VStack {
        TimeBalanceRing(availableMinutes: 40, todayEarned: 76)
            .padding()
    }
    .background(AppTheme.background(for: .light))
}

#Preview("Zero Balance") {
    VStack {
        TimeBalanceRing(availableMinutes: 0, todayEarned: 76)
            .padding()
    }
    .background(AppTheme.background(for: .light))
}

#Preview("Low Balance Pulse") {
    VStack {
        TimeBalanceRing(availableMinutes: 3, todayEarned: 45)
            .padding()
    }
    .background(AppTheme.background(for: .light))
}

#Preview("Hours Format") {
    VStack {
        TimeBalanceRing(availableMinutes: 90, todayEarned: 120)
            .padding()
    }
    .background(AppTheme.background(for: .light))
}

#Preview("Dark Mode") {
    VStack {
        TimeBalanceRing(availableMinutes: 40, todayEarned: 76)
            .padding()
    }
    .background(AppTheme.background(for: .dark))
    .preferredColorScheme(.dark)
}
