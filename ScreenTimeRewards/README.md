# ScreenTime Rewards

An iOS application that tracks screen time usage and implements a reward system based on educational app usage.

## Project Overview

This project implements a ScreenTime tracking system with a reward mechanism for children who use educational apps. The application uses Apple's ScreenTime APIs to monitor device usage and provide rewards based on time spent in educational applications.

## Features

- Track app usage across different categories (educational, entertainment, etc.)
- Monitor time spent in educational apps
- Display usage statistics in an intuitive interface
- Prepare for reward system implementation based on educational usage

## Project Structure

```
ScreenTimeRewards/
├── ScreenTimeRewards/
│   ├── Models/
│   │   └── AppUsage.swift
│   ├── Services/
│   │   └── ScreenTimeService.swift
│   ├── ViewModels/
│   │   └── AppUsageViewModel.swift
│   ├── Views/
│   │   └── AppUsageView.swift
│   ├── Assets.xcassets/
│   ├── Preview Content/
│   ├── ScreenTimeRewardsApp.swift
│   └── LegacyContentView.swift
├── ScreenTimeRewardsTests/
│   ├── ScreenTimeRewardsTests.swift
│   └── FrameworkImportTests.swift
└── ScreenTimeRewardsUITests/
    ├── ScreenTimeRewardsUITests.swift
    └── ScreenTimeRewardsUITestsLaunchTests.swift
```

## Setup Instructions

1. Open `ScreenTimeRewards.xcodeproj` in Xcode
2. Add the required frameworks:
   - Select your project in the Project Navigator
   - Select the "ScreenTimeRewards" target
   - Go to the "General" tab
   - Scroll down to "Frameworks, Libraries, and Embedded Content"
   - Click the "+" button and add:
     - DeviceActivity.framework
     - FamilyControls.framework
3. Add the Family Controls capability:
   - Select your project in the Project Navigator
   - Select the "ScreenTimeRewards" target
   - Go to the "Signing & Capabilities" tab
   - Click the "+" button and add "Family Controls"
4. Ensure the deployment target is compatible with your device:
   - Select your project in the Project Navigator
   - Select the "ScreenTimeRewards" target
   - Go to the "General" tab
   - Under "Deployment Info", set "iOS" to a version compatible with your device
   - The minimum supported version is iOS 14.0
5. Build and run the project

## Required Configurations

### Frameworks
- DeviceActivity: For monitoring device usage
- FamilyControls: For family sharing and parental controls

### Capabilities
- Family Controls: Required for accessing ScreenTime APIs

### Entitlements
- The project includes a ScreenTimeRewards.entitlements file for the necessary permissions

## Implementation Details

### AppUsage Model
Represents an app usage record with:
- Bundle identifier
- App name
- Category (educational, entertainment, etc.)
- Total usage time
- Individual usage sessions
- First and last access dates

### ScreenTimeService
Handles interaction with Apple's ScreenTime APIs:
- Requesting permission to track usage
- Starting and stopping monitoring
- Managing app usage data

### AppUsageViewModel
Manages the UI state and data:
- Loading and refreshing app usage data
- Controlling monitoring state
- Formatting time for display

### AppUsageView
The main user interface:
- Displays monitoring status
- Shows category summaries
- Lists individual app usage
- Provides control buttons

## Testing

### Unit Tests
The project includes unit tests for:
- AppUsage model initialization and functionality
- Time formatting
- Category management
- Framework import verification

To run unit tests:
1. In Xcode, select Product > Test or press ⌘U
2. View results in the Test Navigator

### Manual Testing - Phase 1 Complete
The first phase of manual testing has been completed successfully:
- ✅ Button interactions work correctly
- ✅ Status indicators update properly
- ✅ Sample data displays correctly
- ✅ Reset functionality works
- ✅ Time formatting is correct
- ✅ All unit tests pass

Refer to TESTING_PLAN.md for a comprehensive testing guide that includes:
- UI functionality tests
- Core functionality tests
- Data management tests
- Integration tests

### Testing Checklist - Phase 1
- [x] App launches without crashing
- [x] Main screen displays correctly
- [x] Monitoring controls work (Start/Stop)
- [x] Data reset functionality works
- [x] Time formatting displays correctly
- [x] Sample data loads correctly
- [x] All unit tests pass

## Next Steps - Phase 2 Implementation (In Progress)

We are now moving to Phase 2 implementation which involves integrating the actual ScreenTime APIs:

1. **Implement DeviceActivity Integration** - Enabling actual ScreenTime monitoring
2. **Add Family Controls Authorization** - Implementing authorization flows
3. **Implement Real Data Collection** - Replacing simulated data with actual ScreenTime data
4. **Add Data Persistence** - Storing collected data locally
5. **Test with Real Data** - Validating implementation on physical devices

Refer to PHASE2_IMPLEMENTATION_PLAN.md for detailed implementation guidance.

## Troubleshooting

### Common Build Issues

1. **"Cannot find type 'DeviceActivity' in scope" or similar errors:**
   - Make sure DeviceActivity.framework and FamilyControls.framework are added to the project
   - Verify that the frameworks are properly linked under "Frameworks, Libraries, and Embedded Content"
   - Ensure you've added the Family Controls capability in Signing & Capabilities

2. **"No such module 'DeviceActivity'" or similar errors:**
   - Check that the deployment target is set to iOS 14.0 or later
   - Ensure you're building for a physical device (Simulator may not have these frameworks)
   - Verify that the frameworks are correctly imported in your Swift files

3. **Family Controls capability issues:**
   - Make sure the Family Controls capability is added in Signing & Capabilities
   - Verify that your App ID has the Family Controls capability enabled in the Apple Developer portal

4. **"The OS version is lower than the deployment target":**
   - Check your device's iOS version in Settings > General > About > Software Version
   - In Xcode, set the deployment target to match or be lower than your device's iOS version
   - The minimum supported version for this project is iOS 14.0

### Testing on Physical Devices

The ScreenTime APIs require a physical device to function properly. Testing on the Simulator will not provide accurate results for ScreenTime functionality.

## Technical Requirements

- iOS 14.0+ (minimum supported version)
- Xcode 12.0+
- Swift 5.0+

## Framework Integration Notes

The DeviceActivity and FamilyControls frameworks are part of Apple's ScreenTime APIs. These frameworks:

1. Are only available on physical iOS devices (not in Simulator)
2. Require iOS 14.0 or later
3. Need specific entitlements and capabilities
4. Must be properly linked in the Xcode project

When implementing the actual ScreenTime API integration, you'll need to:

1. Use DeviceActivityCenter to monitor device usage
2. Implement DeviceActivityDelegate to receive usage events
3. Use FamilyControls to manage family sharing settings
4. Handle authorization flows properly

The current implementation provides a foundation that can be extended with the actual API calls once the frameworks are properly linked.

## iOS Version Compatibility

This project requires a minimum iOS version of 14.0 to use the ScreenTime APIs. If your device is running an older version of iOS, you'll need to either:

1. Update your device to iOS 14.0 or later
2. Lower the deployment target in Xcode to match your device's iOS version (if it's 14.0 or later)
3. Use a different device that meets the minimum requirements

To check your device's iOS version:
1. Open the Settings app
2. Tap "General"
3. Tap "About"
4. Look for "Software Version"

To change the deployment target in Xcode:
1. Select your project in the Project Navigator
2. Select the "ScreenTimeRewards" target
3. Go to the "General" tab
4. Under "Deployment Info", change the "iOS" version to match your device