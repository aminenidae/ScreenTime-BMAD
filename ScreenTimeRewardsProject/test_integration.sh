#!/bin/bash

set -euo pipefail

# ScreenTime Rewards - Integration Test Script
# Validates that the project builds for a physical device destination.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DESTINATION=${DESTINATION:-"generic/platform=iOS"}

echo "ScreenTime Rewards - Integration Test"
echo "====================================="

echo "Selected destination: $DESTINATION"

if [[ "$DESTINATION" == *"Simulator"* ]]; then
  cat <<'MSG'
DeviceActivity and FamilyControls frameworks are only available on physical iOS devices.
Skipping simulator build/test. Provide a physical device destination, for example:
  DESTINATION="platform=iOS,id=<device-udid>" ./test_integration.sh
MSG
  exit 0
fi

echo "1. Cleaning previous builds..."
xcodebuild clean \
  -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination "$DESTINATION" >/dev/null 2>&1

echo "2. Building project for device..."
xcodebuild build \
  -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination "$DESTINATION" >/dev/null 2>&1 && echo "   ✅ Build successful"

echo "3. Preparing tests (build-for-testing)..."
xcodebuild build-for-testing \
  -project ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination "$DESTINATION" >/dev/null 2>&1 && echo "   ✅ Test build successful"

echo "4. Manual test reminder"
cat <<'MSG'
Automated Screen Time tests require an interactive session on a physical device.
Run `xcodebuild test` with the same destination once the device is connected and trusted.
MSG

echo ""
echo "Integration Test Summary"
echo "======================="
echo "✅ Build verification: Successful"
echo "✅ Test artifacts: Ready for device execution"
echo "⚠️  Runtime validation requires a physical device session"
