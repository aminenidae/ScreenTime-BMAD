import SwiftUI
import CoreData

/// Full usage dashboard view with horizontal swipe navigation
/// Shown after tapping a device card from the carousel
struct ChildUsageDashboardView: View {
    let devices: [RegisteredDevice]
    let selectedDeviceID: String?

    @StateObject private var viewModel = ParentRemoteViewModel()
    @State private var currentIndex: Int = 0
    @Environment(\.colorScheme) var colorScheme
    
    init(devices: [RegisteredDevice], selectedDeviceID: String?) {
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        
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
        .navigationTitle(currentDevice?.deviceName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
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

// MARK: - Home Tab

private struct ChildHomeTabView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    let device: RegisteredDevice
    @Environment(\.colorScheme) var colorScheme

    var todayUsage: (learningTime: Int, rewardTime: Int) {
        let calendar = Calendar.current
        let todayRecords = viewModel.usageRecords.filter {
            calendar.isDateInToday($0.sessionStart ?? Date())
        }

        let learningTime = todayRecords
            .filter { $0.category == "Learning" }
            .reduce(0) { $0 + Int($1.totalSeconds) }

        let rewardTime = todayRecords
            .filter { $0.category == "Reward" }
            .reduce(0) { $0 + Int($1.totalSeconds) }

        return (learningTime, rewardTime)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Today's Summary
                TodaySummaryCards(
                    learningTime: todayUsage.learningTime,
                    rewardTime: todayUsage.rewardTime
                )

                // App Configuration Summary
                AppConfigSummary(
                    learningCount: viewModel.childLearningApps.count,
                    rewardCount: viewModel.childRewardApps.count
                )

                // Category Summaries (existing)
                if !viewModel.categorySummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Usage by Category")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .padding(.horizontal)

                        ForEach(viewModel.categorySummaries) { summary in
                            NavigationLink(destination: CategoryDetailView(summary: summary)) {
                                CategoryUsageCard(summary: summary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                        }
                    }
                }

                // Historical Reports (existing)
                HistoricalReportsView(viewModel: viewModel)
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.vertical)
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
                                categoryColor: AppTheme.vibrantTeal
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
                                categoryColor: AppTheme.playfulCoral
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
    @Environment(\.colorScheme) var colorScheme

    var displayName: String {
        if let name = app.displayName, !name.isEmpty, !name.hasPrefix("Unknown") {
            return name
        }
        let category = app.category ?? "Unknown"
        let appNumber = abs((app.logicalID ?? "").hashValue) % 100
        return "Privacy Protected \(category) App #\(appNumber)"
    }

    var usageTime: String {
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

                if usage != nil {
                    Text("Last 7 days")
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

    /// Total time from last 7 days of history
    var last7DaysTotal: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!

        return appHistory
            .filter { $0.date >= sevenDaysAgo }
            .reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        HStack(spacing: 12) {
            // App Icon placeholder with shield overlay
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: config.category == "Learning" ? "book.fill" : "gamecontroller.fill")
                            .foregroundColor(categoryColor)
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
                    Text("Last 7 days")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else {
                    Text("No usage yet")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            // Show historical total if available, otherwise fallback to session data
            if !appHistory.isEmpty {
                Text(TimeFormatting.formatSecondsCompact(TimeInterval(last7DaysTotal)))
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
