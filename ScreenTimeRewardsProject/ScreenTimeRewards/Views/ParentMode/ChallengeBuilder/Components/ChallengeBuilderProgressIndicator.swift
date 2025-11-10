import SwiftUI

struct ChallengeBuilderProgressIndicator: View {
    let steps: [ChallengeBuilderStep]
    let currentStep: ChallengeBuilderStep
    var onStepTapped: ((ChallengeBuilderStep) -> Void)?

    private func isCompleted(_ step: ChallengeBuilderStep) -> Bool {
        guard let currentIndex = steps.firstIndex(of: currentStep),
              let stepIndex = steps.firstIndex(of: step) else { return false }
        return stepIndex < currentIndex
    }

    private func isCurrent(_ step: ChallengeBuilderStep) -> Bool {
        step == currentStep
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(steps) { step in
                    Button {
                        onStepTapped?(step)
                    } label: {
                        VStack(spacing: 6) {
                            stepCircle(for: step)
                            Text(step.title)
                                .font(.system(size: 13, weight: isCurrent(step) ? .semibold : .regular))
                                .foregroundColor(isCurrent(step) ? ChallengeBuilderTheme.text : ChallengeBuilderTheme.mutedText)
                        }
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)

                    if step != steps.last {
                        Rectangle()
                            .frame(width: 24, height: 1)
                            .foregroundColor(ChallengeBuilderTheme.border)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(ChallengeBuilderTheme.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ChallengeBuilderTheme.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func stepCircle(for step: ChallengeBuilderStep) -> some View {
        let completed = isCompleted(step)
        let current = isCurrent(step)

        ZStack {
            Circle()
                .fill(
                    completed ? ChallengeBuilderTheme.secondary.opacity(0.15) :
                        current ? ChallengeBuilderTheme.primary.opacity(0.15) :
                        ChallengeBuilderTheme.inputBackground
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(
                            completed ? ChallengeBuilderTheme.secondary :
                                current ? ChallengeBuilderTheme.primary :
                                ChallengeBuilderTheme.border,
                            lineWidth: 2
                        )
                )

            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.secondary)
            } else {
                Text("\(step.rawValue + 1)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(current ? ChallengeBuilderTheme.primary : ChallengeBuilderTheme.mutedText)
            }
        }
    }
}
