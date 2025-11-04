import SwiftUI

struct ChallengeDetailView: View {
    let challenge: Challenge
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                detailsSection
                progressSection
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Challenge Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: goalTypeIcon)
                    .font(.largeTitle)
                    .foregroundColor(goalTypeColor)

                Spacer()

                if challenge.isActive {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                } else {
                    Text("Inactive")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.gray)
                        .cornerRadius(8)
                }
            }

            Text(challenge.title ?? "Untitled Challenge")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(challenge.challengeDescription ?? "No description")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)

            detailRow("Goal Type", value: goalTypeName)
            detailRow("Target Value", value: "\(challenge.targetValue) \(valueUnit)")
            detailRow("Bonus Points", value: "+\(challenge.bonusPercentage)%")
            detailRow("Duration", value: durationText)

            if let jsonString = challenge.targetAppsJSON,
               let data = jsonString.data(using: .utf8),
               let targetApps = try? JSONDecoder().decode([String].self, from: data),
               !targetApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Apps")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(targetApps, id: \.self) { appID in
                        Text(appID)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress")
                .font(.headline)

            // Progress visualization would go here
            Text("Progress tracking visualization would appear here")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var actionsSection: some View {
        VStack(alignment: .center, spacing: 16) {
            Button(action: {
                // Deactivate challenge action
            }) {
                Text("Deactivate Challenge")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Close")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
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

    private var goalTypeName: String {
        guard let goalType = challenge.goalType else { return "Unknown" }
        switch goalType {
        case "daily_minutes": return "Daily Minutes"
        case "weekly_minutes": return "Weekly Minutes"
        case "specific_apps": return "Specific Apps"
        case "streak": return "Streak"
        default: return "Unknown"
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
                return "From \(formatter.string(from: startDate)) (Ongoing)"
            }
        }
        return "Unknown"
    }
}
