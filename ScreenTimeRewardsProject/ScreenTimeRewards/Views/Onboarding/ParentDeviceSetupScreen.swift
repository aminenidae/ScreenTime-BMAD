import SwiftUI

struct ParentDeviceSetupScreen: View {
    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ParentOnboardingStepHeader(
                title: "Set Up Remote Monitoring",
                subtitle: "You'll need access to the child device for a few minutes.",
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

                Text("The child device can use any Apple ID. Pairing only requires that ScreenTime Rewards is installed and its onboarding is finished.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )

            Spacer()

            Button(action: onContinue) {
                Text("I've Installed the App")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 400)
                    .frame(height: 56)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.bottom, 16)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var instructionSteps: [InstructionStep] {
        [
            .init(number: "1", title: "Download on the child device", detail: "Install ScreenTime Rewards on your child's iPhone or iPad."),
            .init(number: "2", title: "Complete their setup", detail: "Follow the guided child onboarding so permissions and learning apps are configured."),
            .init(
                number: "3",
                title: "Return to this device",
                detail: "We'll generate a QR code so the child device can pair with \(deviceName.isEmpty ? "your parent device" : deviceName)."
            )
        ]
    }
}

private struct InstructionCard: View {
    let step: InstructionStep

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(step.number)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 17, weight: .semibold))

                Text(step.detail)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 16)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
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
