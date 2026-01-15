# Repository Guidelines

## Project Structure & Module Organization
- `docs/` holds architecture, PRD, feasibility studies, and standards; review before major changes.
- `ScreenTimeRewards/ScreenTimeRewards/` contains Swift source split into `Models`, `ViewModels`, `Views`, `Services`, and platform resources (`Assets.xcassets`, `Info.plist`, entitlements).
- `ScreenTimeRewardsTests/` and `ScreenTimeRewardsUITests/` provide XCTest targets; keep new tests parallel to the production folder they exercise.
- Debug build logs live under `ScreenTimeRewards/ScreenTimeRewards/Debug Reports/` for quick diagnostics.

## Build, Test, and Development Commands
- `./configure_project.sh` — verifies local structure and lists manual Xcode setup steps.
- `xcodebuild build -project ScreenTimeRewards/ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards -destination 'generic/platform=iOS'` — CI-safe device build.
- `xcodebuild test -project ScreenTimeRewards/ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards -destination 'platform=iOS,id=<device-udid>'` — run all XCTest suites on a physical device.
- `DESTINATION="platform=iOS,id=<device-udid>" ./ScreenTimeRewards/test_integration.sh` — scripted clean build + test prep; script exits early on simulator targets.

## Coding Style & Naming Conventions
- Follow `docs/architecture/coding-standards.md`: Swift 5, SwiftUI-first, 4-space indentation, braces on the defining line.
- Use PascalCase for types/files, camelCase for variables and functions, UPPER_SNAKE_CASE only for true constants.
- Keep lines ≤120 characters and favor descriptive names (`startMonitoring()` over `startMon()`).
- Document public APIs with Swift doc comments and explain *why* decisions are made in inline comments.

## Testing Guidelines
- XCTest is the standard; organize tests mirroring the production folder (`Services` → `ScreenTimeRewardsTests/Services`).
- Name test methods with intention (`testStartMonitoringReturnsSuccess()`), and seed deterministic data via helpers rather than relying on live Screen Time events.
- Run `xcodebuild test …` before submitting; capture device logs when touching DeviceActivity or FamilyControls code paths.

## Commit & Pull Request Guidelines
- Write imperative, scope-limited commit subjects (`Fix DeviceActivity authorization bridge`).
- Reference related docs or stories in the body when relevant (`Refs docs/technical-feasibility-testing-plan.md`).
- PRs should include: purpose summary, testing evidence (command output or screenshots), affected files list, and any new manual setup instructions. Tag QA when altering entitlements or authorization flows.

## Device & Security Notes
- Testing Screen Time features requires iOS 15+ hardware with Family Controls entitlement enabled; simulators cannot validate authorization flows.
- Never commit provisioning profiles or personal identifiers; use the entitlements file already in source control.
