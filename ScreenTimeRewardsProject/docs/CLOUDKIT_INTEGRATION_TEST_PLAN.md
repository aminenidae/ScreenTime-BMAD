# CloudKit Integration Test Plan

This document outlines the steps to test CloudKit integration in the ScreenTime Rewards app.

## Prerequisites

1. Two iOS devices with different iCloud accounts
2. Both devices logged into iCloud
3. App installed on both devices

## Test Cases

### Test Case 1: Device Registration
**Objective:** Verify that devices can register with CloudKit

**Steps:**
1. Launch app on Device A (Parent Device)
2. Select "Parent Device" in DeviceSelectionView
3. Verify device is registered in CloudKit
4. Launch app on Device B (Child Device)
5. Select "Child Device" in DeviceSelectionView
6. Verify device is registered in CloudKit

**Expected Results:**
- Both devices should appear in the CloudKit dashboard
- RegisteredDevice entities should be created locally and synced

### Test Case 2: Cross-Device Sync
**Objective:** Verify that data syncs between devices

**Steps:**
1. On Parent Device, configure app categories
2. Wait 30 seconds for sync
3. On Child Device, verify configurations are received
4. On Child Device, generate usage data
5. Wait 30 seconds for sync
6. On Parent Device, verify usage data is received

**Expected Results:**
- Configuration changes propagate from parent to child
- Usage data propagates from child to parent

### Test Case 3: Offline Queue
**Objective:** Verify offline operations queue and sync when online

**Steps:**
1. Put device in airplane mode
2. Perform operations that would normally sync
3. Verify operations are queued
4. Turn off airplane mode
5. Verify queued operations sync

**Expected Results:**
- Operations queue when offline
- Operations sync when connectivity restored

## Debugging Tools

### CloudKit Debug View
Access the CloudKit debug view in Settings (DEBUG builds only) to:
- Check account status
- Verify CloudKit availability
- Manually trigger status checks

### Console Logging
Enable verbose logging to monitor:
- Registration events
- Sync operations
- Error conditions

## Success Criteria

- [ ] Devices register successfully
- [ ] Data syncs between parent and child devices
- [ ] Offline operations queue properly
- [ ] Conflict resolution works correctly
- [ ] Error handling is robust