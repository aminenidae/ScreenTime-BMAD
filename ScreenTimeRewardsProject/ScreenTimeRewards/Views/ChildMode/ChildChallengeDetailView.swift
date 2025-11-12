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

                    // Progress Section with Chart
                    progressCard

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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
        }
        .task {
            await fetchAppProgressRecords()
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
                // Progress stats
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Text("\(progress.currentValue)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Text("\(progress.targetValue)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(goalTypeColor)
                    }
                }

                // Progress bar
                VStack(spacing: 8) {
                    HStack {
                        Text("\(Int(progress.progressPercentage))% Complete")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        Spacer()

                        Text("\(progress.targetValue - progress.currentValue) to go!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(goalTypeColor)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999)
                                .fill(AppTheme.progressTrack(for: colorScheme))
                                .frame(height: 20)

                            RoundedRectangle(cornerRadius: 999)
                                .fill(goalTypeColor)
                                .frame(width: geometry.size.width * min(progress.progressPercentage / 100, 1.0), height: 20)
                        }
                    }
                    .frame(height: 20)
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

                Text("Learning Apps")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            if learningAppSnapshots.isEmpty {
                Text("All learning apps count!")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.vertical, 8)
            } else {
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

                Text("\(formatTime(Int(snapshot.totalSeconds))) today")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.vibrantTeal)
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

            if rewardAppSnapshots.isEmpty {
                Text("No reward apps yet")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.vertical, 8)
            } else {
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

                Text("Earn \(unlockMinutesText)")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.playfulCoral)
                    .fontWeight(.semibold)
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))
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

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
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
}

// Now using centralized AppTheme
