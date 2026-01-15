import SwiftUI

/// Screen 3: Guided Tutorial Introduction (C3)
/// Introduces the guided tutorial and highlights its benefits
/// Prepares parents for the hands-on setup experience
struct Screen3_SetupPreviewView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header section
                VStack(spacing: 8) {
                    Text("WE'LL GUIDE YOU\nTHROUGH EVERY STEP")
                        .font(.system(size: layout.isRegular ? 27 : 23, weight: .bold))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .textCase(.uppercase)
                        .tracking(3)

                    Text("(ABOUT 3 MINUTES)")
                        .font(.system(size: layout.isRegular ? 20 : 18, weight: .medium))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .textCase(.uppercase)

                    Text("Interactive Tutorial. No Confusion. Just Follow Along.")
                        .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.isLandscape ? 12 : 20)
                .frame(maxWidth: 600)

                // Hero Image - Tutorial Preview Screenshot
                Image("onboarding_C3_tutorial")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: layout.isRegular ? 400 : .infinity)
                    .cornerRadius(AppTheme.CornerRadius.large)
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, layout.isLandscape ? 12 : 16)

                // Benefits List
                VStack(alignment: .leading, spacing: layout.isLandscape ? 10 : 14) {
                    BenefitRow(
                        icon: "hand.tap.fill",
                        text: "Hands-On Interactive Walkthrough",
                        colorScheme: colorScheme
                    )

                    BenefitRow(
                        icon: "lightbulb.fill",
                        text: "Real-Time Guidance At Every Step",
                        colorScheme: colorScheme
                    )

                    BenefitRow(
                        icon: "slider.horizontal.3",
                        text: "See How Incredibly Simple Our Settings Are",
                        colorScheme: colorScheme
                    )

                    BenefitRow(
                        icon: "apps.iphone",
                        text: "Configure Learning & Reward Apps With Help",
                        colorScheme: colorScheme
                    )

                    BenefitRow(
                        icon: "checkmark.circle.fill",
                        text: "Ready To Use In Just 3 Minutes",
                        colorScheme: colorScheme
                    )
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.isLandscape ? 12 : 20)
                .frame(maxWidth: 600)

                Spacer(minLength: layout.isLandscape ? 12 : 20)

                // Reassurance text
                Text("You'll configure the real app with step-by-step guidance. We'll show you exactly what to do.")
                    .font(.system(size: layout.isRegular ? 15 : 13, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.bottom, layout.isLandscape ? 12 : 20)
                    .frame(maxWidth: 600)
                    .textCase(.uppercase)

                // Primary CTA
                Button(action: {
                    onboarding.advanceScreen()
                }) {
                    Text("Let's Set This Up")
                        .font(.system(size: 18, weight: .bold))
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
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            onboarding.logScreenView(screenNumber: 3)
        }
    }
}

// MARK: - Benefit Row Component

private struct BenefitRow: View {
    let icon: String
    let text: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppTheme.vibrantTeal)
                .frame(width: 28, height: 28)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(1)

            Spacer()
        }
    }
}

#Preview {
    Screen3_SetupPreviewView()
        .environmentObject(OnboardingStateManager())
}
