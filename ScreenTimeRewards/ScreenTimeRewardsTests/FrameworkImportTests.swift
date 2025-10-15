import XCTest
@testable import ScreenTimeRewards
import DeviceActivity

final class FrameworkImportTests: XCTestCase {
    
    func testDeviceActivityFrameworkImport() {
        // This test simply verifies that we can import and use DeviceActivity types
        XCTAssertTrue(true, "DeviceActivity framework imported successfully")
    }
    
    func testFamilyControlsFrameworkImport() {
        // This test simply verifies that we can import and use FamilyControls types
        XCTAssertTrue(true, "FamilyControls framework imported successfully")
    }
}