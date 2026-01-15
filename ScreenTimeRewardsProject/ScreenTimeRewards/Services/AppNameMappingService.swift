import Foundation

/// Service to manage user-provided custom names for privacy-protected apps
/// This allows parents to name apps once and remember those names across sessions
class AppNameMappingService {
    static let shared = AppNameMappingService()

    private let userDefaults = UserDefaults.standard
    private let mappingsKey = "appNameMappings"

    private init() {}

    /// Get custom name for an app, or nil if not set
    func getCustomName(for logicalID: String) -> String? {
        guard let mappings = userDefaults.dictionary(forKey: mappingsKey) as? [String: String] else {
            return nil
        }
        return mappings[logicalID]
    }

    /// Set custom name for an app
    func setCustomName(_ name: String, for logicalID: String) {
        var mappings = userDefaults.dictionary(forKey: mappingsKey) as? [String: String] ?? [:]

        // Trim whitespace
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            // Empty name = remove mapping (revert to default)
            mappings.removeValue(forKey: logicalID)
        } else {
            mappings[logicalID] = trimmedName
        }

        userDefaults.set(mappings, forKey: mappingsKey)

        #if DEBUG
        print("[AppNameMappingService] Set custom name '\(trimmedName)' for \(logicalID)")
        #endif

        // Post notification so views can refresh
        NotificationCenter.default.post(name: .appNameMappingChanged, object: nil)
    }

    /// Remove custom name for an app (revert to default)
    func removeCustomName(for logicalID: String) {
        var mappings = userDefaults.dictionary(forKey: mappingsKey) as? [String: String] ?? [:]
        mappings.removeValue(forKey: logicalID)
        userDefaults.set(mappings, forKey: mappingsKey)

        #if DEBUG
        print("[AppNameMappingService] Removed custom name for \(logicalID)")
        #endif

        NotificationCenter.default.post(name: .appNameMappingChanged, object: nil)
    }

    /// Get display name for an app (custom name if set, otherwise default)
    /// - Parameters:
    ///   - logicalID: The app's logical ID
    ///   - defaultName: The default name to use if no custom name is set
    /// - Returns: The display name to show
    func getDisplayName(for logicalID: String, defaultName: String) -> String {
        return getCustomName(for: logicalID) ?? defaultName
    }

    /// Get display name for an app with automatic numbering
    /// - Parameters:
    ///   - logicalID: The app's logical ID
    ///   - category: The app's category (e.g., "Learning")
    ///   - appNumber: The app number within its category
    /// - Returns: The display name to show
    func getDisplayName(for logicalID: String, category: String, appNumber: Int) -> String {
        if let customName = getCustomName(for: logicalID) {
            return customName
        } else {
            return "Privacy Protected \(category) App #\(appNumber)"
        }
    }

    /// Check if an app has a custom name
    func hasCustomName(for logicalID: String) -> Bool {
        return getCustomName(for: logicalID) != nil
    }

    /// Get all custom mappings (for debugging/export)
    func getAllMappings() -> [String: String] {
        return userDefaults.dictionary(forKey: mappingsKey) as? [String: String] ?? [:]
    }

    /// Clear all custom mappings
    func clearAllMappings() {
        userDefaults.removeObject(forKey: mappingsKey)

        #if DEBUG
        print("[AppNameMappingService] Cleared all custom name mappings")
        #endif

        NotificationCenter.default.post(name: .appNameMappingChanged, object: nil)
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let appNameMappingChanged = Notification.Name("appNameMappingChanged")
}
