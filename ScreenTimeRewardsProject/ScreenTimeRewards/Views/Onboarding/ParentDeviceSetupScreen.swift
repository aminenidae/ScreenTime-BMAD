import SwiftUI

struct ParentDeviceSetupScreen: View {
    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            ParentOnboardingStepHeader(
                title: String(localized: "Set Up Remote Monitoring"),
                subtitle: String(localized: "You'll need access to the child device for a few minutes."),
                step: 1,
                totalSteps: 2,
                onBack: onBack
            )

            VStack(alignment: .leading, spacing: 16) {
                ForEach(instructionSteps) { step in
                    InstructionCard(step: step)
                }
            }
            .frame(maxWidth: 640)

            VStack(alignment: .leading, spacing: 12) {
                Label("Tip", systemImage: "lightbulb")
                    .font(.headline)
                    .foregroundColor(AppTheme.accentText(for: colorScheme))

                Text("The child device can use any Apple ID. Pairing only requires that Tic Lock is installed and its onboarding is finished.")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
            }
            .padding()
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.vibrantTeal.opacity(0.08))
            )

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 400)
                    .frame(height: 56)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(AppTheme.CornerRadius.medium)
            }
            .padding(.bottom, 16)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private var instructionSteps: [InstructionStep] {
        [
            .init(number: "1", title: String(localized: "Download on the child device"), detail: String(localized: "Install Tic Lock on your child's iPhone or iPad.")),
            .init(number: "2", title: String(localized: "Complete their setup"), detail: String(localized: "Follow the guided child onboarding so permissions and learning apps are configured.")),
            .init(
                number: "3",
                title: String(localized: "Return to this device"),
                detail: String(localized: "We'll generate a QR code so the child device can pair with \(deviceName.isEmpty ? String(localized: "your parent device") : deviceName).")
            )
        ]
    }
}

private struct InstructionCard: View {
    let step: InstructionStep
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(step.number)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppTheme.vibrantTeal))

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(step.detail)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
            }

            Spacer(minLength: 16)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

private struct InstructionStep: Identifiable {
    let id = UUID()
    let number: String
    let title: String
    let detail: String
}
