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

    // Design colors
    
    
    

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
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.playfulCoral.opacity(0.1), lineWidth: 1)
                )
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
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.playfulCoral)

                // Title
                Text("REWARD APPS")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.vibrantTeal)

                Spacer()

                // Remaining time badge
                HStack(spacing: 4) {
                    Image(systemName: remainingMinutes > 0 ? "clock.fill" : "clock")
                        .font(.system(size: 11))
                    Text("\(remainingMinutes) MIN LEFT")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(remainingMinutes > 0 ? AppTheme.playfulCoral : AppTheme.vibrantTeal.opacity(0.6))

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.6))
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .lineLimit(1)
                    } else {
                        Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .lineLimit(1)
                    }
                }

                // Status text
                if isUnlocked {
                    Text("\(usedMinutes) MIN USED")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.vibrantTeal.opacity(0.6))
                } else if remainingMinutes <= 0 {
                    Text("NO TIME REMAINING")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.vibrantTeal.opacity(0.6))
                } else {
                    Text("READY TO USE")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.playfulCoral)
                }
            }

            Spacer()

            // Lock/unlock indicator
            if isUnlocked || remainingMinutes > 0 {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.playfulCoral)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.4))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.playfulCoral.opacity(0.05))
        )
        .opacity(remainingMinutes > 0 || isUnlocked ? 1.0 : 0.6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.vibrantTeal.opacity(0.4))

            Text("No reward apps configured")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.vibrantTeal.opacity(0.6))

            Text("Ask a parent to set up reward apps for you!")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.vibrantTeal.opacity(0.5))
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
