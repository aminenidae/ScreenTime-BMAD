import SwiftUI

/// Screen 7: Activation
/// Guides user on first actions after setup completion
struct Screen7_ActivationView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme

    let onShowChildDashboard: () -> Void
    let onShowParentDashboard: () -> Void

    private let actionSteps: [(number: Int, title: String, description: String)] = [
        (1, "Review the agreement together (now)", "Show your child their dashboard and remind them of the deal: when learning time fills up, their apps unlock automatically, and when time is up, they lock again."),
        (2, "Let the system run for 48 hours", "Try not to adjust settings. Let your child experience the new rhythm."),
        (3, "Check progress together after 3 days", "Look at how much learning they've done and ask, \"Does this still feel fair?\" Adjust goals if needed.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Your system is live")
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Here's what to do next with your child")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)

            Spacer(minLength: 16)

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(actionSteps, id: \.number) { step in
                        ActionStepCard(
                            step: step,
                            colorScheme: colorScheme
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 24)

            // Primary CTA
            Button(action: {
                completeOnboarding()
                onShowChildDashboard()
            }) {
                Text("Show child dashboard")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Secondary CTA
            Button(action: {
                completeOnboarding()
                onShowParentDashboard()
            }) {
                Text("Go to parent dashboard")
                    .font(.system(size: 16, weight: .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.card(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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

// MARK: - Action Step Card

private struct ActionStepCard: View {
    let step: (number: Int, title: String, description: String)
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Step number badge
            Text("\(step.number)")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(AppTheme.vibrantTeal)
                .foregroundColor(.white)
                .cornerRadius(10)

            // Step content
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(14)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    Screen7_ActivationView(
        onShowChildDashboard: {},
        onShowParentDashboard: {}
    )
    .environmentObject(OnboardingStateManager())
}
