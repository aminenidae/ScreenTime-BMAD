import DeviceActivity
import Foundation
import CoreFoundation

// MARK: - Lightweight Persistence Helper (Extension Version)

/// Simplified persistence helper for extension use
/// NOTE: Full version is in Shared/UsagePersistence.swift (used by main app)
/// This version uses v3 token archive-based persistence
private struct ExtensionUsagePersistence {
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

    let appGroupIdentifier = "group.com.screentimerewards.shared"

    func recordUsage(logicalID: LogicalAppID, additionalSeconds: Int, rewardPointsPerMinute: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Load existing apps
        var apps = loadAllApps()

        // Update or skip
        guard var app = apps[logicalID] else {
            #if DEBUG
            print("[ExtensionPersistence] ⚠️ App \(logicalID) not found, skipping")
            #endif
            return
        }

        app.totalSeconds += additionalSeconds
        let additionalMinutes = additionalSeconds / 60
        app.earnedPoints += additionalMinutes * rewardPointsPerMinute
        app.lastUpdated = Date()

        apps[logicalID] = app

        // Save to v3 storage key (token archive-based)
        if let encoded = try? JSONEncoder().encode(apps) {
            defaults.set(encoded, forKey: "persistedApps_v3")
            defaults.synchronize()

            #if DEBUG
            print("[ExtensionPersistence] ✅ Recorded \(additionalSeconds)s for \(logicalID)")
            print("[ExtensionPersistence] New total: \(app.totalSeconds)s, \(app.earnedPoints)pts")
            #endif
        }
    }

    private func loadAllApps() -> [LogicalAppID: PersistedApp] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: "persistedApps_v3"),
              let apps = try? JSONDecoder().decode([LogicalAppID: PersistedApp].self, from: data) else {
            return [:]
        }
        return apps
    }
}

final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {
    // App Group identifier - must match in both main app and extension
    private let appGroupIdentifier = "group.com.screentimerewards.shared"

    // Shared persistence helper
    private let usagePersistence = ExtensionUsagePersistence()

    override nonisolated init() {
        super.init()
        #if DEBUG
        print("[ScreenTimeActivityExtension] Initialized")
        #endif
    }

    private nonisolated func postNotification(_ name: String, event: DeviceActivityEvent.Name? = nil, activity: DeviceActivityName? = nil) {
        // Darwin notifications can't carry userInfo, so we store data in shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            var eventData: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970
            ]
            if let event {
                eventData["event"] = event.rawValue
                sharedDefaults.set(event.rawValue, forKey: "lastEvent")
            }
            if let activity {
                eventData["activity"] = activity.rawValue
                sharedDefaults.set(activity.rawValue, forKey: "lastActivity")
            }

            // Store complete event data as JSON
            if let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                sharedDefaults.set(jsonString, forKey: "lastEventData")
            }

            sharedDefaults.synchronize()

            #if DEBUG
            print("[ScreenTimeActivityExtension] Stored event data in App Group")
            print("[ScreenTimeActivityExtension] Event: \(event?.rawValue ?? "nil")")
            print("[ScreenTimeActivityExtension] Activity: \(activity?.rawValue ?? "nil")")
            #endif
        } else {
            #if DEBUG
            print("[ScreenTimeActivityExtension] ⚠️ Failed to access App Group: \(appGroupIdentifier)")
            #endif
        }

        // Send Darwin notification (trigger only, no data)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,  // Can't pass userInfo via Darwin
            true
        )

        #if DEBUG
        print("[ScreenTimeActivityExtension] Posted Darwin notification: \(name)")
        #endif
    }

    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] intervalDidStart for activity: \(activity.rawValue)")
        #endif
        postNotification("com.screentimerewards.intervalDidStart", activity: activity)
    }

    override nonisolated func intervalWillStartWarning(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] intervalWillStartWarning for activity: \(activity.rawValue)")
        #endif
        postNotification("com.screentimerewards.intervalWillStart", activity: activity)
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] intervalDidEnd for activity: \(activity.rawValue)")
        #endif
        postNotification("com.screentimerewards.intervalDidEnd", activity: activity)
    }

    override nonisolated func intervalWillEndWarning(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] intervalWillEndWarning for activity: \(activity.rawValue)")
        #endif
        postNotification("com.screentimerewards.intervalWillEnd", activity: activity)
    }

    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] eventDidReachThreshold:")
        print("[ScreenTimeActivityExtension]   Event: \(event.rawValue)")
        print("[ScreenTimeActivityExtension]   Activity: \(activity.rawValue)")
        #endif

        // Record usage to persistent storage IMMEDIATELY (even if main app is closed!)
        recordUsageFromEvent(event)

        // Also notify main app if it's running
        postNotification("com.screentimerewards.eventDidReachThreshold", event: event, activity: activity)
    }

    /// Record usage directly to shared storage from extension
    private nonisolated func recordUsageFromEvent(_ event: DeviceActivityEvent.Name) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeActivityExtension] ⚠️ Failed to access App Group for recording usage")
            #endif
            return
        }

        // Load event mappings
        guard let data = sharedDefaults.data(forKey: "eventMappings"),
              let mappings = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let eventInfo = mappings[event.rawValue] else {
            #if DEBUG
            print("[ScreenTimeActivityExtension] ⚠️ No mapping found for event: \(event.rawValue)")
            #endif
            return
        }

        // Extract app info
        guard let logicalID = eventInfo["logicalID"] as? String,
              let rewardPointsPerMinute = eventInfo["rewardPoints"] as? Int,
              let thresholdSeconds = eventInfo["thresholdSeconds"] as? Int else {
            #if DEBUG
            print("[ScreenTimeActivityExtension] ⚠️ Invalid event mapping data")
            #endif
            return
        }

        #if DEBUG
        print("[ScreenTimeActivityExtension] 📝 Recording usage:")
        print("[ScreenTimeActivityExtension]   Logical ID: \(logicalID)")
        print("[ScreenTimeActivityExtension]   Threshold: \(thresholdSeconds)s")
        print("[ScreenTimeActivityExtension]   Reward points/min: \(rewardPointsPerMinute)")
        #endif

        // Record usage using UsagePersistence
        usagePersistence.recordUsage(
            logicalID: logicalID,
            additionalSeconds: thresholdSeconds,
            rewardPointsPerMinute: rewardPointsPerMinute
        )

        #if DEBUG
        print("[ScreenTimeActivityExtension] ✅ Usage recorded to persistent storage!")
        #endif
    }

    override nonisolated func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] eventWillReachThresholdWarning:")
        print("[ScreenTimeActivityExtension]   Event: \(event.rawValue)")
        print("[ScreenTimeActivityExtension]   Activity: \(activity.rawValue)")
        #endif
        postNotification("com.screentimerewards.eventWillReachThreshold", event: event, activity: activity)
    }
}