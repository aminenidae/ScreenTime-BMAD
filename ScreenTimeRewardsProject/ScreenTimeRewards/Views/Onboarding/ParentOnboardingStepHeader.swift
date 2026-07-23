import SwiftUI

struct ParentOnboardingStepHeader: View {
    let title: String
    let subtitle: String
    let step: Int
    let totalSteps: Int
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Branded teal back pill — matches the rest of the app (was iOS-native blue).
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.accentText(for: colorScheme))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.vibrantTeal.opacity(0.1))
                        )
                }
                .accessibilityLabel("Back")

                Spacer()

                Text("Step \(step) of \(totalSteps)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 25, weight: .bold)) // Reduced from 28
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.system(size: 13)) // Reduced from 16
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 800)
    }
}
