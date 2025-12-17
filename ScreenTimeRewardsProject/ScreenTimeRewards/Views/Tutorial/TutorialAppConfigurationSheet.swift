import SwiftUI
import FamilyControls
import ManagedSettings

/// Named coordinate space for the tutorial config sheet
/// Used to ensure frame capture and spotlight drawing use the same reference
private let tutorialSheetCoordinateSpace = "tutorialSheetContent"

/// Wrapper around AppConfigurationSheet that includes tutorial overlay support
/// Use this wrapper when presenting config sheets during the tutorial
struct TutorialAppConfigurationSheet: View {
    let token: ApplicationToken
    let appName: String
    let appType: AppType
    let learningSnapshots: [LearningAppSnapshot]

    @Binding var configuration: AppScheduleConfiguration
    let onSave: (AppScheduleConfiguration) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var tutorialManager: TutorialModeManager

    /// Stores frames captured in sheet coordinate space
    @State private var sheetTargetFrames: [String: CGRect] = [:]

    /// Controls scrolling to specific sections
    @State private var scrollToSection: AppConfigSection?

    var body: some View {
        GeometryReader { sheetGeometry in
            ZStack {
                AppConfigurationSheet(
                    token: token,
                    appName: appName,
                    appType: appType,
                    learningSnapshots: learningSnapshots,
                    configuration: $configuration,
                    scrollToSection: $scrollToSection,
                    onSave: { config in
                        // Handle save - advance tutorial if in config sheet step
                        if tutorialManager.isActive && tutorialManager.currentStep.isConfigSheetStep {
                            tutorialManager.advanceStep()
                        }
                        onSave(config)
                    },
                    onCancel: onCancel
                )
                // Auto-scroll to sections when tutorial step changes
                .onChange(of: tutorialManager.currentStep) { step in
                    scrollToSectionForStep(step)
                }
                // Collect target frames and convert to sheet-local coordinates
                .onPreferenceChange(TutorialTargetPreferenceKey.self) { globalFrames in
                    if tutorialManager.isActive {
                        // Convert global frames to sheet-local frames
                        let sheetOrigin = sheetGeometry.frame(in: .global).origin
                        var localFrames: [String: CGRect] = [:]
                        for (key, frame) in globalFrames {
                            localFrames[key] = CGRect(
                                x: frame.origin.x - sheetOrigin.x,
                                y: frame.origin.y - sheetOrigin.y,
                                width: frame.width,
                                height: frame.height
                            )
                        }
                        sheetTargetFrames = localFrames
                        tutorialManager.updateTargetFrames(localFrames)
                    }
                }

                // Overlay the tutorial spotlight on the sheet when active
                if tutorialManager.isActive && tutorialManager.isInConfigSheet {
                    SheetTutorialOverlayView(targetFrame: currentTargetFrame)
                        .environmentObject(tutorialManager)
                }
            }
        }
    }

    /// Get the current target frame in sheet-local coordinates
    private var currentTargetFrame: CGRect {
        guard let identifier = tutorialManager.currentStep.targetIdentifier else {
            return .zero
        }
        return sheetTargetFrames[identifier] ?? .zero
    }

    /// Scroll to the appropriate section based on tutorial step
    private func scrollToSectionForStep(_ step: TutorialModeManager.TutorialStep) {
        switch step {
        case .reviewSummaryLearning, .reviewSummaryReward:
            // Small delay to let the view update before scrolling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToSection = .summary
            }
        case .configTimeWindowLearning, .configTimeWindowReward:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToSection = .timeWindow
            }
        case .configDailyLimitsLearning, .configDailyLimitsReward:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToSection = .dailyLimits
            }
        case .configLinkedApps:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToSection = .linkedApps
            }
        default:
            break
        }
    }
}

/// A simplified tutorial overlay for use inside sheets
/// Uses passed-in target frame instead of tutorialManager.targetFrame (which may have stale global coords)
struct SheetTutorialOverlayView: View {
    let targetFrame: CGRect
    @EnvironmentObject var tutorialManager: TutorialModeManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // 1. Dimmed background with spotlight cutout
            spotlightMask

            // 2. Pulsing ring around target (when we have a valid target)
            if targetFrame != .zero {
                TutorialSpotlightRing(frame: targetFrame)
            }

            // 3. Callout with instructions
            if tutorialManager.currentStep.targetIdentifier != nil {
                GeometryReader { geometry in
                    TutorialCalloutView(
                        step: tutorialManager.currentStep,
                        targetFrame: targetFrame,
                        screenSize: geometry.size
                    )
                }
            }

            // 4. Progress bar at top
            VStack {
                TutorialProgressBar(
                    currentStep: tutorialManager.currentStep.rawValue + 1,
                    totalSteps: TutorialModeManager.TutorialStep.allCases.count
                )
                .padding(.top, 16)
                .padding(.horizontal, 24)

                Spacer()
            }

            // 5. Continue button for config sheet steps (not for Save step)
            if tutorialManager.currentStep.isConfigSheetStep && !isSaveStep {
                VStack {
                    Spacer()
                    continueButton
                        .padding(.bottom, 40)
                }
            }
        }
    }

    @ViewBuilder
    private var spotlightMask: some View {
        AnimatableTutorialSpotlight(
            targetFrame: targetFrame,
            cornerRadius: 12,
            padding: 12
        )
        .fill(style: FillStyle(eoFill: true))
        .foregroundColor(Color.black.opacity(0.75))
        .allowsHitTesting(true)
        .onTapGesture {
            // Absorb taps - don't do anything
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: targetFrame)
    }

    private var isSaveStep: Bool {
        tutorialManager.currentStep == .tapSaveLearning ||
        tutorialManager.currentStep == .tapSaveReward
    }

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

#if DEBUG
struct TutorialAppConfigurationSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available - requires ApplicationToken")
    }
}
#endif
