import SwiftUI
import FamilyControls
import ManagedSettings

struct RewardsTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Use shared view model
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var selectedRewardSnapshot: RewardAppSnapshot?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TabTopBar(title: "Reward Apps", style: topBarStyle) {
                    sessionManager.exitToSelection()
                }

                ScrollView {
                    VStack(spacing: 0) {
                        // Points Summary Card
                        HStack(spacing: 16) {
                            // Icon with gradient background
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.playfulCoral.opacity(0.3), AppTheme.sunnyYellow.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)

                                Image(systemName: "gift.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppTheme.playfulCoral)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Points Available")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                                HStack(alignment: .bottom, spacing: 8) {
                                    Text("\(viewModel.availableLearningPoints)")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(AppTheme.vibrantTeal)
                                        .tracking(-0.5)

                                    Text("points")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                        .padding(.bottom, 4)
                                }

                                if viewModel.reservedLearningPoints > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.sunnyYellow)

                                        Text("\(viewModel.reservedLearningPoints) reserved")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppTheme.sunnyYellow)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.card(for: colorScheme))
                                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 4)

                        // Section Header
                        HStack(spacing: 8) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.playfulCoral)

                            Text("Your Rewards")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                        // List of Reward Apps
                        rewardAppsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
                .background(AppTheme.background(for: colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            addAppsButton
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $selectedRewardSnapshot) { snapshot in
            RewardAppDetailView(snapshot: snapshot)
        }
        // NOTE: Picker and sheet presentation handled by MainTabView to avoid conflicts
    }
}

private extension RewardsTabView {
    var topBarStyle: TabTopBarStyle {
        TabTopBarStyle(
            background: AppTheme.background(for: colorScheme),
            titleColor: AppTheme.textPrimary(for: colorScheme),
            iconColor: AppTheme.playfulCoral,
            iconBackground: AppTheme.card(for: colorScheme),
            dividerColor: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06)
        )
    }

    var addAppsButton: some View {
        VStack(spacing: 0) {
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
                viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                viewModel.presentPickerWithRetry(for: .reward)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Manage Reward Apps")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppTheme.playfulCoral)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
        }
    }

    var rewardAppsSection: some View {
        Group {
            if !viewModel.rewardSnapshots.isEmpty {
                // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
                let columns = horizontalSizeClass == .regular ? [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ] : [
                    GridItem(.flexible())
                ]

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(viewModel.rewardSnapshots) { snapshot in
                        rewardAppRow(snapshot: snapshot)
                    }
                }
            } else {
                Text("No reward apps selected")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    @ViewBuilder
    func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24

        Button {
            selectedRewardSnapshot = snapshot
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(iconScale)
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: fallbackIconSize))
                                    .foregroundColor(.gray)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if #available(iOS 15.2, *) {
                            Label(snapshot.token)
                                .labelStyle(.titleOnly)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        } else {
                            Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.playfulCoral)

                            Text("+\(snapshot.pointsPerMinute) pts/min")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.playfulCoral)
                                .lineLimit(1)
                        }

                        Text(formatTime(snapshot.totalSeconds))
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(16)
            }
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remaining = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remaining)m"
        } else {
            return "\(minutes)m"
        }
    }

}


struct RewardsTabView_Previews: PreviewProvider {
    static var previews: some View {
        RewardsTabView()
            .environmentObject(AppUsageViewModel())  // Provide a view model for previews
            .environmentObject(SessionManager.shared)
    }
}
