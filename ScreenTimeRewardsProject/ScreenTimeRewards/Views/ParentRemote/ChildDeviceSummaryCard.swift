import SwiftUI

struct ChildDeviceSummaryCard: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    // Load summary data for this specific device
    @State private var todayUsage: CategoryUsageSummary?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with device name and icon
            HStack {
                Image(systemName: deviceIcon)
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName ?? "Unknown Device")
                        .font(.headline)
                    Text("Last sync: \(lastSyncText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }

            Divider()

            // Quick stats
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let summary = todayUsage {
                HStack(spacing: 32) {
                    StatItem(
                        title: "Screen Time",
                        value: TimeFormatting.formatSecondsCompact(TimeInterval(summary.totalSeconds)),
                        icon: "clock.fill",
                        color: .blue
                    )

                    StatItem(
                        title: "Points Earned",
                        value: "\(summary.totalPoints)",
                        icon: "star.fill",
                        color: .orange
                    )

                    StatItem(
                        title: "Apps Used",
                        value: "\(summary.appCount)",
                        icon: "app.fill",
                        color: .green
                    )
                }
            } else {
                Text("No usage today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            loadSummary()
        }
    }

    private var deviceIcon: String {
        guard let type = device.deviceType else { return "iphone" }
        return type.lowercased().contains("ipad") ? "ipad" : "iphone"
    }

    private var lastSyncText: String {
        guard let lastSync = device.lastSyncDate else {
            return "Never"
        }

        let interval = Date().timeIntervalSince(lastSync)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return lastSync.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func loadSummary() {
        // Load today's usage summary for this device
        isLoading = true

        Task {
            await viewModel.loadDeviceSummary(for: device)

            // Get the loaded summary
            if let deviceID = device.deviceID,
               let summary = viewModel.deviceSummaries[deviceID] {
                await MainActor.run {
                    self.todayUsage = summary
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

private struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}