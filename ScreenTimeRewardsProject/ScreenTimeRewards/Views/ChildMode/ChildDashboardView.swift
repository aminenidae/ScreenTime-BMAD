import SwiftUI
import FamilyControls
import ManagedSettings

struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        ZStack {
            // Background color
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Top App Bar with avatar and points
                    topAppBar

                    // Main content
                    VStack(alignment: .leading, spacing: 0) {
                        // Quests Section
                        if !viewModel.activeChallenges.isEmpty {
                            questsSection
                        }

                        // Learning Zone Section - Show all learning apps
                        if !viewModel.learningSnapshots.isEmpty {
                            learningZoneSection
                        }

                        // Play Zone Section - Show all reward apps
                        if !viewModel.rewardSnapshots.isEmpty {
                            playZoneSection
                        }

                        // Empty state
                        if viewModel.activeChallenges.isEmpty &&
                           viewModel.learningSnapshots.isEmpty &&
                           viewModel.rewardSnapshots.isEmpty {
                            emptyStateView
                        }
                    }

                    Spacer(minLength: 112) // Bottom padding for floating action button
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
}


// MARK: - View Components
private extension ChildDashboardView {
    var topAppBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                // Avatar
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [AppTheme.vibrantTeal.opacity(0.3), AppTheme.playfulCoral.opacity(0.3)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.vibrantTeal.opacity(0.5), lineWidth: 2)
                    )

                // Greeting
                Text("Hi Alex!")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.015 * 20)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Points badge - HIDDEN (keeping code for future use)
                // HStack(spacing: 6) {
                //     Image(systemName: "star.fill")
                //         .font(.system(size: 24))
                //         .foregroundColor(AppTheme.sunnyYellow)
                //
                //     Text("\(viewModel.learningRewardPoints)")
                //         .font(.system(size: 18, weight: .bold))
                //         .tracking(0.015 * 18)
                //         .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                // }
                // .padding(.horizontal, 16)
                // .padding(.vertical, 8)
                // .background(
                //     RoundedRectangle(cornerRadius: 9999)
                //         .fill(AppTheme.sunnyYellow.opacity(colorScheme == .dark ? 0.3 : 0.2))
                // )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }

    var questsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Your Quests!")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.015 * 22)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Horizontal scrolling quest cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.activeChallenges.prefix(3).enumerated()), id: \.element.id) { index, challenge in
                        NavigationLink(destination: ChildChallengeDetailView(
                            challenge: challenge,
                            progress: viewModel.challengeProgress[challenge.challengeID ?? ""]
                        )) {
                            questCard(challenge: challenge, index: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    func questCard(challenge: Challenge, index: Int) -> some View {
        let colors = [
            (icon: "function", bgColor: AppTheme.vibrantTeal, barColor: AppTheme.vibrantTeal),
            (icon: "book", bgColor: AppTheme.playfulCoral, barColor: AppTheme.playfulCoral),
            (icon: "flask", bgColor: AppTheme.vibrantTeal, barColor: AppTheme.vibrantTeal)
        ]
        let colorSet = colors[index % colors.count]

        let challengeID = challenge.challengeID ?? ""
        let progress = viewModel.challengeProgress[challengeID]
        let currentValue = Double(progress?.currentValue ?? 0)
        let targetValue = Double(progress?.targetValue ?? 1)
        let progressPercentage = targetValue > 0 ? (currentValue / targetValue) : 0

        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Icon
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorSet.bgColor.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: colorSet.icon)
                            .font(.system(size: 32))
                            .foregroundColor(colorSet.bgColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title ?? "Challenge")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(challenge.challengeDescription ?? "Complete the challenge")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            // Progress bar (full width now that points are hidden)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 9999)
                        .fill(AppTheme.progressTrack(for: colorScheme))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 9999)
                        .fill(colorSet.barColor)
                        .frame(width: geometry.size.width * progressPercentage, height: 10)
                }
            }
            .frame(height: 10)

            // Points reward - HIDDEN (keeping code for future use)
            // HStack(spacing: 4) {
            //     Image(systemName: "star.fill")
            //         .font(.system(size: 18))
            //         .foregroundColor(AppTheme.sunnyYellow)
            //
            //     Text("+\(challenge.bonusPercentage)% bonus")
            //         .font(.system(size: 16, weight: .bold))
            //         .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            // }

            if let callout = rewardCallout(for: challenge) {
                Text(callout)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorSet.barColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
    }

    var learningZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Learning Zone")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.015 * 22)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 12)

            // Learning apps grid - Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
            let columns = horizontalSizeClass == .regular ? [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ] : [
                GridItem(.flexible())
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.learningSnapshots) { snapshot in
                    learningAppRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        // Icon sizes reduced by 50% to give more room for text
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24

        return HStack(spacing: 16) {
            // App icon - device-specific larger scale
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(iconScale)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.vibrantTeal.opacity(0.2))
                    .frame(width: iconSize, height: iconSize)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: fallbackIconSize))
                            .foregroundColor(AppTheme.vibrantTeal)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                // Use Label to get proper app name
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }

                Text("\(viewModel.formatTime(snapshot.totalSeconds))")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
    }

    var playZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Play Zone")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.015 * 22)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 12)

            // Reward apps grid - Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
            let columns = horizontalSizeClass == .regular ? [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ] : [
                GridItem(.flexible())
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.rewardSnapshots) { snapshot in
                    rewardAppRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        let isUnlocked = viewModel.unlockedRewardApps[snapshot.token] != nil
        let challengeMinutes = rewardMinutesFor(snapshot: snapshot)

        // Icon sizes reduced by 50% to give more room for text
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24

        return HStack(spacing: 16) {
            // App icon - device-specific larger scale
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(iconScale)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: iconSize, height: iconSize)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: fallbackIconSize))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                // Use Label with 8pt font for long names
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                } else {
                    Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(isUnlocked ? "\(viewModel.formatTime(snapshot.totalSeconds)) unlocked" : "Complete a quest to unlock")
                    .font(.system(size: 14, weight: isUnlocked ? .medium : .regular))
                    .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme))
                    .lineLimit(1)

                if let minutes = challengeMinutes, !isUnlocked {
                    Text("Unlock for \(minutes) min")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.sunnyYellow)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
        .opacity(isUnlocked ? 1.0 : 0.5)
    }

    func rewardCallout(for challenge: Challenge) -> String? {
        let ids = challenge.rewardAppIDs
        guard !ids.isEmpty else { return nil }

        let targetMinutes = Int(challenge.targetValue)
        return "Complete \(targetMinutes) minutes of Learning"
    }


    func rewardMinutesFor(snapshot: RewardAppSnapshot) -> Int? {
        let logicalID = snapshot.logicalID
        guard let challenge = viewModel.activeChallenges.first(where: { $0.rewardAppIDs.contains(logicalID) }) else {
            return nil
        }
        return challenge.rewardUnlockMinutes()
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 48)

            // Placeholder for friendly robot image
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [AppTheme.vibrantTeal.opacity(0.2), AppTheme.playfulCoral.opacity(0.2)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 192, height: 144)
                .overlay(
                    Image(systemName: "face.smiling")
                        .font(.system(size: 72))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                )

            Text("All Done for Now!")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.top, 16)

            Text("Great job on finishing your quests! Ask a parent to add a new adventure for you.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 280)
        }
        .padding(.horizontal, 16)
    }
}
