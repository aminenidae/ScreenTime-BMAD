import SwiftUI

struct ChildPaywallStepView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            OnboardingProgressIndicator(currentStep: 6)
                .padding(.top, 8)

            // Value proposition context
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Almost There. One More Thing...")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    VStack(spacing: 6) {
                        Text("See how your kids are learning.")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Text("Understand the patterns.")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Text("Optimize the system.")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                    VStack(spacing: 4) {
                        Text("$4.99/month. Less than a coffee.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                        Text("14-day free trial. No credit card needed.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Paywall
            SubscriptionPaywallView(isOnboarding: true, onComplete: onComplete)

            // Back button at bottom
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .background(AppTheme.background(for: colorScheme))
    }
}
