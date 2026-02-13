import SwiftUI
import Combine
import UIKit

/// Dedicated viewer for monitoring start/stop/kill lifecycle events.
/// Separate from the noisy extension event log — shows ONLY when monitoring
/// started, stopped, was killed by iOS, or had heartbeat gaps.
struct MonitoringLifecycleLogView: View {
    @State private var logText: String = "Loading..."
    @State private var autoRefresh = true
    @State private var filterText = ""
    @Environment(\.colorScheme) var colorScheme

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let appGroupID = "group.com.screentimerewards.shared"

    private var filteredLog: String {
        guard !filterText.isEmpty else { return logText }
        let lines = logText.components(separatedBy: "\n")
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterText) }
        return filtered.isEmpty ? "(No matches for '\(filterText)')" : filtered.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter (e.g., KILLED, STOP, GAP)", text: $filterText)
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

            ScrollView {
                Text(filteredLog)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(colorScheme == .dark ? Color.black : Color(.systemGray6))
        }
        .navigationTitle("Monitoring Log")
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
        let log = defaults.string(forKey: "monitoring_lifecycle_log") ?? ""
        if log.isEmpty {
            logText = """
            (No lifecycle events yet)

            This log tracks ONLY monitoring start/stop events:
            - MONITORING_START — monitoring began
            - MONITORING_STOP — monitoring stopped
            - MONITORING_RESTART — monitoring restarted (with reason)
            - MONITORING_ALIVE — OS confirmed monitoring active on app launch
            - MONITORING_RECOVERED — monitoring was dead, restarted
            - EXTENSION_INIT — new extension process started
            - EXTENSION_KILLED — previous extension process was terminated
            - EXTENSION_GAP — no extension heartbeat for >5 minutes
            - INTERVAL_START/END — iOS daily monitoring cycle
            - MONITORING_RELOAD — thresholds refreshed
            """
        } else {
            logText = log
        }
    }

    private func clearLogs() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: "monitoring_lifecycle_log")
        logText = "(Logs cleared)"
    }

    private func copyLogs() {
        UIPasteboard.general.string = filteredLog
    }
}

#Preview {
    NavigationView {
        MonitoringLifecycleLogView()
    }
}
