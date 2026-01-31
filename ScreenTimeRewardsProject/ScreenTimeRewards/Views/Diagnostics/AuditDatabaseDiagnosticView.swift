import SwiftUI

/// Diagnostic view to verify SQLite audit database functionality
struct AuditDatabaseDiagnosticView: View {
    @State private var isLoading = true
    @State private var dbStats: (totalEvents: Int, uniqueApps: Int, oldestDate: String?, newestDate: String?)?
    @State private var todayCount = 0
    @State private var recentEvents: [(appID: String, date: String, minute: Int, timestamp: Date, secondsAdded: Int)] = []
    @State private var discrepancies: [UsageIntegrityValidator.Discrepancy] = []
    @State private var timestamps: (lastValidation: Date?, lastRepair: Date?, repairCount: Int) = (nil, nil, 0)
    @State private var dbPath: String?
    @State private var showExportSheet = false
    @State private var exportText = ""
    @State private var actionMessage: String?

    @Environment(\.colorScheme) var colorScheme

    private let validator = UsageIntegrityValidator.shared

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.regular) {
                    if isLoading {
                        loadingView
                    } else {
                        databaseStatusCard
                        eventStatisticsCard
                        recentActivityCard
                        integrityStatusCard
                        actionsCard
                    }
                }
                .padding(AppTheme.Spacing.regular)
            }
        }
        .navigationTitle("Audit Database")
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
        .alert("Action Result", isPresented: .constant(actionMessage != nil)) {
            Button("OK") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading database info...")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Database Status Card

    private var databaseStatusCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Database Status")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                statusRow(
                    icon: validator.isDatabaseAvailable ? "checkmark.circle.fill" : "xmark.circle.fill",
                    color: validator.isDatabaseAvailable ? .green : .red,
                    title: "Connection",
                    value: validator.isDatabaseAvailable ? "Connected" : "Not Connected"
                )

                if let path = dbPath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Database Path")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    // MARK: - Event Statistics Card

    private var eventStatisticsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Event Statistics")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                if let stats = dbStats {
                    statusRow(
                        icon: "number.circle.fill",
                        color: .blue,
                        title: "Total Events",
                        value: "\(stats.totalEvents)"
                    )

                    statusRow(
                        icon: "calendar.circle.fill",
                        color: .purple,
                        title: "Events Today",
                        value: "\(todayCount)"
                    )

                    statusRow(
                        icon: "app.badge.fill",
                        color: .orange,
                        title: "Unique Apps",
                        value: "\(stats.uniqueApps)"
                    )

                    if let oldest = stats.oldestDate, let newest = stats.newestDate {
                        statusRow(
                            icon: "calendar.badge.clock",
                            color: .gray,
                            title: "Date Range",
                            value: oldest == newest ? oldest : "\(oldest) → \(newest)"
                        )
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("No statistics available")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    // MARK: - Recent Activity Card

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Recent Activity")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                if recentEvents.isEmpty {
                    HStack {
                        Image(systemName: "tray.fill")
                            .foregroundColor(.gray)
                        Text("No events recorded yet")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                } else {
                    ForEach(Array(recentEvents.enumerated()), id: \.offset) { index, event in
                        eventRow(event, isLast: index == recentEvents.count - 1)
                    }
                }

                Divider()

                // Validation timestamps
                VStack(alignment: .leading, spacing: 8) {
                    if let lastValidation = timestamps.lastValidation {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Last Validation: \(formatRelativeTime(lastValidation))")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }

                    if let lastRepair = timestamps.lastRepair {
                        HStack {
                            Image(systemName: "wrench.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("Last Repair: \(formatRelativeTime(lastRepair)) (\(timestamps.repairCount) fixes)")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func eventRow(_ event: (appID: String, date: String, minute: Int, timestamp: Date, secondsAdded: Int), isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(event.appID.prefix(12)) + "...")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Text("+\(event.secondsAdded)s")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }

            HStack {
                Text("min \(event.minute)")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()

                Text(formatTimestamp(event.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .padding(.vertical, 6)

        if !isLast {
            Divider()
        }
    }

    // MARK: - Integrity Status Card

    private var integrityStatusCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Integrity Status")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: AppTheme.Spacing.small) {
                statusRow(
                    icon: discrepancies.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    color: discrepancies.isEmpty ? .green : .red,
                    title: "Data Integrity",
                    value: discrepancies.isEmpty ? "Healthy" : "\(discrepancies.count) Discrepancies"
                )

                if !discrepancies.isEmpty {
                    Divider()

                    ForEach(Array(discrepancies.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(d.appID.prefix(16)) + "...")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            HStack {
                                Text("UserDefaults: \(d.userDefaultsValue)s")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)

                                Text("→")
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                                Text("Database: \(d.databaseValue)s")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Button {
                runValidation()
            } label: {
                HStack {
                    Image(systemName: "checkmark.shield")
                    Text("Run Validation")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.vibrantTeal)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button {
                forceRepair()
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Force Repair")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(discrepancies.isEmpty ? Color.gray.opacity(0.3) : Color.orange)
                .foregroundColor(discrepancies.isEmpty ? .gray : .white)
                .cornerRadius(12)
            }
            .disabled(discrepancies.isEmpty)

            Button {
                exportDiagnostics()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Report")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.card(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        NavigationView {
            ScrollView {
                Text(exportText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Diagnostic Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showExportSheet = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        UIPasteboard.general.string = exportText
                        showExportSheet = false
                    }
                }
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
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true

        dbPath = validator.getDatabasePath()
        dbStats = validator.getDatabaseStats()
        todayCount = validator.getTodayEventCount()
        recentEvents = validator.getRecentEvents(limit: 5)
        timestamps = validator.getValidationTimestamps()

        // Get current discrepancies
        if let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") {
            let result = validator.validateUsageDataIntegrity(autoRepair: false)
            discrepancies = result.discrepancies
        }

        isLoading = false
    }

    private func refresh() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        loadData()
    }

    // MARK: - Actions

    private func runValidation() {
        let result = validator.validateUsageDataIntegrity(autoRepair: false)
        discrepancies = result.discrepancies
        timestamps = validator.getValidationTimestamps()

        if result.hasDiscrepancies {
            actionMessage = "Found \(result.discrepancies.count) discrepancies. Use 'Force Repair' to fix."
        } else {
            actionMessage = "Validation complete. No discrepancies found. \(result.totalEventsInDB) events in database."
        }
    }

    private func forceRepair() {
        let count = validator.forceRepair()
        loadData()

        if count > 0 {
            actionMessage = "Repaired \(count) discrepancies from database."
        } else {
            actionMessage = "No repairs needed."
        }
    }

    private func exportDiagnostics() {
        var report = "=== Audit Database Diagnostic Report ===\n"
        report += "Generated: \(Date())\n\n"

        report += "--- Database Status ---\n"
        report += "Connected: \(validator.isDatabaseAvailable)\n"
        report += "Path: \(dbPath ?? "Unknown")\n\n"

        report += "--- Statistics ---\n"
        if let stats = dbStats {
            report += "Total Events: \(stats.totalEvents)\n"
            report += "Events Today: \(todayCount)\n"
            report += "Unique Apps: \(stats.uniqueApps)\n"
            report += "Date Range: \(stats.oldestDate ?? "N/A") to \(stats.newestDate ?? "N/A")\n"
        } else {
            report += "No statistics available\n"
        }
        report += "\n"

        report += "--- Recent Events ---\n"
        for event in recentEvents {
            report += "[\(formatTimestamp(event.timestamp))] \(event.appID.prefix(16))... min=\(event.minute) +\(event.secondsAdded)s\n"
        }
        report += "\n"

        report += "--- Integrity Status ---\n"
        report += "Discrepancies: \(discrepancies.count)\n"
        for d in discrepancies {
            report += "  - \(d.appID.prefix(16))...: UD=\(d.userDefaultsValue)s, DB=\(d.databaseValue)s (diff: \(d.difference)s)\n"
        }
        report += "\n"

        report += "--- Timestamps ---\n"
        if let lastVal = timestamps.lastValidation {
            report += "Last Validation: \(lastVal)\n"
        }
        if let lastRep = timestamps.lastRepair {
            report += "Last Repair: \(lastRep) (\(timestamps.repairCount) fixes)\n"
        }

        exportText = report
        showExportSheet = true
    }

    // MARK: - Formatters

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        AuditDatabaseDiagnosticView()
    }
}
