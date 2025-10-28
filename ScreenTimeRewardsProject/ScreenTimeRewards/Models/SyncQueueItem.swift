import Foundation
import CoreData

@objc(SyncQueueItem)
public class SyncQueueItem: NSManagedObject {

}

extension SyncQueueItem {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncQueueItem> {
        return NSFetchRequest<SyncQueueItem>(entityName: "SyncQueueItem")
    }
    
    @NSManaged public var queueID: String?
    @NSManaged public var operation: String?
    @NSManaged public var payloadJSON: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var retryCount: Int16
    @NSManaged public var lastAttempt: Date?
    @NSManaged public var status: String?
}