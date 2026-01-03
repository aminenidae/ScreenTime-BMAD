import SwiftUI
import CoreData

/// Full usage dashboard view with horizontal swipe navigation
/// Shown after tapping a device card from the carousel
struct ChildUsageDashboardView: View {
    let devices: [RegisteredDevice]
    let selectedDeviceID: String?
    /// When true, the view is embedded directly (single-device mode) rather than pushed via NavigationLink
    let isEmbedded: Bool

    @StateObject private var viewModel = ParentRemoteViewModel()
    @State private var currentIndex: Int = 0
    @Environment(\.colorScheme) var colorScheme

    init(devices: [RegisteredDevice], selectedDeviceID: String?, isEmbedded: Bool = false) {
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        self.isEmbedded = isEmbedded

        // Find initial index based on selected device
        if let id = selectedDeviceID,
           let index = devices.firstIndex(where: { $0.deviceID == id }) {
            _currentIndex = State(initialValue: index)
        }
    }
    
    var currentDevice: RegisteredDevice? {
        guard currentIndex < devices.count else { return nil }
        return devices[currentIndex]
    }
    
    var body: some View {
        ZStack {
            // App-themed gradient background
            AppTheme.Gradients.parentBackground(for: colorScheme)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(devices.enumerated()), id: \.element.deviceID) { index, device in
                    ChildUsagePageView(device: device, viewModel: viewModel)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // Hide page dots, use custom navigation
        }
        .navigationTitle(isEmbedded ? "" : (currentDevice?.deviceName ?? "Device"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only show device navigation controls when not embedded (multi-device mode)
            if !isEmbedded {
                ToolbarItem(placement: .principal) {
                    // Custom navigation header showing current device
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation {
                                currentIndex = max(0, currentIndex - 1)
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(currentIndex > 0 ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme))
                        }
                        .disabled(currentIndex == 0)

                        VStack(spacing: 2) {
                            Text(currentDevice?.deviceName ?? "Device")
                                .font(.headline)

                            Text("\(currentIndex + 1) of \(devices.count)")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }

                        Button(action: {
                            withAnimation {
                                currentIndex = min(devices.count - 1, currentIndex + 1)
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(currentIndex < devices.count - 1 ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme))
                        }
                        .disabled(currentIndex >= devices.count - 1)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Task {
                        if let device = currentDevice {
                            await viewModel.loadChildData(for: device)
                        }
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
        .onAppear {
            Task {
                await loadAllDeviceData()
            }
        }
    }
    
    private func loadAllDeviceData() async {
        await viewModel.loadLinkedChildDevices()
    }
}

/// Single page showing complete usage data for one child with Home/Learning/Rewards tabs
struct ChildUsagePageView: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel
    @State private var selectedTab = 0
    @State private var showRemoveConfirmation = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Stale device warning banner
            if device.isStale {
                StaleDeviceBanner(
                    deviceName: device.deviceName ?? "Device",
                    onRemove: { showRemoveConfirmation = true }
                )
            }

            // Tab Selector
            ChildTabSelector(selectedTab: $selectedTab)

            // Tab Content
            TabView(selection: $selectedTab) {
                // Home Tab - Overview
                ChildHomeTabView(viewModel: viewModel, device: device)
                    .tag(0)

                // Learning Tab - All learning apps with full config
                ChildLearningTabView(
                    apps: viewModel.childLearningApps,
                    fullConfigs: viewModel.childLearningAppsFullConfig,
                    usageRecords: viewModel.usageRecords,
                    historyByApp: viewModel.childDailyUsageByApp,
                    onConfigUpdated: { viewModel.updateAppConfig($0) }
                )
                .tag(1)

                // Rewards Tab - All reward apps with full config and shield states
                ChildRewardsTabView(
                    apps: viewModel.childRewardApps,
                    fullConfigs: viewModel.childRewardAppsFullConfig,
                    usageRecords: viewModel.usageRecords,
                    shieldStates: viewModel.childShieldStates,
                    historyByApp: viewModel.childDailyUsageByApp,
                    childLearningApps: viewModel.childLearningAppsFullConfig,
                    onConfigUpdated: { viewModel.updateAppConfig($0) }
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .refreshable {
            await viewModel.loadChildData(for: device)
        }
        .onAppear {
            Task {
                await viewModel.loadChildData(for: device)
            }
        }
        .alert("Remove Device?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Task {
                    let success = await viewModel.unpairChildDevice(device)
                    if success {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will remove \(device.deviceName ?? "this device") from your Family Dashboard. The device appears to be disconnected.")
        }
    }
}

/// Warning banner shown when viewing a stale/disconnected device
private struct StaleDeviceBanner: View {
    let deviceName: String
    let onRemove: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Device Disconnected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("This device's data may be outdated")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()

            Button("Remove") {
                onRemove()
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange)
            .cornerRadius(6)
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .overlay(
            Rectangle()
                .fill(Color.orange)
                .frame(height: 3),
            alignment: .top
        )
    }
}

// MARK: - Tab Selector

private struct ChildTabSelector: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) var colorScheme

    let tabs = [
        ("house.fill", "Home"),
        ("book.fill", "Learning"),
        ("gamecontroller.fill", "Rewards")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                ChildTabButton(
                    icon: tabs[index].0,
                    title: tabs[index].1,
                    isSelected: selectedTab == index
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.card(for: colorScheme))
    }
}

private struct ChildTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.vibrantTeal.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Home Tab (Unified Dashboard)

private struct ChildHomeTabView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    let device: RegisteredDevice
    @StateObject private var dataAdapter: RemoteDashboardDataAdapter
    @Environment(\.colorScheme) var colorScheme

    init(viewModel: ParentRemoteViewModel, device: RegisteredDevice) {
        self.viewModel = viewModel
        self.device = device
        _dataAdapter = StateObject(wrappedValue: RemoteDashboardDataAdapter(viewModel: viewModel))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Section 1: Usage Overview (with drill-down)
                UsageOverviewSection(dataProvider: dataAdapter)

                // Section 2: Time Bank
                TimeBankCard(
                    earnedMinutes: dataAdapter.earnedMinutes + dataAdapter.streakBonusMinutes,
                    usedMinutes: dataAdapter.usedMinutes
                )

                // Section 3: Streaks Summary
                StreaksSummarySection(dataProvider: dataAdapter)

                // Section 4: Daily/Weekly Trends Chart
                RemoteDailyUsageChartCard(dataProvider: dataAdapter)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }
}

// MARK: - Remote Daily Usage Chart Card

/// Chart card for remote context using DashboardDataProvider
private struct RemoteDailyUsageChartCard<Provider: DashboardDataProvider>: View {
    @ObservedObject var dataProvider: Provider
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Trends")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            if dataProvider.dailyTotals.isEmpty {
                Text("No usage data available yet")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Simple bar chart showing last 7 days
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(last7Days, id: \.date) { day in
                        DailyBar(
                            date: day.date,
                            learningMinutes: day.learningMinutes,
                            rewardMinutes: day.rewardMinutes,
                            maxMinutes: maxDailyMinutes
                        )
                    }
                }
                .frame(height: 120)
                .padding(.vertical, 8)

                // Legend
                HStack(spacing: 20) {
                    LegendItem(color: AppTheme.vibrantTeal, label: "Learning")
                    LegendItem(color: AppTheme.playfulCoral, label: "Rewards")
                }
                .font(.caption)
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
    }

    private var last7Days: [DailyUsageTotals] {
        let sorted = dataProvider.dailyTotals.sorted { $0.date < $1.date }
        return Array(sorted.suffix(7))
    }

    private var maxDailyMinutes: Int {
        let max = last7Days.map { $0.learningMinutes + $0.rewardMinutes }.max() ?? 1
        return Swift.max(max, 1) // Avoid division by zero
    }
}

private struct DailyBar: View {
    let date: Date
    let learningMinutes: Int
    let rewardMinutes: Int
    let maxMinutes: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            // Stacked bars
            VStack(spacing: 0) {
                // Reward portion (top)
                Rectangle()
                    .fill(AppTheme.playfulCoral)
                    .frame(height: barHeight(for: rewardMinutes))

                // Learning portion (bottom)
                Rectangle()
                    .fill(AppTheme.vibrantTeal)
                    .frame(height: barHeight(for: learningMinutes))
            }
            .cornerRadius(4)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // Day label
            Text(dayLabel)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func barHeight(for minutes: Int) -> CGFloat {
        guard maxMinutes > 0 else { return 0 }
        return CGFloat(minutes) / CGFloat(maxMinutes) * 80 // Max bar height
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date).prefix(1).uppercased()
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

private struct TodaySummaryCards: View {
    let learningTime: Int
    let rewardTime: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Activity")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal)

            HStack(spacing: 12) {
                SummaryStatCard(
                    icon: "book.fill",
                    value: TimeFormatting.formatSecondsCompact(TimeInterval(learningTime)),
                    label: "Learning",
                    color: AppTheme.vibrantTeal
                )

                SummaryStatCard(
                    icon: "gamecontroller.fill",
                    value: TimeFormatting.formatSecondsCompact(TimeInterval(rewardTime)),
                    label: "Rewards",
                    color: AppTheme.playfulCoral
                )
            }
            .padding(.horizontal)
        }
    }
}

private struct SummaryStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct AppConfigSummary: View {
    let learningCount: Int
    let rewardCount: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("\(learningCount) learning apps")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(AppTheme.playfulCoral)
                Text("\(rewardCount) reward apps")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Learning Tab

private struct ChildLearningTabView: View {
    let apps: [AppConfiguration]
    let fullConfigs: [FullAppConfigDTO]
    let usageRecords: [UsageRecord]
    let historyByApp: [String: [DailyUsageHistoryDTO]]
    var onConfigUpdated: ((FullAppConfigDTO) -> Void)?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if fullConfigs.isEmpty && apps.isEmpty {
                    EmptyAppListView(category: "Learning")
                } else {
                    Text("\(fullConfigs.isEmpty ? apps.count : fullConfigs.count) Learning Apps")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Use full configs if available, otherwise fall back to basic
                    if !fullConfigs.isEmpty {
                        ForEach(fullConfigs) { config in
                            NavigationLink {
                                ParentAppDetailView(
                                    config: config,
                                    shieldState: nil,
                                    appHistory: historyByApp[config.logicalID] ?? [],
                                    childLearningApps: fullConfigs,
                                    onConfigUpdated: onConfigUpdated
                                )
                            } label: {
                                FullAppConfigRow(
                                    config: config,
                                    usage: usageRecords.first { $0.logicalID == config.logicalID },
                                    categoryColor: AppTheme.vibrantTeal,
                                    appHistory: historyByApp[config.logicalID] ?? []
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                        }
                    } else {
                        ForEach(apps, id: \.logicalID) { app in
                            AppConfigRow(
                                app: app,
                                usage: usageRecords.first { $0.logicalID == app.logicalID },
                                categoryColor: AppTheme.vibrantTeal,
                                appHistory: historyByApp[app.logicalID ?? ""] ?? []
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Rewards Tab

private struct ChildRewardsTabView: View {
    let apps: [AppConfiguration]
    let fullConfigs: [FullAppConfigDTO]
    let usageRecords: [UsageRecord]
    let shieldStates: [String: ShieldStateDTO]
    let historyByApp: [String: [DailyUsageHistoryDTO]]
    let childLearningApps: [FullAppConfigDTO]  // For linked apps in edit sheet
    var onConfigUpdated: ((FullAppConfigDTO) -> Void)?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if fullConfigs.isEmpty && apps.isEmpty {
                    EmptyAppListView(category: "Reward")
                } else {
                    Text("\(fullConfigs.isEmpty ? apps.count : fullConfigs.count) Reward Apps")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Use full configs if available, otherwise fall back to basic
                    if !fullConfigs.isEmpty {
                        ForEach(fullConfigs) { config in
                            NavigationLink {
                                ParentAppDetailView(
                                    config: config,
                                    shieldState: shieldStates[config.logicalID],
                                    appHistory: historyByApp[config.logicalID] ?? [],
                                    childLearningApps: childLearningApps,
                                    onConfigUpdated: onConfigUpdated
                                )
                            } label: {
                                FullAppConfigRow(
                                    config: config,
                                    usage: usageRecords.first { $0.logicalID == config.logicalID },
                                    categoryColor: AppTheme.playfulCoral,
                                    shieldState: shieldStates[config.logicalID],
                                    appHistory: historyByApp[config.logicalID] ?? []
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                        }
                    } else {
                        ForEach(apps, id: \.logicalID) { app in
                            AppConfigRow(
                                app: app,
                                usage: usageRecords.first { $0.logicalID == app.logicalID },
                                categoryColor: AppTheme.playfulCoral,
                                appHistory: historyByApp[app.logicalID ?? ""] ?? []
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Shared Components

private struct EmptyAppListView: View {
    let category: String
    @Environment(\.colorScheme) var colorScheme

    var icon: String {
        category == "Learning" ? "book.fill" : "gamecontroller.fill"
    }

    var color: Color {
        category == "Learning" ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(color.opacity(0.5))

            Text("No \(category.lowercased()) apps configured")
                .font(.headline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("Apps will appear here when your child adds them")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

private struct AppConfigRow: View {
    let app: AppConfiguration
    let usage: UsageRecord?
    let categoryColor: Color
    var appHistory: [DailyUsageHistoryDTO] = []
    @Environment(\.colorScheme) var colorScheme

    var displayName: String {
        if let name = app.displayName, !name.isEmpty, !name.hasPrefix("Unknown") {
            return name
        }
        let category = app.category ?? "Unknown"
        let appNumber = abs((app.logicalID ?? "").hashValue) % 100
        return "Privacy Protected \(category) App #\(appNumber)"
    }

    /// Today's usage from daily history
    var todayTotal: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appHistory
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.seconds }
    }

    var usageTime: String {
        if !appHistory.isEmpty {
            return TimeFormatting.formatSecondsCompact(TimeInterval(todayTotal))
        }
        guard let record = usage else { return "0m" }
        return TimeFormatting.formatSecondsCompact(TimeInterval(record.totalSeconds))
    }

    var body: some View {
        HStack(spacing: 12) {
            // App Icon placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(categoryColor.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: app.category == "Learning" ? "book.fill" : "gamecontroller.fill")
                        .foregroundColor(categoryColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)

                if !appHistory.isEmpty || usage != nil {
                    Text("Today's Usage")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else {
                    Text("No usage yet")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            Text(usageTime)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
    }
}

// MARK: - Full App Config Row (with schedule, goals, streaks)

private struct FullAppConfigRow: View {
    let config: FullAppConfigDTO
    let usage: UsageRecord?
    let categoryColor: Color
    var shieldState: ShieldStateDTO? = nil
    var appHistory: [DailyUsageHistoryDTO] = []
    @Environment(\.colorScheme) var colorScheme

    var displayName: String {
        if !config.displayName.isEmpty && !config.displayName.hasPrefix("Unknown") {
            return config.displayName
        }
        let appNumber = abs(config.logicalID.hashValue) % 100
        return "Privacy Protected \(config.category) App #\(appNumber)"
    }

    var usageTime: String {
        guard let record = usage else { return "0m" }
        return TimeFormatting.formatSecondsCompact(TimeInterval(record.totalSeconds))
    }

    /// Today's usage from daily history
    var todayTotal: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appHistory
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        HStack(spacing: 12) {
            // App Icon with shield overlay
            ZStack(alignment: .bottomTrailing) {
                CachedAppIcon(
                    iconURL: config.iconURL,
                    identifier: config.logicalID,
                    size: 50,
                    fallbackSymbol: config.category == "Learning" ? "book.fill" : "gamecontroller.fill"
                )

                // Shield state indicator (for reward apps only)
                if let state = shieldState {
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(state.isUnlocked ? .green : .red)
                        .padding(3)
                        .background(Circle().fill(Color(UIColor.systemBackground)))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)

                    // Inline shield status badge
                    if let state = shieldState {
                        Text(state.isUnlocked ? "UNLOCKED" : "BLOCKED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(state.isUnlocked ? Color.green : Color.red)
                            .cornerRadius(4)
                    }
                }

                if !appHistory.isEmpty || usage != nil {
                    Text("Today's Usage")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else {
                    Text("No usage yet")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            // Show today's usage if available, otherwise fallback to session data
            if !appHistory.isEmpty {
                Text(TimeFormatting.formatSecondsCompact(TimeInterval(todayTotal)))
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            } else {
                Text(usageTime)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            // Chevron indicator for navigation
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
    }
}

struct ChildUsageDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        // Note: Preview requires Core Data context which is not available here
        // For now, we'll just show a placeholder
        
        return Text("Child Usage Dashboard")
    }
}
