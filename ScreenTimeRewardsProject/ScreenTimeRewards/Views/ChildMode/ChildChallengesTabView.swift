import SwiftUI

struct ChildChallengesTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? DesignTokens.Colors.deepNavy : DesignTokens.Colors.lightCream)
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
                                .padding(.horizontal, DesignTokens.Spacing.horizontal)
                                .padding(.bottom, DesignTokens.Spacing.sectionBottom)
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
                    .padding(.horizontal, DesignTokens.Spacing.horizontal)
                    .padding(.bottom, DesignTokens.Spacing.bottomPadding)
                    .padding(.top, DesignTokens.Spacing.topPadding)
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

// MARK: - Design Tokens

private extension ChildChallengesTabView {
    struct DesignTokens {
        struct Colors {
            // Base Colors
            static let deepNavy = Color(red: 0.027, green: 0.231, blue: 0.298) // #073B4C
            static let lightCream = Color(red: 0.969, green: 0.969, blue: 0.949) // #F7F7F2
            static let vibrantTeal = Color(red: 0, green: 0.651, blue: 0.651) // #00A6A6
            static let sunnyYellow = Color(red: 1, green: 0.820, blue: 0.400) // #FFD166
            static let playfulCoral = Color(red: 0.937, green: 0.278, blue: 0.435) // #EF476F

            // Card Background
            static let cardBackgroundLight = Color.white
            static let cardBackgroundDark = Color(red: 0.082, green: 0.294, blue: 0.361) // #154b5c

            // Text Colors
            static func primaryText(for scheme: ColorScheme) -> Color {
                scheme == .dark ? lightCream : deepNavy
            }

            static func secondaryText(for scheme: ColorScheme) -> Color {
                scheme == .dark ? lightCream.opacity(0.7) : deepNavy.opacity(0.7)
            }

            static func cardBackground(for scheme: ColorScheme) -> Color {
                scheme == .dark ? cardBackgroundDark : cardBackgroundLight
            }
        }

        struct Spacing {
            static let horizontal: CGFloat = 16
            static let topPadding: CGFloat = 16
            static let bottomPadding: CGFloat = 32
            static let sectionBottom: CGFloat = 24
            static let sectionTop: CGFloat = 20
            static let sectionTitleBottom: CGFloat = 12
        }

        struct Typography {
            static let appBarTitle = Font.system(size: 20, weight: .bold)
            static let sectionTitle = Font.system(size: 22, weight: .bold)
            static let questTitle = Font.system(size: 16, weight: .medium)
            static let questSubtitle = Font.system(size: 14, weight: .regular)
            static let progressPercent = Font.system(size: 12, weight: .medium)
            static let badgeLabel = Font.system(size: 14, weight: .medium)
        }

        struct Dimensions {
            static let appBarHeight: CGFloat = 60
            static let iconSize: CGFloat = 48
            static let badgeSize: CGFloat = 96
            static let cornerRadius: CGFloat = 16
            static let cardCornerRadius: CGFloat = 12
        }
    }
}

// MARK: - Subviews

private extension ChildChallengesTabView {
    var topAppBar: some View {
        HStack(spacing: 0) {
            // Left Icon
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24))
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
                .frame(width: 48, height: 48)

            Spacer()

            // Title
            Text("Quest Central")
                .font(DesignTokens.Typography.appBarTitle)
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))

            Spacer()

            // Right Icon
            Image(systemName: "person.circle")
                .font(.system(size: 30))
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
                .frame(width: 48, height: 48)
        }
        .frame(height: DesignTokens.Dimensions.appBarHeight)
        .padding(.horizontal, DesignTokens.Spacing.horizontal)
        .background(colorScheme == .dark ? DesignTokens.Colors.deepNavy : DesignTokens.Colors.lightCream)
    }

    var streakSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Streak!")
                    .font(DesignTokens.Typography.questTitle)
                    .fontWeight(.bold)
                    .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))

                HStack(alignment: .bottom, spacing: 12) {
                    // Fire icon
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignTokens.Colors.sunnyYellow)

                    // Streak number
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))

                    // Keep it up text
                    Text("Keep it up!")
                        .font(.system(size: 16))
                        .foregroundColor(DesignTokens.Colors.secondaryText(for: colorScheme))
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.cornerRadius)
                .fill(DesignTokens.Colors.cardBackground(for: colorScheme))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionTitleBottom) {
            Text("Current Quests")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
                .padding(.top, DesignTokens.Spacing.sectionTop)

            VStack(spacing: 12) {
                ForEach(viewModel.activeChallenges) { challenge in
                    questListItem(for: challenge)
                }
            }
        }
        .padding(.bottom, DesignTokens.Spacing.sectionBottom)
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
                    .frame(width: DesignTokens.Dimensions.iconSize, height: DesignTokens.Dimensions.iconSize)

                Image(systemName: questIcon(for: challenge))
                    .font(.system(size: 24))
                    .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title ?? "Challenge")
                    .font(DesignTokens.Typography.questTitle)
                    .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
                    .lineLimit(1)

                Text(goalSubtitle(for: challenge))
                    .font(DesignTokens.Typography.questSubtitle)
                    .foregroundColor(DesignTokens.Colors.secondaryText(for: colorScheme))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorScheme == .dark ? DesignTokens.Colors.deepNavy.opacity(0.5) : DesignTokens.Colors.lightCream)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(iconColor)
                                .frame(width: geometry.size.width * CGFloat(progressFraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    // Percentage
                    Text("\(progressPercent)%")
                        .font(DesignTokens.Typography.progressPercent)
                        .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
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
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.cardCornerRadius)
                .fill(DesignTokens.Colors.cardBackground(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }

    func questIcon(for challenge: Challenge) -> String {
        challenge.goalTypeEnum?.iconName ?? "checkmark.circle"
    }

    func questIconColor(for challenge: Challenge) -> Color {
        challenge.goalTypeEnum?.accentColor ?? DesignTokens.Colors.vibrantTeal
    }

    var badgesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionTitleBottom) {
            Text("Badge Collection")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
                .padding(.top, DesignTokens.Spacing.sectionTop)

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
                        ForEach(0..<(5 - viewModel.badges.count), id: \.self) { _ in
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
                    .fill(DesignTokens.Colors.sunnyYellow.opacity(colorScheme == .dark ? 0.3 : 0.2))
                    .frame(width: DesignTokens.Dimensions.badgeSize, height: DesignTokens.Dimensions.badgeSize)
                    .overlay(
                        Circle()
                            .stroke(DesignTokens.Colors.sunnyYellow, lineWidth: 4)
                    )

                Image(systemName: "star.fill")
                    .font(.system(size: 40))
                    .foregroundColor(DesignTokens.Colors.sunnyYellow)
            }

            Text(badge.badgeName ?? "Badge")
                .font(DesignTokens.Typography.badgeLabel)
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
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
                    .frame(width: DesignTokens.Dimensions.badgeSize, height: DesignTokens.Dimensions.badgeSize)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.4), lineWidth: 4)
                    )

                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color.gray.opacity(0.5))
            }

            Text("Mystery Badge")
                .font(DesignTokens.Typography.badgeLabel)
                .foregroundColor(DesignTokens.Colors.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(width: 96)
        }
        .frame(width: 96)
        .opacity(0.5)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("Future Adventures")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DesignTokens.Spacing.sectionTop)

            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 60))
                    .foregroundColor(DesignTokens.Colors.vibrantTeal)

                Text("No new quests right now, explorer!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.primaryText(for: colorScheme))

                Text("Check back soon for more exciting challenges and awesome rewards.")
                    .font(.system(size: 16))
                    .foregroundColor(DesignTokens.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Dimensions.cornerRadius)
                    .fill(DesignTokens.Colors.cardBackground(for: colorScheme))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
        case .dailyMinutes:
            return "Spend \(target) minutes today"
        case .weeklyMinutes:
            return "Spend \(target) minutes this week"
        case .specificApps:
            return "Practice apps for \(target) minutes"
        case .streak:
            return "Keep learning \(target) days in a row"
        case .pointsTarget:
            return "Earn \(target) points"
        case .none:
            return "Keep learning!"
        }
    }

    func rewardSummary(for challenge: Challenge) -> String? {
        let ids = challenge.rewardAppIDs
        guard !ids.isEmpty else { return nil }
        let names = ids.compactMap { rewardNameLookup[$0] }

        var baseText: String
        if names.isEmpty {
            baseText = "Unlocks \(ids.count) reward apps"
        } else if names.count == 1 {
            baseText = "Unlocks \(names[0])"
        } else if names.count == 2 {
            baseText = "Unlocks \(names[0]) & \(names[1])"
        } else {
            baseText = "Unlocks \(names[0]) & \(names.count - 1) more"
        }

        let minutes = challenge.rewardUnlockMinutes()
        let minuteLabel = minutes == 1 ? "minute" : "minutes"
        return "\(baseText) · \(minutes) \(minuteLabel)"
    }

    var rewardNameLookup: [String: String] {
        viewModel.rewardSnapshots.reduce(into: [:]) { result, snapshot in
            let name = snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName
            result[snapshot.logicalID] = name
        }
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
