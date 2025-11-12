import SwiftUI

struct ChildOnboardingCompletionScreen: View {
    let onStartUsingApp: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 32, weight: .bold))

                Text("Learning apps are ready, and your subscription is active. Start exploring rewards and challenges.")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            VStack(alignment: .leading, spacing: 12) {
                completionTip(icon: "sparkles", message: "Earn points by spending time in your selected learning apps.")
                completionTip(icon: "trophy.fill", message: "Redeem points to unlock favorite games once goals are met.")
                completionTip(icon: "clock.fill", message: "Parents can monitor progress from the remote dashboard.")
            }
            .frame(maxWidth: 520)

            Spacer()

            Button(action: onStartUsingApp) {
                Text("Start Using ScreenTime Rewards")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 400)
                    .frame(height: 56)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func completionTip(icon: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.system(size: 20))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
