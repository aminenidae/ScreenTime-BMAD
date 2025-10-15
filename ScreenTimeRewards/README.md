# ScreenTime Rewards

An iOS application that tracks screen time usage and implements a reward system based on educational app usage.

## Project Overview

This project implements a ScreenTime tracking system with a reward mechanism for children who use educational apps. The application uses Apple's ScreenTime APIs to monitor device usage and provide rewards based on time spent in educational applications.

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

1. Open `ScreenTimeRewards.xcodeproj` in Xcode (Xcode 15 or later recommended)
2. Confirm required frameworks are linked under **Frameworks, Libraries, and Embedded Content**:
   - `DeviceActivity.framework`
   - `FamilyControls.framework`
   - `ManagedSettings.framework`
3. Under **Signing & Capabilities**, ensure the `Family Controls` capability is enabled for the `ScreenTimeRewards` target.
4. Set the deployment target to **iOS 15.0** or later.
5. Build and run on a physical device (Screen Time APIs do not function in Simulator).

## Key Features

- Configurable monitoring of apps selected via the Family Activity picker
- Per-category threshold controls that determine when usage events register
- Real-time updates of educational vs. entertainment totals (demo data until the DeviceActivity extension is completed)
- Start/Stop monitoring controls and data reset

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

## Testing

### Unit Tests
Execute with **Product ▸ Test** (⌘U). Suites cover:
- `AppUsage` model logic (`recordUsage`, session handling)
- View-model formatting and reset behaviour
- Service configuration/monitoring flows (including simulated DeviceActivity events)
- Framework import verification

### On-Device Manual Testing
1. Build & run on an iOS 15+ physical device.
2. Tap the slider icon to open the Family Activity picker; select educational/entertainment apps.
3. Adjust thresholds (5–120 minutes) and tap **Apply Monitoring Configuration**.
4. Start/Stop monitoring and confirm status changes and configuration persistence.
5. (When the DeviceActivity extension is available) leave the device in normal use to observe usage totals update as thresholds are reached.

For command-line testing/CI:
```bash
DESTINATION="platform=iOS,id=<device-udid>" ./ScreenTimeRewards/test_integration.sh
xcodebuild test \
  -project ScreenTimeRewards/ScreenTimeRewards.xcodeproj \
  -scheme ScreenTimeRewards \
  -destination 'platform=iOS,id=<device-udid>'
```
Replace `<device-udid>` with the identifier from `xcrun xctrace list devices`.

## Troubleshooting

1. **Family Activity picker doesn’t appear**: confirm the `FamilyControls` capability is enabled and the device is signed into an Apple ID with Family Sharing.
2. **Monitoring doesn’t start**: check Console logs for authorization errors; rerun `Start Monitoring` after granting Family Controls access on-device.
3. **Usage never changes**: expected until the DeviceActivity monitor extension is added. Use `simulateEvent(named:customDuration:)` in DEBUG builds for validation.
4. **Build errors about ScreenTime frameworks**: ensure you are building for a physical device on iOS 15+ and that all required frameworks are linked.

## Roadmap
- Implement DeviceActivity monitor app extension to receive live Screen Time events
- Persist usage sessions (Core Data/CloudKit) and sync thresholds across devices
- Build parental approval and reward workflows on top of collected data

## References
- `ScreenTimeRewards/PHASE2_IMPLEMENTATION_PLAN.md`
- `ScreenTimeRewards/PHASE2_PROGRESS_REPORT.md`
- `ScreenTimeRewards/TESTING_PLAN.md`
- Apple Developer Documentation: Screen Time APIs, Family Controls, Managed Settings
