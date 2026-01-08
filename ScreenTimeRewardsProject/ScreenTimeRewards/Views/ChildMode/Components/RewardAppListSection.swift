import SwiftUI
import FamilyControls
import ManagedSettings

/// Section displaying reward apps with usage times and unlock status
struct RewardAppListSection: View {
    let snapshots: [RewardAppSnapshot]
    let remainingMinutes: Int
    let unlockedApps: [ApplicationToken: UnlockedRewardApp]

    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = true
    @State private var selectedApp: RewardDetailData?

    private struct RewardDetailData: Identifiable {
        let snapshot: RewardAppSnapshot
        let unlockedApp: UnlockedRewardApp?
        let config: AppScheduleConfiguration?
        var id: String { snapshot.id }
    }

    private var totalUsedSeconds: TimeInterval {
        snapshots.reduce(0) { $0 + $1.totalSeconds }
    }

    private var totalUsedMinutes: Int {
        Int(totalUsedSeconds / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            sectionHeader

            // App list
            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        rewardAppRow(snapshot: snapshot)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: isExpanded)
                    }
                }
            }

            // Empty state
            if snapshots.isEmpty {
                emptyState
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.playfulCoral.opacity(0.1), lineWidth: 1)
                )
        )
        .sheet(item: $selectedApp) { detailData in
            ChildAppDetailView(
                snapshot: detailData.snapshot,
                unlockedApp: detailData.unlockedApp,
                linkedLearningApps: filterValidLinkedApps(for: detailData.config),
                learningProgress: calculateLearningProgress(for: detailData.config),
                learningAppTokens: resolveLearningTokens(for: detailData.config),
                unlockMode: detailData.config?.unlockMode ?? .all,
                streakSettings: detailData.config?.streakSettings,
                dailyLimit: detailData.config?.dailyLimits.todayLimit ?? 60,
                previousDayUsage: nil // Would fetch from historical data
            )
        }
    }

    private func calculateLearningProgress(for config: AppScheduleConfiguration?) -> [String: (used: Int, required: Int, goalMet: Bool)] {
        guard let config = config else { return [:] }
        var progress: [String: (used: Int, required: Int, goalMet: Bool)] = [:]

        // Only calculate progress for linked apps that have valid learning snapshots
        let validLinkedApps = filterValidLinkedApps(for: config)
        for linkedApp in validLinkedApps {
            // Find usage from snapshots
            let usedSeconds = viewModel.learningSnapshots.first(where: { $0.logicalID == linkedApp.logicalID })?.totalSeconds ?? 0
            let usedMinutes = Int(usedSeconds / 60)
            let goalMet = usedMinutes >= linkedApp.minutesRequired
            progress[linkedApp.logicalID] = (usedMinutes, linkedApp.minutesRequired, goalMet)
        }

        return progress
    }

    private func resolveLearningTokens(for config: AppScheduleConfiguration?) -> [String: ApplicationToken] {
        guard let config = config else { return [:] }
        var tokens: [String: ApplicationToken] = [:]

        for linkedApp in config.linkedLearningApps {
            if let snapshot = viewModel.learningSnapshots.first(where: { $0.logicalID == linkedApp.logicalID }) {
                tokens[linkedApp.logicalID] = snapshot.token
            }
        }

        return tokens
    }

    /// Filter linked apps to only include those with valid learning snapshots on device
    private func filterValidLinkedApps(for config: AppScheduleConfiguration?) -> [LinkedLearningApp] {
        guard let config = config else { return [] }

        // Only include linked apps that have a corresponding learning snapshot
        return config.linkedLearningApps.filter { linkedApp in
            viewModel.learningSnapshots.contains { $0.logicalID == linkedApp.logicalID }
        }
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.playfulCoral)

                // Title
                Text("REWARD APPS")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Remaining time badge
                HStack(spacing: 4) {
                    Image(systemName: remainingMinutes > 0 ? "clock.fill" : "clock")
                        .font(.system(size: 11))
                    Text("\(remainingMinutes) MIN LEFT")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(remainingMinutes > 0 ? AppTheme.playfulCoral : AppTheme.textSecondary(for: colorScheme))

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
    }

    private func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        // App is unlocked if it's in the manual unlock list OR if goals are met (blocking condition clear)
        let isManuallyUnlocked = unlockedApps[snapshot.token] != nil
        let isGoalUnlocked = BlockingCoordinator.shared.canUnlockApp(token: snapshot.token)
        let isUnlocked = isManuallyUnlocked || isGoalUnlocked
        
        let usedMinutes = Int(snapshot.totalSeconds / 60)

        return HStack(spacing: 12) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.35)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
            }

            // App name and status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    } else {
                        Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    }
                }

                // Status text
                // Status text
                if isUnlocked {
                    Text("\(usedMinutes) MIN USED")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else {
                    // Check if there is a specific blocking reason
                    let blockingState = BlockingCoordinator.shared.evaluateBlockingState(for: snapshot.token)
                    
                    if let reason = blockingState.primaryReason {
                        switch reason {
                        case .learningGoal:
                            Text("COMPLETE GOAL TO UNLOCK")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        case .downtime:
                            Text("APP IN DOWNTIME")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        case .dailyLimitReached:
                            Text("DAILY LIMIT REACHED")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        case .rewardTimeExpired:
                            Text("TIME EXPIRED")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    } else {
                        // Not blocked by system constraints, just waiting for manual unlock
                        if remainingMinutes > 0 {
                            Text("TAP TO UNLOCK")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.playfulCoral)
                        } else {
                            Text("NO TIME REMAINING")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }
            }

            Spacer()

            // Lock/unlock indicator
            if isUnlocked {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.playfulCoral)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.playfulCoral.opacity(0.05))
        )
        .opacity(remainingMinutes > 0 || isUnlocked ? 1.0 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            let config = AppScheduleService.shared.getSchedule(for: snapshot.logicalID)
            selectedApp = RewardDetailData(
                snapshot: snapshot,
                unlockedApp: unlockedApps[snapshot.token],
                config: config
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))

            Text("No reward apps configured")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("Ask a parent to set up reward apps for you!")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // With remaining time
            RewardAppListSection(
                snapshots: [],
                remainingMinutes: 25,
                unlockedApps: [:]
            )

            // No remaining time
            RewardAppListSection(
                snapshots: [],
                remainingMinutes: 0,
                unlockedApps: [:]
            )

            // Empty state
            RewardAppListSection(
                snapshots: [],
                remainingMinutes: 0,
                unlockedApps: [:]
            )
        }
        .padding()
    }
    .background(AppTheme.background(for: .light))
}
