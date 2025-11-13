import SwiftUI

struct ChildOnboardingStepHeader: View {
    let title: String
    let subtitle: String
    let step: Int
    let totalSteps: Int
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Step \(step) of \(totalSteps)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.8))
            }
        }
    }
}
