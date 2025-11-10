import SwiftUI

struct ParentChallengeCard: View {
    let challenge: Challenge
    let progress: ChallengeProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: goalTypeIcon)
                    .font(.title2)
                    .foregroundColor(goalTypeColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title ?? "Untitled Challenge")
                        .font(.headline)

                    Text(challenge.challengeDescription ?? "No description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Status indicator
                if let progress = progress, progress.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if let progress = progress {
                    Text("\(Int(progress.progressPercentage))%")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(progress.progressPercentage > 50 ? Color.green : Color.blue)
                        )
                        .foregroundColor(.white)
                }
            }

            rewardConfigurationRow

            // Progress bar
            if let progress = progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.progressPercentage, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: progress.progressPercentage > 50 ? .green : .blue))

                    HStack {
                        Text("\(progress.currentValue)/\(progress.targetValue) \(valueUnit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if challenge.isActive {
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        } else {
                            Text("Inactive")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.gray)
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Bonus + timeline info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                    Text("+\(challenge.bonusPercentage)% completion bonus")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(rewardSummaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(durationText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var goalTypeIcon: String {
        challenge.goalTypeEnum?.iconName ?? "flag.fill"
    }

    private var goalTypeColor: Color {
        challenge.goalTypeEnum?.accentColor ?? .gray
    }

    private var valueUnit: String {
        challenge.goalTypeEnum?.valueUnitLabel ?? "minutes"
    }

    private var rewardSummaryText: String {
        let count = challenge.rewardAppIDs.count
        switch count {
        case 0:
            return "No rewards"
        case 1:
            return "1 reward app"
        default:
            return "\(count) reward apps"
        }
    }

    private var durationText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short

        if let startDate = challenge.startDate {
            if let endDate = challenge.endDate {
                return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
            } else {
                return "Ongoing"
            }
        }
        return "Unknown"
    }

    @ViewBuilder
    private var rewardConfigurationRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(rewardRatioText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(rewardUnlockMinutesText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var rewardRatioText: String {
        challenge.learningToRewardRatio?.formattedDescription ?? LearningToRewardRatio.default.formattedDescription
    }

    private var rewardUnlockMinutesText: String {
        let minutes = challenge.rewardUnlockMinutes()
        let minuteLabel = minutes == 1 ? "minute" : "minutes"
        return "≈ \(minutes) \(minuteLabel) of reward time"
    }
}
