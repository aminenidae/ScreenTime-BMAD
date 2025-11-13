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
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 20) {
                // App Icon or Logo placeholder
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal, AppTheme.sunnyYellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                Text("Turn Screen Time\nInto Learning Time")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text("Your child earns screen time by learning. The more they learn, the more they unlock.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 480)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
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
