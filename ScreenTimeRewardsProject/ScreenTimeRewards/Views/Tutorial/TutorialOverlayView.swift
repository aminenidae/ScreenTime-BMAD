import SwiftUI

/// Full-screen overlay that dims everything except the tutorial target
/// Shows spotlight effect, callout, and progress indicator
struct TutorialOverlayView: View {
    @EnvironmentObject var tutorialManager: TutorialModeManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            // Don't show overlay during system sheet or on config step (which has its own panel)
            if !tutorialManager.isWaitingForSystemSheet {
                ZStack {
                    // 1. Dimmed background with spotlight cutout
                    spotlightMask(screenSize: geometry.size)

                    // 2. Pulsing ring around target (when we have a valid target)
                    if tutorialManager.targetFrame != .zero {
                        TutorialSpotlightRing(frame: tutorialManager.targetFrame)
                    }

                    // 3. Callout with instructions (when we have a target to point to)
                    if tutorialManager.currentStep.targetIdentifier != nil {
                        TutorialCalloutView(
                            step: tutorialManager.currentStep,
                            targetFrame: tutorialManager.targetFrame,
                            screenSize: geometry.size
                        )
                    }

                    // 4. Progress bar at top
                    VStack {
                        TutorialProgressBar(
                            currentStep: tutorialManager.currentStep.rawValue + 1,
                            totalSteps: TutorialModeManager.TutorialStep.allCases.count
                        )
                        .padding(.top, 60)
                        .padding(.horizontal, 24)

                        Spacer()
                    }

                    // 5. Settings panel (final step)
                    // NOTE: Authorization is now handled in Screen 3 before tutorial starts
                    if tutorialManager.currentStep == .configureSettings {
                        TutorialSetupPanel()
                    }

                    // 6. Continue button for config sheet steps (not for Save step)
                    if tutorialManager.currentStep.isConfigSheetStep && !isSaveStep {
                        VStack {
                            Spacer()
                            continueButton
                                .padding(.bottom, 40)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func spotlightMask(screenSize: CGSize) -> some View {
        // Use animatable spotlight with even-odd fill for smooth transitions (iOS 16+ compatible)
        AnimatableTutorialSpotlight(
            targetFrame: tutorialManager.targetFrame,
            cornerRadius: 12,
            padding: 12
        )
        .fill(style: FillStyle(eoFill: true))
        .foregroundColor(Color.black.opacity(0.75))
        .allowsHitTesting(true)  // Block taps on dimmed area
        .onTapGesture {
            // Absorb taps - don't do anything
            // This prevents accidental interactions
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tutorialManager.targetFrame)
    }

    /// Whether current step is a Save button step
    private var isSaveStep: Bool {
        tutorialManager.currentStep == .tapSaveLearning ||
        tutorialManager.currentStep == .tapSaveReward
    }

    /// Continue button for advancing through config sheet steps
    private var continueButton: some View {
        Button(action: {
            withAnimation {
                tutorialManager.advanceStep()
            }
        }) {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(AppTheme.vibrantTeal)
            .cornerRadius(25)
            .shadow(color: AppTheme.vibrantTeal.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Preview
// NOTE: TutorialAuthorizationView has been removed.
// Authorization is now handled in Screen 3 before the tutorial starts.

#Preview {
    ZStack {
        Color.gray
            .ignoresSafeArea()

        TutorialOverlayView()
            .environmentObject(TutorialModeManager.shared)
    }
}
