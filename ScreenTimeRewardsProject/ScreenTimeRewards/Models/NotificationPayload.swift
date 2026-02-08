import Foundation
import CloudKit

/// Payload model for parent push notifications sent via CloudKit
struct ParentNotificationPayload: Codable {
    let notificationID: String
    let childDeviceID: String
    let childDeviceName: String
    let notificationType: ParentNotificationType
    let title: String
    let body: String
    let timestamp: Date
    let metadata: [String: String]?

    enum ParentNotificationType: String, Codable {
        case dailyLimitReached = "daily_limit_reached"
        case learningGoalCompleted = "learning_goal_completed"
        case weeklySummary = "weekly_summary"
        case streakMilestone = "streak_milestone"
        case subscriptionReminder = "subscription_reminder"
    }

    /// Convert to CloudKit record for uploading to parent's shared zone
    func toCKRecord(zoneID: CKRecordZone.ID, rootID: CKRecord.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "PN-\(notificationID)", zoneID: zoneID)
        let record = CKRecord(recordType: "ParentNotification", recordID: recordID)

        record["CD_notificationID"] = notificationID as CKRecordValue
        record["CD_childDeviceID"] = childDeviceID as CKRecordValue
        record["CD_childDeviceName"] = childDeviceName as CKRecordValue
        record["CD_notificationType"] = notificationType.rawValue as CKRecordValue
        record["CD_title"] = title as CKRecordValue
        record["CD_body"] = body as CKRecordValue
        record["CD_timestamp"] = timestamp as CKRecordValue
        record["CD_isRead"] = false as CKRecordValue

        if let metadata = metadata,
           let jsonData = try? JSONEncoder().encode(metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            record["CD_metadataJSON"] = jsonString as CKRecordValue
        }

        // Link to shared root for parent access
        record.parent = CKRecord.Reference(recordID: rootID, action: .none)

        return record
    }

    /// Create from CloudKit record
    static func fromCKRecord(_ record: CKRecord) -> ParentNotificationPayload? {
        guard let notificationID = record["CD_notificationID"] as? String,
              let childDeviceID = record["CD_childDeviceID"] as? String,
              let childDeviceName = record["CD_childDeviceName"] as? String,
              let notificationTypeRaw = record["CD_notificationType"] as? String,
              let notificationType = ParentNotificationType(rawValue: notificationTypeRaw),
              let title = record["CD_title"] as? String,
              let body = record["CD_body"] as? String,
              let timestamp = record["CD_timestamp"] as? Date else {
            return nil
        }

        var metadata: [String: String]? = nil
        if let metadataJSON = record["CD_metadataJSON"] as? String,
           let jsonData = metadataJSON.data(using: .utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: jsonData)
        }

        return ParentNotificationPayload(
            notificationID: notificationID,
            childDeviceID: childDeviceID,
            childDeviceName: childDeviceName,
            notificationType: notificationType,
            title: title,
            body: body,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}
