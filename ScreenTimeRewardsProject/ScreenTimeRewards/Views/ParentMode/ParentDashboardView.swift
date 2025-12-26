import SwiftUI

struct ParentDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // Design colors matching ModeSelectionView
    
    
    
    
    

    private var topBarStyle: TabTopBarStyle {
        return TabTopBarStyle(
            background: AppTheme.background(for: colorScheme),
            titleColor: AppTheme.textPrimary(for: colorScheme),
            iconColor: AppTheme.vibrantTeal,
            iconBackground: AppTheme.vibrantTeal.opacity(0.1),
            dividerColor: AppTheme.border(for: colorScheme)
        )
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header
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

                ScrollView {
                    VStack(spacing: 16) {
                        // Today's Activity Summary
                        todayActivityCard

                        // Daily Usage Chart
                        DailyUsageChartCard()

                        // Quick Stats
                        quickStatsGrid

                        // Bottom padding
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - Today's Activity Card

    private var todayActivityCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("TODAY'S ACTIVITY")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()
            }

            HStack(spacing: 12) {
                // Learning Time
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))

                        Text("LEARNING")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(Int(viewModel.learningTime / 60))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))

                        Text("min")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.vibrantTeal.opacity(0.2), lineWidth: 1)
                        )
                )

                // Reward Time
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.playfulCoral)

                        Text("REWARD")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundColor(AppTheme.playfulCoral.opacity(0.8))
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(Int(viewModel.rewardTime / 60))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(AppTheme.playfulCoral)

                        Text("min")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.playfulCoral.opacity(0.7))
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.playfulCoral.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.playfulCoral.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
        )
    }



    // MARK: - Quick Stats Grid

    private var quickStatsGrid: some View {
        VStack(spacing: 16) {
            HStack {
                Text("QUICK STATS")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statTile(
                    icon: "books.vertical.fill",
                    label: "Learning Apps",
                    value: "\(viewModel.learningSnapshots.count)",
                    color: AppTheme.vibrantTeal
                )

                statTile(
                    icon: "gamecontroller.fill",
                    label: "Reward Apps",
                    value: "\(viewModel.rewardSnapshots.count)",
                    color: AppTheme.playfulCoral
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func statTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationView {
        ParentDashboardView()
            .environmentObject(AppUsageViewModel())
            .environmentObject(SessionManager.shared)
    }
}
