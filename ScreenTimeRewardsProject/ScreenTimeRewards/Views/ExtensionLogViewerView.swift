import SwiftUI
import Combine

/// In-app viewer for DeviceActivityMonitor extension debug logs
/// Allows viewing extension events without needing Xcode/Console.app
struct ExtensionLogViewerView: View {
    @State private var logText: String = "Loading..."
    @State private var autoRefresh = true
    @State private var filterText = ""
    @Environment(\.colorScheme) var colorScheme

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let appGroupID = "group.com.screentimerewards.shared"

    /// Filtered log lines based on search text
    private var filteredLog: String {
        guard !filterText.isEmpty else { return logText }
        let lines = logText.components(separatedBy: "\n")
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterText) }
        return filtered.isEmpty ? "(No matches for '\(filterText)')" : filtered.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            VStack(spacing: 12) {
                // Search filter
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter logs (e.g., PHANTOM, CASE_3)", text: $filterText)
                        .textFieldStyle(.plain)
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Actions row
                HStack {
                    Toggle("Auto-refresh", isOn: $autoRefresh)
                        .toggleStyle(.switch)

                    Spacer()

                    Button(action: { copyLogs() }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { clearLogs() }) {
                        Label("Clear", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

            }
            .padding()
            .background(Color(.systemBackground))

            Divider()

            // Log content
            ScrollView {
                ScrollViewReader { proxy in
                    Text(filteredLog)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("logBottom")
                }
            }
            .background(colorScheme == .dark ? Color.black : Color(.systemGray6))
        }
        .navigationTitle("Extension Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { loadLogs() }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear { loadLogs() }
        .onReceive(timer) { _ in
            if autoRefresh { loadLogs() }
        }
    }

    private func loadLogs() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logText = "Error: Cannot access app group '\(appGroupID)'"
            return
        }
        let log = defaults.string(forKey: "extension_debug_log") ?? ""
        if log.isEmpty {
            logText = "(No extension logs yet)\n\nLogs will appear here when:\n- The app monitors device activity\n- Usage threshold events fire\n\nTry using a configured app for 1+ minute."
        } else {
            logText = log
        }
    }

    private func clearLogs() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: "extension_debug_log")
        logText = "(Logs cleared)"
    }

    private func copyLogs() {
        UIPasteboard.general.string = filteredLog
    }
}

#Preview {
    NavigationView {
        ExtensionLogViewerView()
    }
}
