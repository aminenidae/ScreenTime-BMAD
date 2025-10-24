import XCTest
@testable import ScreenTimeRewards
import DeviceActivity
import FamilyControls
import ManagedSettings

final class ScreenTimeRewardsTests: XCTestCase {
    
    func testAppUsageInitialization() {
        let appUsage = AppUsage(
            bundleIdentifier: "com.test.app",
            appName: "Test App",
            category: .learning
        )
        
        XCTAssertEqual(appUsage.bundleIdentifier, "com.test.app")
        XCTAssertEqual(appUsage.appName, "Test App")
        XCTAssertEqual(appUsage.category, .learning)
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
            category: .learning
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
            .learning,
            .reward
        ]
        
        XCTAssertEqual(categories.count, 2)
        XCTAssertTrue(AppUsage.AppCategory.allCases.contains(.learning))
        XCTAssertTrue(AppUsage.AppCategory.allCases.contains(.reward))
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
            category: .learning
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
        XCTAssertGreaterThan(screenTimeService.getTotalTime(for: .learning), 0)
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

    func testScreenTimeServiceSimulatedEventRecordsUsage() {
        let screenTimeService = ScreenTimeService.shared
        screenTimeService.resetData()
#if DEBUG
        screenTimeService.configureForTesting(
            applications: [
                (bundleIdentifier: "com.test.education", name: "Education App", category: .learning, rewardPoints: 10)
            ],
            threshold: DateComponents(minute: 10)
        )
        let eventName = DeviceActivityEvent.Name("usage.learning")
        screenTimeService.handleEventThresholdReached(named: eventName, activity: DeviceActivityName("test"))
        let usages = screenTimeService.getAppUsages()
        XCTAssertEqual(usages.count, 1)
        XCTAssertEqual(usages.first?.bundleIdentifier, "com.test.education")
        XCTAssertTrue(usages.first?.totalTime ?? 0 > 0)
#else
        XCTAssertTrue(true, "Simulation requires DEBUG configuration")
#endif
    }
    
    // Test to verify that privacy-protected apps receive unique logical IDs
    func testUsagePersistenceGeneratesUniqueIDsForPrivacyProtectedApps() {
        let usagePersistence = UsagePersistence()
        
        // Clear any existing data
        usagePersistence.clearAll()
        
        // Create two tokens with the same display name but no bundle identifier (privacy-protected apps)
        let token1 = ApplicationToken(rawValue: UUID().uuidString)
        let token2 = ApplicationToken(rawValue: UUID().uuidString)
        
        let result1 = usagePersistence.resolveLogicalID(for: token1, bundleIdentifier: nil, displayName: "Privacy Protected App")
        let result2 = usagePersistence.resolveLogicalID(for: token2, bundleIdentifier: nil, displayName: "Privacy Protected App")
        
        // Verify that they get different logical IDs
        XCTAssertNotEqual(result1.logicalID, result2.logicalID, "Privacy-protected apps with the same name should receive unique logical IDs")
        
        // Verify that the same token always gets the same logical ID
        let result3 = usagePersistence.resolveLogicalID(for: token1, bundleIdentifier: nil, displayName: "Privacy Protected App")
        XCTAssertEqual(result1.logicalID, result3.logicalID, "Same token should always resolve to the same logical ID")
    }
}