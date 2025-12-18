import SwiftUI

/// Routes between the shared onboarding entry and the device-specific flows.
/// Updated to use the new 7-screen onboarding flow for child devices.
struct OnboardingFlowView: View {
    enum OnboardingStep {
        case welcome
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
                    OnboardingWelcomeStep {
                        withAnimation { onboardingStep = .deviceSelection }
                    }

                case .deviceSelection:
                    DeviceSelectionView(
                        showBackButton: true,
                        onDeviceSelected: { mode, name in
                            handleDeviceSelection(mode: mode, name: name)
                        },
                        onBack: { onboardingStep = .welcome }
                    )

                case .parentFlow:
                    ParentOnboardingCoordinator(
                        deviceName: deviceName,
                        onBack: { onboardingStep = .deviceSelection },
                        onComplete: { onboardingStep = .welcome }
                    )

                case .childFlow:
                    // New 7-screen onboarding flow
                    OnboardingContainerView { destination in
                        handleOnboardingComplete(destination: destination)
                    }
                    .environmentObject(appUsageViewModel)
                    .environmentObject(subscriptionManager)
                }
            }
            .animation(.easeInOut, value: onboardingStep)
        }
    }

    private func handleDeviceSelection(mode: DeviceMode, name: String) {
        deviceName = name
        deviceModeManager.setDeviceMode(mode, deviceName: name)
        onboardingStep = mode == .parentDevice ? .parentFlow : .childFlow
    }

    private func handleOnboardingComplete(destination: OnboardingContainerView.OnboardingDestination) {
        childComplete = true
        // The RootView will automatically navigate based on the completed state
    }
}

// MARK: - Shared Intro Steps

private struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Hero Image Card
            OnboardingHeroCard(
                imageName: "onboarding_0_1",
                title: "Turn Screen Time Into Learning Time",
                subtitle: "Your child earns screen time by learning. The more they learn, the more they unlock.",
                aspectRatio: 0.65
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer(minLength: 24)

            // Feature rows
            VStack(alignment: .leading, spacing: 16) {
                IntroFeatureRow(
                    iconName: "star.fill",
                    title: "Earn by learning",
                    subtitle: "Educational apps earn points automatically"
                )

                IntroFeatureRow(
                    iconName: "gamecontroller.fill",
                    title: "Unlock rewards",
                    subtitle: "Points unlock games and fun apps"
                )

                IntroFeatureRow(
                    iconName: "chart.line.uptrend.xyaxis",
                    title: "Monitor progress",
                    subtitle: "Track learning time from any device"
                )
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)

            Spacer(minLength: 24)

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 420)
                    .frame(height: 56)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }
}

private struct IntroFeatureRow: View {
    let iconName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}
