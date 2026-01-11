import SwiftUI
import Combine
import FamilyControls

// MARK: - Onboarding State

struct OnboardingSetupState: Codable {
    var currentScreen: Int = 1
    var completedScreens: [Int] = []

    // Setup path selection
    var selectedPath: SetupPath?

    // Screen 4: Learning setup
    var selectedLearningAppIDs: [String] = []
    var dailyLearningGoalMinutes: Int = 60
    var childAgreementConfirmed: Bool = false

    // Screen 5: Reward setup
    var selectedRewardAppIDs: [String] = []
    var learningToRewardRatio: Double = 1.0 // 1:1

    // Screen 6: Trial/Subscription
    var trialStartDate: Date?
    var selectedPlan: SubscriptionPlanOption = .annual

    // Screen 7: Activation
    var activationComplete: Bool = false
}

enum SubscriptionPlanOption: String, Codable {
    case monthly = "com.screentime.family.monthly"
    case annual = "com.screentime.family.yearly"
}

struct ManagedAppInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let bundleID: String
    let category: AppCategoryType
    var isSelected: Bool
}

enum AppCategoryType: String, Codable {
    case learning
    case reward
}

// MARK: - Onboarding State Manager

@MainActor
class OnboardingStateManager: ObservableObject {
    @Published var currentScreen: Int = 1
    @Published var completedScreens: [Int] = []

    // Setup path selection (Solo vs Family)
    @Published var selectedPath: SetupPath?

    // Screen 4: Learning setup
    @Published var selectedLearningApps: [ManagedAppInfo] = []
    @Published var dailyLearningGoalMinutes: Int = 60
    @Published var childAgreementConfirmed: Bool = false

    // Screen 5: Reward setup
    @Published var selectedRewardApps: [ManagedAppInfo] = []
    @Published var learningToRewardRatio: Double = 1.0

    // Screen 6: Trial
    @Published var trialStartDate: Date?
    @Published var selectedPlan: SubscriptionPlanOption = .annual

    // Screen 7: Activation
    @Published var onboardingComplete: Bool = false

    /// Whether to show paywall (Solo path only)
    var shouldShowPaywall: Bool {
        selectedPath == .solo
    }

    /// Whether this is a family path (14-day trial, no paywall)
    var isFamilyPath: Bool {
        selectedPath == .family
    }

    // Family Activity Selection for actual app picker
    @Published var learningFamilySelection = FamilyActivitySelection()
    @Published var rewardFamilySelection = FamilyActivitySelection()

    // Reference to AppUsageViewModel for saving
    var appUsageViewModel: AppUsageViewModel?

    private let stateKey = "OnboardingSetupState"

    init() {
        loadState()
    }

    // MARK: - Navigation

    func advanceScreen() {
        if !completedScreens.contains(currentScreen) {
            completedScreens.append(currentScreen)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen += 1
        }
        saveState()
        logEvent("onboarding_screen\(currentScreen - 1)_cta_tapped")
    }

    func goBack() {
        guard currentScreen > 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen -= 1
        }
        saveState()
    }

    func skipToSetup() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = 4
        }
        saveState()
        logEvent("onboarding_skip_to_setup")
    }

    func skipToActivation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = 7
        }
        saveState()
        logEvent("onboarding_skip_to_activation")
    }

    func resetSetup() {
        selectedPath = nil
        selectedLearningApps = []
        selectedRewardApps = []
        learningFamilySelection = FamilyActivitySelection()
        rewardFamilySelection = FamilyActivitySelection()
        dailyLearningGoalMinutes = 60
        childAgreementConfirmed = false
        learningToRewardRatio = 1.0
        currentScreen = 1
        completedScreens = []
        saveState()
        logEvent("onboarding_setup_reset")
    }

    /// Set the monitoring path and advance
    func selectPath(_ path: SetupPath) {
        selectedPath = path
        saveState()
        logEvent("onboarding_path_selected", params: ["path": path.rawValue])
        advanceScreen()
    }

    // MARK: - Analytics

    func logScreenView(screenNumber: Int) {
        logEvent("onboarding_screen\(screenNumber)_shown")
    }

    func logEvent(_ eventName: String, params: [String: Any]? = nil) {
        #if DEBUG
        print("[Onboarding Analytics] \(eventName) \(params ?? [:])")
        #endif
        // TODO: Integrate with Firebase/Mixpanel when available
        // Analytics.logEvent(eventName, parameters: params ?? [:])
    }

    // MARK: - Persistence

    private func saveState() {
        let state = OnboardingSetupState(
            currentScreen: currentScreen,
            completedScreens: completedScreens,
            selectedPath: selectedPath,
            selectedLearningAppIDs: selectedLearningApps.filter(\.isSelected).map(\.id),
            dailyLearningGoalMinutes: dailyLearningGoalMinutes,
            childAgreementConfirmed: childAgreementConfirmed,
            selectedRewardAppIDs: selectedRewardApps.filter(\.isSelected).map(\.id),
            learningToRewardRatio: learningToRewardRatio,
            trialStartDate: trialStartDate,
            selectedPlan: selectedPlan,
            activationComplete: onboardingComplete
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(OnboardingSetupState.self, from: data) else {
            return
        }

        // IMPORTANT: Always start fresh at screen 1 for new onboarding sessions
        // Only restore currentScreen if onboarding was completed (for re-entry scenarios)
        // Otherwise, always start from the beginning
        if state.activationComplete {
            currentScreen = state.currentScreen
            completedScreens = state.completedScreens
        } else {
            // Fresh start - reset to screen 1
            currentScreen = 1
            completedScreens = []
            // Also clear persisted state to avoid confusion
            UserDefaults.standard.removeObject(forKey: stateKey)
            return
        }

        dailyLearningGoalMinutes = state.dailyLearningGoalMinutes
        childAgreementConfirmed = state.childAgreementConfirmed
        learningToRewardRatio = state.learningToRewardRatio
        trialStartDate = state.trialStartDate
        selectedPlan = state.selectedPlan
        onboardingComplete = state.activationComplete
    }

    // MARK: - App Setup Integration

    func saveLearningAppsToViewModel() {
        guard let viewModel = appUsageViewModel else { return }

        // Save to AppUsageViewModel
        viewModel.familySelection = learningFamilySelection
        viewModel.pendingSelection = learningFamilySelection

        // Assign categories and points for learning apps
        for token in learningFamilySelection.applicationTokens {
            viewModel.categoryAssignments[token] = .learning
            viewModel.rewardPoints[token] = 10
        }

        viewModel.onCategoryAssignmentSave()
    }

    func saveRewardAppsToViewModel() {
        guard let viewModel = appUsageViewModel else { return }

        // Merge reward apps into the existing selection
        var combinedSelection = viewModel.familySelection
        for token in rewardFamilySelection.applicationTokens {
            combinedSelection.applicationTokens.insert(token)
            viewModel.categoryAssignments[token] = .reward
            viewModel.rewardPoints[token] = 0
        }

        viewModel.familySelection = combinedSelection
        viewModel.pendingSelection = combinedSelection
        viewModel.onCategoryAssignmentSave()
    }

    func startMonitoring() {
        appUsageViewModel?.startMonitoring(force: true)
    }
}
