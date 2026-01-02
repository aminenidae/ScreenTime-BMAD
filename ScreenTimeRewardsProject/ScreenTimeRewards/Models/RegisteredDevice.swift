import Foundation
import CoreData
import ObjectiveC

// MARK: - Associated Object Key for isStale
private var isStaleKey: UInt8 = 0

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
    @NSManaged public var subscriptionTier: String?
    @NSManaged public var sharedZoneID: String?
    @NSManaged public var sharedZoneOwner: String?

    // MARK: - Transient Properties (not persisted)

    /// Indicates if this child's zone no longer exists or is inaccessible
    /// Set during validation, not persisted to CloudKit
    /// Uses Objective-C associated objects since Swift extensions can't have stored properties
    public var isStale: Bool {
        get {
            return objc_getAssociatedObject(self, &isStaleKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &isStaleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Human-readable status for UI display
    public var connectionStatus: ConnectionStatus {
        if isStale {
            return .stale
        } else if let lastSync = lastSyncDate {
            let hoursSinceSync = Date().timeIntervalSince(lastSync) / 3600
            if hoursSinceSync > 24 {
                return .inactive(hours: Int(hoursSinceSync))
            }
            return .active
        }
        return .unknown
    }

    public enum ConnectionStatus {
        case active
        case inactive(hours: Int)
        case stale
        case unknown

        public var displayText: String {
            switch self {
            case .active:
                return "Connected"
            case .inactive(let hours):
                if hours >= 48 {
                    return "Last seen \(hours / 24) days ago"
                }
                return "Last seen \(hours) hours ago"
            case .stale:
                return "Disconnected"
            case .unknown:
                return "Unknown"
            }
        }

        public var isHealthy: Bool {
            switch self {
            case .active:
                return true
            default:
                return false
            }
        }
    }
}
