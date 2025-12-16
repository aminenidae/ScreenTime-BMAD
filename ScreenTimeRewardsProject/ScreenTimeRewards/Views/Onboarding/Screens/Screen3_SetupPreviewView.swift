import SwiftUI

/// Screen 3: Setup Preview
/// Shows what the user will configure in the next steps
struct Screen3_SetupPreviewView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLearningPreview = false
    @State private var showRewardPreview = false

    var body: some View {
        VStack(spacing: 0) {
            // Title section
            VStack(spacing: 8) {
                Text("Set up your family system")
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("(about 3 minutes)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Two quick steps, then it runs automatically every day.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)

            Spacer(minLength: 20)

            // Two cards
            HStack(spacing: 16) {
                // Card 1: Learning
                SetupPreviewCard(
                    stepNumber: 1,
                    title: "Learning apps",
                    emoji: "book.fill",
                    details: ["Choose learning apps", "Set daily learning goal"],
                    colorScheme: colorScheme
                ) {
                    showLearningPreview = true
                }

                // Card 2: Reward
                SetupPreviewCard(
                    stepNumber: 2,
                    title: "Reward apps",
                    emoji: "play.tv.fill",
                    details: ["Choose reward apps", "Set time ratio"],
                    colorScheme: colorScheme
                ) {
                    showRewardPreview = true
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 32)

            // Reassurance
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("You'll do this once. The system repeats daily automatically.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Spacer(minLength: 40)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("Start setup")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .sheet(isPresented: $showLearningPreview) {
            PreviewSheetView(
                title: "Learning Apps Setup",
                description: "You'll select educational apps like Khan Academy, Duolingo, or any app that encourages learning. Then set a daily goal (we recommend 60 minutes).",
                colorScheme: colorScheme
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRewardPreview) {
            PreviewSheetView(
                title: "Reward Apps Setup",
                description: "You'll select reward apps like YouTube, Roblox, or TikTok. Then choose how much reward time learning unlocks (1:1 is a great starting point).",
                colorScheme: colorScheme
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            onboarding.logScreenView(screenNumber: 3)
        }
    }
}

// MARK: - Setup Preview Card

private struct SetupPreviewCard: View {
    let stepNumber: Int
    let title: String
    let emoji: String
    let details: [String]
    let colorScheme: ColorScheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step \(stepNumber)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)

                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }

                    Spacer()

                    Image(systemName: emoji)
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(details, id: \.self) { detail in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.vibrantTeal.opacity(0.5))
                                .frame(width: 4, height: 4)

                            Text(detail)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }
            .padding(16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview Sheet

private struct PreviewSheetView: View {
    let title: String
    let description: String
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(description)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Button(action: { dismiss() }) {
                Text("Got it")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }
}

#Preview {
    Screen3_SetupPreviewView()
        .environmentObject(OnboardingStateManager())
}
