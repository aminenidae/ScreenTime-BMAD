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
    let childName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var logFiles: [LogFileInfo]
    @State private var selectedURLs: Set<URL> = []
    @State private var showingDeleteConfirm = false
    @State private var batteryLine: String

    init(childName: String) {
        self.childName = childName
        let urls = ExtensionFileLogger.shared.allLogFileURLs()
        _logFiles = State(initialValue: urls.map(LogFileInfo.init))
        _batteryLine = State(initialValue: Self.formattedBatteryLine())
    }

    var body: some View {
        NavigationStack {
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
                            Button {
                                toggleSelection(info.url)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedURLs.contains(info.url) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedURLs.contains(info.url) ? .accentColor : .secondary)
                                        .font(.system(size: 20))
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
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        exportFiles()
                    } label: {
                        if selectedURLs.isEmpty {
                            Label("Export all", systemImage: "square.and.arrow.up")
                        } else {
                            Label("Export \(selectedURLs.count) selected", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(logFiles.isEmpty)

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Clear logs", systemImage: "trash")
                    }
                    .disabled(logFiles.isEmpty)
                } footer: {
                    Text("Tap files to pick specific days, or export all.")
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
        }
    }

    private func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    private func exportFiles() {
        let urls = selectedURLs.isEmpty
            ? logFiles.map(\.url)
            : logFiles.map(\.url).filter { selectedURLs.contains($0) }
        guard !urls.isEmpty else { return }

        let sanitized = childName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let prefix = sanitized.isEmpty ? "" : "\(sanitized)-"
        let tmp = FileManager.default.temporaryDirectory

        var renamed: [URL] = []
        for url in urls {
            let newName = "\(prefix)\(url.lastPathComponent)"
            let dest = tmp.appendingPathComponent(newName)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                renamed.append(dest)
            } else {
                renamed.append(url)
            }
        }

        let ac = UIActivityViewController(activityItems: renamed, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        ac.popoverPresentationController?.sourceView = presenter.view
        presenter.present(ac, animated: true)
    }

    private func reload() {
        let urls = ExtensionFileLogger.shared.allLogFileURLs()
        logFiles = urls.map(LogFileInfo.init)
        selectedURLs = []
        batteryLine = Self.formattedBatteryLine()
    }

    private static func formattedBatteryLine() -> String {
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

