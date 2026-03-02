import SwiftUI
import UIKit
import Combine

/// Dedicated viewer for background task scheduling and execution events.
/// Shows when BGTasks are registered, scheduled, started, completed, expired, or failed.
struct BackgroundTaskLogView: View {
    @State private var logText: String = "Loading..."
    @State private var autoRefresh = true
    @State private var filterText = ""
    @Environment(\.colorScheme) var colorScheme

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let appGroupID = "group.com.screentimerewards.shared"

    init(initialFilter: String = "") {
        _filterText = State(initialValue: initialFilter)
    }

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
                    TextField("Filter (e.g., MIDNIGHT, EXPIRED, FAILED)", text: $filterText)
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
        .navigationTitle("BGTask Log")
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
        let log = defaults.string(forKey: "bgtask_log") ?? ""
        if log.isEmpty {
            logText = """
            (No background task events yet)

            This log tracks background task lifecycle events:
            - REGISTER — background tasks registered with iOS
            - MIDNIGHT_RESET — midnight reset task (counter reset + threshold rebuild)
            - MIDNIGHT_SCHEDULE — next midnight task scheduled
            - USAGE_UPLOAD — usage upload to parent CloudKit
            - CONFIG_CHECK — configuration check from parent
            - SUB_VERIFY — subscription verification task
            - SHIELD_SYNC — shield state sync to parent
            - MONITORING_REFRESH — intra-day sliding window advancement (every 45 min)

            Status suffixes:
            - EXPIRED — iOS killed task before completion
            - FAILED — task encountered an error
            """
        } else {
            logText = log
        }
    }

    private func clearLogs() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: "bgtask_log")
        logText = "(Logs cleared)"
    }

    private func copyLogs() {
        UIPasteboard.general.string = filteredLog
    }
}

#Preview {
    NavigationView {
        BackgroundTaskLogView()
    }
}
