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

    /// Represents usage summary for a single calendar day
    struct DailyUsageSummary: Codable, Equatable {
        let date: Date   // Normalized to start-of-day
        var seconds: Int
        var points: Int

        init(date: Date, seconds: Int, points: Int) {
            self.date = Calendar.current.startOfDay(for: date)
            self.seconds = seconds
            self.points = points
        }
    }

    struct PersistedApp: Codable {
        let logicalID: LogicalAppID
        let displayName: String
        var category: String
        var rewardPoints: Int
        var totalSeconds: Int
        var earnedPoints: Int
        let createdAt: Date
        var lastUpdated: Date
        var todaySeconds: Int
        var todayPoints: Int
        var lastResetDate: Date
        var dailyHistory: [DailyUsageSummary]

        // Custom init for migration from old format
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            logicalID = try container.decode(LogicalAppID.self, forKey: .logicalID)
            displayName = try container.decode(String.self, forKey: .displayName)
            category = try container.decode(String.self, forKey: .category)
            rewardPoints = try container.decode(Int.self, forKey: .rewardPoints)
            totalSeconds = try container.decode(Int.self, forKey: .totalSeconds)
            earnedPoints = try container.decode(Int.self, forKey: .earnedPoints)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)

            // New fields with defaults for migration
            todaySeconds = try container.decodeIfPresent(Int.self, forKey: .todaySeconds) ?? 0
            todayPoints = try container.decodeIfPresent(Int.self, forKey: .todayPoints) ?? 0
            lastResetDate = try container.decodeIfPresent(Date.self, forKey: .lastResetDate) ?? Calendar.current.startOfDay(for: Date())
            dailyHistory = try container.decodeIfPresent([DailyUsageSummary].self, forKey: .dailyHistory) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case logicalID, displayName, category, rewardPoints, totalSeconds, earnedPoints, createdAt, lastUpdated, todaySeconds, todayPoints, lastResetDate, dailyHistory
        }

        // Regular initializer for creating new instances
        init(logicalID: LogicalAppID,
             displayName: String,
             category: String,
             rewardPoints: Int,
             totalSeconds: Int,
             earnedPoints: Int,
             createdAt: Date,
             lastUpdated: Date,
             todaySeconds: Int = 0,
             todayPoints: Int = 0,
             lastResetDate: Date? = nil,
             dailyHistory: [DailyUsageSummary] = []) {
            self.logicalID = logicalID
            self.displayName = displayName
            self.category = category
            self.rewardPoints = rewardPoints
            self.totalSeconds = totalSeconds
            self.earnedPoints = earnedPoints
            self.createdAt = createdAt
            self.lastUpdated = lastUpdated
            self.todaySeconds = todaySeconds
            self.todayPoints = todayPoints
            self.lastResetDate = lastResetDate ?? Calendar.current.startOfDay(for: Date())
            self.dailyHistory = dailyHistory
        }
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

        // Improved fallback for unexpected token structure
        // Use a more descriptive fallback that includes the token's description
        let tokenDescription = String(describing: token).replacingOccurrences(of: " ", with: "_")
        return "token.fallback.\(tokenDescription)"
    }

    /// Compatibility shim for existing callers.
    func getTokenArchiveHash(for token: ManagedSettings.ApplicationToken) -> String {
        tokenHash(for: token)
    }

    func logicalID(for tokenHash: String) -> LogicalAppID? {
        cachedTokenMappings[tokenHash]?.logicalID
    }

    /// Resolve logical ID from a bundle identifier (when available).
    /// Falls back to direct app lookup where logical IDs are stored as bundle IDs.
    func logicalID(forBundleIdentifier bundleID: String) -> LogicalAppID? {
        if cachedApps[bundleID] != nil {
            return bundleID
        }

        if let mapping = cachedTokenMappings.values.first(where: { $0.bundleIdentifier == bundleID }) {
            return mapping.logicalID
        }

        return nil
    }

    func loadAllApps() -> [LogicalAppID: PersistedApp] {
        cachedApps
    }

    /// Reload cached apps from shared defaults, returning the latest snapshot.
    func reloadAppsFromDisk() -> [LogicalAppID: PersistedApp] {
        cachedApps = UsagePersistence.decodeApps(from: userDefaults, key: persistedAppsKey)
        return cachedApps
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

        // Check if it's a new day and reset daily counters if needed
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if !calendar.isDate(app.lastResetDate, inSameDayAs: today) {
            // Archive previous day's usage before resetting
            if app.todaySeconds > 0 || app.todayPoints > 0 {
                let previousDay = calendar.startOfDay(for: app.lastResetDate)
                let summary = DailyUsageSummary(date: previousDay, seconds: app.todaySeconds, points: app.todayPoints)
                app.dailyHistory.append(summary)

                // Cleanup: keep only the last 30 days
                if let cutoff = calendar.date(byAdding: .day, value: -30, to: today) {
                    app.dailyHistory.removeAll { $0.date < cutoff }
                }

                #if DEBUG
                print("[UsagePersistence] 📅 Archived \(app.displayName): \(app.todaySeconds)s, \(app.todayPoints)pts on \(previousDay)")
                #endif
            }

            // New day - reset daily counters
            app.todaySeconds = 0
            app.todayPoints = 0
            app.lastResetDate = today

            #if DEBUG
            print("[UsagePersistence] 🌅 New day detected for \(app.displayName) - resetting daily counters")
            #endif
        }

        // Update both total and today counters
        let earnedPointsThisInterval = (additionalSeconds / 60) * rewardPointsPerMinute

        #if DEBUG
        let beforeTodaySeconds = app.todaySeconds
        let beforeTotalSeconds = app.totalSeconds
        print("[UsagePersistence] 🔍 DIAGNOSTIC: Recording usage for \(app.displayName)")
        print("[UsagePersistence] 🔍 DIAGNOSTIC: Before: todaySeconds=\(beforeTodaySeconds)s, totalSeconds=\(beforeTotalSeconds)s")
        print("[UsagePersistence] 🔍 DIAGNOSTIC: Adding: \(additionalSeconds)s")
        #endif

        app.totalSeconds += additionalSeconds
        app.earnedPoints += earnedPointsThisInterval
        app.todaySeconds += additionalSeconds
        app.todayPoints += earnedPointsThisInterval
        app.lastUpdated = now

        cachedApps[logicalID] = app
        persistApps()

        #if DEBUG
        print("[UsagePersistence] 🔍 DIAGNOSTIC: After: todaySeconds=\(app.todaySeconds)s, totalSeconds=\(app.totalSeconds)s, timestamp=\(Date())")
        print("[UsagePersistence] 📝 Recorded \(additionalSeconds)s for \(app.displayName): today=\(app.todaySeconds)s, total=\(app.totalSeconds)s")
        #endif
    }

    func clearAll() {
        cachedApps.removeAll()
        cachedTokenMappings.removeAll()
        persistApps()
        persistMappings()
    }

    /// Remove all persisted app usage data and token mappings.
    /// - Parameter reason: Optional context for logging to aid diagnostics.
    func clearAllAppData(reason: String? = nil) {
        clearAll()
        #if DEBUG
        if let reason, !reason.isEmpty {
            print("[UsagePersistence] 🧹 Cleared all persisted data (\(reason))")
        } else {
            print("[UsagePersistence] 🧹 Cleared all persisted data")
        }
        #endif
    }

    /// Reset today's usage counters for every persisted app.
    /// - Parameter referenceDate: Allows tests to supply a custom date for determining the new reset boundary.
    func resetDailyCounters(referenceDate: Date = Date()) {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: referenceDate)
        var mutated = false

        for (logicalID, var app) in cachedApps {
            // If we're crossing a day boundary, archive the previous day's usage
            if !calendar.isDate(app.lastResetDate, inSameDayAs: midnight) && (app.todaySeconds > 0 || app.todayPoints > 0) {
                let summary = DailyUsageSummary(date: app.lastResetDate, seconds: app.todaySeconds, points: app.todayPoints)
                app.dailyHistory.append(summary)

                // Cleanup: Keep only last 30 days
                if let cutoff = calendar.date(byAdding: .day, value: -30, to: midnight) {
                    app.dailyHistory.removeAll { $0.date < cutoff }
                }
            }

            if app.todaySeconds != 0 || app.todayPoints != 0 || !calendar.isDate(app.lastResetDate, inSameDayAs: midnight) {
                app.todaySeconds = 0
                app.todayPoints = 0
                app.lastResetDate = midnight
                cachedApps[logicalID] = app
                mutated = true
                #if DEBUG
                print("[UsagePersistence] 🌅 Reset daily counters for \(app.displayName) (\(logicalID))")
                #endif
            }
        }

        if mutated {
            persistApps()
        }
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
        
        // First, try to find a direct "data" property
        if let data = mirror.children.first(where: { $0.label == "data" })?.value as? Data {
            return data
        }

        // If not found, recursively search in nested structures
        for child in mirror.children {
            let childMirror = Mirror(reflecting: child.value)
            if let data = childMirror.children.first(where: { $0.label == "data" })?.value as? Data {
                return data
            }
            
            // Try one more level deep
            for grandChild in childMirror.children {
                let grandChildMirror = Mirror(reflecting: grandChild.value)
                if let data = grandChildMirror.children.first(where: { $0.label == "data" })?.value as? Data {
                    return data
                }
            }
        }

        #if DEBUG
        let labels = mirror.children.compactMap { $0.label }
        print("[UsagePersistence] ⚠️ Failed to extract token data property, using hashValue fallback")
        print("[UsagePersistence] Token type: \(type(of: token))")
        print("[UsagePersistence] Available properties: \(labels)")
        #endif

        // Last resort: try to create a hash from the token's description
        let tokenString = String(describing: token)
        return tokenString.data(using: .utf8)
    }
}
