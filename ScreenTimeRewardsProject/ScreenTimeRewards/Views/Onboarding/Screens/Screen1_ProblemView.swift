import SwiftUI

/// Screen 1: Problem Recognition (C1)
/// Hero image showing the "five more minutes" struggle with empathetic messaging
struct Screen1_ProblemView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Hero Image Card (C1)
            ProblemHeroCard(layout: layout)
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: layout.heroCardMaxWidth)

            Spacer(minLength: layout.isLandscape ? 12 : 24)

            // Headline
            Text("The \"five more minutes\"\nbattle can end today")
                .font(.system(size: layout.isRegular ? 32 : 28, weight: .bold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 8 : 12)

            // Body copy
            Text("Every parent knows this conversation. Your child begs. You negotiate. You worry about learning. There's a better way.")
                .font(.system(size: layout.isRegular ? 18 : 16, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 16 : 32)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("Show me how")
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
                onboarding.logEvent("onboarding_screen1_skip_tapped")
                onboarding.skipToActivation()
            }) {
                Text("Skip for now")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer(minLength: layout.isLandscape ? 12 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 1)
        }
    }
}

// MARK: - Problem Hero Card

private struct ProblemHeroCard: View {
    let layout: ResponsiveCardLayout

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image
            Image("onboarding_C1")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: layout.heroCardHeight)
                .clipped()

            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.5)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            // Text overlay
            VStack(alignment: .leading, spacing: 4) {
                Text("The Daily Struggle")
                    .font(.system(size: layout.isRegular ? 24 : 20, weight: .semibold))
                    .foregroundColor(.white)

                Text("Sound familiar? Screen time negotiations don't have to be this hard.")
                    .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .padding(layout.isRegular ? 20 : 16)
        }
        .frame(height: layout.heroCardHeight)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

#Preview {
    Screen1_ProblemView()
        .environmentObject(OnboardingStateManager())
}
