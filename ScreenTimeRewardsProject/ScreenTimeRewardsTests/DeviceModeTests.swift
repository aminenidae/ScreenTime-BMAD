import XCTest
@testable import ScreenTimeRewards

final class DeviceModeTests: XCTestCase {
    
    func testDeviceModeRawValues() {
        XCTAssertEqual(DeviceMode.parentDevice.rawValue, "parentDevice")
        XCTAssertEqual(DeviceMode.childDevice.rawValue, "childDevice")
    }
    
    func testDeviceModeDisplayName() {
        XCTAssertEqual(DeviceMode.parentDevice.displayName, "Parent Device")
        XCTAssertEqual(DeviceMode.childDevice.displayName, "Child Device")
    }
    
    func testDeviceModeDescription() {
        XCTAssertEqual(DeviceMode.parentDevice.description, "Monitor and configure child devices remotely")
        XCTAssertEqual(DeviceMode.childDevice.description, "Run monitoring on this device with parental controls")
    }
    
    func testDeviceModeRequiresScreenTimeAuth() {
        XCTAssertFalse(DeviceMode.parentDevice.requiresScreenTimeAuth)
        XCTAssertTrue(DeviceMode.childDevice.requiresScreenTimeAuth)
    }
    
    func testDeviceModeCodable() throws {
        let parentMode = DeviceMode.parentDevice
        let childMode = DeviceMode.childDevice
        
        // Encode
        let encoder = JSONEncoder()
        let parentData = try encoder.encode(parentMode)
        let childData = try encoder.encode(childMode)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedParent = try decoder.decode(DeviceMode.self, from: parentData)
        let decodedChild = try decoder.decode(DeviceMode.self, from: childData)
        
        // Verify
        XCTAssertEqual(decodedParent, parentMode)
        XCTAssertEqual(decodedChild, childMode)
    }
    
    func testDeviceModeEquality() {
        XCTAssertEqual(DeviceMode.parentDevice, DeviceMode.parentDevice)
        XCTAssertEqual(DeviceMode.childDevice, DeviceMode.childDevice)
        XCTAssertNotEqual(DeviceMode.parentDevice, DeviceMode.childDevice)
    }
}