# ScreenTime Rewards - Developer Quick Start Guide

## Overview
This guide provides a quick start for developers working on the ScreenTime Rewards application. It covers the essential setup, key components, and common workflows.

## Prerequisites
- Xcode 13.0 or later
- iOS 15.0+ development environment
- Physical iOS device for testing (ScreenTime APIs don't work in Simulator)
- Apple Developer account with FamilyControls entitlements

## Project Setup

### 1. Clone and Open
```bash
cd /path/to/ScreenTime-BMAD/ScreenTimeRewardsProject
open ScreenTimeRewards.xcodeproj
```

### 2. Configure Signing
- Set your Team in Project Settings
- Ensure App Group capability is enabled
- Verify Bundle Identifier matches entitlements

### 3. Dependencies
No external dependencies required. Uses only Apple frameworks:
- FamilyControls
- DeviceActivity
- ManagedSettings
- SwiftUI
- Combine

## Key Components

### Models
**AppUsage.swift**
- Core data model for tracking app usage
- Custom categories: Learning, Reward
- Reward points system
- Time tracking with sessions

### ViewModels
**AppUsageViewModel.swift**
- Main view model for UI binding
- Category and reward point calculations
- FamilyControls authorization flow
- Data persistence management

### Views
**AppUsageView.swift**
- Main dashboard view
- Monitoring controls
- Category summaries
- App usage list

**CategoryAssignmentView.swift**
- Category and reward point assignment
- Uses Label(token) for app display
- Summary sections

### Services
**ScreenTimeService.swift**
- Core ScreenTime API integration
- DeviceActivity monitoring
- Extension communication
- Data processing

**ScreenTimeNotifications.swift**
- Notification name constants

## Common Workflows

### 1. Adding a New Feature
1. Identify the appropriate layer (Model/View/ViewModel/Service)
2. Create or modify the relevant component
3. Update dependent components as needed
4. Test thoroughly on physical device
5. Document changes in technical documentation

### 2. Modifying Category System
1. Update AppUsage.AppCategory enum
2. Modify CategoryAssignmentView picker options
3. Update AppUsageView category displays
4. Adjust ScreenTimeService categorization logic
5. Update any summary sections

### 3. Changing Reward Calculation
1. Modify AppUsage.earnedRewardPoints calculation
2. Update UI displays in AppUsageView
3. Verify calculation in ScreenTimeService
4. Test with various time and point values

### 4. Adding New Settings
1. Add properties to AppUsageViewModel
2. Create UI controls in AppUsageView
3. Implement logic in ScreenTimeService if needed
4. Add persistence if settings should survive restarts

## Testing

### Unit Tests
Run tests in Xcode:
```
Product → Test or ⌘U
```

Key test areas:
- AppUsage model initialization
- Time formatting
- Reward point calculations
- Category assignments

### Manual Testing
1. Build and run on physical device
2. Grant ScreenTime permissions
3. Select apps via FamilyActivityPicker
4. Assign categories and reward points
5. Configure monitoring thresholds
6. Start monitoring
7. Use selected apps to trigger events
8. Verify usage data appears
9. Test category adjustment workflow

## Debugging Tips

### 1. Authorization Issues
- Check NSFamilyControlsUsageDescription in Info.plist
- Verify App Group configuration
- Ensure physical device testing
- Check device ScreenTime settings

### 2. Events Not Firing
- Verify monitoring is started
- Check threshold durations
- Use Console app to monitor extension logs
- Verify App Group access in extension

### 3. Data Not Persisting
- Check App Group identifier consistency
- Verify UserDefaults suiteName
- Check for storage key collisions

### 4. UI Display Issues
- Verify Label(token) usage for app names
- Check authorization before picker access
- Ensure proper state binding in views

## Common Patterns

### 1. Privacy-Compliant Design
```swift
// Always use ApplicationToken as primary identifier
guard let token = application.token else { continue }

// Use Label(token) for app display
Label(token)

// Store data in App Group
let sharedDefaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")
```

### 2. Extension Communication
```swift
// Send notification from extension
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    CFNotificationName("com.screentimerewards.eventDidReachThreshold" as CFString),
    nil, nil, true
)

// Handle in main app
NotificationCenter.default.publisher(for: ScreenTimeService.usageDidChangeNotification)
```

### 3. Data Persistence
```swift
// Save to App Group
guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
sharedDefaults.set(encodedData, forKey: "categoryAssignments")

// Load from App Group
if let data = sharedDefaults.data(forKey: "categoryAssignments") {
    // Decode and use data
}
```

## Code Standards

### Swift Style
- Use descriptive variable names
- Follow Swift API Design Guidelines
- Maintain consistent indentation (4 spaces)
- Use MARK: comments for organization

### Architecture
- MVVM pattern
- Unidirectional data flow
- Separation of concerns
- Dependency injection

### Error Handling
- Handle optionals gracefully
- Provide user-friendly error messages
- Log detailed information for debugging
- Fail gracefully when possible

## Important Files

### Core Implementation
- `Models/AppUsage.swift` - Data model
- `ViewModels/AppUsageViewModel.swift` - Main view model
- `Views/AppUsageView.swift` - Main UI
- `Views/CategoryAssignmentView.swift` - Assignment UI
- `Services/ScreenTimeService.swift` - Core service

### Documentation
- `SCREEN_TIME_REWARDS_TECHNICAL_DOCUMENTATION.md` - Complete technical guide
- `IMPLEMENTATION_PROGRESS_SUMMARY.md` - Progress summary
- `DEVELOPER_QUICK_START.md` - This file

## Troubleshooting

### Build Errors
1. Check for CodingKeys mismatches
2. Verify numeric type consistency
3. Ensure all required properties are initialized
4. Check for missing imports

### Runtime Issues
1. Verify physical device testing for ScreenTime APIs
2. Check authorization flows
3. Validate App Group configuration
4. Confirm entitlements are properly set

### Performance Issues
1. Minimize UI updates on main thread
2. Use background queues for heavy operations
3. Optimize data processing
4. Profile with Instruments

## Getting Help

### Documentation
- Technical Documentation: `SCREEN_TIME_REWARDS_TECHNICAL_DOCUMENTATION.md`
- Implementation Summary: `IMPLEMENTATION_PROGRESS_SUMMARY.md`

### Team Contacts
- Ameen (Project Owner)
- Refer to commit history for specific component authors

### Apple Resources
- [FamilyControls Framework Documentation](https://developer.apple.com/documentation/familycontrols)
- [DeviceActivity Documentation](https://developer.apple.com/documentation/deviceactivity)
- [ManagedSettings Documentation](https://developer.apple.com/documentation/managedsettings)

## Next Steps

1. Familiarize yourself with the codebase structure
2. Run the app on a physical device
3. Review the technical documentation
4. Make a small change to understand the workflow
5. Run tests to ensure everything works
6. Start on your assigned tasks

Remember: The app is designed to be privacy-compliant and user-friendly. Always consider these principles when making changes.