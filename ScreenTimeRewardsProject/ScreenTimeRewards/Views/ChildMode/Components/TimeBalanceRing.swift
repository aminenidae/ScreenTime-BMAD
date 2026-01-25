import SwiftUI

/// Animated circular ring showing reward time balance
/// Displays available time as a filling ring (full = time available)
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

    // Design colors

    private var progress: Double {
        // Show full ring if there's any available time, proportional otherwise
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

    var body: some View {
        ZStack {
            // Background ring (track)
            Circle()
                .stroke(
                    AppTheme.vibrantTeal.opacity(0.1),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animatedProgress)

            // Center content
            VStack(spacing: 4) {
                // Game controller icon
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))

                // Balance amount (cumulative available) - shows h:mm when >= 60
                Text(formattedAvailableTime)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: availableMinutes)

                // Label - removes "MIN" when showing hours
                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .frame(width: 160, height: 160)
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
        // Low balance pulse effect
        .overlay {
            if isLowBalance {
                Circle()
                    .stroke(AppTheme.playfulCoral.opacity(0.5), lineWidth: 3)
                    .scaleEffect(1.1)
                    .opacity(0.5)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: isLowBalance
                    )
            }
        }
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: isLowBalance
                ? [AppTheme.playfulCoral, AppTheme.sunnyYellow]
                : [AppTheme.sunnyYellow, AppTheme.vibrantTeal],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }
}

// MARK: - Preview

#Preview("Full Balance") {
    ZStack {
        LinearGradient(
            colors: [AppTheme.vibrantTeal, AppTheme.playfulCoral],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 0)
    }
}

#Preview("Partial Balance") {
    ZStack {
        LinearGradient(
            colors: [AppTheme.vibrantTeal, AppTheme.playfulCoral],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 20)
    }
}

#Preview("Low Balance") {
    ZStack {
        LinearGradient(
            colors: [AppTheme.vibrantTeal, AppTheme.playfulCoral],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 42)
    }
}

#Preview("Empty Balance") {
    ZStack {
        LinearGradient(
            colors: [AppTheme.vibrantTeal, AppTheme.playfulCoral],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        TimeBalanceRing(earnedMinutes: 45, usedMinutes: 45)
    }
}
