import Foundation
import ManagedSettings
import CryptoKit

/// Service to manage per-app blocking reasons in App Group UserDefaults
/// Each blocked app stores its own blocking info, keyed by token hash
class BlockingReasonService {
    static let shared = BlockingReasonService()

    private let appGroupID = "group.com.screentimerewards.shared"
    private let keyPrefix = "appBlocking_"

    private init() {}

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Token Hashing

    /// Generate a stable hash for an ApplicationToken
    /// This MUST match the algorithm used in ShieldConfigurationExtension
    func tokenHash(for token: ApplicationToken) -> String {
        let tokenData = try? JSONEncoder().encode(token)
        guard let data = tokenData else { return "unknown" }
        let hash = SHA256.hash(data: data)
        return "token.sha256." + hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Set Blocking Reason (per-app)

    /// Set learning goal blocking for a specific app
    func setLearningGoalBlocking(
        token: ApplicationToken,
        targetMinutes: Int,
        currentMinutes: Int
    ) {
        let hash = tokenHash(for: token)
        let info = AppBlockingInfo.learningGoal(
            tokenHash: hash,
            targetMinutes: targetMinutes,
            currentMinutes: currentMinutes
        )
        saveBlockingInfo(info, forHash: hash)
    }

    /// Set daily limit blocking for a specific app
    func setDailyLimitBlocking(
        token: ApplicationToken,
        limitMinutes: Int,
        usedMinutes: Int
    ) {
        let hash = tokenHash(for: token)
        let info = AppBlockingInfo.dailyLimit(
            tokenHash: hash,
            limitMinutes: limitMinutes,
            usedMinutes: usedMinutes
        )
        saveBlockingInfo(info, forHash: hash)
    }

    /// Set downtime blocking for a specific app with full time window
    func setDowntimeBlocking(
        token: ApplicationToken,
        windowStartHour: Int,
        windowStartMinute: Int,
        windowEndHour: Int,
        windowEndMinute: Int,
        dayName: String
    ) {
        let hash = tokenHash(for: token)
        let info = AppBlockingInfo.downtime(
            tokenHash: hash,
            windowStartHour: windowStartHour,
            windowStartMinute: windowStartMinute,
            windowEndHour: windowEndHour,
            windowEndMinute: windowEndMinute,
            dayName: dayName
        )
        saveBlockingInfo(info, forHash: hash)
    }

    /// Set blocking with priority check - only sets if new reason has higher priority
    func setBlockingWithPriority(
        token: ApplicationToken,
        newReason: BlockingReasonType,
        learningTarget: Int? = nil,
        learningCurrent: Int? = nil,
        dailyLimit: Int? = nil,
        usedMinutes: Int? = nil,
        downtimeWindowStartHour: Int? = nil,
        downtimeWindowStartMinute: Int? = nil,
        downtimeWindowEndHour: Int? = nil,
        downtimeWindowEndMinute: Int? = nil,
        downtimeDayName: String? = nil
    ) {
        let hash = tokenHash(for: token)

        // Check existing blocking reason
        if let existingInfo = getBlockingInfo(forHash: hash) {
            // Only update if new reason has higher priority (lower number)
            if newReason.priority >= existingInfo.reasonType.priority {
                return // Existing reason has equal or higher priority
            }
        }

        // Set the new blocking reason
        switch newReason {
        case .downtime:
            if let startHour = downtimeWindowStartHour,
               let startMinute = downtimeWindowStartMinute,
               let endHour = downtimeWindowEndHour,
               let endMinute = downtimeWindowEndMinute,
               let dayName = downtimeDayName {
                setDowntimeBlocking(
                    token: token,
                    windowStartHour: startHour,
                    windowStartMinute: startMinute,
                    windowEndHour: endHour,
                    windowEndMinute: endMinute,
                    dayName: dayName
                )
            }
        case .dailyLimitReached:
            if let limit = dailyLimit, let used = usedMinutes {
                setDailyLimitBlocking(token: token, limitMinutes: limit, usedMinutes: used)
            }
        case .learningGoal:
            if let target = learningTarget, let current = learningCurrent {
                setLearningGoalBlocking(token: token, targetMinutes: target, currentMinutes: current)
            }
        }
    }

    // MARK: - Get Blocking Info

    /// Get blocking info for a specific app by token
    func getBlockingInfo(for token: ApplicationToken) -> AppBlockingInfo? {
        let hash = tokenHash(for: token)
        return getBlockingInfo(forHash: hash)
    }

    /// Get blocking info by hash (internal use)
    private func getBlockingInfo(forHash hash: String) -> AppBlockingInfo? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: keyPrefix + hash) else {
            return nil
        }
        return try? JSONDecoder().decode(AppBlockingInfo.self, from: data)
    }

    // MARK: - Clear Blocking

    /// Clear blocking reason for a specific app
    func clearBlockingReason(token: ApplicationToken) {
        let hash = tokenHash(for: token)
        sharedDefaults?.removeObject(forKey: keyPrefix + hash)
    }

    /// Clear blocking reason by hash
    func clearBlockingReason(forHash hash: String) {
        sharedDefaults?.removeObject(forKey: keyPrefix + hash)
    }

    /// Clear all blocking data
    func clearAllBlockingData() {
        guard let defaults = sharedDefaults else { return }
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(keyPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Bulk Operations

    /// Set learning goal blocking for multiple apps at once
    func setLearningGoalBlockingForApps(
        tokens: Set<ApplicationToken>,
        targetMinutes: Int,
        currentMinutes: Int
    ) {
        for token in tokens {
            setLearningGoalBlocking(
                token: token,
                targetMinutes: targetMinutes,
                currentMinutes: currentMinutes
            )
        }
    }

    /// Clear blocking for multiple apps
    func clearBlockingForApps(tokens: Set<ApplicationToken>) {
        for token in tokens {
            clearBlockingReason(token: token)
        }
    }

    // MARK: - Private

    private func saveBlockingInfo(_ info: AppBlockingInfo, forHash hash: String) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        sharedDefaults?.set(data, forKey: keyPrefix + hash)
    }
}
