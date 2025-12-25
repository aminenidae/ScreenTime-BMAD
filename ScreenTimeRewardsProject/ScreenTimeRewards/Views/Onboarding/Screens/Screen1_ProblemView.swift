import SwiftUI

/// Screen 1: Problem Recognition (C1)
/// Hero image showing the "five more minutes" struggle with empathetic messaging
struct Screen1_ProblemView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var visibleBullets: Set<Int> = []
    @State private var animationStarted = false

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    private let bullets = [
        "your child begs",
        "you either give up",
        "or say no... and you are the \"bad guy\"",
        "there is a better way"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.isLandscape ? 8 : 16)

            // Hero Image Card (C1)
            ProblemHeroCard(layout: layout)
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: layout.heroCardMaxWidth)

            Spacer(minLength: layout.isLandscape ? 12 : 24)

            // Headline
            Text("THE \"FIVE MORE MINUTES\"\nBATTLE CAN END TODAY")
                .font(.system(size: layout.isRegular ? 29 : 25, weight: .bold)) // Reduced from 32/28
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(3)
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 8 : 12)

            // Animated bullet points
            VStack(alignment: .leading, spacing: layout.isLandscape ? 10 : 14) {
                ForEach(bullets.indices, id: \.self) { index in
                    ProblemBulletRow(
                        text: bullets[index],
                        isVisible: visibleBullets.contains(index),
                        layout: layout,
                        colorScheme: colorScheme
                    )
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .frame(maxWidth: 600)

            Spacer(minLength: layout.isLandscape ? 16 : 32)

            // Primary CTA
            Button(action: {
                onboarding.advanceScreen()
            }) {
                Text("Show Me How")
                    .font(.system(size: 18, weight: .bold)) // Standardized button font size
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: layout.isLandscape ? 12 : 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 1)
            startBulletAnimations()
        }
    }

    /// Starts the staggered bullet animations with 1-second delays
    private func startBulletAnimations() {
        guard !animationStarted else { return }
        animationStarted = true

        for index in bullets.indices {
            let delay = Double(index) * 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    _ = visibleBullets.insert(index)
                }
            }
        }
    }
}

// MARK: - Problem Bullet Row

private struct ProblemBulletRow: View {
    let text: String
    let isVisible: Bool
    let layout: ResponsiveCardLayout
    let colorScheme: ColorScheme

    /// Vertical offset for enter animation
    private var enterOffset: CGFloat {
        isVisible ? 0 : 20
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(AppTheme.vibrantTeal)

            Text(text)
                .font(.system(size: layout.isRegular ? 17 : 15, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(1)

            Spacer()
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: enterOffset)
    }
}

// MARK: - Problem Hero Card

private struct ProblemHeroCard: View {
    let layout: ResponsiveCardLayout

    /// Card height - responsive based on device
    private var cardHeight: CGFloat {
        if layout.isIpad {
            return 280
        } else if layout.isLandscape {
            return 160
        } else {
            return 200
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background image - explicitly sized to geometry
                Image("onboarding_C1")
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

                // Text overlay
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE DAILY STRUGGLE")
                        .font(.system(size: layout.isIpad ? 21 : 13, weight: .semibold)) // Reduced from 24/16
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                        .tracking(2)

                    Text("Sound Familiar? Screen Time Negotiations Don't Have To Be This Hard.")
                        .font(.system(size: layout.isIpad ? 16 : 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .textCase(.uppercase)
                }
                .padding(layout.isIpad ? 20 : 12)
            }
        }
        .frame(height: cardHeight)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

#Preview {
    Screen1_ProblemView()
        .environmentObject(OnboardingStateManager())
}
