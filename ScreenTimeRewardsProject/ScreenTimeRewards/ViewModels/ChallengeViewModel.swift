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
        goalType: String,
        targetValue: Int,
        bonusPercentage: Int,
        targetApps: [String]?,
        startDate: Date,
        endDate: Date?,
        createdBy: String,
        assignedTo: String
    ) async {
        do {
            try await challengeService.createChallenge(
                title: title,
                description: description,
                goalType: goalType,
                targetValue: targetValue,
                bonusPercentage: bonusPercentage,
                targetApps: targetApps,
                startDate: startDate,
                endDate: endDate,
                createdBy: createdBy,
                assignedTo: assignedTo
            )
            await loadChallenges()
        } catch {
            errorMessage = "Failed to create challenge: \(error.localizedDescription)"
        }
    }
}