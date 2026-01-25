import SwiftUI

/// Animated horizontal progress bar showing reward time balance
/// Displays available time with a filling bar (full = time available)
struct TimeBalanceRing: View {
    let availableMinutes: Int   // Cumulative available (rollover + today)
    let todayEarned: Int        // Today's earned (for progress calculation)

    @Environment(\.colorScheme) var colorScheme
    @State private var animatedProgress: Double = 0

    // Backward compatibility initializer
    init(availableMinutes: Int, todayEarned: Int) {
        self.availableMinutes = availableMinutes
        self.todayEarned = todayEarned
    }

    // Legacy initializer for backward compatibility
    init(earnedMinutes: Int, usedMinutes: Int) {
        self.availableMinutes = max(earnedMinutes - usedMinutes, 0)
        self.todayEarned = earnedMinutes
    }

    private var progress: Double {
        // Use a 60-minute reference as "full" for meaningful progress display
        let reference = max(todayEarned, 60)
        guard reference > 0 else { return availableMinutes > 0 ? 1.0 : 0.0 }
        return min(1.0, Double(availableMinutes) / Double(reference))
    }

    private var isLowBalance: Bool {
        availableMinutes > 0 && availableMinutes < 5
    }

    /// Formats available time as "X h Y min" when >= 60 minutes, otherwise just the number
    private var formattedAvailableTime: String {
        if availableMinutes >= 60 {
            let hours = availableMinutes / 60
            let mins = availableMinutes % 60
            if mins == 0 {
                return "\(hours) h"
            }
            return "\(hours) h \(mins) min"
        }
        return "\(availableMinutes)"
    }

    /// Label changes based on whether we're showing hours or minutes
    private var timeLabel: String {
        availableMinutes >= 60 ? "AVAILABLE" : "MIN AVAILABLE"
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: isLowBalance
                ? [AppTheme.playfulCoral, AppTheme.sunnyYellow]
                : [AppTheme.vibrantTeal, AppTheme.sunnyYellow],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Content color that contrasts against the progress bar gradient
    private var contentColor: Color {
        // White works well against both teal and coral gradients in light mode
        // In dark mode, use cream for warmth
        colorScheme == .dark ? AppTheme.lightCream : .white
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(AppTheme.vibrantTeal.opacity(0.1))

                // Progress bar
                Capsule()
                    .fill(progressGradient)
                    .frame(width: geometry.size.width * animatedProgress)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animatedProgress)

                // Content overlay
                HStack(spacing: 12) {
                    // Game controller icon
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 28))
                        .foregroundColor(contentColor.opacity(0.9))

                    // Time display
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedAvailableTime)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(contentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4), value: availableMinutes)

                        Text(timeLabel)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundColor(contentColor.opacity(0.85))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(height: 80)
        .overlay {
            // Low balance pulse effect
            if isLowBalance {
                Capsule()
                    .stroke(AppTheme.playfulCoral.opacity(0.5), lineWidth: 3)
                    .scaleEffect(x: 1.02, y: 1.05)
                    .opacity(0.5)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: isLowBalance
                    )
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Preview

#Preview("Full Balance") {
    VStack {
        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 0)
            .padding()
    }
    .background(AppTheme.background(for: .light))
}

#Preview("Partial Balance") {
    VStack {
        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 20)
            .padding()
    }
    .background(AppTheme.background(for: .light))
}

#Preview("Low Balance") {
    VStack {
        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 42)
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
        TimeBalanceRing(earnedMinutes: 60, usedMinutes: 15)
            .padding()
    }
    .background(AppTheme.background(for: .dark))
    .preferredColorScheme(.dark)
}
