import SwiftUI
import FamilyControls

struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background color
            (colorScheme == .dark ? DesignColors.navyBlue : DesignColors.backgroundLight)
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

                        // Learning Zone Section
                        if !viewModel.usedLearningApps.isEmpty {
                            learningZoneSection
                        }

                        // Play Zone Section
                        if !viewModel.usedRewardApps.isEmpty {
                            playZoneSection
                        }

                        // Empty state
                        if viewModel.activeChallenges.isEmpty &&
                           viewModel.usedLearningApps.isEmpty &&
                           viewModel.usedRewardApps.isEmpty {
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

// MARK: - Design Colors
private extension ChildDashboardView {
    struct DesignColors {
        static let primary = Color(hex: "13ec13")
        static let backgroundLight = Color(hex: "f6f8f6")
        static let backgroundDark = Color(hex: "102210")
        static let navyBlue = Color(hex: "1e293b")
        static let teal = Color(hex: "2dd4bf")
        static let sunnyYellow = Color(hex: "facc15")
        static let coral = Color(hex: "fb7185")
        static let skyBlue = Color(hex: "e0f2fe")

        // Context colors
        static let slate900 = Color(hex: "0f172a")
        static let slate800 = Color(hex: "1e293b")
        static let slate500 = Color(hex: "64748b")
        static let slate400 = Color(hex: "94a3b8")
        static let slate200 = Color(hex: "e2e8f0")
        static let slate700 = Color(hex: "334155")
        static let white = Color.white
        static let blue500 = Color(hex: "3b82f6")
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
                            gradient: Gradient(colors: [DesignColors.teal.opacity(0.3), DesignColors.coral.opacity(0.3)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(DesignColors.teal.opacity(0.5), lineWidth: 2)
                    )

                // Greeting
                Text("Hi Alex!")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.015 * 20)
                    .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)

                Spacer()

                // Points badge
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignColors.sunnyYellow)

                    Text("\(viewModel.learningRewardPoints)")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.015 * 18)
                        .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9999)
                        .fill(DesignColors.sunnyYellow.opacity(colorScheme == .dark ? 0.3 : 0.2))
                )
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
                .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Horizontal scrolling quest cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.activeChallenges.prefix(3).enumerated()), id: \.element.id) { index, challenge in
                        questCard(challenge: challenge, index: index)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    func questCard(challenge: Challenge, index: Int) -> some View {
        let colors = [
            (icon: "function", bgColor: DesignColors.teal, barColor: DesignColors.teal),
            (icon: "book", bgColor: DesignColors.coral, barColor: DesignColors.coral),
            (icon: "flask", bgColor: DesignColors.blue500, barColor: DesignColors.blue500)
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
                        .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)

                    Text(challenge.challengeDescription ?? "Complete the challenge")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? DesignColors.slate400 : DesignColors.slate500)
                }
            }

            HStack(spacing: 16) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 9999)
                            .fill(colorScheme == .dark ? DesignColors.slate700 : DesignColors.slate200)
                            .frame(height: 10)

                        RoundedRectangle(cornerRadius: 9999)
                            .fill(colorSet.barColor)
                            .frame(width: geometry.size.width * progressPercentage, height: 10)
                    }
                }
                .frame(height: 10)

                // Points reward
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18))
                        .foregroundColor(DesignColors.sunnyYellow)

                    Text("+\(challenge.bonusPercentage)% bonus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? DesignColors.slate200 : DesignColors.slate800)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? DesignColors.slate800 : .white)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }

    var learningZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Learning Zone")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.015 * 22)
                .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 12)

            // Learning apps list
            VStack(spacing: 8) {
                ForEach(viewModel.usedLearningApps) { snapshot in
                    learningAppRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        let progressPercentage = 0.75 // Placeholder, adjust based on actual data if available

        return HStack(spacing: 16) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(DesignColors.teal.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 36))
                            .foregroundColor(DesignColors.teal)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)

                Text("\(viewModel.formatTime(snapshot.totalSeconds))")
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? DesignColors.slate400 : DesignColors.slate500)
            }

            Spacer()

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 9999)
                        .fill(colorScheme == .dark ? DesignColors.slate700 : DesignColors.slate200)
                        .frame(width: 96, height: 8)

                    RoundedRectangle(cornerRadius: 9999)
                        .fill(DesignColors.teal)
                        .frame(width: 96 * progressPercentage, height: 8)
                }
            }
            .frame(width: 96, height: 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? DesignColors.slate800 : .white)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }

    var playZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Play Zone")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.015 * 22)
                .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 12)

            // Reward apps list
            VStack(spacing: 8) {
                ForEach(viewModel.usedRewardApps) { snapshot in
                    rewardAppRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        let isUnlocked = viewModel.unlockedRewardApps[snapshot.token] != nil

        return HStack(spacing: 16) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(DesignColors.coral.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 36))
                            .foregroundColor(DesignColors.coral)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)

                Text(isUnlocked ? "\(viewModel.formatTime(snapshot.totalSeconds)) unlocked" : "Complete a quest to unlock")
                    .font(.system(size: 14, weight: isUnlocked ? .medium : .regular))
                    .foregroundColor(isUnlocked ? DesignColors.teal : (colorScheme == .dark ? DesignColors.slate400 : DesignColors.slate500))
            }

            Spacer()

            // Lock/Play icon
            Circle()
                .fill(isUnlocked ? DesignColors.teal.opacity(colorScheme == .dark ? 0.2 : 0.1) : (colorScheme == .dark ? DesignColors.slate700 : DesignColors.slate200))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: isUnlocked ? "play.fill" : "lock.fill")
                        .foregroundColor(isUnlocked ? DesignColors.teal : DesignColors.slate500)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? DesignColors.slate800 : .white)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .opacity(isUnlocked ? 1.0 : 0.5)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 48)

            // Placeholder for friendly robot image
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [DesignColors.teal.opacity(0.2), DesignColors.coral.opacity(0.2)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 192, height: 144)
                .overlay(
                    Image(systemName: "face.smiling")
                        .font(.system(size: 72))
                        .foregroundColor(DesignColors.slate400)
                )

            Text("All Done for Now!")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : DesignColors.slate900)
                .padding(.top, 16)

            Text("Great job on finishing your quests! Ask a parent to add a new adventure for you.")
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? DesignColors.slate400 : DesignColors.slate500)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 280)
        }
        .padding(.horizontal, 16)
    }
}

