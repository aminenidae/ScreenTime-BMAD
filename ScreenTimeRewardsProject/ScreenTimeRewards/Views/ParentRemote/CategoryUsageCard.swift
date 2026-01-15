import SwiftUI

struct CategoryUsageCard: View {
    let summary: CategoryUsageSummary
    @Environment(\.colorScheme) var colorScheme

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
        case "Learning": return AppTheme.vibrantTeal
        case "Reward": return AppTheme.playfulCoral
        case "Social": return AppTheme.sunnyYellow
        case "Creative": return AppTheme.sunnyYellow
        default: return AppTheme.textSecondary(for: colorScheme)
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
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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