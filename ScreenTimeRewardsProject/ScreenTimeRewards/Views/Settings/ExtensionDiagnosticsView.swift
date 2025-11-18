import SwiftUI

/// Diagnostic view to troubleshoot extension execution and tracking issues
struct ExtensionDiagnosticsView: View {
    @State private var diagnosticData: DiagnosticData?
    @State private var isRefreshing = false
    @State private var showExportSheet = false
    @State private var exportText = ""

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.regular) {
                    if let data = diagnosticData {
                        extensionStatusCard(data)
                        heartbeatCard(data)
                        eventMappingsCard(data)
                        errorLogCard(data)
                        actionsCard()
                    } else {
                        loadingView
                    }
                }
                .padding(AppTheme.Spacing.regular)
            }
        }
        .navigationTitle("Extension Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refresh()
        }
        .onAppear {
            loadData()
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheet
        }
    }

    // MARK: - Extension Status Card

    @ViewBuilder
    private func extensionStatusCard(_ data: DiagnosticData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Extension Status")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                statusRow(
                    icon: data.isExtensionInitialized ? "checkmark.circle.fill" : "xmark.circle.fill",
                    color: data.isExtensionInitialized ? .green : .red,
                    title: "Extension Initialized",
                    value: data.isExtensionInitialized ? "Yes" : "No"
                )

                if let initTime = data.extensionInitTime {
                    statusRow(
                        icon: "clock.fill",
                        color: .blue,
                        title: "Last Init",
                        value: formatRelativeTime(initTime)
                    )
                }

                statusRow(
                    icon: "memorychip.fill",
                    color: memoryColor(data.memoryUsageMB),
                    title: "Memory Usage",
                    value: String(format: "%.1f MB / 6 MB", data.memoryUsageMB)
                )
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    // MARK: - Heartbeat Card

    @ViewBuilder
    private func heartbeatCard(_ data: DiagnosticData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Heartbeat Monitor")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                statusRow(
                    icon: data.isHeartbeatHealthy ? "heart.fill" : "heart.slash.fill",
                    color: data.isHeartbeatHealthy ? .green : .red,
                    title: "Status",
                    value: data.isHeartbeatHealthy ? "Healthy" : "Unhealthy"
                )

                if let lastHeartbeat = data.lastHeartbeat {
                    statusRow(
                        icon: "clock.arrow.circlepath",
                        color: .secondary,
                        title: "Last Heartbeat",
                        value: formatRelativeTime(lastHeartbeat)
                    )

                    statusRow(
                        icon: "hourglass",
                        color: data.heartbeatGapSeconds > 120 ? .orange : .green,
                        title: "Gap",
                        value: "\(data.heartbeatGapSeconds)s"
                    )
                } else {
                    Text("No heartbeat data available")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.vertical, AppTheme.Spacing.small)
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    // MARK: - Event Mappings Card

    @ViewBuilder
    private func eventMappingsCard(_ data: DiagnosticData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Event Mappings (\(data.eventMappings.count))")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                if data.eventMappings.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("No event mappings found!")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                } else {
                    let sortedMappings = data.eventMappings.sorted(by: { $0.key < $1.key })
                    ForEach(Array(sortedMappings.enumerated()), id: \.element.key) { index, element in
                        eventMappingRow(eventName: element.key, mapping: element.value, isLast: index == sortedMappings.count - 1)
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func eventMappingRow(eventName: String, mapping: EventMappingInfo, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mapping.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Event: \(eventName)")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            HStack(spacing: 12) {
                Label("\(mapping.category)", systemImage: "tag.fill")
                Label("\(mapping.rewardPoints)pts/min", systemImage: "star.fill")
                Label("\(mapping.thresholdSeconds)s", systemImage: "clock.fill")
                if let increment = mapping.incrementSeconds {
                    Label("+\(increment)s", systemImage: "arrowtriangle.right.fill")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 8)

        if !isLast {
            Divider()
        }
    }

    // MARK: - Error Log Card

    @ViewBuilder
    private func errorLogCard(_ data: DiagnosticData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Error Log (\(data.errorLog.count))")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                if data.errorLog.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No errors recorded")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                } else {
                    let displayedErrors = Array(data.errorLog.prefix(10))
                    ForEach(Array(displayedErrors.enumerated()), id: \.element.id) { index, error in
                        errorRow(error, isLast: index == displayedErrors.count - 1)
                    }

                    if data.errorLog.count > 10 {
                        Text("Showing 10 of \(data.errorLog.count) errors")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .padding(.top, 8)
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func errorRow(_ error: ErrorLogEntry, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: error.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(error.success ? .green : .red)
                    .font(.system(size: 12))

                Text(error.action)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Text(String(format: "%.1fMB", error.memoryUsageMB))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            if let errorDesc = error.errorDescription {
                Text(errorDesc)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }

            Text(formatTimestamp(error.timestamp))
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 8)

        if !isLast {
            Divider()
        }
    }

    // MARK: - Actions Card

    @ViewBuilder
    private func actionsCard() -> some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Button {
                Task {
                    await ScreenTimeService.shared.restartMonitoring(
                        reason: "settings_extension_diagnostics_button",
                        force: true
                    )
                    await refresh()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Restart Monitoring")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.vibrantTeal)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button {
                exportDiagnostics()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Diagnostics")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.card(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.textSecondary(for: colorScheme).opacity(0.3), lineWidth: 1)
                )
            }

            Button {
                clearLogs()
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Error Log")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.card(for: colorScheme))
                .foregroundColor(.red)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func statusRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }

    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ProgressView()
            Text("Loading diagnostics...")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exportSheet: some View {
        NavigationView {
            ScrollView {
                Text(exportText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Diagnostics Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: exportText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        showExportSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            diagnosticData = DiagnosticData.empty
            return
        }

        // Extension initialization
        let isInitialized = defaults.bool(forKey: "extension_initialized_flag")
        let initTimestamp = defaults.double(forKey: "extension_initialized")
        let initTime = initTimestamp > 0 ? Date(timeIntervalSince1970: initTimestamp) : nil

        // Heartbeat
        let heartbeatTimestamp = defaults.double(forKey: "extension_heartbeat")
        let lastHeartbeat = heartbeatTimestamp > 0 ? Date(timeIntervalSince1970: heartbeatTimestamp) : nil
        let heartbeatGap = heartbeatTimestamp > 0 ? Int(Date().timeIntervalSince1970 - heartbeatTimestamp) : 0
        let isHealthy = heartbeatGap < 120

        // Memory
        let memoryMB = defaults.double(forKey: "extension_memory_mb")

        // Event mappings
        var mappings: [String: EventMappingInfo] = [:]
        if let data = defaults.data(forKey: "eventMappings"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for (eventName, info) in json {
                if let logicalID = info["logicalID"] as? String,
                   let displayName = info["displayName"] as? String,
                   let category = info["category"] as? String,
                   let rewardPoints = info["rewardPoints"] as? Int,
                   let thresholdSeconds = info["thresholdSeconds"] as? Int {
                    let incrementSeconds = info["incrementSeconds"] as? Int
                    mappings[eventName] = EventMappingInfo(
                        logicalID: logicalID,
                        displayName: displayName,
                        category: category,
                        rewardPoints: rewardPoints,
                        thresholdSeconds: thresholdSeconds,
                        incrementSeconds: incrementSeconds
                    )
                }
            }
        }

        // Error log
        let errorLog = ExtensionErrorLogReader.readAll()

        diagnosticData = DiagnosticData(
            isExtensionInitialized: isInitialized,
            extensionInitTime: initTime,
            lastHeartbeat: lastHeartbeat,
            heartbeatGapSeconds: heartbeatGap,
            isHeartbeatHealthy: isHealthy,
            memoryUsageMB: memoryMB,
            eventMappings: mappings,
            errorLog: errorLog.map {
                ErrorLogEntry(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    eventName: $0.eventName,
                    success: $0.success,
                    errorDescription: $0.errorDescription,
                    memoryUsageMB: $0.memoryUsageMB,
                    action: $0.action
                )
            }
        )
    }

    private func refresh() async {
        isRefreshing = true
        loadData()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s for UX
        isRefreshing = false
    }

    private func clearLogs() {
        ExtensionErrorLogReader.clear()
        loadData()
    }

    private func exportDiagnostics() {
        guard let data = diagnosticData else { return }

        var report = "Screen Time Rewards - Extension Diagnostics\n"
        report += "Generated: \(Date().formatted())\n\n"

        report += "=== EXTENSION STATUS ===\n"
        report += "Initialized: \(data.isExtensionInitialized ? "Yes" : "No")\n"
        if let initTime = data.extensionInitTime {
            report += "Last Init: \(formatRelativeTime(initTime))\n"
        }
        report += "Memory: \(String(format: "%.1f MB", data.memoryUsageMB))\n\n"

        report += "=== HEARTBEAT ===\n"
        report += "Status: \(data.isHeartbeatHealthy ? "Healthy" : "Unhealthy")\n"
        if let lastHeartbeat = data.lastHeartbeat {
            report += "Last Heartbeat: \(formatRelativeTime(lastHeartbeat))\n"
            report += "Gap: \(data.heartbeatGapSeconds)s\n"
        } else {
            report += "No heartbeat data\n"
        }
        report += "\n"

        report += "=== EVENT MAPPINGS (\(data.eventMappings.count)) ===\n"
        if data.eventMappings.isEmpty {
            report += "No event mappings found!\n"
        } else {
            for (eventName, mapping) in data.eventMappings.sorted(by: { $0.key < $1.key }) {
                report += "\(eventName):\n"
                report += "  App: \(mapping.displayName)\n"
                report += "  ID: \(mapping.logicalID)\n"
                report += "  Category: \(mapping.category)\n"
                report += "  Rewards: \(mapping.rewardPoints)pts/min\n"
                report += "  Threshold: \(mapping.thresholdSeconds)s\n"
                if let increment = mapping.incrementSeconds {
                    report += "  Increment: \(increment)s\n"
                }
            }
        }
        report += "\n"

        report += "=== ERROR LOG (\(data.errorLog.count)) ===\n"
        if data.errorLog.isEmpty {
            report += "No errors\n"
        } else {
            for error in data.errorLog {
                report += "[\(formatTimestamp(error.timestamp))] \(error.action)\n"
                report += "  Success: \(error.success)\n"
                if let errorDesc = error.errorDescription {
                    report += "  Error: \(errorDesc)\n"
                }
                report += "  Memory: \(String(format: "%.1fMB", error.memoryUsageMB))\n"
            }
        }

        exportText = report
        showExportSheet = true
    }

    // MARK: - Formatting Helpers

    private func formatRelativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .shortened)
    }

    private func memoryColor(_ memoryMB: Double) -> Color {
        if memoryMB > 5.5 {
            return .red
        } else if memoryMB > 4.5 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Data Models

private struct DiagnosticData {
    let isExtensionInitialized: Bool
    let extensionInitTime: Date?
    let lastHeartbeat: Date?
    let heartbeatGapSeconds: Int
    let isHeartbeatHealthy: Bool
    let memoryUsageMB: Double
    let eventMappings: [String: EventMappingInfo]
    let errorLog: [ErrorLogEntry]

    static var empty: DiagnosticData {
        DiagnosticData(
            isExtensionInitialized: false,
            extensionInitTime: nil,
            lastHeartbeat: nil,
            heartbeatGapSeconds: 0,
            isHeartbeatHealthy: false,
            memoryUsageMB: 0,
            eventMappings: [:],
            errorLog: []
        )
    }
}

private struct EventMappingInfo {
    let logicalID: String
    let displayName: String
    let category: String
    let rewardPoints: Int
    let thresholdSeconds: Int
    let incrementSeconds: Int?
}

private struct ErrorLogEntry: Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let eventName: String
    let success: Bool
    let errorDescription: String?
    let memoryUsageMB: Double
    let action: String
}

// MARK: - Extension Error Log Reader

private enum ExtensionErrorLogReader {
    private static let logKey = "extension_error_log"
    private static let appGroupIdentifier = "group.com.screentimerewards.shared"

    struct Entry: Codable, Identifiable {
        let id: UUID
        let timestamp: TimeInterval
        let eventName: String
        let success: Bool
        let errorDescription: String?
        let memoryUsageMB: Double
        let action: String
    }

    static func readAll() -> [Entry] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: logKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.removeObject(forKey: logKey)
        defaults.synchronize()
    }
}
