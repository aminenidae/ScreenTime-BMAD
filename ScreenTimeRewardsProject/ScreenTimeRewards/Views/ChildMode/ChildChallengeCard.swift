import SwiftUI

struct ChildChallengeCard: View {
    let challenge: Challenge
    let progress: ChallengeProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                }

                Spacer()
            }

            // Progress Bar
            if let progress = progress {
                VStack(alignment: .leading, spacing: 8) {
                    // Animated progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)

                            // Progress fill
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progressGradient(for: progress.progressPercentage))
                                .frame(width: geometry.size.width * min(progress.progressPercentage / 100, 1.0), height: 16)
                                .animation(.spring(), value: progress.currentValue)
                        }
                    }
                    .frame(height: 16)

                    // Progress text
                    HStack {
                        Text("\(progress.currentValue)/\(progress.targetValue) \(valueUnit)")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(progress.progressPercentage))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
            }
            .padding(.top, 4)

            // Completion badge
            if progress?.isCompleted == true {
                completionBadge
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: progress?.isCompleted == true ? 3 : 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Helpers

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

    private var backgroundColor: Color {
        if progress?.isCompleted == true {
            return Color.yellow.opacity(0.15)  // Gold
        }
        return Color.blue.opacity(0.05)
    }

    private var borderColor: Color {
        if progress?.isCompleted == true {
            return Color.yellow  // Gold
        }
        return Color.gray.opacity(0.3)
    }

    private func progressGradient(for percentage: Double) -> LinearGradient {
        if percentage >= 90 {
            // Near completion - green
            return LinearGradient(
                colors: [.green, .green.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if percentage >= 50 {
            // Good progress - blue to green
            return LinearGradient(
                colors: [.blue, .green],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            // Early progress - blue
            return LinearGradient(
                colors: [.blue, .blue.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var completionBadge: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Completed!")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.15))
        )
    }
}
