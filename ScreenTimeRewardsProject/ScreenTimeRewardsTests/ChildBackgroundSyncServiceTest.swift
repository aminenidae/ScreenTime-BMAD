import XCTest
@testable import ScreenTimeRewards

@MainActor
class ChildBackgroundSyncServiceTest: XCTestCase {
    
    func testChildBackgroundSyncServiceInitialization() {
        // Test that the singleton can be accessed
        let service = ChildBackgroundSyncService.shared
        XCTAssertNotNil(service, "ChildBackgroundSyncService should be initializable")
    }
    
    func testRegisterBackgroundTasks() {
        // Test that background tasks can be registered without crashing
        let service = ChildBackgroundSyncService.shared
        XCTAssertNoThrow(service.registerBackgroundTasks(), "Registering background tasks should not throw")
    }
    
    func testScheduleUsageUpload() {
        // Test that usage upload scheduling works without crashing
        let service = ChildBackgroundSyncService.shared
        XCTAssertNoThrow(service.scheduleUsageUpload(), "Scheduling usage upload should not throw")
    }
    
    func testScheduleConfigCheck() {
        // Test that config check scheduling works without crashing
        let service = ChildBackgroundSyncService.shared
        XCTAssertNoThrow(service.scheduleConfigCheck(), "Scheduling config check should not throw")
    }
}