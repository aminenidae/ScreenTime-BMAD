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

            // Bonus info
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                Text("+\(challenge.bonusPercentage)% bonus points")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(durationText)
                    .font(.caption)
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
        guard let goalType = challenge.goalType else { return "flag.fill" }
        switch goalType {
        case "daily_minutes": return "sun.max.fill"
        case "weekly_minutes": return "calendar"
        case "specific_apps": return "app.fill"
        case "streak": return "flame.fill"
        default: return "flag.fill"
        }
    }

    private var goalTypeColor: Color {
        guard let goalType = challenge.goalType else { return .gray }
        switch goalType {
        case "daily_minutes": return .orange
        case "weekly_minutes": return .blue
        case "specific_apps": return .green
        case "streak": return .red
        default: return .gray
        }
    }

    private var valueUnit: String {
        guard let goalType = challenge.goalType else { return "min" }
        switch goalType {
        case "daily_minutes", "weekly_minutes", "specific_apps": return "min"
        case "streak": return "days"
        default: return "min"
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
}
