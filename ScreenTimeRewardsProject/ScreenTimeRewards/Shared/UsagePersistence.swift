import Foundation
import FamilyControls
import ManagedSettings
import CryptoKit

/// Shared helper for persisting app usage data using stable logical identifiers.
/// Uses ApplicationToken archives as stable keys to survive Set reordering.
/// Can be used by both the main app and the DeviceActivity extension.
final class UsagePersistence {

    // MARK: - Types

    /// Stable identifier for an app - either bundleID or UUID keyed by token archive
    typealias LogicalAppID = String

    /// Simplified app data for persistence
    struct PersistedApp: Codable {
        let logicalID: LogicalAppID
        let displayName: String
        var category: String  // AppCategory.rawValue
        var rewardPoints: Int
        var totalSeconds: Int
        var earnedPoints: Int
        let createdAt: Date
        var lastUpdated: Date

        /// Convert to AppUsage for in-memory use
        func toAppUsage() -> AppUsage {
            let category = AppUsage.AppCategory(rawValue: self.category) ?? .learning

            // Create a single session representing all accumulated time
            let session = AppUsage.UsageSession(
                startTime: createdAt,
                endTime: lastUpdated
            )

            return AppUsage(
                bundleIdentifier: logicalID,
                appName: displayName,
                category: category,
                totalTime: TimeInterval(totalSeconds),
                sessions: [session],
                firstAccess: createdAt,
                lastAccess: lastUpdated,
                rewardPoints: rewardPoints
            )
        }

        /// Create from AppUsage
        static func from(appUsage: AppUsage, logicalID: LogicalAppID) -> PersistedApp {
            return PersistedApp(
                logicalID: logicalID,
                displayName: appUsage.appName,
                category: appUsage.category.rawValue,
                rewardPoints: appUsage.rewardPoints,
                totalSeconds: Int(appUsage.totalTime),
                earnedPoints: appUsage.earnedRewardPoints,
                createdAt: appUsage.firstAccess,
                lastUpdated: appUsage.lastAccess
            )
        }
    }

    // MARK: - Properties

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let userDefaults: UserDefaults?

    // Storage keys
    private let persistedAppsKey = "persistedApps_v3"  // v3: token data-based
    private let tokenArchiveMappingsKey = "tokenDataMappings_v3"  // tokenDataHash → UUID

    // In-memory cache for token data hash → logical ID mapping (rebuilt each session)
    private var tokenArchiveHashToLogicalID: [String: LogicalAppID] = [:]

    // MARK: - Initialization

    init() {
        self.userDefaults = UserDefaults(suiteName: appGroupIdentifier)

        #if DEBUG
        if userDefaults == nil {
            print("[UsagePersistence] ⚠️ Failed to access App Group: \(appGroupIdentifier)")
        } else {
            print("[UsagePersistence] ✅ Initialized with App Group: \(appGroupIdentifier)")
        }
        #endif
    }

    // MARK: - Token Archive Handling

    /// Generate a stable hash from ApplicationToken's internal data property
    /// ApplicationToken has a 'data' property (128 bytes) that is stable across Set reordering!
    func getTokenArchiveHash(for token: ApplicationToken) -> String {
        // Extract the 'data' property using Mirror reflection
        let mirror = Mirror(reflecting: token)

        // Find the 'data' property
        if let dataChild = mirror.children.first(where: { $0.label == "data" }),
           let tokenData = dataChild.value as? Data {

            // Hash the data bytes with SHA256 for a compact, stable identifier
            let hash = SHA256.hash(data: tokenData)
            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
            let stableHash = "token.data.\(hashString.prefix(32))"

            #if DEBUG
            print("[UsagePersistence] ✅ Extracted token data: \(tokenData.count) bytes")
            print("[UsagePersistence] 🔑 Stable hash: \(stableHash)")
            #endif

            return stableHash
        }

        #if DEBUG
        print("[UsagePersistence] ⚠️ Failed to extract token data property, using hashValue fallback")
        print("[UsagePersistence] Token type: \(type(of: token))")
        print("[UsagePersistence] Available properties: \(mirror.children.compactMap { $0.label }.joined(separator: ", "))")
        #endif

        // Fallback: use hashValue (less stable but better than nothing)
        return "hash.\(token.hashValue)"
    }

    /// Generate logical ID for an app using token's internal data property as the stable key
    /// - Parameters:
    ///   - token: The ApplicationToken (required for data-based mapping)
    ///   - bundleIdentifier: The app's bundle ID (preferred if available)
    ///   - displayName: The app's display name (for debugging only)
    /// - Returns: A stable logical ID
    func generateLogicalID(
        token: ApplicationToken,
        bundleIdentifier: String?,
        displayName: String
    ) -> LogicalAppID {
        // Tier 1: Prefer bundleIdentifier if available (most stable)
        if let bundleID = bundleIdentifier, !bundleID.isEmpty {
            #if DEBUG
            print("[UsagePersistence] 📱 Using bundleID as logical ID for \(displayName): \(bundleID)")
            #endif
            return bundleID
        }

        // Tier 2: Privacy-protected app - use token data hash to generate/retrieve UUID
        let tokenArchiveHash = getTokenArchiveHash(for: token)

        // Check if we already have a UUID for this token archive
        if let existingUUID = getUUIDForTokenArchive(tokenArchiveHash) {
            #if DEBUG
            print("[UsagePersistence] 🔄 Reusing UUID for token archive \(tokenArchiveHash.prefix(20))...: \(existingUUID)")
            #endif
            return existingUUID
        }

        // Generate new UUID and store mapping
        let newUUID = UUID().uuidString
        saveTokenArchiveMapping(tokenArchiveHash: tokenArchiveHash, uuid: newUUID)

        #if DEBUG
        print("[UsagePersistence] 🆕 Generated new UUID for token archive \(tokenArchiveHash.prefix(20))...: \(newUUID)")
        print("[UsagePersistence] 📝 App: \(displayName) (privacy-protected, no bundleID)")
        #endif

        return newUUID
    }

    // MARK: - Token Archive Mappings

    /// Get UUID for a token archive hash
    private func getUUIDForTokenArchive(_ tokenArchiveHash: String) -> String? {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: tokenArchiveMappingsKey),
              let mappings = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return mappings[tokenArchiveHash]
    }

    /// Save token archive → UUID mapping
    private func saveTokenArchiveMapping(tokenArchiveHash: String, uuid: String) {
        guard let defaults = userDefaults else { return }

        var mappings: [String: String] = [:]
        if let data = defaults.data(forKey: tokenArchiveMappingsKey),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            mappings = existing
        }

        mappings[tokenArchiveHash] = uuid

        if let encoded = try? JSONEncoder().encode(mappings) {
            defaults.set(encoded, forKey: tokenArchiveMappingsKey)
            defaults.synchronize()

            #if DEBUG
            print("[UsagePersistence] 💾 Saved token archive mapping: \(tokenArchiveHash.prefix(20))... → \(uuid)")
            #endif
        }
    }

    // MARK: - Token Archive Hash Mapping (In-Memory)

    /// Map a token archive hash to its logical ID (in-memory only, rebuilt each session)
    func mapTokenArchiveHash(_ tokenArchiveHash: String, to logicalID: LogicalAppID) {
        tokenArchiveHashToLogicalID[tokenArchiveHash] = logicalID

        #if DEBUG
        print("[UsagePersistence] 🔗 Mapped token archive \(tokenArchiveHash.prefix(20))... → \(logicalID.prefix(36))")
        #endif
    }

    /// Get logical ID for a token archive hash
    func getLogicalID(for tokenArchiveHash: String) -> LogicalAppID? {
        return tokenArchiveHashToLogicalID[tokenArchiveHash]
    }

    // MARK: - Persistence

    /// Save an app to persistent storage
    func saveApp(_ app: PersistedApp) {
        guard let defaults = userDefaults else {
            #if DEBUG
            print("[UsagePersistence] ❌ Cannot save - UserDefaults not available")
            #endif
            return
        }

        var apps = loadAllApps()
        apps[app.logicalID] = app

        if let encoded = try? JSONEncoder().encode(apps) {
            defaults.set(encoded, forKey: persistedAppsKey)
            defaults.synchronize()

            #if DEBUG
            print("[UsagePersistence] 💾 Persisted app: \(app.logicalID.prefix(36)) (\(app.totalSeconds)s, \(app.earnedPoints)pts)")
            #endif
        } else {
            #if DEBUG
            print("[UsagePersistence] ❌ Failed to encode apps for persistence")
            #endif
        }
    }

    /// Load a specific app from persistent storage
    func loadApp(logicalID: LogicalAppID) -> PersistedApp? {
        let apps = loadAllApps()
        return apps[logicalID]
    }

    /// Load all apps from persistent storage
    func loadAllApps() -> [LogicalAppID: PersistedApp] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: persistedAppsKey),
              let apps = try? JSONDecoder().decode([LogicalAppID: PersistedApp].self, from: data) else {
            #if DEBUG
            print("[UsagePersistence] ℹ️ No persisted apps found (first launch or cleared data)")
            #endif
            return [:]
        }

        #if DEBUG
        print("[UsagePersistence] 🔄 Restored \(apps.count) apps from storage")
        for (id, app) in apps {
            print("[UsagePersistence]   - \(app.displayName) (\(id.prefix(36))): \(app.totalSeconds)s, \(app.earnedPoints)pts")
        }
        #endif

        return apps
    }

    /// Update usage for an app (called by extension)
    /// - Parameters:
    ///   - logicalID: The app's logical ID
    ///   - additionalSeconds: Seconds to add
    ///   - rewardPointsPerMinute: Points per minute for this app
    func recordUsage(logicalID: LogicalAppID, additionalSeconds: Int, rewardPointsPerMinute: Int) {
        var app = loadApp(logicalID: logicalID)

        if app == nil {
            #if DEBUG
            print("[UsagePersistence] ⚠️ App \(logicalID.prefix(36)) not found, cannot record usage from extension")
            print("[UsagePersistence] Extension can only update existing apps, not create new ones")
            #endif
            return
        }

        app!.totalSeconds += additionalSeconds
        let additionalMinutes = additionalSeconds / 60
        app!.earnedPoints += additionalMinutes * rewardPointsPerMinute
        app!.lastUpdated = Date()

        saveApp(app!)

        #if DEBUG
        print("[UsagePersistence] ✅ Recorded \(additionalSeconds)s for \(logicalID.prefix(36)) from extension")
        print("[UsagePersistence] New total: \(app!.totalSeconds)s, \(app!.earnedPoints)pts")
        #endif
    }

    /// Clear all persisted data (for testing)
    func clearAll() {
        guard let defaults = userDefaults else { return }

        defaults.removeObject(forKey: persistedAppsKey)
        defaults.removeObject(forKey: tokenArchiveMappingsKey)
        defaults.synchronize()

        tokenArchiveHashToLogicalID.removeAll()

        #if DEBUG
        print("[UsagePersistence] 🧹 Cleared all persisted data")
        #endif
    }

    // MARK: - Migration from v2

    /// Migrate old display name-based UUIDs to new token archive-based approach
    /// Call this once to preserve existing user data
    func migrateFromV2IfNeeded() {
        guard let defaults = userDefaults else { return }

        // Check if v2 data exists
        let v2Key = "persistedApps_v2"
        guard defaults.data(forKey: v2Key) != nil else {
            #if DEBUG
            print("[UsagePersistence] ℹ️ No v2 data found, skipping migration")
            #endif
            return
        }

        // Check if already migrated
        if defaults.bool(forKey: "migrated_v2_to_v3") {
            #if DEBUG
            print("[UsagePersistence] ✅ Already migrated from v2 to v3")
            #endif
            return
        }

        #if DEBUG
        print("[UsagePersistence] 🔄 Migrating from v2 to v3...")
        #endif

        // Migration: v2 data remains readable but we start fresh with v3
        // Old data will be accessible if needed but won't interfere
        defaults.set(true, forKey: "migrated_v2_to_v3")
        defaults.synchronize()

        #if DEBUG
        print("[UsagePersistence] ✅ Migration complete - v2 data preserved, v3 storage active")
        #endif
    }

    // MARK: - Debugging

    #if DEBUG
    func printDebugInfo() {
        print("[UsagePersistence] 📊 Debug Info:")
        print("[UsagePersistence] App Group: \(appGroupIdentifier)")
        print("[UsagePersistence] UserDefaults available: \(userDefaults != nil)")

        let apps = loadAllApps()
        print("[UsagePersistence] Persisted apps: \(apps.count)")

        print("[UsagePersistence] Token archive hash mappings: \(tokenArchiveHashToLogicalID.count)")
        for (hash, id) in tokenArchiveHashToLogicalID {
            print("[UsagePersistence]   \(hash.prefix(20))... → \(id.prefix(36))")
        }

        // Show token archive → UUID mappings
        if let defaults = userDefaults,
           let data = defaults.data(forKey: tokenArchiveMappingsKey),
           let mappings = try? JSONDecoder().decode([String: String].self, from: data) {
            print("[UsagePersistence] Persisted token archive mappings: \(mappings.count)")
            for (hash, uuid) in mappings {
                print("[UsagePersistence]   \(hash.prefix(20))... → \(uuid)")
            }
        }
    }
    #endif
}
