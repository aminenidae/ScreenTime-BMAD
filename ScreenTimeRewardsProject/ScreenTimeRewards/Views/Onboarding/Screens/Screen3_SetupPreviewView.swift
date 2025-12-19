import SwiftUI

/// Screen 3: Setup Preview (C3)
/// Shows what the user will configure with image cards for Learning and Reward apps
/// Adapts to iPad with side-by-side layout and landscape with smaller cards
struct Screen3_SetupPreviewView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var showLearningPreview = false
    @State private var showRewardPreview = false

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title section
            VStack(spacing: 8) {
                Text("Set up your family system")
                    .font(.system(size: layout.isRegular ? 30 : 26, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("(about 3 minutes)")
                    .font(.system(size: layout.isRegular ? 20 : 18, weight: .medium))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Two quick steps, then it runs automatically every day.")
                    .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.isLandscape ? 12 : 20)
            .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Two Image Cards - Side by side on iPad, stacked on iPhone
            Group {
                if layout.useSideBySideLayout {
                    // iPad: Side by side
                    HStack(spacing: layout.cardSpacing) {
                        SetupImageCard(
                            imageName: "onboarding_C3_1",
                            title: "Learning Apps",
                            subtitle: "Configure which apps earn screen time",
                            layout: layout
                        ) {
                            showLearningPreview = true
                        }

                        SetupImageCard(
                            imageName: "onboarding_C3_2",
                            title: "Reward Apps",
                            subtitle: "Set approved entertainment options",
                            layout: layout
                        ) {
                            showRewardPreview = true
                        }
                    }
                    .frame(maxWidth: 800)
                } else {
                    // iPhone: Stacked
                    VStack(spacing: layout.cardSpacing) {
                        SetupImageCard(
                            imageName: "onboarding_C3_1",
                            title: "Learning Apps",
                            subtitle: "Configure which apps earn screen time",
                            layout: layout
                        ) {
                            showLearningPreview = true
                        }

                        SetupImageCard(
                            imageName: "onboarding_C3_2",
                            title: "Reward Apps",
                            subtitle: "Set approved entertainment options",
                            layout: layout
                        ) {
                            showRewardPreview = true
                        }
                    }
                }
            }
            .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: layout.isLandscape ? 12 : 24)

            // Reassurance
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("You'll do this once. The system repeats daily automatically.")
                    .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, layout.horizontalPadding)
            .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 16 : 32)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("Start setup")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: layout.isLandscape ? 12 : 24)
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

// MARK: - Setup Image Card

private struct SetupImageCard: View {
    let imageName: String
    let title: String
    let subtitle: String
    let layout: ResponsiveCardLayout
    let action: () -> Void

    /// Card height - responsive based on device
    private var cardHeight: CGFloat {
        if layout.isIpad {
            return 200
        } else if layout.isLandscape {
            return 140
        } else {
            return 160
        }
    }

    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    // Background image - explicitly sized to geometry
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: cardHeight)
                        .clipped()

                    // Gradient overlay
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.5)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geometry.size.width, height: cardHeight)

                    // Text content
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: layout.isIpad ? 22 : 16, weight: .semibold))
                                .foregroundColor(.white)

                            Text(subtitle)
                                .font(.system(size: layout.isIpad ? 16 : 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: layout.isIpad ? 16 : 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(layout.isIpad ? 20 : 12)
                }
            }
            .frame(height: cardHeight)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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
