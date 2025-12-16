import SwiftUI

// MARK: - Step Model

private struct SolutionStep: Identifiable {
    let id: Int
    let emoji: String
    let title: String
    let description: String
}

/// Screen 2: Solution (5-Step Cycle with Animation)
/// Explains the unique 5-step system that makes screen time management automatic
struct Screen2_SolutionView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleSteps: Set<Int> = []

    private let steps: [SolutionStep] = [
        SolutionStep(id: 0, emoji: "handshake", title: "The Agreement", description: "You and your child agree: \"30 min learning = 30 min YouTube. Deal?\""),
        SolutionStep(id: 1, emoji: "book.fill", title: "Learning", description: "Your child uses learning apps until they reach the daily goal."),
        SolutionStep(id: 2, emoji: "lock.open.fill", title: "Auto-Unlock", description: "Reward apps unlock automatically. No parent intervention needed!"),
        SolutionStep(id: 3, emoji: "play.tv.fill", title: "Reward Time", description: "Your child enjoys earned reward time."),
        SolutionStep(id: 4, emoji: "lock.fill", title: "Auto-Lock", description: "Apps lock automatically again. No parent intervention needed!")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 8) {
                Text("What if your child\n**agreed** to the rules?")
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Learning automatically unlocks AND locks reward apps. First, create the agreement together.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)

            // 5-Step Cycle (scrollable)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        StepRow(
                            step: step,
                            isLast: step.id == steps.count - 1,
                            isVisible: visibleSteps.contains(step.id),
                            colorScheme: colorScheme
                        )
                        .onAppear {
                            let stepId = step.id
                            let delay = Double(stepId) * 0.15
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    _ = visibleSteps.insert(stepId)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }

            Spacer(minLength: 16)

            // Supporting copy
            Text("The app is the referee, not the bad guy. Because your child helped create the rules, they follow them willingly.")
                .font(.system(size: 14, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("See what you'll set up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)

            // Secondary link
            Button(action: {
                onboarding.skipToSetup()
            }) {
                Text("Skip to setup")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer(minLength: 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 2)
        }
    }
}

// MARK: - Step Row Component

private struct StepRow: View {
    let step: SolutionStep
    let isLast: Bool
    let isVisible: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon column with connector
            VStack(spacing: 0) {
                // Emoji/Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .frame(width: 50, height: 50)

                    Image(systemName: step.emoji)
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                // Vertical connector (skip on last step)
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.vibrantTeal.opacity(0.3))
                        .frame(width: 2, height: 24)
                }
            }
            .frame(width: 50)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text(step.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 8)

            Spacer()
        }
        .padding(.horizontal, 24)
        .opacity(isVisible ? 1.0 : 0.3)
        .offset(x: isVisible ? 0 : -20)
    }
}

#Preview {
    Screen2_SolutionView()
        .environmentObject(OnboardingStateManager())
}
