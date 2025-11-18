import DeviceActivity
import Foundation
import CoreFoundation
import Darwin

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
        var todaySeconds: Int
        var todayPoints: Int
        var lastResetDate: Date

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
        }

        enum CodingKeys: String, CodingKey {
            case logicalID, displayName, category, rewardPoints, totalSeconds, earnedPoints, createdAt, lastUpdated, todaySeconds, todayPoints, lastResetDate
        }
    }

    let appGroupIdentifier = "group.com.screentimerewards.shared"

    nonisolated func recordUsage(logicalID: LogicalAppID,
                                 additionalSeconds: Int,
                                 rewardPointsPerMinute: Int,
                                 displayName: String,
                                 category: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[ExtensionPersistence] FATAL: Cannot access app group '\(appGroupIdentifier)'")
            #if DEBUG
            fatalError("[ExtensionPersistence] App group unavailable - check entitlements")
            #else
            return
            #endif
        }

        // Load existing apps
        var apps = loadAllApps()

        guard var app = apps[logicalID] else {
            NSLog("[ExtensionPersistence] ❌ FATAL: App not seeded for logicalID '\(logicalID)'")
            NSLog("[ExtensionPersistence] Available apps: \(apps.keys.joined(separator: ", "))")
            NSLog("[ExtensionPersistence] This means main app didn't seed apps before monitoring started!")
            #if DEBUG
            fatalError("[ExtensionPersistence] App '\(displayName)' not seeded - main app should seed all apps before monitoring")
            #endif
            return
        }

        // Check if it's a new day and reset daily counters if needed
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if !calendar.isDate(app.lastResetDate, inSameDayAs: today) {
            // New day - reset daily counters
            app.todaySeconds = 0
            app.todayPoints = 0
            app.lastResetDate = today

            NSLog("[ExtensionPersistence] 🌅 New day detected for \(app.displayName) - resetting daily counters")
        }

        // Update both total and today counters
        let earnedPointsThisInterval = (additionalSeconds / 60) * rewardPointsPerMinute

        #if DEBUG
        let beforeTodaySeconds = app.todaySeconds
        let beforeTotalSeconds = app.totalSeconds
        NSLog("[ExtensionPersistence] 🔍 DIAGNOSTIC: Recording usage for \(app.displayName)")
        NSLog("[ExtensionPersistence] 🔍 DIAGNOSTIC: Before: todaySeconds=\(beforeTodaySeconds)s, totalSeconds=\(beforeTotalSeconds)s")
        NSLog("[ExtensionPersistence] 🔍 DIAGNOSTIC: Adding: \(additionalSeconds)s")
        #endif

        app.totalSeconds += additionalSeconds
        app.earnedPoints += earnedPointsThisInterval
        app.todaySeconds += additionalSeconds
        app.todayPoints += earnedPointsThisInterval
        app.lastUpdated = now

        apps[logicalID] = app

        // Save to v3 storage key (token archive-based)
        if let encoded = try? JSONEncoder().encode(apps) {
            defaults.set(encoded, forKey: "persistedApps_v3")
            defaults.synchronize()

            #if DEBUG
            NSLog("[ExtensionPersistence] 🔍 DIAGNOSTIC: After: todaySeconds=\(app.todaySeconds)s, totalSeconds=\(app.totalSeconds)s, timestamp=\(Date())")
            #endif

            NSLog("[ExtensionPersistence] ✅ Recorded \(additionalSeconds)s for '\(displayName)'")
            NSLog("[ExtensionPersistence] Today: \(app.todaySeconds)s (\(app.todayPoints)pts), Total: \(app.totalSeconds)s (\(app.earnedPoints)pts)")
        }
    }

    private nonisolated func loadAllApps() -> [LogicalAppID: PersistedApp] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: "persistedApps_v3"),
              let apps = try? JSONDecoder().decode([LogicalAppID: PersistedApp].self, from: data) else {
            return [:]
        }
        return apps
    }
}

private enum ExtensionMonitorError: LocalizedError {
    case appGroupUnavailable
    case eventMappingMissing

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group is unavailable."
        case .eventMappingMissing:
            return "Missing event mapping."
        }
    }
}

private struct EventMapping {
    let logicalID: String
    let displayName: String
    let category: String
    let rewardPointsPerMinute: Int
    let thresholdSeconds: Int
    let incrementSeconds: Int
}

private struct ExtensionErrorEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let eventName: String
    let success: Bool
    let errorDescription: String?
    let memoryUsageMB: Double
    let action: String

    init(eventName: String, success: Bool, errorDescription: String?, memoryUsageMB: Double, action: String) {
        self.id = UUID()
        self.timestamp = Date().timeIntervalSince1970
        self.eventName = eventName
        self.success = success
        self.errorDescription = errorDescription
        self.memoryUsageMB = memoryUsageMB
        self.action = action
    }
}

private enum ExtensionErrorLog {
    private static let logKey = "extension_error_log"
    private static let appGroupIdentifier = "group.com.screentimerewards.shared"
    private static let maxEntries = 100

    static func append(_ entry: ExtensionErrorEntry) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[ExtensionErrorLog] WARNING: Cannot access app group to log error")
            return
        }
        var entries = readAll()
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        if let encoded = try? JSONEncoder().encode(entries) {
            defaults.set(encoded, forKey: logKey)
        }
    }

    static func readAll() -> [ExtensionErrorEntry] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: logKey),
              let decoded = try? JSONDecoder().decode([ExtensionErrorEntry].self, from: data) else {
            return []
        }
        return decoded
    }
}

final class ScreenTimeActivityMonitorExtension: DeviceActivityMonitor {
    // App Group identifier - must match in both main app and extension
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let phantomCooldownSeconds: TimeInterval = 55

    // Shared persistence helper
    private let usagePersistence = ExtensionUsagePersistence()
    private var heartbeatTimer: DispatchSourceTimer?

    override nonisolated init() {
        super.init()
        NSLog("[EXTENSION] ========================================")
        NSLog("[EXTENSION] Extension initialized at \(Date())")
        NSLog("[EXTENSION] ========================================")

        // Write initialization flag for diagnostic purposes
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(Date().timeIntervalSince1970, forKey: "extension_initialized")
            defaults.set(true, forKey: "extension_initialized_flag")
            defaults.synchronize()
            NSLog("[EXTENSION] ✅ Wrote initialization flag to app group")
        } else {
            NSLog("[EXTENSION] ❌ CRITICAL: Cannot access app group in init!")
        }
    }

    deinit {
        heartbeatTimer?.cancel()
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

    private nonisolated func startHeartbeatTimer() {
        stopHeartbeatTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 60)
        timer.setEventHandler { [weak self] in
            self?.writeHeartbeat()
        }
        timer.resume()
        heartbeatTimer = timer
        writeHeartbeat()
    }

    private nonisolated func stopHeartbeatTimer() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private nonisolated func writeHeartbeat() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        sharedDefaults.set(Date().timeIntervalSince1970, forKey: "extension_heartbeat")
        sharedDefaults.set(getMemoryUsageMB(), forKey: "extension_memory_mb")
        sharedDefaults.synchronize()
    }

    private nonisolated func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        NSLog("[EXTENSION] 🟢 intervalDidStart for activity: \(activity.rawValue)")
        startHeartbeatTimer()
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
        stopHeartbeatTimer()
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
        NSLog("[EXTENSION] ⏰ eventDidReachThreshold FIRED!")
        NSLog("[EXTENSION]   Event: \(event.rawValue)")
        NSLog("[EXTENSION]   Activity: \(activity.rawValue)")
        #endif

        writeHeartbeat()
        let memoryMB = getMemoryUsageMB()
        #if DEBUG
        NSLog("[EXTENSION]   Memory: \(String(format: "%.1f", memoryMB)) MB")
        #endif

        let currentGeneration = readCurrentRestartGeneration()
        if let eventGeneration = extractGeneration(from: event.rawValue),
           currentGeneration > 0,
           (eventGeneration < currentGeneration - 1 || eventGeneration > currentGeneration) {
            NSLog("[EXTENSION] ⚠️ Skipping stale event \(event.rawValue) (generation \(eventGeneration)) - current generation \(currentGeneration)")
            ExtensionErrorLog.append(ExtensionErrorEntry(
                eventName: event.rawValue,
                success: false,
                errorDescription: "Stale generation \(eventGeneration), current \(currentGeneration)",
                memoryUsageMB: memoryMB,
                action: "stale_generation"
            ))
            return
        }

        if checkMemoryPressure(currentMemoryMB: memoryMB) {
            NSLog("[EXTENSION] ⚠️ HIGH MEMORY PRESSURE - using minimal path")
            let didRecordMinimal = recordUsageMinimal(event, activity: activity, memoryUsageMB: memoryMB)
            if didRecordMinimal {
                ExtensionErrorLog.append(ExtensionErrorEntry(
                    eventName: event.rawValue,
                    success: true,
                    errorDescription: "High memory pressure, minimal path used",
                    memoryUsageMB: memoryMB,
                    action: "memory_warning"
                ))
            } else {
                ExtensionErrorLog.append(ExtensionErrorEntry(
                    eventName: event.rawValue,
                    success: false,
                    errorDescription: "Minimal path skipped due to cooldown",
                    memoryUsageMB: memoryMB,
                    action: "cooldown_skip"
                ))
            }
            postNotification("com.screentimerewards.eventDidReachThreshold", event: event, activity: activity)
            return
        }

        var didRecordUsage = false
        do {
            didRecordUsage = try recordUsageFromEvent(event)
            if didRecordUsage {
                #if DEBUG
                NSLog("[EXTENSION] ✅ Successfully recorded usage for event: \(event.rawValue)")
                #endif
                ExtensionErrorLog.append(ExtensionErrorEntry(
                    eventName: event.rawValue,
                    success: true,
                    errorDescription: nil,
                    memoryUsageMB: memoryMB,
                    action: "record_usage"
                ))
            } else {
                ExtensionErrorLog.append(ExtensionErrorEntry(
                    eventName: event.rawValue,
                    success: false,
                    errorDescription: "Skipped due to cooldown",
                    memoryUsageMB: memoryMB,
                    action: "cooldown_skip"
                ))
            }
        } catch {
            NSLog("[EXTENSION] ❌ FAILED to record usage: \(error.localizedDescription)")
            ExtensionErrorLog.append(ExtensionErrorEntry(
                eventName: event.rawValue,
                success: false,
                errorDescription: error.localizedDescription,
                memoryUsageMB: memoryMB,
                action: "record_usage"
            ))
            #if DEBUG
            NSLog("[EXTENSION] ❌ Error details: \(error)")
            fatalError("[EXTENSION] Recording failed - check event mappings")
            #endif
        }

        if didRecordUsage {
            do {
                try postUsageNotification()
                ExtensionErrorLog.append(ExtensionErrorEntry(
                    eventName: event.rawValue,
                    success: true,
                    errorDescription: nil,
                    memoryUsageMB: memoryMB,
                    action: "post_notification"
                ))
            } catch {
                ExtensionErrorLog.append(ExtensionErrorEntry(
                    eventName: event.rawValue,
                    success: false,
                    errorDescription: error.localizedDescription,
                    memoryUsageMB: memoryMB,
                    action: "post_notification"
                ))
            }
        }

        postNotification("com.screentimerewards.eventDidReachThreshold", event: event, activity: activity)
    }

    private nonisolated func lastRecordedKey(for logicalID: String) -> String {
        "lastRecorded_\(logicalID)"
    }

    private nonisolated func shouldSkipRecording(for mapping: EventMapping,
                                                 defaults: UserDefaults,
                                                 now: TimeInterval) -> (skip: Bool, delta: TimeInterval, hasLastRecord: Bool) {
        let key = lastRecordedKey(for: mapping.logicalID)
        let lastRecorded = defaults.double(forKey: key)
        let timeSinceLast = now - lastRecorded
        let shouldSkip = lastRecorded > 0 && timeSinceLast < phantomCooldownSeconds
        return (shouldSkip, timeSinceLast, lastRecorded > 0)
    }

    /// Record usage directly to shared storage from extension
    private nonisolated func recordUsageFromEvent(_ event: DeviceActivityEvent.Name) throws -> Bool {
        NSLog("[EXTENSION] 📝 Reading event mapping for: \(event.rawValue)")
        let mapping = try readEventMapping(for: event)

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[EXTENSION] ❌ Cannot access app group for timestamp guard")
            throw ExtensionMonitorError.appGroupUnavailable
        }

        let now = Date().timeIntervalSince1970
        let (shouldSkip, timeSinceLast, hasLastRecord) = shouldSkipRecording(for: mapping, defaults: defaults, now: now)

        if shouldSkip {
            NSLog("[EXTENSION] ⏭️ SKIPPING \(mapping.displayName) - last recorded \(Int(timeSinceLast))s ago (< \(Int(phantomCooldownSeconds))s cooldown)")
            NSLog("[EXTENSION] This is a phantom threshold fire from DeviceActivity's cumulative tracking")
            return false
        }

        NSLog("[EXTENSION] 📝 Recording usage for \(mapping.displayName)")
        if hasLastRecord {
            NSLog("[EXTENSION]   Last recorded: \(Int(timeSinceLast))s ago")
        } else {
            NSLog("[EXTENSION]   Last recorded: never")
        }
        NSLog("[EXTENSION]   Logical ID: \(mapping.logicalID)")
        NSLog("[EXTENSION]   Category: \(mapping.category)")
        NSLog("[EXTENSION]   Threshold: \(mapping.thresholdSeconds)s cumulative")
        NSLog("[EXTENSION]   Increment: \(mapping.incrementSeconds)s")
        NSLog("[EXTENSION]   Reward points/min: \(mapping.rewardPointsPerMinute)")

        usagePersistence.recordUsage(
            logicalID: mapping.logicalID,
            additionalSeconds: mapping.incrementSeconds,
            rewardPointsPerMinute: mapping.rewardPointsPerMinute,
            displayName: mapping.displayName,
            category: mapping.category
        )

        defaults.set(now, forKey: lastRecordedKey(for: mapping.logicalID))
        defaults.synchronize()

        NSLog("[EXTENSION] ✅ Usage recorded to persistent storage!")
        return true
    }

    override nonisolated func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeActivityExtension] eventWillReachThresholdWarning:")
        print("[ScreenTimeActivityExtension]   Event: \(event.rawValue)")
        print("[ScreenTimeActivityExtension]   Activity: \(activity.rawValue)")
        #endif
        postNotification("com.screentimerewards.eventWillReachThreshold", event: event, activity: activity)
    }

    private nonisolated func recordUsageMinimal(_ event: DeviceActivityEvent.Name,
                                                activity: DeviceActivityName,
                                                memoryUsageMB: Double) -> Bool {
        guard let mapping = try? readEventMapping(for: event) else {
            NSLog("[EXTENSION] ❌ MINIMAL PATH: Cannot read event mapping for \(event.rawValue)")
            #if DEBUG
            fatalError("[EXTENSION] Minimal path failed - no event mapping")
            #endif
            return false
        }

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[EXTENSION] ❌ MINIMAL PATH: Cannot access app group for timestamp guard")
            return false
        }

        let now = Date().timeIntervalSince1970
        let (shouldSkip, timeSinceLast, hasLastRecord) = shouldSkipRecording(for: mapping, defaults: defaults, now: now)
        if shouldSkip {
            NSLog("[EXTENSION] ⏭️ MINIMAL PATH SKIP \(mapping.displayName) - last recorded \(Int(timeSinceLast))s ago (< \(Int(phantomCooldownSeconds))s cooldown)")
            return false
        }

        usagePersistence.recordUsage(
            logicalID: mapping.logicalID,
            additionalSeconds: mapping.incrementSeconds,
            rewardPointsPerMinute: mapping.rewardPointsPerMinute,
            displayName: mapping.displayName,
            category: mapping.category
        )

        defaults.set(now, forKey: lastRecordedKey(for: mapping.logicalID))
        defaults.synchronize()

        ExtensionErrorLog.append(ExtensionErrorEntry(
            eventName: event.rawValue,
            success: true,
            errorDescription: "Minimal recording path",
            memoryUsageMB: memoryUsageMB,
            action: "minimal_record"
        ))

        try? postUsageNotification()
        return true
    }

    private nonisolated func readEventMapping(for event: DeviceActivityEvent.Name) throws -> EventMapping {
        NSLog("[EXTENSION] 🔍 Reading event mapping for: \(event.rawValue)")

        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[EXTENSION] ❌ FATAL: Cannot access app group for event mappings")
            throw ExtensionMonitorError.appGroupUnavailable
        }

        guard let data = sharedDefaults.data(forKey: "eventMappings") else {
            NSLog("[EXTENSION] ❌ FATAL: No 'eventMappings' data found in app group")
            NSLog("[EXTENSION] This means the main app never saved event mappings!")
            throw ExtensionMonitorError.eventMappingMissing
        }

        guard let mappings = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            NSLog("[EXTENSION] ❌ FATAL: Cannot deserialize eventMappings JSON")
            throw ExtensionMonitorError.eventMappingMissing
        }

        NSLog("[EXTENSION] 📋 Found \(mappings.count) event mappings in storage")
        NSLog("[EXTENSION] 📋 Available events: \(mappings.keys.joined(separator: ", "))")

        guard let eventInfo = mappings[event.rawValue] else {
            NSLog("[EXTENSION] ❌ FATAL: No mapping found for event '\(event.rawValue)'")
            NSLog("[EXTENSION] Event mismatch - main app created different event names!")
            throw ExtensionMonitorError.eventMappingMissing
        }

        guard let logicalID = eventInfo["logicalID"] as? String,
              let displayName = eventInfo["displayName"] as? String,
              let rewardPointsPerMinute = eventInfo["rewardPoints"] as? Int,
              let thresholdSeconds = eventInfo["thresholdSeconds"] as? Int else {
            NSLog("[EXTENSION] ❌ FATAL: Event mapping incomplete for '\(event.rawValue)'")
            NSLog("[EXTENSION] Event info: \(eventInfo)")
            throw ExtensionMonitorError.eventMappingMissing
        }

        let incrementSeconds = eventInfo["incrementSeconds"] as? Int ?? thresholdSeconds
        let category = (eventInfo["category"] as? String) ?? "Learning"
        NSLog("[EXTENSION] ✅ Successfully read mapping: \(displayName) (\(logicalID))")

        return EventMapping(
            logicalID: logicalID,
            displayName: displayName,
            category: category,
            rewardPointsPerMinute: rewardPointsPerMinute,
            thresholdSeconds: thresholdSeconds,
            incrementSeconds: incrementSeconds
        )
    }

    private nonisolated func postUsageNotification() throws {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw ExtensionMonitorError.appGroupUnavailable
        }

        let currentSequence = max(
            sharedDefaults.integer(forKey: "usageNotificationSequence"),
            sharedDefaults.integer(forKey: "notification_sequence")
        )
        let nextSequence = currentSequence + 1
        sharedDefaults.set(nextSequence, forKey: "usageNotificationSequence")
        sharedDefaults.set(nextSequence, forKey: "notification_sequence")
        sharedDefaults.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.screentimerewards.usageRecorded" as CFString),
            nil,
            nil,
            true
        )
    }

    private nonisolated func checkMemoryPressure(currentMemoryMB: Double) -> Bool {
        currentMemoryMB > 5.0
    }

    private nonisolated func readCurrentRestartGeneration() -> Int {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0
        }
        return sharedDefaults.integer(forKey: "currentRestartGeneration")
    }

    private nonisolated func extractGeneration(from eventName: String) -> Int? {
        guard let range = eventName.range(of: ".gen.") else {
            return nil
        }
        let suffix = eventName[range.upperBound...]
        return Int(suffix)
    }
}
