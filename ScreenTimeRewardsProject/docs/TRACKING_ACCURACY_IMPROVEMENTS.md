# Screen Time Tracking Accuracy Improvements - Implementation Plan

## Overview
This plan implements recommendations from "Maximizing Tracking Accuracy.pdf" with a focus on eliminating missed usage events and maximizing tracking accuracy. The implementation will enhance the existing DeviceActivityMonitor extension and add robust error recovery mechanisms.

## Goals
1. **Primary:** Eliminate missed or inaccurate usage time (reported user issue)
2. **Secondary:** Implement best practices from technical report
3. **Future:** Add DeviceActivityReport extension for better UI (low priority)

## Implementation Phases

### Phase 1: Enhanced Event Monitoring (HIGH PRIORITY)
**Problem:** Users report missed usage time, likely due to:
- One-time event firing limitation
- Gaps during monitoring restart (2-minute intervals)
- Extension crashes or failures going undetected

**Solution:** Implement redundant tracking with multiple safety nets

**Files to modify:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift`
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
- `ScreenTimeRewards/Shared/UsagePersistence.swift`

**Changes:**

#### 1.1 Dual-Schedule Architecture (recommended in report for reliability)
- Create two overlapping schedules offset by 30 seconds
- Schedule A: 00:00:00 - 23:59:59 with 1-min thresholds
- Schedule B: 00:00:30 - 23:59:29 with 1-min thresholds
- If one misses an event, the other catches it
- Deduplication logic in recording layer

**Implementation:**
```swift
// In ScreenTimeService.swift
private func scheduleMonitoringWithRedundancy() {
    let scheduleA = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
        repeats: true
    )

    let scheduleB = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0, second: 30),
        intervalEnd: DateComponents(hour: 23, minute: 59, second: 29),
        repeats: true
    )

    // Create events for both schedules
    // Add deduplication in recordUsage() using timestamp proximity check
}
```

#### 1.2 Heartbeat Verification System
- Extension writes heartbeat timestamp every 30 seconds
- Main app monitors heartbeat and detects gaps
- If gap > 2 minutes detected, trigger recovery logic
- Recovery: Schedule immediate one-time interval to force event

**Implementation:**
```swift
// In DeviceActivityMonitorExtension.swift
private func writeHeartbeat() {
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
    shared?.set(Date().timeIntervalSince1970, forKey: "extension_heartbeat")
}

// In ScreenTimeService.swift
func checkExtensionHealth() {
    guard let lastHeartbeat = userDefaults.double(forKey: "extension_heartbeat") else { return }
    let gap = Date().timeIntervalSince1970 - lastHeartbeat

    if gap > 120 { // 2 minutes
        triggerRecoverySchedule()
    }
}
```

#### 1.3 Extension Health Monitoring
- Add extension error logging to shared UserDefaults
- Main app reads error log on launch and after notifications
- Detect crashes/failures and alert user to restart device if needed

**Implementation:**
```swift
// Create ExtensionHealthLog in shared UserDefaults
struct ExtensionHealthLog: Codable {
    let timestamp: TimeInterval
    let eventType: String // "success", "error", "crash"
    let details: String
    let memoryUsage: Int64? // bytes
}

// Extension logs all events
// Main app checks log periodically
```

#### 1.4 Enhanced Darwin Notifications
- Add sequence numbers to detect missed notifications
- Main app compares expected vs received sequence
- Request re-sync from shared storage if gaps detected

**Implementation:**
```swift
// Add sequence number to notification payload
var notificationSequence: Int = 0

func postUsageNotification() {
    notificationSequence += 1
    userDefaults.set(notificationSequence, forKey: "last_notification_seq")
    userDefaults.set(usageData, forKey: "last_notification_data")

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName("com.screentimerewards.usageRecorded" as CFString),
        nil, nil, true
    )
}

// Main app checks sequence on receive
func handleNotification() {
    let expected = lastReceivedSeq + 1
    let actual = userDefaults.integer(forKey: "last_notification_seq")

    if actual != expected {
        // Missed notifications - re-sync from shared storage
        syncAllPendingUsage()
    }
    lastReceivedSeq = actual
}
```

### Phase 2: Improved Threshold Strategy (MEDIUM PRIORITY)
**Problem:** Report recommends frequent thresholds but warns about the ~8 event limit

**Solution:** Optimize event scheduling within Apple's limits

**Files to modify:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift` (lines 1007-1041)

**Changes:**

#### 2.1 Smart Event Grouping
- Current: One event per app (breaks at ~8 apps)
- New: Group apps by category (Learning, Reward, Other)
- Create category-level events with 1-minute thresholds
- Each category event tracks all apps in that category
- Supports unlimited apps within 3 event limit

**Implementation:**
```swift
// Group apps by category instead of individual events
func createCategoryEvents() -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

    // Learning apps category event
    let learningApps = applications.filter { $0.category == .learning }
    let learningSelection = FamilyActivitySelection(
        applicationTokens: Set(learningApps.map { $0.token })
    )
    events[.init("learning_1min")] = DeviceActivityEvent(
        applications: learningSelection.applicationTokens,
        threshold: DateComponents(minute: 1)
    )

    // Reward apps category event
    let rewardApps = applications.filter { $0.category == .reward }
    let rewardSelection = FamilyActivitySelection(
        applicationTokens: Set(rewardApps.map { $0.token })
    )
    events[.init("reward_1min")] = DeviceActivityEvent(
        applications: rewardSelection.applicationTokens,
        threshold: DateComponents(minute: 1)
    )

    return events
}
```

#### 2.2 Tiered Threshold Implementation
- First threshold: 1 minute (catch quick switches)
- Second threshold: 5 minutes (accumulate active usage)
- Third threshold: 15 minutes (long session detection)
- Each fires independently, providing multiple data points

**Implementation:**
```swift
// Create multiple thresholds per category
events[.init("learning_1min")] = DeviceActivityEvent(
    applications: learningSelection.applicationTokens,
    threshold: DateComponents(minute: 1)
)
events[.init("learning_5min")] = DeviceActivityEvent(
    applications: learningSelection.applicationTokens,
    threshold: DateComponents(minute: 5)
)
events[.init("learning_15min")] = DeviceActivityEvent(
    applications: learningSelection.applicationTokens,
    threshold: DateComponents(minute: 15)
)
```

#### 2.3 Include Past Activity Flag
- Set `includesPastActivity: true` on first threshold
- Forces immediate event if usage exists at interval start
- Prevents missing usage that occurred before monitoring started

**Implementation:**
```swift
let event = DeviceActivityEvent(
    applications: selection.applicationTokens,
    threshold: DateComponents(minute: 1),
    includesPastActivity: true  // Fire immediately if usage exists
)
```

### Phase 3: Dynamic Restart Optimization (MEDIUM PRIORITY)
**Problem:** Fixed 2-minute restart is arbitrary and may miss usage during restart gap

**Solution:** Intelligent restart timing based on app state

**Files to modify:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift` (lines 956-1005)

**Changes:**

#### 3.1 App State-Aware Restart
```swift
private var restartInterval: TimeInterval {
    switch UIApplication.shared.applicationState {
    case .active:
        return 60  // Foreground: Restart every 60 seconds (active monitoring)
    case .background, .inactive:
        return 300 // Background: Restart every 300 seconds (battery saving)
    @unknown default:
        return 120
    }
}
```

#### 3.2 Usage-Based Delay
- Monitor recent event frequency
- If events fired in last 30 seconds, delay restart by 30s
- Prevents restart during active usage period
- Reduces chance of missing mid-session events

**Implementation:**
```swift
private var lastEventTimestamp: Date?

func shouldDelayRestart() -> Bool {
    guard let lastEvent = lastEventTimestamp else { return false }
    let timeSinceLastEvent = Date().timeIntervalSince(lastEvent)
    return timeSinceLastEvent < 30  // Active usage in last 30 seconds
}

func scheduleRestart() {
    if shouldDelayRestart() {
        // Delay restart by 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.restartMonitoring()
        }
    } else {
        restartMonitoring()
    }
}
```

#### 3.3 Background Task Integration
- Use BGProcessingTask for background restarts
- Ensures restart happens even if app is suspended
- Register background task in Info.plist

**Implementation:**
```swift
// Register background task
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.screentimerewards.monitoring-restart",
    using: nil
) { task in
    self.handleBackgroundRestart(task: task as! BGProcessingTask)
}

// Schedule background restart
func scheduleBackgroundRestart() {
    let request = BGProcessingTaskRequest(
        identifier: "com.screentimerewards.monitoring-restart"
    )
    request.earliestBeginDate = Date(timeIntervalSinceNow: restartInterval)

    try? BGTaskScheduler.shared.submit(request)
}

// Add to Info.plist:
// <key>BGTaskSchedulerPermittedIdentifiers</key>
// <array>
//     <string>com.screentimerewards.monitoring-restart</string>
// </array>
```

### Phase 4: Session Continuity & Recovery (HIGH PRIORITY)
**Problem:** Extension operates independently; if it fails, main app may never know

**Solution:** Implement robust failure detection and recovery

**Files to create/modify:**
- `ScreenTimeRewards/Models/UsageRecoveryLog.swift` (NEW)
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`

**Changes:**

#### 4.1 Extension Recovery Log
- Extension writes to App Group shared file: `recovery_log.json`
- Log entries: `{ timestamp, eventName, success, errorDescription }`
- Main app reads log periodically and on notifications

**Create UsageRecoveryLog.swift:**
```swift
import Foundation

struct RecoveryLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let eventName: String
    let success: Bool
    let errorDescription: String?
    let attemptedAction: String  // "record_usage", "post_notification", etc.
    let memoryUsageBytes: Int64?
}

class UsageRecoveryLog {
    private static let logFileName = "recovery_log.json"

    static func append(entry: RecoveryLogEntry) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.screentimerewards.shared"
        ) else { return }

        let logURL = containerURL.appendingPathComponent(logFileName)

        var entries: [RecoveryLogEntry] = []
        if let data = try? Data(contentsOf: logURL),
           let decoded = try? JSONDecoder().decode([RecoveryLogEntry].self, from: data) {
            entries = decoded
        }

        entries.append(entry)

        // Keep only last 100 entries
        if entries.count > 100 {
            entries = Array(entries.suffix(100))
        }

        if let encoded = try? JSONEncoder().encode(entries) {
            try? encoded.write(to: logURL)
        }
    }

    static func readAll() -> [RecoveryLogEntry] {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.screentimerewards.shared"
        ) else { return [] }

        let logURL = containerURL.appendingPathComponent(logFileName)

        guard let data = try? Data(contentsOf: logURL),
              let decoded = try? JSONDecoder().decode([RecoveryLogEntry].self, from: data) else {
            return []
        }

        return decoded
    }

    static func clear() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.screentimerewards.shared"
        ) else { return }

        let logURL = containerURL.appendingPathComponent(logFileName)
        try? FileManager.default.removeItem(at: logURL)
    }
}
```

**Modify DeviceActivityMonitorExtension.swift:**
```swift
override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    do {
        // Existing recording logic...
        try recordUsageFromEvent(event, activity: activity)

        // Log success
        UsageRecoveryLog.append(entry: RecoveryLogEntry(
            id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            eventName: event.rawValue,
            success: true,
            errorDescription: nil,
            attemptedAction: "record_usage",
            memoryUsageBytes: getMemoryUsage()
        ))

    } catch {
        // Log failure
        UsageRecoveryLog.append(entry: RecoveryLogEntry(
            id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            eventName: event.rawValue,
            success: false,
            errorDescription: error.localizedDescription,
            attemptedAction: "record_usage",
            memoryUsageBytes: getMemoryUsage()
        ))
    }
}

private func getMemoryUsage() -> Int64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    guard kerr == KERN_SUCCESS else { return 0 }
    return Int64(info.resident_size)
}
```

#### 4.2 Gap Detection Algorithm
- Compare expected intervals vs recorded intervals
- Expected: If monitoring started at 12:00, expect events at 12:01, 12:02, 12:03...
- If gap > 5 minutes detected, mark as "potential data loss"
- Alert: Show in-app banner "Some usage may not have been tracked"

**Implementation in ScreenTimeService.swift:**
```swift
struct UsageGap {
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    let affectedApps: [String]
}

func detectUsageGaps() -> [UsageGap] {
    var gaps: [UsageGap] = []

    // Get all usage records for today, sorted by timestamp
    let records = fetchTodayUsageRecords().sorted { $0.timestamp < $1.timestamp }

    for i in 0..<records.count - 1 {
        let current = records[i]
        let next = records[i + 1]

        let gapDuration = next.timestamp.timeIntervalSince(current.timestamp)

        // Gap > 5 minutes is suspicious
        if gapDuration > 300 {
            gaps.append(UsageGap(
                startTime: current.timestamp,
                endTime: next.timestamp,
                durationMinutes: Int(gapDuration / 60),
                affectedApps: [current.logicalID, next.logicalID]
            ))
        }
    }

    return gaps
}

// Check for gaps on app launch and periodically
func checkForDataLoss() {
    let gaps = detectUsageGaps()

    if !gaps.isEmpty {
        let totalLostMinutes = gaps.reduce(0) { $0 + $1.durationMinutes }

        if totalLostMinutes > 10 {
            // Show alert to user
            NotificationCenter.default.post(
                name: .dataLossDetected,
                object: nil,
                userInfo: ["gaps": gaps, "totalMinutes": totalLostMinutes]
            )
        }
    }
}
```

#### 4.3 Offline Queue
- Extension maintains queue of failed writes
- Retries on next event callback
- Main app processes queue on launch

**Implementation:**
```swift
// In DeviceActivityMonitorExtension.swift
private var failedWrites: [(eventName: String, data: Data, timestamp: TimeInterval)] = []

func recordUsageFromEvent(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    // Try to process failed writes first
    retryFailedWrites()

    do {
        // Normal recording logic
        try performRecording(event, activity)
    } catch {
        // Queue for retry
        if let data = try? encodeEventData(event, activity) {
            failedWrites.append((event.rawValue, data, Date().timeIntervalSince1970))
        }
    }
}

func retryFailedWrites() {
    var remainingFails: [(String, Data, TimeInterval)] = []

    for (eventName, data, timestamp) in failedWrites {
        do {
            try processQueuedWrite(data)
            print("[Extension] Successfully retried write for \(eventName)")
        } catch {
            // Still failing, keep in queue
            remainingFails.append((eventName, data, timestamp))
        }
    }

    failedWrites = remainingFails
}
```

#### 4.4 Clock Sync Protection
- Validate timestamps against monotonic clock
- Detect time zone changes or clock adjustments
- Recalculate usage if system time jumped

**Implementation:**
```swift
import QuartzCore

class MonotonicClock {
    private static var bootTimeOffset: TimeInterval?

    static func now() -> TimeInterval {
        return CACurrentMediaTime()
    }

    static func detectClockJump(systemTime: Date, monotonicTime: TimeInterval) -> Bool {
        // Compare system time vs monotonic time
        // If difference > 60 seconds, clock was adjusted
        let expectedSystemTime = Date(timeIntervalSince1970: bootTimeEstimate + monotonicTime)
        let diff = abs(systemTime.timeIntervalSince(expectedSystemTime))

        return diff > 60
    }
}

// In recording logic:
func recordUsage(timestamp: Date) {
    let monotonicNow = MonotonicClock.now()

    if MonotonicClock.detectClockJump(systemTime: timestamp, monotonicTime: monotonicNow) {
        // Clock was adjusted - use monotonic time instead
        UsageRecoveryLog.append(entry: RecoveryLogEntry(
            id: UUID(),
            timestamp: monotonicNow,
            eventName: "clock_adjustment_detected",
            success: true,
            errorDescription: "System time jumped, using monotonic clock",
            attemptedAction: "record_usage",
            memoryUsageBytes: nil
        ))
    }
}
```

### Phase 5: Enhanced Error Handling (HIGH PRIORITY)
**Problem:** Report warns about sandbox crashes, memory limits, and silent failures

**Solution:** Comprehensive error handling and logging

**Files to modify:**
- `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift`
- `ScreenTimeRewards/Services/ScreenTimeService.swift`
- `ScreenTimeRewards/Views/Settings/TrackingHealthView.swift` (NEW)

**Changes:**

#### 5.1 Extension Memory Monitoring
- Track memory usage in extension (6 MB limit warned in report)
- If approaching limit, defer non-critical operations
- Use lightweight data structures only

**Implementation:**
```swift
private func checkMemoryPressure() -> Bool {
    let memoryUsage = getMemoryUsage()
    let memoryLimitMB: Int64 = 6 * 1024 * 1024  // 6 MB
    let warningThresholdMB: Int64 = 5 * 1024 * 1024  // 5 MB

    if memoryUsage > warningThresholdMB {
        print("[Extension] ⚠️ Memory usage high: \(memoryUsage / 1024 / 1024) MB")

        // Clear any cached data
        clearNonEssentialCaches()

        return true
    }

    return false
}

override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    // Check memory first
    if checkMemoryPressure() {
        // Use minimal recording path
        recordUsageMinimal(event, activity)
    } else {
        // Full recording with detailed logging
        recordUsageFull(event, activity)
    }
}
```

#### 5.2 Graceful Degradation
- If UserDefaults write fails, write to emergency fallback file
- If notification post fails, set flag for main app to poll
- Never crash on errors; log and continue

**Implementation:**
```swift
func recordUsageWithFallback(data: Data) {
    // Try primary storage (UserDefaults)
    do {
        try writeToPrimaryStorage(data)
    } catch {
        // Fallback to file storage
        do {
            try writeToFallbackFile(data)
            print("[Extension] Wrote to fallback file")
        } catch {
            // Last resort: Set flag for main app to investigate
            UserDefaults(suiteName: "group.com.screentimerewards.shared")?
                .set(true, forKey: "emergency_flag")
            print("[Extension] ❌ All storage failed, set emergency flag")
        }
    }
}

func writeToFallbackFile(_ data: Data) throws {
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.screentimerewards.shared"
    ) else { throw NSError(domain: "NoContainer", code: 1) }

    let fallbackURL = containerURL.appendingPathComponent("fallback_\(Date().timeIntervalSince1970).json")
    try data.write(to: fallbackURL)
}
```

#### 5.3 Comprehensive Logging
```swift
enum LogSeverity: String, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case critical = "CRITICAL"
}

struct LogEntry: Codable {
    let timestamp: TimeInterval
    let severity: LogSeverity
    let component: String
    let message: String
    let metadata: [String: String]?
}

class ExtensionLogger {
    private static let maxLogEntries = 500
    private static let logKey = "extension_logs"

    static func log(_ severity: LogSeverity, component: String, message: String, metadata: [String: String]? = nil) {
        let entry = LogEntry(
            timestamp: Date().timeIntervalSince1970,
            severity: severity,
            component: component,
            message: message,
            metadata: metadata
        )

        appendLog(entry)

        // Also print to console for debugging
        print("[\(severity.rawValue)] [\(component)] \(message)")
    }

    private static func appendLog(_ entry: LogEntry) {
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

        var logs: [LogEntry] = []
        if let data = shared?.data(forKey: logKey),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            logs = decoded
        }

        logs.append(entry)

        // Keep only most recent entries
        if logs.count > maxLogEntries {
            logs = Array(logs.suffix(maxLogEntries))
        }

        if let encoded = try? JSONEncoder().encode(logs) {
            shared?.set(encoded, forKey: logKey)
        }
    }
}

// Usage:
ExtensionLogger.log(.info, component: "EventHandler", message: "Threshold reached", metadata: [
    "eventName": event.rawValue,
    "activityName": activity.rawValue
])
```

#### 5.4 Main App Diagnostics - TrackingHealthView.swift

**Create new file:**
```swift
import SwiftUI

struct TrackingHealthView: View {
    @State private var healthStatus: HealthStatus?
    @State private var recoveryLogs: [RecoveryLogEntry] = []
    @State private var extensionLogs: [LogEntry] = []
    @State private var detectedGaps: [UsageGap] = []

    var body: some View {
        List {
            Section("Extension Health") {
                if let status = healthStatus {
                    HStack {
                        Text("Last Heartbeat")
                        Spacer()
                        Text(status.lastHeartbeat, style: .relative)
                            .foregroundColor(status.heartbeatHealthy ? .green : .red)
                    }

                    HStack {
                        Text("Event Count (Today)")
                        Spacer()
                        Text("\(status.todayEventCount)")
                    }

                    HStack {
                        Text("Error Count")
                        Spacer()
                        Text("\(status.errorCount)")
                            .foregroundColor(status.errorCount > 0 ? .orange : .green)
                    }

                    HStack {
                        Text("Memory Usage")
                        Spacer()
                        Text("\(status.memoryUsageMB) MB / 6 MB")
                            .foregroundColor(status.memoryUsageMB > 5 ? .red : .green)
                    }
                }
            }

            Section("Detected Data Gaps") {
                if detectedGaps.isEmpty {
                    Text("No gaps detected ✓")
                        .foregroundColor(.green)
                } else {
                    ForEach(detectedGaps, id: \.startTime) { gap in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(gap.durationMinutes) minute gap")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Text("\(gap.startTime.formatted()) - \(gap.endTime.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Recovery Log") {
                if recoveryLogs.isEmpty {
                    Text("No issues recorded")
                        .foregroundColor(.green)
                } else {
                    ForEach(recoveryLogs.prefix(20)) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: log.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(log.success ? .green : .red)
                                Text(log.eventName)
                                    .font(.headline)
                            }
                            if let error = log.errorDescription {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            Text(Date(timeIntervalSince1970: log.timestamp).formatted())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Extension Logs") {
                ForEach(extensionLogs.prefix(30), id: \.timestamp) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            severityBadge(log.severity)
                            Text(log.component)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(log.message)
                            .font(.caption)
                        Text(Date(timeIntervalSince1970: log.timestamp).formatted())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button("Export Diagnostics") {
                    exportDiagnostics()
                }

                Button("Clear Logs", role: .destructive) {
                    clearAllLogs()
                }
            }
        }
        .navigationTitle("Tracking Health")
        .onAppear {
            loadHealthData()
        }
    }

    private func severityBadge(_ severity: LogSeverity) -> some View {
        Text(severity.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor(severity).opacity(0.2))
            .foregroundColor(severityColor(severity))
            .cornerRadius(4)
    }

    private func severityColor(_ severity: LogSeverity) -> Color {
        switch severity {
        case .debug: return .blue
        case .info: return .green
        case .warn: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }

    private func loadHealthData() {
        // Load from UserDefaults and services
        healthStatus = calculateHealthStatus()
        recoveryLogs = UsageRecoveryLog.readAll()
        extensionLogs = readExtensionLogs()
        detectedGaps = ScreenTimeService.shared.detectUsageGaps()
    }

    private func calculateHealthStatus() -> HealthStatus {
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

        let lastHeartbeat = shared?.double(forKey: "extension_heartbeat") ?? 0
        let heartbeatDate = Date(timeIntervalSince1970: lastHeartbeat)
        let heartbeatHealthy = Date().timeIntervalSince(heartbeatDate) < 300 // 5 minutes

        let logs = UsageRecoveryLog.readAll()
        let todayLogs = logs.filter { Date(timeIntervalSince1970: $0.timestamp).isToday }

        return HealthStatus(
            lastHeartbeat: heartbeatDate,
            heartbeatHealthy: heartbeatHealthy,
            todayEventCount: todayLogs.count,
            errorCount: todayLogs.filter { !$0.success }.count,
            memoryUsageMB: (logs.last?.memoryUsageBytes ?? 0) / 1024 / 1024
        )
    }

    private func readExtensionLogs() -> [LogEntry] {
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
        guard let data = shared?.data(forKey: "extension_logs"),
              let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return decoded.reversed()  // Most recent first
    }

    private func exportDiagnostics() {
        // Create diagnostics report
        let report = """
        Screen Time Rewards - Tracking Diagnostics
        Generated: \(Date().formatted())

        === HEALTH STATUS ===
        \(healthStatus.map { String(describing: $0) } ?? "N/A")

        === RECOVERY LOG ===
        \(recoveryLogs.map { "\($0.timestamp): \($0.eventName) - \($0.success ? "Success" : "Failed")" }.joined(separator: "\n"))

        === EXTENSION LOGS ===
        \(extensionLogs.map { "[\($0.severity.rawValue)] \($0.component): \($0.message)" }.joined(separator: "\n"))

        === DATA GAPS ===
        \(detectedGaps.map { "\($0.durationMinutes) min gap: \($0.startTime) - \($0.endTime)" }.joined(separator: "\n"))
        """

        // Share sheet
        let activityVC = UIActivityViewController(
            activityItems: [report],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func clearAllLogs() {
        UsageRecoveryLog.clear()
        let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")
        shared?.removeObject(forKey: "extension_logs")
        loadHealthData()
    }
}

struct HealthStatus {
    let lastHeartbeat: Date
    let heartbeatHealthy: Bool
    let todayEventCount: Int
    let errorCount: Int
    let memoryUsageMB: Int64
}

extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}
```

### Phase 6: DeviceActivityReport Extension (LOW PRIORITY - FUTURE)
**Problem:** App shows "Unknown App" names due to privacy limitations

**Solution:** Add privileged extension to display real app info

**Note:** This is marked as LOW PRIORITY per user request. Implement only after Phases 1-5 are complete and tested.

**Files to create:**
- `ScreenTimeReportExtension/` (NEW target)
- `ScreenTimeReportExtension/DeviceActivityReportExtension.swift`
- `ScreenTimeReportExtension/TotalActivityView.swift`
- `ScreenTimeReportExtension/Info.plist`
- `ScreenTimeReportExtension/ScreenTimeReportExtension.entitlements`

**Implementation Steps:**

#### 6.1 Create Extension Target
1. In Xcode: File → New → Target → DeviceActivityReport Extension
2. Name: "ScreenTimeReportExtension"
3. Add to same App Group: `group.com.screentimerewards.shared`
4. Add Family Controls entitlement

#### 6.2 Report View Implementation

**TotalActivityView.swift:**
```swift
import SwiftUI
import DeviceActivity

struct TotalActivityView: View {
    let context: DeviceActivityReport.Context
    let filter: DeviceActivityFilter

    var body: some View {
        DeviceActivityReport(context: context, filter: filter)
    }
}

@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReportScene { context in
            TotalActivityView(context: context, filter: context.filter)
        }
    }
}

struct TotalActivityReportScene: DeviceActivityReportScene {
    let content: (DeviceActivityReport.Context) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TotalActivityView {
        // Access real app names and icons here
        let totalDuration = await data.reduce(0) { total, activity in
            total + activity.totalActivityDuration
        }

        return content(.init(totalDuration: totalDuration))
    }
}
```

**Note:** Detailed implementation deferred to Phase 6 execution.

#### 6.3 Integrate with Main App
```swift
// In main app, display report view:
import DeviceActivity

struct UsageReportView: View {
    @State private var context: DeviceActivityReport.Context = .init(rawValue: "usage")
    @State private var filter = DeviceActivityFilter(
        segment: .daily(during: DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Date()))
    )

    var body: some View {
        VStack {
            Text("Today's Usage")
                .font(.title)

            DeviceActivityReport(context, filter: filter)
                .frame(height: 400)
        }
    }
}
```

---

## Testing Strategy

### Unit Tests

**Test Coverage Required:**

1. **Deduplication Logic**
```swift
func testDualScheduleDeduplication() {
    // Given: Two events with same timestamp from different schedules
    let eventA = UsageEvent(timestamp: Date(), schedule: "A", appID: "learning1")
    let eventB = UsageEvent(timestamp: Date(), schedule: "B", appID: "learning1")

    // When: Both recorded
    service.recordUsage(eventA)
    service.recordUsage(eventB)

    // Then: Only one entry should exist
    XCTAssertEqual(service.usageRecords.count, 1)
}
```

2. **Gap Detection**
```swift
func testGapDetection() {
    // Given: Usage records with 10-minute gap
    let record1 = UsageRecord(timestamp: Date(), duration: 60)
    let record2 = UsageRecord(timestamp: Date().addingTimeInterval(660), duration: 60)

    // When: Detecting gaps
    let gaps = service.detectUsageGaps(records: [record1, record2])

    // Then: Should detect 10-minute gap
    XCTAssertEqual(gaps.count, 1)
    XCTAssertEqual(gaps.first?.durationMinutes, 10)
}
```

3. **Recovery Queue**
```swift
func testOfflineQueue() {
    // Given: Extension with failed write
    let extension = MockExtension()
    extension.simulateWriteFailure()

    // When: Recording usage
    extension.recordUsage(appID: "test", duration: 60)

    // Then: Should queue for retry
    XCTAssertEqual(extension.failedWrites.count, 1)

    // When: Write succeeds on retry
    extension.simulateWriteSuccess()
    extension.retryFailedWrites()

    // Then: Queue should be empty
    XCTAssertEqual(extension.failedWrites.count, 0)
}
```

4. **Category Grouping**
```swift
func testCategoryEventGrouping() {
    // Given: 15 apps (10 learning, 5 reward)
    let apps = createMockApps(learning: 10, reward: 5)

    // When: Creating events
    let events = service.createCategoryEvents(apps: apps)

    // Then: Should have 2 category events (under 8-event limit)
    XCTAssertEqual(events.count, 2)
    XCTAssertTrue(events.keys.contains("learning_1min"))
    XCTAssertTrue(events.keys.contains("reward_1min"))
}
```

### Integration Tests

1. **Extension-to-Main-App Communication**
```swift
func testExtensionNotification() {
    let expectation = XCTestExpectation(description: "Receive Darwin notification")

    // Setup notification observer in main app
    let observer = CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        nil,
        { _, _, _, _, _ in expectation.fulfill() },
        "com.screentimerewards.usageRecorded" as CFString,
        nil,
        .deliverImmediately
    )

    // Extension posts notification
    mockExtension.postUsageNotification()

    wait(for: [expectation], timeout: 2.0)
}
```

2. **Heartbeat Verification**
```swift
func testHeartbeatMonitoring() {
    // Given: Extension writing heartbeat
    mockExtension.startHeartbeat()

    // When: Main app checks health
    sleep(1)
    var healthy = service.isExtensionHealthy()
    XCTAssertTrue(healthy)

    // When: Heartbeat stops
    mockExtension.stopHeartbeat()
    sleep(3)  // Wait > 2 minutes threshold
    healthy = service.isExtensionHealthy()

    // Then: Should detect unhealthy state
    XCTAssertFalse(healthy)
}
```

3. **Restart Timing**
```swift
func testDynamicRestartTiming() {
    // Given: App in foreground
    service.simulateAppState(.active)

    // When: Getting restart interval
    var interval = service.restartInterval

    // Then: Should use short interval
    XCTAssertEqual(interval, 60)

    // Given: App in background
    service.simulateAppState(.background)

    // When: Getting restart interval
    interval = service.restartInterval

    // Then: Should use long interval
    XCTAssertEqual(interval, 300)
}
```

4. **Error Recovery**
```swift
func testErrorRecoveryFlow() {
    // Given: Extension with persistent error
    mockExtension.simulatePersistentError()

    // When: Multiple recording attempts
    for _ in 0..<5 {
        mockExtension.recordUsage(appID: "test", duration: 60)
    }

    // Then: All failures should be logged
    let logs = UsageRecoveryLog.readAll()
    XCTAssertEqual(logs.filter { !$0.success }.count, 5)

    // When: Error resolved
    mockExtension.simulateErrorResolved()
    mockExtension.recordUsage(appID: "test", duration: 60)

    // Then: Should log success
    let latestLogs = UsageRecoveryLog.readAll()
    XCTAssertTrue(latestLogs.last?.success ?? false)
}
```

### Manual Testing

#### 1. Accuracy Test
**Objective:** Verify recorded time matches actual usage

**Steps:**
1. Select a learning app (e.g., Safari)
2. Note exact start time
3. Use app for exactly 10 minutes (set timer)
4. Return to Screen Time Rewards app
5. Check recorded usage

**Expected Result:** Recorded time = 10 minutes ± 30 seconds

**Pass Criteria:** Accuracy within 5% (9:30 - 10:30)

#### 2. Reliability Test
**Objective:** Ensure extension continues recording when app is closed

**Steps:**
1. Start monitoring
2. Use learning app for 5 minutes
3. Force-quit Screen Time Rewards app
4. Continue using learning app for 5 more minutes
5. Relaunch Screen Time Rewards app
6. Check total recorded usage

**Expected Result:** Total recorded time = 10 minutes

**Pass Criteria:** All usage recorded despite app being closed

#### 3. Edge Cases

**A. Time Zone Change**
1. Start monitoring in EST
2. Use learning app for 5 minutes
3. Change device time zone to PST
4. Continue using app for 5 minutes
5. Check recorded usage

**Expected:** Total time = 10 minutes (unaffected by TZ change)

**B. Device Restart**
1. Start monitoring
2. Use learning app for 3 minutes
3. Restart device
4. After reboot, use app for 3 more minutes
5. Check recorded usage

**Expected:** Total time = 6 minutes (pre + post restart)

**C. Low Memory**
1. Open 20+ apps to consume memory
2. Start using learning app
3. Monitor extension memory usage in TrackingHealthView
4. Verify usage still recorded

**Expected:** Extension degrades gracefully, no crashes

**D. Many Apps (Scaling)**
1. Select 20+ apps (10 learning, 10 reward)
2. Create challenge with all apps
3. Use various apps throughout day
4. Check all usage recorded

**Expected:** All usage tracked despite > 8 app limit

#### 4. Battery Impact Test
**Objective:** Ensure changes don't significantly drain battery

**Steps:**
1. Full charge device
2. Run for 8 hours with monitoring active
3. Note battery percentage
4. Compare to baseline (previous version)

**Expected Result:** Additional battery drain < 5%

**Pass Criteria:** Acceptable if < 8% daily drain from tracking

---

## Rollout Plan

### Phase 1-2: Foundation (Week 1)
**Deliverables:**
- Dual-schedule architecture implemented
- Heartbeat verification system active
- Enhanced Darwin notifications with sequence numbers
- Event grouping by category (Learning/Reward)
- Tiered thresholds (1min, 5min, 15min)

**Testing:**
- Unit tests for deduplication
- Integration tests for dual-schedule
- Manual accuracy test on 3 developer devices

**Deployment:**
- Internal TestFlight build
- Monitor for 3 days on team devices

### Phase 3-4: Reliability (Week 2)
**Deliverables:**
- Dynamic restart timing (foreground/background aware)
- Usage-based restart delay
- Recovery log system
- Gap detection algorithm
- Offline queue for failed writes
- Clock sync protection

**Testing:**
- All integration tests
- Edge case testing (TZ change, device restart)
- Manual reliability test

**Deployment:**
- Beta TestFlight to 5-10 users
- Collect feedback for 5 days
- Monitor TrackingHealthView reports

### Phase 5: Polish (Week 3)
**Deliverables:**
- Extension memory monitoring
- Graceful degradation on errors
- Comprehensive logging system
- TrackingHealthView UI
- Diagnostics export feature

**Testing:**
- Low memory test
- Scaling test (20+ apps)
- Battery impact test
- Full regression suite

**Deployment:**
- Expand beta to 20-30 users
- Run for 7 days
- Analyze metrics and logs

### Production Release (Week 4)
**Deliverables:**
- Bug fixes from beta feedback
- Performance optimizations
- Final documentation
- Release notes

**Deployment:**
- Submit to App Store
- Gradual rollout (10% → 50% → 100%)
- Monitor analytics for anomalies

### Phase 6: Future Enhancement (Week 5+)
**Deliverables:**
- DeviceActivityReport extension (if needed)
- UI improvements based on real app name display
- Additional visualizations

**Deployment:**
- Optional feature flag
- Gradual rollout to interested users

---

## Success Metrics

### Primary Metrics

**1. Missed Usage Events**
- **Baseline:** Unknown (not currently measured)
- **Target:** < 2% of total events
- **Measurement:** Compare expected events (1 per minute) vs actual recorded events
- **Formula:** `(Expected Events - Recorded Events) / Expected Events × 100`

**2. User-Reported Inaccuracies**
- **Baseline:** Current user reports (qualitative)
- **Target:** 90% reduction in reports
- **Measurement:** Support tickets tagged "tracking inaccurate"

**3. Data Loss Incidents**
- **Target:** < 1 per 1000 tracking sessions
- **Measurement:** Detected gaps > 10 minutes in gap detection algorithm
- **Formula:** `Gaps Detected / Total Sessions × 1000`

### Secondary Metrics

**4. Battery Impact**
- **Target:** < 5% daily drain attributed to app
- **Measurement:** iOS Settings → Battery → Screen Time Rewards
- **Collection:** Beta testers report daily usage %

**5. Extension Crash Rate**
- **Target:** < 0.1% of all callbacks
- **Measurement:** Recovery log error entries / total log entries
- **Formula:** `Error Count / Total Events × 100`

**6. Event Firing Reliability**
- **Target:** > 98% of scheduled events fire
- **Measurement:** Heartbeat checks + event count vs expected
- **Formula:** `Actual Events / Expected Events × 100`

### Monitoring Dashboard

**Weekly Report Contents:**
- Total events recorded this week
- Average events per user per day
- Gap detection rate
- Error rate from recovery log
- Battery usage histogram (user-reported)
- Top 5 error messages from extension logs

**Analytics Events to Track:**
```swift
// Add to analytics platform
Analytics.track("tracking_gap_detected", properties: [
    "gap_duration_minutes": gapDuration,
    "affected_apps": affectedApps.count
])

Analytics.track("extension_error", properties: [
    "error_type": error.localizedDescription,
    "memory_usage_mb": memoryUsage,
    "event_name": eventName
])

Analytics.track("tracking_accuracy_check", properties: [
    "expected_events": expectedEvents,
    "actual_events": actualEvents,
    "accuracy_percentage": accuracy
])
```

---

## Technical Considerations

### Apple API Limitations (from "Maximizing Tracking Accuracy.pdf")

**Confirmed Constraints:**
1. ✅ **Special entitlement:** `com.apple.developer.family-controls` - Already configured in entitlements files
2. ✅ **User-selected scope:** Can only track apps user selects via FamilyActivityPicker - Existing implementation handles this
3. ✅ **No cross-app communication:** DeviceActivityReport extension sandboxed - Using Darwin notifications + App Group UserDefaults workaround
4. ⚠️ **Minimum interval:** 15 minutes for DeviceActivitySchedule - Currently using 24-hour interval with 1-min thresholds (compliant)
5. ⚠️ **Event limit:** ~20 schedules, ~8 events per schedule - Phase 2 addresses with category grouping
6. ⚠️ **Extension sandbox:** 6 MB RAM limit - Phase 5 monitors and handles gracefully

**Workarounds Implemented:**
- Dual-schedule for redundancy (schedules A & B)
- Category grouping to stay under event limits
- App Group UserDefaults for cross-process data
- Darwin notifications for wake-up signals
- Recovery log for error tracking

### Known Platform Bugs (from report)

**iOS 17.6 Issues:**
1. **Double-counting:** Safari usage + web category both counted
   - **Mitigation:** Advise users to update to iOS 18+ in release notes
   - **Detection:** Check for duplicate entries in same time window

2. **Share Across Devices:** Syncs multiple devices, inflates totals
   - **Mitigation:** Add setting warning: "Disable 'Share Across Devices' in Settings → Screen Time for accurate single-device tracking"
   - **Detection:** Check for impossible usage patterns (> 24 hours/day)

3. **`intervalDidEnd` unreliable:** Sometimes doesn't fire
   - **Mitigation:** Don't rely on it for critical logic (already avoided in current implementation)
   - **Verification:** Current implementation uses restart timer, not `intervalDidEnd`

### Breaking Changes
**None.** All changes are:
- Additive (new features)
- Internal optimizations (no API changes)
- Backward compatible (existing data format unchanged)

**Data Migration:**
- Not required (no schema changes)
- New fields added to UserDefaults are optional
- Recovery log is net-new (doesn't affect existing data)

---

## Documentation Updates

### 1. Developer Documentation

**Update ScreenTimeService.swift header:**
```swift
/**
 # ScreenTimeService

 Core service for tracking app usage using Apple's DeviceActivity framework.

 ## Architecture

 - **Dual-Schedule Monitoring:** Uses two overlapping 24-hour schedules offset by 30 seconds
   for redundancy. If one schedule misses an event, the other catches it.

 - **Extension Integration:** DeviceActivityMonitor extension runs in separate process and
   records usage to App Group UserDefaults. Extension posts Darwin notifications to wake
   main app for real-time processing.

 - **Heartbeat System:** Extension writes timestamp every 30 seconds. Main app monitors
   heartbeat and triggers recovery if gap > 2 minutes detected.

 - **Category Grouping:** Apps grouped by category (Learning/Reward/Other) to stay within
   Apple's ~8 event limit while supporting unlimited apps.

 ## Recovery Mechanisms

 - **Offline Queue:** Extension queues failed writes and retries on next callback
 - **Gap Detection:** Algorithm detects missing time intervals and alerts user
 - **Recovery Log:** All extension errors logged for diagnostics
 - **Graceful Degradation:** Falls back to emergency storage if primary fails

 ## Monitoring

 Use `TrackingHealthView` in Settings to monitor extension health, view error logs,
 and export diagnostics. Check heartbeat status, memory usage, and detected gaps.

 ## Testing

 - Unit tests: `ScreenTimeServiceTests.swift`
 - Integration tests: `ScreenTimeIntegrationTests.swift`
 - Manual test guide: `docs/TRACKING_ACCURACY_IMPROVEMENTS.md`
 */
class ScreenTimeService: ObservableObject {
    // ...
}
```

**Add Architecture Diagram:**
```
docs/architecture/tracking_system.png

┌─────────────────────────────────────────────────────────────┐
│                     Main App Process                         │
│                                                              │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │ ScreenTimeService│ ───▶ │ Usage Persistence │            │
│  │                  │      │  (UserDefaults)   │            │
│  │  - Start Monitor │      │                   │            │
│  │  - Check Health  │      │  - App Usage      │            │
│  │  - Detect Gaps   │      │  - Recovery Log   │            │
│  └────────┬─────────┘      └──────────────────┘            │
│           │                                                  │
│           │ Darwin Notifications                             │
│           ▼                                                  │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │ Notification     │      │ Core Data        │            │
│  │ Handler          │ ───▶ │ UsageRecord      │            │
│  └──────────────────┘      │ ChallengeProgress│            │
│                             └──────────────────┘            │
└─────────────────────────────────────────────────────────────┘
                               │
                               │ App Group UserDefaults
                               ▼
┌─────────────────────────────────────────────────────────────┐
│              DeviceActivityMonitor Extension                 │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ ScreenTimeActivityMonitorExtension                    │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │  │
│  │  │ Schedule A   │  │ Schedule B   │  │ Heartbeat  │ │  │
│  │  │ (00:00:00)   │  │ (00:00:30)   │  │ Timer      │ │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬─────┘ │  │
│  │         │                 │                  │        │  │
│  │         └─────────┬───────┘                  │        │  │
│  │                   ▼                          ▼        │  │
│  │          ┌─────────────────┐       ┌─────────────┐   │  │
│  │          │ Event Handler   │       │ Write       │   │  │
│  │          │ - Deduplication │       │ Heartbeat   │   │  │
│  │          │ - Category Logic│       │             │   │  │
│  │          │ - Error Handling│       │             │   │  │
│  │          └────────┬────────┘       └─────────────┘   │  │
│  │                   │                                   │  │
│  │                   ▼                                   │  │
│  │          ┌─────────────────┐                         │  │
│  │          │ Persistence      │                         │  │
│  │          │ - Primary (UD)   │                         │  │
│  │          │ - Fallback (File)│                         │  │
│  │          │ - Recovery Queue │                         │  │
│  │          └────────┬────────┘                         │  │
│  │                   │                                   │  │
│  │                   ▼                                   │  │
│  │          ┌─────────────────┐                         │  │
│  │          │ Post Darwin      │                         │  │
│  │          │ Notification     │                         │  │
│  │          └──────────────────┘                         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2. User-Facing Documentation

**Help Article: "Understanding Usage Tracking"**
```markdown
# How Screen Time Rewards Tracks Your Usage

Screen Time Rewards uses Apple's official Screen Time APIs to track how long
you use learning and reward apps. Here's how it works:

## What Gets Tracked

- ✅ **Learning Apps:** Educational apps you select during setup
- ✅ **Reward Apps:** Fun apps you can unlock by completing learning goals
- ❌ **Other Apps:** We don't track apps outside your selected categories

## How It Works

1. You select which apps to track using Apple's app picker
2. Our app monitors these apps in the background
3. Usage is recorded every minute for accuracy
4. Your progress updates automatically

## Accuracy & Privacy

- **Accuracy:** Tracking is accurate to within 30 seconds
- **Privacy:** Only YOU can see your usage data
- **No Spying:** We cannot see apps you haven't selected
- **Offline:** Tracking works even when app is closed

## Troubleshooting

**"Some usage wasn't tracked"**

If you see this message:

1. Open Settings → Screen Time Rewards → Tracking Health
2. Check if extension is healthy (green checkmark)
3. If unhealthy, restart your device
4. Contact support if issue persists

**"Usage seems wrong"**

Possible causes:

- **Share Across Devices** enabled in iOS Settings → Screen Time
  → Turn OFF to track only this device
- **Time zone changed** during the day
  → Check TrackingHealth for clock adjustments
- **App was force-quit** during tracking
  → Avoid force-quitting; use normally

**Battery Usage**

Screen Time Rewards tracking uses <5% battery per day. If you notice higher
usage, check TrackingHealth for extension errors.

## Get Help

Still having issues? Export diagnostics:

1. Settings → Tracking Health
2. Tap "Export Diagnostics"
3. Send to support@screentimerewards.com
```

### 3. Troubleshooting Guide

**For Support Team:**
```markdown
# Screen Time Tracking - Support Troubleshooting Guide

## Common Issues & Solutions

### Issue: "Usage not recorded"

**Symptoms:**
- User reports learning time not showing up
- Challenge progress not updating
- Zero usage despite using apps

**Diagnosis Steps:**

1. **Check Extension Health**
   - Settings → Tracking Health
   - Look for:
     - Last heartbeat (should be < 5 min ago)
     - Error count (should be 0 or low)
     - Memory usage (should be < 5 MB)

2. **Check Permissions**
   - iOS Settings → Screen Time Rewards
   - Verify "Family Controls" permission granted
   - Check app list includes the apps in question

3. **Check Share Across Devices**
   - iOS Settings → Screen Time
   - Turn OFF "Share Across Devices"
   - This can cause double-counting issues

**Solutions:**

- **Extension Unhealthy:** Restart device
- **Permission Missing:** Re-grant in iOS Settings
- **Gaps Detected:** Normal if < 5 min; alert developer if > 10 min

### Issue: "Inaccurate time (too high or too low)"

**Diagnosis:**

1. **Export Diagnostics**
   - Settings → Tracking Health → Export Diagnostics
   - Check for:
     - Multiple gap detections
     - High error count in recovery log
     - Clock adjustment events

2. **Check Data Gaps**
   - TrackingHealth → Detected Data Gaps
   - Note gap durations and times

**Solutions:**

- **Consistent over-reporting:** Check for iOS 17.6 Safari bug; advise update
- **Consistent under-reporting:** Possible extension crashes; check recovery log
- **Random gaps:** Network issues or low memory; monitor over several days

### Issue: "Battery drain"

**Diagnosis:**

1. **Check Memory Usage**
   - TrackingHealth → Extension Health → Memory Usage
   - Should be < 5 MB

2. **Check Error Rate**
   - TrackingHealth → Recovery Log
   - High error rate = excessive retries = battery drain

**Solutions:**

- **High memory:** Extension may be crashing and restarting; report to dev team
- **High errors:** Underlying system issue; try reinstalling app

## Escalation Criteria

**Escalate to Engineering if:**

1. Heartbeat consistently > 5 min old
2. Error rate > 10% in recovery log
3. Memory usage > 5.5 MB (approaching 6 MB limit)
4. Gaps > 30 minutes detected regularly
5. User reports 100% inaccuracy (0 usage when should have usage)

**Include in Escalation:**

- Exported diagnostics file
- iOS version
- Device model
- Steps to reproduce
- Expected vs actual behavior
```

---

## File Structure

After implementation, the project structure will be:

```
ScreenTimeRewardsProject/
├── ScreenTimeRewards/
│   ├── Services/
│   │   └── ScreenTimeService.swift          (MODIFIED - Phases 1-4)
│   ├── Models/
│   │   ├── UsageRecoveryLog.swift           (NEW - Phase 4)
│   │   └── AppUsage.swift                    (existing)
│   ├── Shared/
│   │   ├── UsagePersistence.swift           (MODIFIED - Phase 1)
│   │   └── ScreenTimeNotifications.swift    (MODIFIED - Phase 1)
│   ├── Views/
│   │   └── Settings/
│   │       └── TrackingHealthView.swift     (NEW - Phase 5)
│   └── ScreenTimeRewards.entitlements       (existing)
│
├── ScreenTimeActivityExtension/
│   ├── DeviceActivityMonitorExtension.swift (MODIFIED - Phases 1-5)
│   └── ScreenTimeActivityExtension.entitlements (existing)
│
├── ScreenTimeReportExtension/               (NEW - Phase 6 - Low Priority)
│   ├── DeviceActivityReportExtension.swift  (NEW)
│   ├── TotalActivityView.swift              (NEW)
│   ├── Info.plist                           (NEW)
│   └── ScreenTimeReportExtension.entitlements (NEW)
│
├── docs/
│   ├── TRACKING_ACCURACY_IMPROVEMENTS.md    (THIS FILE)
│   ├── Maximizing Tracking Accuracy.pdf     (reference)
│   └── architecture/
│       └── tracking_system.png              (NEW - architecture diagram)
│
└── ScreenTimeRewardsTests/
    ├── ScreenTimeServiceTests.swift         (MODIFIED - new tests)
    └── ScreenTimeIntegrationTests.swift     (NEW - integration tests)
```

---

## Risk Assessment

### Low Risk Items
**Likelihood: Low | Impact: Low**

1. **Dual-Schedule Architecture**
   - Well-documented pattern in Apple forums
   - Deduplication is straightforward timestamp comparison
   - Rollback: Simply disable second schedule

2. **Heartbeat Verification**
   - Simple timestamp write/read
   - No complex logic
   - Rollback: Remove heartbeat check, no impact

3. **Enhanced Logging**
   - Purely observational
   - No impact on core functionality
   - Rollback: Remove log writes

### Medium Risk Items
**Likelihood: Medium | Impact: Medium**

1. **Dynamic Restart Timing**
   - New: App state-based intervals
   - Risk: Longer intervals (5 min) may miss short usage bursts
   - Mitigation: A/B test with current 2-min vs new dynamic
   - Rollback: Revert to fixed 2-minute timer

2. **Event Grouping by Category**
   - New: Multiple apps per event instead of one-to-one
   - Risk: Extension receives aggregate usage, must distribute correctly
   - Mitigation: Extensive unit tests for distribution logic
   - Rollback: Revert to individual app events (limit to 8 apps)

3. **Background Task Integration**
   - New: BGProcessingTask for background restart
   - Risk: iOS may not grant background time consistently
   - Mitigation: Keep foreground timer as fallback
   - Rollback: Remove background task, rely on foreground only

### High Risk Items
**Likelihood: Low | Impact: High**

1. **Memory Optimization in Extension**
   - Known limit: 6 MB RAM for extension
   - Risk: Complex recovery logic may exceed limit, crash extension
   - Mitigation:
     - Monitor memory in dev/beta builds
     - Simplify data structures
     - Use minimal logging in production
     - Defer non-critical operations
   - Rollback: Remove memory monitoring overhead

2. **Gap Detection Algorithm**
   - New: Automated detection of missing usage
   - Risk: False positives annoy users ("gaps" during legitimate idle time)
   - Mitigation:
     - High threshold (> 10 min gap)
     - User can dismiss alerts
     - Collect telemetry on gap frequency
   - Rollback: Disable gap detection UI, keep logging only

3. **Recovery Queue Mechanism**
   - New: Offline queue for failed writes
   - Risk: Queue grows unbounded, memory issues
   - Mitigation:
     - Limit queue size to 50 entries
     - Purge oldest if limit exceeded
     - Clear queue on successful sync
   - Rollback: Remove queue, log failures only

### Critical Risks
**Likelihood: Very Low | Impact: Critical**

1. **Extension Stability Regression**
   - **Scenario:** New code introduces crash in extension
   - **Impact:** ALL usage tracking stops
   - **Mitigation:**
     - Comprehensive error handling (Phase 5)
     - Beta test on 20-30 devices for 7 days
     - Crash reporting integration (Crashlytics)
     - Feature flags for gradual rollout
   - **Rollback Plan:**
     - Immediate: Disable dual-schedule via remote config
     - Within 24h: Push build with extension reverted to v1.0
     - Communication: Alert users via in-app message

2. **Data Corruption**
   - **Scenario:** Deduplication logic fails, creates duplicate entries
   - **Impact:** Inflated usage numbers, wrong challenge progress
   - **Mitigation:**
     - Extensive unit tests for deduplication
     - Data validation on read (detect duplicates, auto-fix)
     - Recovery log tracks all writes
   - **Rollback Plan:**
     - Detection: Analytics alert on avg usage > 18h/day
     - Fix: Run cleanup script to deduplicate Core Data
     - Prevention: Add duplicate check before save

### Mitigation Strategies

**1. Feature Flags**
```swift
enum TrackingFeature {
    static var dualScheduleEnabled: Bool {
        RemoteConfig.bool(for: "dual_schedule_enabled") ?? false
    }

    static var gapDetectionEnabled: Bool {
        RemoteConfig.bool(for: "gap_detection_enabled") ?? false
    }

    static var backgroundTaskEnabled: Bool {
        RemoteConfig.bool(for: "background_task_enabled") ?? false
    }
}

// Use in code:
if TrackingFeature.dualScheduleEnabled {
    scheduleMonitoringWithRedundancy()
} else {
    scheduleMonitoringStandard()
}
```

**2. A/B Testing**
- 50% users get dual-schedule, 50% get single
- Compare: accuracy, battery usage, error rate
- After 2 weeks: roll out winner to 100%

**3. Gradual Rollout**
- Week 1: 10% of users (internal + beta)
- Week 2: 25% of users
- Week 3: 50% of users
- Week 4: 100% if metrics look good

**4. Monitoring Alerts**
```
Alert: Extension crash rate > 1%
Action: Disable new features via feature flag

Alert: Average usage > 20h/day (impossible)
Action: Data corruption detected, run cleanup

Alert: Gap detection rate > 50%
Action: False positive rate too high, disable UI alerts
```

**5. Rollback Playbook**
```markdown
# Emergency Rollback Procedure

## Trigger Conditions
- Extension crash rate > 5%
- User reports of zero usage > 10 per day
- Battery drain reports > 20 per day
- Data corruption detected

## Steps

1. **Immediate (0-30 min)**
   - Disable all feature flags via Firebase Remote Config
   - Post incident in #engineering Slack
   - Update status page

2. **Short-term (30 min - 2 hours)**
   - Revert extension code to previous stable version
   - Build emergency patch release
   - Submit to App Store for expedited review

3. **Communication (Within 24 hours)**
   - In-app message: "We detected an issue with usage tracking. An update is coming soon."
   - Email to affected users with workaround (if any)
   - Post-mortem doc started

4. **Post-Rollback**
   - Analyze logs from affected users
   - Reproduce issue in test environment
   - Fix root cause before re-enabling
```

---

## Estimated Effort

### Development Time (Engineer-Days)

**Phase 1: Enhanced Event Monitoring**
- Dual-schedule architecture: 1.5 days
- Heartbeat verification: 0.5 days
- Extension health monitoring: 1 day
- Enhanced Darwin notifications: 0.5 days
- Testing & debugging: 0.5 days
- **Subtotal: 4 days**

**Phase 2: Improved Threshold Strategy**
- Smart event grouping: 1.5 days
- Tiered threshold implementation: 0.5 days
- Include past activity flag: 0.5 days
- Testing: 0.5 days
- **Subtotal: 3 days**

**Phase 3: Dynamic Restart Optimization**
- App state-aware restart: 0.5 days
- Usage-based delay: 0.5 days
- Background task integration: 1 day
- Testing: 0.5 days
- **Subtotal: 2.5 days**

**Phase 4: Session Continuity & Recovery**
- Extension recovery log: 1 day
- Gap detection algorithm: 1.5 days
- Offline queue: 1 day
- Clock sync protection: 0.5 days
- Testing: 1 day
- **Subtotal: 5 days**

**Phase 5: Enhanced Error Handling**
- Extension memory monitoring: 0.5 days
- Graceful degradation: 1 day
- Comprehensive logging: 1 day
- TrackingHealthView UI: 1.5 days
- Diagnostics export: 0.5 days
- Testing: 0.5 days
- **Subtotal: 5 days**

**Phase 6: DeviceActivityReport Extension (Low Priority)**
- Create extension target: 0.5 days
- Report view implementation: 2 days
- Integration with main app: 1 day
- Testing: 1 day
- UI polish: 0.5 days
- **Subtotal: 5 days**

### Testing Time

**Unit Testing:** 3 days
- Write tests for all phases
- Achieve 80%+ code coverage for new code

**Integration Testing:** 2 days
- Extension-to-app communication tests
- End-to-end tracking scenarios
- Edge case testing

**Manual Testing:** 2 days
- Accuracy tests
- Reliability tests
- Battery impact tests
- Scaling tests (20+ apps)

**Beta Testing Period:** 7-14 days
- Monitor metrics
- Collect feedback
- Fix critical bugs

**Total Development Time:**
- **Phases 1-5 (Required):** 19.5 days development + 7 days testing = **26.5 days**
- **Phase 6 (Optional):** +5 days development + 1 day testing = **5 days**

### Resource Requirements

**Engineering:**
- 1 Senior iOS Engineer (full-time)
- 1 QA Engineer (part-time for manual testing)
- 1 Backend Engineer (part-time for analytics setup)

**Design:**
- 0.5 days for TrackingHealthView UI design

**Product:**
- 1 day for writing user-facing documentation
- 0.5 days for beta test coordination

**DevOps:**
- 0.5 days for remote config setup (feature flags)
- 0.5 days for analytics dashboard

**Total Effort: ~6-7 weeks** (including buffer for bug fixes and iterations)

---

## References

1. **"Maximizing Tracking Accuracy.pdf"** - Technical report (provided)
   - Sections referenced: All (pages 1-4)
   - Key recommendations implemented in Phases 1-5

2. **Apple Official Documentation**
   - [DeviceActivity Framework](https://developer.apple.com/documentation/deviceactivity)
   - [FamilyControls Framework](https://developer.apple.com/documentation/familycontrols)
   - [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)

3. **WWDC Sessions**
   - [WWDC 2021: Meet Screen Time API](https://developer.apple.com/videos/play/wwdc2021/10123/)
   - [WWDC 2022: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/10153/)

4. **Developer Forum Reports**
   - [DeviceActivityMonitor overcount issue](https://developer.apple.com/forums/thread/763542)
   - [Screen Time API latency](https://www.reddit.com/r/iOSProgramming/comments/12m10eg/help_with_apples_new_screen_time_api_being_super/)

5. **Community Articles**
   - [A Developer's Guide to Apple's Screen Time APIs](https://medium.com/@juliusbrussee/a-developers-guide-to-apple-s-screen-time-apis-familycontrols-managedsettingsdeviceactivity-e660147367d7)
   - [Creating an iOS Screen Time Tracking App](https://medium.com/@danisharfin1/creating-an-ios-screen-time-tracking-app-using-swiftui-and-apples-deviceactivity-frameworke999c6f37930)
   - [Time After (Screen) Time - DeviceActivityMonitor Extension](https://letvar.medium.com/time-after-screen-time-part-3-the-device-activity-monitor-extension-284da931391b)

6. **Current Implementation Analysis** (completed by planning agent)
   - File: `/ScreenTimeRewards/Services/ScreenTimeService.swift` (2,245 lines)
   - File: `/ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` (229 lines)
   - File: `/ScreenTimeRewards/Shared/UsagePersistence.swift`
   - Diagnosis document: `/docs/DATA_QUALITY_ISSUES_DIAGNOSIS_AND_FIX_PLAN.md`

---

## Appendix A: Code Snippets

### Deduplication Logic Example

```swift
// In ScreenTimeService.swift
private func recordUsageWithDeduplication(
    logicalID: String,
    duration: TimeInterval,
    timestamp: Date,
    scheduleID: String
) {
    // Check for recent record within 90-second window
    let recentWindow: TimeInterval = 90

    let recentRecords = usageRecords.filter { record in
        record.logicalID == logicalID &&
        abs(record.timestamp.timeIntervalSince(timestamp)) < recentWindow
    }

    if !recentRecords.isEmpty {
        // Duplicate detected from other schedule - skip
        print("[ScreenTimeService] Deduplication: Skipping \(logicalID) at \(timestamp) (already recorded)")
        return
    }

    // Not a duplicate - proceed with recording
    let record = UsageRecord(
        logicalID: logicalID,
        duration: duration,
        timestamp: timestamp,
        scheduleID: scheduleID
    )

    usageRecords.append(record)
    saveToUserDefaults(record)
}
```

### Category Event Creation

```swift
// In ScreenTimeService.swift
private func createCategoryEvents(
    learningApps: [TrackedApplication],
    rewardApps: [TrackedApplication]
) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {

    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

    // Learning category events (1min, 5min, 15min thresholds)
    if !learningApps.isEmpty {
        let learningTokens = Set(learningApps.map { $0.token })

        events[.init("learning_1min")] = DeviceActivityEvent(
            applications: learningTokens,
            threshold: DateComponents(minute: 1),
            includesPastActivity: true
        )

        events[.init("learning_5min")] = DeviceActivityEvent(
            applications: learningTokens,
            threshold: DateComponents(minute: 5)
        )

        events[.init("learning_15min")] = DeviceActivityEvent(
            applications: learningTokens,
            threshold: DateComponents(minute: 15)
        )
    }

    // Reward category events
    if !rewardApps.isEmpty {
        let rewardTokens = Set(rewardApps.map { $0.token })

        events[.init("reward_1min")] = DeviceActivityEvent(
            applications: rewardTokens,
            threshold: DateComponents(minute: 1),
            includesPastActivity: true
        )

        events[.init("reward_5min")] = DeviceActivityEvent(
            applications: rewardTokens,
            threshold: DateComponents(minute: 5)
        )

        events[.init("reward_15min")] = DeviceActivityEvent(
            applications: rewardTokens,
            threshold: DateComponents(minute: 15)
        )
    }

    return events
}
```

### Extension Event Handler with Error Recovery

```swift
// In DeviceActivityMonitorExtension.swift
override func eventDidReachThreshold(
    _ event: DeviceActivityEvent.Name,
    activity: DeviceActivityName
) {
    ExtensionLogger.log(.info, component: "EventHandler",
                       message: "Threshold reached",
                       metadata: ["eventName": event.rawValue])

    // Write heartbeat
    writeHeartbeat()

    // Check memory pressure
    if checkMemoryPressure() {
        ExtensionLogger.log(.warn, component: "MemoryMonitor",
                           message: "Memory pressure detected, using minimal path")
        recordUsageMinimal(event, activity: activity)
        return
    }

    // Retry any failed writes from queue
    retryFailedWrites()

    // Attempt to record usage
    do {
        try recordUsageFull(event, activity: activity)

        // Log success
        UsageRecoveryLog.append(entry: RecoveryLogEntry(
            id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            eventName: event.rawValue,
            success: true,
            errorDescription: nil,
            attemptedAction: "record_usage",
            memoryUsageBytes: getMemoryUsage()
        ))

        // Post notification to main app
        postUsageNotification(event: event, activity: activity)

    } catch {
        ExtensionLogger.log(.error, component: "EventHandler",
                           message: "Failed to record usage",
                           metadata: ["error": error.localizedDescription])

        // Log failure
        UsageRecoveryLog.append(entry: RecoveryLogEntry(
            id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            eventName: event.rawValue,
            success: false,
            errorDescription: error.localizedDescription,
            attemptedAction: "record_usage",
            memoryUsageBytes: getMemoryUsage()
        ))

        // Queue for retry
        queueFailedWrite(event: event, activity: activity)
    }
}

private func recordUsageFull(
    _ event: DeviceActivityEvent.Name,
    activity: DeviceActivityName
) throws {
    // Full recording logic with detailed data
    let eventMapping = readEventMapping(for: event)

    guard let mapping = eventMapping else {
        throw TrackingError.noMappingFound
    }

    // Calculate usage (1 minute threshold = 60 seconds)
    let duration: TimeInterval = 60
    let points = mapping.rewardPoints

    // Update persistence
    try ExtensionUsagePersistence.shared.recordUsage(
        logicalID: mapping.logicalID,
        totalSeconds: Int(duration),
        earnedPoints: points
    )
}

private func recordUsageMinimal(
    _ event: DeviceActivityEvent.Name,
    activity: DeviceActivityName
) {
    // Minimal recording when memory is low
    // Only update totals, skip detailed logging
    let shared = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    // Increment simple counter
    let key = "usage_count_\(event.rawValue)"
    let current = shared?.integer(forKey: key) ?? 0
    shared?.set(current + 1, forKey: key)
}
```

---

## Appendix B: Testing Checklist

### Unit Test Checklist

- [ ] Deduplication logic prevents duplicate entries from dual schedules
- [ ] Deduplication allows entries > 90 seconds apart
- [ ] Category event grouping creates correct number of events (< 8)
- [ ] Category event includes all apps in category
- [ ] Tiered thresholds (1min, 5min, 15min) all fire independently
- [ ] Gap detection identifies 10-minute gap correctly
- [ ] Gap detection ignores legitimate 3-minute gap
- [ ] Offline queue adds failed writes
- [ ] Offline queue retries and removes on success
- [ ] Clock sync detection identifies time jump > 60 seconds
- [ ] Heartbeat write updates timestamp
- [ ] Extension health check detects stale heartbeat (> 2 min)
- [ ] Memory monitoring detects high usage (> 5 MB)
- [ ] Recovery log appends entry correctly
- [ ] Recovery log limits to 100 entries
- [ ] Dynamic restart interval returns 60s for foreground
- [ ] Dynamic restart interval returns 300s for background

### Integration Test Checklist

- [ ] Extension posts Darwin notification on event
- [ ] Main app receives Darwin notification
- [ ] Main app reads sequence number from notification
- [ ] Main app detects missed notification (sequence gap)
- [ ] Extension writes to App Group UserDefaults
- [ ] Main app reads from App Group UserDefaults
- [ ] Dual schedules fire events at correct times (0 and 30 seconds offset)
- [ ] Deduplication prevents double-recording from both schedules
- [ ] Heartbeat written every 30 seconds
- [ ] Main app triggers recovery when heartbeat stale
- [ ] Background task scheduled correctly
- [ ] Background task runs restart logic

### Manual Test Checklist

#### Accuracy Test
- [ ] Learning app usage for 10 minutes records 10 min ± 30s
- [ ] Reward app usage for 10 minutes records 10 min ± 30s
- [ ] Mixed usage (5 min learning + 5 min reward) records both correctly
- [ ] Very short usage (30 seconds) is captured

#### Reliability Test
- [ ] Force-quit app during usage → extension continues recording
- [ ] Relaunch app → all usage synced from shared storage
- [ ] Device restart mid-usage → usage before + after both recorded
- [ ] Airplane mode → usage recorded offline, syncs when online

#### Edge Cases
- [ ] Time zone change → timestamps remain accurate
- [ ] Clock adjustment (manual time change) → detected and logged
- [ ] Low memory (20+ apps open) → extension degrades gracefully
- [ ] 20+ tracked apps → category grouping works, all usage recorded

#### Battery Test
- [ ] 8-hour monitoring → battery drain < 5%
- [ ] TrackingHealthView shows extension memory < 5 MB
- [ ] No excessive wake-ups visible in battery usage details

#### UI Test
- [ ] TrackingHealthView displays correct health status
- [ ] Recovery log shows events (success/failure)
- [ ] Extension logs display with correct severity colors
- [ ] Detected gaps show in UI if > 10 minutes
- [ ] Export diagnostics creates shareable file
- [ ] Clear logs removes all entries

---

## Appendix C: Analytics Events

### Events to Track

```swift
// Tracking Accuracy
Analytics.track("tracking_accuracy_check", properties: [
    "expected_events": Int,        // Expected events based on time
    "actual_events": Int,          // Actually recorded events
    "accuracy_percentage": Double, // actual / expected * 100
    "timestamp": Date
])

// Data Gaps
Analytics.track("tracking_gap_detected", properties: [
    "gap_duration_minutes": Int,   // How long the gap was
    "gap_start_time": Date,        // When gap started
    "affected_apps": [String],     // Logical IDs of affected apps
    "auto_recovered": Bool         // Did recovery mechanism work?
])

// Extension Errors
Analytics.track("extension_error", properties: [
    "error_type": String,          // Error description
    "error_code": Int?,            // Error code if available
    "event_name": String,          // Which event was being processed
    "memory_usage_mb": Double,     // Memory at time of error
    "action_attempted": String,    // What was trying to do
    "retry_count": Int             // How many times retried
])

// Extension Health
Analytics.track("extension_health_check", properties: [
    "heartbeat_age_seconds": Int,  // Age of last heartbeat
    "is_healthy": Bool,            // Heartbeat < 2 min old
    "event_count_today": Int,      // Events fired today
    "error_count_today": Int,      // Errors today
    "memory_usage_mb": Double      // Current memory
])

// Recovery Actions
Analytics.track("recovery_triggered", properties: [
    "recovery_type": String,       // "gap_recovery", "heartbeat_recovery", etc.
    "triggered_by": String,        // "user", "automatic"
    "success": Bool,               // Did recovery work?
    "data_recovered_minutes": Int? // How much usage recovered
])

// User Actions
Analytics.track("diagnostics_exported", properties: [
    "export_method": String,       // "share_sheet", "email"
    "error_count": Int,            // Errors in export
    "gap_count": Int               // Gaps in export
])

Analytics.track("logs_cleared", properties: [
    "log_types_cleared": [String], // ["recovery", "extension", "all"]
    "entries_cleared": Int         // How many entries removed
])

// Performance
Analytics.track("deduplication_event", properties: [
    "duplicate_detected": Bool,    // Was it a duplicate?
    "time_diff_seconds": Int,      // Time between duplicate events
    "schedule_ids": [String]       // Which schedules fired
])
```

### Dashboard Metrics

**Weekly Aggregation:**

```
Tracking Accuracy Rate:
  (avg_accuracy_percentage across all users)
  Target: > 95%

Extension Health Score:
  (% of users with healthy extension)
  Target: > 98%

Gap Detection Rate:
  (gaps detected / total tracking sessions)
  Target: < 5%

Error Rate:
  (error events / total events)
  Target: < 1%

Battery Impact:
  (avg battery % from user reports)
  Target: < 5% daily
```

---

## Document Version History

**Version 1.0** - 2025-11-13
- Initial implementation plan created
- All 6 phases defined
- Testing strategy outlined
- Rollout plan established
- Risk assessment completed
- Based on "Maximizing Tracking Accuracy.pdf" analysis

**Author:** AI Assistant (Claude)
**Reviewed By:** [To be filled by dev team lead]
**Status:** Draft - Awaiting Implementation
**Priority:** High (Phases 1-5), Low (Phase 6)

---

**END OF IMPLEMENTATION PLAN**
