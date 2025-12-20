import SwiftUI
import FamilyControls
import ManagedSettings

// Combined struct to prevent race condition in sheet presentation
private struct LearningConfigSheetData: Identifiable, Equatable {
    let snapshot: LearningAppSnapshot
    var config: AppScheduleConfiguration
    var id: String { snapshot.id }

    static func == (lhs: LearningConfigSheetData, rhs: LearningConfigSheetData) -> Bool {
        lhs.id == rhs.id
    }
}

struct LearningTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var tutorialManager: TutorialModeManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // App schedule configuration
    @StateObject private var scheduleService = AppScheduleService.shared

    // Sheet state
    @State private var selectedLearningSnapshot: LearningAppSnapshot?
    @State private var configSheetData: LearningConfigSheetData?  // Combined snapshot + config

    private var hasLearningApps: Bool {
        !viewModel.learningSnapshots.isEmpty
    }

    // Daily goal (challenges removed - return 0)
    private var dailyGoalMinutes: Int {
        return 0
    }

    // MARK: - Design Colors
    private var backgroundColor: Color {
        AppTheme.background(for: colorScheme)
    }

    private var cardColor: Color {
        AppTheme.card(for: colorScheme)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : AppTheme.vibrantTeal
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(hex: "8E8E93") : AppTheme.vibrantTeal.opacity(0.7)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            backgroundColor
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
                                .foregroundColor(primaryTextColor)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(primaryTextColor.opacity(0.1))
                                )
                        }

                        Spacer()

                        Text("LEARNING APPS")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(2)
                            .foregroundColor(primaryTextColor)

                        Spacer()

                        // Invisible spacer for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(primaryTextColor.opacity(0.15))
                        .frame(height: 1)
                }
                .background(backgroundColor)

                ScrollView {
                    VStack(spacing: 0) {
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        if !viewModel.learningSnapshots.isEmpty {
                            selectedAppsSection
                        }

                        // Bottom padding for FAB
                        Color.clear.frame(height: 100)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Floating Action Button
            addAppsButton
        }
        .refreshable {
            await viewModel.refresh()
        }
        // Detail view sheet (for configured apps)
        .sheet(item: $selectedLearningSnapshot) { snapshot in
            LearningAppDetailView(snapshot: snapshot)
        }
        // Configuration sheet
        .sheet(item: $configSheetData) { data in
            if tutorialManager.isActive {
                // Use tutorial wrapper with overlay support
                TutorialAppConfigurationSheet(
                    token: data.snapshot.token,
                    appName: data.snapshot.displayName,
                    appType: .learning,
                    learningSnapshots: [],
                    configuration: Binding(
                        get: { data.config },
                        set: { newConfig in
                            configSheetData = LearningConfigSheetData(snapshot: data.snapshot, config: newConfig)
                        }
                    ),
                    onSave: { savedConfig in
                        try? scheduleService.saveSchedule(savedConfig)
                        viewModel.blockRewardApps()
                        configSheetData = nil
                        // After save, advance to next major step (tapRewardsTab)
                        if tutorialManager.currentStep == .tapSaveLearning {
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
                    appType: .learning,
                    configuration: Binding(
                        get: { data.config },
                        set: { newConfig in
                            configSheetData = LearningConfigSheetData(snapshot: data.snapshot, config: newConfig)
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
            if newValue != nil && tutorialManager.isActive && tutorialManager.currentStep == .tapFirstLearningApp {
                tutorialManager.advanceStep()  // Move to configTimeWindowLearning
            }
        }
        // NOTE: Picker and sheet presentation handled by MainTabView to avoid conflicts
    }

    // MARK: - Helpers

    private func isConfigured(_ snapshot: LearningAppSnapshot) -> Bool {
        scheduleService.schedules[snapshot.logicalID] != nil
    }

    private func configSummary(for snapshot: LearningAppSnapshot) -> String? {
        scheduleService.schedules[snapshot.logicalID]?.displaySummary
    }

    private func openConfigSheet(for snapshot: LearningAppSnapshot) {
        let existingConfig = scheduleService.schedules[snapshot.logicalID]
            ?? AppScheduleConfiguration.defaultLearning(logicalID: snapshot.logicalID)
        // Set combined data atomically to prevent race condition
        configSheetData = LearningConfigSheetData(snapshot: snapshot, config: existingConfig)
    }

    private func handleAppTap(_ snapshot: LearningAppSnapshot) {
        if isConfigured(snapshot) {
            // Direct to detail view (configuration accessible from there)
            selectedLearningSnapshot = snapshot
        } else {
            // Open config sheet directly
            openConfigSheet(for: snapshot)
        }
    }

    // MARK: - Summary Card
    var summaryCard: some View {
        HStack(spacing: 16) {
            // Icon with background
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(primaryTextColor.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: "book.fill")
                    .font(.system(size: 26))
                    .foregroundColor(primaryTextColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY GOAL")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(secondaryTextColor)

                HStack(alignment: .bottom, spacing: 8) {
                    Text("\(dailyGoalMinutes)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(primaryTextColor)

                    Text("MINUTES")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                        .padding(.bottom, 4)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }

    // MARK: - Selected Apps Section
    var selectedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 18))
                    .foregroundColor(primaryTextColor)

                Text("LEARNING APPS")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(primaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)

            // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
            let columns = horizontalSizeClass == .regular ? [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ] : [
                GridItem(.flexible())
            ]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(viewModel.learningSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    learningAppRow(snapshot: snapshot)
                        .tutorialTarget(index == 0 ? "first_learning_app" : "")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - App Row
    @ViewBuilder
    func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        // Standardized icon sizes (50% reduction)
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24
        let configured = isConfigured(snapshot)

        Button {
            handleAppTap(snapshot)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(iconScale)
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(primaryTextColor.opacity(0.1))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: fallbackIconSize))
                                    .foregroundColor(primaryTextColor)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if #available(iOS 15.2, *) {
                            Label(snapshot.token)
                                .labelStyle(.titleOnly)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                        } else {
                            Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        // Show different content based on configuration status
                        if configured {
                            // Configured: show usage time and config summary
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(secondaryTextColor)

                                Text(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(secondaryTextColor)

                                if let summary = configSummary(for: snapshot) {
                                    Text("•")
                                        .foregroundColor(secondaryTextColor.opacity(0.5))
                                    Text(summary)
                                        .font(.system(size: 11))
                                        .foregroundColor(secondaryTextColor.opacity(0.8))
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    // Chevron indicator
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(configured ? secondaryTextColor : AppTheme.sunnyYellow)
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(configured ? (colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme)) : AppTheme.sunnyYellow.opacity(0.5), lineWidth: configured ? 1 : 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Apps Button (FAB)
    var addAppsButton: some View {
        VStack(spacing: 0) {
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    backgroundColor.opacity(0),
                    backgroundColor
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                // If in tutorial and this is the current target, advance the step
                if tutorialManager.isActive && tutorialManager.isCurrentTarget("add_learning_apps") {
                    tutorialManager.completeCurrentStep()
                }
                viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                viewModel.presentPickerWithRetry(for: .learning)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("MANAGE APPS")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(colorScheme == .dark ? Color.black : AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.vibrantTeal)
                )
                .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .tutorialTarget("add_learning_apps")
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(backgroundColor)
        }
    }

}

struct LearningTabView_Previews: PreviewProvider {
    static var previews: some View {
        LearningTabView()
            .environmentObject(AppUsageViewModel())
            .environmentObject(SessionManager.shared)
    }
}
