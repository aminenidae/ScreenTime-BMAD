import SwiftUI

struct ParentDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // Design colors matching ModeSelectionView
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
    private let accentPeach = Color(red: 1.0, green: 0.70, blue: 0.55)
    private let accentYellow = Color(red: 0.98, green: 0.80, blue: 0.30)

    private var topBarStyle: TabTopBarStyle {
        return TabTopBarStyle(
            background: creamBackground,
            titleColor: tealColor,
            iconColor: tealColor,
            iconBackground: tealColor.opacity(0.1),
            dividerColor: tealColor.opacity(0.15)
        )
    }

    var body: some View {
        ZStack {
            // Background
            creamBackground
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
                                .foregroundColor(tealColor)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(tealColor.opacity(0.1))
                                )
                        }

                        Spacer()

                        Text("DASHBOARD")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(2)
                            .foregroundColor(tealColor)

                        Spacer()

                        // Invisible spacer for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(tealColor.opacity(0.15))
                        .frame(height: 1)
                }
                .background(creamBackground)

                ScrollView {
                    VStack(spacing: 16) {
                        // Today's Activity Summary
                        todayActivityCard

                        // Daily Usage Chart
                        DailyUsageChartCard()

                        // Streak Status
                        if viewModel.currentStreak > 0 {
                            streakCard
                        }

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
                    .foregroundColor(tealColor)

                Text("TODAY'S ACTIVITY")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(tealColor)

                Spacer()
            }

            HStack(spacing: 12) {
                // Learning Time
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 14))
                            .foregroundColor(tealColor)

                        Text("LEARNING")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundColor(tealColor.opacity(0.7))
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(Int(viewModel.learningTime / 60))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(tealColor)

                        Text("min")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(tealColor.opacity(0.6))
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tealColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(tealColor.opacity(0.2), lineWidth: 1)
                        )
                )

                // Reward Time
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                            .foregroundColor(lightCoral)

                        Text("REWARD")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundColor(lightCoral.opacity(0.8))
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(Int(viewModel.rewardTime / 60))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(lightCoral)

                        Text("min")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(lightCoral.opacity(0.7))
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(lightCoral.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(lightCoral.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(tealColor.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: 16) {
            // Flame icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(accentYellow.opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundColor(accentYellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY STREAK")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(tealColor.opacity(0.7))

                HStack(alignment: .bottom, spacing: 8) {
                    Text("\(viewModel.currentStreak)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(tealColor)

                    Text("days")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(tealColor.opacity(0.6))
                        .padding(.bottom, 4)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accentYellow.opacity(0.3), lineWidth: 2)
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
                    .foregroundColor(tealColor)

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
                    color: tealColor
                )

                statTile(
                    icon: "gamecontroller.fill",
                    label: "Reward Apps",
                    value: "\(viewModel.rewardSnapshots.count)",
                    color: lightCoral
                )

                statTile(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Total Apps",
                    value: "\(viewModel.appUsages.count)",
                    color: accentYellow
                )

                statTile(
                    icon: "star.fill",
                    label: "Badges Earned",
                    value: "\(viewModel.badges.filter { $0.isUnlocked }.count)",
                    color: accentPeach
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(tealColor.opacity(0.1), lineWidth: 1)
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
                .foregroundColor(tealColor)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundColor(tealColor.opacity(0.6))
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
