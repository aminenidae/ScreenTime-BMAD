import SwiftUI

// MARK: - Solution Step Model

struct SolutionStep: Identifiable {
    let id: Int
    let imageName: String
    let stepNumber: Int
    let title: String
    let subtitle: String
}

/// Value slides — the "how it works" pitch, trimmed to the 3 strongest steps and
/// written for parent conversion (sentence case, skippable). Decoupled from ASO: the
/// keyword-loaded App Store screenshots are produced separately, so these no longer
/// double as OCR screenshot sources.
struct Screen2_SolutionStepView: View {
    /// Called when the last value slide is passed. Self-contained: the slides now sit
    /// in the shared front-of-funnel (before the "whose phone?" question), so they no
    /// longer depend on the child-flow OnboardingStateManager.
    let onComplete: () -> Void
    /// Called when Back is tapped on the first slide (earlier slides step back in place).
    let onBack: () -> Void

    @State private var stepIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    /// The 3 strongest steps (earn → auto-unlock → time's up), sentence-cased for
    /// parents. Trimmed from the old 5-slide ASO carousel per the onboarding redesign.
    static let steps: [SolutionStep] = [
        SolutionStep(
            id: 0,
            imageName: "onboarding_C2_2",
            stepNumber: 1,
            title: String(localized: "Kids earn screen time"),
            subtitle: String(localized: "Learning apps award points for every minute of progress.")
        ),
        SolutionStep(
            id: 1,
            imageName: "onboarding_C2_3",
            stepNumber: 2,
            title: String(localized: "Apps unlock automatically"),
            subtitle: String(localized: "No asking. No nagging. Apps unlock when goals are met.")
        ),
        SolutionStep(
            id: 2,
            imageName: "onboarding_C2_5",
            stepNumber: 3,
            title: String(localized: "Time's up, automatically"),
            subtitle: String(localized: "Time's up. The app locks. No negotiations needed.")
        )
    ]

    private var currentStep: SolutionStep {
        let idx = max(0, min(stepIndex, Self.steps.count - 1))
        return Self.steps[idx]
    }

    private var isLastStep: Bool {
        stepIndex >= Self.steps.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back (left) + Skip (right). Back steps through slides, then out to welcome.
            HStack {
                OnboardingBackButton(action: handleBack)

                Spacer()

                Button(action: {
                    AppAnalytics.shared.trackOnboarding(.onboardingSkipTapped, parameters: ["screen_name": "value_slides"])
                    onComplete()
                }) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 8)

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
                Text(isLastStep ? String(localized: "Continue") : String(localized: "Next"))
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.CornerRadius.medium)
            }
            .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: layout.isLandscape ? 12 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            AppAnalytics.shared.trackOnboarding(.onboardingScreenViewed, parameters: ["screen_name": "value_slides"])
        }
    }

    // MARK: - Sub-views

    private var stepIndicatorChip: some View {
        Text("Step \(currentStep.stepNumber) of \(Self.steps.count)")
            .font(.system(size: 13, weight: .semibold))
            .tracking(2)
            .foregroundColor(AppTheme.accentText(for: colorScheme))
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
                    .fill(index == stepIndex ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.25))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == stepIndex ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: stepIndex)
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
        if stepIndex < Self.steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                stepIndex += 1
            }
        } else {
            onComplete()
        }
    }

    private func handleBack() {
        if stepIndex > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                stepIndex -= 1
            }
        } else {
            onBack()
        }
    }
}

#Preview {
    Screen2_SolutionStepView(onComplete: {}, onBack: {})
}
