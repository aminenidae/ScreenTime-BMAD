import SwiftUI
import Combine
import FamilyControls

/// Manages the guided tutorial flow state
/// Tracks current step, target element frames, and tutorial completion
@MainActor
class TutorialModeManager: ObservableObject {
    static let shared = TutorialModeManager()

    // MARK: - Tutorial Steps
    // NOTE: Authorization is now handled in Screen 4 BEFORE the tutorial starts.
    // The tutorial guides parents through selecting AND configuring apps (18 steps total).

    enum TutorialStep: Int, CaseIterable {
        // Learning flow (Steps 1-8)
        case tapLearningTab = 0           // Step 1: Navigate to Learning tab
        case tapAddLearningApps = 1       // Step 2: Tap "Manage Learning apps" button
        case selectLearningApps = 2       // Step 3: System picker (waiting state)
        case tapFirstLearningApp = 3      // Step 4: Tap first learning app to configure
        case configTimeWindowLearning = 4 // Step 5: Configure time window
        case configDailyLimitsLearning = 5 // Step 6: Configure daily limits
        case reviewSummaryLearning = 6    // Step 7: Review summary section
        case tapSaveLearning = 7          // Step 8: Tap Save button

        // Reward flow (Steps 9-17)
        case tapRewardsTab = 8            // Step 9: Navigate to Rewards tab
        case tapAddRewardApps = 9         // Step 10: Tap "Manage Reward Apps" button
        case selectRewardApps = 10        // Step 11: System picker (waiting state)
        case tapFirstRewardApp = 11       // Step 12: Tap first reward app to configure
        case configTimeWindowReward = 12  // Step 13: Configure time window
        case configDailyLimitsReward = 13 // Step 14: Configure daily limits
        case configLinkedApps = 14        // Step 15: Configure linked learning apps
        case reviewSummaryReward = 15     // Step 16: Review summary section
        case tapSaveReward = 16           // Step 17: Tap Save button

        // Final (Step 18)
        case configureSettings = 17       // Step 18: Configure daily goal + ratio

        var instructionText: String {
            switch self {
            // Learning flow
            case .tapLearningTab:
                return "Tap the Learning tab to add educational apps."
            case .tapAddLearningApps:
                return "Tap here to select which apps count as learning time."
            case .selectLearningApps:
                return "Select the apps you want to count as learning time, then tap Done."
            case .tapFirstLearningApp:
                return "Tap your first learning app to configure it."
            case .configTimeWindowLearning:
                return "Set when this app can be used (e.g., 8 AM - 8 PM)."
            case .configDailyLimitsLearning:
                return "Set how long your child can use this app each day."
            case .reviewSummaryLearning:
                return "Review the configuration summary. This shows what you've set up."
            case .tapSaveLearning:
                return "Tap Save to apply these settings."

            // Reward flow
            case .tapRewardsTab:
                return "Now tap the Rewards tab to add fun apps."
            case .tapAddRewardApps:
                return "Tap here to select which apps are rewards."
            case .selectRewardApps:
                return "Select your child's favorite apps as rewards, then tap Done."
            case .tapFirstRewardApp:
                return "Now tap your first reward app to configure it."
            case .configTimeWindowReward:
                return "Set when reward time is available."
            case .configDailyLimitsReward:
                return "Set the maximum reward time per day."
            case .configLinkedApps:
                return "Choose which learning apps unlock this reward."
            case .reviewSummaryReward:
                return "Review the reward app settings before saving."
            case .tapSaveReward:
                return "Tap Save to complete reward app setup."

            // Final
            case .configureSettings:
                return "Almost done! Set how much learning unlocks reward time."
            }
        }

        var targetIdentifier: String? {
            switch self {
            // Learning flow
            case .tapLearningTab:
                return "tab_learning"
            case .tapAddLearningApps:
                return "add_learning_apps"
            case .selectLearningApps:
                return nil  // System picker, no target
            case .tapFirstLearningApp:
                return "first_learning_app"
            case .configTimeWindowLearning:
                return "config_time_window"
            case .configDailyLimitsLearning:
                return "config_daily_limits"
            case .reviewSummaryLearning:
                return "config_summary"
            case .tapSaveLearning:
                return "config_save"

            // Reward flow
            case .tapRewardsTab:
                return "tab_rewards"
            case .tapAddRewardApps:
                return "add_reward_apps"
            case .selectRewardApps:
                return nil  // System picker, no target
            case .tapFirstRewardApp:
                return "first_reward_app"
            case .configTimeWindowReward:
                return "config_time_window"
            case .configDailyLimitsReward:
                return "config_daily_limits"
            case .configLinkedApps:
                return "config_linked_apps"
            case .reviewSummaryReward:
                return "config_summary"
            case .tapSaveReward:
                return "config_save"

            // Final
            case .configureSettings:
                return nil  // Custom panel, no target
            }
        }

        var requiredTabIndex: Int? {
            switch self {
            case .tapLearningTab, .tapAddLearningApps, .selectLearningApps,
                 .tapFirstLearningApp, .configTimeWindowLearning,
                 .configDailyLimitsLearning, .reviewSummaryLearning, .tapSaveLearning:
                return 1  // Learning tab
            case .tapRewardsTab, .tapAddRewardApps, .selectRewardApps,
                 .tapFirstRewardApp, .configTimeWindowReward,
                 .configDailyLimitsReward, .configLinkedApps,
                 .reviewSummaryReward, .tapSaveReward, .configureSettings:
                return 2  // Rewards tab
            }
        }

        /// Whether this step occurs inside a config sheet
        var isConfigSheetStep: Bool {
            switch self {
            case .configTimeWindowLearning, .configDailyLimitsLearning,
                 .reviewSummaryLearning, .tapSaveLearning,
                 .configTimeWindowReward, .configDailyLimitsReward,
                 .configLinkedApps, .reviewSummaryReward, .tapSaveReward:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Published State

    /// Whether tutorial mode is currently active
    @Published var isActive: Bool = false

    /// Current step in the tutorial
    @Published var currentStep: TutorialStep = .tapLearningTab

    /// Frame of the current target element in global coordinates
    @Published var targetFrame: CGRect = .zero

    /// All registered target frames (collected via PreferenceKey)
    @Published var allTargetFrames: [String: CGRect] = [:]

    /// Whether we're waiting for a system sheet (FamilyActivityPicker)
    @Published var isWaitingForSystemSheet: Bool = false

    /// Controls which tab should be selected
    @Published var forcedTabIndex: Int = 0

    /// Step completion tracking
    @Published private(set) var stepCompletionStatus: [TutorialStep: Bool] = [:]

    // MARK: - FamilyControls Authorization State

    @Published var isAuthorized: Bool = false

    // MARK: - App Selection State

    @Published var learningFamilySelection = FamilyActivitySelection()
    @Published var rewardFamilySelection = FamilyActivitySelection()
    @Published var learningToRewardRatio: Double = 1.0
    @Published var dailyLearningGoalMinutes: Int = 60

    // MARK: - Callbacks

    var onTutorialComplete: (() -> Void)?

    // MARK: - Initialization

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Tutorial Lifecycle

    func startTutorial() {
        isActive = true

        // Authorization is handled in Screen 3 before tutorial starts
        // So we always start at the learning tab step
        checkAuthorizationStatus()  // Update auth state for reference
        currentStep = .tapLearningTab
        forcedTabIndex = 1  // Start on Learning tab

        stepCompletionStatus = [:]

        #if DEBUG
        print("[Tutorial] Started - authorized: \(isAuthorized), step: \(currentStep)")
        #endif
    }

    func advanceStep() {
        guard isActive else { return }

        // Mark current step as complete
        stepCompletionStatus[currentStep] = true

        // Find next step
        guard let currentIndex = TutorialStep.allCases.firstIndex(of: currentStep),
              currentIndex + 1 < TutorialStep.allCases.count else {
            // No more steps - complete tutorial
            endTutorial(success: true)
            return
        }

        let nextStep = TutorialStep.allCases[currentIndex + 1]

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = nextStep
        }

        // Update forced tab if needed
        if let tabIndex = nextStep.requiredTabIndex {
            forcedTabIndex = tabIndex
        }

        // Update target frame for new step
        updateTargetFrame()

        #if DEBUG
        print("[Tutorial] Advanced to step: \(nextStep)")
        #endif
    }

    func completeCurrentStep() {
        advanceStep()
    }

    func endTutorial(success: Bool) {
        isActive = false

        if success {
            // Clear persisted state
            UserDefaults.standard.removeObject(forKey: "tutorial_progress_step")

            #if DEBUG
            print("[Tutorial] Completed successfully")
            #endif

            // Notify completion
            onTutorialComplete?()
        }
    }

    // MARK: - System Sheet Handling

    func willPresentSystemSheet() {
        isWaitingForSystemSheet = true
        #if DEBUG
        print("[Tutorial] System sheet presenting")
        #endif
    }

    func handleSystemSheetDismissed(hasSelection: Bool) {
        isWaitingForSystemSheet = false

        #if DEBUG
        print("[Tutorial] System sheet dismissed, hasSelection: \(hasSelection)")
        #endif

        if hasSelection {
            advanceStep()
        } else {
            // No selection - go back to previous step to highlight the "Manage Apps" button again
            goBackToPreviousStep()
        }
    }

    /// Go back to the previous step (used when picker is dismissed without selection)
    func goBackToPreviousStep() {
        guard isActive else { return }

        guard let currentIndex = TutorialStep.allCases.firstIndex(of: currentStep),
              currentIndex > 0 else {
            return
        }

        let previousStep = TutorialStep.allCases[currentIndex - 1]

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = previousStep
        }

        // Update forced tab if needed
        if let tabIndex = previousStep.requiredTabIndex {
            forcedTabIndex = tabIndex
        }

        // Update target frame for previous step
        updateTargetFrame()

        #if DEBUG
        print("[Tutorial] Went back to step: \(previousStep)")
        #endif
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        isAuthorized = (status == .approved)
    }

    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await MainActor.run {
                isAuthorized = true
                UserDefaults.standard.set(true, forKey: "authorizationGranted")
            }
            return true
        } catch {
            #if DEBUG
            print("[Tutorial] Authorization failed: \(error)")
            #endif
            return false
        }
    }

    func handleAuthorizationGranted() {
        isAuthorized = true
        advanceStep()
    }

    // MARK: - Target Frame Management

    func updateTargetFrames(_ frames: [String: CGRect]) {
        allTargetFrames = frames
        updateTargetFrame()
    }

    private func updateTargetFrame() {
        guard let identifier = currentStep.targetIdentifier,
              let frame = allTargetFrames[identifier] else {
            targetFrame = .zero
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            targetFrame = frame
        }
    }

    // MARK: - Persistence (for app backgrounding)

    func persistProgress() {
        UserDefaults.standard.set(currentStep.rawValue, forKey: "tutorial_progress_step")
    }

    func resumeIfNeeded() {
        guard let savedStep = UserDefaults.standard.value(forKey: "tutorial_progress_step") as? Int,
              let step = TutorialStep(rawValue: savedStep) else {
            return
        }

        currentStep = step
        isActive = true

        if let tabIndex = step.requiredTabIndex {
            forcedTabIndex = tabIndex
        }
    }

    // MARK: - Helper Methods

    func isCurrentTarget(_ identifier: String) -> Bool {
        guard isActive else { return false }
        return currentStep.targetIdentifier == identifier
    }

    /// Whether the current step requires interaction with TabView content (not just tabs)
    var currentStepNeedsContentInteraction: Bool {
        switch currentStep {
        case .tapAddLearningApps, .tapAddRewardApps,
             .tapFirstLearningApp, .tapFirstRewardApp,
             .configureSettings:
            return true
        default:
            return false
        }
    }

    /// Whether currently showing a config sheet
    var isInConfigSheet: Bool {
        currentStep.isConfigSheetStep
    }

    func shouldAllowInteraction(for identifier: String) -> Bool {
        // When tutorial is not active, allow all interactions
        guard isActive else { return true }

        // During system sheet, allow all (sheet handles it)
        if isWaitingForSystemSheet { return true }

        // Only allow interaction with current target
        return isCurrentTarget(identifier)
    }
}
