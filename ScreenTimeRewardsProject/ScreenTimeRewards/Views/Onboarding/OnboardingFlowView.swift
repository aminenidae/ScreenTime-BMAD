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
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var isLandscape: Bool {
        vSizeClass == .compact
    }

    var body: some View {
        GeometryReader { geometry in
            let imageWidth = geometry.size.width - 48 // 24 padding on each side
            let imageHeight: CGFloat = isLandscape ? 160 : 260

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero Image (no text overlay)
                    Image("onboarding_0_1")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageWidth, height: imageHeight)
                        .clipped()
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    // Title slogan below image
                    Text("We Designed The Only Way\nKids' Screen Time Should Be")
                        .font(.system(size: isLandscape ? 18 : 20, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(.horizontal, 24)
                        .padding(.top, isLandscape ? 12 : 20)

                    Spacer(minLength: isLandscape ? 12 : 16)

                    // Feature rows with custom icons
                    VStack(alignment: .leading, spacing: isLandscape ? 10 : 14) {
                        IntroFeatureRow(
                            imageName: "onboarding_icon_1",
                            title: "Earn By Learning",
                            subtitle: "Educational Apps Earn Points Automatically"
                        )

                        IntroFeatureRow(
                            imageName: "onboarding_icon_2",
                            title: "Unlock Rewards",
                            subtitle: "Points Unlock Games And Fun Apps"
                        )

                        IntroFeatureRow(
                            imageName: "onboarding_icon_3",
                            title: "Monitor Progress",
                            subtitle: "Track Learning Time From Any Device"
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: isLandscape ? 12 : 20)

                    Button(action: onContinue) {
                        Text("Get Started")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.vibrantTeal)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }
}

private struct IntroFeatureRow: View {
    let imageName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))

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
