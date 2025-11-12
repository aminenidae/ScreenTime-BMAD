import SwiftUI

/// Routes between the shared onboarding entry and the device-specific flows.
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
                    ChildOnboardingCoordinator(
                        deviceName: deviceName,
                        onBack: { onboardingStep = .deviceSelection },
                        onComplete: { onboardingStep = .welcome }
                    )
                }
            }
            .animation(.easeInOut, value: onboardingStep)
            .padding()
        }
    }

    private func handleDeviceSelection(mode: DeviceMode, name: String) {
        deviceName = name
        deviceModeManager.setDeviceMode(mode, deviceName: name)
        onboardingStep = mode == .parentDevice ? .parentFlow : .childFlow
    }
}

// MARK: - Shared Intro Steps

private struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("Welcome to ScreenTime Rewards")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Guide your family through a tailored onboarding experience for both parent and child devices.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 16) {
                IntroFeatureRow(
                    iconName: "sparkles",
                    title: "Show the value quickly",
                    subtitle: "Parents see remote monitoring tools right away."
                )

                IntroFeatureRow(
                    iconName: "person.2.fill",
                    title: "Device-specific flows",
                    subtitle: "Choose parent or child setup with custom steps."
                )

                IntroFeatureRow(
                    iconName: "lock.shield",
                    title: "Secure pairing",
                    subtitle: "Connect devices when you're ready—no rush."
                )
            }
            .frame(maxWidth: 520)

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 420)
                    .frame(height: 56)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
