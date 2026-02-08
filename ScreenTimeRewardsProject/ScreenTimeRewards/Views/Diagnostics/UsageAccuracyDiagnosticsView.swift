//
//  UsageAccuracyDiagnosticsView.swift
//  ScreenTimeRewards
//
//  Created by Claude on 2025-11-19.
//  Diagnostics view for usage tracking accuracy validation
//

import SwiftUI

@available(iOS 16.0, *)
struct UsageAccuracyDiagnosticsView: View {
    @StateObject private var validationService = UsageValidationService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingExportSheet = false
    @State private var diagnosticReport: String = ""
    @State private var showingResetConfirmation = false

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Validation Status Card
                    validationStatusCard

                    // Statistics Card
                    statisticsCard

                    // Detected Issues
                    if !validationService.detectedIssues.isEmpty {
                        issuesSection
                    }

                    // Recommendations
                    recommendationsSection

                    // Actions
                    actionsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Usage Accuracy")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [diagnosticReport])
        }
        .confirmationDialog("Reset Validation Data?",
                          isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                validationService.resetValidationState()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all validation history and detected issues. Tracking will continue normally.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage Tracking Accuracy")
                .font(.title2.bold())
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Monitor tracking health and detect iOS Screen Time API bugs.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Validation Status Card

    private var validationStatusCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 60, height: 60)

                    Image(systemName: validationService.validationStatus.systemImage)
                        .font(.system(size: 28))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(validationService.validationStatus.displayText)
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    if let lastValidation = validationService.lastValidationDate {
                        Text("Last checked: \(formatDate(lastValidation))")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    } else {
                        Text("Not yet validated")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Spacer()
            }

            // Status description
            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    // MARK: - Statistics Card

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Statistics")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            let snapshot = validationService.exportDiagnosticSnapshot()

            VStack(spacing: 12) {
                StatRow(
                    label: "iOS Version",
                    value: snapshot.iosVersion,
                    icon: "iphone",
                    color: .blue
                )

                StatRow(
                    label: "Device Model",
                    value: snapshot.deviceModel,
                    icon: "ipad",
                    color: .purple
                )

                StatRow(
                    label: "Apps Monitored",
                    value: "\(snapshot.totalAppsMonitored)",
                    icon: "app.badge",
                    color: AppTheme.vibrantTeal
                )

                StatRow(
                    label: "Total Tracked Usage",
                    value: formatDuration(snapshot.trackedUsageSeconds),
                    icon: "clock.fill",
                    color: AppTheme.sunnyYellow
                )

                StatRow(
                    label: "Threshold Events Fired",
                    value: "\(snapshot.thresholdEventsFired)",
                    icon: "bell.fill",
                    color: .orange
                )

                if let reliability = snapshot.extensionReliabilityRate {
                    StatRow(
                        label: "Extension Reliability",
                        value: "\(Int(reliability * 100))%",
                        icon: "checkmark.circle.fill",
                        color: reliability > 0.9 ? .green : .orange
                    )
                }
            }
        }
        .padding(20)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    // MARK: - Issues Section

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detected Issues")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: 12) {
                ForEach(validationService.detectedIssues) { issue in
                    IssueCard(issue: issue, colorScheme: colorScheme)
                }
            }
        }
    }

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Best Practices")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(alignment: .leading, spacing: 12) {
                RecommendationRow(
                    icon: "icloud.slash",
                    text: "Disable 'Share Across Devices' in iOS Settings → Screen Time",
                    color: .red
                )

                RecommendationRow(
                    icon: "apps.iphone",
                    text: "Keep app running in background (don't force-close)",
                    color: .blue
                )

                RecommendationRow(
                    icon: "iphone",
                    text: "Use single device for most accurate tracking",
                    color: .green
                )

                RecommendationRow(
                    icon: "app",
                    text: "Prefer native apps over web-based apps",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Export Diagnostic Report
            Button(action: exportDiagnosticReport) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))

                    Text("Export Diagnostic Report")
                        .font(.headline)

                    Spacer()
                }
                .foregroundColor(.white)
                .padding(16)
                .background(AppTheme.vibrantTeal)
                .cornerRadius(12)
            }

            // Reset Validation Data
            Button(action: { showingResetConfirmation = true }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18))

                    Text("Reset Validation Data")
                        .font(.headline)

                    Spacer()
                }
                .foregroundColor(AppTheme.error)
                .padding(16)
                .background(AppTheme.error.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch validationService.validationStatus {
        case .unknown: return .gray
        case .healthy: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var statusDescription: String {
        switch validationService.validationStatus {
        case .unknown:
            return "No validation has been performed yet. Use the app to generate tracking data."
        case .healthy:
            return "Usage tracking appears accurate. No significant issues detected."
        case .warning:
            return "Minor tracking issues detected. Review recommendations below."
        case .error:
            return "Significant tracking issues detected. Please review detected issues and follow recommended actions."
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        TimeFormatting.formatSecondsCompact(seconds)
    }

    private func exportDiagnosticReport() {
        diagnosticReport = validationService.exportDiagnosticReport()
        showingExportSheet = true
    }
}

// MARK: - Supporting Views

private struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Spacer()

            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }
}

private struct IssueCard: View {
    let issue: UsageValidationService.ValidationIssue
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: severityIcon)
                    .font(.system(size: 16))
                    .foregroundColor(severityColor)

                Text(issue.title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            Text(issue.description)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if let action = issue.recommendedAction {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text(action)
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(severityColor.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severityColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var severityIcon: String {
        switch issue.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private struct RecommendationRow: View {
    let icon: String
    let text: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Preview

struct UsageAccuracyDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            UsageAccuracyDiagnosticsView()
        }
    }
}
