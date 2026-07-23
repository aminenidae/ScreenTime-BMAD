import SwiftUI

/// Routes between the shared onboarding entry and the device-specific flows.
/// Updated to use the new 7-screen onboarding flow for child devices.
struct OnboardingFlowView: View {
    enum OnboardingStep {
        case welcome
        case valueSlides
        case ahaMoment
        case deviceSelection
        case parentFlow
        case childFlow
    }

    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var deviceName: String
    @StateObject private var deviceModeManager = DeviceModeManager.shared
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @AppStorage("hasCompletedParentOnboarding") private var parentComplete = false
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false

    init() {
        let modeManager = DeviceModeManager.shared
        _deviceName = State(initialValue: modeManager.deviceName)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch onboardingStep {
                case .welcome:
                    // Merged welcome + problem screen (front-of-funnel, shown to everyone).
                    Screen1_ProblemView(onContinue: {
                        AppAnalytics.shared.trackOnboarding(.onboardingWelcomeCtaTapped)
                        withAnimation { onboardingStep = .valueSlides }
                    })
                    .onAppear { AppAnalytics.shared.trackOnboarding(.onboardingWelcomeViewed) }

                case .valueSlides:
                    // Value slides moved ahead of the device question so both paths see them.
                    Screen2_SolutionStepView(
                        onComplete: { withAnimation { onboardingStep = .ahaMoment } },
                        onBack: { withAnimation { onboardingStep = .welcome } }
                    )

                case .ahaMoment:
                    // "See it work" — canned animation of the earn → unlock loop.
                    OnboardingAhaMomentView(
                        onContinue: { withAnimation { onboardingStep = .deviceSelection } },
                        onBack: { withAnimation { onboardingStep = .valueSlides } }
                    )

                case .deviceSelection:
                    DeviceSelectionView(
                        showBackButton: true,
                        onDeviceSelected: { mode, name in
                            handleDeviceSelection(mode: mode, name: name)
                        },
                        onBack: { onboardingStep = .ahaMoment }
                    )
                    .onAppear { AppAnalytics.shared.trackOnboarding(.onboardingDeviceSelectionViewed) }

                case .parentFlow:
                    ParentOnboardingCoordinator(
                        deviceName: deviceName,
                        onBack: { onboardingStep = .deviceSelection },
                        onComplete: { onboardingStep = .welcome }
                    )
                    .environmentObject(subscriptionManager)

                case .childFlow:
                    // Child tail: enters directly at the finish line (front screens already shown).
                    OnboardingContainerView { destination in
                        handleOnboardingComplete(destination: destination)
                    }
                    .environmentObject(appUsageViewModel)
                    .environmentObject(subscriptionManager)
                }
            }
            .animation(.easeInOut, value: onboardingStep)
            // Overall progress through the shared intro (welcome → slides → device
            // question). Front-only: once the path forks, each path shows its own local
            // steps, so a single global "of N" would be dishonest across two lengths.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let step = frontProgressStep {
                    OnboardingProgressBar(step: step, total: 4)
                }
            }
        }
    }

    /// 0-based position in the shared front-of-funnel, or nil once the path forks.
    private var frontProgressStep: Int? {
        switch onboardingStep {
        case .welcome:         return 0
        case .valueSlides:     return 1
        case .ahaMoment:       return 2
        case .deviceSelection: return 3
        case .parentFlow, .childFlow: return nil
        }
    }

    private func handleDeviceSelection(mode: DeviceMode, name: String) {
        deviceName = name
        AppAnalytics.shared.trackOnboarding(.onboardingDeviceTypeSelected, parameters: [
            "device_type": mode == .parentDevice ? "parent" : "child"
        ])
        deviceModeManager.setDeviceMode(mode, deviceName: name)
        onboardingStep = mode == .parentDevice ? .parentFlow : .childFlow
    }

    private func handleOnboardingComplete(destination: OnboardingContainerView.OnboardingDestination) {
        childComplete = true
        // The RootView will automatically navigate based on the completed state
    }
}

// The merged welcome (Screen1_ProblemView) and value slides (Screen2_SolutionStepView)
// now live in the shared front-of-funnel above, before the device question.

/// Shared back button for onboarding screens, so back navigation looks identical
/// everywhere. Every screen uses one except the first (welcome) and the terminal
/// finish-line screens.
struct OnboardingBackButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Back")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(AppTheme.accentText(for: colorScheme))
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(AppTheme.vibrantTeal.opacity(0.1))
            .cornerRadius(AppTheme.CornerRadius.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

/// Thin segmented progress bar for the shared intro. Visual only (no "Step N" text) so
/// it doesn't collide with the value slides' own "Step X of 3" chip.
private struct OnboardingProgressBar: View {
    let step: Int   // 0-based
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}
