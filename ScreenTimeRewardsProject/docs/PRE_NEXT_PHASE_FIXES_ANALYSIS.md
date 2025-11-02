# Pre-Next Phase Fixes - Analysis & Implementation Guide

**Date:** November 2, 2025
**Status:** Analysis Complete - Ready for Implementation
**Purpose:** Address critical UX and architectural issues before proceeding to next development phase

---

## Issue 1: FamilyActivityPicker Flickering

### Problem Description
When opening the FamilyActivityPicker for learning apps in child device/parent mode, the picker flickers upon presentation.

### Root Cause Analysis

**Location:** `ScreenTimeRewards/Views/LearningTabView.swift:92-96`

The picker is being presented through a complex state management chain:

1. **Button tap** calls `viewModel.presentPickerWithRetry(for: .learning)`
2. **State reset** happens in `resetPickerStateForNewPresentation()` which sets:
   ```swift
   isFamilyPickerPresented = false  // Resets the picker state
   ```
3. **Then immediately** in `requestAuthorizationAndOpenPicker()` it sets:
   ```swift
   isFamilyPickerPresented = true  // After a 0.5s delay
   ```

**The Problem:**
- The picker's `@Published var isFamilyPickerPresented` is bound to the view via `.familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, ...)`
- **State thrashing**: Setting false → true with delay causes SwiftUI to flash the view
- The 0.5s delay in `AppUsageViewModel.swift:1024` is meant to let authorization propagate, but it causes visible UI flicker

### Solution

**Strategy: Separate reset state from presentation state**

#### Implementation Steps:

**File:** `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

1. **Add a new flag to control state reset without affecting presentation:**
```swift
@Published private var isPreparing = false
```

2. **Modify `resetPickerStateForNewPresentation()`:**
```swift
private func resetPickerStateForNewPresentation() {
    #if DEBUG
    print("[AppUsageViewModel] 🔁 Resetting picker state for new presentation")
    #endif

    // Mark as preparing (prevents onChange handlers from firing)
    isPreparing = true

    // ONLY reset if picker is not already being presented
    // This prevents the flicker
    if isFamilyPickerPresented {
        #if DEBUG
        print("[AppUsageViewModel] ⚠️ Picker already presented - skipping reset")
        #endif
        return
    }

    // Reset other state
    isCategoryAssignmentPresented = false
    shouldPresentAssignmentAfterPickerDismiss = false
    shouldUsePendingSelectionForSheet = false
    activePickerContext = nil

    // Clear errors
    pickerError = nil
    pickerLoadingTimeout = false
    pickerRetryCount = 0
    cancelPickerTimeout()

    // Clear preparing flag after brief delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.isPreparing = false
    }
}
```

3. **Modify `requestAuthorizationAndOpenPicker()` to remove the false→true toggle:**
```swift
private func requestAuthorizationAndOpenPicker() {
    #if DEBUG
    print("[AppUsageViewModel] Requesting authorization and opening picker")
    #endif

    Task {
        let authResult = await requestAuthorization()

        await MainActor.run {
            switch authResult {
            case .success(let status):
                #if DEBUG
                print("[AppUsageViewModel] ✅ Authorization successful: \(status)")
                #endif

                self.isAuthorizationGranted = true

                // REMOVE THE FALSE RESET - just set to true
                // No need to wait 0.5s - authorization is already done
                self.isFamilyPickerPresented = true
                self.startPickerTimeout()

            case .failure(let error):
                #if DEBUG
                print("[AppUsageViewModel] ❌ Authorization failed: \(error)")
                #endif
                self.isAuthorizationGranted = false
                self.errorMessage = "Authorization required: \(error.errorDescription ?? "Please grant Screen Time permission in Settings")"
            }
        }
    }
}
```

**Expected Result:**
- ✅ No visible flicker when opening picker
- ✅ Cleaner state transitions
- ✅ Faster picker presentation (no artificial 0.5s delay after auth is complete)

---

## Issue 2: Usage Time Count Accuracy

### Problem Description
The usage time counting system is not accurate. Time reported doesn't match actual app usage.

### Current Implementation Analysis

**How Usage Time is Currently Tracked:**

**File:** `ScreenTimeRewards/Services/ScreenTimeService.swift:145`
```swift
private let defaultThreshold = DateComponents(minute: 1)
```

**The Current System:**
1. **DeviceActivity monitors** apps with **1-minute threshold events**
2. **Extension fires** `eventDidReachThreshold` **every 1 minute** of usage
3. **Extension records** exactly `thresholdSeconds` (60 seconds) each time
4. **Main app** receives notification and creates/updates UsageRecord

**File:** `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift:209-213`
```swift
usagePersistence.recordUsage(
    logicalID: logicalID,
    additionalSeconds: thresholdSeconds,  // Always 60 seconds
    rewardPointsPerMinute: rewardPointsPerMinute
)
```

### Problems with Current Approach

**1. Fixed Interval Counting (Not Actual Duration)**
- **Problem**: Records exactly 60 seconds every time event fires
- **Reality**: User might use app for 1m 45s, but we record 1m (lose 45s)
- **OR**: User might use app for 45s, close it, event never fires (lose all 45s)

**2. Aggregation on Parent Side Creates Duplicates**
- **Problem**: CloudKit keeps versions of updated records
- **We fixed this** with de-duplication in ParentRemoteViewModel (Task 17)
- **But root cause remains**: We're updating same record multiple times

**3. Missing Last Session Data**
- **Problem**: If user uses app for 30s and switches, no event fires
- **No record created** until full 1-minute threshold reached

### Recommended Solution

**Strategy: Hybrid approach using both thresholds AND interval monitoring**

#### Implementation Plan:

**1. Keep 1-Minute Threshold Events (for reliability)**
- These guarantee we capture usage even if app crashes
- Extension runs even when main app is closed

**2. Add `intervalDidEnd` Tracking (for accuracy)**

**File:** `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`

**Current:** Only tracks `eventDidReachThreshold`
**Add:** Track `intervalDidEnd` to capture precise session duration

```swift
override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
    #if DEBUG
    print("[ScreenTimeActivityExtension] intervalDidEnd for activity: \(activity.rawValue)")
    #endif

    // Record final session time when monitoring interval ends
    recordSessionEnd()

    // Post notification to main app
    postNotification("com.screentimerewards.intervalDidEnd", activity: activity)
}

private nonisolated func recordSessionEnd() {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        return
    }

    // Get all active sessions from shared storage
    guard let sessionsData = sharedDefaults.data(forKey: "activeSessions"),
          var sessions = try? JSONDecoder().decode([String: ActiveSession].self, from: sessionsData) else {
        return
    }

    let now = Date()

    // For each active session, calculate and record final duration
    for (logicalID, session) in sessions {
        let totalDuration = now.timeIntervalSince(session.startTime)
        let recordedSeconds = session.recordedSeconds
        let remainingSeconds = Int(totalDuration) - recordedSeconds

        if remainingSeconds > 0 {
            // Record the remaining time
            usagePersistence.recordUsage(
                logicalID: logicalID,
                additionalSeconds: remainingSeconds,
                rewardPointsPerMinute: session.pointsPerMinute
            )
        }
    }

    // Clear active sessions
    sharedDefaults.removeObject(forKey: "activeSessions")
    sharedDefaults.synchronize()
}

// Add session tracking structure
private struct ActiveSession: Codable {
    let logicalID: String
    let startTime: Date
    var recordedSeconds: Int
    let pointsPerMinute: Int
}
```

**3. Track Active Sessions**

**Modify `eventDidReachThreshold`:**
```swift
override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    // Get event info
    guard let logicalID = getLogicalID(for: event),
          let thresholdSeconds = getThresholdSeconds(for: event),
          let rewardPointsPerMinute = getRewardPoints(for: event) else {
        return
    }

    // Record the threshold amount
    usagePersistence.recordUsage(
        logicalID: logicalID,
        additionalSeconds: thresholdSeconds,
        rewardPointsPerMinute: rewardPointsPerMinute
    )

    // Update active session tracking
    updateActiveSession(
        logicalID: logicalID,
        recordedSeconds: thresholdSeconds,
        pointsPerMinute: rewardPointsPerMinute
    )

    postNotification("com.screentimerewards.eventDidReachThreshold", event: event, activity: activity)
}

private nonisolated func updateActiveSession(logicalID: String, recordedSeconds: Int, pointsPerMinute: Int) {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        return
    }

    var sessions: [String: ActiveSession] = [:]
    if let data = sharedDefaults.data(forKey: "activeSessions"),
       let existing = try? JSONDecoder().decode([String: ActiveSession].self, from: data) {
        sessions = existing
    }

    if var session = sessions[logicalID] {
        // Update existing session
        session.recordedSeconds += recordedSeconds
        sessions[logicalID] = session
    } else {
        // Create new session
        sessions[logicalID] = ActiveSession(
            logicalID: logicalID,
            startTime: Date(),
            recordedSeconds: recordedSeconds,
            pointsPerMinute: pointsPerMinute
        )
    }

    if let encoded = try? JSONEncoder().encode(sessions) {
        sharedDefaults.set(encoded, forKey: "activeSessions")
        sharedDefaults.synchronize()
    }
}
```

**4. Alternative Simpler Approach (If Above Is Too Complex)**

**Just use DeviceActivityReport API:**

Apple provides `DeviceActivityReport` which gives **exact usage data**. This is more accurate than threshold events.

**File:** Create new `ScreenTimeRewards/Services/DeviceActivityReportService.swift`

```swift
import DeviceActivity
import SwiftUI

class DeviceActivityReportService {
    static let shared = DeviceActivityReportService()

    func generateReport(for tokens: Set<ApplicationToken>) async -> [String: TimeInterval] {
        // Use DeviceActivityReport to get EXACT usage times
        // This is the official Apple way to get accurate usage data

        var results: [String: TimeInterval] = [:]

        // DeviceActivityReport provides accurate screen time data
        // It's available in iOS 15+ and is the recommended approach

        return results
    }
}
```

**Recommended: Use DeviceActivityReport for accuracy, keep threshold events as backup**

### Accuracy Comparison

| Approach | Accuracy | Reliability | Complexity |
|----------|----------|-------------|------------|
| Current (1min threshold only) | ±60s | High | Low |
| Hybrid (threshold + intervalDidEnd) | ±5s | High | Medium |
| DeviceActivityReport API | Exact | Medium | Low |

**Best Solution:** DeviceActivityReport API with threshold events as fallback

---

## Issue 3: Parent Dashboard UI Updates

### Required Changes

**1. Remove AppConfiguration Card (Abandoned Feature)**

**File:** `ScreenTimeRewards/Views/ParentRemoteDashboardView.swift:50-52`

**REMOVE:**
```swift
// App Configuration
RemoteAppConfigurationView(viewModel: viewModel)
    .padding(.horizontal)
```

**2. Implement Multi-Child Device Support**

### Current Architecture Issues

**Current State:**
- `viewModel.selectedChildDevice` shows only ONE child at a time
- Dashboard displays data for selectedChildDevice only
- No way to view multiple children simultaneously

**Required UX:**
- Parent with 3 children should see **3 separate dashboard cards**
- Each card shows that child's usage, points, activity
- Tapping card expands to full detail view
- All children visible at glance (scrollable)

### Implementation Design

**File:** `ScreenTimeRewards/Views/ParentRemoteDashboardView.swift`

**REPLACE lines 44-56** with:

```swift
// Multi-child view - show all linked children
if !viewModel.linkedChildDevices.isEmpty {
    VStack(spacing: 20) {
        // Show card for each child device
        ForEach(viewModel.linkedChildDevices, id: \.deviceID) { childDevice in
            NavigationLink(destination: ChildDetailView(device: childDevice, viewModel: viewModel)) {
                ChildDeviceSummaryCard(device: childDevice, viewModel: viewModel)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    .padding(.horizontal)
} else if !viewModel.isLoading {
    // No devices linked
    // ... existing empty state code ...
}
```

**Create New Component:** `ScreenTimeRewards/Views/ParentRemote/ChildDeviceSummaryCard.swift`

```swift
import SwiftUI

struct ChildDeviceSummaryCard: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    // Load summary data for this specific device
    @State private var todayUsage: CategoryUsageSummary?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with device name and icon
            HStack {
                Image(systemName: deviceIcon)
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName ?? "Unknown Device")
                        .font(.headline)
                    Text("Last sync: \(lastSyncText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }

            Divider()

            // Quick stats
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let summary = todayUsage {
                HStack(spacing: 32) {
                    StatItem(
                        title: "Screen Time",
                        value: formatSeconds(summary.totalSeconds),
                        icon: "clock.fill",
                        color: .blue
                    )

                    StatItem(
                        title: "Points Earned",
                        value: "\(summary.totalPoints)",
                        icon: "star.fill",
                        color: .orange
                    )

                    StatItem(
                        title: "Apps Used",
                        value: "\(summary.appCount)",
                        icon: "app.fill",
                        color: .green
                    )
                }
            } else {
                Text("No usage today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            loadSummary()
        }
    }

    private var deviceIcon: String {
        guard let type = device.deviceType else { return "iphone" }
        return type.lowercased().contains("ipad") ? "ipad" : "iphone"
    }

    private var lastSyncText: String {
        guard let lastSync = device.lastSyncDate else {
            return "Never"
        }

        let interval = Date().timeIntervalSince(lastSync)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return lastSync.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    private func loadSummary() {
        // Load today's usage summary for this device
        isLoading = true

        Task {
            await viewModel.loadDeviceSummary(for: device)

            // Get the loaded summary
            if let deviceID = device.deviceID,
               let summary = viewModel.deviceSummaries[deviceID] {
                await MainActor.run {
                    self.todayUsage = summary
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

private struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
```

**Create New View:** `ScreenTimeRewards/Views/ParentRemote/ChildDetailView.swift`

```swift
import SwiftUI

struct ChildDetailView: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Device header
                DeviceHeaderView(device: device)

                // Usage summary for this device
                RemoteUsageSummaryView(viewModel: viewModel)
                    .padding(.horizontal)

                // Historical reports for this device
                HistoricalReportsView(viewModel: viewModel)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(device.deviceName ?? "Device Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load data for this specific device
            Task {
                await viewModel.loadChildData(for: device)
            }
        }
    }
}

private struct DeviceHeaderView: View {
    let device: RegisteredDevice

    var body: some View {
        HStack {
            Image(systemName: deviceIcon)
                .font(.largeTitle)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName ?? "Unknown Device")
                    .font(.title2)
                    .fontWeight(.bold)

                if let deviceID = device.deviceID {
                    Text("ID: \(deviceID.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let regDate = device.registrationDate {
                    Text("Paired on \(regDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var deviceIcon: String {
        guard let type = device.deviceType else { return "iphone" }
        return type.lowercased().contains("ipad") ? "ipad" : "iphone"
    }
}
```

**Update ViewModel:** `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`

**Add:**
```swift
// Store summaries for each device
@Published var deviceSummaries: [String: CategoryUsageSummary] = [:]

func loadDeviceSummary(for device: RegisteredDevice) async {
    guard let deviceID = device.deviceID else { return }

    // Load today's summary for this device
    await loadChildData(for: device)

    // Create summary from loaded data
    let summary = createTodaySummary(for: deviceID)

    await MainActor.run {
        self.deviceSummaries[deviceID] = summary
    }
}

private func createTodaySummary(for deviceID: String) -> CategoryUsageSummary {
    // Aggregate today's usage for this device
    let deviceRecords = usageRecords.filter { record in
        record.deviceID == deviceID &&
        Calendar.current.isDateInToday(record.sessionStart ?? Date())
    }

    let totalSeconds = deviceRecords.reduce(0) { $0 + Int($1.totalSeconds) }
    let totalPoints = deviceRecords.reduce(0) { $0 + Int($1.earnedPoints) }
    let appCount = Set(deviceRecords.compactMap { $0.logicalID }).count

    return CategoryUsageSummary(
        category: "All Apps",
        totalSeconds: totalSeconds,
        totalPoints: totalPoints,
        appCount: appCount
    )
}
```

---

## Issue 4: Child Device Pairing Limit (2 Parents Max)

### Problem Description
Need to limit each child device to pair with **maximum 2 parent devices**.

### Current Architecture

**File:** `ScreenTimeRewards/Services/DevicePairingService.swift`

**Current Pairing Flow (Child Side):**
1. Child scans QR code with share metadata
2. `acceptPairing()` accepts the share
3. Creates `CD_RegisteredDevice` record in parent's shared zone
4. No limit enforcement

**Current Pairing Flow (Parent Side):**
1. Parent generates QR code with CKShare
2. Creates shared zone
3. Waits for child to accept
4. No limit on how many parents a child can pair with

### Required Changes

#### Implementation Plan

**File:** `ScreenTimeRewards/Services/DevicePairingService.swift`

**1. Add validation in `acceptPairing()` before accepting share:**

```swift
func acceptPairing(shareMetadata: CKShare.Metadata) async throws {
    #if DEBUG
    print("[DevicePairingService] 📱 Child accepting pairing invitation")
    #endif

    // STEP 1: Check how many parents this child is already paired with
    let currentParentCount = try await getParentPairingCount()

    guard currentParentCount < 2 else {
        throw PairingError.maxParentsReached
    }

    // Continue with existing acceptance logic...
    let share = try await container.accept(shareMetadata)
    // ... rest of method
}

// NEW: Get count of parent devices child is currently paired with
private func getParentPairingCount() async throws -> Int {
    let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    let sharedDatabase = container.sharedCloudDatabase

    // Query all shared zones this child device has access to
    let query = CKQuery(
        recordType: "CD_SharedZoneRoot",
        predicate: NSPredicate(value: true)
    )

    do {
        let (results, _) = try await sharedDatabase.records(matching: query)
        let parentCount = results.matchResults.count

        #if DEBUG
        print("[DevicePairingService] ℹ️ Child device currently paired with \(parentCount) parent(s)")
        #endif

        return parentCount
    } catch {
        #if DEBUG
        print("[DevicePairingService] ⚠️ Failed to query parent count: \(error)")
        #endif
        // If we can't determine, allow the pairing (fail open)
        return 0
    }
}
```

**2. Add new error type:**

```swift
enum PairingError: LocalizedError {
    case maxParentsReached
    case shareNotFound
    case invalidQRCode
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .maxParentsReached:
            return "This child device is already paired with the maximum number of parent devices (2). Please unpair from one parent before adding another."
        case .shareNotFound:
            return "Pairing invitation not found or expired."
        case .invalidQRCode:
            return "Invalid QR code. Please scan a valid pairing QR code."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
```

**3. Add UI to show pairing status:**

**File:** `ScreenTimeRewards/Views/ChildMode/ChildPairingView.swift`

**Add before QR scanner:**

```swift
// Show current pairing status
if !pairedParents.isEmpty {
    VStack(alignment: .leading, spacing: 12) {
        Text("Paired Parent Devices (\(pairedParents.count)/2)")
            .font(.headline)

        ForEach(pairedParents, id: \.deviceID) { parent in
            HStack {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text(parent.deviceName ?? "Unknown Parent")
                        .font(.subheadline)
                    Text("Paired on \(parent.registrationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Unpair") {
                    showingUnpairConfirmation = parent
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }

        if pairedParents.count >= 2 {
            Text("Maximum parent devices reached. Unpair from one parent to add another.")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal)
        }
    }
    .padding()
}
```

**4. Add state to track paired parents:**

```swift
@State private var pairedParents: [RegisteredDevice] = []
@State private var showingUnpairConfirmation: RegisteredDevice?

.onAppear {
    Task {
        await loadPairedParents()
    }
}

private func loadPairedParents() async {
    // Query all parent devices this child is paired with
    // ... CloudKit query implementation
}
```

**5. Implement unpair functionality:**

```swift
func unpairFromParent(parentDeviceID: String) async throws {
    #if DEBUG
    print("[DevicePairingService] 🔓 Child unpairing from parent: \(parentDeviceID)")
    #endif

    // Remove child's device record from that parent's shared zone
    // This effectively unpairs

    let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    let sharedDatabase = container.sharedCloudDatabase

    // Find and delete the device record in parent's zone
    let query = CKQuery(
        recordType: "CD_RegisteredDevice",
        predicate: NSPredicate(
            format: "CD_deviceID == %@ AND CD_parentDeviceID == %@",
            DeviceModeManager.shared.deviceID,
            parentDeviceID
        )
    )

    let (results, _) = try await sharedDatabase.records(matching: query)

    for case let .success(record) in results.matchResults.values {
        try await sharedDatabase.deleteRecord(withID: record.id)

        #if DEBUG
        print("[DevicePairingService] ✅ Removed device record from parent's zone")
        #endif
    }
}
```

---

## Summary of Changes

### Priority 1: Critical UX (Do First)
1. **Fix Picker Flicker** - Poor UX, easy fix
2. **Remove AppConfiguration Card** - Feature abandoned, should be removed

### Priority 2: Architectural (Do Next)
3. **Multi-Child Dashboard** - Essential for real-world use
4. **2-Parent Limit** - Important constraint, moderate complexity

### Priority 3: Enhancement (Do After MVP)
5. **Usage Time Accuracy** - Current system works, just not perfect

## Testing Checklist

After implementation:

**Picker Flicker Fix:**
- [ ] Open learning apps picker - no visible flicker
- [ ] Open reward apps picker - no visible flicker
- [ ] Picker opens quickly (no artificial delay)

**Dashboard Updates:**
- [ ] AppConfiguration card removed from parent dashboard
- [ ] Multiple child devices show as separate cards
- [ ] Tapping child card opens detail view
- [ ] Each child's data is separate and accurate

**Pairing Limits:**
- [ ] Child can pair with 1st parent successfully
- [ ] Child can pair with 2nd parent successfully
- [ ] Child cannot pair with 3rd parent (error shown)
- [ ] Child can unpair from parent
- [ ] After unpair, child can pair with new parent

**Usage Time (If Implemented):**
- [ ] 30-second usage is recorded (not lost)
- [ ] 1m 45s usage records 105 seconds (not 60)
- [ ] Session end captures remaining time
- [ ] No duplicate records on parent side

---

**For Dev Agent:**

Implement these fixes in the order listed in Priority sections. Each fix has detailed implementation steps with file locations and code examples. Focus on Priority 1 first for immediate UX improvement.
