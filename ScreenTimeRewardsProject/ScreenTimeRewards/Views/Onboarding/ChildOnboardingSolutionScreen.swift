import SwiftUI

/// Screen 2: Solution Visualization - Animated 3-step sequence explaining how it works
struct ChildOnboardingSolutionScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var currentAnimationStep = 0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressIndicator(currentStep: 1)

                Spacer()
                    .frame(height: 40)

                // Headline
                Text("What If Learning Apps AUTOMATICALLY Unlocked Reward Apps?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 40)

                // 4-Step Animation
                VStack(spacing: 24) {
                    animationStep(
                        number: 1,
                        emoji: "📚",
                        title: "Child learns 30 min",
                        subtitle: "Khan Academy active",
                        isActive: currentAnimationStep >= 1
                    )

                    // Arrow
                    Image(systemName: "arrow.down")
                        .font(.system(size: 20))
                        .foregroundColor(currentAnimationStep >= 2 ? AppTheme.vibrantTeal : .secondary.opacity(0.3))
                        .scaleEffect(currentAnimationStep >= 2 ? 1.2 : 1.0)
                        .animation(.spring(response: 0.5), value: currentAnimationStep)

                    animationStep(
                        number: 2,
                        emoji: "🔓",
                        title: "Rewards unlock automatically",
                        subtitle: "No manual intervention",
                        isActive: currentAnimationStep >= 2
                    )

                    // Arrow
                    Image(systemName: "arrow.down")
                        .font(.system(size: 20))
                        .foregroundColor(currentAnimationStep >= 3 ? AppTheme.sunnyYellow : .secondary.opacity(0.3))
                        .scaleEffect(currentAnimationStep >= 3 ? 1.2 : 1.0)
                        .animation(.spring(response: 0.5), value: currentAnimationStep)

                    animationStep(
                        number: 3,
                        emoji: "🎬",
                        title: "Child enjoys YouTube 30 min",
                        subtitle: "Reward time earned",
                        isActive: currentAnimationStep >= 3
                    )

                    // Arrow
                    Image(systemName: "arrow.down")
                        .font(.system(size: 20))
                        .foregroundColor(currentAnimationStep >= 4 ? AppTheme.playfulCoral : .secondary.opacity(0.3))
                        .scaleEffect(currentAnimationStep >= 4 ? 1.2 : 1.0)
                        .animation(.spring(response: 0.5), value: currentAnimationStep)

                    animationStep(
                        number: 4,
                        emoji: "🔒",
                        title: "Rewards lock automatically",
                        subtitle: "Cycle complete - Repeats daily",
                        isActive: currentAnimationStep >= 4
                    )
                }
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 30)

                // Value proposition
                VStack(spacing: 8) {
                    Text("Turn learning into a game kids actually want to play.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("No negotiations. No guilt. No manual intervention.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("The system works FOR you, not against you.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    // Continue
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.vibrantTeal)
                            .cornerRadius(16)
                    }

                    // Back
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - Subviews

    private func animationStep(
        number: Int,
        emoji: String,
        title: String,
        subtitle: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 16) {
            // Number badge
            ZStack {
                Circle()
                    .fill(isActive ? AppTheme.vibrantTeal : Color.secondary.opacity(0.2))
                    .frame(width: 36, height: 36)

                Text("\(number)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isActive ? .white : .secondary)
            }
            .scaleEffect(isActive ? 1.0 : 0.8)

            // Emoji
            Text(emoji)
                .font(.system(size: 40))
                .scaleEffect(isActive ? 1.0 : 0.8)
                .opacity(isActive ? 1.0 : 0.4)

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isActive ? AppTheme.textPrimary(for: colorScheme) : .secondary)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? AppTheme.card(for: colorScheme) : Color.clear)
                .shadow(
                    color: isActive ? Color.black.opacity(0.08) : .clear,
                    radius: isActive ? 8 : 0,
                    x: 0,
                    y: 4
                )
        )
        .animation(.spring(response: 0.6), value: isActive)
    }

    // MARK: - Animation Logic

    private func startAnimation() {
        // Sequence the animation steps (4 steps total)
        currentAnimationStep = 0

        // Step 1: Learning (0.3s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5)) {
                currentAnimationStep = 1
            }
        }

        // Step 2: Auto-unlock (1.0s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.5)) {
                currentAnimationStep = 2
            }
        }

        // Step 3: Reward time (1.7s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.spring(response: 0.5)) {
                currentAnimationStep = 3
            }
        }

        // Step 4: Auto-lock (2.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.spring(response: 0.5)) {
                currentAnimationStep = 4
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ChildOnboardingSolutionScreen(
        onContinue: { print("Continue") },
        onBack: { print("Back") }
    )
}
