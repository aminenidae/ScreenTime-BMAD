#if DEBUG
import SwiftUI
import UIKit

struct TrackingHealthView: View {
    @State private var healthStatus: ExtensionHealthStatus?
    @State private var errorLog: [ExtensionErrorEntry] = []
    @State private var gaps: [UsageGap] = []

    var body: some View {
        List {
            extensionHealthSection
            gapSection
            errorSection
            actionsSection
        }
        .navigationTitle("Tracking Health")
        .refreshable {
            await refresh()
        }
        .onAppear {
            loadData()
        }
    }

    private var extensionHealthSection: some View {
        Section("Extension Status") {
            if let status = healthStatus {
                HStack {
                    Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(status.isHealthy ? .green : .orange)
                    VStack(alignment: .leading) {
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
            } else {
                Text("No heartbeat data yet")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var gapSection: some View {
        Section("Detected Gaps") {
            if gaps.isEmpty {
                Text("No gaps detected")
                    .foregroundColor(.secondary)
            } else {
                ForEach(gaps) { gap in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(gap.durationMinutes) min gap")
                            .font(.headline)
                        Text("\(gap.startTime.formatted(date: .abbreviated, time: .shortened)) → \(gap.endTime.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Detected via \(gap.detectionMethod.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var errorSection: some View {
        Section("Recent Errors") {
            let failures = errorLog.filter { !$0.success }
            if failures.isEmpty {
                Text("No recent errors")
                    .foregroundColor(.secondary)
            } else {
                ForEach(failures.prefix(10)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.action)
                            .font(.headline)
                        if let description = entry.errorDescription {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Text(Date(timeIntervalSince1970: entry.timestamp).formatted())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Restart Monitoring") {
                Task {
                    await ScreenTimeService.shared.restartMonitoring(
                        reason: "settings_tracking_health_button",
                        force: true
                    )
                    await refresh()
                }
            }

            Button("Export Diagnostics") {
                exportDiagnostics()
            }

            Button("Clear Logs", role: .destructive) {
                ExtensionErrorLog.clear()
                loadData()
            }
        }
    }

    private func loadData() {
        healthStatus = ScreenTimeService.shared.getExtensionHealthStatus()
        errorLog = ExtensionErrorLog.readAll().reversed()
        gaps = ScreenTimeService.shared.detectUsageGaps()
    }

    private func refresh() async {
        loadData()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func memoryColor(_ memoryMB: Double) -> Color {
        if memoryMB > 5.5 { return .red }
        if memoryMB > 4.5 { return .orange }
        return .green
    }

    private func formatRelativeTime(seconds: Int) -> String {
        if seconds == Int.max {
            return "Never"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }

    private func exportDiagnostics() {
        let report = createDiagnosticsReport()

        let controller = UIActivityViewController(activityItems: [report], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(controller, animated: true)
        }
    }

    private func createDiagnosticsReport() -> String {
        var report = "Screen Time Rewards - Tracking Diagnostics\n"
        report += "Generated: \(Date().formatted())\n\n"

        if let status = healthStatus {
            report += "Extension Healthy: \(status.isHealthy)\n"
            report += "Last Heartbeat Gap: \(status.heartbeatGapSeconds)s\n"
            report += "Memory Usage: \(String(format: "%.1f MB", status.memoryUsageMB))\n"
        }
        report += "\nDetected Gaps:\n"
        if gaps.isEmpty {
            report += "None\n"
        } else {
            gaps.forEach { gap in
                report += "\(gap.durationMinutes) min (\(gap.detectionMethod)) at \(gap.startTime) → \(gap.endTime)\n"
            }
        }
        report += "\nRecent Errors:\n"
        let failures = errorLog.filter { !$0.success }
        if failures.isEmpty {
            report += "None\n"
        } else {
            failures.prefix(20).forEach { entry in
                report += "[\(Date(timeIntervalSince1970: entry.timestamp).formatted())] \(entry.action): \(entry.errorDescription ?? "Unknown error")\n"
            }
        }
        return report
    }
}
#endif
