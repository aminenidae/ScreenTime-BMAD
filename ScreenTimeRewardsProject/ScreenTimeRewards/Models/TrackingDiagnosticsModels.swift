import Foundation

struct ExtensionHealthStatus {
    let lastHeartbeat: Date
    let heartbeatGapSeconds: Int
    let isHealthy: Bool
    let memoryUsageMB: Double
}

struct NotificationGapLog: Codable {
    let detectedAt: TimeInterval
    let missedCount: Int
}

struct UsageGap: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    let detectionMethod: String
}
