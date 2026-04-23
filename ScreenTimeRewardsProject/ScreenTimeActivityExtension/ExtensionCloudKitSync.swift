import Foundation
import CloudKit

/// Lightweight CloudKit sync for DeviceActivity extension
/// Syncs usage data to parent's CloudKit zone for real-time updates
final class ExtensionCloudKitSync {
    static let shared = ExtensionCloudKitSync()

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private init() {}

    /// Sync current usage data to CloudKit for parent device visibility
    /// Called from extension after each usage recording
    func syncUsageToParent(defaults: UserDefaults) {
        debugLog("CLOUDKIT_SYNC: → entry container=\(container.containerIdentifier ?? "nil")", defaults: defaults)

        // 10-slot daily schedule: sync on first threshold event after each slot boundary.
        // Slots: 06:00, 08:00, 10:00, 12:00, 14:00, 16:00, 18:00, 20:00, 22:00, 23:59.
        // Before 06:00 there is no current slot → skip (kids rarely use devices overnight).
        let slotMinutes: [Int] = [360, 480, 600, 720, 840, 960, 1080, 1200, 1320, 1439]
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minutesSinceMidnight = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        guard let currentSlotMin = slotMinutes.last(where: { $0 <= minutesSinceMidnight }) else {
            debugLog("CLOUDKIT_SYNC: ⏩ Before first slot (06:00) — skipping", defaults: defaults)
            return
        }

        let dateStr = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        let currentSlotToken = "\(dateStr):\(currentSlotMin)"
        let lastSlotToken = defaults.string(forKey: "ext_cloudkit_last_slot_token") ?? ""

        debugLog("CLOUDKIT_SYNC: slot decision min=\(minutesSinceMidnight) currentSlot=\(currentSlotMin) lastToken=\(lastSlotToken) currentToken=\(currentSlotToken)", defaults: defaults)

        if lastSlotToken == currentSlotToken {
            debugLog("CLOUDKIT_SYNC: ⏩ Slot \(currentSlotToken) already synced", defaults: defaults)
            return
        }

        // Parent zone info is written to the App Group by
        // DevicePairingService.syncParentZoneInfoToAppGroup() after pairing.
        // Bail out cleanly if the main app hasn't migrated yet.
        let enabled = defaults.bool(forKey: "ext_parentSyncEnabled")
        let rawZone = defaults.string(forKey: "ext_parentZoneID")
        let rawOwner = defaults.string(forKey: "ext_parentZoneOwner")
        let rawRoot = defaults.string(forKey: "ext_parentRootRecordName")
        let rawChild = defaults.string(forKey: "ext_deviceID")
        debugLog("CLOUDKIT_SYNC: appgroup ext_parentSyncEnabled=\(enabled) zone=\(rawZone ?? "nil") owner=\(rawOwner ?? "nil") root=\(rawRoot ?? "nil") childID=\(rawChild ?? "nil")", defaults: defaults)

        guard enabled else {
            debugLog("CLOUDKIT_SYNC: Parent sync not enabled — skipping", defaults: defaults)
            return
        }
        guard let zoneName = rawZone,
              let zoneOwner = rawOwner,
              let rootName = rawRoot,
              !zoneName.isEmpty, !zoneOwner.isEmpty, !rootName.isEmpty else {
            debugLog("CLOUDKIT_SYNC: Parent zone info not yet synced — skipping", defaults: defaults)
            return
        }

        // Child device ID still needed for CD_deviceID field + deterministic record naming.
        guard let childDeviceID = rawChild, !childDeviceID.isEmpty else {
            debugLog("CLOUDKIT_SYNC: No child device ID found", defaults: defaults)
            return
        }

        // Collect all app usage data from shared defaults
        let usageData = collectUsageData(defaults: defaults)

        guard !usageData.isEmpty else {
            debugLog("CLOUDKIT_SYNC: No usage data to sync", defaults: defaults)
            return
        }

        // Mirror the main-app path: shared DB, parent-owned zone, CD_UsageRecord schema,
        // records parented to the shared root so they belong to the share.
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)
        let database = container.sharedCloudDatabase

        debugLog("CLOUDKIT_SYNC: Syncing \(usageData.count) apps to zone \(zoneName)", defaults: defaults)

        let dayKey = Self.dayKeyFormatter.string(from: now)
        let sessionStart = Calendar.current.startOfDay(for: now)

        var recordsToSave: [CKRecord] = []
        recordsToSave.reserveCapacity(usageData.count)
        for (appID, data) in usageData {
            // Deterministic record name → per-slot saves upsert the same record via
            // CKModifyRecordsOperation(.changedKeys). The main-app path uses an async
            // query to dedupe; the extension must stay synchronous.
            let recID = CKRecord.ID(recordName: "UR-\(childDeviceID)-\(appID)-\(dayKey)", zoneID: zoneID)
            let rec = CKRecord(recordType: "CD_UsageRecord", recordID: recID)
            rec.parent = CKRecord.Reference(recordID: rootID, action: .none)

            rec["CD_deviceID"] = childDeviceID as CKRecordValue
            rec["CD_logicalID"] = appID as CKRecordValue
            rec["CD_displayName"] = appID as CKRecordValue
            rec["CD_sessionStart"] = sessionStart as CKRecordValue
            rec["CD_sessionEnd"] = now as CKRecordValue
            rec["CD_totalSeconds"] = Int(data.todaySeconds) as CKRecordValue
            rec["CD_earnedPoints"] = 0 as CKRecordValue
            rec["CD_category"] = "" as CKRecordValue
            rec["CD_syncTimestamp"] = now as CKRecordValue

            recordsToSave.append(rec)
        }

        let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .utility

        let dbScope: String
        switch database.databaseScope {
        case .public: dbScope = "public"
        case .private: dbScope = "private"
        case .shared: dbScope = "shared"
        @unknown default: dbScope = "unknown"
        }
        debugLog("CLOUDKIT_SYNC: prepared \(recordsToSave.count) records → DB=\(dbScope) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) firstRecID=\(recordsToSave.first?.recordID.recordName ?? "nil")", defaults: defaults)

        operation.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                // Only stamp the slot token AFTER a successful write so a failed write
                // retries on the next RECORDED event in the same slot.
                defaults.set(currentSlotToken, forKey: "ext_cloudkit_last_slot_token")
                self?.debugLog("CLOUDKIT_SYNC: ✅ Synced \(recordsToSave.count) apps to slot \(currentSlotToken)", defaults: defaults)
            case .failure(let error):
                let nsErr = error as NSError
                self?.debugLog("CLOUDKIT_SYNC: ❌ Slot \(currentSlotToken) failed code=\(nsErr.code) domain=\(nsErr.domain) desc=\(nsErr.localizedDescription) userInfoKeys=\(nsErr.userInfo.keys.sorted())", defaults: defaults)
            }
        }

        database.add(operation)
    }

    /// Collect usage data from shared UserDefaults
    private func collectUsageData(defaults: UserDefaults) -> [String: UsageData] {
        var result: [String: UsageData] = [:]

        // Use tracked app list instead of materializing all UserDefaults keys
        let appIDs = defaults.stringArray(forKey: "tracked_app_ids") ?? []

        // Collect data for each app
        for appID in appIDs {
            let todaySeconds = defaults.integer(forKey: "ext_usage_\(appID)_today")
            let totalSeconds = defaults.integer(forKey: "ext_usage_\(appID)_total")

            // Collect hourly data
            var hourlyData: [String: Int] = [:]
            for hour in 0..<24 {
                let hourlyKey = "ext_usage_\(appID)_hourly_\(hour)"
                let hourlySeconds = defaults.integer(forKey: hourlyKey)
                if hourlySeconds > 0 {
                    hourlyData["\(hour)"] = hourlySeconds
                }
            }

            result[appID] = UsageData(
                todaySeconds: todaySeconds,
                totalSeconds: totalSeconds,
                hourlyData: hourlyData.isEmpty ? nil : hourlyData
            )
        }

        return result
    }

    /// Cached DateFormatter
    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// O(1) append-only debug log — shares buffer with main extension
    private func debugLog(_ message: String, defaults: UserDefaults) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        let entry = "[\(timestamp)][SYNC] \(message)\n"

        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        log.append(entry)

        // Size-based trim (same thresholds as main extension)
        if log.utf8.count > 50_000 {
            let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            let kept = lines.suffix(200)
            log = kept.joined(separator: "\n") + "\n"
        }

        defaults.set(log, forKey: "extension_debug_log")
    }
}

// MARK: - Supporting Types

private struct UsageData {
    let todaySeconds: Int
    let totalSeconds: Int
    let hourlyData: [String: Int]?
}
