import SwiftUI

struct ParentOnboardingStepHeader: View {
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

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 800)
    }
}
