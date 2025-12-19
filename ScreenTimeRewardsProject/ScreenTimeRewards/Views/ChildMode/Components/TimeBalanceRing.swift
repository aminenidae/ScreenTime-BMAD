import SwiftUI

/// Animated circular ring showing reward time balance
/// Displays remaining time as a depleting ring (full = all time available)
struct TimeBalanceRing: View {
    let earnedMinutes: Int
    let usedMinutes: Int

    @Environment(\.colorScheme) var colorScheme
    @State private var animatedProgress: Double = 0

    // Design colors
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
    private let accentYellow = Color(red: 0.98, green: 0.80, blue: 0.30)

    private var remainingMinutes: Int {
        max(earnedMinutes - usedMinutes, 0)
    }

    private var progress: Double {
        guard earnedMinutes > 0 else { return 0 }
        return Double(remainingMinutes) / Double(earnedMinutes)
    }

    private var isLowBalance: Bool {
        remainingMinutes > 0 && remainingMinutes < 5
    }

    var body: some View {
        ZStack {
            // Background ring (track)
            Circle()
                .stroke(
                    tealColor.opacity(0.1),
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
                    .foregroundColor(tealColor.opacity(0.8))

                // Balance amount
                Text("\(remainingMinutes)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(tealColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: remainingMinutes)

                // Label
                Text("MIN LEFT")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(tealColor.opacity(0.6))
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
                    .stroke(lightCoral.opacity(0.5), lineWidth: 3)
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
                ? [lightCoral, accentYellow]
                : [accentYellow, tealColor],
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
