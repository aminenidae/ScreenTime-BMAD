import SwiftUI

// MARK: - Activation Step Model

private struct ActivationStepCard: Identifiable {
    let id: Int
    let imageName: String
    let stepNumber: String
    let title: String
    let subtitle: String
}

/// Screen 7: Activation (C7) with image cards
/// Guides user on first actions after setup completion with visual step cards
/// Adapts to iPad with side-by-side layout and landscape with smaller cards
struct Screen7_ActivationView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var visibleSteps: Set<Int> = []
    @State private var animationStarted = false

    let onShowChildDashboard: () -> Void
    let onShowParentDashboard: () -> Void

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    /// Delay between each step animation (in seconds)
    private let stepAnimationDelay: Double = 2.0

    private let steps: [ActivationStepCard] = [
        ActivationStepCard(id: 0, imageName: "onboarding_C7_1", stepNumber: "1", title: "Discuss With Your Child", subtitle: "Explain The Learning & Reward System Together"),
        ActivationStepCard(id: 1, imageName: "onboarding_C7_2", stepNumber: "2", title: "Let It Run", subtitle: "Try Not To Adjust For 48 Hours. Let Them Experience The Rhythm."),
        ActivationStepCard(id: 2, imageName: "onboarding_C7_3", stepNumber: "3", title: "Check Progress", subtitle: "After 3 Days, Review Learning And Ask \"Does This Feel Fair?\"")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Your System Is Live")
                    .font(.system(size: layout.isRegular ? 32 : 28, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Here's What To Do Next With Your Child")
                    .font(.system(size: layout.isRegular ? 18 : 16, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.isLandscape ? 12 : 20)
            .frame(maxWidth: 600)

            // Step Image Cards - Vertical scroll with staggered animation
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: layout.cardSpacing) {
                        ForEach(steps) { step in
                            ActivationImageCard(step: step, layout: layout, isVisible: visibleSteps.contains(step.id))
                                .id(step.id)
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 8)
                }
                .onChange(of: visibleSteps) { newValue in
                    // Auto-scroll to the latest visible step
                    if let maxStep = newValue.max() {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(maxStep, anchor: .center)
                        }
                    }
                }
            }

            Spacer(minLength: layout.isLandscape ? 16 : 24)

            // Primary CTA
            Button(action: {
                completeOnboarding()
                onShowChildDashboard()
            }) {
                Text("Show Child Dashboard")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, 12)

            // Secondary CTA
            Button(action: {
                completeOnboarding()
                onShowParentDashboard()
            }) {
                Text("Go To Parent Dashboard")
                    .font(.system(size: 16, weight: .regular))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.card(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .cornerRadius(12)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, layout.isLandscape ? 16 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 7)
            onboarding.logEvent("onboarding_completed")
            startStepAnimations()
        }
    }

    private func completeOnboarding() {
        onboarding.onboardingComplete = true
    }

    /// Starts the staggered step animations with 2-second delays
    private func startStepAnimations() {
        guard !animationStarted else { return }
        animationStarted = true

        for step in steps {
            let delay = Double(step.id) * stepAnimationDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    _ = visibleSteps.insert(step.id)
                }
            }
        }
    }
}

// MARK: - Activation Image Card

private struct ActivationImageCard: View {
    let step: ActivationStepCard
    let layout: ResponsiveCardLayout
    let isVisible: Bool

    /// Card height - responsive based on device
    private var cardHeight: CGFloat {
        if layout.isIpad {
            return 220
        } else if layout.isLandscape {
            return 140
        } else {
            return 160
        }
    }

    /// Vertical offset for enter animation (enters from bottom)
    private var enterOffset: CGFloat {
        isVisible ? 0 : 60
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background image - explicitly sized to geometry
                Image(step.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: cardHeight)
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.55)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: cardHeight)

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.stepNumber)
                        .font(.system(size: layout.isIpad ? 32 : 20, weight: .bold))
                        .foregroundColor(.white)

                    Text(step.title)
                        .font(.system(size: layout.isIpad ? 20 : 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(step.subtitle)
                        .font(.system(size: layout.isIpad ? 14 : 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(layout.isIpad ? 20 : 10)
            }
        }
        .frame(height: cardHeight)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(isVisible ? 0.15 : 0.05), radius: isVisible ? 12 : 4, x: 0, y: isVisible ? 6 : 2)
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: enterOffset)
        .scaleEffect(isVisible ? 1.0 : 0.9)
    }
}

#Preview {
    Screen7_ActivationView(
        onShowChildDashboard: {},
        onShowParentDashboard: {}
    )
    .environmentObject(OnboardingStateManager())
}
