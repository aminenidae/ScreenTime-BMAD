import SwiftUI

struct ChildOnboardingCompletionScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel

    let onStartUsingApp: () -> Void

    @State private var showCelebration = false

    // Calculate app counts
    private var learningAppCount: Int {
        appUsageViewModel.categoryAssignments.filter { $0.value == .learning }.count
    }

    private var rewardAppCount: Int {
        appUsageViewModel.categoryAssignments.filter { $0.value == .reward }.count
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressIndicator(currentStep: 7)
                    .padding(.top, 8)

                Spacer()
                    .frame(height: 40)

                // Success icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.green.opacity(0.2),
                                    AppTheme.vibrantTeal.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                }

                Spacer()
                    .frame(height: 24)

                // Headline
                VStack(spacing: 12) {
                    Text("Your System Is Live")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("The Real Magic Starts Now")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 32)

                // Stats
                HStack(spacing: 16) {
                    statCard(
                        icon: "brain.head.profile",
                        count: learningAppCount,
                        label: "Learning Apps",
                        color: AppTheme.vibrantTeal
                    )

                    statCard(
                        icon: "gamecontroller.fill",
                        count: rewardAppCount,
                        label: "Reward Apps",
                        color: AppTheme.playfulCoral
                    )
                }
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 24)

                // First Action Steps
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.number")
                            .foregroundColor(AppTheme.vibrantTeal)
                        Text("Your First Steps:")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        tipRow(emoji: "1️⃣", text: "Show Your Child Their Dashboard")
                        tipRow(emoji: "2️⃣", text: "Don't Touch Anything for 48 Hours")
                        tipRow(emoji: "3️⃣", text: "Check Back in 3 Days")
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppTheme.card(for: colorScheme))
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                )
                .padding(.horizontal, 24)

                Spacer()

                // Start button
                PulsingButton(shouldPulse: true) {
                    Button(action: onStartUsingApp) {
                        Text("View Dashboard")
                            .font(.system(size: 22, weight: .bold))
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
            }

            // Confetti overlay
            if showCelebration {
                OnboardingConfettiView(isActive: showCelebration)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Trigger confetti celebration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showCelebration = true
            }
        }
    }

    // MARK: - Subviews

    private func statCard(icon: String, count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
            }

            // Count
            Text("\(count)")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)

            // Label
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private func tipRow(emoji: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 24))

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
