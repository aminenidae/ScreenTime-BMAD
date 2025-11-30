import SwiftUI
import Combine

private struct ChallengeSubmissionValues {
    let title: String
    let description: String
    let goalType: ChallengeGoalType
    let targetValue: Int
    let bonusPercentage: Int
    let targetApps: [String]?
    let rewardApps: [String]?
    let startDate: Date
    let endDate: Date?
    let activeDays: [Int]?
    let startTime: Date?
    let endTime: Date?
    let createdBy: String
    let assignedTo: String
    let learningToRewardRatio: LearningToRewardRatio
    let streakBonusEnabled: Bool
    let streakTargetDays: Int
    let streakBonusPercentage: Int
}

@MainActor
final class ChallengeBuilderCoordinator: ObservableObject {
    @Published var data = ChallengeBuilderData()
    @Published var currentStep: ChallengeBuilderStep = .details
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let challengeService: ChallengeService
    private let challengeViewModel: ChallengeViewModel

    /// Allow parent containers to hook into completion.
    var onSubmit: ((ChallengeBuilderData) -> Void)?

    let steps = ChallengeBuilderStep.allCases

    init(
        challengeViewModel: ChallengeViewModel,
        challengeService: ChallengeService = .shared,
        initialData: ChallengeBuilderData? = nil
    ) {
        self.challengeViewModel = challengeViewModel
        self.challengeService = challengeService

        // If initial data is provided (edit mode), use it
        if let initialData = initialData {
            self.data = initialData
            #if DEBUG
            print("[ChallengeBuilderCoordinator] ✏️ Initialized with existing data: \(initialData.title)")
            #endif
        }
    }

    var currentStepIndex: Int {
        steps.firstIndex(of: currentStep) ?? 0
    }

    var progress: Double {
        guard let index = steps.firstIndex(of: currentStep) else { return 0 }
        return Double(index + 1) / Double(steps.count)
    }

    var isOnLastStep: Bool {
        currentStep == steps.last
    }

    func goToPrevious() {
        guard let currentIndex = steps.firstIndex(of: currentStep), currentIndex > 0 else { return }
        currentStep = steps[currentIndex - 1]
        errorMessage = nil
    }

    func goToNext() {
        guard let currentIndex = steps.firstIndex(of: currentStep),
              currentIndex < steps.count - 1 else { return }

        guard isStepValid(currentStep) else {
            errorMessage = validationMessage(for: currentStep)
            return
        }

        errorMessage = nil
        currentStep = steps[currentIndex + 1]
    }

    func setStep(_ step: ChallengeBuilderStep) {
        guard let targetIndex = steps.firstIndex(of: step),
              let currentIndex = steps.firstIndex(of: currentStep) else { return }

        if targetIndex <= currentIndex {
            currentStep = step
            errorMessage = nil
            return
        }

        // Ensure all intermediate steps are valid before allowing skip forward.
        for index in currentIndex...targetIndex {
            let stepToValidate = steps[index]
            guard isStepValid(stepToValidate) else {
                errorMessage = validationMessage(for: stepToValidate)
                return
            }
        }

        currentStep = step
        errorMessage = nil
    }

    func handlePrimaryAction() {
        if isOnLastStep {
            submit()
        } else {
            goToNext()
        }
    }

    private func submit() {
        guard !isSaving else { return }
        guard data.canSubmit else {
            errorMessage = validationMessage(for: .summary)
            return
        }
        errorMessage = nil

        let submissionValues = buildSubmissionValues()
        isSaving = true

        Task {
            do {
                try await challengeService.createChallenge(
                    title: submissionValues.title,
                    description: submissionValues.description,
                    goalType: submissionValues.goalType,
                    targetValue: submissionValues.targetValue,
                    bonusPercentage: submissionValues.bonusPercentage,
                    targetApps: submissionValues.targetApps,
                    rewardApps: submissionValues.rewardApps,
                    startDate: submissionValues.startDate,
                    endDate: submissionValues.endDate,
                    activeDays: submissionValues.activeDays,
                    startTime: submissionValues.startTime,
                    endTime: submissionValues.endTime,
                    createdBy: submissionValues.createdBy,
                    assignedTo: submissionValues.assignedTo,
                    learningToRewardRatio: submissionValues.learningToRewardRatio,
                    progressTrackingMode: data.progressTrackingMode,
                    streakBonusEnabled: submissionValues.streakBonusEnabled,
                    streakTargetDays: submissionValues.streakTargetDays,
                    streakBonusPercentage: submissionValues.streakBonusPercentage
                )

                await challengeViewModel.loadChallenges()

                await MainActor.run {
                    self.isSaving = false
                    self.onSubmit?(self.data)
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = "Failed to create challenge: \(error.localizedDescription)"
                }
            }
        }
    }

    func isStepValid(_ step: ChallengeBuilderStep) -> Bool {
        switch step {
        case .details:
            return data.isDetailsStepValid
        case .learningApps:
            // Step is valid if no apps selected OR all selected apps are configured
            return data.selectedLearningAppIDs.isEmpty || data.areLearningAppsConfigured
        case .rewardApps:
            // Step is valid if no apps selected OR all selected apps are configured
            return data.selectedRewardAppIDs.isEmpty || data.areRewardAppsConfigured
        case .rewardConfig:
            return data.isRewardConfigValid
        case .summary:
            return data.canSubmit
        }
    }

    func validationMessage(for step: ChallengeBuilderStep) -> String? {
        switch step {
        case .details:
            return "Add a challenge name and goal before continuing."
        case .learningApps:
            if !data.areLearningAppsConfigured {
                let count = data.unconfiguredLearningAppCount
                return "Configure \(count) learning app\(count == 1 ? "" : "s") before continuing."
            }
            return nil
        case .rewardApps:
            if !data.areRewardAppsConfigured {
                let count = data.unconfiguredRewardAppCount
                return "Configure \(count) reward app\(count == 1 ? "" : "s") before continuing."
            }
            return nil
        case .rewardConfig:
            return "Set a valid learning-to-reward ratio before continuing."
        case .summary:
            return "Complete the required steps before creating the challenge."
        }
    }

    private func buildSubmissionValues() -> ChallengeSubmissionValues {
        let trimmedTitle = data.trimmedTitle.isEmpty ? "Untitled Challenge" : data.trimmedTitle
        let activeDays = data.schedule.activeDays.isEmpty ? nil : Array(data.schedule.activeDays).sorted()
        let startTime = data.schedule.usesCustomTimeRange ? data.schedule.startTime : nil
        let endTime = data.schedule.usesCustomTimeRange ? data.schedule.endTime : nil
        let endDate = data.schedule.hasEndDate ? data.schedule.endDate : nil
        let creatorID = DeviceModeManager.shared.deviceID

        return ChallengeSubmissionValues(
            title: trimmedTitle,
            description: data.description,
            goalType: data.goalType,
            targetValue: data.dailyMinutesGoal,
            bonusPercentage: 0, // No longer used for reward calculation
            targetApps: data.selectedLearningAppIDs.isEmpty ? nil : Array(data.selectedLearningAppIDs),
            rewardApps: data.selectedRewardAppIDs.isEmpty ? nil : Array(data.selectedRewardAppIDs),
            startDate: data.schedule.startDate,
            endDate: endDate,
            activeDays: activeDays,
            startTime: startTime,
            endTime: endTime,
            createdBy: creatorID,
            assignedTo: creatorID,
            learningToRewardRatio: data.learningToRewardRatio,
            streakBonusEnabled: data.streakBonus.enabled,
            streakTargetDays: data.streakBonus.targetDays,
            streakBonusPercentage: data.streakBonus.bonusPercentage
        )
    }
}
