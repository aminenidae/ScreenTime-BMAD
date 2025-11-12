import SwiftUI

/// Parent-specific intro screen that highlights remote monitoring benefits.
struct ParentWelcomeScreen: View {
    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void

    private let featureRows: [FeatureRow] = [
        .init(icon: "network", title: "Monitor from anywhere", detail: "Check in on every paired child device from a single dashboard."),
        .init(icon: "trophy.fill", title: "Create meaningful rewards", detail: "Launch challenges that motivate learning and good habits."),
        .init(icon: "qrcode.viewfinder", title: "Connect devices securely", detail: "Pair whenever you're ready—no pressure to finish right now.")
    ]

    var body: some View {
        VStack(spacing: 32) {
            header

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("Welcome, \(deviceName.isEmpty ? "Parent" : deviceName)")
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("This device becomes your remote monitor. You'll guide setup on your child's device and connect them with a QR code.")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 16) {
                    ForEach(featureRows) { row in
                        ParentFeatureCard(row: row)
                    }
                }
            }
            .frame(maxWidth: 640)

            Spacer()

            Button(action: onContinue) {
                Text("Show Me the Steps")
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

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("Parent Onboarding")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    struct FeatureRow: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }
}

private struct ParentFeatureCard: View {
    let row: ParentWelcomeScreen.FeatureRow

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: row.icon)
                    .foregroundColor(Color.accentColor)
                    .font(.system(size: 22, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 17, weight: .semibold))

                Text(row.detail)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
