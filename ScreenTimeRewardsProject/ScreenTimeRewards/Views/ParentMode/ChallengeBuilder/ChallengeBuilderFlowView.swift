import SwiftUI

struct ChallengeBuilderFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator: ChallengeBuilderCoordinator

    // Onboarding mode support
    let isOnboarding: Bool
    let onBack: (() -> Void)?
    let onComplete: (() -> Void)?
    let onSkip: (() -> Void)?

    init(
        viewModel: ChallengeViewModel,
        isOnboarding: Bool = false,
        initialData: ChallengeBuilderData? = nil,
        onBack: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil
    ) {
        self.isOnboarding = isOnboarding
        self.onBack = onBack
        self.onComplete = onComplete
        self.onSkip = onSkip
        _coordinator = StateObject(wrappedValue: ChallengeBuilderCoordinator(
            challengeViewModel: viewModel,
            initialData: initialData
        ))
    }

    var body: some View {
        ZStack {
            ChallengeBuilderTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ChallengeBuilderProgressIndicator(
                            steps: coordinator.steps,
                            currentStep: coordinator.currentStep,
                            onStepTapped: { step in
                                coordinator.setStep(step)
                            }
                        )

                        if let errorMessage = coordinator.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.1))
                                )
                        }

                        stepView(for: coordinator.currentStep)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 0) {
                    // Skip button for onboarding mode
                    if isOnboarding, let onSkip = onSkip {
                        Button(action: onSkip) {
                            Text("Skip for now")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }

                    ChallengeBuilderNavigationFooter(
                        backTitle: "Back",
                        nextTitle: coordinator.isOnLastStep ? "Create Challenge" : "Next",
                        showBackButton: isOnboarding ? true : coordinator.currentStep != .details,
                        isBackEnabled: true,
                        isNextEnabled: coordinator.isStepValid(coordinator.currentStep),
                        isLoading: coordinator.isSaving,
                        onBack: {
                            if isOnboarding && coordinator.currentStep == .details {
                                onBack?()
                            } else {
                                coordinator.goToPrevious()
                            }
                        },
                        onNext: {
                            coordinator.handlePrimaryAction()
                        }
                    )
                }
                .padding(.horizontal, 20)
                .background(.ultraThinMaterial)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            coordinator.onSubmit = { _ in
                if isOnboarding {
                    onComplete?()
                } else {
                    dismiss()
                }
            }
        }
    }

    private var navBar: some View {
        let primaryEnabled = coordinator.isStepValid(coordinator.currentStep)

        return HStack(spacing: 12) {
            if !isOnboarding {
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.playfulCoral.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.playfulCoral)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Create Challenge")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Spacer()

            Button(action: {
                coordinator.handlePrimaryAction()
            }) {
                HStack(spacing: 6) {
                    Text(coordinator.isOnLastStep ? "Create" : "Next")
                        .font(.system(size: 16, weight: .bold))

                    if !coordinator.isOnLastStep {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundColor(primaryEnabled ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.4))
                .frame(minWidth: 44, alignment: .trailing)
            }
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ChallengeBuilderTheme.background.opacity(0.9)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(ChallengeBuilderTheme.border),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func stepView(for step: ChallengeBuilderStep) -> some View {
        switch step {
        case .details:
            ChallengeDetailsStepView(data: $coordinator.data)
        case .learningApps:
            LearningAppsStepView(
                selectedAppIDs: $coordinator.data.selectedLearningAppIDs,
                progressTrackingMode: $coordinator.data.progressTrackingMode,
                goalValue: .constant(coordinator.data.dailyMinutesGoal),
                goalType: $coordinator.data.goalType
            )
        case .rewardApps:
            RewardAppsStepView(selectedAppIDs: $coordinator.data.selectedRewardAppIDs)
        case .rewardConfig:
            RewardConfigStepView(data: $coordinator.data)
        case .schedule:
            ScheduleStepView(data: $coordinator.data)
        case .summary:
            SummaryStepView(data: $coordinator.data) { step in
                coordinator.setStep(step)
            }
        }
    }

    private func placeholderView(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(ChallengeBuilderTheme.text)
            Text("This step is coming soon.")
                .font(.system(size: 16))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundColor(ChallengeBuilderTheme.border)
        )
    }
}
