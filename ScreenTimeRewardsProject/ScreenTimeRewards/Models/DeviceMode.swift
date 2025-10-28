import Foundation

enum DeviceMode: String, Codable {
    case parentDevice
    case childDevice
    
    var displayName: String {
        switch self {
        case .parentDevice:
            return "Parent Device"
        case .childDevice:
            return "Child Device"
        }
    }
    
    var description: String {
        switch self {
        case .parentDevice:
            return "Monitor and configure child devices remotely"
        case .childDevice:
            return "Run monitoring on this device with parental controls"
        }
    }
    
    var requiresScreenTimeAuth: Bool {
        switch self {
        case .parentDevice:
            return false  // No local monitoring
        case .childDevice:
            return true   // Full ScreenTime API access needed
        }
    }
}