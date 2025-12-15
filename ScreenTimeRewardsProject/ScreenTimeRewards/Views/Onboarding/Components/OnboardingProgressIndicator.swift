import SwiftUI

/// Displays "Level X of 7" progress indicator for child onboarding
struct OnboardingProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    let showProgress: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(currentStep: Int, totalSteps: Int = 7, showProgress: Bool = true) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.showProgress = showProgress
    }

    var body: some View {
        if showProgress {
            VStack(spacing: 8) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)

                        // Progress fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.vibrantTeal, AppTheme.sunnyYellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(.spring(response: 0.6), value: currentStep)
                    }
                }
                .frame(height: 8)

                // Level text
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("Level \(currentStep) of \(totalSteps)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    if currentStep == totalSteps {
                        Text("- Complete!")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }

    private var progress: CGFloat {
        CGFloat(currentStep) / CGFloat(totalSteps)
    }
}

#Preview {
    VStack(spacing: 40) {
        OnboardingProgressIndicator(currentStep: 1)
        OnboardingProgressIndicator(currentStep: 3)
        OnboardingProgressIndicator(currentStep: 5)
        OnboardingProgressIndicator(currentStep: 8)
        OnboardingProgressIndicator(currentStep: 1, showProgress: false)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
