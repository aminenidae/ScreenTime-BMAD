import SwiftUI
import FamilyControls
import ManagedSettings
import CoreData

struct ChildChallengeDetailView: View {
    let challenge: Challenge
    let progress: ChallengeProgress?
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var appProgressRecords: [AppProgress] = []
    @State private var streakRecord: StreakRecord?

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Challenge Description (Kid-friendly)
                    descriptionCard

                    // Streak Card (if streak bonus is enabled)
                    if challenge.streakBonusEnabled {
                        streakCard
                    }

                    // Per-App Progress (only for per-app tracking mode)
                    if challenge.isPerAppTracking && !appProgressRecords.isEmpty {
                        PerAppProgressView(
                            challenge: challenge,
                            appProgressRecords: appProgressRecords,
                            learningSnapshots: viewModel.learningSnapshots
                        )
                    }

                    // Learning Apps Section
                    learningAppsSection

                    // Reward Apps Section
                    rewardAppsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAppProgressRecords()
            await fetchStreakRecord()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(goalTypeColor.opacity(colorScheme == .dark ? 0.3 : 0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: goalTypeIcon)
                    .font(.system(size: 40))
                    .foregroundColor(goalTypeColor)
            }

            // Title
            Text(challenge.title ?? "Challenge")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Description Card
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Your Mission")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            Text(kidFriendlyDescription)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .lineSpacing(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Progress Card
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Your Progress")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            if let progress = progress {
                VStack(spacing: 16) {
                    // Circular Progress
                    ZStack {
                        // Background circle
                        Circle()
                            .stroke(
                                Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2),
                                lineWidth: 14
                            )
                            .frame(width: 160, height: 160)

                        // Progress circle
                        Circle()
                            .trim(from: 0, to: min(progress.progressPercentage / 100, 1.0))
                            .stroke(
                                goalTypeColor,
                                style: StrokeStyle(
                                    lineWidth: 14,
                                    lineCap: .round
                                )
                            )
                            .frame(width: 160, height: 160)
                            .rotationEffect(.degrees(-90))

                        // Center content
                        VStack(spacing: 4) {
                            Text("\(min(Int(progress.progressPercentage), 100))%")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text("\(progress.currentValue)/\(progress.targetValue)m")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // To go text (or completed message)
                    if progress.currentValue >= progress.targetValue {
                        Text("Goal completed! 🎉")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(goalTypeColor)
                    } else {
                        Text("\(progress.targetValue - progress.currentValue) to go!")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(goalTypeColor)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Learning Apps Section
    private var learningAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Your Learnings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            // Show total usage with progress bar
            let totalLearningSeconds = learningAppSnapshots.reduce(0) { $0 + $1.totalSeconds }
            let totalLearningMinutes = Int(totalLearningSeconds / 60)
            let targetMinutes = Int(progress?.targetValue ?? 0)
            let learningProgress = targetMinutes > 0 ? min(Double(totalLearningMinutes) / Double(targetMinutes), 1.0) : 0.0
            let learningPercentage = Int(learningProgress * 100)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Total Usage Today")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    Spacer()

                    Text("\(learningPercentage)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                            .frame(height: 10)

                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.vibrantTeal)
                            .frame(width: geometry.size.width * learningProgress, height: 10)
                    }
                }
                .frame(height: 10)

                Text("\(totalLearningMinutes) / \(targetMinutes) minutes goal")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.vertical, 8)

            // Individual learning app cards
            if !learningAppSnapshots.isEmpty {
                VStack(spacing: 12) {
                    ForEach(learningAppSnapshots) { snapshot in
                        learningAppRow(snapshot: snapshot)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    private func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        HStack(spacing: 12) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.35)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                // App name (will show from Label API)
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                }

                Text("\(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds)) today")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.vibrantTeal.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
    }

    // MARK: - Reward Apps Section
    private var rewardAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("Your Rewards")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            // Show total reward usage with progress bar
            let totalRewardSeconds = rewardAppSnapshots.reduce(0) { $0 + $1.totalSeconds }
            let totalRewardMinutes = Int(totalRewardSeconds / 60)
            let maxRewardMinutes = challenge.rewardUnlockMinutes()
            let rewardProgress = maxRewardMinutes > 0 ? min(Double(totalRewardMinutes) / Double(maxRewardMinutes), 1.0) : 0.0
            let rewardPercentage = Int(rewardProgress * 100)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Total Used Today")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    Spacer()

                    Text("\(rewardPercentage)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.playfulCoral)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                            .frame(height: 10)

                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.playfulCoral)
                            .frame(width: geometry.size.width * rewardProgress, height: 10)
                    }
                }
                .frame(height: 10)

                Text("\(totalRewardMinutes) / \(maxRewardMinutes) minutes unlocked")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.vertical, 8)

            if !rewardAppSnapshots.isEmpty {
                VStack(spacing: 12) {
                    ForEach(rewardAppSnapshots) { snapshot in
                        rewardAppRow(snapshot: snapshot)
                    }
                }
            }

            // Bonus callout
            if challenge.bonusPercentage > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.sunnyYellow)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bonus Time!")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        Text("Complete today and get +\(challenge.bonusPercentage)% extra reward time!")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.sunnyYellow.opacity(colorScheme == .dark ? 0.2 : 0.1))
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    private func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        HStack(spacing: 12) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.35)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                // App name
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                }

                Text("\(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds)) used today")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.playfulCoral.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
    }

    // MARK: - Helpers

    private var kidFriendlyDescription: String {
        let target = Int(challenge.targetValue)
        switch challenge.goalTypeEnum {
        case .dailyQuest:
            return "Spend \(target) minutes learning today and unlock awesome rewards! The more you learn, the more you can play. You've got this! 🌟"
        case .none:
            return "Complete this challenge to unlock amazing rewards. You're doing great - keep going! 🚀"
        }
    }

    private var goalTypeIcon: String {
        challenge.goalTypeEnum?.iconName ?? "flag.fill"
    }

    private var goalTypeColor: Color {
        challenge.goalTypeEnum?.accentColor ?? AppTheme.vibrantTeal
    }

    private var learningAppSnapshots: [LearningAppSnapshot] {
        let appIDs = challenge.targetAppIDs
        if appIDs.isEmpty {
            return viewModel.learningSnapshots
        }
        return viewModel.learningSnapshots.filter { appIDs.contains($0.logicalID) }
    }

    private var rewardAppSnapshots: [RewardAppSnapshot] {
        let appIDs = challenge.rewardAppIDs
        return viewModel.rewardSnapshots.filter { appIDs.contains($0.logicalID) }
    }

    private var unlockMinutesText: String {
        let minutes = challenge.rewardUnlockMinutes()
        let bonus = challenge.bonusPercentage

        if bonus > 0 {
            let bonusMinutes = Int(Double(minutes) * (1.0 + Double(bonus) / 100.0))
            return "\(minutes) min (+\(bonusMinutes - minutes) bonus)"
        }
        return "\(minutes) min"
    }

    private func fetchAppProgressRecords() async {
        guard let challengeID = challenge.challengeID else { return }

        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = AppProgress.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "challengeID == %@", challengeID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "appLogicalID", ascending: true)]

        do {
            let records = try await context.perform {
                try context.fetch(fetchRequest)
            }
            await MainActor.run {
                appProgressRecords = records
            }
        } catch {
            print("[ChildChallengeDetailView] Error fetching app progress: \(error)")
        }
    }

    private func fetchStreakRecord() async {
        let deviceID = DeviceModeManager.shared.deviceID
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = StreakRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "childDeviceID == %@", deviceID)
        fetchRequest.fetchLimit = 1

        do {
            let records = try await context.perform {
                try context.fetch(fetchRequest)
            }
            await MainActor.run {
                streakRecord = records.first
            }
        } catch {
            print("[ChildChallengeDetailView] Error fetching streak record: \(error)")
        }
    }

    // MARK: - Streak Card
    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Streak Progress")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            let currentStreak = Int(streakRecord?.currentStreak ?? 0)
            let targetDays = Int(challenge.streakTargetDays)
            let bonusPercentage = Int(challenge.streakBonusPercentage)
            let streakProgress = min(Double(currentStreak) / Double(targetDays), 1.0)

            HStack(spacing: 20) {
                // Streak icon and count
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.sunnyYellow.opacity(colorScheme == .dark ? 0.3 : 0.2))
                            .frame(width: 70, height: 70)

                        VStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppTheme.sunnyYellow)

                            Text("\(currentStreak)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                    }

                    Text("Day Streak")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Progress bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Progress to Bonus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Spacer()

                            Text("\(currentStreak)/\(targetDays) days")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                                    .frame(height: 12)

                                // Progress
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.sunnyYellow)
                                    .frame(width: geometry.size.width * streakProgress, height: 12)
                            }
                        }
                        .frame(height: 12)
                    }

                    // Bonus info
                    if currentStreak >= targetDays {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)

                            Text("+\(bonusPercentage)% bonus unlocked!")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.sunnyYellow)

                            Text("Reach \(targetDays) days for +\(bonusPercentage)% bonus!")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

// Now using centralized AppTheme
