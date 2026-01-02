import SwiftUI
import FamilyControls
import ManagedSettings

// Combined struct to prevent race condition in sheet presentation
private struct RewardConfigSheetData: Identifiable, Equatable {
    let snapshot: RewardAppSnapshot
    var config: AppScheduleConfiguration
    var id: String { snapshot.id }

    static func == (lhs: RewardConfigSheetData, rhs: RewardConfigSheetData) -> Bool {
        lhs.id == rhs.id
    }
}

struct RewardsTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Use shared view model
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var tutorialManager: TutorialModeManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // App schedule configuration
    @StateObject private var scheduleService = AppScheduleService.shared

    // Sheet state
    @State private var selectedRewardSnapshot: RewardAppSnapshot?
    @State private var configSheetData: RewardConfigSheetData?  // Combined snapshot + config

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header
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

                        Text("REWARD APPS")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(2)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))

                        Spacer()

                        // Invisible spacer for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(AppTheme.brandedText(for: colorScheme).opacity(0.15))
                        .frame(height: 1)
                }
                .background(AppTheme.background(for: colorScheme))

                ScrollView {
                    VStack(spacing: 0) {
                        // Points Summary Card
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        // Section Header
                        HStack(spacing: 8) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.playfulCoral)

                            Text("YOUR REWARDS")
                                .font(.system(size: 14, weight: .semibold))
                                .tracking(1.5)
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                        // List of Reward Apps
                        rewardAppsSection
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 96)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            addAppsButton
        }
        .refreshable {
            await viewModel.refresh()
        }
        // Detail view sheet (for configured apps)
        .sheet(item: $selectedRewardSnapshot) { snapshot in
            RewardAppDetailView(snapshot: snapshot)
        }
        // Configuration sheet
        .sheet(item: $configSheetData) { data in
            if tutorialManager.isActive {
                // Use tutorial wrapper with overlay support
                TutorialAppConfigurationSheet(
                    token: data.snapshot.token,
                    appName: data.snapshot.displayName,
                    appType: .reward,
                    learningSnapshots: viewModel.learningSnapshots,
                    configuration: Binding(
                        get: { data.config },
                        set: { newConfig in
                            configSheetData = RewardConfigSheetData(snapshot: data.snapshot, config: newConfig)
                        }
                    ),
                    onSave: { savedConfig in
                        try? scheduleService.saveSchedule(savedConfig)
                        viewModel.blockRewardApps()
                        configSheetData = nil
                        // After save, advance to final settings step
                        if tutorialManager.currentStep == .tapSaveReward {
                            tutorialManager.advanceStep()
                        }
                    },
                    onCancel: {
                        configSheetData = nil
                    }
                )
                .environmentObject(tutorialManager)
                .interactiveDismissDisabled(true)  // Prevent swipe-to-dismiss during tutorial
            } else {
                // Normal config sheet
                AppConfigurationSheet(
                    token: data.snapshot.token,
                    appName: data.snapshot.displayName,
                    appType: .reward,
                    learningSnapshots: viewModel.learningSnapshots,
                    configuration: Binding(
                        get: { data.config },
                        set: { newConfig in
                            configSheetData = RewardConfigSheetData(snapshot: data.snapshot, config: newConfig)
                        }
                    ),
                    onSave: { savedConfig in
                        try? scheduleService.saveSchedule(savedConfig)
                        viewModel.blockRewardApps()
                        configSheetData = nil
                    },
                    onCancel: {
                        configSheetData = nil
                    }
                )
            }
        }
        // Advance tutorial when config sheet opens
        .onChange(of: configSheetData) { newValue in
            if newValue != nil && tutorialManager.isActive && tutorialManager.currentStep == .tapFirstRewardApp {
                tutorialManager.advanceStep()  // Move to configTimeWindowReward
            }
        }
        // NOTE: Picker and sheet presentation handled by MainTabView to avoid conflicts
    }

    // MARK: - Summary Card

    var summaryCard: some View {
        HStack(spacing: 16) {
            // Icon with background
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.playfulCoral.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: "gift.fill")
                    .font(.system(size: 26))
                    .foregroundColor(AppTheme.playfulCoral)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY USAGE TIME")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))

                HStack(alignment: .bottom, spacing: 8) {
                    Text("\(Int(viewModel.rewardTime / 60))")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("MINUTES")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                        .padding(.bottom, 4)
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("\(viewModel.availableLearningPoints) MINUTES AVAILABLE")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.sunnyYellow)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.playfulCoral.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func isConfigured(_ snapshot: RewardAppSnapshot) -> Bool {
        scheduleService.schedules[snapshot.logicalID] != nil
    }

    private func configSummary(for snapshot: RewardAppSnapshot) -> String? {
        scheduleService.schedules[snapshot.logicalID]?.displaySummary
    }

    private func openConfigSheet(for snapshot: RewardAppSnapshot) {
        // Reward apps get stricter default limits
        let existingConfig = scheduleService.schedules[snapshot.logicalID]
            ?? AppScheduleConfiguration.defaultReward(logicalID: snapshot.logicalID)
        // Set combined data atomically to prevent race condition
        configSheetData = RewardConfigSheetData(snapshot: snapshot, config: existingConfig)
    }

    private func handleAppTap(_ snapshot: RewardAppSnapshot) {
        if isConfigured(snapshot) {
            // Direct to detail view (configuration accessible from there)
            selectedRewardSnapshot = snapshot
        } else {
            // Open config sheet directly
            openConfigSheet(for: snapshot)
        }
    }
}

private extension RewardsTabView {
    var addAppsButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.background(for: colorScheme).opacity(0),
                    AppTheme.background(for: colorScheme)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                // If in tutorial and this is the current target, advance the step
                if tutorialManager.isActive && tutorialManager.isCurrentTarget("add_reward_apps") {
                    tutorialManager.completeCurrentStep()
                }
                viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                viewModel.presentPickerWithRetry(for: .reward)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("/")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                    Text("REWARD APPS")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.playfulCoral)
                )
                .shadow(color: AppTheme.playfulCoral.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .tutorialTarget("add_reward_apps")
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
        }
    }

    var rewardAppsSection: some View {
        Group {
            if !viewModel.rewardSnapshots.isEmpty {
                // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
                let columns = horizontalSizeClass == .regular ? [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ] : [
                    GridItem(.flexible())
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(viewModel.rewardSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        rewardAppRow(snapshot: snapshot)
                            .tutorialTarget(index == 0 ? "first_reward_app" : "")
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))

                    Text("No reward apps selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            }
        }
    }

    @ViewBuilder
    func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24
        let configured = isConfigured(snapshot)

        Button {
            handleAppTap(snapshot)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(iconScale)
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.playfulCoral.opacity(0.1))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: fallbackIconSize))
                                    .foregroundColor(AppTheme.playfulCoral)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if #available(iOS 15.2, *) {
                            Label(snapshot.token)
                                .labelStyle(.titleOnly)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        } else {
                            Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        // Show different content based on configuration status
                        if configured {
                            // Configured: show usage time and config summary
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.playfulCoral.opacity(0.8))

                                Text(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.playfulCoral)

                                if let summary = configSummary(for: snapshot) {
                                    Text("•")
                                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
                                    Text(summary)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            // Unconfigured: show warning
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.sunnyYellow)

                                Text("TAP TO CONFIGURE")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.sunnyYellow)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(configured ? AppTheme.brandedText(for: colorScheme).opacity(0.5) : AppTheme.sunnyYellow)
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(configured ? AppTheme.playfulCoral.opacity(0.15) : AppTheme.sunnyYellow.opacity(0.5), lineWidth: configured ? 1 : 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}


struct RewardsTabView_Previews: PreviewProvider {
    static var previews: some View {
        RewardsTabView()
            .environmentObject(AppUsageViewModel())  // Provide a view model for previews
            .environmentObject(SessionManager.shared)
    }
}
