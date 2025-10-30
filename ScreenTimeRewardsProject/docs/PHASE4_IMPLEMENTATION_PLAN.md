# Phase 4 Implementation Plan
## Child Background Sync

**Date:** October 28, 2025
**Version:** 1.0

---

## Overview
This document outlines the implementation plan for Phase 4 of the CloudKit Remote Monitoring Implementation, which focuses on implementing background sync capabilities on child devices. This phase will ensure usage data is uploaded in near real-time and configuration changes are applied immediately.

## Phase Goals
1. Implement background task registration for periodic sync operations
2. Update DeviceActivityMonitor thresholds for 1-minute granularity
3. Implement configuration polling for immediate updates
4. Add sync status indicators for user feedback
5. Implement robust retry logic for failed syncs

## Implementation Tasks

### Task 4.1: Implement Background Task Registration
**Duration:** 2 hours

**Objective:** Register background tasks for usage upload and configuration checking

**Implementation:**
- Create ChildBackgroundSyncService singleton
- Register background tasks with BGTaskScheduler
- Implement task handlers for usage upload and config check
- Add proper error handling and task completion

**Files to Create:**
- `ScreenTimeRewards/Services/ChildBackgroundSyncService.swift`

**Acceptance Criteria:**
- Background task registration for usage upload
- Background task registration for config check
- Proper task handling with completion
- Error handling for background operations

### Task 4.2: Update DeviceActivityMonitor Thresholds
**Duration:** 3 hours

**Objective:** Reduce DeviceActivityMonitor thresholds for near real-time updates

**Implementation:**
- Modify ScreenTimeActivityMonitor to use 1-minute thresholds
- Add immediate upload trigger for significant events
- Optimize battery usage with efficient threshold handling

**Files to Modify:**
- `ScreenTimeRewards/Services/ScreenTimeActivityMonitor.swift`

**Acceptance Criteria:**
- 1-minute threshold for DeviceActivity events
- Immediate upload on significant events
- Proper error handling
- Battery usage optimization

### Task 4.3: Implement Configuration Polling
**Duration:** 4 hours

**Objective:** Enable periodic polling for configuration updates

**Implementation:**
- Extend ChildBackgroundSyncService with config polling
- Implement periodic checks for parent configuration updates
- Add immediate configuration application
- Track command execution status

**Files to Modify:**
- `ScreenTimeRewards/Services/ChildBackgroundSyncService.swift`

**Acceptance Criteria:**
- Periodic configuration polling
- Immediate configuration application
- Command execution tracking
- Error handling for network issues

### Task 4.4: Add Sync Status Indicators
**Duration:** 2 hours

**Objective:** Provide visual feedback on sync status to users

**Implementation:**
- Create SyncStatusIndicatorView for displaying sync status
- Add color-coded status indicators
- Implement status text descriptions
- Integrate with existing child mode UI

**Files to Create:**
- `ScreenTimeRewards/Views/ChildMode/SyncStatusIndicatorView.swift`

**Acceptance Criteria:**
- Visual sync status indicator
- Status text descriptions
- Color-coded status states
- Integration with existing UI

### Task 4.5: Implement Retry Logic
**Duration:** 3 hours

**Objective:** Add robust retry logic for failed sync operations

**Implementation:**
- Extend OfflineQueueManager with enhanced retry logic
- Implement exponential backoff for retries
- Add max retry limit enforcement
- Add logging for failed operations

**Files to Modify:**
- `ScreenTimeRewards/Services/OfflineQueueManager.swift`

**Acceptance Criteria:**
- Exponential backoff for retries
- Max retry limit enforcement
- Failed operation logging
- User notification for persistent failures

## Technical Requirements

### Background Task Configuration
```xml
<!-- Required capabilities -->
1. Background Modes:
   - Background fetch
   - Remote notifications
   - Background processing
2. Background Task Identifiers:
   - com.screentimerewards.usage-upload
   - com.screentimerewards.config-check
```

### DeviceActivityMonitor Updates
```swift
// Target threshold
let threshold = DateComponents(minute: 1)

// Immediate upload trigger
func triggerImmediateUpload() {
    // Implementation for immediate data upload
}
```

### Sync Status States
```swift
enum SyncStatus {
    case idle      // No sync in progress
    case syncing   // Sync operation in progress
    case success   // Last sync completed successfully
    case error     // Last sync failed
}
```

## Testing Strategy

### Unit Testing
- Background task registration and handling
- DeviceActivityMonitor threshold updates
- Configuration polling functionality
- Sync status indicator states
- Retry logic with various failure scenarios

### Integration Testing
- Background task execution with real CloudKit operations
- DeviceActivityMonitor event handling
- Configuration update propagation from parent to child
- Sync status updates in UI
- Offline/online transition handling

### Manual Testing
- Background task scheduling and execution
- Real-time usage data upload
- Configuration change propagation
- Sync status visualization
- Retry behavior with network interruptions

## Files to Create

1. `ScreenTimeRewards/Services/ChildBackgroundSyncService.swift`
2. `ScreenTimeRewards/Views/ChildMode/SyncStatusIndicatorView.swift`

## Files to Modify

1. `ScreenTimeRewards/Services/ScreenTimeActivityMonitor.swift`
2. `ScreenTimeRewards/Services/OfflineQueueManager.swift`

## Dependencies

- Phase 2: CloudKit Sync Service (completed)
- Phase 3: Parent Remote Dashboard (completed)

## Next Steps

1. Implement ChildBackgroundSyncService with background task registration
2. Update ScreenTimeActivityMonitor with 1-minute thresholds
3. Add configuration polling functionality
4. Create sync status indicator UI
5. Enhance retry logic in OfflineQueueManager
6. Comprehensive testing of all components
7. Integration testing with parent dashboard

## Success Criteria

- ✅ Background tasks registered and executing
- ✅ 1-minute DeviceActivityMonitor thresholds
- ✅ Configuration polling working correctly
- ✅ Sync status indicators visible in UI
- ✅ Retry logic handling failures appropriately
- ✅ All unit tests passing (>80% coverage)
- ✅ Integration tests completed successfully