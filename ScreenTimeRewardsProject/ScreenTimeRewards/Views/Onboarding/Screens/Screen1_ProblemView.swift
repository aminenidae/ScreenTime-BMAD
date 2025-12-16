import SwiftUI

/// Screen 1: Problem Recognition
/// Educates parents on the daily screen time struggle
struct Screen1_ProblemView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Illustration placeholder
            ZStack {
                Circle()
                    .fill(AppTheme.vibrantTeal.opacity(0.1))
                    .frame(width: 200, height: 200)

                Image(systemName: "timer")
                    .font(.system(size: 80))
                    .foregroundColor(AppTheme.vibrantTeal)
            }
            .padding()

            Spacer(minLength: 20)

            // Headline
            Text("The \"five more minutes\"\nbattle can end today")
                .font(.system(size: 28, weight: .bold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal)

            Spacer(minLength: 12)

            // Body copy
            Text("Every parent knows this conversation. Your child begs. You negotiate. You worry about learning. There's a better way.")
                .font(.system(size: 16, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 24)

            Spacer(minLength: 40)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("Show me how")
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
                onboarding.logEvent("onboarding_screen1_skip_tapped")
                onboarding.skipToActivation()
            }) {
                Text("Skip for now")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer(minLength: 32)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 1)
        }
    }
}

#Preview {
    Screen1_ProblemView()
        .environmentObject(OnboardingStateManager())
}
