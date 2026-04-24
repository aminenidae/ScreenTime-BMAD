import SwiftUI
import UIKit

/// Diagnostics screen reachable from the parent Settings tab.
///
/// Lists every retained `ext-log-YYYY-MM-DD.log` file written by
/// `ExtensionFileLogger` (the rotating-file logger that captures the FULL
/// daily log without size truncation), shows the most recent battery
/// snapshot persisted by `AppDelegate.persistBatterySnapshot()`, and
/// exposes two actions:
///
///   • Export all — share every log file via UIActivityViewController
///     (AirDrop, Files, Mail, etc.). No zip dependency; iOS handles
///     multi-file activity items natively.
///   • Clear logs — delete every retained log file (with confirmation).
///
/// File-discovery and file-deletion both go through `ExtensionFileLogger`
/// so the path constants are not duplicated. The current battery snapshot
/// is read directly from the App Group `UserDefaults`.
///
/// NOTE: This file must be added to the ScreenTimeRewards target in Xcode
/// before it will compile.
struct DiagnosticsLogExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var logFiles: [LogFileInfo] = []
    @State private var showingDeleteConfirm = false
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var batteryLine: String = "—"

    var body: some View {
        NavigationView {
            List {
                Section("Battery (last snapshot from main app)") {
                    Text(batteryLine)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Section("Log files") {
                    if logFiles.isEmpty {
                        Text("No log files yet. Logs are written when the extension fires threshold events.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(logFiles, id: \.url) { info in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.url.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                    Text(info.sizeString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                Section {
                    Button {
                        shareItems = logFiles.map { $0.url as Any }
                        showingShareSheet = !shareItems.isEmpty
                    } label: {
                        Label("Export all", systemImage: "square.and.arrow.up")
                    }
                    .disabled(logFiles.isEmpty)

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Clear logs", systemImage: "trash")
                    }
                    .disabled(logFiles.isEmpty)
                } footer: {
                    Text("Logs help diagnose usage-recording issues like the Apr 23 charging-flush overcounting incident. They include battery state at every monitoring restart and threshold burst.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { reload() }
            .confirmationDialog(
                "Delete all log files?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete \(logFiles.count) file\(logFiles.count == 1 ? "" : "s")", role: .destructive) {
                    ExtensionFileLogger.shared.deleteAllLogFiles()
                    reload()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Future log lines will start a fresh file.")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
        }
    }

    private func reload() {
        let urls = ExtensionFileLogger.shared.allLogFileURLs()
        logFiles = urls.map(LogFileInfo.init)
        batteryLine = formattedBatteryLine()
    }

    private func formattedBatteryLine() -> String {
        guard let defaults = UserDefaults(suiteName: ExtensionFileLogger.appGroupID) else {
            return "App Group unavailable"
        }
        let ts = defaults.double(forKey: "battery_state_timestamp")
        guard ts > 0 else { return "No snapshot yet — open this app once with battery monitoring enabled." }
        let stateInt = defaults.integer(forKey: "last_known_battery_state")
        let level = defaults.double(forKey: "last_known_battery_level")
        let stateStr: String
        switch stateInt {
        case 1: stateStr = "unplugged"
        case 2: stateStr = "charging"
        case 3: stateStr = "full"
        default: stateStr = "unknown"
        }
        let pct = (level >= 0) ? "\(Int(level * 100))%" : "?"
        let snapshot = Date(timeIntervalSince1970: ts)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(stateStr) \(pct) — snapshot \(formatter.string(from: snapshot))"
    }

    struct LogFileInfo {
        let url: URL
        let sizeString: String

        init(url: URL) {
            self.url = url
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            self.sizeString = formatter.string(fromByteCount: Int64(bytes))
        }
    }
}

/// Thin SwiftUI wrapper around UIActivityViewController. Used by the
/// Diagnostics screen's "Export all" button to share log file URLs via
/// AirDrop, Files, Mail, Messages, etc. iOS handles multiple file URLs
/// in a single activity item array natively (no zip needed).
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
