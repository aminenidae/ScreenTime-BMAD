import Foundation

struct CategoryUsageSummary: Identifiable {
    let id = UUID()
    let category: String
    let totalSeconds: Int
    let appCount: Int
    let totalPoints: Int
    let apps: [UsageRecord]

    var formattedTime: String {
        TimeFormatting.formatSecondsCompact(TimeInterval(totalSeconds))
    }
}