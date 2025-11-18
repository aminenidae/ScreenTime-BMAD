# Screen Time Tracking Accuracy Improvements - REVISED PLAN
## Incremental Improvements (Architecture-Safe)

**Date:** 2025-11-13
**Status:** Ready for Implementation
**Priority:** High

---

## Overview

This revised plan addresses missed usage time and tracking inaccuracies through **incremental, non-breaking improvements** to the existing DeviceActivityMonitor extension architecture.

**Key Constraint:** Maintains the current 1:1 event-to-app mapping (one DeviceActivityEvent per app) because Apple's API doesn't expose which specific app triggered a multi-app event.

**User Goal:** Eliminate missed or inaccurate usage time (reported issue).

---

## What Changed from Original Plan

**REMOVED** (architectural conflicts):
- ❌ Phase 2.1: Smart Event Grouping (breaks 1:1 app mapping)
- ❌ Phase 2.2: Tiered Thresholds (exceeds 8-event limit)
- ❌ Phase 6: DeviceActivityReport Extension (too complex for incremental approach)

**KEPT** (safe, incremental):
- ✅ Heartbeat verification
- ✅ Extension health monitoring
- ✅ Gap detection
- ✅ Error recovery mechanisms
- ✅ Diagnostics UI

**MODIFIED**:
- Dual-schedule now duplicates existing 1:1 events (doesn't change mapping)
- Dynamic restart simplified (no background tasks)
- Offline queue works within existing extension

---

## Implementation Phases

### Phase 1: Extension Health Monitoring (HIGH PRIORITY)
**Goal:** Detect when extension stops working

**Files to modify:**
- `ScreenTimeRewards/Shared/ScreenTimeNotifications.swift`
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
- `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Changes:**

#### 1.1 Heartbeat System
Extension writes timestamp every 30 seconds; main app monitors for gaps.

**Add to DeviceActivityMonitorExtension.swift:**
```swift
// MARK: - Heartbeat
private var heartbeatTimer: Timer?

override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)

    // Start heartbeat timer
    heartbeatTimer?.invalidate()
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        self?.writeHeartbeat()
    }
    writeHeartbeat() // Write immediately
}

override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    heartbeatTimer?.invalidate()
}

private func writeHeartbeat() {
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
    shared?.set(Date().timeIntervalSince1970, forKey: "extension_heartbeat")
    shared?.set(getMemoryUsageMB(), forKey: "extension_memory_mb")
}

private func getMemoryUsageMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    guard kerr == KERN_SUCCESS else { return 0 }
    return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
}
```

**Add to ScreenTimeService.swift:**
```swift
// MARK: - Extension Health
private var healthCheckTimer: Timer?

func startHealthMonitoring() {
    healthCheckTimer?.invalidate()
    healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.checkExtensionHealth()
    }
}

func checkExtensionHealth() {
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    guard let lastHeartbeat = shared?.double(forKey: "extension_heartbeat") else {
        print("[ScreenTimeService] ⚠️ No heartbeat found")
        return
    }

    let gap = Date().timeIntervalSince1970 - lastHeartbeat

    if gap > 120 { // 2 minutes
        print("[ScreenTimeService] ⚠️ Extension heartbeat stale (\(Int(gap))s)")

        // Trigger recovery: restart monitoring
        Task {
            await restartMonitoring()
        }

        // Post notification for UI
        NotificationCenter.default.post(
            name: .init("ExtensionUnhealthy"),
            object: nil,
            userInfo: ["gap_seconds": Int(gap)]
        )
    }
}

func getExtensionHealthStatus() -> ExtensionHealthStatus {
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    let lastHeartbeat = shared?.double(forKey: "extension_heartbeat") ?? 0
    let memoryMB = shared?.double(forKey: "extension_memory_mb") ?? 0

    let gap = Date().timeIntervalSince1970 - lastHeartbeat
    let isHealthy = gap < 120 // Less than 2 minutes

    return ExtensionHealthStatus(
        lastHeartbeat: Date(timeIntervalSince1970: lastHeartbeat),
        heartbeatGapSeconds: Int(gap),
        isHealthy: isHealthy,
        memoryUsageMB: memoryMB
    )
}

struct ExtensionHealthStatus {
    let lastHeartbeat: Date
    let heartbeatGapSeconds: Int
    let isHealthy: Bool
    let memoryUsageMB: Double
}
```

#### 1.2 Enhanced Darwin Notifications with Sequence Numbers
Detect missed notifications by checking sequence gaps.

**Modify DeviceActivityMonitorExtension.swift:**
```swift
private func postUsageNotification() {
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    // Increment sequence number
    let currentSeq = shared?.integer(forKey: "notification_sequence") ?? 0
    let nextSeq = currentSeq + 1
    shared?.set(nextSeq, forKey: "notification_sequence")

    print("[Extension] Posting notification seq=\(nextSeq)")

    // Post Darwin notification
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName("com.screentimerewards.usageRecorded" as CFString),
        nil, nil, true
    )
}
```

**Modify ScreenTimeService.swift notification handler:**
```swift
private var lastReceivedSequence: Int = 0

@objc private func handleUsageRecordedNotification() {
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
    let currentSeq = shared?.integer(forKey: "notification_sequence") ?? 0

    let expectedSeq = lastReceivedSequence + 1

    if currentSeq != expectedSeq && lastReceivedSequence > 0 {
        let missedCount = currentSeq - expectedSeq
        print("[ScreenTimeService] ⚠️ Missed \(missedCount) notification(s). Seq: expected=\(expectedSeq), got=\(currentSeq)")

        // Record gap event for analytics
        NotificationCenter.default.post(
            name: .init("MissedNotifications"),
            object: nil,
            userInfo: ["missed_count": missedCount]
        )
    }

    lastReceivedSequence = currentSeq

    // Process usage data...
    Task {
        await processSharedUsageData()
    }
}
```

---

### Phase 2: Extension Error Recovery (HIGH PRIORITY)
**Goal:** Log extension errors and provide recovery mechanisms

**Files to create:**
- `ScreenTimeRewards/Models/ExtensionErrorLog.swift`

**Files to modify:**
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
- `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Changes:**

#### 2.1 Extension Error Logging

**Create ExtensionErrorLog.swift:**
```swift
import Foundation

struct ExtensionErrorEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let eventName: String
    let success: Bool
    let errorDescription: String?
    let memoryUsageMB: Double
    let action: String // "record_usage", "post_notification", etc.

    init(
        eventName: String,
        success: Bool,
        errorDescription: String? = nil,
        memoryUsageMB: Double,
        action: String
    ) {
        self.id = UUID()
        self.timestamp = Date().timeIntervalSince1970
        self.eventName = eventName
        self.success = success
        self.errorDescription = errorDescription
        self.memoryUsageMB = memoryUsageMB
        self.action = action
    }
}

class ExtensionErrorLog {
    private static let logKey = "extension_error_log"
    private static let maxEntries = 100

    static func append(_ entry: ExtensionErrorEntry) {
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

        var entries: [ExtensionErrorEntry] = []
        if let data = shared?.data(forKey: logKey),
           let decoded = try? JSONDecoder().decode([ExtensionErrorEntry].self, from: data) {
            entries = decoded
        }

        entries.append(entry)

        // Keep only most recent entries
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        if let encoded = try? JSONEncoder().encode(entries) {
            shared?.set(encoded, forKey: logKey)
        }
    }

    static func readAll() -> [ExtensionErrorEntry] {
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

        guard let data = shared?.data(forKey: logKey),
              let decoded = try? JSONDecoder().decode([ExtensionErrorEntry].self, from: data) else {
            return []
        }

        return decoded
    }

    static func clear() {
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
        shared?.removeObject(forKey: logKey)
    }

    static func getTodayErrors() -> [ExtensionErrorEntry] {
        let all = readAll()
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

        return all.filter { $0.timestamp >= startOfDay && !$0.success }
    }
}
```

**Modify DeviceActivityMonitorExtension.swift eventDidReachThreshold:**
```swift
override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    #if DEBUG
    print("[Extension] eventDidReachThreshold: \(event.rawValue)")
    #endif

    let memoryMB = getMemoryUsageMB()

    do {
        // Existing recording logic...
        try recordUsageFromEvent(event, activity: activity)

        // Log success
        ExtensionErrorLog.append(ExtensionErrorEntry(
            eventName: event.rawValue,
            success: true,
            errorDescription: nil,
            memoryUsageMB: memoryMB,
            action: "record_usage"
        ))

    } catch {
        // Log failure
        ExtensionErrorLog.append(ExtensionErrorEntry(
            eventName: event.rawValue,
            success: false,
            errorDescription: error.localizedDescription,
            memoryUsageMB: memoryMB,
            action: "record_usage"
        ))

        print("[Extension] ❌ Error recording usage: \(error)")
    }

    // Attempt to post notification even if recording failed
    do {
        postUsageNotification()

        ExtensionErrorLog.append(ExtensionErrorEntry(
            eventName: event.rawValue,
            success: true,
            errorDescription: nil,
            memoryUsageMB: memoryMB,
            action: "post_notification"
        ))

    } catch {
        ExtensionErrorLog.append(ExtensionErrorEntry(
            eventName: event.rawValue,
            success: false,
            errorDescription: error.localizedDescription,
            memoryUsageMB: memoryMB,
            action: "post_notification"
        ))
    }
}
```

#### 2.2 Graceful Degradation on High Memory

**Add to DeviceActivityMonitorExtension.swift:**
```swift
private func checkMemoryPressure() -> Bool {
    let memoryMB = getMemoryUsageMB()
    return memoryMB > 5.0 // Warning threshold: 5 MB (limit is 6 MB)
}

override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    // Check memory first
    if checkMemoryPressure() {
        print("[Extension] ⚠️ High memory usage, using minimal recording path")

        // Log memory warning
        ExtensionErrorLog.append(ExtensionErrorEntry(
            eventName: event.rawValue,
            success: true,
            errorDescription: "High memory pressure, minimal path used",
            memoryUsageMB: getMemoryUsageMB(),
            action: "memory_warning"
        ))

        // Use simplified recording (less logging, no extras)
        recordUsageMinimal(event, activity: activity)
        return
    }

    // Normal recording path...
}

private func recordUsageMinimal(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    // Minimal recording with no extra logging
    guard let mapping = readEventMapping(for: event) else { return }

    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    // Just increment counter, skip detailed persistence
    let key = "minimal_usage_\(mapping.logicalID)"
    let current = shared?.integer(forKey: key) ?? 0
    shared?.set(current + 60, forKey: key) // 1 minute = 60 seconds

    postUsageNotification()
}
```

---

### Phase 3: Gap Detection (MEDIUM PRIORITY)
**Goal:** Detect and alert user when usage data appears to be missing

**Files to modify:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Changes:**

#### 3.1 Gap Detection Algorithm

**Add to ScreenTimeService.swift:**
```swift
// MARK: - Gap Detection

struct UsageGap {
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    let detectionMethod: String // "missing_events", "notification_gap", etc.
}

func detectUsageGaps() -> [UsageGap] {
    var gaps: [UsageGap] = []

    // Method 1: Check notification sequence for gaps
    gaps.append(contentsOf: detectNotificationGaps())

    // Method 2: Check heartbeat for staleness
    gaps.append(contentsOf: detectHeartbeatGaps())

    // Method 3: Check for Core Data session gaps
    gaps.append(contentsOf: detectSessionGaps())

    return gaps.sorted { $0.startTime < $1.startTime }
}

private func detectNotificationGaps() -> [UsageGap] {
    // Check if notification sequence has big jumps
    // (already tracked in handleUsageRecordedNotification)
    return []
}

private func detectHeartbeatGaps() -> [UsageGap] {
    var gaps: [UsageGap] = []

    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
    guard let lastHeartbeat = shared?.double(forKey: "extension_heartbeat") else {
        return []
    }

    let gapSeconds = Date().timeIntervalSince1970 - lastHeartbeat

    // If heartbeat is stale (> 5 min), that's a gap
    if gapSeconds > 300 {
        gaps.append(UsageGap(
            startTime: Date(timeIntervalSince1970: lastHeartbeat),
            endTime: Date(),
            durationMinutes: Int(gapSeconds / 60),
            detectionMethod: "heartbeat_stale"
        ))
    }

    return gaps
}

private func detectSessionGaps() -> [UsageGap] {
    var gaps: [UsageGap] = []

    // Fetch today's usage records from Core Data
    let context = PersistenceController.shared.container.viewContext
    let request = UsageRecord.fetchRequest()

    let startOfDay = Calendar.current.startOfDay(for: Date())
    request.predicate = NSPredicate(format: "timestamp >= %@", startOfDay as NSDate)
    request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

    guard let records = try? context.fetch(request) else { return [] }

    // Check for gaps between consecutive records
    for i in 0..<records.count - 1 {
        let current = records[i]
        let next = records[i + 1]

        guard let currentTime = current.timestamp,
              let nextTime = next.timestamp else { continue }

        let gapSeconds = nextTime.timeIntervalSince(currentTime)

        // Gap > 10 minutes is suspicious (during active tracking)
        if gapSeconds > 600 {
            gaps.append(UsageGap(
                startTime: currentTime,
                endTime: nextTime,
                durationMinutes: Int(gapSeconds / 60),
                detectionMethod: "session_gap"
            ))
        }
    }

    return gaps
}

func shouldAlertUserAboutGaps() -> Bool {
    let gaps = detectUsageGaps()
    let totalLostMinutes = gaps.reduce(0) { $0 + $1.durationMinutes }

    // Alert if > 15 minutes of gaps detected
    return totalLostMinutes > 15
}
```

---

### Phase 4: Dynamic Restart Optimization (MEDIUM PRIORITY)
**Goal:** Optimize monitoring restart timing based on app state

**Files to modify:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift` (lines 956-1005)

**Changes:**

#### 4.1 App State-Aware Restart Interval

**Modify ScreenTimeService.swift:**
```swift
// MARK: - Dynamic Restart

private var restartInterval: TimeInterval {
    // Check app state
    let appState = UIApplication.shared.applicationState

    switch appState {
    case .active:
        // Foreground: Restart every 60 seconds for accuracy
        return 60
    case .background, .inactive:
        // Background: Restart every 300 seconds to save battery
        return 300
    @unknown default:
        return 120 // Default fallback
    }
}

private var lastEventTimestamp: Date?

private func shouldDelayRestart() -> Bool {
    // If we received event recently (< 30 seconds ago), delay restart
    // to avoid interrupting active usage
    guard let lastEvent = lastEventTimestamp else { return false }

    let timeSinceLastEvent = Date().timeIntervalSince(lastEvent)
    return timeSinceLastEvent < 30
}

private func scheduleNextRestart() {
    restartTimer?.invalidate()

    let interval = shouldDelayRestart() ? 30 : restartInterval

    #if DEBUG
    print("[ScreenTimeService] Next restart in \(Int(interval))s (app state: \(UIApplication.shared.applicationState.rawValue))")
    #endif

    restartTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
        Task { @MainActor in
            await self?.restartMonitoring()
        }
    }
}

// Update this in notification handler:
@objc private func handleUsageRecordedNotification() {
    lastEventTimestamp = Date() // Track when events come in

    // ... existing logic
}
```

---

### Phase 5: Diagnostics UI (MEDIUM PRIORITY)
**Goal:** Provide user-facing diagnostics screen for troubleshooting

**Files to create:**
- `ScreenTimeRewards/Views/Settings/TrackingHealthView.swift`

**Files to modify:**
- `ScreenTimeRewards/Views/SettingsTabView.swift`

**Changes:**

#### 5.1 Create TrackingHealthView

**Create TrackingHealthView.swift:**
```swift
import SwiftUI

struct TrackingHealthView: View {
    @State private var healthStatus: ExtensionHealthStatus?
    @State private var errorLog: [ExtensionErrorEntry] = []
    @State private var gaps: [UsageGap] = []
    @State private var isRefreshing = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        List {
            // Extension Health Section
            Section("Extension Status") {
                if let status = healthStatus {
                    HStack {
                        Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(status.isHealthy ? .green : .red)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.isHealthy ? "Healthy" : "Unhealthy")
                                .font(.headline)

                            Text("Last heartbeat: \(formatRelativeTime(seconds: status.heartbeatGapSeconds))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Memory Usage")
                        Spacer()
                        Text(String(format: "%.1f MB / 6 MB", status.memoryUsageMB))
                            .foregroundColor(memoryColor(status.memoryUsageMB))
                    }
                }
            }

            // Data Gaps Section
            Section("Detected Gaps") {
                if gaps.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No significant gaps detected")
                    }
                } else {
                    ForEach(gaps, id: \.startTime) { gap in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(gap.durationMinutes) minute gap")
                                    .font(.headline)
                            }

                            Text("\(gap.startTime.formatted(date: .omitted, time: .shortened)) - \(gap.endTime.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("Detection: \(gap.detectionMethod)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Error Log Section
            Section("Recent Errors") {
                let errors = errorLog.filter { !$0.success }

                if errors.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No errors recorded")
                    }
                } else {
                    ForEach(errors.prefix(10)) { error in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.action)
                                .font(.headline)

                            if let desc = error.errorDescription {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            Text(Date(timeIntervalSince1970: error.timestamp).formatted())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Actions Section
            Section {
                Button("Restart Monitoring") {
                    restartMonitoring()
                }

                Button("Export Diagnostics") {
                    exportDiagnostics()
                }

                Button("Clear Logs", role: .destructive) {
                    clearLogs()
                }
            }
        }
        .navigationTitle("Tracking Health")
        .refreshable {
            await refresh()
        }
        .onAppear {
            loadData()
        }
    }

    private func loadData() {
        healthStatus = ScreenTimeService.shared.getExtensionHealthStatus()
        errorLog = ExtensionErrorLog.readAll()
        gaps = ScreenTimeService.shared.detectUsageGaps()
    }

    private func refresh() async {
        isRefreshing = true
        loadData()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay for UX
        isRefreshing = false
    }

    private func formatRelativeTime(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }

    private func memoryColor(_ memoryMB: Double) -> Color {
        if memoryMB > 5.5 {
            return .red
        } else if memoryMB > 4.5 {
            return .orange
        } else {
            return .green
        }
    }

    private func restartMonitoring() {
        Task {
            await ScreenTimeService.shared.restartMonitoring()
            await refresh()
        }
    }

    private func exportDiagnostics() {
        let report = createDiagnosticsReport()

        let activityVC = UIActivityViewController(
            activityItems: [report],
            applicationActivities: nil
        )

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func createDiagnosticsReport() -> String {
        var report = "Screen Time Rewards - Tracking Diagnostics\n"
        report += "Generated: \(Date().formatted())\n\n"

        report += "=== EXTENSION HEALTH ===\n"
        if let status = healthStatus {
            report += "Status: \(status.isHealthy ? "Healthy" : "Unhealthy")\n"
            report += "Last Heartbeat: \(formatRelativeTime(seconds: status.heartbeatGapSeconds))\n"
            report += "Memory Usage: \(String(format: "%.1f MB", status.memoryUsageMB))\n"
        }
        report += "\n"

        report += "=== DATA GAPS ===\n"
        if gaps.isEmpty {
            report += "No gaps detected\n"
        } else {
            for gap in gaps {
                report += "\(gap.durationMinutes) min gap: \(gap.startTime) - \(gap.endTime) (\(gap.detectionMethod))\n"
            }
        }
        report += "\n"

        report += "=== ERROR LOG ===\n"
        let errors = errorLog.filter { !$0.success }
        if errors.isEmpty {
            report += "No errors recorded\n"
        } else {
            for error in errors.prefix(20) {
                report += "[\(Date(timeIntervalSince1970: error.timestamp).formatted())] \(error.action): \(error.errorDescription ?? "Unknown")\n"
            }
        }

        return report
    }

    private func clearLogs() {
        ExtensionErrorLog.clear()
        loadData()
    }
}
```

#### 5.2 Add to Settings

**Modify SettingsTabView.swift:**
```swift
// Add new navigation link in settings
Section("DIAGNOSTICS") {
    NavigationLink(destination: TrackingHealthView()) {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Tracking Health")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("View diagnostics and troubleshoot issues")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(16)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }
    .buttonStyle(PlainButtonStyle())
}
```

---

### Phase 6: Include Past Activity Flag (LOW PRIORITY)
**Goal:** Catch usage that occurred before monitoring started

**Files to modify:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Changes:**

**Modify event creation in scheduleActivity():**
```swift
// Around line 1020-1030
let event = DeviceActivityEvent(
    applications: Set([application.token]),
    threshold: threshold,
    includesPastActivity: true  // ADD THIS LINE
)
```

This ensures that if a user was already using an app when monitoring started, the first threshold fires immediately with that usage.

---

## Testing Strategy

### Manual Testing (Required Before Release)

**Test 1: Heartbeat Verification**
1. Open app, start monitoring
2. Go to Settings → Tracking Health
3. Verify "Last heartbeat" shows < 1 minute
4. Wait 2 minutes
5. Refresh Tracking Health
6. Verify heartbeat updates (should be < 1 minute again)

**Pass Criteria:** Heartbeat updates every 30-60 seconds

---

**Test 2: Extension Health Detection**
1. Force-quit app (swipe up)
2. Wait 5 minutes (don't use any tracked apps)
3. Reopen app
4. Check Tracking Health
5. Should show warning if heartbeat is stale

**Pass Criteria:** Stale heartbeat detected after > 2 minutes

---

**Test 3: Error Logging**
1. Enable airplane mode (to simulate errors)
2. Use a learning app for 2 minutes
3. Disable airplane mode
4. Open Tracking Health → Recent Errors
5. Verify error logs captured

**Pass Criteria:** Errors logged with timestamps and descriptions

---

**Test 4: Gap Detection**
1. Use learning app for 3 minutes
2. Force-quit Screen Time Rewards app
3. Wait 15 minutes (idle, don't use device)
4. Use learning app for 3 more minutes
5. Reopen Screen Time Rewards
6. Check Tracking Health → Detected Gaps

**Pass Criteria:** 15-minute gap detected and displayed

---

**Test 5: Dynamic Restart**
1. Open app (foreground)
2. Monitor logs: should see "Next restart in 60s"
3. Background app
4. Check logs: should see "Next restart in 300s"

**Pass Criteria:** Restart interval adjusts based on app state

---

**Test 6: Memory Monitoring**
1. Select 8+ apps to track
2. Use apps actively for 30 minutes
3. Check Tracking Health → Memory Usage
4. Verify memory stays < 5 MB

**Pass Criteria:** Memory under warning threshold

---

**Test 7: Diagnostics Export**
1. Create some usage data and errors
2. Go to Tracking Health
3. Tap "Export Diagnostics"
4. Share to email or save

**Pass Criteria:** Full diagnostics report generated

---

## Rollout Plan

### Week 1: Core Health Monitoring
**Implement:**
- Phase 1.1: Heartbeat system
- Phase 1.2: Sequence numbers
- Phase 2.1: Error logging

**Test:**
- Manual tests 1, 2, 3
- Monitor for 3 days on developer devices

**Deploy:**
- Internal TestFlight build

---

### Week 2: Recovery & Detection
**Implement:**
- Phase 2.2: Graceful degradation
- Phase 3.1: Gap detection
- Phase 4.1: Dynamic restart

**Test:**
- Manual tests 4, 5, 6
- Beta test with 5-10 users

**Deploy:**
- Expand beta to 20 users

---

### Week 3: UI & Polish
**Implement:**
- Phase 5.1: TrackingHealthView
- Phase 6: Include past activity flag

**Test:**
- Manual test 7
- Full regression suite
- Battery impact test

**Deploy:**
- Expand beta to 50 users
- Monitor for 7 days

---

### Week 4: Production Release
**Deliverables:**
- Bug fixes from beta
- Documentation updates
- Release notes

**Deploy:**
- Submit to App Store
- Gradual rollout (10% → 50% → 100%)

---

## Success Metrics

**Primary:**
- Extension heartbeat stale rate: < 2% of checks
- Error log entries (failures): < 1% of total events
- User reports of "missed usage": 90% reduction

**Secondary:**
- Gap detection alerts: < 5% of user sessions
- Memory usage: < 5 MB average
- Battery impact: < 5% daily drain

**Monitoring:**
- Weekly report on extension health status
- Alert if error rate > 5%
- Alert if average heartbeat gap > 3 minutes

---

## File Structure

```
ScreenTimeRewards/
  Models/
    ExtensionErrorLog.swift (NEW)
  Services/
    ScreenTimeService.swift (MODIFIED - add health monitoring, gap detection)
  Views/
    Settings/
      TrackingHealthView.swift (NEW)
      SettingsTabView.swift (MODIFIED - add navigation link)
  Shared/
    ScreenTimeNotifications.swift (MODIFIED - add sequence numbers)

ScreenTimeActivityExtension/
  DeviceActivityMonitorExtension.swift (MODIFIED - add heartbeat, error logging)
```

---

## Estimated Effort

**Development:**
- Phase 1: 2 days (heartbeat + sequence numbers)
- Phase 2: 2 days (error logging + graceful degradation)
- Phase 3: 1 day (gap detection)
- Phase 4: 1 day (dynamic restart)
- Phase 5: 2 days (TrackingHealthView UI)
- Phase 6: 0.5 days (include past activity)

**Testing:**
- Manual testing: 2 days
- Beta period: 7-14 days

**Total: ~3 weeks** (8.5 dev days + testing/iteration)

---

## Risk Assessment

**Low Risk:**
- Heartbeat system (simple timestamp write/read)
- Error logging (observational only)
- TrackingHealthView (read-only UI)

**Medium Risk:**
- Dynamic restart timing (must test battery impact)
- Gap detection (false positives could annoy users)

**Mitigation:**
- Feature flags for gradual rollout
- High threshold for gap alerts (> 15 min only)
- Extensive beta testing period

---

## References

1. Original plan: `docs/TRACKING_ACCURACY_IMPROVEMENTS.md`
2. Current implementation: `ScreenTimeRewards/Services/ScreenTimeService.swift`
3. Extension: `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
4. Technical report: `docs/Maximizing Tracking Accuracy.pdf`

---

**Document Version:** 2.0 (Revised)
**Date:** 2025-11-13
**Status:** Ready for Implementation
**Approval:** Pending

---

**END OF REVISED IMPLEMENTATION PLAN**
