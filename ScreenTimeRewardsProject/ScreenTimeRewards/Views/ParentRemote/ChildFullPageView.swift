import SwiftUI
import CoreData

/// Full-page view showing complete child device data
/// Displayed in horizontal paging TabView on parent dashboard
struct ChildFullPageView: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    @State private var todayUsage: CategoryUsageSummary?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Device Header
                DeviceHeaderSection(device: device)

                // Today's Summary
                if let usage = todayUsage {
                    TodayUsageSummarySection(usage: usage)
                } else if isLoading {
                    ProgressView("Loading today's usage...")
                        .padding()
                } else {
                    NoUsageDataSection()
                }

                Divider()
                    .padding(.horizontal)

                // Detailed Statistics
                DetailedStatsSection(device: device, viewModel: viewModel)

                Divider()
                    .padding(.horizontal)

                // Historical Reports
                HistoricalReportsSection(device: device, viewModel: viewModel)

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .onAppear {
            Task {
                await loadDeviceData()
            }
        }
    }

    private func loadDeviceData() async {
        isLoading = true
        defer { isLoading = false }

        // Load today's summary for this specific device
        await viewModel.loadDeviceSummary(for: device)
        
        // Get the loaded summary from the view model
        if let deviceID = device.deviceID,
           let summary = viewModel.deviceSummaries[deviceID] {
            todayUsage = summary
        }
    }
}

// MARK: - Subviews

private struct DeviceHeaderSection: View {
    let device: RegisteredDevice

    var deviceIcon: String {
        // Determine icon based on device type
        if let deviceName = device.deviceName?.lowercased() {
            if deviceName.contains("ipad") {
                return "ipad"
            } else if deviceName.contains("iphone") {
                return "iphone"
            }
        }
        return "laptopcomputer"
    }

    var lastSyncText: String {
        guard let lastSync = device.lastSyncDate else {
            return "Never synced"
        }

        let now = Date()
        let interval = now.timeIntervalSince(lastSync)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Device icon
            Image(systemName: deviceIcon)
                .font(.system(size: 60))
                .foregroundColor(.blue)

            // Device name
            Text(device.deviceName ?? "Unknown Device")
                .font(.title)
                .fontWeight(.bold)

            // Last sync info
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Last sync: \(lastSyncText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Device ID (for debugging)
            #if DEBUG
            Text("ID: \(device.deviceID ?? "Unknown")")
                .font(.caption2)
                .foregroundColor(.gray)
            #endif
        }
        .padding(.top, 20)
    }
}

private struct TodayUsageSummarySection: View {
    let usage: CategoryUsageSummary

    var formattedTime: String {
        let hours = usage.totalSeconds / 3600
        let minutes = (usage.totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Today's Activity")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 32) {
                // Screen Time
                VStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text(formattedTime)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Screen Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                // Points Earned
                VStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)

                    Text("\(usage.totalPoints)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Points Earned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(12)
            }

            // Apps used count
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundColor(.secondary)

                Text("\(usage.appCount) learning apps used today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}

private struct NoUsageDataSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("No activity today")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Usage data will appear here once the child uses learning apps")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct DetailedStatsSection: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Usage Details")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // This would show the detailed app-by-app breakdown
            // Using RemoteUsageSummaryView if it exists, or create new detailed view
            RemoteUsageSummaryView(viewModel: viewModel)
        }
    }
}

private struct HistoricalReportsSection: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Recent History")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Show historical data
            HistoricalReportsView(viewModel: viewModel)
        }
    }
}

// MARK: - Preview

struct ChildFullPageView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock device for preview
        let mockDevice = RegisteredDevice()
        mockDevice.deviceName = "Child's iPhone"
        mockDevice.deviceID = "preview-device-id"
        mockDevice.lastSyncDate = Date()

        return ChildFullPageView(
            device: mockDevice,
            viewModel: ParentRemoteViewModel()
        )
    }
}