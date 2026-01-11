import SwiftUI
import FamilyControls
import ManagedSettings

/// A picker for linking learning apps to a reward app with per-app time requirements
struct LinkedLearningAppsPicker: View {
    @Binding var linkedApps: [LinkedLearningApp]
    @Binding var unlockMode: UnlockMode
    let learningSnapshots: [LearningAppSnapshot]

    // Minutes presets
    private let minutePresets = [5, 10, 15, 20, 30, 45, 60]
    private let rewardMinutePresets = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("UNLOCK REQUIREMENTS")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }

                Text("LINK LEARNING APPS TO UNLOCK THIS REWARD")
                    .font(.system(size: 11))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }

            // Learning apps list
            if learningSnapshots.isEmpty {
                emptyLearningAppsView
            } else {
                learningAppsList
            }

            // Warning when no apps linked
            if linkedApps.isEmpty && !learningSnapshots.isEmpty {
                blockedWarning
            }

            // Unlock mode section (only show when multiple apps linked)
            if linkedApps.count > 1 {
                unlockModeSection
            }
        }
    }

    // MARK: - Learning Apps List

    private var learningAppsList: some View {
        VStack(spacing: 8) {
            ForEach(learningSnapshots) { snapshot in
                learningAppRow(snapshot: snapshot)
            }
        }
    }

    private func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        let isSelected = linkedApps.contains { $0.logicalID == snapshot.logicalID }
        let linkedApp = linkedApps.first { $0.logicalID == snapshot.logicalID }

        return VStack(alignment: .leading, spacing: 8) {
            // Main row with checkbox
            HStack(spacing: 12) {
                // App icon
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.3)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        )
                }

                // App name
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "LEARNING APP" : snapshot.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                }

                Spacer()

                // Checkbox
                Button(action: {
                    toggleApp(snapshot: snapshot)
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? AppTheme.lightCream : ChallengeBuilderTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            // Per-app configuration (only when selected)
            if isSelected, let app = linkedApp {
                perAppConfig(app: app, snapshot: snapshot)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? AppTheme.vibrantTeal.opacity(0.08) : ChallengeBuilderTheme.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? AppTheme.vibrantTeal.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }

    // MARK: - Per-App Configuration

    private func perAppConfig(app: LinkedLearningApp, snapshot: LearningAppSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // First row: Learn time + Period
            HStack(spacing: 8) {
                Text("LEARN:")
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)

                // Minutes picker
                Menu {
                    ForEach(minutePresets, id: \.self) { minutes in
                        Button(action: {
                            updateMinutes(for: snapshot.logicalID, minutes: minutes)
                        }) {
                            HStack {
                                Text(formatMinutes(minutes))
                                if app.minutesRequired == minutes {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formatMinutes(app.minutesRequired))
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppTheme.vibrantTeal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.vibrantTeal.opacity(0.15))
                    )
                }

                // Period picker (daily/weekly)
                Menu {
                    ForEach(GoalPeriod.allCases, id: \.self) { period in
                        Button(action: {
                            updatePeriod(for: snapshot.logicalID, period: period)
                        }) {
                            HStack {
                                Text(period.displayName)
                                if app.goalPeriod == period {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(app.goalPeriod.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppTheme.sunnyYellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.sunnyYellow.opacity(0.15))
                    )
                }

                Spacer()
            }

            // Second row: Reward earned
            HStack(spacing: 8) {
                Text("EARN:")
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)

                // Reward minutes picker
                Menu {
                    ForEach(rewardMinutePresets, id: \.self) { minutes in
                        Button(action: {
                            updateRewardMinutes(for: snapshot.logicalID, minutes: minutes)
                        }) {
                            HStack {
                                Text(formatMinutes(minutes))
                                if app.rewardMinutesEarned == minutes {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formatMinutes(app.rewardMinutesEarned))
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppTheme.playfulCoral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.playfulCoral.opacity(0.15))
                    )
                }

                Text("REWARD")
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)

                Spacer()
            }
        }
        .padding(.leading, 44) // Align with app name
    }

    // MARK: - Unlock Mode Section

    private var unlockModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UNLOCK MODE")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ChallengeBuilderTheme.text)

            // Mode selection
            HStack(spacing: 8) {
                modeButton(mode: .all)
                modeButton(mode: .any)
            }

            Text(unlockMode.description)
                .font(.system(size: 11))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    private func modeButton(mode: UnlockMode) -> some View {
        let isSelected = unlockMode == mode

        return Button(action: { unlockMode = mode }) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))

                Text(mode.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? AppTheme.lightCream : ChallengeBuilderTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.vibrantTeal.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppTheme.lightCream.opacity(0.3) : ChallengeBuilderTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Warning Views

    private var blockedWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("No learning apps linked")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)

                Text("This reward app will be blocked until you link at least one learning app.")
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var emptyLearningAppsView: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(ChallengeBuilderTheme.mutedText)

            Text("No learning apps available. Add learning apps first to set unlock requirements.")
                .font(.system(size: 13))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChallengeBuilderTheme.inputBackground)
        )
    }

    // MARK: - Actions

    private func toggleApp(snapshot: LearningAppSnapshot) {
        if let index = linkedApps.firstIndex(where: { $0.logicalID == snapshot.logicalID }) {
            linkedApps.remove(at: index)
        } else {
            linkedApps.append(.defaultRequirement(logicalID: snapshot.logicalID))
        }
    }

    private func updateMinutes(for logicalID: String, minutes: Int) {
        if let index = linkedApps.firstIndex(where: { $0.logicalID == logicalID }) {
            linkedApps[index].minutesRequired = minutes
        }
    }

    private func updatePeriod(for logicalID: String, period: GoalPeriod) {
        if let index = linkedApps.firstIndex(where: { $0.logicalID == logicalID }) {
            linkedApps[index].goalPeriod = period
        }
    }

    private func updateRewardMinutes(for logicalID: String, minutes: Int) {
        if let index = linkedApps.firstIndex(where: { $0.logicalID == logicalID }) {
            linkedApps[index].rewardMinutesEarned = minutes
        }
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins > 0 {
                return "\(hours)h \(mins)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - Preview

#if DEBUG
struct LinkedLearningAppsPicker_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available - requires LearningAppSnapshots")
    }
}
#endif
