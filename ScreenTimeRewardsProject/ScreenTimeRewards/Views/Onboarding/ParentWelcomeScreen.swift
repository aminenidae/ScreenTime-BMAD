import SwiftUI

/// Parent-specific intro screen that highlights remote monitoring benefits.
struct ParentWelcomeScreen: View {
    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let featureRows: [FeatureRow] = [
        .init(icon: "network", title: "MONITOR FROM ANYWHERE", detail: "Check in on every paired child device from a single dashboard."),
        .init(icon: "trophy.fill", title: "CREATE MEANINGFUL REWARDS", detail: "Launch challenges that motivate learning and good habits."),
        .init(icon: "qrcode.viewfinder", title: "CONNECT DEVICES SECURELY", detail: "Pair whenever you're ready—no pressure to finish right now.")
    ]

    var body: some View {
        VStack(spacing: 32) {
            header

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("WELCOME, \(deviceName.isEmpty ? "PARENT" : deviceName.uppercased())")
                        .font(.system(size: 29, weight: .bold)) // Reduced from 32
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .textCase(.uppercase)
                        .tracking(3)

                    Text("This device becomes your remote monitor. You'll guide setup on your child's device and connect them with a QR code.")
                        .font(.system(size: 17))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .textCase(.uppercase)
                }

                VStack(spacing: 16) {
                    ForEach(featureRows) { row in
                        ParentFeatureCard(row: row, colorScheme: colorScheme)
                    }
                }
            }
            .frame(maxWidth: 640)

            Spacer()

            Button(action: onContinue) {
                Text("Show Me the Steps")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.lightCream)
                    .frame(maxWidth: 400)
                    .frame(height: 56)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .textCase(.uppercase)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("PARENT ONBOARDING")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(2)
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
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .fill(AppTheme.vibrantTeal.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: row.icon)
                    .foregroundColor(AppTheme.vibrantTeal)
                    .font(.system(size: 22, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(2)

                Text(row.detail)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                    .textCase(.uppercase)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }
}
