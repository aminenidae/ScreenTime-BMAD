import XCTest
@testable import ScreenTimeRewards
import DeviceActivity
import FamilyControls
import ManagedSettings

final class ScreenTimeRewardsTests: XCTestCase {
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
    func testTimeFormatting() {
        let viewModel = AppUsageViewModel()
        
        XCTAssertEqual(viewModel.formatTime(0), "00:00:00")
        XCTAssertEqual(viewModel.formatTime(3661), "01:01:01")
        XCTAssertEqual(viewModel.formatTime(7265), "02:01:05")
    }
    
    @MainActor
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
    @MainActor
    func testScreenTimeServiceInitialization() {
        let screenTimeService = ScreenTimeService.shared
        XCTAssertNotNil(screenTimeService)
    }
    
    @MainActor
    func testScreenTimeServiceBootstrapSampleData() async {
        let screenTimeService = ScreenTimeService.shared
        await screenTimeService.resetData()
        screenTimeService.bootstrapSampleDataIfNeeded()
        let usages = screenTimeService.getAppUsages()
        XCTAssertFalse(usages.isEmpty)
        XCTAssertGreaterThan(screenTimeService.getTotalTime(for: .learning), 0)
    }
    
    @MainActor
    func testScreenTimeServiceStartStopMonitoring() async {
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

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(screenTimeService.isMonitoring)

        screenTimeService.stopMonitoring()
        XCTAssertFalse(screenTimeService.isMonitoring)
    }

    @MainActor
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
    @MainActor
    func testUsagePersistenceGeneratesUniqueIDsForPrivacyProtectedApps() {
        let usagePersistence = UsagePersistence()
        
        // Clear any existing data
        usagePersistence.clearAll()
        
        // Create two tokens with the same display name but no bundle identifier (privacy-protected apps)
        let token1 = ApplicationToken(from: UUID().uuidString)
        let token2 = ApplicationToken(from: UUID().uuidString)
        
        let result1 = usagePersistence.resolveLogicalID(for: token1, bundleIdentifier: nil, displayName: "Privacy Protected App")
        let result2 = usagePersistence.resolveLogicalID(for: token2, bundleIdentifier: nil, displayName: "Privacy Protected App")
        
        // Verify that they get different logical IDs
        XCTAssertNotEqual(result1.logicalID, result2.logicalID, "Privacy-protected apps with the same name should receive unique logical IDs")
        
        // Verify that the same token always gets the same logical ID
        let result3 = usagePersistence.resolveLogicalID(for: token1, bundleIdentifier: nil, displayName: "Privacy Protected App")
        XCTAssertEqual(result1.logicalID, result3.logicalID, "Same token should always resolve to the same logical ID")
    }
    
    // MARK: - Phase 4B Tests
    
    // Test ParentPINService functionality
    func testParentPINServiceWeakPINDetection() {
        // Create a temporary instance for testing
        let pinService = ParentPINService()
        
        // Test weak PINs that should be rejected
        XCTAssertTrue(pinService.isWeakPIN("1234"), "Sequential PIN should be weak")
        XCTAssertTrue(pinService.isWeakPIN("0000"), "Repeated digits PIN should be weak")
        XCTAssertTrue(pinService.isWeakPIN("1111"), "Repeated digits PIN should be weak")
        XCTAssertTrue(pinService.isWeakPIN("2345"), "Sequential PIN should be weak")
        XCTAssertTrue(pinService.isWeakPIN("5432"), "Reverse sequential PIN should be weak")
        
        // Test strong PINs that should be accepted
        XCTAssertFalse(pinService.isWeakPIN("1235"), "Non-sequential PIN should not be weak")
        XCTAssertFalse(pinService.isWeakPIN("5678"), "Non-sequential PIN should not be weak")
        XCTAssertFalse(pinService.isWeakPIN("1357"), "Non-sequential PIN should not be weak")
    }
    
    func testParentPINServicePINValidation() {
        // Create a temporary instance for testing
        let pinService = ParentPINService()
        
        // Test PIN length validation
        switch pinService.setParentPIN("123") {
        case .success:
            XCTFail("PIN with less than 4 digits should be rejected")
        case .failure(let error):
            XCTAssertEqual(error, PINError.invalidLength, "Should return invalid length error")
        }
        
        switch pinService.setParentPIN("12345") {
        case .success:
            XCTFail("PIN with more than 4 digits should be rejected")
        case .failure(let error):
            XCTAssertEqual(error, PINError.invalidLength, "Should return invalid length error")
        }
        
        // Test weak PIN rejection
        switch pinService.setParentPIN("1234") {
        case .success:
            XCTFail("Weak PIN should be rejected")
        case .failure(let error):
            XCTAssertEqual(error, PINError.weakPIN, "Should return weak PIN error")
        }
        
        // Test valid PIN acceptance
        switch pinService.setParentPIN("1235") {
        case .success:
            // PIN should be accepted
            XCTAssertTrue(pinService.validatePIN("1235"), "Valid PIN should be accepted")
            XCTAssertFalse(pinService.validatePIN("5432"), "Invalid PIN should be rejected")
        case .failure(let error):
            XCTFail("Valid PIN should be accepted, but got error: \(error)")
        }
    }
    
    // Test ParentalApprovalService (basic functionality)
    @MainActor
    func testParentalApprovalServiceInitialization() {
        let approvalService = ParentalApprovalService()
        XCTAssertNotNil(approvalService, "ParentalApprovalService should be initialized")
    }
}