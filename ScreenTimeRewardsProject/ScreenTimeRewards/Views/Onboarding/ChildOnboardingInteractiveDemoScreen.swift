import SwiftUI

/// Screen 4: Interactive Demo - MOST CRITICAL SCREEN
/// Demonstrates the earn/unlock mechanic with hands-on experience
struct ChildOnboardingInteractiveDemoScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let onContinue: () -> Void
    let onBack: () -> Void

    // Animation states
    @State private var learningPoints = 0
    @State private var displayPoints = 0
    @State private var isUnlocked = false
    @State private var showCelebration = false
    @State private var showFloatingBook = false
    @State private var hasInteracted = false
    @State private var buttonScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressIndicator(currentStep: 2)

                Spacer()
                    .frame(height: 30)

                // Headline
                VStack(spacing: 12) {
                    Text("See Your System In Action")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    if !hasInteracted {
                        VStack(spacing: 8) {
                            Text("This is exactly what your child will see.")
                                .font(.system(size: 15))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .multilineTextAlignment(.center)

                            Text("The system tracks automatically.\nNo app switching. No manual timing.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 40)

                // Demo Area
                VStack(spacing: 24) {
                    // Locked/Unlocked game icon
                    UnlockAnimation(
                        isUnlocked: $isUnlocked,
                        iconName: "gamecontroller.fill"
                    )
                    .frame(height: 120)

                    // Game label
                    Text(isUnlocked ? "Unlocked! 🎉" : "Locked Game")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : .secondary)
                        .animation(.easeInOut, value: isUnlocked)

                    // Progress bar
                    VStack(spacing: 8) {
                        HStack {
                            Text("Points")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            AnimatedNumberCounter(
                                targetNumber: learningPoints,
                                currentNumber: $displayPoints,
                                duration: 0.5
                            )
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.sunnyYellow)
                            Text("/ 10")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 24)

                                // Progress fill
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.sunnyYellow, AppTheme.sunnyYellow.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geometry.size.width * CGFloat(displayPoints) / 10.0,
                                        height: 24
                                    )
                                    .animation(.spring(response: 0.6), value: displayPoints)
                            }
                        }
                        .frame(height: 24)
                    }
                    .padding(.horizontal, 32)

                    // Floating book overlay
                    if showFloatingBook {
                        FloatingElement(
                            emoji: "📚",
                            fromY: 0,
                            toY: -100,
                            isAnimating: $showFloatingBook
                        )
                        .frame(height: 100)
                    }
                }
                .padding(.vertical, 30)

                Spacer()
                    .frame(height: 30)

                // Interactive button
                if !hasInteracted {
                    PulsingButton(shouldPulse: !hasInteracted) {
                        Button(action: triggerLearningAnimation) {
                            HStack(spacing: 12) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 24))
                                Text("Try Learning! 📚")
                                    .font(.system(size: 22, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(
                                LinearGradient(
                                    colors: [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: AppTheme.vibrantTeal.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                    }
                    .scaleEffect(buttonScale)
                    .padding(.horizontal, 24)
                } else {
                    // Explanation text after interaction
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                            Text("Just learning leading to rewards.")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }

                        Text("Automatic tracking. Zero intervention required.")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    // Continue (only enabled after interaction)
                    Button(action: onContinue) {
                        Text(hasInteracted ? "Continue Setup" : "Try the demo first")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(hasInteracted ? AppTheme.vibrantTeal : Color.secondary.opacity(0.4))
                            .cornerRadius(16)
                    }
                    .disabled(!hasInteracted)

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

            // Confetti overlay
            if showCelebration {
                OnboardingConfettiView(isActive: showCelebration)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Add subtle button pulse
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                buttonScale = 1.05
            }
        }
    }

    // MARK: - Animation Logic

    private func triggerLearningAnimation() {
        guard !hasInteracted else { return }

        hasInteracted = true
        buttonScale = 1.0 // Stop pulsing

        // Phase 1: Floating book appears (0s)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showFloatingBook = true
        }

        // Phase 2: Points counter animation (0.5s delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                learningPoints = 10
            }
        }

        // Phase 3: Unlock animation (1.0s delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isUnlocked = true
            }
            // Trigger haptic
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
        }

        // Phase 4: Confetti celebration (1.2s delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showCelebration = true
            // Trigger success haptic
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
        }

        // Phase 5: Hide floating book (1.5s delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showFloatingBook = false
            }
        }

        // Phase 6: Stop confetti (4s delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            showCelebration = false
        }
    }
}

// MARK: - Preview
#Preview {
    ChildOnboardingInteractiveDemoScreen(
        onContinue: { print("Continue") },
        onBack: { print("Back") }
    )
}
