import SwiftUI
import FamilyControls
import ManagedSettings

/// Section displaying reward apps with usage times and unlock status
struct RewardAppListSection: View {
    let snapshots: [RewardAppSnapshot]
    let remainingMinutes: Int
    let unlockedApps: [ApplicationToken: UnlockedRewardApp]

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = true

    private var totalUsedSeconds: TimeInterval {
        snapshots.reduce(0) { $0 + $1.totalSeconds }
    }

    private var totalUsedMinutes: Int {
        Int(totalUsedSeconds / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            sectionHeader

            // App list
            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        rewardAppRow(snapshot: snapshot)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: isExpanded)
                    }
                }
            }

            // Empty state
            if snapshots.isEmpty {
                emptyState
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 3)
        )
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(AppTheme.playfulCoral.opacity(colorScheme == .dark ? 0.3 : 0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.playfulCoral)
                }

                // Title
                Text("Reward Apps")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Remaining time badge
                HStack(spacing: 4) {
                    Image(systemName: remainingMinutes > 0 ? "clock.fill" : "clock")
                        .font(.system(size: 12))
                    Text("\(remainingMinutes) min left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(remainingMinutes > 0 ? AppTheme.playfulCoral : AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppTheme.playfulCoral.opacity(colorScheme == .dark ? 0.25 : 0.12))
                )

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
    }

    private func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        let isUnlocked = unlockedApps[snapshot.token] != nil
        let usedMinutes = Int(snapshot.totalSeconds / 60)

        return HStack(spacing: 12) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.35)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.playfulCoral.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.playfulCoral)
                    )
            }

            // App name and status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    } else {
                        Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    }
                }

                // Status text
                if isUnlocked {
                    Text("\(usedMinutes) min used")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else if remainingMinutes <= 0 {
                    Text("No time remaining")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                } else {
                    Text("Ready to use")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }

            Spacer()

            // Lock/unlock indicator
            if isUnlocked || remainingMinutes > 0 {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppTheme.playfulCoral.opacity(colorScheme == .dark ? 0.15 : 0.08))
        )
        .opacity(remainingMinutes > 0 || isUnlocked ? 1.0 : 0.6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("No reward apps configured")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("Ask a parent to set up reward apps for you!")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // With remaining time
            RewardAppListSection(
                snapshots: [],
                remainingMinutes: 25,
                unlockedApps: [:]
            )

            // No remaining time
            RewardAppListSection(
                snapshots: [],
                remainingMinutes: 0,
                unlockedApps: [:]
            )

            // Empty state
            RewardAppListSection(
                snapshots: [],
                remainingMinutes: 0,
                unlockedApps: [:]
            )
        }
        .padding()
    }
    .background(AppTheme.background(for: .light))
}
