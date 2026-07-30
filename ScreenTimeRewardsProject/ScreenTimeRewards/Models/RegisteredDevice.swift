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

    /// Predicate for "the child devices in this parent's local store".
    ///
    /// Deliberately does NOT compare `parentDeviceID` against the current parent's
    /// deviceID. That ID is regenerated on every parent reinstall (DeviceModeManager
    /// "PHASE 3"), while each child row keeps whatever parent ID existed when that child
    /// paired — so the comparison matches nothing after a reinstall, and every caller
    /// silently sees zero children while CloudKit correctly reports several. Same root
    /// cause as the family record, the server parent-slot list, the child-device lookup,
    /// the child's paired-parent list and command delivery.
    ///
    /// Filtering on `deviceType` alone is correct here: a parent's Core Data mirrors only
    /// its own CloudKit zones, so every child row present is one of its own children. The
    /// deviceID exclusion covers a device that was previously set up as a child and still
    /// carries its own stale row.
    ///
    /// Defined once because five call sites had this predicate copy-pasted
    /// (localPairedChildCount, populateFromLocalCache, pruneStaleLocalChildDevices,
    /// knownChildZoneNames, synthesizeLinkedChildDevicesFromLocal) and would otherwise
    /// need fixing — and drift — independently.
    static func childrenOfThisParentPredicate(excludingDeviceID ownDeviceID: String) -> NSPredicate {
        NSPredicate(format: "deviceType == %@ AND deviceID != %@", "child", ownDeviceID)
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
    @NSManaged public var subscriptionStatus: String?
    @NSManaged public var subscriptionExpiryDate: Date?
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
                return String(localized: "Connected")
            case .inactive(let hours):
                if hours >= 48 {
                    return String(localized: "Last seen \(hours / 24) days ago")
                }
                return String(localized: "Last seen \(hours) hours ago")
            case .stale:
                return String(localized: "Disconnected")
            case .unknown:
                return String(localized: "Unknown")
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
