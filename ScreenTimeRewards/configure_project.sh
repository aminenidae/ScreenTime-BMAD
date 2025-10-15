#!/bin/bash

# Script to configure the ScreenTimeRewards Xcode project

echo "Configuring ScreenTimeRewards Xcode project..."

# Check if we're in the right directory
if [ ! -d "ScreenTimeRewards.xcodeproj" ]; then
    echo "Error: ScreenTimeRewards.xcodeproj not found in current directory"
    exit 1
fi

echo "Project structure verified."

# List the files we've added
echo "Added files:"
echo "  - ScreenTimeRewards/Models/AppUsage.swift"
echo "  - ScreenTimeRewards/Services/ScreenTimeService.swift"
echo "  - ScreenTimeRewards/ViewModels/AppUsageViewModel.swift"
echo "  - ScreenTimeRewards/Views/AppUsageView.swift"
echo "  - Updated ScreenTimeRewards/ScreenTimeRewardsApp.swift"
echo "  - Updated ScreenTimeRewards/Info.plist"
echo "  - Renamed ContentView.swift to LegacyContentView.swift"
echo "  - Updated ScreenTimeRewardsTests/ScreenTimeRewardsTests.swift"
echo "  - Added ScreenTimeRewardsTests/FrameworkImportTests.swift"

echo ""
echo "Manual steps needed:"
echo "1. Open the project in Xcode"
echo "2. Add the required frameworks to the project:"
echo "   - Select your project in the Project Navigator"
echo "   - Select the 'ScreenTimeRewards' target"
echo "   - Go to the 'General' tab"
echo "   - Scroll down to 'Frameworks, Libraries, and Embedded Content'"
echo "   - Click the '+' button and add:"
echo "     - DeviceActivity.framework"
echo "     - FamilyControls.framework"
echo "3. Add the Family Controls capability:"
echo "   - Select your project in the Project Navigator"
echo "   - Select the 'ScreenTimeRewards' target"
echo "   - Go to the 'Signing & Capabilities' tab"
echo "   - Click the '+' button and add 'Family Controls'"
echo "4. Ensure the deployment target is compatible with your device:"
echo "   - Select your project in the Project Navigator"
echo "   - Select the 'ScreenTimeRewards' target"
echo "   - Go to the 'General' tab"
echo "   - Under 'Deployment Info', set 'iOS' to a version compatible with your device"
echo "   - The minimum supported version is iOS 14.0"
echo "5. Build and run the project"

echo ""
echo "If you encounter build errors:"
echo "1. Make sure the DeviceActivity and FamilyControls frameworks are properly linked"
echo "2. Check that the Family Controls capability is enabled"
echo "3. Verify that the deployment target is set to iOS 14.0 or later"
echo "4. Ensure you're building for a physical device (not Simulator)"
echo "5. Check that the frameworks are imported in ScreenTimeService.swift"
echo "6. If you see 'The OS version is lower than the deployment target':"
echo "   - Check your device's iOS version in Settings > General > About > Software Version"
echo "   - In Xcode, set the deployment target to match or be lower than your device's iOS version"

echo ""
echo "Testing:"
echo "1. Run the unit tests to verify framework imports work correctly"
echo "2. Run the AppUsage tests to verify model functionality"
echo "3. Test basic UI functionality:"
echo "   - Verify the main screen loads correctly"
echo "   - Check that all buttons are visible and functional"
echo "   - Test the monitoring start/stop functionality"
echo "   - Verify data reset works"
echo "4. Refer to TESTING_PLAN.md for a comprehensive testing guide"

echo ""
echo "The project is now configured with the ScreenTime tracking components."
echo "Next steps:"
echo "1. Run the unit tests to verify functionality"
echo "2. Test ScreenTime API integration on physical devices"
echo "3. Implement reward mechanisms based on usage data"