import Foundation

/// Mutable version of FullAppConfigDTO for parent-side editing.
/// Used in ParentAppEditSheet to track changes before sending to child.
struct MutableAppConfigDTO: Identifiable {
    var id: String { logicalID }

    // MARK: - Immutable Identifiers

    /// Stable ID for the app (SHA-256 hash of ApplicationToken)
    let logicalID: String

    /// The child device this config belongs to
    let deviceID: String

    /// App display name (read-only from parent)
    let displayName: String

    /// Token hash for app identification (read-only)
    let tokenHash: String?

    // MARK: - Editable Basic Fields

    /// Category: "Learning" or "Reward"
    var category: String

    /// Points per minute for learning apps
    var pointsPerMinute: Int

    /// Whether app tracking is enabled
    var isEnabled: Bool

    /// Whether the reward app is currently blocked
    var blockingEnabled: Bool

    // MARK: - Editable Schedule

    /// Full schedule configuration (time windows, daily limits)
    var scheduleConfig: AppScheduleConfiguration?

    // MARK: - Editable Reward App Settings

    /// Linked learning apps for unlock requirements (editable list)
    var linkedLearningApps: [LinkedLearningApp]

    /// Unlock mode: all (AND) or any (OR)
    var unlockMode: UnlockMode

    // MARK: - Editable Streak Settings

    /// Streak bonus configuration
    var streakSettings: AppStreakSettings?

    // MARK: - Tracking

    /// Original config for change detection
    private let originalCategory: String
    private let originalPointsPerMinute: Int
    private let originalIsEnabled: Bool
    private let originalBlockingEnabled: Bool

    // MARK: - Static Factory

    /// Empty config for fallback initialization (should not be used in practice)
    static var empty: MutableAppConfigDTO {
        MutableAppConfigDTO(
            logicalID: "",
            deviceID: "",
            displayName: "Unknown",
            tokenHash: nil,
            category: "Learning",
            pointsPerMinute: 1,
            isEnabled: false,
            blockingEnabled: false,
            scheduleConfig: nil,
            linkedLearningApps: [],
            unlockMode: .all,
            streakSettings: nil
        )
    }

    // MARK: - Initialization

    /// Direct initializer with all fields
    private init(
        logicalID: String,
        deviceID: String,
        displayName: String,
        tokenHash: String?,
        category: String,
        pointsPerMinute: Int,
        isEnabled: Bool,
        blockingEnabled: Bool,
        scheduleConfig: AppScheduleConfiguration?,
        linkedLearningApps: [LinkedLearningApp],
        unlockMode: UnlockMode,
        streakSettings: AppStreakSettings?
    ) {
        self.logicalID = logicalID
        self.deviceID = deviceID
        self.displayName = displayName
        self.tokenHash = tokenHash
        self.category = category
        self.pointsPerMinute = pointsPerMinute
        self.isEnabled = isEnabled
        self.blockingEnabled = blockingEnabled
        self.scheduleConfig = scheduleConfig
        self.linkedLearningApps = linkedLearningApps
        self.unlockMode = unlockMode
        self.streakSettings = streakSettings

        // Store originals for change detection
        self.originalCategory = category
        self.originalPointsPerMinute = pointsPerMinute
        self.originalIsEnabled = isEnabled
        self.originalBlockingEnabled = blockingEnabled
    }

    /// Create from a FullAppConfigDTO for editing
    init(from dto: FullAppConfigDTO) {
        self.logicalID = dto.logicalID
        self.deviceID = dto.deviceID
        self.displayName = dto.displayName
        self.tokenHash = dto.tokenHash

        self.category = dto.category
        self.pointsPerMinute = dto.pointsPerMinute
        self.isEnabled = dto.isEnabled
        self.blockingEnabled = dto.blockingEnabled

        self.scheduleConfig = dto.scheduleConfig
        self.linkedLearningApps = dto.linkedLearningApps
        self.unlockMode = dto.unlockMode
        self.streakSettings = dto.streakSettings

        // Store originals for change detection
        self.originalCategory = dto.category
        self.originalPointsPerMinute = dto.pointsPerMinute
        self.originalIsEnabled = dto.isEnabled
        self.originalBlockingEnabled = dto.blockingEnabled
    }

    // MARK: - Computed Properties

    /// Whether this is a learning app
    var isLearningApp: Bool {
        category == "Learning"
    }

    /// Whether this is a reward app
    var isRewardApp: Bool {
        category == "Reward"
    }

    /// Check if any field has been modified
    var hasChanges: Bool {
        category != originalCategory ||
            pointsPerMinute != originalPointsPerMinute ||
            isEnabled != originalIsEnabled ||
            blockingEnabled != originalBlockingEnabled ||
            scheduleConfigChanged ||
            linkedLearningAppsChanged ||
            streakSettingsChanged
    }

    /// Check if schedule has changed (simplified check)
    private var scheduleConfigChanged: Bool {
        // For now, assume any schedule config counts as a change
        // A more sophisticated implementation would compare with original
        return scheduleConfig != nil
    }

    /// Check if linked apps have changed
    private var linkedLearningAppsChanged: Bool {
        // Compare counts and content
        return linkedLearningApps.count > 0 // Simplified check
    }

    /// Check if streak settings changed
    private var streakSettingsChanged: Bool {
        streakSettings != nil
    }

    // MARK: - Validation

    /// Validate the configuration before sending
    var validationErrors: [String] {
        var errors: [String] = []

        if category.isEmpty {
            errors.append("Category is required")
        }

        if pointsPerMinute < 0 {
            errors.append("Points per minute cannot be negative")
        }

        if isRewardApp && linkedLearningApps.isEmpty {
            // Warning, not necessarily an error
        }

        return errors
    }

    /// Whether the config is valid to send
    var isValid: Bool {
        validationErrors.isEmpty
    }
}

// MARK: - Category Change Helpers

extension MutableAppConfigDTO {
    /// Switch category from Learning to Reward
    mutating func switchToReward() {
        guard isLearningApp else { return }
        category = "Reward"
        // Set default reward app schedule
        if scheduleConfig == nil {
            scheduleConfig = .defaultReward(logicalID: logicalID)
        } else {
            // Update existing schedule with reward defaults
            scheduleConfig?.dailyLimits = .defaultReward
        }
        // Enable default streak settings
        if streakSettings == nil {
            streakSettings = .defaultSettings
        }
    }

    /// Switch category from Reward to Learning
    mutating func switchToLearning() {
        guard isRewardApp else { return }
        category = "Learning"
        // Clear reward-specific settings
        linkedLearningApps = []
        unlockMode = .all
        streakSettings = nil
        blockingEnabled = false
        // Update schedule to learning defaults
        scheduleConfig?.dailyLimits = .unlimited
    }
}

// MARK: - Schedule Helpers

extension MutableAppConfigDTO {
    /// Get daily limits summary for display
    var dailyLimitsSummary: String {
        scheduleConfig?.dailyLimits.displaySummary ?? "Not set"
    }

    /// Get time window summary for display
    var timeWindowSummary: String {
        if let config = scheduleConfig {
            if config.useAdvancedTimeWindowConfig {
                return config.dailyTimeWindows.displaySummary
            } else {
                return config.allowedTimeWindow.displayString
            }
        }
        return "Not set"
    }

    /// Get linked apps summary for display
    var linkedAppsSummary: String {
        if linkedLearningApps.isEmpty {
            return "None"
        }
        let count = linkedLearningApps.count
        let modeText = unlockMode == .all ? "all" : "any"
        return "\(count) app\(count == 1 ? "" : "s") (\(modeText) required)"
    }
}
