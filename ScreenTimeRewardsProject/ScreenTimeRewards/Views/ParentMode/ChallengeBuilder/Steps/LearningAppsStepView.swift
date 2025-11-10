import SwiftUI

struct LearningAppsStepView: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel
    @Binding var selectedAppIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if learningSnapshots.isEmpty {
                emptyState(
                    message: "Add learning apps from the Learning tab first."
                )
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
            Text("Select Learning Apps")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(ChallengeBuilderTheme.text)
            Text("Which apps should count toward this challenge?")
                .font(.system(size: 15))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            if !selectedAppIDs.isEmpty {
                Text("\(selectedAppIDs.count) selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.primary)
            }
        }
    }

    private var learningSnapshots: [LearningAppSnapshot] {
        appUsageViewModel.learningSnapshots
    }

    private var selectionList: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(learningSnapshots) { snapshot in
                row(for: snapshot)
            }
        }
    }

    @ViewBuilder
    private func row(for snapshot: LearningAppSnapshot) -> some View {
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

    private func displayName(for snapshot: LearningAppSnapshot) -> String {
        appUsageViewModel.resolvedDisplayName(for: snapshot.token) ?? snapshot.displayName
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
            Text("No Learning Apps Yet")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Tip")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ChallengeBuilderTheme.primary)
            Text("Leave empty to count all learning apps. You can always narrow this down later.")
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(ChallengeBuilderTheme.inputBackground.opacity(0.7))
        )
    }
}
