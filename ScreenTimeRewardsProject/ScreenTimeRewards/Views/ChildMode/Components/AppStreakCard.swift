import SwiftUI

struct ChildAppStreakCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let nextMilestone: Int?
    let progress: Double
    let milestoneCycleDays: Int
    let isAtRisk: Bool
    let potentialBonus: Int

    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            headerSection
            streakDisplay
            milestoneProgress
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .onAppear { animateEntrance() }
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
        return max(next - currentStreak, 0)
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
            if longestStreak > currentStreak {
                bestStreakBadge
            }
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
                Text("\(currentStreak)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.sunnyYellow)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: currentStreak)

                Text(currentStreak == 1 ? "DAY" : "DAYS")
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
             if isAtRisk {
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
                VStack(spacing: 12) {
                    // Day X of Y Text
                    HStack {
                         Text("Day \(completedDaysInCycle) of \(milestoneCycleDays)")
                             .font(.system(size: 14, weight: .semibold))
                             .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                         Spacer()

                         Text("\(daysUntilMilestone) days left")
                             .font(.system(size: 12, weight: .medium))
                             .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }

                    // Dot Visual
                    HStack(spacing: 8) {
                        ForEach(0..<milestoneCycleDays, id: \.self) { index in
                            Circle()
                                .fill(index < completedDaysInCycle
                                    ? (colorScheme == .dark ? Color.white : AppTheme.vibrantTeal)
                                    : Color.clear)
                                .frame(height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            colorScheme == .dark
                                                ? (index < completedDaysInCycle ? Color.white : Color.white.opacity(0.3))
                                                : (index < completedDaysInCycle ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.3)),
                                            lineWidth: index < completedDaysInCycle ? 0 : 1.5
                                        )
                                )
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 12)

                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.sunnyYellow)

                        Text("Reach \(nextMilestone) days for a bonus of \(potentialBonus) minutes!")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
    }

    private var completedDaysInCycle: Int {
        // Calculate days completed in current cycle based on progress
        // progress is 0..1. If cycle is 3 and progress is 0.33, it's 1 day.
        Int(round(progress * Double(milestoneCycleDays)))
    }

    private var bestStreakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("\(longestStreak)")
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
