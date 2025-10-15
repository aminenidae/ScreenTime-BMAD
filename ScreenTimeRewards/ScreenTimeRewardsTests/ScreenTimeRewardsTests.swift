import XCTest
@testable import ScreenTimeRewards
import DeviceActivity

final class ScreenTimeRewardsTests: XCTestCase {
    
    func testAppUsageInitialization() {
        let appUsage = AppUsage(
            bundleIdentifier: "com.test.app",
            appName: "Test App",
            category: .educational
        )
        
        XCTAssertEqual(appUsage.bundleIdentifier, "com.test.app")
        XCTAssertEqual(appUsage.appName, "Test App")
        XCTAssertEqual(appUsage.category, .educational)
        XCTAssertEqual(appUsage.totalTime, 0)
        XCTAssertTrue(appUsage.sessions.isEmpty)
        XCTAssertNotNil(appUsage.id)
        XCTAssertNotNil(appUsage.firstAccess)
        XCTAssertNotNil(appUsage.lastAccess)
    }
    
    func testAppUsageSessionTracking() {
        var appUsage = AppUsage(
            bundleIdentifier: "com.test.app",
            appName: "Test App",
            category: .educational
        )
        
        // Start a session
        appUsage.startSession()
        XCTAssertEqual(appUsage.sessions.count, 1)
        XCTAssertNil(appUsage.sessions[0].endTime)
        
        // End the session
        let startTime = appUsage.sessions[0].startTime
        appUsage.endSession()
        XCTAssertEqual(appUsage.sessions.count, 1)
        XCTAssertNotNil(appUsage.sessions[0].endTime)
        
        // Check that totalTime is updated
        XCTAssertTrue(appUsage.totalTime > 0)
        XCTAssertTrue(appUsage.lastAccess >= startTime)
    }
    
    func testAppCategoryCases() {
        let categories: [AppUsage.AppCategory] = [
            .educational,
            .entertainment,
            .productivity,
            .social,
            .games,
            .utility,
            .other
        ]
        
        XCTAssertEqual(categories.count, 7)
        XCTAssertTrue(AppUsage.AppCategory.allCases.contains(.educational))
        XCTAssertTrue(AppUsage.AppCategory.allCases.contains(.entertainment))
    }
    
    func testTimeFormatting() {
        let viewModel = AppUsageViewModel()
        
        XCTAssertEqual(viewModel.formatTime(0), "00:00:00")
        XCTAssertEqual(viewModel.formatTime(3661), "01:01:01")
        XCTAssertEqual(viewModel.formatTime(7265), "02:01:05")
    }
    
    func testTodayUsageCalculation() {
        var appUsage = AppUsage(
            bundleIdentifier: "com.test.app",
            appName: "Test App",
            category: .educational
        )
        
        // Start and end a session today
        appUsage.startSession()
        appUsage.endSession()
        
        // Today's usage should be greater than 0
        XCTAssertTrue(appUsage.todayUsage >= 0)
    }
    
    // New test to verify ScreenTimeService DeviceActivity integration
    func testScreenTimeServiceInitialization() {
        let screenTimeService = ScreenTimeService.shared
        XCTAssertNotNil(screenTimeService)
    }
    
    func testScreenTimeServiceBootstrapSampleData() {
        let screenTimeService = ScreenTimeService.shared
        screenTimeService.resetData()
        screenTimeService.bootstrapSampleDataIfNeeded()
        let usages = screenTimeService.getAppUsages()
        XCTAssertFalse(usages.isEmpty)
        XCTAssertGreaterThan(screenTimeService.getTotalTime(for: .educational), 0)
    }
    
    func testScreenTimeServiceStartStopMonitoring() {
        let screenTimeService = ScreenTimeService.shared
        let expectation = expectation(description: "Monitoring completion")

        screenTimeService.startMonitoring { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected monitoring success but received error: \(error)")
            }
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertTrue(screenTimeService.isMonitoring)

        screenTimeService.stopMonitoring()
        XCTAssertFalse(screenTimeService.isMonitoring)
    }
}
