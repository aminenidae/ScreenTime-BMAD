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

    let onShowChildDashboard: () -> Void
    let onShowParentDashboard: () -> Void

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    private let steps: [ActivationStepCard] = [
        ActivationStepCard(id: 0, imageName: "onboarding_C7_1", stepNumber: "1", title: "Discuss with Your Child", subtitle: "Explain the learning & reward system together"),
        ActivationStepCard(id: 1, imageName: "onboarding_C7_2", stepNumber: "2", title: "Let It Run", subtitle: "Try not to adjust for 48 hours. Let them experience the rhythm.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Your system is live")
                    .font(.system(size: layout.isRegular ? 32 : 28, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Here's what to do next with your child")
                    .font(.system(size: layout.isRegular ? 18 : 16, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.isLandscape ? 12 : 20)
            .frame(maxWidth: 600)

            // Step Image Cards - Side by side on iPad, horizontal scroll on iPhone
            if layout.useSideBySideLayout {
                // iPad: Side by side
                HStack(spacing: layout.cardSpacing) {
                    ForEach(steps) { step in
                        ActivationImageCard(step: step, layout: layout)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: 700)
            } else {
                // iPhone: Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: layout.cardSpacing) {
                        ForEach(steps) { step in
                            ActivationImageCard(step: step, layout: layout)
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 8)
                }
            }

            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Additional text step (no image available)
            HStack(alignment: .top, spacing: 14) {
                Text("3")
                    .font(.system(size: layout.isRegular ? 20 : 18, weight: .bold))
                    .frame(width: layout.isRegular ? 48 : 40, height: layout.isRegular ? 48 : 40)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Check progress after 3 days")
                        .font(.system(size: layout.isRegular ? 18 : 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Look at how much learning they've done and ask, \"Does this still feel fair?\" Adjust goals if needed.")
                        .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(layout.isRegular ? 20 : 16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(14)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
            .padding(.horizontal, layout.horizontalPadding)
            .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 16 : 24)

            // Primary CTA
            Button(action: {
                completeOnboarding()
                onShowChildDashboard()
            }) {
                Text("Show child dashboard")
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
                Text("Go to parent dashboard")
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
        }
    }

    private func completeOnboarding() {
        onboarding.onboardingComplete = true
    }
}

// MARK: - Activation Image Card

private struct ActivationImageCard: View {
    let step: ActivationStepCard
    let layout: ResponsiveCardLayout

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image
            Image(step.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: layout.useSideBySideLayout ? nil : layout.scrollCardWidth,
                    height: layout.scrollCardHeight
                )
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
        .frame(
            width: layout.useSideBySideLayout ? nil : layout.scrollCardWidth,
            height: layout.scrollCardHeight
        )
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    Screen7_ActivationView(
        onShowChildDashboard: {},
        onShowParentDashboard: {}
    )
    .environmentObject(OnboardingStateManager())
}
