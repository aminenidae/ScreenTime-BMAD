import Foundation
import CoreData

@objc(ConfigurationCommand)
public class ConfigurationCommand: NSManagedObject {

}

extension ConfigurationCommand {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ConfigurationCommand> {
        return NSFetchRequest<ConfigurationCommand>(entityName: "ConfigurationCommand")
    }
    
    @NSManaged public var commandID: String?
    @NSManaged public var targetDeviceID: String?
    @NSManaged public var commandType: String?
    @NSManaged public var payloadJSON: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var executedAt: Date?
    @NSManaged public var status: String?
    @NSManaged public var errorMessage: String?
}