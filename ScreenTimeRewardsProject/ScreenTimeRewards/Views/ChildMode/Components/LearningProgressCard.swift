import SwiftUI

struct LearningProgressCard: View {
    let linkedLearningApps: [LinkedLearningApp]
    let learningProgress: [String: (used: Int, required: Int, goalMet: Bool)] // Key: logicalID
    let unlockMode: UnlockMode
    let isUnlocked: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection

            // Progress bars for each linked app
            ForEach(linkedLearningApps, id: \.logicalID) { linkedApp in
                learningAppProgressRow(for: linkedApp)
            }

            // Unlock mode explanation
            if !isUnlocked && !linkedLearningApps.isEmpty {
                unlockModeExplanation
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.vibrantTeal)

            Text(isUnlocked ? "YOU'VE EARNED THIS TIME BY:" : "COMPLETE THESE TO UNLOCK")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()
        }
    }

    private func learningAppProgressRow(for linkedApp: LinkedLearningApp) -> some View {
        let progress = learningProgress[linkedApp.logicalID] ?? (0, linkedApp.minutesRequired, false)
        let percentage = progress.required > 0 ? Double(progress.used) / Double(progress.required) : 0
        let appName = AppNameMappingService.shared.getDisplayName(for: linkedApp.logicalID, defaultName: "Learning App")

        return VStack(alignment: .leading, spacing: 8) {
            // App name and status
            HStack {
                // Icon placeholder
                Circle()
                    .fill(AppTheme.vibrantTeal.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.vibrantTeal)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)

                    Text("\(linkedApp.goalPeriod.displayName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                if progress.goalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .frame(height: 24)

                    // Filled progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: progress.goalMet
                                    ? [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)]
                                    : [AppTheme.sunnyYellow, AppTheme.vibrantTeal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(percentage, 1.0), height: 24)

                    // Progress text overlay
                    HStack {
                        Spacer()
                        Text("\(progress.used) / \(progress.required) MIN")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.trailing, 8)
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.vertical, 4)
    }

    private var unlockModeExplanation: some View {
        HStack(spacing: 8) {
            Image(systemName: unlockMode == .all ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.playfulCoral)

            Text(unlockMode == .all ? "Complete ALL apps above" : "Complete ANY ONE app above")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.playfulCoral.opacity(0.08))
        )
    }
}
