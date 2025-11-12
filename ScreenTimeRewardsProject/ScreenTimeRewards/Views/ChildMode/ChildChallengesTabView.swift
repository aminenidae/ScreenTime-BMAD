import SwiftUI

struct ChildChallengesTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top App Bar
                topAppBar

                // Main Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Streak Card
                        if viewModel.currentStreak > 0 {
                            streakSection
                                .padding(.horizontal, AppTheme.Spacing.regular)
                                .padding(.bottom, AppTheme.Spacing.xLarge)
                        }

                        // Current Quests Section
                        if !viewModel.activeChallenges.isEmpty {
                            activeChallengesSection
                        }

                        // Badge Collection Section
                        badgesSection

                        // Empty State / Future Adventures
                        if viewModel.activeChallenges.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.regular)
                    .padding(.bottom, AppTheme.Spacing.xxLarge)
                    .padding(.top, AppTheme.Spacing.regular)
                }
            }
        }
        .refreshable {
            await viewModel.loadChallengeData()
        }
        .overlay {
            if viewModel.showCompletionCelebration {
                let minutes = max(viewModel.lastRewardUnlockMinutes, 1)
                let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
                CompletionCelebrationView(
                    title: "Goal Complete!",
                    subtitle: "You've unlocked \(minuteText) of reward time!",
                    buttonText: "Claim Reward",
                    onDismiss: {
                        viewModel.showCompletionCelebration = false
                        viewModel.completedChallengeID = nil
                    }
                )
            }
        }
    }
}


// MARK: - Subviews

private extension ChildChallengesTabView {
    var topAppBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                sessionManager.exitToSelection()
            }) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .frame(width: 48, height: 48)
            }

            Spacer()

            // Title
            Text("Quest Central")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()

            // Right Icon
            Image(systemName: "person.circle")
                .font(.system(size: 30))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(width: 48, height: 48)
        }
        .frame(height: 60)
        .padding(.horizontal, AppTheme.Spacing.regular)
        .background(AppTheme.background(for: colorScheme))
    }

    var streakSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Streak!")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                HStack(alignment: .bottom, spacing: 12) {
                    // Fire icon
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.sunnyYellow)

                    // Streak number
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    // Keep it up text
                    Text("Keep it up!")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Current Quests")
                .font(AppTheme.Typography.title2)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.top, AppTheme.Spacing.large)

            VStack(spacing: 12) {
                ForEach(viewModel.activeChallenges) { challenge in
                    NavigationLink(destination: ChildChallengeDetailView(
                        challenge: challenge,
                        progress: viewModel.challengeProgress[challenge.challengeID ?? ""]
                    )) {
                        questListItem(for: challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, AppTheme.Spacing.xLarge)
    }

    func questListItem(for challenge: Challenge) -> some View {
        let challengeProgress = viewModel.challengeProgress[challenge.challengeID ?? ""]
        let progressPercent = Int(min(challengeProgress?.progressPercentage ?? 0, 100))
        let progressFraction = progressFractionValue(for: challengeProgress, fallbackTarget: Int(challenge.targetValue))
        let iconColor = questIconColor(for: challenge)

        return HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(colorScheme == .dark ? 0.3 : 0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: questIcon(for: challenge))
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title ?? "Challenge")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)

                Text(goalSubtitle(for: challenge))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.progressTrack(for: colorScheme))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(iconColor)
                                .frame(width: geometry.size.width * CGFloat(progressFraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    // Percentage
                    Text("\(progressPercent)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.top, 4)

                if let summary = rewardSummary(for: challenge) {
                    Text(summary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(iconColor)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
    }

    func questIcon(for challenge: Challenge) -> String {
        challenge.goalTypeEnum?.iconName ?? "checkmark.circle"
    }

    func questIconColor(for challenge: Challenge) -> Color {
        challenge.goalTypeEnum?.accentColor ?? AppTheme.vibrantTeal
    }

    var badgesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Badge Collection")
                .font(AppTheme.Typography.title2)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.top, AppTheme.Spacing.large)

            if viewModel.badges.isEmpty {
                // Show placeholder badges when none earned yet
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(0..<5, id: \.self) { index in
                            lockedBadgeItem
                        }
                    }
                    .padding(.bottom, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.badges) { badge in
                            earnedBadgeItem(for: badge)
                        }

                        // Add locked badges to show what's remaining
                        let remainingBadges = max(5 - viewModel.badges.count, 0)
                        ForEach(0..<remainingBadges, id: \.self) { _ in
                            lockedBadgeItem
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    func earnedBadgeItem(for badge: Badge) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(AppTheme.sunnyYellow.opacity(colorScheme == .dark ? 0.3 : 0.2))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.sunnyYellow, lineWidth: 4)
                    )

                Image(systemName: "star.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            Text(badge.badgeName ?? "Badge")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(width: 96)
        }
        .frame(width: 96)
    }

    var lockedBadgeItem: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.4), lineWidth: 4)
                    )

                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color.gray.opacity(0.5))
            }

            Text("Mystery Badge")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(width: 96)
        }
        .frame(width: 96)
        .opacity(0.5)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("Future Adventures")
                .font(AppTheme.Typography.title2)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.Spacing.large)

            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("No new quests right now, explorer!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Check back soon for more exciting challenges and awesome rewards.")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
            )
        }
        .padding(.top, 32)
    }
}

private extension ChildChallengesTabView {
    func progressFractionValue(for progress: ChallengeProgress?, fallbackTarget: Int) -> Double {
        let target = max(Double(progress?.targetValue ?? Int32(fallbackTarget)), 1)
        let current = Double(progress?.currentValue ?? 0)
        let fraction = current / target
        return min(max(fraction, 0), 1)
    }

    func goalSubtitle(for challenge: Challenge) -> String {
        let target = Int(challenge.targetValue)
        switch challenge.goalTypeEnum {
        case .dailyQuest:
            return "Spend \(target) minutes today"
        case .none:
            return "Keep learning!"
        }
    }

    func rewardSummary(for challenge: Challenge) -> String? {
        let ids = challenge.rewardAppIDs
        guard !ids.isEmpty else { return nil }

        let targetMinutes = Int(challenge.targetValue)
        return "Complete \(targetMinutes) minutes of Learning"
    }

    var completedChallengeTitle: String {
        guard
            let id = viewModel.completedChallengeID,
            let challenge = viewModel.activeChallenges.first(where: { $0.challengeID == id })
        else {
            return "Challenge Completed"
        }
        return challenge.title ?? "Challenge Completed"
    }
}
