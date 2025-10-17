# ScreenTime Rewards - Technical Documentation

## Overview
This document captures the technical implementation, lessons learned, and best practices for the ScreenTime Rewards application. It serves as a comprehensive guide for rebuilding the working path and coordinating future development efforts.

## Project Structure
```
ScreenTimeRewardsProject/
├── ScreenTimeRewards/
│   ├── Models/
│   │   └── AppUsage.swift
│   ├── ViewModels/
│   │   └── AppUsageViewModel.swift
│   ├── Views/
│   │   ├── AppUsageView.swift
│   │   └── CategoryAssignmentView.swift
│   ├── Services/
│   │   └── ScreenTimeService.swift
│   ├── Shared/
│   │   └── ScreenTimeNotifications.swift
│   └── Assets.xcassets/
├── ScreenTimeRewardsTests/
└── ScreenTimeRewardsUITests/
```

## Core Components

### 1. AppUsage Model
The `AppUsage` struct represents an app usage record for tracking purposes.

**Key Features:**
- Custom categories: Learning and Reward (instead of Apple's predefined categories)
- Reward points system with earned points calculation
- Time tracking with session management
- Codable for data persistence

**Implementation Details:**
```swift
enum AppCategory: String, Codable, CaseIterable {
    case learning = "Learning"
    case reward = "Reward"
}

var earnedRewardPoints: Int {
    let minutes = Int(totalTime / 60)
    return minutes * rewardPoints
}
```

### 2. ScreenTimeService
The core service that handles Screen Time API functionality.

**Key Features:**
- DeviceActivity monitoring with custom thresholds
- Application token-based tracking (privacy compliant)
- Extension-to-app communication via App Group UserDefaults
- Darwin notifications for event handling

**Implementation Details:**
- Uses ApplicationToken as primary identifier (not bundle IDs)
- Groups applications by user-assigned categories
- Creates DeviceActivityEvents per category
- Handles event callbacks from DeviceActivityMonitor extension

### 3. AppUsageViewModel
The view model that manages app usage data for the UI.

**Key Features:**
- Data binding with @Published properties
- Category-based time and reward point calculations
- FamilyControls authorization flow
- Data persistence using App Group UserDefaults

**Key Methods:**
- `openCategoryAssignmentForAdjustment()` - Smart reopening of category assignment
- `updateCategoryTotals()` - Calculates time per category
- `updateCategoryRewardPoints()` - Calculates reward points per category

### 4. UI Components

#### AppUsageView
Main view showing:
- Monitoring status
- Category summaries (Learning/Reward) with time and points
- Total reward points
- Monitoring settings
- App usage list
- Control buttons

#### CategoryAssignmentView
View for assigning categories and reward points:
- Displays apps using Label(token) for real names/icons
- Category picker with Learning/Reward options
- Reward points stepper (0-100, step by 5)
- Category and reward points summaries

## Key Implementation Patterns

### 1. Privacy-Compliant Design
- Uses ApplicationToken as primary identifier (Apple's recommended approach)
- No dependency on bundle identifiers or display names
- All data stored in App Group for extension sharing
- FamilyControls authorization before picker access

### 2. Custom Category System
- Simplified from Apple's 7+ categories to just 2: Learning and Reward
- User-defined reward points per app
- Category-based monitoring and reporting

### 3. Data Persistence
- App Group UserDefaults for sharing between app and extension
- Separate storage for category assignments and reward points
- Token hash-based keys for storage (limitation of UserDefaults)

### 4. Extension Communication
- Darwin notifications for triggering (no payload)
- App Group UserDefaults for data exchange
- Event names and timestamps stored in shared storage

## Lessons Learned

### 1. FamilyActivityPicker Limitations
- Returns nil for bundle IDs and display names by design (privacy)
- Must request authorization BEFORE opening picker
- Label(token) works to display real app names/icons
- Tokens are the only guaranteed identifier

### 2. Reward Points Calculation
- Initially calculated based on category multipliers
- Changed to user-assigned points × usage time
- More intuitive and flexible for users

### 3. Category Adjustment Flow
- Users need to adjust categories/points after initial setup
- Smart reopening preserves existing assignments
- Direct access when apps already selected

### 4. Build System Issues
- CodingKeys must match actual stored properties
- Numeric type consistency (Double to Int conversion)
- Proper error handling for optional values

## Testing Approach

### 1. Unit Testing
- Test AppUsage initialization and functionality
- Test time formatting and category calculations
- Test reward points calculations
- Test ScreenTimeService basic functionality

### 2. Integration Testing
- DeviceActivity event handling
- Real ScreenTime data collection
- Family Controls authorization flow
- Data flow from DeviceActivity to AppUsage

### 3. Manual Testing
- UI functionality tests
- Core functionality tests
- Data management tests
- Integration tests on physical devices

## Best Practices

### 1. Privacy Compliance
- Always use ApplicationToken as primary identifier
- Request FamilyControls authorization before picker access
- Add NSFamilyControlsUsageDescription to Info.plist
- Use App Groups for extension communication

### 2. Error Handling
- Graceful handling of nil values from FamilyActivityPicker
- Clear error messages for authorization failures
- Robust data persistence with fallbacks

### 3. User Experience
- Clear category assignment with visual feedback
- Summary sections for transparency
- Intuitive reward points adjustment
- Responsive UI with proper loading states

## Common Issues and Solutions

### 1. "Unknown App" Display
**Issue:** Apps show as "Unknown App" instead of real names
**Solution:** Use Label(token) for display, ensure authorization before picker

### 2. Events Not Firing
**Issue:** DeviceActivity events not triggering
**Solution:** Verify monitoring is started, check thresholds, use extension logs

### 3. Data Not Persisting
**Issue:** Category assignments lost after app restart
**Solution:** Implement App Group UserDefaults storage

### 4. Build Errors
**Issue:** CodingKeys mismatch causing build failures
**Solution:** Ensure CodingKeys match stored properties only

## Future Enhancements

### 1. Improved Persistence
- Replace UserDefaults with CoreData for better data management
- Implement proper token serialization/deserialization

### 2. Enhanced UI
- Add visual indicators for high-usage apps
- Implement charts/graphs for usage patterns
- Add goal tracking and achievements

### 3. Advanced Features
- Parental approval workflow
- CloudKit sync for multi-device support
- Custom reward schedules
- Usage history and trends

## Implementation Checklist

### Core Functionality
- [x] FamilyControls authorization flow
- [x] FamilyActivityPicker integration
- [x] Category assignment (Learning/Reward)
- [x] Reward points assignment
- [x] DeviceActivity monitoring
- [x] Usage tracking and reporting
- [x] Category adjustment capability

### Data Management
- [x] App Group UserDefaults implementation
- [x] Extension-to-app communication
- [x] Data persistence across app restarts
- [x] Category-based calculations

### UI/UX
- [x] Main dashboard with category summaries
- [x] Category assignment view
- [x] Monitoring controls
- [x] Category adjustment workflow

## Testing Validation

### Successful Tests
1. FamilyActivityPicker returns tokens successfully
2. Label(token) displays real app names/icons
3. Category assignment works correctly
4. Reward points are calculated properly
5. DeviceActivity events fire when thresholds reached
6. Usage data appears in app after events
7. Category totals update correctly
8. Data persists across app restarts
9. Category adjustment workflow functions

### Edge Cases Tested
1. Apps with nil bundle IDs/display names
2. Multiple apps in same category
3. Different reward point values
4. Short and long usage durations
5. App restart scenarios
6. Authorization denial/regrant flows

## Code Quality Standards

### Swift Best Practices
- Follow Swift 5 guidelines
- Use descriptive variable and function names
- Implement proper error handling
- Maintain consistent code formatting

### Architecture Principles
- MVVM pattern with clear separation of concerns
- Single responsibility principle for classes/methods
- Dependency injection for testability
- Reactive programming with Combine framework

### Documentation Standards
- Swift doc comments for public APIs
- Inline comments for complex logic
- Clear commit messages and PR descriptions
- This comprehensive documentation

## Deployment Considerations

### App Store Requirements
- Proper entitlements for FamilyControls
- Privacy usage descriptions in Info.plist
- Age rating considerations for parental controls
- App Store guidelines compliance

### Device Compatibility
- iOS 15.0+ requirement
- Physical device testing for ScreenTime APIs
- Family Sharing configuration
- Screen Time settings verification

## Conclusion

This implementation successfully demonstrates a privacy-compliant, user-friendly ScreenTime tracking application with a reward system. The key innovations include:

1. Custom category system (Learning/Reward) instead of Apple's complex categories
2. User-defined reward points with intuitive calculation
3. Seamless category adjustment workflow
4. Privacy-first design using ApplicationTokens
5. Robust data persistence and extension communication

The solution addresses all major challenges identified in the technical feasibility study and provides a solid foundation for production implementation.