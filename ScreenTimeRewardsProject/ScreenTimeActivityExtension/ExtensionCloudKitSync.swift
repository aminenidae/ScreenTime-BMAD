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
        // Throttle: only sync every 5 minutes to reduce extension CPU/memory pressure
        // Main app already syncs on foreground activation, so extension provides periodic updates
        let lastSync = defaults.double(forKey: "ext_cloudkit_last_sync")
        let timeSinceSync = Date().timeIntervalSince1970 - lastSync
        if timeSinceSync < 300 && lastSync > 0 {
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

        // Update last sync timestamp
        defaults.set(Date().timeIntervalSince1970, forKey: "ext_cloudkit_last_sync")
    }

    /// Collect usage data from shared UserDefaults
    private func collectUsageData(defaults: UserDefaults) -> [String: UsageData] {
        var result: [String: UsageData] = [:]

        let allKeys = defaults.dictionaryRepresentation().keys

        // Find all app IDs by looking for ext_usage keys
        var appIDs = Set<String>()
        for key in allKeys {
            if key.hasPrefix("ext_usage_") && key.hasSuffix("_today") {
                // Extract app ID from "ext_usage_<appID>_today"
                let startIndex = key.index(key.startIndex, offsetBy: 10) // Skip "ext_usage_"
                let endIndex = key.index(key.endIndex, offsetBy: -6) // Remove "_today"
                if startIndex < endIndex {
                    let appID = String(key[startIndex..<endIndex])
                    appIDs.insert(appID)
                }
            }
        }

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

    /// Debug logging to shared UserDefaults
    private func debugLog(_ message: String, defaults: UserDefaults) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)][SYNC] \(message)"

        var log = defaults.string(forKey: "extension_debug_log") ?? ""
        let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
        let trimmedLines = Array(lines.suffix(499))
        log = (trimmedLines + [entry]).joined(separator: "\n")
        defaults.set(log, forKey: "extension_debug_log")
    }
}

// MARK: - Supporting Types

private struct UsageData {
    let todaySeconds: Int
    let totalSeconds: Int
    let hourlyData: [String: Int]?
}
