import Foundation

/// Payload structure for parent-to-child full configuration update commands.
/// This is sent via ConfigurationCommand with commandType "update_full_config".
struct FullConfigUpdatePayload: Codable {
    // MARK: - Command Metadata

    /// Unique identifier for this command
    let commandID: String

    /// The parent device that initiated this command
    let parentDeviceID: String

    /// When the parent made this modification
    let parentModifiedAt: Date

    /// Version number for optimistic locking
    let version: Int

    // MARK: - Target Identification

    /// The logical ID of the app being configured
    let logicalID: String

    /// The child device this config applies to
    let targetDeviceID: String

    // MARK: - Basic Configuration

    /// App category ("Learning" or "Reward")
    var category: String

    /// Points earned per minute of usage (for learning apps)
    var pointsPerMinute: Int

    /// Whether the app tracking is enabled
    var isEnabled: Bool

    /// Whether the app is currently blocked (for reward apps)
    var blockingEnabled: Bool

    // MARK: - Schedule Configuration

    /// Full schedule configuration including time windows and daily limits
    var scheduleConfig: AppScheduleConfiguration?

    // MARK: - Reward App Configuration

    /// Learning apps linked to this reward app for unlock requirements
    var linkedLearningApps: [LinkedLearningApp]

    /// Unlock mode: all (AND) or any (OR) linked apps
    var unlockMode: UnlockMode

    // MARK: - Streak Configuration

    /// Streak bonus settings for this app
    var streakSettings: AppStreakSettings?

    // MARK: - Initialization

    /// Create a new payload from a mutable config DTO
    init(
        from config: MutableAppConfigDTO,
        parentDeviceID: String,
        version: Int = 1
    ) {
        self.commandID = UUID().uuidString
        self.parentDeviceID = parentDeviceID
        self.parentModifiedAt = Date()
        self.version = version

        self.logicalID = config.logicalID
        self.targetDeviceID = config.deviceID

        self.category = config.category
        self.pointsPerMinute = config.pointsPerMinute
        self.isEnabled = config.isEnabled
        self.blockingEnabled = config.blockingEnabled

        self.scheduleConfig = config.scheduleConfig
        self.linkedLearningApps = config.linkedLearningApps
        self.unlockMode = config.unlockMode
        self.streakSettings = config.streakSettings
    }

    /// Create directly with all fields
    init(
        commandID: String = UUID().uuidString,
        parentDeviceID: String,
        parentModifiedAt: Date = Date(),
        version: Int = 1,
        logicalID: String,
        targetDeviceID: String,
        category: String,
        pointsPerMinute: Int,
        isEnabled: Bool,
        blockingEnabled: Bool,
        scheduleConfig: AppScheduleConfiguration?,
        linkedLearningApps: [LinkedLearningApp],
        unlockMode: UnlockMode,
        streakSettings: AppStreakSettings?
    ) {
        self.commandID = commandID
        self.parentDeviceID = parentDeviceID
        self.parentModifiedAt = parentModifiedAt
        self.version = version
        self.logicalID = logicalID
        self.targetDeviceID = targetDeviceID
        self.category = category
        self.pointsPerMinute = pointsPerMinute
        self.isEnabled = isEnabled
        self.blockingEnabled = blockingEnabled
        self.scheduleConfig = scheduleConfig
        self.linkedLearningApps = linkedLearningApps
        self.unlockMode = unlockMode
        self.streakSettings = streakSettings
    }
}

// MARK: - Encoding/Decoding Helpers

extension FullConfigUpdatePayload {
    /// Encode to Base64 string for storage in ConfigurationCommand.payloadJSON
    func toBase64String() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }

    /// Decode from Base64 string stored in ConfigurationCommand.payloadJSON
    static func fromBase64String(_ base64: String) throws -> FullConfigUpdatePayload {
        guard let data = Data(base64Encoded: base64) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid Base64 string")
            )
        }
        return try JSONDecoder().decode(FullConfigUpdatePayload.self, from: data)
    }
}
