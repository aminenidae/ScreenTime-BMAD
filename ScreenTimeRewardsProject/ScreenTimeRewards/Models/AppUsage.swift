import Foundation
import FamilyControls
import ManagedSettings

/// Represents an unlocked reward app with reserved learning points
///
/// Point Calculation Formula:
/// - reservedPoints = Initial Redeemed Points - Consumed Points
/// - As the app is used, points are consumed and reservedPoints decreases
/// - When reservedPoints reaches 0, the app is automatically locked
struct UnlockedRewardApp: Codable, Identifiable {
    let id: String  // Token hash
    var token: ApplicationToken?

    /// Remaining reserved points (Redeemed - Consumed)
    /// This value decreases as the app is used
    var reservedPoints: Int

    /// Cost per minute of usage
    let pointsPerMinute: Int

    /// When this app was unlocked
    let unlockedAt: Date

    /// How many minutes of usage remain based on reserved points
    var remainingMinutes: Int {
        guard pointsPerMinute > 0 else { return 0 }
        return reservedPoints / pointsPerMinute
    }

    /// Whether the reserved points have been exhausted
    var isExpired: Bool {
        reservedPoints <= 0
    }

    /// Indicates whether this unlock was granted by completing a challenge.
    /// Challenge unlocks should not consume the child's earned points.
    var isChallengeReward: Bool

    enum CodingKeys: String, CodingKey {
        case id, reservedPoints, pointsPerMinute, unlockedAt, isChallengeReward
    }

    init(token: ApplicationToken, tokenHash: String, reservedPoints: Int, pointsPerMinute: Int, isChallengeReward: Bool = false) {
        self.id = tokenHash  // Use stable SHA-256 hash instead of unstable hashValue
        self.token = token
        self.reservedPoints = reservedPoints
        self.pointsPerMinute = pointsPerMinute
        self.unlockedAt = Date()
        self.isChallengeReward = isChallengeReward
    }

    // Initializer for rehydration with preserved unlock time
    init(token: ApplicationToken, tokenHash: String, reservedPoints: Int, pointsPerMinute: Int, unlockedAt: Date, isChallengeReward: Bool = false) {
        self.id = tokenHash  // Use stable SHA-256 hash instead of unstable hashValue
        self.token = token
        self.reservedPoints = reservedPoints
        self.pointsPerMinute = pointsPerMinute
        self.unlockedAt = unlockedAt
        self.isChallengeReward = isChallengeReward
    }

    // Custom decoding to handle token reconstruction limitation
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.reservedPoints = try container.decode(Int.self, forKey: .reservedPoints)
        self.pointsPerMinute = try container.decode(Int.self, forKey: .pointsPerMinute)
        self.unlockedAt = try container.decode(Date.self, forKey: .unlockedAt)
        self.isChallengeReward = try container.decodeIfPresent(Bool.self, forKey: .isChallengeReward) ?? false
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
        try container.encode(isChallengeReward, forKey: .isChallengeReward)
    }
}

/// Represents an app usage record for tracking purposes
struct AppUsage: Codable, Identifiable {
    // Explicitly define CodingKeys to exclude id from decoding since it's computed
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier, appName, category, totalTime, sessions, firstAccess, lastAccess, rewardPoints, earnedRewardPoints
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
    private(set) var earnedRewardPoints: Int // Accumulated points (stored, not computed)
    
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
        self.earnedRewardPoints = 0
    }
    
    /// Convenience initializer for creating an app usage record with predetermined values
    init(bundleIdentifier: String,
         appName: String,
         category: AppCategory,
         totalTime: TimeInterval,
         sessions: [UsageSession],
         firstAccess: Date,
         lastAccess: Date,
         rewardPoints: Int = 10,
         earnedRewardPoints: Int = 0) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.category = category
        self.rewardPoints = rewardPoints
        self.totalTime = totalTime
        self.sessions = sessions
        self.firstAccess = firstAccess
        self.lastAccess = lastAccess
        self.earnedRewardPoints = earnedRewardPoints
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

        // Calculate and add points for ONLY the new duration (incremental tracking)
        let newMinutes = Int(duration / 60)
        let newPoints = newMinutes * rewardPoints
        earnedRewardPoints += newPoints
    }
    
    /// Get today's usage time
    var todayUsage: TimeInterval {
        let today = Calendar.current.startOfDay(for: Date())
        return sessions.filter { session in
            guard let sessionDate = session.endTime ?? session.startTime as Date? else { return false }
            return Calendar.current.isDate(sessionDate, inSameDayAs: today)
        }.reduce(0) { $0 + $1.duration }
    }
}
