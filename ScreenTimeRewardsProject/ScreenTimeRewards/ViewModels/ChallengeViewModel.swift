import Foundation
import Combine

@MainActor
class ChallengeViewModel: ObservableObject {
    @Published var activeChallenges: [Challenge] = []
    @Published var challengeProgress: [String: ChallengeProgress] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let challengeService = ChallengeService.shared

    func loadChallenges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let deviceID = DeviceModeManager.shared.deviceID
            activeChallenges = try await challengeService.fetchActiveChallenges(for: deviceID)
            challengeProgress = challengeService.challengeProgress
        } catch {
            errorMessage = "Failed to load challenges: \(error.localizedDescription)"
        }
    }

    func createChallenge(
        title: String,
        description: String,
        goalType: ChallengeGoalType,
        targetValue: Int,
        bonusPercentage: Int,
        targetApps: [String]?,
        rewardApps: [String]?,
        startDate: Date,
        endDate: Date?,
        activeDays: [Int]?,
        startTime: Date?,
        endTime: Date?,
        createdBy: String,
        assignedTo: String,
        learningToRewardRatio: LearningToRewardRatio? = nil
    ) async {
        do {
            try await challengeService.createChallenge(
                title: title,
                description: description,
                goalType: goalType,
                targetValue: targetValue,
                bonusPercentage: bonusPercentage,
                targetApps: targetApps,
                rewardApps: rewardApps,
                startDate: startDate,
                endDate: endDate,
                activeDays: activeDays,
                startTime: startTime,
                endTime: endTime,
                createdBy: createdBy,
                assignedTo: assignedTo,
                learningToRewardRatio: learningToRewardRatio
            )
            await loadChallenges()
        } catch {
            errorMessage = "Failed to create challenge: \(error.localizedDescription)"
        }
    }
}
