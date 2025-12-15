import SwiftUI

/// Screen 1: Welcome - First impression for child onboarding
struct ChildOnboardingWelcomeScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let onContinue: () -> Void

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Hero Section
                VStack(spacing: 24) {
                    // Hero Illustration
                    heroIllustration

                    // Headline
                    Text("THE 'FIVE MORE MINUTES' BATTLE CAN END TODAY")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // Problem statement
                    VStack(spacing: 12) {
                        Text("Every parent knows this conversation.")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .multilineTextAlignment(.center)

                        Text("Your child begs for more screen time.\nYou negotiate. You compromise.\nYou worry about how much they're actually learning.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("There's a better way.")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()

                // Continue Button
                PulsingButton(shouldPulse: true) {
                    Button(action: onContinue) {
                        Text("See How It Works")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                LinearGradient(
                                    colors: [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)

                // Note: Progress indicator hidden on first screen (as per plan)
            }
        }
    }

    // MARK: - Subviews

    private var heroIllustration: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.vibrantTeal.opacity(0.2),
                            AppTheme.sunnyYellow.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 200, height: 200)

            // Game controller + book fusion
            HStack(spacing: -20) {
                Image(systemName: "book.fill")
                    .font(.system(size: 70))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .rotationEffect(.degrees(-15))

                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 70))
                    .foregroundColor(AppTheme.sunnyYellow)
                    .rotationEffect(.degrees(15))
            }
        }
    }

}

// MARK: - Preview
#Preview {
    ChildOnboardingWelcomeScreen {
        print("Continue tapped")
    }
}
