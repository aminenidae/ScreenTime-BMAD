import Foundation

/// Types of blocking reasons for shield messages
enum BlockingReasonType: String, Codable {
    case learningGoal       // Reward app blocked until learning goal met
    case dailyLimitReached  // Used up daily allowed minutes
    case downtime           // Outside allowed time window

    /// Priority for display (lower = higher priority, shows first when multiple reasons apply)
    /// Downtime (1) > Daily Limit (2) > Learning Goal (3)
    var priority: Int {
        switch self {
        case .downtime: return 1
        case .dailyLimitReached: return 2
        case .learningGoal: return 3
        }
    }
}

/// Per-app blocking data stored in App Group by token hash
struct AppBlockingInfo: Codable {
    let tokenHash: String              // SHA256 hash of ApplicationToken
    let reasonType: BlockingReasonType
    let updatedAt: Date

    // Learning goal context (when reasonType == .learningGoal)
    var learningTargetMinutes: Int?
    var learningCurrentMinutes: Int?

    // Daily limit context (when reasonType == .dailyLimitReached)
    var dailyLimitMinutes: Int?
    var usedMinutes: Int?

    // Downtime context (when reasonType == .downtime)
    // Full allowed time window for display
    var downtimeWindowStartHour: Int?
    var downtimeWindowStartMinute: Int?
    var downtimeWindowEndHour: Int?
    var downtimeWindowEndMinute: Int?
    var downtimeDayName: String?
    var downtimeSummaryMessage: String?  // Pre-computed summary from config

    // Legacy fields (kept for backwards compatibility)
    var downtimeEndHour: Int?
    var downtimeEndMinute: Int?

    // MARK: - Convenience Initializers

    /// Create blocking info for learning goal
    static func learningGoal(
        tokenHash: String,
        targetMinutes: Int,
        currentMinutes: Int
    ) -> AppBlockingInfo {
        AppBlockingInfo(
            tokenHash: tokenHash,
            reasonType: .learningGoal,
            updatedAt: Date(),
            learningTargetMinutes: targetMinutes,
            learningCurrentMinutes: currentMinutes
        )
    }

    /// Create blocking info for daily limit reached
    static func dailyLimit(
        tokenHash: String,
        limitMinutes: Int,
        usedMinutes: Int
    ) -> AppBlockingInfo {
        AppBlockingInfo(
            tokenHash: tokenHash,
            reasonType: .dailyLimitReached,
            updatedAt: Date(),
            dailyLimitMinutes: limitMinutes,
            usedMinutes: usedMinutes
        )
    }

    /// Create blocking info for downtime with full time window
    static func downtime(
        tokenHash: String,
        windowStartHour: Int,
        windowStartMinute: Int,
        windowEndHour: Int,
        windowEndMinute: Int,
        dayName: String,
        summaryMessage: String? = nil
    ) -> AppBlockingInfo {
        AppBlockingInfo(
            tokenHash: tokenHash,
            reasonType: .downtime,
            updatedAt: Date(),
            downtimeWindowStartHour: windowStartHour,
            downtimeWindowStartMinute: windowStartMinute,
            downtimeWindowEndHour: windowEndHour,
            downtimeWindowEndMinute: windowEndMinute,
            downtimeDayName: dayName,
            downtimeSummaryMessage: summaryMessage,
            // Also set legacy fields for backwards compatibility
            downtimeEndHour: windowStartHour,
            downtimeEndMinute: windowStartMinute
        )
    }
}
