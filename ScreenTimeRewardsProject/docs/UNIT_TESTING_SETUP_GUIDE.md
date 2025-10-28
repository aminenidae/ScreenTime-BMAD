# Unit Testing Setup Guide
## ScreenTime Rewards Project

**Date:** October 27, 2025

## Overview
This guide explains how to properly set up and run unit tests for the ScreenTime Rewards project. The build error you encountered ("No such module 'XCTest'") occurs because test files need to be part of a proper test target in Xcode.

## Why the Error Occurred
The test files I created were placed in the main application target rather than in a dedicated test target. In Xcode:
- Application code goes in the main target (ScreenTimeRewards)
- Test code must go in a test target (ScreenTimeRewardsTests or similar)

## Proper Test Setup in Xcode

### 1. Check Existing Test Target
First, check if a test target already exists:

1. Open the project in Xcode
2. In the Project Navigator, look for:
   - `ScreenTimeRewardsTests` (unit tests)
   - `ScreenTimeRewardsUITests` (UI tests)

If these don't exist, you'll need to create them.

### 2. Create Test Target (if needed)
If no test target exists:

1. In Xcode, go to **File** → **New** → **Target**
2. Select **iOS** → **Testing** → **Unit Testing Bundle**
3. Click **Next**
4. Set the following:
   - Product Name: `ScreenTimeRewardsTests`
   - Language: Swift
   - Test Host: ScreenTimeRewards.app
5. Click **Finish**

### 3. Move Test Files to Correct Location
When you create actual test files:

1. Place them in the `ScreenTimeRewardsTests` folder in Xcode
2. Ensure they're added to the test target (check the Target Membership in the File Inspector)
3. Import the main module with: `@testable import ScreenTimeRewards`

## Example Test Structure
Here's how a proper test file should be structured:

```swift
import XCTest
@testable import ScreenTimeRewards

class CloudKitSyncServiceTests: XCTestCase {
    var cloudKitSyncService: CloudKitSyncService!
    
    override func setUp() {
        super.setUp()
        cloudKitSyncService = CloudKitSyncService()
    }
    
    override func tearDown() {
        cloudKitSyncService = nil
        super.tearDown()
    }
    
    func testExample() {
        // Your test code here
        XCTAssertNotNil(cloudKitSyncService)
    }
}
```

## Running Tests
To run tests in Xcode:

1. **Product** → **Test** (or press ⌘+U)
2. Or click the test button in the toolbar
3. Or use the scheme selector to choose a test scheme

## Command Line Testing
You can also run tests from the command line:

```bash
xcodebuild test \
  -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0'
```

## Test Organization
Organize tests to match the structure of your source code:

```
ScreenTimeRewardsTests/
├── Services/
│   ├── CloudKitSyncServiceTests.swift
│   ├── OfflineQueueManagerTests.swift
│   └── ScreenTimeServiceTests.swift
├── Models/
│   ├── DeviceModeTests.swift
│   └── AppUsageTests.swift
└── Views/
    ├── DeviceSelectionViewTests.swift
    └── RootViewTests.swift
```

## Testing Best Practices

### 1. Use Descriptive Test Names
```swift
func testResolveConflict_parentDeviceAlwaysWins() {
    // Clear what is being tested
}
```

### 2. Follow AAA Pattern
- **Arrange**: Set up test data
- **Act**: Execute the method under test
- **Assert**: Verify the results

### 3. Test One Thing
Each test should verify one specific behavior.

### 4. Use setUp and tearDown
Initialize shared resources in `setUp()`, clean up in `tearDown()`.

## Common Testing Scenarios

### Testing CloudKitSyncService
```swift
func testMergeConfigurations_combinesLocalAndRemote() {
    // Arrange
    let localConfig = createMockAppConfiguration(logicalID: "app1")
    let remoteConfig = createMockAppConfiguration(logicalID: "app2")
    
    // Act
    let merged = cloudKitSyncService.mergeConfigurations(
        local: [localConfig], 
        remote: [remoteConfig]
    )
    
    // Assert
    XCTAssertEqual(merged.count, 2)
}
```

### Testing OfflineQueueManager
```swift
func testEnqueueOperation_increasesQueueCount() {
    // Arrange
    let initialCount = offlineQueueManager.queuedOperationsCount
    let payload = ["test": "data"]
    
    // Act
    try? offlineQueueManager.enqueueOperation(
        operation: "test_op", 
        payload: payload
    )
    
    // Assert
    XCTAssertEqual(offlineQueueManager.queuedOperationsCount, initialCount + 1)
}
```

## Troubleshooting

### "No such module 'XCTest'" Error
- Ensure test files are in a test target
- Check Target Membership in File Inspector
- Verify the file is not added to the main app target

### "No such module 'ScreenTimeRewards'" Error
- Use `@testable import ScreenTimeRewards`
- Ensure the main target builds successfully
- Check that the test target has the main target as its Host Application

### Tests Not Running
- Check that the test class inherits from XCTestCase
- Verify test method names start with "test"
- Ensure test methods are public or internal (not private)

## Next Steps
1. Set up the test target in Xcode if it doesn't exist
2. Create proper test files in the test target
3. Implement tests for the new CloudKit functionality
4. Run tests to verify the implementation works correctly

The core functionality has been implemented and should work correctly. The test files just need to be properly integrated into Xcode's testing framework.