import SwiftUI

/// A picker for configuring how much reward time a learning app earns per learning minute.
/// Used in learning app configuration sheets (both child and parent modes).
struct LearningRewardRatioPicker: View {
    @Binding var ratioLearningMinutes: Int
    @Binding var rewardMinutesEarned: Int

    @Environment(\.colorScheme) private var colorScheme

    private let ratioPresets = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.arrow.left")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Reward Ratio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text("How much reward time each minute of learning earns")
                .font(.system(size: 12))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            // Ratio sentence: "Every [Xm] of learning grants [Ym] reward"
            ratioRow
        }
        .padding(16)
    }

    private var ratioRow: some View {
        HStack(spacing: 0) {
            Text("Every ")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            learningMinutesPicker

            Text(" of learning grants ")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            rewardMinutesPicker

            Text(" reward")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    private var learningMinutesPicker: some View {
        Menu {
            ForEach(ratioPresets, id: \.self) { minutes in
                Button(action: {
                    ratioLearningMinutes = minutes
                }) {
                    HStack {
                        Text(formatMinutes(minutes))
                        if ratioLearningMinutes == minutes {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(formatMinutes(ratioLearningMinutes))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(AppTheme.vibrantTeal)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.vibrantTeal.opacity(0.15))
            )
        }
    }

    private var rewardMinutesPicker: some View {
        Menu {
            ForEach(ratioPresets, id: \.self) { minutes in
                Button(action: {
                    rewardMinutesEarned = minutes
                }) {
                    HStack {
                        Text(formatMinutes(minutes))
                        if rewardMinutesEarned == minutes {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(formatMinutes(rewardMinutesEarned))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(AppTheme.playfulCoral)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.playfulCoral.opacity(0.15))
            )
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins > 0 {
                return "\(hours)h \(mins)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}
