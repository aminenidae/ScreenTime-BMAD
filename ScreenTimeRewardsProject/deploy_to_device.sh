#!/bin/bash

# Script to build, install, and run the ScreenTime Rewards app on a connected iOS device

echo "ScreenTime Rewards - Device Deployment Script"
echo "=========================================="

# Get the device UDID
DEVICE_UDID=$(xcrun xctrace list devices | grep -E '.*\([0-9]+(\.[0-9]+)*\) \([A-Z0-9-]+\)' | head -1 | grep -oE '\([A-Z0-9-]+\)$' | tr -d '()')

if [ -z "$DEVICE_UDID" ]; then
    echo "Error: No iOS device found. Please connect your device and trust this computer."
    exit 1
fi

echo "Found device with UDID: $DEVICE_UDID"

# Get the project directory
PROJECT_DIR="/Users/ameen/Documents/ScreenTime-BMAD/ScreenTimeRewardsProject"
PROJECT_FILE="$PROJECT_DIR/ScreenTimeRewards.xcodeproj"
SCHEME="ScreenTimeRewards"
DESTINATION="platform=iOS,id=$DEVICE_UDID"

echo "Using project: $PROJECT_FILE"
echo "Using scheme: $SCHEME"
echo "Using destination: $DESTINATION"

echo ""
echo "Step 1: Cleaning previous builds..."
xcodebuild clean \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Clean successful"
else
    echo "❌ Clean failed"
    exit 1
fi

echo ""
echo "Step 2: Building project..."
xcodebuild build \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Build successful"
else
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "Step 3: Installing app to device..."
xcodebuild install \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Installation successful"
else
    echo "❌ Installation failed"
    exit 1
fi

echo ""
echo "Deployment Summary"
echo "================="
echo "✅ Project cleaned"
echo "✅ Project built successfully"
echo "✅ App installed to device"
echo ""
echo "To run the app:"
echo "1. Unlock your device"
echo "2. If prompted, trust the developer profile in Settings > General > VPN & Device Management"
echo "3. Find and tap the ScreenTimeRewards app on your home screen"
echo ""
echo "Note: If this is the first time installing, you may need to:"
echo "1. Go to Settings > Screen Time > App & Website Activity"
echo "2. Ensure ScreenTimeActivityExtension is enabled"
echo "3. Grant Family Controls permissions when prompted"
echo ""
echo "If you encounter any issues:"
echo "1. Check that your device is properly connected and trusted"
echo "2. Verify that your provisioning profiles are up to date"
echo "3. Ensure the Family Controls capability is properly configured"
echo "4. Make sure both the main app and extension use the same App Group"
echo ""
echo "Note: Renaming the parent folder from 'ScreenTimeRewards' to 'ScreenTimeRewardsProject' does not affect the build or installation process."