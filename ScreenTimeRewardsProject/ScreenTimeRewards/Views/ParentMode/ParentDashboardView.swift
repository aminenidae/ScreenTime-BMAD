import SwiftUI

/// Parent dashboard view for local (child device) context.
/// Uses LocalDashboardDataAdapter to provide data to the unified dashboard.
struct ParentDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

    @StateObject private var dataAdapter: LocalDashboardDataAdapter

    init() {
        // Initialize with a temporary adapter - will be replaced on appear
        _dataAdapter = StateObject(wrappedValue: LocalDashboardDataAdapter(
            viewModel: AppUsageViewModel()
        ))
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Content
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

                        // Section 4: Daily/Weekly Trends (existing chart)
                        DailyUsageChartCard()

                        // Bottom padding
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .onAppear {
            // Update the adapter with the actual view model from environment
            updateAdapter()
        }
    }

    private func updateAdapter() {
        // Create new adapter with the actual EnvironmentObject viewModel
        // This is a workaround since we can't directly inject EnvironmentObject into StateObject
        Task { @MainActor in
            dataAdapter.updateViewModel(viewModel)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    sessionManager.exitToSelection()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.vibrantTeal.opacity(0.1))
                        )
                }
                .accessibilityLabel("Go back")

                Spacer()

                Text("DASHBOARD")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Invisible spacer for balance
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Rectangle()
                .fill(AppTheme.border(for: colorScheme))
                .frame(height: 1)
        }
        .background(AppTheme.background(for: colorScheme))
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ParentDashboardView()
            .environmentObject(AppUsageViewModel())
            .environmentObject(SessionManager.shared)
    }
}
