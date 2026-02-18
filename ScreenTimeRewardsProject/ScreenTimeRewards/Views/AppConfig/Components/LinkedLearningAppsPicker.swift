import SwiftUI
import FamilyControls
import ManagedSettings

/// A picker for linking learning apps to a reward app with per-app time requirements
struct LinkedLearningAppsPicker: View {
    @Binding var linkedApps: [LinkedLearningApp]
    @Binding var unlockMode: UnlockMode
    let learningSnapshots: [LearningAppSnapshot]
    let rewardAppToken: ApplicationToken  // Reward app token for icon display in unlock sentence

    @Environment(\.colorScheme) private var colorScheme

    // Minutes presets for goal
    private let minutePresets = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("Unlock Requirements")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }

                Text("Link learning apps to unlock this reward")
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

        return VStack(alignment: .leading, spacing: 10) {
            // Row 1: App icon + app name + checkbox
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                }

                Spacer()

                // Checkbox (on right)
                Button(action: {
                    toggleApp(snapshot: snapshot)
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? AppTheme.lightCream : ChallengeBuilderTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            // Row 2: Plain English requirement sentence with inline pickers (only when selected)
            if isSelected, let app = linkedApp {
                collapsedConfigRow(app: app, snapshot: snapshot)
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

    // MARK: - Collapsed Config Row (Plain English requirement sentence)

    private func collapsedConfigRow(app: LinkedLearningApp, snapshot: LearningAppSnapshot) -> some View {
        HStack(spacing: 0) {
            // Plain English sentence with inline pickers and app icons: "Use [learning icon] for [15m] per [day] to unlock [reward icon]"
            Text("Use ")
                .font(.system(size: 12))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
                .lineLimit(1)
                .fixedSize()

            // Learning app icon (inline)
            inlineLearningAppIcon(snapshot: snapshot)

            Text(" for ")
                .font(.system(size: 12))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
                .lineLimit(1)
                .fixedSize()

            // Minutes picker (inline)
            inlineMinutesPicker(app: app, snapshot: snapshot)

            Text(" per ")
                .font(.system(size: 12))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
                .lineLimit(1)
                .fixedSize()

            // Period picker (inline)
            inlinePeriodPicker(app: app, snapshot: snapshot)

            Text(" to unlock ")
                .font(.system(size: 12))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
                .lineLimit(1)
                .fixedSize()

            // Reward app icon (inline)
            inlineRewardAppIcon()
        }
        .padding(.leading, 8)
    }

    // MARK: - Inline App Icons

    @ViewBuilder
    private func inlineLearningAppIcon(snapshot: LearningAppSnapshot) -> some View {
        if #available(iOS 15.2, *) {
            Label(snapshot.token)
                .labelStyle(.iconOnly)
                .scaleEffect(0.8)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.vibrantTeal.opacity(0.2))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "book.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.vibrantTeal)
                )
        }
    }

    @ViewBuilder
    private func inlineRewardAppIcon() -> some View {
        if #available(iOS 15.2, *) {
            Label(rewardAppToken)
                .labelStyle(.iconOnly)
                .scaleEffect(0.8)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.playfulCoral.opacity(0.2))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "gift.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.playfulCoral)
                )
        }
    }

    // MARK: - Inline Pickers

    private func inlineMinutesPicker(app: LinkedLearningApp, snapshot: LearningAppSnapshot) -> some View {
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
            HStack(spacing: 2) {
                Text(formatMinutes(app.minutesRequired))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(AppTheme.vibrantTeal)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.vibrantTeal.opacity(0.15))
            )
        }
    }

    private func inlinePeriodPicker(app: LinkedLearningApp, snapshot: LearningAppSnapshot) -> some View {
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
            HStack(spacing: 2) {
                Text(app.goalPeriod.shortDisplayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(colorScheme == .dark ? AppTheme.sunnyYellow : AppTheme.brandedText(for: colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.sunnyYellow.opacity(0.15))
            )
        }
    }

    // MARK: - Unlock Mode Section

    private var unlockModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlock Mode")
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
            .foregroundColor(isSelected ? AppTheme.vibrantTeal : AppTheme.brandedText(for: colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.vibrantTeal.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppTheme.vibrantTeal.opacity(0.5) : ChallengeBuilderTheme.border, lineWidth: 1)
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
            // Store display name along with logicalID to enable fallback lookup
            // This fixes the bug where stale logicalIDs prevent earned calculation
            var newLinkedApp = LinkedLearningApp.defaultRequirement(logicalID: snapshot.logicalID)
            newLinkedApp.displayName = snapshot.displayName
            linkedApps.append(newLinkedApp)
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
