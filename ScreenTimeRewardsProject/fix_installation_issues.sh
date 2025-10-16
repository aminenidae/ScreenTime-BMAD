#!/bin/bash

# Script to help resolve iOS app installation issues (Error 3002)

echo "ScreenTime Rewards - Installation Issue Fixer"
echo "==========================================="

echo ""
echo "Common causes of Error 3002:"
echo "1. Missing or incorrect App Group configuration"
echo "2. Device not included in provisioning profile"
echo "3. Missing Family Controls entitlement"
echo "4. Expired or invalid provisioning profiles"

echo ""
echo "Recommended steps to resolve:"

cat << 'STEPS'
1. Verify App Group in Apple Developer Portal:
   - Go to https://developer.apple.com/account/resources/identifiers/list
   - Check that "group.com.screentimerewards.shared" exists
   - Ensure both app IDs are associated with this group

2. Check device registration:
   - Get your device UDID (Settings > General > About > Serial Number)
   - Verify device is registered in Apple Developer Portal
   - Check that provisioning profile includes your device

3. In Xcode, refresh provisioning:
   - Select your project in Project Navigator
   - Select the main app target
   - Go to Signing & Capabilities
   - Ensure Team is set correctly
   - Enable Family Controls capability if not present
   - Enable App Groups capability with "group.com.screentimerewards.shared"
   - Repeat for ScreenTimeActivityExtension target

4. Clean and rebuild:
   - Product > Clean Build Folder (Shift+Cmd+K)
   - Delete app from device if present
   - Rebuild and run

5. If issues persist:
   - Xcode > Preferences > Accounts
   - Select your team
   - Click "Manage Certificates"
   - Remove expired certificates
   - Refresh provisioning profiles
STEPS

echo ""
echo "For command-line verification:"
echo "xcrun xctrace list devices"
echo "xcodebuild -project ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards -destination 'platform=iOS,id=<device-udid>' clean build"

echo ""
echo "If you continue to have issues, try manually downloading and installing the provisioning profile from the Apple Developer Portal."