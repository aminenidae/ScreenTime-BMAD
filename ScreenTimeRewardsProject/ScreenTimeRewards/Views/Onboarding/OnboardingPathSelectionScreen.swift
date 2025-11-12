import SwiftUI

enum OnboardingPath {
    case quickStart
    case fullSetup
}

struct OnboardingPathSelectionScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let deviceName: String
    let onBack: () -> Void
    let onPathSelected: (OnboardingPath) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("How much time do you have?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)

                Text("Choose your setup experience")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            Spacer()

            // Path options
            VStack(spacing: 16) {
                pathCard(
                    icon: "bolt.fill",
                    title: "Quick Start",
                    duration: "2 min",
                    description: "Get started immediately with essential setup",
                    color: AppTheme.sunnyYellow,
                    path: .quickStart
                )

                pathCard(
                    icon: "target",
                    title: "Full Setup",
                    duration: "10 min",
                    description: "Complete walkthrough: learning apps, rewards, and challenges",
                    color: AppTheme.vibrantTeal,
                    path: .fullSetup
                )
            }

            Spacer()

            // Back button
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)
        }
        .padding(24)
        .background(AppTheme.background(for: colorScheme))
    }

    private func pathCard(
        icon: String,
        title: String,
        duration: String,
        description: String,
        color: Color,
        path: OnboardingPath
    ) -> some View {
        Button {
            onPathSelected(path)
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(color)
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        Text(duration)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(color.opacity(0.15))
                            )
                    }

                    Text(description)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}
