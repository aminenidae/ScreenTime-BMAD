import Foundation
import SwiftUI

enum DeviceMode: String, Codable {
    case parentDevice
    case childDevice
    
    var displayName: String {
        switch self {
        case .parentDevice:
            return String(localized: "Parent Device")
        case .childDevice:
            return String(localized: "Child Device")
        }
    }
    
    var description: String {
        switch self {
        case .parentDevice:
            return String(localized: "Monitor and configure child devices remotely")
        case .childDevice:
            return String(localized: "Run monitoring on this device with parental controls")
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