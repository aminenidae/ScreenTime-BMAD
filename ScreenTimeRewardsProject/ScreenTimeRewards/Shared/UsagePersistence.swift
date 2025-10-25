import Foundation
import FamilyControls
import ManagedSettings
import CryptoKit

/// Shared helper for persisting app usage using stable identifiers derived from ApplicationToken data.
/// This helper is used by both the main app and the DeviceActivity extension.
@available(iOS 16.0, *)
final class UsagePersistence {

    // MARK: - Types

    typealias LogicalAppID = String

    struct PersistedApp: Codable {
        let logicalID: LogicalAppID
        let displayName: String
        var category: String
        var rewardPoints: Int
        var totalSeconds: Int
        var earnedPoints: Int
        let createdAt: Date
        var lastUpdated: Date
    }

    struct TokenMapping: Codable {
        let logicalID: LogicalAppID
        let displayName: String
        let bundleIdentifier: String?
        let createdAt: Date
        var lastUpdated: Date
    }

    // MARK: - Properties

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let persistedAppsKey = "persistedApps_v3"
    private let tokenMappingsKey = "tokenMappings_v1"

    private let userDefaults: UserDefaults?
    private var cachedApps: [LogicalAppID: PersistedApp]
    private var cachedTokenMappings: [String: TokenMapping]

    // MARK: - Initialisation

    init() {
        userDefaults = UserDefaults(suiteName: appGroupIdentifier)
        cachedApps = UsagePersistence.decodeApps(from: userDefaults, key: persistedAppsKey)
        cachedTokenMappings = UsagePersistence.decodeMappings(from: userDefaults, key: tokenMappingsKey)

        #if DEBUG
        if userDefaults == nil {
            print("[UsagePersistence] ⚠️ Failed to access App Group: \(appGroupIdentifier)")
        } else {
            print("[UsagePersistence] ✅ Loaded \(cachedApps.count) apps, \(cachedTokenMappings.count) token mappings")
        }
        #endif
    }

    // MARK: - Public API

    /// Resolve (and persist if needed) the logical ID for a given ApplicationToken.
    func resolveLogicalID(for token: ManagedSettings.ApplicationToken,
                          bundleIdentifier: String?,
                          displayName: String) -> (logicalID: LogicalAppID, tokenHash: String) {
        let tokenHash = tokenHash(for: token)

        if var mapping = cachedTokenMappings[tokenHash] {
            mapping.lastUpdated = Date()
            cachedTokenMappings[tokenHash] = mapping
            persistMappings()
            return (mapping.logicalID, tokenHash)
        }

        var logicalID: LogicalAppID

        if let bundleID = bundleIdentifier, !bundleID.isEmpty {
            logicalID = bundleID
        } else {
            // TASK K & L: Always generate a new UUID for privacy-protected apps to prevent collisions
            logicalID = UUID().uuidString
        }

        let mapping = TokenMapping(
            logicalID: logicalID,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            createdAt: Date(),
            lastUpdated: Date()
        )
        cachedTokenMappings[tokenHash] = mapping
        persistMappings()

        #if DEBUG
        print("[UsagePersistence] 🔗 Registered token hash \(tokenHash.prefix(16))… → \(logicalID)")
        #endif

        return (logicalID, tokenHash)
    }

    /// Convenience for existing callers – returns only logical ID.
    func generateLogicalID(token: ManagedSettings.ApplicationToken,
                           bundleIdentifier: String?,
                           displayName: String) -> LogicalAppID {
        resolveLogicalID(for: token, bundleIdentifier: bundleIdentifier, displayName: displayName).logicalID
    }

    /// Expose the stable token hash (SHA256 of the token's internal data).
    func tokenHash(for token: ManagedSettings.ApplicationToken) -> String {
        if let data = extractTokenData(token) {
            let digest = SHA256.hash(data: data)
            return "token.sha256." + digest.map { String(format: "%02x", $0) }.joined()
        }

        // Fallback for unexpected token structure – use Swift hash (unstable but better than nothing).
        return "token.hash.\(token.hashValue)"
    }

    /// Compatibility shim for existing callers.
    func getTokenArchiveHash(for token: ManagedSettings.ApplicationToken) -> String {
        tokenHash(for: token)
    }

    func logicalID(for tokenHash: String) -> LogicalAppID? {
        cachedTokenMappings[tokenHash]?.logicalID
    }

    func loadAllApps() -> [LogicalAppID: PersistedApp] {
        cachedApps
    }

    func app(for logicalID: LogicalAppID) -> PersistedApp? {
        cachedApps[logicalID]
    }

    func saveApp(_ app: PersistedApp) {
        cachedApps[app.logicalID] = app
        persistApps()
    }

    func recordUsage(logicalID: LogicalAppID,
                     additionalSeconds: Int,
                     rewardPointsPerMinute: Int) {
        guard var app = cachedApps[logicalID] else {
            #if DEBUG
            print("[UsagePersistence] ⚠️ Attempted to record usage for unknown app: \(logicalID)")
            #endif
            return
        }

        app.totalSeconds += additionalSeconds
        app.earnedPoints += (additionalSeconds / 60) * rewardPointsPerMinute
        app.lastUpdated = Date()

        cachedApps[logicalID] = app
        persistApps()
    }

    func clearAll() {
        cachedApps.removeAll()
        cachedTokenMappings.removeAll()
        persistApps()
        persistMappings()
    }

    /// Delete a persisted app by its logical ID
    /// - Parameter logicalID: The logical ID of the app to delete
    func deleteApp(logicalID: LogicalAppID) {
        cachedApps.removeValue(forKey: logicalID)
        persistApps()
        
        #if DEBUG
        print("[UsagePersistence] 🗑️ Deleted app with logicalID: \(logicalID)")
        #endif
    }

    #if DEBUG
    func printDebugInfo() {
        print("[UsagePersistence] 📊 Cached apps: \(cachedApps.count)")
        for (id, app) in cachedApps {
            print("   • \(app.displayName) -> \(id) (\(app.totalSeconds)s, \(app.earnedPoints)pts)")
        }
        print("[UsagePersistence] 🔐 Token mappings: \(cachedTokenMappings.count)")
        for (hash, mapping) in cachedTokenMappings {
            print("   • \(hash.prefix(16))… -> \(mapping.logicalID) [\(mapping.displayName)]")
        }
    }
    #endif

    // MARK: - Private helpers

    private func persistApps() {
        guard let defaults = userDefaults,
              let encoded = try? JSONEncoder().encode(cachedApps) else { return }
        defaults.set(encoded, forKey: persistedAppsKey)
        defaults.synchronize()
    }

    private func persistMappings() {
        guard let defaults = userDefaults,
              let encoded = try? JSONEncoder().encode(cachedTokenMappings) else { return }
        defaults.set(encoded, forKey: tokenMappingsKey)
        defaults.synchronize()
    }

    private static func decodeApps(from defaults: UserDefaults?, key: String) -> [LogicalAppID: PersistedApp] {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let apps = try? JSONDecoder().decode([LogicalAppID: PersistedApp].self, from: data) else {
            return [:]
        }
        return apps
    }

    private static func decodeMappings(from defaults: UserDefaults?, key: String) -> [String: TokenMapping] {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let mappings = try? JSONDecoder().decode([String: TokenMapping].self, from: data) else {
            return [:]
        }
        return mappings
    }

    private func extractTokenData(_ token: ManagedSettings.ApplicationToken) -> Data? {
        let mirror = Mirror(reflecting: token)
        if let data = mirror.children.first(where: { $0.label == "data" })?.value as? Data {
            return data
        }

        for child in mirror.children {
            let childMirror = Mirror(reflecting: child.value)
            if let data = childMirror.children.first(where: { $0.label == "data" })?.value as? Data {
                return data
            }
        }

        #if DEBUG
        let labels = mirror.children.compactMap { $0.label }
        print("[UsagePersistence] ⚠️ Failed to extract token data property, using hashValue fallback")
        print("[UsagePersistence] Token type: \(type(of: token))")
        print("[UsagePersistence] Available properties: \(labels)")
        #endif

        return nil
    }
}
