import SwiftUI

struct AppStreakCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let nextMilestone: Int?
    let bonusMinutesEarned: Int
    let potentialBonusMinutes: Int
    let progress: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("YOUR STREAK FOR THIS APP")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            HStack(spacing: 24) {
                // Flame icon with ring
                ZStack {
                    Circle()
                        .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AppTheme.sunnyYellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 60, height: 60)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.sunnyYellow)
                }

                // Streak stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("\(currentStreak)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.sunnyYellow)

                        Text(currentStreak == 1 ? "DAY" : "DAYS")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .offset(y: 8)
                    }

                    if let nextMilestone = nextMilestone {
                        Text("\(nextMilestone - currentStreak) more to \(nextMilestone)-day bonus!")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Spacer()
            }

            // Bonus earned
            if bonusMinutesEarned > 0 {
                HStack {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 12))
                    Text("+\(bonusMinutesEarned) bonus minutes earned from streaks!")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AppTheme.sunnyYellow)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.sunnyYellow.opacity(0.1))
                )
            }
            
            // Potential bonus footer
            if let milestone = nextMilestone {
                HStack(spacing: 6) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    
                    Text("You will earn \(potentialBonusMinutes) minutes bonus at completion of \(milestone)-day streak!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }
}
