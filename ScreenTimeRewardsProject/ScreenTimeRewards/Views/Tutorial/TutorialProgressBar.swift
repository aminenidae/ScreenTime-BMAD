import SwiftUI

/// Progress indicator showing current step in the tutorial (no step numbers to avoid overwhelming users)
struct TutorialProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    private var progress: CGFloat {
        CGFloat(currentStep) / CGFloat(totalSteps)
    }

    var body: some View {
        // Simple progress bar without step numbers
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)

                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geometry.size.width * progress, 12), height: 6)
                    .animation(.spring(response: 0.4), value: progress)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.3))
        )
    }

}

// MARK: - Alternative Linear Progress Style

struct TutorialLinearProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    private var progress: CGFloat {
        CGFloat(currentStep) / CGFloat(totalSteps)
    }

    var body: some View {
        // Progress bar without step numbers
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)

                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geometry.size.width * progress, 12), height: 6)
                    .animation(.spring(response: 0.4), value: progress)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.7)
            .ignoresSafeArea()

        VStack(spacing: 40) {
            TutorialProgressBar(currentStep: 3, totalSteps: 8)

            TutorialLinearProgressBar(currentStep: 3, totalSteps: 8)
                .frame(width: 200)
        }
    }
}
