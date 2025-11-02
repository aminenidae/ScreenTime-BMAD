import SwiftUI

struct CategoryUsageCard: View {
    let summary: CategoryUsageSummary

    var categoryIcon: String {
        switch summary.category {
        case "Learning": return "📚"
        case "Reward": return "🎮"
        case "Social": return "💬"
        case "Creative": return "🎨"
        default: return "📱"
        }
    }

    var categoryColor: Color {
        switch summary.category {
        case "Learning": return .blue
        case "Reward": return .purple
        case "Social": return .green
        case "Creative": return .orange
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(categoryIcon)
                    .font(.largeTitle)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.category) Apps")
                        .font(.headline)
                        .foregroundColor(categoryColor)

                    Text("\(summary.appCount) app\(summary.appCount == 1 ? "" : "s") active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            Divider()

            // Stats
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(summary.formattedTime)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Points")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(summary.totalPoints)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(categoryColor)
                }
            }
        }
        .padding()
        .background(categoryColor.opacity(0.1))
        .cornerRadius(12)
    }
}

struct CategoryUsageCard_Previews: PreviewProvider {
    static var previews: some View {
        CategoryUsageCard(
            summary: CategoryUsageSummary(
                category: "Learning",
                totalSeconds: 3600,
                appCount: 3,
                totalPoints: 120,
                apps: []
            )
        )
        .padding()
    }
}