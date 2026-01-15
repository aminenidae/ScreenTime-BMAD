import Foundation
import CoreData

@objc(AppConfiguration)
public class AppConfiguration: NSManagedObject {

}

extension AppConfiguration {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AppConfiguration> {
        return NSFetchRequest<AppConfiguration>(entityName: "AppConfiguration")
    }
    
    @NSManaged public var logicalID: String?
    @NSManaged public var tokenHash: String?
    @NSManaged public var bundleIdentifier: String?
    @NSManaged public var displayName: String?
    @NSManaged public var sfSymbolName: String?
    @NSManaged public var iconURL: String?
    @NSManaged public var appStoreId: Int64
    @NSManaged public var category: String?
    @NSManaged public var pointsPerMinute: Int16
    @NSManaged public var isEnabled: Bool
    @NSManaged public var blockingEnabled: Bool
    @NSManaged public var dateAdded: Date?
    @NSManaged public var lastModified: Date?
    @NSManaged public var deviceID: String?
    @NSManaged public var syncStatus: String?
}