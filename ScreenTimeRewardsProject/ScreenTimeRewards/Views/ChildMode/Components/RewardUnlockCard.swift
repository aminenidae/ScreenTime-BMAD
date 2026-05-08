import SwiftUI
import FamilyControls
import ManagedSettings

/// One card per reward app that surfaces the unlock requirements (linked learning apps + progress)
/// directly on the dashboard. Replaces the old single-section grouping that hid linkage behind a sheet.
struct RewardUnlockCard: View {
    let snapshot: RewardAppSnapshot
    let unlockedApp: UnlockedRewardApp?
    let remainingMinutes: Int

    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var showDetail = false
    @State private var unlockedGlow: Double = 0.35

    private var config: AppScheduleConfiguration? {
        AppScheduleService.shared.getSchedule(for: snapshot.logicalID)
    }

    private var validLinkedApps: [LinkedLearningApp] {
        guard let config = config else { return [] }
        return config.linkedLearningApps.filter { linkedApp in
            viewModel.learningSnapshots.contains { $0.logicalID == linkedApp.logicalID }
        }
    }

    private var learningProgress: [String: (used: Int, required: Int, goalMet: Bool)] {
        var progress: [String: (used: Int, required: Int, goalMet: Bool)] = [:]
        for linkedApp in validLinkedApps {
            let usedSeconds = viewModel.learningSnapshots.first(where: { $0.logicalID == linkedApp.logicalID })?.totalSeconds ?? 0
            let usedMinutes = Int(usedSeconds / 60)
            let goalMet = usedMinutes >= linkedApp.minutesRequired
            progress[linkedApp.logicalID] = (usedMinutes, linkedApp.minutesRequired, goalMet)
        }
        return progress
    }

    private var learningTokens: [String: ApplicationToken] {
        var tokens: [String: ApplicationToken] = [:]
        for linkedApp in (config?.linkedLearningApps ?? []) {
            if let learningSnapshot = viewModel.learningSnapshots.first(where: { $0.logicalID == linkedApp.logicalID }) {
                tokens[linkedApp.logicalID] = learningSnapshot.token
            }
        }
        return tokens
    }

    private var isUnlocked: Bool {
        let isManuallyUnlocked = unlockedApp != nil
        let isGoalUnlocked = BlockingCoordinator.shared.canUnlockApp(token: snapshot.token)
        return isManuallyUnlocked || isGoalUnlocked
    }

    private var usedMinutes: Int {
        Int(snapshot.totalSeconds / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            if !validLinkedApps.isEmpty {
                Rectangle()
                    .fill(AppTheme.playfulCoral.opacity(0.12))
                    .frame(height: 1)
                    .padding(.vertical, 12)

                unlockSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(
                    color: isUnlocked ? AppTheme.playfulCoral.opacity(unlockedGlow) : .clear,
                    radius: 10
                )
        )
        .overlay(borderOverlay)
        .contentShape(Rectangle())
        .onTapGesture {
            showDetail = true
        }
        .onAppear {
            // Subtle "ready to play" pulse on unlocked cards. Locked cards stay still.
            if isUnlocked {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    unlockedGlow = 0.75
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            ChildAppDetailView(
                snapshot: snapshot,
                unlockedApp: unlockedApp,
                linkedLearningApps: validLinkedApps,
                learningProgress: learningProgress,
                learningAppTokens: learningTokens,
                unlockMode: config?.unlockMode ?? .all,
                streakSettings: config?.streakSettings,
                dailyLimit: config?.dailyLimits.todayLimit ?? 60,
                previousDayUsage: nil
            )
        }
    }

    // MARK: - Border

    @ViewBuilder
    private var borderOverlay: some View {
        if isUnlocked {
            // Unlocked: solid coral border (the glow comes from the shadow above).
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.playfulCoral, lineWidth: 2)
        } else {
            // Locked: dashed teal border — clear "in progress" cue, full readability.
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    AppTheme.vibrantTeal.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.5)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                }

                statusText
            }

            Spacer()

            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isUnlocked ? AppTheme.playfulCoral : AppTheme.brandedText(for: colorScheme))
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if isUnlocked {
            Text("\(usedMinutes) MIN USED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        } else {
            let blockingState = BlockingCoordinator.shared.evaluateBlockingState(for: snapshot.token)
            if let reason = blockingState.primaryReason {
                Text(text(for: reason))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            } else if remainingMinutes > 0 {
                Text("TAP TO UNLOCK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.playfulCoral)
            } else {
                Text("NO TIME REMAINING")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
    }

    private func text(for reason: BlockingReasonType) -> String {
        switch reason {
        case .learningGoal: return "COMPLETE GOAL TO UNLOCK"
        case .downtime: return "APP IN DOWNTIME"
        case .dailyLimitReached: return "DAILY LIMIT REACHED"
        case .rewardTimeExpired: return "TIME EXPIRED"
        }
    }

    // MARK: - Unlock section (linked learning apps)

    private var unlockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Mode badge only when there's a real choice to communicate (2+ apps).
            // With a single linked app, "DO ALL" / "PICK ONE" is meaningless noise.
            if validLinkedApps.count >= 2, let mode = config?.unlockMode {
                HStack(spacing: 6) {
                    Image(systemName: mode == .all ? "checkmark.circle.fill" : "hand.point.up.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(mode == .all ? "DO ALL" : "PICK ONE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(AppTheme.vibrantTeal)
            }

            ForEach(validLinkedApps, id: \.logicalID) { linkedApp in
                linkedLearningRow(linkedApp: linkedApp)
            }
        }
    }

    private func linkedLearningRow(linkedApp: LinkedLearningApp) -> some View {
        let progress = learningProgress[linkedApp.logicalID] ?? (used: 0, required: linkedApp.minutesRequired, goalMet: false)
        let token = learningTokens[linkedApp.logicalID]

        return HStack(spacing: 10) {
            if #available(iOS 15.2, *), let token = token {
                Label(token)
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.vibrantTeal.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.vibrantTeal)
                    )
            }

            if #available(iOS 15.2, *), let token = token {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            } else {
                Text(linkedApp.displayName ?? "Learning App")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("\(progress.used) / \(progress.required)m")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(progress.goalMet ? AppTheme.vibrantTeal : AppTheme.textPrimary(for: colorScheme))
                    .monospacedDigit()
                Image(systemName: progress.goalMet ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(progress.goalMet ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme).opacity(0.4))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(progress.goalMet ? AppTheme.vibrantTeal.opacity(0.1) : AppTheme.vibrantTeal.opacity(0.04))
        )
    }
}
