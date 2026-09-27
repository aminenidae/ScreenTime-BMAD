import SwiftUI

/// Screen 7 (repurposed): the trial-first "finish line".
/// Reached right after the value slides — config has NOT happened yet. This is the
/// psychological pivot from prospect to owner: celebrate that the app is live and the
/// trial has started, then carry on into setup.
///
/// The "I'll explore on my own" escape was removed: it dropped parents onto an empty
/// child dashboard with nothing configured. Setup is now the only way forward, and it
/// runs permission gate → tutorial.
/// See docs/ONBOARDING_TRIAL_FIRST_REDESIGN_2026-07-22.md.
struct Screen7_ActivationView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    /// Start the no-card 14-day trial. Called once, on appear (idempotent upstream).
    let onStartTrial: () -> Void
    /// Continue into setup: the Screen Time permission gate, then the tutorial.
    let onPersonalize: () -> Void

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.isLandscape ? 16 : 40)

            // Celebration + trial confirmation (ownership framing)
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: layout.isLandscape ? 48 : 64))
                    .foregroundColor(AppTheme.accentText(for: colorScheme))

                Text("You're all set")
                    .font(.system(size: layout.isRegular ? 34 : 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("Your app is live and your 14-day free trial has started.")
                    .font(.system(size: layout.isRegular ? 17 : 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                // Relationship close — end on the outcome that matters, not the mechanics.
                Text("Here's to fewer screen-time battles — and more trust between you and your child.")
                    .font(.system(size: layout.isRegular ? 15 : 14))
                    .foregroundColor(AppTheme.accentText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, layout.horizontalPadding)

            Spacer()

            // Sole CTA: pulls into setup, which opens with the Screen Time
            // permission gate before the tutorial.
            Button(action: {
                AppAnalytics.shared.trackOnboarding(.onboardingFinishLinePersonalizeTapped)
                onPersonalize()
            }) {
                Text("Personalize My App")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.CornerRadius.medium)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, layout.isLandscape ? 16 : 32)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onStartTrial()
            onboarding.logScreenView(screenNumber: 7)
            AppAnalytics.shared.trackOnboarding(.onboardingFinishLineShown)
            // onboarding_completed deliberately does NOT fire here: the permission
            // gate and tutorial still follow. It fires on dashboard entry, in
            // OnboardingContainerView.enterChildDashboard().
        }
    }
}

#Preview {
    Screen7_ActivationView(onStartTrial: {}, onPersonalize: {})
        .environmentObject(OnboardingStateManager())
}
