import DeviceActivity
import SwiftUI

/// DeviceActivityReport scene that extracts current daily usage and writes it to the app group
struct TotalActivityReport: DeviceActivityReportScene {
    /// Stable context identifier for the report
    static let context = DeviceActivityReport.Context("total-usage-sync")

    let context: DeviceActivityReport.Context = TotalActivityReport.context
    let content: (ActivityReport) -> TotalActivityView

    init(@ViewBuilder content: @escaping (ActivityReport) -> TotalActivityView) {
        self.content = content
    }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ActivityReport {
        NSLog("[ReportExtension] 📊 ==== makeConfiguration CALLED ====")
        NSLog("[ReportExtension] 📊 Current time: \(Date())")
        print("[ReportExtension] 📊 ==== makeConfiguration CALLED ====")
        print("[ReportExtension] 📊 Current time: \(Date())")

        var appUsageMap: [String: TimeInterval] = [:]

        // Aggregate per-app usage across data entries → segments → categories → applications
        for await entry in data {
            NSLog("[ReportExtension] 📊 Processing activity entry")
            for await segment in entry.activitySegments {
                NSLog("[ReportExtension] 📊 Processing activity segment")
                for await category in segment.categories {
                    NSLog("[ReportExtension] 📊 Processing category")
                    for await appActivity in category.applications {
                        let bundleID = appActivity.application.bundleIdentifier ?? "unknown"
                        let duration = appActivity.totalActivityDuration
                        appUsageMap[bundleID, default: 0] += duration
                        NSLog("[ReportExtension] 📊 App: \(bundleID), duration: \(Int(duration))s")
                    }
                }
            }
        }

        NSLog("[ReportExtension] 📊 Aggregation complete. Total apps: \(appUsageMap.count)")
        print("[ReportExtension] 📊 Aggregation complete. Total apps: \(appUsageMap.count)")

        let report = ActivityReport(
            timestamp: Date(),
            appUsageMap: appUsageMap
        )

        await bridgeToAppGroup(report)

        NSLog("[ReportExtension] ✅ makeConfiguration complete")
        print("[ReportExtension] ✅ makeConfiguration complete")
        return report
    }

    /// Persist a snapshot to the shared App Group for the main app to consume
    private func bridgeToAppGroup(_ report: ActivityReport) async {
        NSLog("[ReportExtension] 🔍 Attempting to access app group: group.com.screentimerewards.shared")
        print("[ReportExtension] 🔍 Attempting to access app group: group.com.screentimerewards.shared")

        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            NSLog("[ReportExtension] ❌ FAILED to access app group!")
            print("[ReportExtension] ❌ FAILED to access app group!")
            return
        }

        NSLog("[ReportExtension] ✅ App group accessible")
        print("[ReportExtension] ✅ App group accessible")

        let snapshot: [String: Any] = [
            "timestamp": report.timestamp.timeIntervalSince1970,
            "apps": report.appUsageMap.mapValues { Int($0) }
        ]

        NSLog("[ReportExtension] 📦 Snapshot content: \(snapshot)")
        print("[ReportExtension] 📦 Snapshot content: \(snapshot)")

        defaults.set(snapshot, forKey: "report_snapshot")

        NSLog("[ReportExtension] ✅ Wrote snapshot with \(report.appUsageMap.count) apps at \(report.timestamp)")
        print("[ReportExtension] ✅ Wrote snapshot with \(report.appUsageMap.count) apps at \(report.timestamp)")

        // Log individual apps for debugging
        for (bundleID, seconds) in report.appUsageMap {
            NSLog("[ReportExtension] 📊 Snapshot includes: \(bundleID) → \(Int(seconds))s")
        }
    }
}

/// Report configuration model
struct ActivityReport {
    let timestamp: Date
    let appUsageMap: [String: TimeInterval] // bundleID -> total seconds today
}
