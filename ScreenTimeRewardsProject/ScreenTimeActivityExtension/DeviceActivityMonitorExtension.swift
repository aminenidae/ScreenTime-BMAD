import DeviceActivity
import Foundation
import CoreFoundation

final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {
    // App Group identifier - must match in both main app and extension
    private let appGroupIdentifier = "group.com.screentimerewards.shared"

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
        postNotification("com.screentimerewards.eventDidReachThreshold", event: event, activity: activity)
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