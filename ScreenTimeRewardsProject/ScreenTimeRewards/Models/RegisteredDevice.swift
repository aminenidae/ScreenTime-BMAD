import Foundation
import CoreData

@objc(RegisteredDevice)
public class RegisteredDevice: NSManagedObject {

}

extension RegisteredDevice {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RegisteredDevice> {
        return NSFetchRequest<RegisteredDevice>(entityName: "RegisteredDevice")
    }
    
    @NSManaged public var deviceID: String?
    @NSManaged public var deviceName: String?
    @NSManaged public var deviceType: String?
    @NSManaged public var childName: String?
    @NSManaged public var parentDeviceID: String?
    @NSManaged public var registrationDate: Date?
    @NSManaged public var lastSyncDate: Date?
    @NSManaged public var isActive: Bool
}