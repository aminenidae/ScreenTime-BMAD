import XCTest
@testable import ScreenTimeRewards

@MainActor
class DevicePairingServiceTest: XCTestCase {
    
    func testDevicePairingServiceInitialization() {
        // Test that the singleton can be accessed
        let service = DevicePairingService.shared
        XCTAssertNotNil(service, "DevicePairingService should be initializable")
    }
    
    func testPairingStatus() {
        let service = DevicePairingService.shared
        
        // Initially should not be paired
        XCTAssertFalse(service.isPaired(), "Device should not be paired initially")
        
        // Test unpairing (should not crash even if not paired)
        service.unpairDevice()
    }
    
    func testPairingPayloadStructure() {
        // Test that we can create a pairing payload
        let payload = DevicePairingService.PairingPayload(
            shareURL: "https://example.com/share",
            parentDeviceID: "parent-device-id",
            verificationToken: "verification-token",
            sharedZoneID: "test-zone-id",
            timestamp: Date()
        )
        
        XCTAssertEqual(payload.shareURL, "https://example.com/share")
        XCTAssertEqual(payload.parentDeviceID, "parent-device-id")
        XCTAssertEqual(payload.verificationToken, "verification-token")
    }
    
    func testObservableObjectConformance() {
        // Test that the service conforms to ObservableObject
        let service = DevicePairingService.shared
        XCTAssertFalse(service.isPairing, "Initial pairing status should be false")
    }
}