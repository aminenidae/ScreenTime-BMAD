import Foundation
import CoreData

@objc(UsageRecord)
public class UsageRecord: NSManagedObject {

}

extension UsageRecord {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UsageRecord> {
        return NSFetchRequest<UsageRecord>(entityName: "UsageRecord")
    }
    
    @NSManaged public var recordID: String?
    @NSManaged public var logicalID: String?
    @NSManaged public var displayName: String?
    @NSManaged public var sessionStart: Date?
    @NSManaged public var sessionEnd: Date?
    @NSManaged public var totalSeconds: Int32
    @NSManaged public var earnedPoints: Int32
    @NSManaged public var category: String?
    @NSManaged public var deviceID: String?
    @NSManaged public var syncTimestamp: Date?
    @NSManaged public var isSynced: Bool
}