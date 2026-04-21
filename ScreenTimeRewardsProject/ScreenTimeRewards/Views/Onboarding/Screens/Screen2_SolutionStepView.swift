import SwiftUI

// MARK: - Solution Step Model

struct SolutionStep: Identifiable {
    let id: Int
    let imageName: String
    let stepNumber: Int
    let title: String
    let subtitle: String
}

/// Screen 2: Solution (split into 5 dedicated full-screen steps)
/// Each step is structured for both real onboarding AND ASC screenshot capture:
/// - Large OCR-readable title carries ASO tokens
/// - Hero image is full-width, centered
/// - One screen = one step = one capturable screenshot
struct Screen2_SolutionStepView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    /// 5 solution steps. Titles are OCR-targeted for App Store search indexing
    /// (Apple indexes screenshot caption text since June 2025).
    /// Token coverage anchors:
    /// - Step 2: `points` (Pop 9), `screen time`
    /// - Step 3: `unlock apps` (Pop 5 / Diff 41 — exceptional)
    /// - Step 5: `limit screen time` (Pop 23 / Diff 55) — mirrors locked Subtitle for compounded weight
    static let steps: [SolutionStep] = [
        SolutionStep(
            id: 0,
            imageName: "onboarding_C2_1",
            stepNumber: 1,
            title: "PARENTS SET LEARNING GOALS",
            subtitle: "Together, you and your child agree on the daily target."
        ),
        SolutionStep(
            id: 1,
            imageName: "onboarding_C2_2",
            stepNumber: 2,
            title: "KIDS EARN SCREEN TIME",
            subtitle: "Learning apps award points for every minute of progress."
        ),
        SolutionStep(
            id: 2,
            imageName: "onboarding_C2_3",
            stepNumber: 3,
            title: "UNLOCK APPS AUTOMATICALLY",
            subtitle: "No asking. No nagging. Apps unlock when goals are met."
        ),
        SolutionStep(
            id: 3,
            imageName: "onboarding_C2_4",
            stepNumber: 4,
            title: "KIDS PLAY GUILT-FREE",
            subtitle: "Reward apps unlock — entertainment they've earned."
        ),
        SolutionStep(
            id: 4,
            imageName: "onboarding_C2_5",
            stepNumber: 5,
            title: "LIMIT SCREEN TIME, AUTOMATICALLY",
            subtitle: "Time's up. The app locks. No negotiations needed."
        )
    ]

    private var currentStep: SolutionStep {
        let idx = max(0, min(onboarding.solutionStepIndex, Self.steps.count - 1))
        return Self.steps[idx]
    }

    private var isLastStep: Bool {
        onboarding.solutionStepIndex >= Self.steps.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Step indicator chip
            stepIndicatorChip

            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Title — large, OCR-target
            Text(currentStep.title)
                .font(.system(size: titleFontSize, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .tracking(2)
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: 600)
                .id("title-\(currentStep.id)")
                .transition(.opacity)

            Spacer(minLength: layout.isLandscape ? 12 : 20)

            // Hero image — full-width, large
            heroImage
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: layout.heroCardMaxWidth)
                .id("image-\(currentStep.id)")
                .transition(.opacity)

            Spacer(minLength: layout.isLandscape ? 12 : 20)

            // Subtitle — readable, supporting
            Text(currentStep.subtitle)
                .font(.system(size: subtitleFontSize, weight: .regular))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: 600)
                .id("subtitle-\(currentStep.id)")
                .transition(.opacity)

            Spacer(minLength: layout.isLandscape ? 12 : 20)

            // Progress dots
            progressDots
                .padding(.bottom, layout.isLandscape ? 8 : 12)

            // Primary CTA
            Button(action: handleAdvance) {
                Text(isLastStep ? "Continue" : "Next")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, layout.horizontalPadding)

            // Simulator-only: skip to paywall (parity with Screen 1)
            // Gated behind UserDefaults so it can be hidden during ASC screenshot capture.
            #if targetEnvironment(simulator)
            if UserDefaults.standard.bool(forKey: "showSimulatorDebugButtons") {
                Button("📸 Skip to Paywall (Simulator Only)") {
                    onboarding.skipToPaywall()
                }
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .padding(.top, 8)
            }
            #endif

            Spacer(minLength: layout.isLandscape ? 12 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 2)
        }
        .onChange(of: onboarding.solutionStepIndex) { newIndex in
            onboarding.logEvent("onboarding_screen2_step\(newIndex + 1)_shown")
        }
    }

    // MARK: - Sub-views

    private var stepIndicatorChip: some View {
        Text("STEP \(currentStep.stepNumber) OF \(Self.steps.count)")
            .font(.system(size: 13, weight: .semibold))
            .tracking(2)
            .foregroundColor(AppTheme.vibrantTeal)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(AppTheme.vibrantTeal.opacity(0.12))
            .cornerRadius(AppTheme.CornerRadius.small)
    }

    private var heroImage: some View {
        GeometryReader { geometry in
            Image(currentStep.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: heroHeight)
                .clipped()
                .cornerRadius(AppTheme.CornerRadius.large)
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        }
        .frame(height: heroHeight)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Self.steps.indices, id: \.self) { index in
                Circle()
                    .fill(index == onboarding.solutionStepIndex ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.25))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == onboarding.solutionStepIndex ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: onboarding.solutionStepIndex)
            }
        }
    }

    // MARK: - Layout helpers

    private var titleFontSize: CGFloat {
        if layout.isIpad { return 44 }
        return layout.isLandscape ? 28 : 34
    }

    private var subtitleFontSize: CGFloat {
        if layout.isIpad { return 22 }
        return layout.isLandscape ? 16 : 18
    }

    private var heroHeight: CGFloat {
        if layout.isIpad { return 360 }
        return layout.isLandscape ? 200 : 320
    }

    // MARK: - Actions

    private func handleAdvance() {
        onboarding.advanceSolutionStep(totalSteps: Self.steps.count)
    }
}

#Preview {
    Screen2_SolutionStepView()
        .environmentObject(OnboardingStateManager())
}
