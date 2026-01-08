import SwiftUI

/// Detailed view for an app in the parent dashboard
/// Shows comprehensive app information including usage history, schedule, and unlock requirements
struct ParentAppDetailView: View {
    let config: FullAppConfigDTO
    var shieldState: ShieldStateDTO?
    var appHistory: [DailyUsageHistoryDTO]
    var childLearningApps: [FullAppConfigDTO] = []  // For linked apps picker
    var onConfigUpdated: ((FullAppConfigDTO) -> Void)?  // Callback to update ViewModel

    @State private var selectedTimeRange: TimeRange = .daily
    @State private var isEditSheetPresented = false
    @State private var editingConfig: MutableAppConfigDTO?
    @State private var syncStatus: ConfigSyncStatus = .idle
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    enum ConfigSyncStatus {
        case idle, sending, success, failed
    }

    enum TimeRange: String, CaseIterable {
        case daily = "7 DAYS"
        case weekly = "4 WEEKS"
        case monthly = "6 MONTHS"

        var days: Int {
            switch self {
            case .daily: return 7
            case .weekly: return 28
            case .monthly: return 180
            }
        }
    }

    // MARK: - Computed Properties

    var displayName: String {
        if !config.displayName.isEmpty && !config.displayName.hasPrefix("Unknown") {
            return config.displayName
        }
        let appNumber = abs(config.logicalID.hashValue) % 100
        return "Privacy Protected \(config.category) App #\(appNumber)"
    }

    var categoryColor: Color {
        config.category == "Learning" ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    var filteredHistory: [DailyUsageHistoryDTO] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -selectedTimeRange.days, to: today)!
        return appHistory.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    var totalSeconds: Int {
        filteredHistory.reduce(0) { $0 + $1.seconds }
    }

    var todaySeconds: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appHistory.first { calendar.isDate($0.date, inSameDayAs: today) }?.seconds ?? 0
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Streak Bonus (if enabled) - right below header
                    if let streak = config.streakSettings, streak.isEnabled {
                        streakBonusSection(streak)
                    }

                    // Usage Summary
                    usageSummaryCard

                    // Usage Chart
                    usageChartSection

                    // Schedule (if configured)
                    if config.scheduleConfig != nil {
                        scheduleSection
                    }

                    // Unlock Requirements (Reward apps only)
                    if config.category == "Reward" && !config.linkedLearningApps.isEmpty {
                        unlockRequirementsSection
                    }

                    // Bottom padding for FAB
                    Color.clear.frame(height: 80)
                }
                .padding()
            }

            // Floating Configure Button
            configureButton
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditSheetPresented) {
            ZStack {
                ParentAppEditSheet(
                    config: $editingConfig,
                    childLearningApps: childLearningApps.filter { $0.category == "Learning" },
                    onSave: { updatedConfig in
                        Task {
                            await sendConfigUpdate(updatedConfig)
                        }
                    },
                    onCancel: {
                        isEditSheetPresented = false
                        editingConfig = nil
                    }
                )

                // Saving overlay
                if syncStatus == .sending {
                    SavingConfigOverlayView(appName: config.displayName)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: syncStatus)
        }
        .alert(syncStatus == .success ? "Changes Sent" : "Sync Error", isPresented: $showingSyncAlert) {
            Button("OK") {
                if syncStatus == .success {
                    isEditSheetPresented = false
                    editingConfig = nil
                }
            }
        } message: {
            Text(syncAlertMessage)
        }
    }

    // MARK: - Floating Configure Button
    private var configureButton: some View {
        VStack(spacing: 0) {
            // Gradient overlay for smooth transition
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.background(for: colorScheme).opacity(0),
                    AppTheme.background(for: colorScheme)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                editingConfig = MutableAppConfigDTO(from: config)
                isEditSheetPresented = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                    Text("CONFIGURE")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(categoryColor)
                )
                .shadow(color: categoryColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
        }
    }

    // MARK: - Edit Actions

    private func sendConfigUpdate(_ updatedConfig: MutableAppConfigDTO) async {
        syncStatus = .sending

        let payload = FullConfigUpdatePayload(
            from: updatedConfig,
            parentDeviceID: DeviceModeManager.shared.deviceID
        )

        do {
            // Send command directly to CloudKit shared zone (not via Core Data)
            try await CloudKitSyncService.shared.sendConfigCommandToSharedZone(
                deviceID: updatedConfig.deviceID,
                payload: payload
            )

            await MainActor.run {
                syncStatus = .success
                syncAlertMessage = "Changes have been sent to the child's device. They will apply when the device syncs."
                showingSyncAlert = true

                // Optimistic update: update ViewModel immediately
                let updatedFullConfig = config.applying(changes: updatedConfig)
                onConfigUpdated?(updatedFullConfig)
            }
        } catch {
            await MainActor.run {
                syncStatus = .failed
                syncAlertMessage = "Failed to send changes: \(error.localizedDescription)"
                showingSyncAlert = true
            }
        }
    }

    // MARK: - Header Section (matches AppDetailHeaderView style)

    private var headerSection: some View {
        HStack(spacing: AppTheme.Spacing.regular) {
            // App icon using CachedAppIcon
            ZStack(alignment: .bottomTrailing) {
                // Icon with background for visibility
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 56, height: 56)

                    CachedAppIcon(
                        iconURL: config.iconURL,
                        identifier: config.logicalID,
                        size: 56,
                        fallbackSymbol: config.category == "Learning" ? "book.fill" : "gamecontroller.fill"
                    )
                }

                // Shield state indicator
                if let state = shieldState {
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(state.isUnlocked ? .green : .red)
                        .padding(3)
                        .background(Circle().fill(Color(UIColor.systemBackground)))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                // App name
                Text(displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .lineLimit(1)
                    .textCase(.uppercase)

                // Category badge
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: config.category == "Learning" ? "book.fill" : "gift.fill")
                        .font(.system(size: 10))

                    Text(config.category == "Learning" ? "LEARNING" : "REWARD")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)

                    // Status Badge (for reward apps)
                    if let state = shieldState {
                        Text("•")
                            .font(.system(size: 10))
                        Text(state.isUnlocked ? "UNLOCKED" : "BLOCKED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(state.isUnlocked ? .green : .red)
                    }
                }
                .foregroundColor(config.category == "Learning" ? AppTheme.brandedText(for: colorScheme) : categoryColor)
                .padding(.horizontal, AppTheme.Spacing.regular)
                .padding(.vertical, AppTheme.Spacing.tiny)
                .background(
                    Capsule()
                        .fill(categoryColor.opacity(0.15))
                )
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }

    // MARK: - Usage Summary Card

    private var usageSummaryCard: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor)

                Text("USAGE SUMMARY")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()
            }

            HStack(spacing: 20) {
                // Last N Days
                VStack(spacing: 4) {
                    Text(TimeFormatting.formatSeconds(totalSeconds))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(categoryColor)
                    Text("LAST \(selectedTimeRange.days) DAYS")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(AppTheme.border(for: colorScheme))
                    .frame(width: 1, height: 40)

                // Today
                VStack(spacing: 4) {
                    Text(TimeFormatting.formatSeconds(todaySeconds))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Text("TODAY")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(categoryColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Usage Chart Section (matches AppUsageChart style)

    private var usageChartSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.regular) {
            HStack {
                Text("USAGE HISTORY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)

                Spacer()

                Menu {
                    Picker("PERIOD", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                                .textCase(.uppercase)
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.tiny) {
                        Text(selectedTimeRange.rawValue.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.5)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .padding(.horizontal, AppTheme.Spacing.regular)
                    .padding(.vertical, AppTheme.Spacing.tiny)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                    )
                }
            }

            if filteredHistory.isEmpty {
                VStack(spacing: AppTheme.Spacing.regular) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))

                    Text("NO USAGE DATA YET")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                        .textCase(.uppercase)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            } else {
                UsageBarChart(
                    history: filteredHistory,
                    categoryColor: categoryColor,
                    colorScheme: colorScheme
                )
                .frame(height: 180)
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.border(for: colorScheme), lineWidth: 1)
                )
        )
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor)

                Text("SCHEDULE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()
            }

            if let schedule = config.scheduleConfig {
                VStack(spacing: 12) {
                    // Time Window
                    HStack {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor)
                            .frame(width: 24)
                        Text("Allowed Time")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(schedule.todayTimeWindow.isFullDay ? "ALL DAY" : schedule.todayTimeWindow.displayString.uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    }

                    Rectangle()
                        .fill(AppTheme.border(for: colorScheme))
                        .frame(height: 1)

                    // Daily Limit
                    HStack {
                        Image(systemName: "timer")
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor)
                            .frame(width: 24)
                        Text("Daily Limit")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text(schedule.dailyLimits.displaySummary.uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(categoryColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Unlock Requirements Section

    /// Get icon URL for a linked learning app by looking it up in childLearningApps
    private func iconURLForLinkedApp(_ logicalID: String) -> String? {
        childLearningApps.first { $0.logicalID == logicalID }?.iconURL
    }

    private var unlockRequirementsSection: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("UNLOCK REQUIREMENTS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()

                // Unlock mode badge
                Text(config.unlockMode == .all ? "ALL" : "ANY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(config.unlockMode == .all ? Color.orange : AppTheme.vibrantTeal)
                    .cornerRadius(8)
            }

            VStack(spacing: 8) {
                ForEach(config.linkedLearningApps, id: \.logicalID) { linkedApp in
                    HStack(spacing: 12) {
                        // App icon - look up from childLearningApps
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.vibrantTeal.opacity(0.15))
                                .frame(width: 32, height: 32)

                            CachedAppIcon(
                                iconURL: iconURLForLinkedApp(linkedApp.logicalID),
                                identifier: linkedApp.logicalID,
                                size: 32,
                                fallbackSymbol: "book.fill"
                            )
                        }

                        Text(linkedApp.displayName ?? "Learning App")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                            .lineLimit(1)

                        Spacer()

                        Text("\(linkedApp.minutesRequired) MIN")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.vibrantTeal.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Streak Bonus Section (matches AppStreakCard style)

    private func streakBonusSection(_ streak: AppStreakSettings) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("STREAK SETTINGS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .tracking(1)

                Spacer()

                // Bonus badge
                HStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.sunnyYellow)
                    Text(streak.bonusType == .percentage ? "+\(streak.bonusValue)%" : "+\(streak.bonusValue)M")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.sunnyYellow.opacity(0.15))
                .clipShape(Capsule())
            }

            // Streak cycle info
            HStack(alignment: .center, spacing: 16) {
                // Flame icon with ring
                ZStack {
                    Circle()
                        .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.sunnyYellow)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(streak.streakCycleDays)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.sunnyYellow)
                    +
                    Text(" DAY CYCLE")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    Text("Earn bonus after \(streak.streakCycleDays) consecutive days")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()
            }

            // Milestone dots preview
            HStack(spacing: 6) {
                ForEach(0..<min(streak.streakCycleDays, 7), id: \.self) { index in
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.2))
                        .frame(height: 10)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.vibrantTeal, lineWidth: 1)
                                .opacity(0.3)
                        )
                        .frame(maxWidth: .infinity)
                }
                if streak.streakCycleDays > 7 {
                    Text("...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Usage Bar Chart

private struct UsageBarChart: View {
    let history: [DailyUsageHistoryDTO]
    let categoryColor: Color
    let colorScheme: ColorScheme

    var maxSeconds: Int {
        history.map { $0.seconds }.max() ?? 1
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(4, (geometry.size.width - CGFloat(history.count - 1) * 4) / CGFloat(history.count))
            let maxHeight = geometry.size.height - 30 // Space for labels

            VStack(spacing: 0) {
                // Bars
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(history, id: \.id) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(categoryColor)
                                .frame(
                                    width: barWidth,
                                    height: max(4, CGFloat(day.seconds) / CGFloat(maxSeconds) * maxHeight)
                                )
                        }
                    }
                }
                .frame(height: maxHeight)

                // Date labels (show first, middle, last)
                HStack {
                    if let first = history.first {
                        Text(formatShortDate(first.date))
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                    if let last = history.last {
                        Text(formatShortDate(last.date))
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .frame(height: 20)
            }
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

// MARK: - Saving Config Overlay

private struct SavingConfigOverlayView: View {
    let appName: String
    @Environment(\.colorScheme) var colorScheme
    @State private var iconScale: CGFloat = 1.0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Saving card
            VStack(spacing: 20) {
                // Animated gear/upload icon
                ZStack {
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .scaleEffect(iconScale)

                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .scaleEffect(iconScale)
                }
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        iconScale = 1.1
                    }
                }

                VStack(spacing: 8) {
                    Text("Saving Changes...")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("Sending configuration to child's device")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }

                // Animated progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(AppTheme.vibrantTeal)
                            .frame(width: 10, height: 10)
                            .scaleEffect(isAnimating ? 1.0 : 0.5)
                            .opacity(isAnimating ? 1.0 : 0.3)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

struct ParentAppDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Preview would need mock data
            Text("Preview requires mock FullAppConfigDTO")
        }
    }
}
