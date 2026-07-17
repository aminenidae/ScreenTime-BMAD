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
                        AppAnalytics.shared.track(.onboardingWelcomeCtaTapped)
                        withAnimation { onboardingStep = .deviceSelection }
                    }
                    .onAppear { AppAnalytics.shared.track(.onboardingWelcomeViewed) }

                case .deviceSelection:
                    DeviceSelectionView(
                        showBackButton: true,
                        onDeviceSelected: { mode, name in
                            handleDeviceSelection(mode: mode, name: name)
                        },
                        onBack: { onboardingStep = .welcome }
                    )
                    .onAppear { AppAnalytics.shared.track(.onboardingDeviceSelectionViewed) }

                case .parentFlow:
                    ParentOnboardingCoordinator(
                        deviceName: deviceName,
                        onBack: { onboardingStep = .deviceSelection },
                        onComplete: { onboardingStep = .welcome }
                    )
                    .environmentObject(subscriptionManager)

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
        AppAnalytics.shared.track(.onboardingDeviceTypeSelected, parameters: [
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
            let imageWidth = max(100, geometry.size.width - 48) // 24 padding on each side, minimum 100
            let imageHeight: CGFloat = isLandscape ? 160 : 260

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero image card with gradient overlay + caption
                    ZStack(alignment: .bottomLeading) {
                        Image("onboarding_0_1")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: imageWidth, height: imageHeight)
                            .clipped()

                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: imageWidth, height: imageHeight)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Parental Control, Made Simple")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .textCase(.uppercase)
                                .tracking(1.5)
                            Text("You set what's safe. They earn what's fun.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                    }
                    .frame(width: imageWidth, height: imageHeight)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Headline
                    Text("Real Parental Control.\nZero Arguments.")
                        .font(.system(size: isLandscape ? 20 : 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.horizontal, 24)
                        .padding(.top, isLandscape ? 12 : 20)

                    Spacer(minLength: isLandscape ? 12 : 16)

                    // Confirmation lines
                    VStack(alignment: .leading, spacing: isLandscape ? 10 : 16) {
                        ConfirmationLine(
                            text: String(localized: "You decide what's safe — enforced automatically"),
                            colorScheme: colorScheme
                        )
                        ConfirmationLine(
                            text: String(localized: "Learning apps earn real time on the apps they love"),
                            colorScheme: colorScheme
                        )
                        ConfirmationLine(
                            text: String(localized: "No timers to manage. No fights to referee."),
                            colorScheme: colorScheme
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: isLandscape ? 12 : 20)

                    // Expectation-setter: tells the night-time solo installer the cost
                    // (3 min) and that her own phone is a valid starting point — the two
                    // facts the funnel showed were missing at this decision moment.
                    Text("Setup takes about 3 minutes — start on your phone or your child's.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.bottom, isLandscape ? 8 : 12)

                    Button(action: onContinue) {
                        Text("Start Setup")
                            .font(.system(size: 18, weight: .bold)) // Keep at 18 for now, standardize later
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.vibrantTeal)
                            .cornerRadius(AppTheme.CornerRadius.medium)
                            .textCase(.uppercase)
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

private struct ConfirmationLine: View {
    let text: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(AppTheme.vibrantTeal)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 400, alignment: .leading)
    }
}
