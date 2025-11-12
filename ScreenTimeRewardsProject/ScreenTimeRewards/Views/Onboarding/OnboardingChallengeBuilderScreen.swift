import SwiftUI

struct OnboardingChallengeBuilderScreen: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext

    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var challengeName: String = "Daily Learning Quest"
    @State private var dailyMinutes: Int = 30
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var hasLearningApps: Bool {
        !appUsageViewModel.learningSnapshots.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ChildOnboardingStepHeader(
                    title: "Create Your First Challenge",
                    subtitle: "Set a daily learning goal to motivate your child. You can customize this later.",
                    step: 4,
                    totalSteps: 5,
                    onBack: onBack
                )

                if hasLearningApps {
                    challengeCard
                    previewCard
                } else {
                    noAppsCard
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: createChallenge) {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text(hasLearningApps ? "Create Challenge" : "Continue")
                                    .font(.system(size: 17, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accentColor)
                        .cornerRadius(14)
                    }
                    .disabled(isCreating || (hasLearningApps && challengeName.isEmpty))

                    if hasLearningApps {
                        Button(action: onContinue) {
                            Text("Skip for now")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Challenge Details")
                .font(.headline)

            // Challenge name
            VStack(alignment: .leading, spacing: 8) {
                Text("Challenge Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Enter challenge name", text: $challengeName)
                    .textFieldStyle(.roundedBorder)
            }

            // Daily minutes goal
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Daily Goal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(dailyMinutes) minutes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                Slider(value: Binding(
                    get: { Double(dailyMinutes) },
                    set: { dailyMinutes = Int($0) }
                ), in: 10...120, step: 5)
                .tint(AppTheme.vibrantTeal)

                HStack {
                    Text("10 min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("120 min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Info
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("This challenge will track all learning apps you selected and reward your child with points.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What your child will see", systemImage: "eyes")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(AppTheme.vibrantTeal.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(challengeName.isEmpty ? "Daily Learning Quest" : challengeName)
                        .font(.system(size: 16, weight: .bold))

                    Text("\(dailyMinutes) minutes of learning")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(AppTheme.sunnyYellow)
                        Text("\(dailyMinutes * 10) points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var noAppsCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("No Learning Apps Selected")
                .font(.headline)

            Text("You need to select learning apps before creating a challenge. You can create challenges later from the Challenges tab.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }

    private func createChallenge() {
        guard hasLearningApps else {
            // Just continue if no apps
            onContinue()
            return
        }

        guard !challengeName.isEmpty else { return }

        isCreating = true

        Task {
            do {
                let service = ChallengeService.shared

                // Get all learning app tokens
                let learningTokens = appUsageViewModel.learningSnapshots.map { $0.token }

                // Convert tokens to strings (encode as Data then base64)
                let learningAppStrings: [String] = try learningTokens.compactMap { token in
                    guard let data = try? JSONEncoder().encode(token) else { return nil }
                    return data.base64EncodedString()
                }

                // Create challenge with simple defaults
                try await service.createChallenge(
                    title: challengeName,
                    description: "Complete \(dailyMinutes) minutes of learning each day",
                    goalType: .dailyQuest,
                    targetValue: dailyMinutes,
                    bonusPercentage: 10,
                    targetApps: learningAppStrings,
                    rewardApps: [], // No reward unlocking for now
                    startDate: Date(),
                    endDate: nil,
                    activeDays: [1, 2, 3, 4, 5, 6, 7], // All days
                    startTime: Calendar.current.date(from: DateComponents(hour: 0, minute: 0))!,
                    endTime: Calendar.current.date(from: DateComponents(hour: 23, minute: 59))!,
                    createdBy: DeviceModeManager.shared.deviceID,
                    assignedTo: DeviceModeManager.shared.deviceID,
                    learningToRewardRatio: LearningToRewardRatio(learningMinutes: 60, rewardMinutes: 60),
                    progressTrackingMode: .combined,
                    streakBonusEnabled: true,
                    streakTargetDays: 7,
                    streakBonusPercentage: 25
                )

                await MainActor.run {
                    isCreating = false
                    onContinue()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
