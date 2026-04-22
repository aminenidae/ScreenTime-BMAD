import Foundation
import CloudKit

/// Lightweight CloudKit sync for DeviceActivity extension
/// Syncs usage data to parent's CloudKit zone for real-time updates
final class ExtensionCloudKitSync {
    static let shared = ExtensionCloudKitSync()

    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let container = CKContainer(identifier: "iCloud.com.i6dev.ScreenTimeRewards")

    private init() {}

    /// Sync current usage data to CloudKit for parent device visibility
    /// Called from extension after each usage recording
    func syncUsageToParent(defaults: UserDefaults) {
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

        if lastSlotToken == currentSlotToken {
            debugLog("CLOUDKIT_SYNC: ⏩ Slot \(currentSlotToken) already synced", defaults: defaults)
            return
        }

        // Get child device ID from shared defaults
        guard let childDeviceID = defaults.string(forKey: "ext_deviceID"),
              !childDeviceID.isEmpty else {
            debugLog("CLOUDKIT_SYNC: No child device ID found", defaults: defaults)
            return
        }

        // Get zone name for this child
        let zoneName = "ChildMonitoring_\(childDeviceID)"
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        // Collect all app usage data from shared defaults
        let usageData = collectUsageData(defaults: defaults)

        guard !usageData.isEmpty else {
            debugLog("CLOUDKIT_SYNC: No usage data to sync", defaults: defaults)
            return
        }

        debugLog("CLOUDKIT_SYNC: Syncing \(usageData.count) apps to zone \(zoneName)", defaults: defaults)

        // Create/update UsageRecord records for each app
        let database = container.privateCloudDatabase

        for (appID, data) in usageData {
            let recordID = CKRecord.ID(recordName: "Usage_\(appID)", zoneID: zoneID)
            let record = CKRecord(recordType: "UsageRecord", recordID: recordID)

            record["appLogicalID"] = appID
            record["todaySeconds"] = data.todaySeconds
            record["totalSeconds"] = data.totalSeconds
            record["lastUpdated"] = Date()
            record["childDeviceID"] = childDeviceID

            // Add hourly data if available (as JSON string for CloudKit compatibility)
            if let hourlyData = data.hourlyData,
               let jsonData = try? JSONSerialization.data(withJSONObject: hourlyData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                record["hourlyData"] = jsonString
            }

            // Use save with ifServerRecordUnchanged policy for conflict resolution
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility

            operation.modifyRecordsResultBlock = { [weak self] result in
                switch result {
                case .success:
                    self?.debugLog("CLOUDKIT_SYNC: ✅ Synced \(appID.prefix(12))...", defaults: defaults)
                case .failure(let error):
                    self?.debugLog("CLOUDKIT_SYNC: ❌ Failed \(appID.prefix(12))... - \(error.localizedDescription)", defaults: defaults)
                }
            }

            database.add(operation)
        }

        // Mark this slot as synced for today
        defaults.set(currentSlotToken, forKey: "ext_cloudkit_last_slot_token")
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
