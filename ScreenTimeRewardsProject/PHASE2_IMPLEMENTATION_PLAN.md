# Phase 2 Implementation Plan: ScreenTime API Integration

## Overview
This document outlines the remaining work to deliver real ScreenTime API integration for ScreenTime Rewards. Core monitoring configuration is in place; next steps focus on the DeviceActivity extension, persistence, and reward logic.

## Immediate Next Steps

### 1. Validate DeviceActivity Extension
- [ ] Exercise the extension on hardware and confirm notifications trigger UI updates
- [ ] Add logging/analytics for event reception and failure modes
- [ ] Gracefully handle authorization revocation and offline gaps in the service

### 2. Enhance Family Controls Flow
- [ ] Persist `FamilyActivitySelection` and thresholds (UserDefaults/Core Data)
- [ ] Reflect authorization status in UI and guide users through initial setup
- [ ] Support editing/removing previously selected apps/categories

### 3. Collect & Store Real Usage Data
- [ ] Replace sample data seeding once DeviceActivity events flow
- [ ] Persist recorded `AppUsage` sessions (Core Data + CloudKit sync prep)
- [ ] Provide daily/hourly aggregates for reward logic

### 4. Implement Reward Experience
- [ ] Define reward thresholds and mapping to monitored categories
- [ ] Build parental approval flow (notifications / in-app approvals)
- [ ] Surface reward status & history to the child-facing UI

## Detailed Task Breakdown

### Task 1: DeviceActivity Extension
1. Verify on-device event delivery and add diagnostic logging for intermittent failures
2. Harden Darwin-notification handling in the app (debounce duplicates, capture metadata)
3. Surface extension status in the UI (e.g., “Awaiting Screen Time data” banner until events arrive)

### Task 2: Family Controls & Authorization UX
1. Wrap the existing picker with first-run experience (AuthorizationCenter UI as needed)
2. Store selections + thresholds, restoring on launch
3. Detect authorization revocation and prompt the user to re-enable

### Task 3: Data Persistence & Reporting
1. Model `UsageSession` entities in Core Data aligned with `AppUsage`
2. Write ingestion pipeline triggered by event notifications
3. Provide aggregated summaries for UI and reward engine (daily totals, category totals)

### Task 4: Reward Mechanics
1. Define reward schema (e.g., X minutes educational unlocks Y minutes entertainment)
2. Implement scheduler that checks aggregated data and produces reward opportunities
3. Support parental approval (notifications, manual overrides)
4. Update UI to display earned rewards and redemption status

## Updated Implementation Approach

1. **Extension Wiring** – complete the DeviceActivity monitor app extension and integrate with service delegate
2. **Persist & Sync** – move from in-memory usage to durable storage and plan for CloudKit syncing
3. **Reward Layer** – build on top of persisted data to deliver actual incentives
4. **Polish & QA** – run device QA, regression tests, and finalize documentation before release

## Testing Considerations

- **Unit Tests**: Expand coverage for persistence and reward calculation
- **Extension Tests**: Create manual/automated scenarios validating extension callbacks (requires device)
- **End-to-End**: Validate full flow: configure apps → collect usage → earn reward → approval
- **Performance**: Monitor battery/CPU with MetricKit, especially during event spikes

## Timeline Estimate
- DeviceActivity extension & real data capture: 2–3 days
- Persistence & CloudKit groundwork: 2–3 days
- Reward experience implementation: 3–4 days
- QA and polish: 1–2 days

## Success Criteria
- [ ] DeviceActivity events from extension update app state in near-real time
- [ ] Family activity selections and thresholds persist across launches/devices
- [ ] Usage sessions stored and available for reward calculations
- [ ] Reward flows functional with parental approvals
- [ ] Unit/integration tests pass on physical hardware
- [ ] Battery usage remains within <5% impact during typical monitoring

## References
- `ScreenTimeRewards/ScreenTimeRewards/Services/ScreenTimeService.swift`
- `ScreenTimeRewards/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`
- Apple Developer Documentation: DeviceActivity Monitor Extensions, Family Controls, Managed Settings
