import Foundation

struct CategoryUsageSummary: Identifiable {
    let id = UUID()
    let category: String
    let totalSeconds: Int
    let appCount: Int
    let totalPoints: Int
    let apps: [UsageRecord]

    var formattedTime: String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}