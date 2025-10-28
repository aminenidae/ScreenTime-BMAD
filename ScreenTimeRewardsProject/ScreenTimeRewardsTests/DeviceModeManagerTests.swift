import XCTest
@testable import ScreenTimeRewards

final class DeviceModeManagerTests: XCTestCase {
    
    func testDeviceModeManagerInitialization() {
        let modeManager = DeviceModeManager.shared
        
        // Device ID should be a valid UUID string
        XCTAssertNotNil(UUID(uuidString: modeManager.deviceID))
        
        // Device name should not be empty
        XCTAssertFalse(modeManager.deviceName.isEmpty)
        
        // Initially, currentMode should be nil (needs device selection)
        XCTAssertNil(modeManager.currentMode)
        XCTAssertTrue(modeManager.needsDeviceSelection)
        XCTAssertFalse(modeManager.isParentDevice)
        XCTAssertFalse(modeManager.isChildDevice)
    }
    
    func testDeviceModeManagerSetMode() {
        let modeManager = DeviceModeManager.shared
        
        // Set to parent mode
        modeManager.setDeviceMode(.parentDevice)
        
        XCTAssertEqual(modeManager.currentMode, .parentDevice)
        XCTAssertTrue(modeManager.isParentDevice)
        XCTAssertFalse(modeManager.isChildDevice)
        XCTAssertFalse(modeManager.needsDeviceSelection)
        
        // Set to child mode
        modeManager.setDeviceMode(.childDevice)
        
        XCTAssertEqual(modeManager.currentMode, .childDevice)
        XCTAssertTrue(modeManager.isChildDevice)
        XCTAssertFalse(modeManager.isParentDevice)
        XCTAssertFalse(modeManager.needsDeviceSelection)
    }
    
    func testDeviceModeManagerReset() {
        let modeManager = DeviceModeManager.shared
        
        // Set a mode first
        modeManager.setDeviceMode(.parentDevice)
        XCTAssertNotNil(modeManager.currentMode)
        
        // Reset the mode
        modeManager.resetDeviceMode()
        
        // Should be back to needing device selection
        XCTAssertNil(modeManager.currentMode)
        XCTAssertTrue(modeManager.needsDeviceSelection)
        XCTAssertFalse(modeManager.isParentDevice)
        XCTAssertFalse(modeManager.isChildDevice)
    }
    
    func testDeviceModeManagerDeviceIDPersistence() {
        let firstManager = DeviceModeManager.shared
        let firstDeviceID = firstManager.deviceID
        
        // Create a new instance (simulating app restart)
        let secondManager = DeviceModeManager()
        let secondDeviceID = secondManager.deviceID
        
        // Device ID should be consistent across instances
        XCTAssertEqual(firstDeviceID, secondDeviceID)
    }
    
    func testDeviceModeManagerDeviceNamePersistence() {
        let modeManager = DeviceModeManager.shared
        let originalName = modeManager.deviceName
        
        // Set a custom device name
        let customName = "Test Device"
        modeManager.setDeviceMode(.parentDevice, deviceName: customName)
        
        XCTAssertEqual(modeManager.deviceName, customName)
        
        // Create a new instance to test persistence
        let newManager = DeviceModeManager()
        XCTAssertEqual(newManager.deviceName, customName)
    }
}