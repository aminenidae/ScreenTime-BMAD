# ScreenTime Rewards

A SwiftUI-based iOS application that demonstrates Screen Time API integration for monitoring app usage and implementing reward mechanisms.

## Setup & Configuration

1. Open `ScreenTimeRewards.xcodeproj` in Xcode 15+.
2. Confirm required frameworks are linked under **Frameworks, Libraries, and Embedded Content**:
   - `DeviceActivity.framework`
   - `FamilyControls.framework`
   - `ManagedSettings.framework`
3. Under **Signing & Capabilities**, ensure the `Family Controls` capability and **App Groups** (e.g. `group.com.screentimerewards.shared`) are enabled for both the app and the **ScreenTimeActivityExtension** target.
4. Sign the new app extension target (`ScreenTimeActivityExtension`) with the same team.
5. Set the deployment target to **iOS 15.0** or later.
6. Build and run on a physical device (Screen Time APIs do not function in Simulator).

## Key Features

- Configurable monitoring of apps selected via the Family Activity picker
- Per-category threshold controls that determine when usage events register
- Real-time updates of educational vs. entertainment totals (demo data until the DeviceActivity extension is completed)
- Start/Stop monitoring controls and data reset
- **Experimental category expansion for "All Apps" edge case resolution** (DEBUG only)

## Implementation Details

### AppUsage Model
Represents an app usage record with:
- Bundle identifier & display name
- Category (educational, entertainment, productivity, etc.)
- Total usage time and individual sessions
- First/last access timestamps

### ScreenTimeService
Handles Screen Time API integration:
- Requests authorization (async/await or continuation bridge on iOS 15)
- Configures DeviceActivity monitoring using `FamilyActivitySelection`
- Responds to DeviceActivity events through a custom monitor bridge
- Broadcasts usage updates via NotificationCenter
- Provides debug helpers (`configureForTesting`, `simulateEvent`) for unit tests
- **Includes experimental `expandCategoryTokens` method for category expansion** (DEBUG only)

### AppUsageViewModel
- Maintains monitoring state, picker selections, and threshold values
- Applies configuration by calling `ScreenTimeService.configureMonitoring`
- Refreshes UI when usage data changes
- Surfaces error messages from authorization/monitoring flows

### AppUsageView
- Displays monitoring status indicators and category totals
- Presents the Family Activity picker via toolbar button
- Allows per-category threshold adjustment with steppers
- Shows a live list of recorded usage sessions

### ExperimentalCategoryExpansionView (DEBUG only)
- **Isolated experimental environment to test category expansion without affecting production flows**
- Button to trigger FamilyActivityPicker
- Display area for before/after state (category tokens → expanded apps)
- User confirmation flow for category selections
- Comprehensive logging for debugging

## Testing

### Unit Tests
Execute with **Product ▸ Test** (⌘U). Suites cover:
- `AppUsage` model logic (`recordUsage`, session handling)
- View-model formatting and reset behaviour
- Service configuration/monitoring flows (including simulated DeviceActivity events)
- Framework import verification

### On-Device Manual Testing
1. Build & run on an iOS 15+ physical device with Screen Time enabled and the extension installed (look for the "ScreenTimeActivityExtension" bundle under Settings ▶ Screen Time ▶ App & Website Activity).
2. Tap the slider icon to open the Family Activity picker; select educational/entertainment apps.
3. Adjust thresholds (1–120 minutes) and tap **Apply Monitoring Configuration**.
4. Start/Stop monitoring and confirm status changes and configuration persistence.
5. Use the device normally; when thresholds are reached the extension posts events and the totals update in real time (watch the category tiles and app list).
6. Use the `Reset Data` button between runs to clear accumulated sessions.

For command-line testing/CI:
```bash
DESTINATION="platform=iOS,id=<device-udid>" ./ScreenTimeRewards/test_integration.sh
xcodebuild test \
  -project ScreenTimeRewards/ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination 'platform=iOS,id=<device-udid>'
```
Replace `<device-udid>` with the identifier from `xcrun xctrace list devices`.

### Experimental Testing (DEBUG only)
1. Build & run on an iOS 15+ physical device with DEBUG configuration
2. Navigate to the "🔬 Experimental" tab
3. Tap "Select Apps/Categories" to open the FamilyActivityPicker
4. Test various selection scenarios:
   - Individual app selection
   - "All Apps" selection
   - Single category selection
   - Multiple category selection
   - Mixed selection (apps + categories)
5. Observe the confirmation flow for category selections
6. Verify proper handling of cancel and confirm actions

## Deployment Scripts

This project includes helpful scripts for deployment:

1. **deploy_to_device.sh** - Builds, installs, and prepares the app for running on your connected iOS device
2. **fix_installation_issues.sh** - Provides guidance for resolving common installation issues (Error 3002)

To use the deployment script:
```bash
cd ScreenTimeRewardsProject
./deploy_to_device.sh
```

## Troubleshooting

1. **Family Activity picker doesn't appear**: confirm the `FamilyControls` capability is enabled and the device is signed into an Apple ID with Family Sharing.
2. **Monitoring doesn't start**: check Console logs for authorization errors; rerun `Start Monitoring` after granting Family Controls access on-device.
3. **Usage never changes**: expected until the DeviceActivity monitor extension is added. Use `simulateEvent(named:customDuration:)` in DEBUG builds for validation.
4. **Build errors about ScreenTime frameworks**: ensure you are building for a physical device on iOS 15+ and that all required frameworks are linked.
5. **Extension builds but data doesn't change**: confirm both targets share the same App Group (`group.com.screentimerewards.shared`) and reinstall the app after toggling entitlements.
6. **Installation Error 3002**: This typically indicates provisioning profile or entitlements issues. Run `./fix_installation_issues.sh` for detailed steps to resolve.

## Documentation

### Core Documentation
1. `SCREEN_TIME_REWARDS_TECHNICAL_DOCUMENTATION.md` - Comprehensive technical guide
2. `IMPLEMENTATION_PROGRESS_SUMMARY.md` - Progress summary with features implemented
3. `PATH1_TESTING_GUIDE.md` - Original testing guide
4. `IMPLEMENTATION_OPTIONS.md` - Alternative implementation paths

### Phase 1 Documentation
1. `docs/EXPERIMENTAL_CATEGORY_EXPANSION_RESULTS.md` - Results of experimental prototype
2. `docs/expansion_test_logs.txt` - Test logs for category expansion
3. `docs/PHASE1_IMPLEMENTATION_SUMMARY.md` - Implementation summary for Phase 1
4. `docs/PHASE1_COMPLETION_REPORT.md` - Completion report for Phase 1

## Roadmap
- Implement DeviceActivity monitor app extension to receive live Screen Time events
- Persist usage sessions (Core Data/CloudKit) and sync thresholds across devices
- Build parental approval and reward workflows on top of collected data
- **Refine and productionize category expansion solution for "All Apps" edge case**

## References
- `ScreenTimeRewards/PHASE2_IMPLEMENTATION_PLAN.md`
- `ScreenTimeRewards/PHASE2_PROGRESS_REPORT.md`
- `ScreenTimeRewards/TESTING_PLAN.md`
- Apple Developer Documentation: Screen Time APIs, Family Controls, Managed Settings