import SwiftUI
import ManagedSettings

struct LearningAppsStepView: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel
    @Binding var selectedAppIDs: Set<String>
    @Binding var progressTrackingMode: ProgressTrackingMode
    @Binding var goalValue: Int
    @Binding var goalType: ChallengeGoalType
    @Binding var appConfigs: [String: AppScheduleConfiguration]

    // Sheet state
    @State private var configSheetSnapshot: LearningAppSnapshot?
    @State private var editingConfig: AppScheduleConfiguration?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if learningSnapshots.isEmpty {
                emptyState(
                    message: "Add learning apps from the Learning tab first."
                )
            } else {
                selectionList

                // Show tracking mode selector if multiple apps are selected
                if selectedAppIDs.count >= 2 {
                    trackingModeSelector
                }

                // Show warning if apps need configuration
                if unconfiguredCount > 0 {
                    configWarning
                }
            }

            helperText
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
        )
        .sheet(item: $configSheetSnapshot) { snapshot in
            if let config = editingConfig {
                AppConfigurationSheet(
                    token: snapshot.token,
                    appName: displayName(for: snapshot),
                    appType: .learning,
                    configuration: Binding(
                        get: { config },
                        set: { editingConfig = $0 }
                    ),
                    onSave: { savedConfig in
                        appConfigs[snapshot.logicalID] = savedConfig
                        configSheetSnapshot = nil
                        editingConfig = nil
                    },
                    onCancel: {
                        configSheetSnapshot = nil
                        editingConfig = nil
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "book.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Select Learning Apps")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text("Which apps should count toward this challenge?")
                .font(.system(size: 15))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            if !selectedAppIDs.isEmpty {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.sunnyYellow.opacity(0.2))
                            .frame(width: 22, height: 22)

                        Text("\(selectedAppIDs.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.sunnyYellow)
                    }

                    Text("selected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)

                    // Show configured count
                    if configuredCount > 0 {
                        Text("(\(configuredCount) configured)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var learningSnapshots: [LearningAppSnapshot] {
        appUsageViewModel.learningSnapshots
    }

    private var configuredCount: Int {
        selectedAppIDs.filter { appConfigs[$0] != nil }.count
    }

    private var unconfiguredCount: Int {
        selectedAppIDs.filter { appConfigs[$0] == nil }.count
    }

    private var selectionList: some View {
        VStack(spacing: 12) {
            ForEach(learningSnapshots) { snapshot in
                row(for: snapshot)
            }
        }
    }

    @ViewBuilder
    private func row(for snapshot: LearningAppSnapshot) -> some View {
        let resolvedName = displayName(for: snapshot)
        let subtitle = snapshot.displayName == resolvedName ? nil : snapshot.displayName
        let isSelected = selectedAppIDs.contains(snapshot.logicalID)

        ChallengeBuilderAppSelectionRow(
            token: snapshot.token,
            title: resolvedName,
            subtitle: subtitle,
            isSelected: isSelected,
            onToggle: { toggleSelection(for: snapshot.logicalID) },
            configuration: appConfigs[snapshot.logicalID],
            onConfigure: isSelected ? {
                openConfigSheet(for: snapshot)
            } : nil
        )
    }

    private func displayName(for snapshot: LearningAppSnapshot) -> String {
        appUsageViewModel.resolvedDisplayName(for: snapshot.token) ?? snapshot.displayName
    }

    private func toggleSelection(for logicalID: String) {
        if selectedAppIDs.contains(logicalID) {
            selectedAppIDs.remove(logicalID)
            // Also remove config when deselecting
            appConfigs.removeValue(forKey: logicalID)
        } else {
            selectedAppIDs.insert(logicalID)
        }
    }

    private func openConfigSheet(for snapshot: LearningAppSnapshot) {
        // Get existing config or create default
        let existingConfig = appConfigs[snapshot.logicalID]
            ?? AppScheduleConfiguration.defaultLearning(logicalID: snapshot.logicalID)
        editingConfig = existingConfig
        configSheetSnapshot = snapshot
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

    private var configWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(unconfiguredCount) app\(unconfiguredCount == 1 ? "" : "s") need configuration")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Text("Tap each app to set time limits and allowed hours")
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var trackingModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("Progress Tracking")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            VStack(spacing: 12) {
                trackingModeOption(.combined)
                trackingModeOption(.perApp)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.vibrantTeal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(AppTheme.vibrantTeal.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func trackingModeOption(_ mode: ProgressTrackingMode) -> some View {
        Button(action: { progressTrackingMode = mode }) {
            HStack(spacing: 12) {
                Image(systemName: progressTrackingMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(progressTrackingMode == mode ? AppTheme.vibrantTeal : ChallengeBuilderTheme.mutedText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)

                    Text(mode.description)
                        .font(.system(size: 13))
                        .foregroundColor(ChallengeBuilderTheme.mutedText)

                    // Show example
                    Text(mode.exampleText(appCount: selectedAppIDs.count, targetMinutes: goalValue))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.sunnyYellow)
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(progressTrackingMode == mode ?
                          AppTheme.vibrantTeal.opacity(0.15) :
                          ChallengeBuilderTheme.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                progressTrackingMode == mode ?
                                AppTheme.vibrantTeal :
                                Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var helperText: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.sunnyYellow)

                Text("Tip")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
            }

            Text("Leave empty to count all learning apps. You can always narrow this down later.")
                .font(.system(size: 14))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.sunnyYellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
