import SwiftUI

struct ParentDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var topBarStyle: TabTopBarStyle {
        let dividerOpacity = colorScheme == .dark ? 0.15 : 0.06
        return TabTopBarStyle(
            background: AppTheme.background(for: colorScheme),
            titleColor: AppTheme.textPrimary(for: colorScheme),
            iconColor: AppTheme.vibrantTeal,
            iconBackground: AppTheme.card(for: colorScheme),
            dividerColor: Color.black.opacity(dividerOpacity)
        )
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabTopBar(title: "Dashboard", style: topBarStyle) {
                    sessionManager.exitToSelection()
                }

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.regular) {
                        // Today's Activity Summary
                        todayActivityCard

                        // Daily Usage Chart
                        DailyUsageChartCard()

                        // Points Overview - HIDDEN (keeping code for future use)
                        // pointsOverviewCard

                        // Streak Status
                        if viewModel.currentStreak > 0 {
                            streakCard
                        }

                        // Quick Stats
                        quickStatsGrid

                        // Bottom padding
                        Color.clear.frame(height: AppTheme.Spacing.large)
                    }
                    .padding(.horizontal, AppTheme.Spacing.regular)
                    .padding(.top, AppTheme.Spacing.tiny)
                }
            }
        }
    }

    // MARK: - Today's Activity Card

    private var todayActivityCard: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Today's Activity")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            HStack(spacing: AppTheme.Spacing.regular) {
                // Learning Time
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.learningPeach)

                        Text("Learning")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(Int(viewModel.learningTime / 60))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(AppTheme.learningPeach)

                        Text("min")
                            .font(AppTheme.Typography.callout)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.regular)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.learningPeach.opacity(colorScheme == .dark ? 0.2 : 0.1))
                )

                // Reward Time
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.playfulCoral)

                        Text("Reward")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(Int(viewModel.rewardTime / 60))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(AppTheme.playfulCoral)

                        Text("min")
                            .font(AppTheme.Typography.callout)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.regular)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.playfulCoral.opacity(colorScheme == .dark ? 0.2 : 0.1))
                )
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    // MARK: - Points Overview Card

    private var pointsOverviewCard: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Points Overview")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            // Points Grid
            VStack(spacing: AppTheme.Spacing.medium) {
                // Row 1: Earned & Available
                HStack(spacing: AppTheme.Spacing.medium) {
                    pointStatBox(
                        icon: "plus.circle.fill",
                        label: "Earned",
                        value: "\(viewModel.learningRewardPoints)",
                        color: AppTheme.learningPeach
                    )

                    pointStatBox(
                        icon: "checkmark.circle.fill",
                        label: "Available",
                        value: "\(viewModel.availableLearningPoints)",
                        color: AppTheme.sunnyYellow
                    )
                }

                // Row 2: Bonus & Consumed
                HStack(spacing: AppTheme.Spacing.medium) {
                    pointStatBox(
                        icon: "star.fill",
                        label: "Bonus",
                        value: "\(viewModel.bonusLearningPoints)",
                        color: Color.orange
                    )

                    pointStatBox(
                        icon: "arrow.right.circle.fill",
                        label: "Consumed",
                        value: "\(viewModel.totalConsumedPoints)",
                        color: AppTheme.playfulCoral
                    )
                }
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    private func pointStatBox(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)

                Text(label)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.08))
        )
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: AppTheme.Spacing.regular) {
            // Flame icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.sunnyYellow.opacity(0.3), AppTheme.playfulCoral.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("Daily Streak")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                HStack(alignment: .bottom, spacing: 8) {
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("days")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.bottom, 4)
                }

                Text("Keep it up! 🎉")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.sunnyYellow.opacity(0.3), AppTheme.playfulCoral.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        )
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    // MARK: - Quick Stats Grid

    private var quickStatsGrid: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Quick Stats")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppTheme.Spacing.medium) {
                statTile(
                    icon: "books.vertical.fill",
                    label: "Learning Apps",
                    value: "\(viewModel.learningSnapshots.count)",
                    color: AppTheme.learningPeach
                )

                statTile(
                    icon: "gamecontroller.fill",
                    label: "Reward Apps",
                    value: "\(viewModel.rewardSnapshots.count)",
                    color: AppTheme.playfulCoral
                )

                statTile(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Total Apps",
                    value: "\(viewModel.appUsages.count)",
                    color: AppTheme.sunnyYellow
                )

                statTile(
                    icon: "star.fill",
                    label: "Badges Earned",
                    value: "\(viewModel.badges.filter { $0.isUnlocked }.count)",
                    color: Color.orange
                )
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    private func statTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.08))
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
