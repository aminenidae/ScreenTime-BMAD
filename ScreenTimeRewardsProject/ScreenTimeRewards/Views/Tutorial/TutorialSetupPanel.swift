import SwiftUI

/// Final tutorial step panel showing completion message and next steps
struct TutorialSetupPanel: View {
    @EnvironmentObject var tutorialManager: TutorialModeManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Success Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal.opacity(0.2), AppTheme.vibrantTeal.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                // Header
                VStack(spacing: 8) {
                    Text("Setup Complete!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("You've successfully configured your first apps")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }

                Divider()
                    .padding(.horizontal)

                // What's Next Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's Next?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    // Tip 1: Add more apps
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.learningPeach)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add More Apps")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text("Use the same steps to configure additional learning and reward apps anytime.")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Tip 2: Replay tutorial
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.playfulCoral)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Replay Tutorial")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text("Need a refresher? You can access this tutorial again from the Settings tab.")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Tip 3: Monitor progress
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Track Progress")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text("Check the Dashboard to see your child's learning progress and earned rewards.")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 4)

                // Complete Button
                Button(action: completeSetup) {
                    HStack(spacing: 8) {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(14)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: -5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    private func completeSetup() {
        // Complete the tutorial
        tutorialManager.endTutorial(success: true)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.7)
            .ignoresSafeArea()

        TutorialSetupPanel()
            .environmentObject(TutorialModeManager.shared)
    }
}
