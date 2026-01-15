import SwiftUI
import FamilyControls

/// Container view that wraps MainTabView with the tutorial overlay
/// Manages the guided tutorial flow and coordinates with the main app
struct GuidedTutorialContainerView: View {
    @StateObject private var tutorialManager = TutorialModeManager.shared
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    /// Callback when tutorial completes successfully
    let onTutorialComplete: () -> Void

    var body: some View {
        ZStack {
            // The actual MainTabView (in parent mode for configuration)
            TutorialMainTabView(selectedTab: $tutorialManager.forcedTabIndex)
                .environmentObject(appUsageViewModel)
                .environmentObject(sessionManager)
                .environmentObject(subscriptionManager)
                .environmentObject(tutorialManager)

            // Tutorial overlay (only when active and NOT in config sheet - sheet has its own overlay)
            if tutorialManager.isActive && !tutorialManager.isInConfigSheet {
                TutorialOverlayView()
                    .environmentObject(tutorialManager)
                    .transition(.opacity)
            }
        }
        // Collect target frames from all tutorial targets
        .onPreferenceChange(TutorialTargetPreferenceKey.self) { frames in
            tutorialManager.updateTargetFrames(frames)
        }
        // Monitor picker presentation
        .onChange(of: appUsageViewModel.isFamilyPickerPresented) { isPresented in
            handlePickerPresentation(isPresented: isPresented)
        }
        // Monitor learning snapshots to detect when apps are assigned (fixes race condition)
        .onChange(of: appUsageViewModel.learningSnapshots.count) { count in
            if tutorialManager.isActive &&
               tutorialManager.currentStep == .selectLearningApps &&
               count > 0 {
                #if DEBUG
                print("[Tutorial] Learning snapshots populated (\(count)), advancing to tapFirstLearningApp")
                #endif
                tutorialManager.handleSystemSheetDismissed(hasSelection: true)
            }
        }
        // Monitor reward snapshots similarly
        .onChange(of: appUsageViewModel.rewardSnapshots.count) { count in
            if tutorialManager.isActive &&
               tutorialManager.currentStep == .selectRewardApps &&
               count > 0 {
                #if DEBUG
                print("[Tutorial] Reward snapshots populated (\(count)), advancing to tapFirstRewardApp")
                #endif
                tutorialManager.handleSystemSheetDismissed(hasSelection: true)
            }
        }
        // Monitor tutorial completion
        .onChange(of: tutorialManager.isActive) { isActive in
            if !isActive {
                // Transfer settings to view model
                transferTutorialSettings()
                onTutorialComplete()
            }
        }
        .onAppear {
            tutorialManager.onTutorialComplete = {
                // Will trigger onChange above
            }
            tutorialManager.startTutorial()
        }
    }

    private func handlePickerPresentation(isPresented: Bool) {
        if isPresented {
            tutorialManager.willPresentSystemSheet()
        } else {
            tutorialManager.isWaitingForSystemSheet = false

            #if DEBUG
            print("[Tutorial] Picker dismissed, scheduling check for snapshots")
            #endif

            // Use delay to let snapshot updates propagate, then explicitly check
            // This handles the case where count was already > 0 (onChange doesn't fire)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkAndAdvanceFromPickerStep()
            }
        }
    }

    private func checkAndAdvanceFromPickerStep() {
        guard tutorialManager.isActive else { return }

        #if DEBUG
        print("[Tutorial] Checking if should advance - step: \(tutorialManager.currentStep), learning: \(appUsageViewModel.learningSnapshots.count), reward: \(appUsageViewModel.rewardSnapshots.count)")
        #endif

        switch tutorialManager.currentStep {
        case .selectLearningApps:
            if !appUsageViewModel.learningSnapshots.isEmpty {
                #if DEBUG
                print("[Tutorial] Advancing from selectLearningApps to tapFirstLearningApp")
                #endif
                tutorialManager.handleSystemSheetDismissed(hasSelection: true)
            } else {
                #if DEBUG
                print("[Tutorial] No learning apps selected - going back to add button")
                #endif
                tutorialManager.handleSystemSheetDismissed(hasSelection: false)
            }
        case .selectRewardApps:
            if !appUsageViewModel.rewardSnapshots.isEmpty {
                #if DEBUG
                print("[Tutorial] Advancing from selectRewardApps to tapFirstRewardApp")
                #endif
                tutorialManager.handleSystemSheetDismissed(hasSelection: true)
            } else {
                #if DEBUG
                print("[Tutorial] No reward apps selected - going back to add button")
                #endif
                tutorialManager.handleSystemSheetDismissed(hasSelection: false)
            }
        default:
            break
        }
    }

    private func transferTutorialSettings() {
        // The app selections are already in appUsageViewModel via the pickers
        // Just need to transfer goal and ratio

        // Save daily goal to UserDefaults (used by the app)
        UserDefaults.standard.set(tutorialManager.dailyLearningGoalMinutes, forKey: "dailyLearningGoalMinutes")

        // Save ratio
        UserDefaults.standard.set(tutorialManager.learningToRewardRatio, forKey: "learningToRewardRatio")

        // Trigger monitoring to start
        appUsageViewModel.blockRewardApps()

        #if DEBUG
        print("[Tutorial] Settings transferred - goal: \(tutorialManager.dailyLearningGoalMinutes)min, ratio: \(tutorialManager.learningToRewardRatio)")
        #endif
    }
}

// MARK: - Tutorial-Aware MainTabView

/// Modified MainTabView that works with the tutorial system
/// Includes forced tab selection and tutorial targets
struct TutorialMainTabView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var tutorialManager: TutorialModeManager

    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    // Swipeable pages (swiping disabled during tutorial)
                    TabView(selection: $selectedTab) {
                        ParentDashboardView()
                            .tag(0)

                        LearningTabView()
                            .tag(1)

                        RewardsTabView()
                            .tag(2)

                        SettingsTabView()
                            .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Disable swiping during tutorial, but allow content interaction when needed
                    .allowsHitTesting(!tutorialManager.isActive || tutorialManager.isWaitingForSystemSheet || tutorialManager.currentStepNeedsContentInteraction)

                    // Custom tab indicator with tutorial targets
                    TutorialTabIndicator(selectedTab: $selectedTab)
                        .environmentObject(tutorialManager)
                }
                .environmentObject(viewModel)
                .navigationViewStyle(.stack)
                .navigationBarHidden(true)
            }
            .navigationViewStyle(.stack)
            .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
            .onChange(of: viewModel.familySelection) { _ in
                viewModel.onPickerSelectionChange()
            }
            .onChange(of: viewModel.isFamilyPickerPresented) { isPresented in
                if !isPresented {
                    viewModel.onFamilyPickerDismissed()
                }
            }

            HiddenUsageReportView()
        }
    }
}

// MARK: - Tutorial Tab Indicator

/// Tab indicator with tutorial target markers
struct TutorialTabIndicator: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var tutorialManager: TutorialModeManager

    private let tabs: [(String, String, String)] = [
        ("Dashboard", "DashboardIcon", "tab_dashboard"),
        ("Learning", "LearningIcon", "tab_learning"),
        ("Rewards", "RewardsIcon", "tab_rewards"),
        ("Settings", "SettingsIcon", "tab_settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(index: index)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func tabButton(index: Int) -> some View {
        let tab = tabs[index]
        let isTarget = tutorialManager.isCurrentTarget(tab.2)

        Button(action: {
            // Only allow tap if this is the current target or tutorial is not active
            if !tutorialManager.isActive || isTarget {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = index
                }
                // If this was a tutorial target, advance
                if isTarget {
                    tutorialManager.completeCurrentStep()
                }
            }
        }) {
            VStack(spacing: 6) {
                Image(tab.1)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)

                Text(tab.0)
                    .font(.system(size: 12, weight: selectedTab == index ? .semibold : .regular))
                    .foregroundColor(selectedTab == index ? AppTheme.vibrantTeal : .secondary)

                // Active indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(selectedTab == index ? AppTheme.vibrantTeal : Color.clear)
                    .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .tutorialTarget(tab.2)
        // Control hit testing based on tutorial state
        .allowsHitTesting(!tutorialManager.isActive || isTarget || tutorialManager.isWaitingForSystemSheet)
    }
}

// MARK: - Preview

#Preview {
    GuidedTutorialContainerView {
        print("Tutorial completed!")
    }
    .environmentObject(AppUsageViewModel())
    .environmentObject(SessionManager.shared)
    .environmentObject(SubscriptionManager.shared)
}
