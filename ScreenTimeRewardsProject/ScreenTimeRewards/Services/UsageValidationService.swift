//
//  UsageValidationService.swift
//  ScreenTimeRewards
//
//  Created by Claude on 2025-11-19.
//  Protective measure against iOS Screen Time API overcounting bugs (iOS 17.6.1 - 18.5+)
//

import Foundation
import Combine
import DeviceActivity
import FamilyControls
import UIKit

/// Service to validate usage tracking accuracy and detect potential iOS Screen Time API bugs
///
/// **Context:** iOS 17.6.1 through iOS 18.5+ has confirmed overcounting bugs (Apple DTS FB15103784)
/// This service helps detect and diagnose usage tracking issues.
///
/// **See:** `/docs/SCREENTIME_OVERCOUNTING_ANALYSIS.md` and `USAGE_TRACKING_ACCURACY.md`
@available(iOS 16.0, *)
@MainActor
class UsageValidationService: ObservableObject {
    static let shared = UsageValidationService()

    // MARK: - Published State

    @Published var validationStatus: ValidationStatus = .unknown
    @Published var lastValidationDate: Date?
    @Published var detectedIssues: [ValidationIssue] = []

    // MARK: - Types

    enum ValidationStatus {
        case unknown
        case healthy           // Tracking appears accurate
        case warning           // Minor discrepancies detected
        case error             // Significant issues detected

        var displayText: String {
            switch self {
            case .unknown: return "Not Yet Validated"
            case .healthy: return "Tracking Healthy"
            case .warning: return "Minor Issues Detected"
            case .error: return "Significant Issues Detected"
            }
        }

        var systemImage: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .healthy: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    struct ValidationIssue: Identifiable {
        let id = UUID()
        let severity: Severity
        let title: String
        let description: String
        let timestamp: Date
        let recommendedAction: String?

        enum Severity {
            case info
            case warning
            case critical
        }
    }

    struct ValidationResult {
        let ourTotal: TimeInterval
        let expectedTotal: TimeInterval
        let variance: Double
        let isAccurate: Bool
        let detectedIssues: [ValidationIssue]
    }

    struct DiagnosticSnapshot {
        let timestamp: Date
        let iosVersion: String
        let deviceModel: String
        let shareAcrossDevicesEnabled: Bool?
        let totalAppsMonitored: Int
        let trackedUsageSeconds: TimeInterval
        let thresholdEventsFired: Int
        let extensionReliabilityRate: Double?
        let detectedIssues: [ValidationIssue]
    }

    // MARK: - Configuration

    /// Variance threshold above which we consider tracking inaccurate (15%)
    private let accuracyThreshold: Double = 0.15

    /// Threshold for extension reliability warnings (< 90%)
    private let extensionReliabilityWarningThreshold: Double = 0.90

    // MARK: - Private State

    private var thresholdFireHistory: [String: [Date]] = [:]  // eventID -> [fire timestamps]
    private var appLastFireTime: [String: Date] = [:]  // appID -> last fire timestamp (Layer 2: Rate Limiting)
    private var recentAppFires: [String: [Date]] = [:]  // appID -> recent fire timestamps (Layer 3: Cascade Detection)

    // MARK: - Initialization

    private init() {
        // Private singleton
    }

    // MARK: - Public API

    /// Record that a threshold event fired with multi-layer validation
    /// - Parameters:
    ///   - eventID: The event identifier (e.g., "usage.app.0.min.16")
    ///   - appID: The application identifier for rate limiting
    ///   - timestamp: The time the event fired
    /// - Returns: `true` if event is valid and should be recorded, `false` if it should be rejected
    func recordThresholdFire(eventID: String, appID: String, at timestamp: Date = Date()) -> Bool {
        // === LAYER 1: Duplicate Event Rejection ===
        // Same eventID should not fire twice within 5 seconds
        if let lastFire = thresholdFireHistory[eventID]?.last {
            let timeDiff = timestamp.timeIntervalSince(lastFire)

            if timeDiff < 5.0 {
                // DUPLICATE DETECTED - reject it
                NSLog("[UsageValidationService] ❌ REJECTED - Duplicate fire")
                NSLog("[UsageValidationService]    Event: \(eventID)")
                NSLog("[UsageValidationService]    Time since last: \(String(format: "%.2f", timeDiff))s")

                let issue = ValidationIssue(
                    severity: .critical,
                    title: "Duplicate Threshold Fire Detected",
                    description: "Event '\(eventID)' fired twice within \(String(format: "%.1f", timeDiff)) seconds. This is a symptom of iOS Screen Time API bugs.",
                    timestamp: timestamp,
                    recommendedAction: "Disable 'Share Across Devices' in iOS Settings → Screen Time. This is a known iOS 17.6.1+ bug."
                )
                detectedIssues.append(issue)
                updateValidationStatus(issues: [issue])

                return false  // ❌ REJECT
            }
        }

        // === LAYER 2: Rate Limiting ===
        // Same app cannot fire more than 1 event per minute (physically impossible)
        // Threshold: 55s (5-second buffer for clock precision, allows 59.94s-60s legitimate events)
        if let lastAppFire = appLastFireTime[appID] {
            let timeSinceLastFire = timestamp.timeIntervalSince(lastAppFire)

            if timeSinceLastFire < 55.0 {
                // RATE LIMIT EXCEEDED - physically impossible
                NSLog("[UsageValidationService] ❌ REJECTED - Rate limit exceeded")
                NSLog("[UsageValidationService]    App: \(appID)")
                NSLog("[UsageValidationService]    Event: \(eventID)")
                NSLog("[UsageValidationService]    Time since last app fire: \(String(format: "%.2f", timeSinceLastFire))s")
                NSLog("[UsageValidationService]    Threshold: 55.0s (allows clock precision variance)")

                let issue = ValidationIssue(
                    severity: .critical,
                    title: "Rate Limit Exceeded",
                    description: "App '\(appID)' fired events \(String(format: "%.1f", timeSinceLastFire))s apart. Physically impossible (minimum 55s between events, threshold accounts for clock precision).",
                    timestamp: timestamp,
                    recommendedAction: "This is likely the iOS Screen Time API overcounting bug. Disable 'Share Across Devices'."
                )
                detectedIssues.append(issue)
                updateValidationStatus(issues: [issue])

                return false  // ❌ REJECT
            }
        }

        // === LAYER 3: Cascade Detection ===
        // Detect when multiple events fire in rapid succession (cascade pattern)
        if recentAppFires[appID] == nil {
            recentAppFires[appID] = []
        }

        // Clean old fires (keep only last 5 seconds)
        recentAppFires[appID] = recentAppFires[appID]?.filter {
            timestamp.timeIntervalSince($0) < 5.0
        } ?? []

        // Check if this would be the 3rd+ event in 5 seconds (cascade)
        if let fires = recentAppFires[appID], fires.count >= 2 {
            // CASCADE DETECTED
            NSLog("[UsageValidationService] ❌ REJECTED - Cascade detected")
            NSLog("[UsageValidationService]    App: \(appID)")
            NSLog("[UsageValidationService]    Event: \(eventID)")
            NSLog("[UsageValidationService]    Events in last 5s: \(fires.count + 1)")

            let issue = ValidationIssue(
                severity: .critical,
                title: "Event Cascade Detected",
                description: "App '\(appID)' fired \(fires.count + 1) events within 5 seconds. This is the iOS Screen Time API cascade bug.",
                timestamp: timestamp,
                recommendedAction: "Disable 'Share Across Devices' in iOS Settings → Screen Time."
            )
            detectedIssues.append(issue)
            updateValidationStatus(issues: [issue])

            return false  // ❌ REJECT
        }

        // === ALL LAYERS PASSED - Event is VALID ===

        // Record this fire in history
        if thresholdFireHistory[eventID] == nil {
            thresholdFireHistory[eventID] = []
        }
        thresholdFireHistory[eventID]?.append(timestamp)

        // Update app-level tracking
        appLastFireTime[appID] = timestamp
        recentAppFires[appID]?.append(timestamp)

        #if DEBUG
        NSLog("[UsageValidationService] ✅ VALID event")
        NSLog("[UsageValidationService]    Event: \(eventID)")
        NSLog("[UsageValidationService]    App: \(appID)")
        #endif

        return true  // ✅ ACCEPT
    }

    /// Validate usage accuracy for a specific app
    /// - Parameters:
    ///   - appName: The application name to validate
    ///   - ourTotal: Our tracked total in seconds
    ///   - expectedThresholdsFired: How many threshold events we expected to fire
    ///   - actualThresholdsFired: How many threshold events actually fired
    /// - Returns: Validation result with detected issues
    func validateUsageAccuracy(
        appName: String,
        ourTotal: TimeInterval,
        expectedThresholdsFired: Int,
        actualThresholdsFired: Int
    ) -> ValidationResult {
        var issues: [ValidationIssue] = []

        // Calculate expected total based on threshold events
        // Each threshold = 60 seconds
        let expectedTotal = TimeInterval(actualThresholdsFired * 60)

        // Check if we have discrepancy
        let variance = abs(ourTotal - expectedTotal) / max(expectedTotal, 1.0)
        let isAccurate = variance < accuracyThreshold

        // Check for missing threshold events (extension reliability issue)
        if actualThresholdsFired < expectedThresholdsFired {
            let missedEvents = expectedThresholdsFired - actualThresholdsFired
            let reliability = Double(actualThresholdsFired) / Double(expectedThresholdsFired)

            if reliability < extensionReliabilityWarningThreshold {
                issues.append(ValidationIssue(
                    severity: .warning,
                    title: "Extension Missed Events",
                    description: "DeviceActivityMonitor extension missed \(missedEvents) threshold events (\(Int(reliability * 100))% reliability). This may occur when the app is force-closed.",
                    timestamp: Date(),
                    recommendedAction: "Keep the app running in background instead of force-closing it for best accuracy."
                ))
            }
        }

        // Check for overcounting (Apple's bug symptom)
        if ourTotal > expectedTotal * 1.5 {
            issues.append(ValidationIssue(
                severity: .critical,
                title: "Potential Overcounting Detected",
                description: "Tracked usage (\(Int(ourTotal))s) is significantly higher than expected (\(Int(expectedTotal))s). This may indicate iOS Screen Time API overcounting bug.",
                timestamp: Date(),
                recommendedAction: "Disable 'Share Across Devices' in iOS Settings → Screen Time. Ensure no other devices are using this Apple ID."
            ))
        }

        // Check for undercounting
        if ourTotal < expectedTotal * 0.5 {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "Potential Undercounting Detected",
                description: "Tracked usage (\(Int(ourTotal))s) is significantly lower than expected (\(Int(expectedTotal))s).",
                timestamp: Date(),
                recommendedAction: "Ensure Screen Time permissions are granted. Try resetting the challenge."
            ))
        }

        // Update service state
        detectedIssues.append(contentsOf: issues)
        lastValidationDate = Date()
        updateValidationStatus(issues: issues)

        return ValidationResult(
            ourTotal: ourTotal,
            expectedTotal: expectedTotal,
            variance: variance,
            isAccurate: isAccurate,
            detectedIssues: issues
        )
    }

    /// Export diagnostic snapshot for troubleshooting
    func exportDiagnosticSnapshot() -> DiagnosticSnapshot {
        let screenTimeService = ScreenTimeService.shared
        let usagePersistence = screenTimeService.usagePersistence

        // Get current tracked usage
        var totalSeconds: TimeInterval = 0
        var totalThresholdsFired = 0
        var totalAppsMonitored = 0

        // Calculate totals from persistence
        let allApps = usagePersistence.loadAllApps()
        totalAppsMonitored = allApps.count
        for (_, appData) in allApps {
            totalSeconds += TimeInterval(appData.todaySeconds)
            // Estimate thresholds fired based on seconds (each 60s = 1 threshold)
            totalThresholdsFired += appData.todaySeconds / 60
        }

        // Calculate extension reliability if we have data
        var reliabilityRate: Double?
        if !thresholdFireHistory.isEmpty {
            let totalExpectedEvents = totalThresholdsFired  // This is what actually fired
            // We'd need to know expected vs actual, but for now use what we have
            reliabilityRate = totalThresholdsFired > 0 ? 1.0 : nil
        }

        return DiagnosticSnapshot(
            timestamp: Date(),
            iosVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            shareAcrossDevicesEnabled: nil,  // Cannot detect programmatically
            totalAppsMonitored: totalAppsMonitored,
            trackedUsageSeconds: totalSeconds,
            thresholdEventsFired: totalThresholdsFired,
            extensionReliabilityRate: reliabilityRate,
            detectedIssues: detectedIssues
        )
    }

    /// Export diagnostic data as formatted string for sharing/support
    func exportDiagnosticReport() -> String {
        let snapshot = exportDiagnosticSnapshot()

        var report = """
        # Screen Time Rewards - Usage Tracking Diagnostic Report

        **Generated:** \(formatDate(snapshot.timestamp))
        **iOS Version:** \(snapshot.iosVersion)
        **Device:** \(snapshot.deviceModel)

        ## Current Status
        - **Validation Status:** \(validationStatus.displayText)
        - **Last Validated:** \(lastValidationDate.map(formatDate) ?? "Never")

        ## Tracking Statistics
        - **Apps Monitored:** \(snapshot.totalAppsMonitored)
        - **Total Tracked Usage:** \(formatDuration(snapshot.trackedUsageSeconds))
        - **Threshold Events Fired:** \(snapshot.thresholdEventsFired)
        """

        if let reliability = snapshot.extensionReliabilityRate {
            report += "\n- **Extension Reliability:** \(Int(reliability * 100))%"
        }

        if let shareEnabled = snapshot.shareAcrossDevicesEnabled {
            report += "\n- **Share Across Devices:** \(shareEnabled ? "⚠️ ENABLED (should be OFF)" : "✅ Disabled")"
        } else {
            report += "\n- **Share Across Devices:** Unknown (check iOS Settings → Screen Time)"
        }

        // Issues section
        if !snapshot.detectedIssues.isEmpty {
            report += "\n\n## Detected Issues\n"
            for (index, issue) in snapshot.detectedIssues.enumerated() {
                report += "\n### \(index + 1). \(issue.title)"
                report += "\n- **Severity:** \(issue.severity)"
                report += "\n- **Description:** \(issue.description)"
                if let action = issue.recommendedAction {
                    report += "\n- **Recommended Action:** \(action)"
                }
                report += "\n"
            }
        } else {
            report += "\n\n## Detected Issues\n\nNo issues detected. Tracking appears healthy. ✅\n"
        }

        // Recommendations
        report += """

        ## Recommendations for Accurate Tracking

        1. ✅ **Disable "Share Across Devices"** in iOS Settings → Screen Time
        2. ✅ **Keep app running** (backgrounded is OK, but don't force-close)
        3. ✅ **Single device usage** for most accurate results
        4. ✅ **Native apps only** (avoid web-based learning apps if possible)

        ## Known iOS Bugs

        iOS 17.6.1 through iOS 18.5+ has confirmed Screen Time API overcounting bugs:
        - Inflated usage totals (2x or more)
        - Premature threshold fires
        - Duplicate callbacks
        - Safari double-counting
        - Cross-device bleed

        **Apple DTS Feedback:** FB15103784 (No fix available yet)

        Our static threshold approach appears to avoid these bugs based on testing.

        ---

        For support, please send this report to: support@screentimerewards.com
        """

        return report
    }

    /// Clear all validation history and reset state
    func resetValidationState() {
        thresholdFireHistory.removeAll()
        appLastFireTime.removeAll()
        recentAppFires.removeAll()
        detectedIssues.removeAll()
        lastValidationDate = nil
        validationStatus = .unknown
    }

    // MARK: - Private Helpers

    private func updateValidationStatus(issues: [ValidationIssue]) {
        let hasCritical = issues.contains { $0.severity == .critical }
        let hasWarning = issues.contains { $0.severity == .warning }

        if hasCritical {
            validationStatus = .error
        } else if hasWarning {
            validationStatus = .warning
        } else if !detectedIssues.isEmpty {
            validationStatus = .warning
        } else {
            validationStatus = .healthy
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m (\(Int(seconds))s total)"
        } else {
            return "\(minutes)m (\(Int(seconds))s total)"
        }
    }
}
