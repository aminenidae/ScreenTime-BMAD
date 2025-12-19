import SwiftUI

// MARK: - Step Card Model

private struct SolutionStepCard: Identifiable {
    let id: Int
    let imageName: String
    let stepNumber: String
    let title: String
    let subtitle: String
}

/// Screen 2: Solution (5-Step Cycle with Image Cards)
/// Explains the unique 5-step system with visual image cards
/// Features staggered enter animations with auto-scroll to focus on each step
/// Adapts to iPad with grid layout and landscape with smaller cards
struct Screen2_SolutionView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var visibleSteps: Set<Int> = []
    @State private var animationStarted = false

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    /// Delay between each step animation (in seconds)
    private let stepAnimationDelay: Double = 2.0

    private let steps: [SolutionStepCard] = [
        SolutionStepCard(id: 0, imageName: "onboarding_C2_1", stepNumber: "1", title: "Agree On A Goal", subtitle: "Parent & Child Discuss Learning Targets"),
        SolutionStepCard(id: 1, imageName: "onboarding_C2_2", stepNumber: "2", title: "Child Learns", subtitle: "Educational Apps Unlock With Every Milestone"),
        SolutionStepCard(id: 2, imageName: "onboarding_C2_3", stepNumber: "3", title: "Automatic Unlock", subtitle: "No Asking. Just Automatic Rewards."),
        SolutionStepCard(id: 3, imageName: "onboarding_C2_4", stepNumber: "4", title: "Enjoy Rewards", subtitle: "Guilt-Free Entertainment They've Earned"),
        SolutionStepCard(id: 4, imageName: "onboarding_C2_5", stepNumber: "5", title: "Auto-Lock", subtitle: "Time's Up. No Negotiations. Peaceful Transition.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 8) {
                Text("What If Your Child\n**Agreed** To The Rules?")
                    .font(.system(size: layout.isRegular ? 30 : 26, weight: .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Learning Automatically Unlocks AND Locks Reward Apps.")
                    .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.horizontalPadding)
            }
            .padding(.vertical, layout.isLandscape ? 12 : 20)
            .frame(maxWidth: 600)

            // 5-Step Image Cards - Single column, full-width, stacked vertically with auto-scroll
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: layout.cardSpacing) {
                        ForEach(steps) { step in
                            SolutionStepImageCard(step: step, layout: layout, isVisible: visibleSteps.contains(step.id))
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

            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Supporting copy
            Text("The app is the referee, not the bad guy. Because your child helped create the rules, they follow them willingly.")
                .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, layout.isLandscape ? 12 : 20)
                .frame(maxWidth: 600)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("See What You'll Set Up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: layout.isLandscape ? 12 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 2)
            startStepAnimations()
        }
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

// MARK: - Solution Step Image Card

private struct SolutionStepImageCard: View {
    let step: SolutionStepCard
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
    Screen2_SolutionView()
        .environmentObject(OnboardingStateManager())
}
