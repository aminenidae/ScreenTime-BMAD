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
                        title: String(localized: "Screen Time"),
                        value: TimeFormatting.formatSecondsCompact(TimeInterval(summary.totalSeconds)),
                        icon: "clock.fill",
                        color: .blue
                    )

                    StatItem(
                        title: String(localized: "Points Earned"),
                        value: "\(summary.totalPoints)",
                        icon: "star.fill",
                        color: .orange
                    )

                    StatItem(
                        title: String(localized: "Apps Used"),
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
            return String(localized: "Never")
        }

        let interval = Date().timeIntervalSince(lastSync)
        if interval < 60 {
            return String(localized: "Just now")
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return lastSync.formatted(date: .abbreviated, time: .omitted)
        }
    }

    /// Read today's summary directly from the on-disk per-child cache.
    ///
    /// We intentionally DO NOT call `viewModel.loadDeviceSummary` here —
    /// that path runs through `loadChildData`, which mutates the shared VM's
    /// `selectedChildDevice` and clears child-specific @Published state.
    /// With 5 cards appearing concurrently, the cascade thrashed
    /// `selectedChildDevice` between children, breaking the child-detail
    /// page's `isVMShowingThisDevice` spinner gate — tap a card, navigate,
    /// a later card fires and steals the selection, spinner stays on.
    ///
    /// The cached `dailySnapshot` already has the totals we display
    /// (screen-time seconds, earned points). No CK round-trip, no shared
    /// VM mutation, no contention between cards.
    private func loadSummary() {
        guard let deviceID = device.deviceID else {
            isLoading = false
            return
        }
        let parentID = DeviceModeManager.shared.deviceID
        guard !parentID.isEmpty,
              let snapshot = ParentDeviceCacheService.shared.loadCachedState(parentID: parentID),
              let child = snapshot.children.first(where: { $0.deviceID == deviceID }),
              let daily = child.dailySnapshot else {
            isLoading = false
            todayUsage = nil
            return
        }

        let totalSeconds = daily.totalLearningSeconds + daily.totalRewardSeconds
        // App count isn't stored on the daily snapshot — count distinct apps
        // from cached usage history for today.
        let todayKey = Calendar.current.startOfDay(for: Date())
        let todayAppCount = child.dailyUsageHistory?
            .filter { Calendar.current.startOfDay(for: $0.date) == todayKey && $0.seconds > 0 }
            .map { $0.logicalID }
            .reduce(into: Set<String>()) { $0.insert($1) }
            .count ?? 0

        todayUsage = CategoryUsageSummary(
            category: "All Apps",
            totalSeconds: totalSeconds,
            appCount: todayAppCount,
            totalPoints: daily.totalEarnedMinutes,
            apps: []
        )
        isLoading = false
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