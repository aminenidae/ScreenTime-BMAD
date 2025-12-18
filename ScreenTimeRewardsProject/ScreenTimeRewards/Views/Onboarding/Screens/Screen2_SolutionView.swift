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
/// Adapts to iPad with grid layout and landscape with smaller cards
struct Screen2_SolutionView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var visibleSteps: Set<Int> = []

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    private let steps: [SolutionStepCard] = [
        SolutionStepCard(id: 0, imageName: "onboarding_C2_1", stepNumber: "1", title: "Agree on a Goal", subtitle: "Parent & child discuss learning targets"),
        SolutionStepCard(id: 1, imageName: "onboarding_C2_2", stepNumber: "2", title: "Child Learns", subtitle: "Educational apps unlock with every milestone"),
        SolutionStepCard(id: 2, imageName: "onboarding_C2_3", stepNumber: "3", title: "Automatic Unlock", subtitle: "No asking. Just automatic rewards."),
        SolutionStepCard(id: 3, imageName: "onboarding_C2_4", stepNumber: "4", title: "Enjoy Rewards", subtitle: "Guilt-free entertainment they've earned"),
        SolutionStepCard(id: 4, imageName: "onboarding_C2_5", stepNumber: "5", title: "Auto-Lock", subtitle: "Time's up. No negotiations. Peaceful transition.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 8) {
                Text("What if your child\n**agreed** to the rules?")
                    .font(.system(size: layout.isRegular ? 30 : 26, weight: .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Learning automatically unlocks AND locks reward apps.")
                    .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.horizontalPadding)
            }
            .padding(.vertical, layout.isLandscape ? 12 : 20)
            .frame(maxWidth: 600)

            // 5-Step Image Cards - Grid on iPad, HScroll on iPhone
            if layout.useGridLayout {
                // iPad: Scrollable grid
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: layout.cardSpacing),
                            GridItem(.flexible(), spacing: layout.cardSpacing)
                        ],
                        spacing: layout.cardSpacing
                    ) {
                        ForEach(steps) { step in
                            SolutionStepImageCard(step: step, layout: layout, isVisible: visibleSteps.contains(step.id))
                                .onAppear {
                                    animateStepAppearance(stepId: step.id)
                                }
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 8)
                }
            } else {
                // iPhone: Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: layout.cardSpacing) {
                        ForEach(steps) { step in
                            SolutionStepImageCard(step: step, layout: layout, isVisible: visibleSteps.contains(step.id))
                                .onAppear {
                                    animateStepAppearance(stepId: step.id)
                                }
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 8)
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
                Text("See what you'll set up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: 12)

            // Secondary link
            Button(action: {
                onboarding.skipToSetup()
            }) {
                Text("Skip to setup")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer(minLength: layout.isLandscape ? 12 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 2)
        }
    }

    private func animateStepAppearance(stepId: Int) {
        let delay = Double(stepId) * 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.4)) {
                _ = visibleSteps.insert(stepId)
            }
        }
    }
}

// MARK: - Solution Step Image Card

private struct SolutionStepImageCard: View {
    let step: SolutionStepCard
    let layout: ResponsiveCardLayout
    let isVisible: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image
            Image(step.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: layout.useGridLayout ? nil : layout.scrollCardWidth, height: layout.scrollCardHeight)
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

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(step.stepNumber)
                    .font(.system(size: layout.isRegular ? 32 : 28, weight: .bold))
                    .foregroundColor(.white)

                Text(step.title)
                    .font(.system(size: layout.isRegular ? 20 : 18, weight: .semibold))
                    .foregroundColor(.white)

                Text(step.subtitle)
                    .font(.system(size: layout.isRegular ? 14 : 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .padding(layout.isRegular ? 16 : 12)
        }
        .frame(width: layout.useGridLayout ? nil : layout.scrollCardWidth, height: layout.scrollCardHeight)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .opacity(isVisible ? 1.0 : 0.5)
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .animation(.easeOut(duration: 0.4), value: isVisible)
    }
}

#Preview {
    Screen2_SolutionView()
        .environmentObject(OnboardingStateManager())
}
