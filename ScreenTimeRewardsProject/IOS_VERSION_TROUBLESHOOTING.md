# iOS Version Compatibility Troubleshooting Guide

## Understanding the Issue

The error "The OS version is lower than the deployment target" occurs when your device's iOS version is older than the minimum iOS version specified in your Xcode project's deployment target.

## How to Check Your Device's iOS Version

1. On your iPhone or iPad, open the **Settings** app
2. Tap **General**
3. Tap **About**
4. Look for **Software Version** - this shows your current iOS version

## How to Check Your Project's Deployment Target

1. Open your project in Xcode
2. Select your project in the Project Navigator (left sidebar)
3. Select your app target (e.g., "ScreenTimeRewards")
4. Go to the **General** tab
5. Look under **Deployment Info** for the **iOS** version

## Solutions

### Solution 1: Update Your Device (Recommended)

If your device supports a newer version of iOS:
1. Connect your device to Wi-Fi
2. Open the **Settings** app
3. Tap **General**
4. Tap **Software Update**
5. If an update is available, tap **Download and Install**
6. Follow the on-screen instructions

### Solution 2: Lower the Deployment Target

If you cannot update your device or prefer not to:
1. Open your project in Xcode
2. Select your project in the Project Navigator
3. Select your app target
4. Go to the **General** tab
5. Under **Deployment Info**, change the **iOS** version to match or be lower than your device's iOS version
6. The minimum supported version for ScreenTime APIs is iOS 14.0

## Minimum iOS Version Requirements

This project requires iOS 14.0 or later because it uses Apple's ScreenTime APIs:
- DeviceActivity framework: iOS 14.0+
- FamilyControls framework: iOS 14.0+

If your device is running iOS 13.x or earlier, you will need to either:
1. Update your device to iOS 14.0 or later
2. Use a different device that meets the requirements
3. Modify the project to remove ScreenTime API dependencies (not recommended as it defeats the purpose of the app)

## Common iOS Version Scenarios

| Device iOS Version | Project Deployment Target | Will It Build? | Solution |
|-------------------|---------------------------|----------------|----------|
| 15.2 | 14.0 | ✅ Yes | No action needed |
| 14.5 | 15.0 | ❌ No | Lower deployment target to 14.5 or update device |
| 13.7 | 14.0 | ❌ No | Update device to iOS 14.0+ or use different device |
| 16.0 | 14.0 | ✅ Yes | No action needed |

## Additional Notes

1. **Simulator vs. Physical Device**: The ScreenTime APIs only work on physical devices, not in the Simulator.

2. **App Store Requirements**: If you plan to distribute this app on the App Store, you should consider what minimum iOS version will reach your target audience.

3. **Feature Availability**: Lowering the deployment target below iOS 14.0 will prevent the app from using ScreenTime APIs, which are essential for this project's functionality.

## Need Help?

If you're still having issues:
1. Check that your device meets the minimum requirements
2. Verify that you've properly linked the required frameworks
3. Ensure that you've added the Family Controls capability
4. Confirm that you're building for a physical device, not the Simulator