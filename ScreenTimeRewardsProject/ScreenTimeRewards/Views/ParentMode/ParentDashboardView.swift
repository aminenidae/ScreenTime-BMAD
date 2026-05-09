import SwiftUI

/// Parent dashboard view for local (child device) context.
/// Uses LocalDashboardDataAdapter to provide data to the unified dashboard.
struct ParentDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

    @StateObject private var dataAdapter: LocalDashboardDataAdapter

    init() {
        // Initialize with a temporary adapter - will be replaced on appear
        _dataAdapter = StateObject(wrappedValue: LocalDashboardDataAdapter(
            viewModel: AppUsageViewModel()
        ))
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Section 1: Time Bank
                        TimeBankCard(
                            earnedMinutes: dataAdapter.earnedMinutes + dataAdapter.streakBonusMinutes,
                            usedMinutes: dataAdapter.usedMinutes,
                            availableMinutes: dataAdapter.availableMinutes
                        )

                        // Section 2: Card-per-reward (mirrors child dashboard layout —
                        // each reward shows its linked-learning requirements + progress
                        // directly underneath, replacing the hidden "Today's Activity" grouping).
                        ForEach(viewModel.rewardSnapshots, id: \.id) { rewardSnapshot in
                            RewardUnlockCard(
                                snapshot: rewardSnapshot,
                                unlockedApp: viewModel.unlockedRewardApps[rewardSnapshot.token],
                                remainingMinutes: viewModel.cumulativeAvailableMinutes,
                                pulseWhenUnlocked: false
                            )
                        }

                        // Section 3: Streaks Summary
                        StreaksSummarySection(dataProvider: dataAdapter)

                        // Section 4: Daily/Weekly Trends (existing chart)
                        DailyUsageChartCard()

                        // Bottom padding
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .onAppear {
            // Update the adapter with the actual view model from environment
            updateAdapter()
            tryFirePromptForCurrentState()
        }
        .onChange(of: dataAdapter.earnedMinutes) { _ in
            tryFirePromptForCurrentState()
        }
        .onChange(of: dataAdapter.currentStreak) { _ in
            tryFirePromptForCurrentState()
        }
    }

    /// Prefer the stronger delight trigger (firstWeeklyWin) when both are eligible.
    /// Don't fire the weaker trigger after the stronger one has already consumed a slot.
    private func tryFirePromptForCurrentState() {
        let service = RatingPromptService.shared

        let d = UserDefaults(suiteName: "group.com.screentimerewards.shared")
        let fpsFlag = d?.bool(forKey: "rating_prompt_fired_firstParentSuccess_v1") ?? false
        let fwwFlag = d?.bool(forKey: "rating_prompt_fired_firstWeeklyWin_v1") ?? false
        let legacyFlag = d?.bool(forKey: "rating_prompt_fired_v1") ?? false
        print("[RatingDebug] tryFire earned=\(dataAdapter.earnedMinutes) streak=\(dataAdapter.currentStreak) fpsFlag=\(fpsFlag) fwwFlag=\(fwwFlag) legacy=\(legacyFlag)")

        if dataAdapter.currentStreak >= 3 {
            service.requestReviewIfEligible(trigger: .firstWeeklyWin)
            return
        }

        if dataAdapter.earnedMinutes > 0 && !service.hasFired(trigger: .firstWeeklyWin) {
            service.requestReviewIfEligible(trigger: .firstParentSuccess)
        }
    }

    private func updateAdapter() {
        // Create new adapter with the actual EnvironmentObject viewModel
        // This is a workaround since we can't directly inject EnvironmentObject into StateObject
        Task { @MainActor in
            dataAdapter.updateViewModel(viewModel)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    sessionManager.exitToSelection()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.vibrantTeal.opacity(0.1))
                        )
                }
                .accessibilityLabel("Go back")

                Spacer()

                Text("DASHBOARD")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Invisible spacer for balance
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Rectangle()
                .fill(AppTheme.border(for: colorScheme))
                .frame(height: 1)
        }
        .background(AppTheme.background(for: colorScheme))
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ParentDashboardView()
            .environmentObject(AppUsageViewModel())
            .environmentObject(SessionManager.shared)
    }
}
