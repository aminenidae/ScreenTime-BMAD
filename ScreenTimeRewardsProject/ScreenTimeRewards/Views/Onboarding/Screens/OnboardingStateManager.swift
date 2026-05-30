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

    /// Sub-step index for Screen 2 (solution flow): 0..4 across 5 dedicated step screens.
    /// Reset to 0 whenever currentScreen becomes 2; advanced via `advanceSolutionStep()`.
    @Published var solutionStepIndex: Int = 0

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
        trackAttemptStart()
    }

    // MARK: - Navigation

    func advanceScreen() {
        logScreenExit(screenNumber: currentScreen)
        if !completedScreens.contains(currentScreen) {
            completedScreens.append(currentScreen)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen += 1
        }
        // Reset solution sub-step when entering Screen 2
        if currentScreen == 2 {
            solutionStepIndex = 0
        }
        saveState()
    }

    /// Advance to the next sub-step inside Screen 2 (solution flow).
    /// When the last step is passed, advances to the next top-level screen.
    func advanceSolutionStep(totalSteps: Int) {
        if solutionStepIndex < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                solutionStepIndex += 1
            }
            logEvent("onboarding_screen2_step\(solutionStepIndex)_advanced")
        } else {
            advanceScreen()
        }
    }

    #if targetEnvironment(simulator)
    /// Simulator-only helper for ASC capture: jump directly to a specific solution step.
    func jumpToSolutionStep(_ index: Int) {
        currentScreen = 2
        solutionStepIndex = index
        saveState()
    }
    #endif

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

    /// Simulator-only: Skip directly to paywall for App Store screenshots
    func skipToPaywall() {
        selectedPath = .solo  // Ensure paywall shows
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = 6
        }
        saveState()
        logEvent("onboarding_skip_to_paywall_simulator")
    }

    func resetSetup() {
        AppAnalytics.shared.track(.onboardingSkipConfirmed, parameters: [
            "from_screen": currentScreen,
            "from_screen_name": screenName(for: currentScreen),
            "path": selectedPath?.rawValue ?? "none"
        ])
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
    }

    /// Set the monitoring path and advance
    func selectPath(_ path: SetupPath) {
        selectedPath = path
        saveState()
        AppAnalytics.shared.track(.onboardingPathSelected, parameters: [
            "path": path.rawValue,
            "attempt": UserDefaults.standard.integer(forKey: attemptKey)
        ])
        advanceScreen()
    }

    // MARK: - Analytics

    private let screenEnteredAt = NSMutableDictionary()
    private let attemptKey = "onboarding_attempt_count"

    func logScreenView(screenNumber: Int) {
        screenEnteredAt[screenNumber] = Date()
        AppAnalytics.shared.track(.onboardingScreenViewed, parameters: [
            "screen_number": screenNumber,
            "screen_name": screenName(for: screenNumber),
            "attempt": UserDefaults.standard.integer(forKey: attemptKey)
        ])
    }

    func logScreenExit(screenNumber: Int) {
        var params: [String: Any] = ["screen_number": screenNumber]
        if let entered = screenEnteredAt[screenNumber] as? Date {
            params["time_spent_seconds"] = Date().timeIntervalSince(entered)
        }
        params["screen_name"] = screenName(for: screenNumber)
        AppAnalytics.shared.track(.onboardingCtaTapped, parameters: params)
    }

    func trackAttemptStart() {
        let count = UserDefaults.standard.integer(forKey: attemptKey) + 1
        UserDefaults.standard.set(count, forKey: attemptKey)
        AppAnalytics.shared.track(.onboardingAttemptStarted, parameters: ["attempt": count])
    }

    func logEvent(_ eventName: String, params: [String: Any]? = nil) {
        #if DEBUG
        print("[Onboarding Analytics] \(eventName) \(params ?? [:])")
        #endif
    }

    private func screenName(for number: Int) -> String {
        switch number {
        case 1: return "problem"
        case 2: return "solution"
        case 3: return "path_selection"
        case 4: return "authorization"
        case 5: return "tutorial"
        case 6: return "paywall"
        case 7: return "activation"
        default: return "unknown"
        }
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
