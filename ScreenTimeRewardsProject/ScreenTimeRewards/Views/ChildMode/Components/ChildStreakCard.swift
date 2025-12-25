import SwiftUI

struct ChildStreakCard: View {
    let aggregateStreak: (current: Int, longest: Int, isAtRisk: Bool)
    let appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)]
    let nextMilestone: Int?
    let progress: Double
    let hasAnyStreaksEnabled: Bool

    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    @State private var showDetailView = false

    var body: some View {
        // Only show if streaks are enabled and streak > 0
        if hasAnyStreaksEnabled && aggregateStreak.current > 0 {
            VStack(spacing: 16) {
                headerSection
                streakDisplay
                milestoneProgress
                
                // Show detail button if multiple apps have streaks
                if appStreaks.count > 1 {
                    detailButton
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .onAppear { animateEntrance() }
            .sheet(isPresented: $showDetailView) {
                StreakDetailView(appStreaks: appStreaks)
            }
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(AppTheme.card(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
            )
    }
    
    private var daysUntilMilestone: Int {
        guard let next = nextMilestone else { return 0 }
        return max(next - aggregateStreak.current, 0)
    }
    
    // MARK: - Subcomponents

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.sunnyYellow)
                .rotationEffect(.degrees(isAnimating ? 0 : -10))
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3),
                          value: isAnimating)

            Text("DAILY STREAK")
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()

            // Longest streak badge
            if aggregateStreak.longest > aggregateStreak.current {
                bestStreakBadge
            }
        }
    }
    
    private var detailButton: some View {
        Button(action: { showDetailView = true }) {
            HStack {
                Text("View All \(appStreaks.count) Streaks")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .foregroundColor(AppTheme.vibrantTeal)
        }
    }

    private var streakDisplay: some View {
        HStack(spacing: 20) {
            // Flame icon ring
            ZStack {
                Circle()
                    .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.sunnyYellow, AppTheme.vibrantTeal],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7),
                              value: progress)

                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.sunnyYellow)
                    .shadow(color: AppTheme.sunnyYellow.opacity(0.3), radius: 8)
            }

            // Streak count
            VStack(alignment: .leading, spacing: 4) {
                Text("\(aggregateStreak.current)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.sunnyYellow)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: aggregateStreak.current)

                Text(aggregateStreak.current == 1 ? "DAY" : "DAYS")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .scaleEffect(isAnimating ? 1 : 0.9)
        .opacity(isAnimating ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4),
                  value: isAnimating)
        .overlay {
             if aggregateStreak.isAtRisk {
                 VStack {
                     HStack {
                         Image(systemName: "exclamationmark.triangle.fill")
                             .font(.system(size: 12))
                         Text("Complete a goal today!")
                             .font(.system(size: 11, weight: .medium))
                     }
                     .foregroundColor(AppTheme.playfulCoral)
                     .padding(8)
                     .background(
                         Capsule()
                             .fill(AppTheme.playfulCoral.opacity(0.1))
                     )
                 }
                 .padding(.top, 100) // Position below the flame
             }
         }
    }

    private var milestoneProgress: some View {
        Group {
            if let nextMilestone = nextMilestone {
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(AppTheme.vibrantTeal.opacity(0.1))
                                .frame(height: 6)

                            // Progress fill
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.vibrantTeal, AppTheme.sunnyYellow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress,
                                       height: 6)
                        }
                    }
                    .frame(height: 6)

                    // Milestone text
                    HStack {
                        Image(systemName: "target")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.vibrantTeal)

                        Text("\(daysUntilMilestone) more \(daysUntilMilestone == 1 ? "day" : "days") to \(nextMilestone)-day bonus!")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                        Spacer()
                    }
                }
            }
        }
    }

    private var bestStreakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("\(aggregateStreak.longest)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.sunnyYellow)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppTheme.sunnyYellow.opacity(0.15))
        )
    }

    private func animateEntrance() {
        withAnimation(.easeOut(duration: 0.6)) {
            isAnimating = true
        }
    }
}