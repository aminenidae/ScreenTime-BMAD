import SwiftUI

/// Parent-specific intro screen that highlights remote monitoring benefits.
struct ParentWelcomeScreen: View {
    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let featureRows: [FeatureRow] = [
        .init(icon: "network", title: String(localized: "Monitor from anywhere"), detail: String(localized: "Check in on every paired child device from a single dashboard.")),
        .init(icon: "trophy.fill", title: String(localized: "Create meaningful rewards"), detail: String(localized: "Launch challenges that motivate learning and good habits.")),
        .init(icon: "qrcode.viewfinder", title: String(localized: "Connect devices securely"), detail: String(localized: "Pair whenever you're ready—no pressure to finish right now."))
    ]

    var body: some View {
        VStack(spacing: 32) {
            header

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("Welcome, \(deviceName.isEmpty ? "Parent" : deviceName)")
                        .font(.system(size: 29, weight: .bold)) // Reduced from 32
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("This device becomes your remote monitor. You'll guide setup on your child's device and connect them with a QR code.")
                        .font(.system(size: 17))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
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
                    .foregroundColor(.white)
                    .frame(maxWidth: 400)
                    .frame(height: 56)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(AppTheme.CornerRadius.medium)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            // Branded teal back pill — matches the rest of the app (was iOS-native blue).
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.vibrantTeal.opacity(0.1))
                    )
            }
            .accessibilityLabel("Back")

            Spacer()

            Text("Parent setup")
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
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .fill(AppTheme.vibrantTeal.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: row.icon)
                    .foregroundColor(AppTheme.accentText(for: colorScheme))
                    .font(.system(size: 22, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(row.detail)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
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
