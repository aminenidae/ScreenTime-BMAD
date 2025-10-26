import Foundation
import FamilyControls
import ManagedSettings

/// Represents an unlocked reward app with reserved learning points
struct UnlockedRewardApp: Codable, Identifiable {
    let id: String  // Token hash
    var token: ApplicationToken?
    var reservedPoints: Int
    let pointsPerMinute: Int
    let unlockedAt: Date

    var remainingMinutes: Int {
        guard pointsPerMinute > 0 else { return 0 }
        return reservedPoints / pointsPerMinute
    }

    var isExpired: Bool {
        reservedPoints <= 0
    }

    enum CodingKeys: String, CodingKey {
        case id, reservedPoints, pointsPerMinute, unlockedAt
    }

    init(token: ApplicationToken, reservedPoints: Int, pointsPerMinute: Int) {
        self.id = String(token.hashValue)
        self.token = token
        self.reservedPoints = reservedPoints
        self.pointsPerMinute = pointsPerMinute
        self.unlockedAt = Date()
    }

    // Initializer for rehydration with preserved unlock time
    init(token: ApplicationToken, reservedPoints: Int, pointsPerMinute: Int, unlockedAt: Date) {
        self.id = String(token.hashValue)
        self.token = token
        self.reservedPoints = reservedPoints
        self.pointsPerMinute = pointsPerMinute
        self.unlockedAt = unlockedAt
    }

    // Custom decoding to handle token reconstruction limitation
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.reservedPoints = try container.decode(Int.self, forKey: .reservedPoints)
        self.pointsPerMinute = try container.decode(Int.self, forKey: .pointsPerMinute)
        self.unlockedAt = try container.decode(Date.self, forKey: .unlockedAt)
        // Note: token cannot be reconstructed from persistence
        // It must be re-matched from the current familySelection
        self.token = nil
    }

    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reservedPoints, forKey: .reservedPoints)
        try container.encode(pointsPerMinute, forKey: .pointsPerMinute)
        try container.encode(unlockedAt, forKey: .unlockedAt)
    }
}

/// Represents an app usage record for tracking purposes
struct AppUsage: Codable, Identifiable {
    // Explicitly define CodingKeys to exclude id from decoding since it's computed
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier, appName, category, totalTime, sessions, firstAccess, lastAccess, rewardPoints
    }
    
    let id = UUID()
    let bundleIdentifier: String
    let appName: String
    let category: AppCategory
    var totalTime: TimeInterval // in seconds
    var sessions: [UsageSession]
    let firstAccess: Date
    var lastAccess: Date
    var rewardPoints: Int // Reward points assigned to this app
    
    enum AppCategory: String, Codable, CaseIterable {
        case learning = "Learning"
        case reward = "Reward"
    }
    
    struct UsageSession: Codable, Identifiable {
        // Explicitly define CodingKeys to exclude id from decoding since it's computed
        enum CodingKeys: String, CodingKey {
            case startTime, endTime
        }
        
        let id = UUID()
        let startTime: Date
        var endTime: Date?
        var duration: TimeInterval {
            if let endTime = endTime {
                return endTime.timeIntervalSince(startTime)
            }
            return Date().timeIntervalSince(startTime)
        }
    }
    
    /// Initialize a new app usage record
    init(bundleIdentifier: String, appName: String, category: AppCategory, rewardPoints: Int = 10) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.category = category
        self.rewardPoints = rewardPoints
        self.totalTime = 0
        self.sessions = []
        self.firstAccess = Date()
        self.lastAccess = Date()
    }
    
    /// Convenience initializer for creating an app usage record with predetermined values
    init(bundleIdentifier: String,
         appName: String,
         category: AppCategory,
         totalTime: TimeInterval,
         sessions: [UsageSession],
         firstAccess: Date,
         lastAccess: Date,
         rewardPoints: Int = 10) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.category = category
        self.rewardPoints = rewardPoints
        self.totalTime = totalTime
        self.sessions = sessions
        self.firstAccess = firstAccess
        self.lastAccess = lastAccess
    }
    
    /// Start a new usage session
    mutating func startSession() {
        let session = UsageSession(startTime: Date())
        sessions.append(session)
        lastAccess = Date()
    }
    
    /// End the current usage session
    mutating func endSession() {
        guard let lastIndex = sessions.indices.last else { return }
        sessions[lastIndex].endTime = Date()
        updateTotalTime()
        lastAccess = Date()
    }
    
    /// Update the total time based on all sessions
    private mutating func updateTotalTime() {
        totalTime = sessions.reduce(0) { $0 + $1.duration }
    }

    /// Append a usage session with a known duration.
    /// - Parameters:
    ///   - duration: Length of the session in seconds.
    ///   - endDate: Timestamp marking the end of the session. Defaults to current date.
    mutating func recordUsage(duration: TimeInterval, endingAt endDate: Date = Date()) {
        let adjustedEnd = endDate
        let startDate = adjustedEnd.addingTimeInterval(-duration)
        let session = UsageSession(startTime: startDate, endTime: adjustedEnd)
        sessions.append(session)
        totalTime += duration
        lastAccess = adjustedEnd
    }
    
    /// Get today's usage time
    var todayUsage: TimeInterval {
        let today = Calendar.current.startOfDay(for: Date())
        return sessions.filter { session in
            guard let sessionDate = session.endTime ?? session.startTime as Date? else { return false }
            return Calendar.current.isDate(sessionDate, inSameDayAs: today)
        }.reduce(0) { $0 + $1.duration }
    }
    
    /// Calculate reward points earned based on usage time and assigned reward points
    var earnedRewardPoints: Int {
        let minutes = Int(totalTime / 60)
        // Calculate earned points based on assigned reward points and usage time
        // For example: If 80 points are assigned and user used app for 1 minute, they earn 80 points
        return minutes * rewardPoints
    }
}