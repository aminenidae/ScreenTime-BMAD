import SwiftUI

struct RewardAppsStepView: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel
    @Binding var selectedAppIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if rewardSnapshots.isEmpty {
                emptyState(message: "Assign apps to the Reward category first.")
            } else {
                selectionList
            }

            helperText
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "gift.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("Choose Reward Apps")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text("Which apps will be unlocked as rewards?")
                .font(.system(size: 15))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            if !selectedAppIDs.isEmpty {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.playfulCoral.opacity(0.2))
                            .frame(width: 22, height: 22)

                        Text("\(selectedAppIDs.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.playfulCoral)
                    }

                    Text("selected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }
                .padding(.top, 4)
            }
        }
    }

    private var rewardSnapshots: [RewardAppSnapshot] {
        appUsageViewModel.rewardSnapshots
    }

    private var selectionList: some View {
        VStack(spacing: 12) {
            ForEach(rewardSnapshots) { snapshot in
                row(for: snapshot)
            }
        }
    }

    @ViewBuilder
    private func row(for snapshot: RewardAppSnapshot) -> some View {
        let resolvedName = displayName(for: snapshot)
        let subtitle = snapshot.displayName == resolvedName ? nil : snapshot.displayName

        ChallengeBuilderAppSelectionRow(
            token: snapshot.token,
            title: resolvedName,
            subtitle: subtitle,
            isSelected: selectedAppIDs.contains(snapshot.logicalID),
            onToggle: { toggleSelection(for: snapshot.logicalID) }
        )
    }

    private func displayName(for snapshot: RewardAppSnapshot) -> String {
        appUsageViewModel.resolvedDisplayName(for: snapshot.token) ?? (snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
    }

    private func toggleSelection(for logicalID: String) {
        if selectedAppIDs.contains(logicalID) {
            selectedAppIDs.remove(logicalID)
        } else {
            selectedAppIDs.insert(logicalID)
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Reward Apps Yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ChallengeBuilderTheme.text)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundColor(ChallengeBuilderTheme.border)
        )
    }

    private var helperText: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Optional")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text("Select apps that unlock when the challenge is completed. Leave empty for no rewards.")
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.playfulCoral.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(AppTheme.playfulCoral.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
