import SwiftUI
import FamilyControls
import ManagedSettings

/// Reusable row component for displaying app usage in child dashboard
/// Used for both learning and reward apps with configurable styling
struct AppUsageRow: View {
    let token: ApplicationToken
    let usageSeconds: TimeInterval
    let accentColor: Color

    // Optional progress indicator
    var progressValue: Double? = nil
    var progressLabel: String? = nil

    // For reward apps - lock status
    var isLocked: Bool = false
    var lockMessage: String? = nil

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            appIcon

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Top row: App name and usage time
                HStack {
                    appNameLabel
                    Spacer()
                    usageTimeLabel
                    if isLocked {
                        lockIcon
                    }
                }

                // Bottom row: Progress bar or lock message
                if let lockMessage = lockMessage, isLocked {
                    Text(lockMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else if let progress = progressValue {
                    progressBar(value: progress)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
        .opacity(isLocked ? 0.6 : 1.0)
    }

    // MARK: - Subviews

    private var appIcon: some View {
        Group {
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.4)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 20))
                            .foregroundColor(accentColor)
                    )
            }
        }
    }

    private var appNameLabel: some View {
        Group {
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            } else {
                Text("App")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            }
        }
    }

    private var usageTimeLabel: some View {
        Text(TimeFormatting.formatSecondsCompact(usageSeconds))
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(accentColor)
    }

    private var lockIcon: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isLocked ? AppTheme.textSecondary(for: colorScheme) : AppTheme.brandedText(for: colorScheme))
    }

    private func progressBar(value: Double) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.progressTrack(for: colorScheme))
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor)
                        .frame(width: geometry.size.width * min(max(value, 0), 1), height: 8)
                }
            }
            .frame(height: 8)

            if let label = progressLabel {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Learning app example (would need real token in actual use)
        Text("Learning App Row")
            .font(.headline)

        // Reward app - unlocked
        Text("Reward App - Unlocked")
            .font(.headline)

        // Reward app - locked
        Text("Reward App - Locked")
            .font(.headline)
    }
    .padding()
    .background(AppTheme.background(for: .light))
}
