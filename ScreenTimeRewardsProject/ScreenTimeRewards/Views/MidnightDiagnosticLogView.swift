import SwiftUI
import Combine
import UIKit

/// Dedicated viewer for midnight diagnostic events.
/// Captures EVERYTHING between midnight (intervalDidStart) and the first scheduleActivity() call.
/// Immune to regular debug log trimming — helps diagnose cross-midnight catch-up overcounting.
struct MidnightDiagnosticLogView: View {
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
                    TextField("Filter (e.g., SKIP, RECORD, SCHEDULE)", text: $filterText)
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
        .navigationTitle("Midnight Diagnostic")
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
        let log = defaults.string(forKey: "midnight_diagnostic_log") ?? ""
        if log.isEmpty {
            logText = """
            (No midnight diagnostic data yet)

            This log captures events between midnight (intervalDidStart)
            and the first scheduleActivity() call.

            It helps diagnose cross-midnight catch-up overcounting.
            Data is cleared each midnight and preserved until the next midnight.

            Event types:
            - MIDNIGHT_START — intervalDidStart fired
            - APP_STATE — per-app state dump at midnight
            - DIAG_SKIP_* — events blocked by filters
            - DIAG_NEW_DAY — first event of new day recorded
            - DIAG_INCREMENT — subsequent event recorded
            - SCHEDULE_READ — scheduleActivity reading ext_usage
            - SCHEDULE_WINDOW — threshold window being registered
            - DIAGNOSTIC_CLOSED — scheduleActivity completed
            """
        } else {
            logText = log
        }
    }

    private func clearLogs() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: "midnight_diagnostic_log")
        logText = "(Logs cleared)"
    }

    private func copyLogs() {
        UIPasteboard.general.string = filteredLog
    }
}

#Preview {
    NavigationView {
        MidnightDiagnosticLogView()
    }
}
