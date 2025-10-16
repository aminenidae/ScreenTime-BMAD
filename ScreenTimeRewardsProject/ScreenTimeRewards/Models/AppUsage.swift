import Foundation

/// Represents an app usage record for tracking purposes
struct AppUsage: Codable, Identifiable {
    // Explicitly define CodingKeys to exclude id from decoding since it's computed
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier, appName, category, totalTime, sessions, firstAccess, lastAccess
    }
    
    let id = UUID()
    let bundleIdentifier: String
    let appName: String
    let category: AppCategory
    var totalTime: TimeInterval // in seconds
    var sessions: [UsageSession]
    let firstAccess: Date
    var lastAccess: Date
    
    enum AppCategory: String, Codable, CaseIterable {
        case educational = "Educational"
        case entertainment = "Entertainment"
        case productivity = "Productivity"
        case social = "Social"
        case games = "Games"
        case utility = "Utility"
        case other = "Other"
    }
    
    struct UsageSession: Codable, Identifiable {
        // Explicitly define CodingKeys to exclude id and duration from decoding since they're computed
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
    init(bundleIdentifier: String, appName: String, category: AppCategory) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.category = category
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
         lastAccess: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.category = category
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
}