import SwiftUI

/// A picker for parents to link/unlink learning apps to a reward app remotely.
/// Uses FullAppConfigDTO since parent doesn't have access to ApplicationTokens.
struct ParentLinkedAppsPicker: View {
    @Binding var linkedApps: [LinkedLearningApp]
    @Binding var unlockMode: UnlockMode
    let availableLearningApps: [FullAppConfigDTO]
    let rewardAppIconURL: String?  // Reward app icon for inline display
    let rewardAppLogicalID: String // Reward app ID for CachedAppIcon

    @Environment(\.colorScheme) var colorScheme

    // Track which apps have their config expanded
    @State private var expandedAppIDs: Set<String> = []

    // Minutes presets for goal (collapsed row)
    private let minutePresets = [5, 10, 15, 20, 30, 45, 60]
    // Ratio presets for expanded row (1-10 minutes)
    private let ratioPresets = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

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
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }

                Text("LINK LEARNING APPS TO UNLOCK THIS REWARD")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }

            // Learning apps list
            if availableLearningApps.isEmpty {
                emptyLearningAppsView
            } else {
                learningAppsList
            }

            // Warning when no apps linked
            if linkedApps.isEmpty && !availableLearningApps.isEmpty {
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
            ForEach(availableLearningApps, id: \.logicalID) { app in
                learningAppRow(app: app)
            }
        }
    }

    private func learningAppRow(app: FullAppConfigDTO) -> some View {
        let isSelected = linkedApps.contains { $0.logicalID == app.logicalID }
        let linkedApp = linkedApps.first { $0.logicalID == app.logicalID }
        let isExpanded = expandedAppIDs.contains(app.logicalID)

        return VStack(alignment: .leading, spacing: 10) {
            // Row 1: App icon + app name + checkbox
            HStack(spacing: 12) {
                // App icon - use CachedAppIcon if URL exists
                if let iconURL = app.iconURL, !iconURL.isEmpty {
                    CachedAppIcon(
                        iconURL: iconURL,
                        identifier: app.logicalID,
                        size: 36,
                        fallbackSymbol: "book.fill"
                    )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.vibrantTeal.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }

                // App name
                Text(app.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .lineLimit(1)

                Spacer()

                // Checkbox (on right)
                Button(action: {
                    toggleApp(app: app)
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? AppTheme.vibrantTeal : .gray)
                }
                .buttonStyle(.plain)
            }

            // Row 2: Plain English requirement sentence with inline pickers (only when selected)
            if isSelected, let linked = linkedApp {
                collapsedConfigRow(app: linked, learningApp: app, isExpanded: isExpanded)
            }

            // Row 3: Expanded ratio explanation (only when selected AND expanded)
            if isSelected, let linked = linkedApp, isExpanded {
                expandedConfigRow(app: linked, learningApp: app)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AppTheme.vibrantTeal.opacity(0.08) : AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? AppTheme.vibrantTeal.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }

    // MARK: - Collapsed Config Row (Plain English requirement sentence)

    private func collapsedConfigRow(app: LinkedLearningApp, learningApp: FullAppConfigDTO, isExpanded: Bool) -> some View {
        HStack(spacing: 0) {
            // Plain English sentence with inline pickers and app icons
            Group {
                Text("Use ")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()

                // Learning app icon (inline)
                inlineLearningAppIcon(app: learningApp)

                Text(" for ")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()

                // Minutes picker (inline)
                inlineMinutesPicker(app: app, logicalID: learningApp.logicalID)

                Text(" per ")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()

                // Period picker (inline)
                inlinePeriodPicker(app: app, logicalID: learningApp.logicalID)

                Text(" to unlock ")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()

                // Reward app icon (inline)
                inlineRewardAppIcon()
            }

            Spacer(minLength: 8)

            // Chevron at end of sentence
            Button(action: {
                toggleExpanded(for: learningApp.logicalID)
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
    }

    // MARK: - Expanded Config Row (Ratio explanation)

    private func expandedConfigRow(app: LinkedLearningApp, learningApp: FullAppConfigDTO) -> some View {
        HStack(spacing: 0) {
            Text("Every ")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

            // Learning time picker (inline)
            inlineLearnTimePicker(app: app, logicalID: learningApp.logicalID)

            Text(" on ")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

            // Learning app icon
            inlineLearningAppIcon(app: learningApp)

            Text(" grants ")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

            // Reward time picker (inline)
            inlineRewardTimePicker(app: app, logicalID: learningApp.logicalID)

            Text(" on ")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

            // Reward app icon
            inlineRewardAppIcon()
        }
        .padding(.leading, 8)
        .padding(.top, 4)
    }

    // MARK: - Inline App Icons

    @ViewBuilder
    private func inlineLearningAppIcon(app: FullAppConfigDTO) -> some View {
        if let iconURL = app.iconURL, !iconURL.isEmpty {
            CachedAppIcon(
                iconURL: iconURL,
                identifier: app.logicalID,
                size: 20,
                fallbackSymbol: "book.fill"
            )
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
        if let iconURL = rewardAppIconURL, !iconURL.isEmpty {
            CachedAppIcon(
                iconURL: iconURL,
                identifier: rewardAppLogicalID,
                size: 20,
                fallbackSymbol: "gift.fill"
            )
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

    private func inlineMinutesPicker(app: LinkedLearningApp, logicalID: String) -> some View {
        Menu {
            ForEach(minutePresets, id: \.self) { minutes in
                Button(action: {
                    updateMinutes(for: logicalID, minutes: minutes)
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

    private func inlinePeriodPicker(app: LinkedLearningApp, logicalID: String) -> some View {
        Menu {
            ForEach(GoalPeriod.allCases, id: \.self) { period in
                Button(action: {
                    updatePeriod(for: logicalID, period: period)
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

    private func inlineLearnTimePicker(app: LinkedLearningApp, logicalID: String) -> some View {
        Menu {
            ForEach(ratioPresets, id: \.self) { minutes in
                Button(action: {
                    updateRatioLearning(for: logicalID, minutes: minutes)
                }) {
                    HStack {
                        Text(formatMinutes(minutes))
                        if app.ratioLearningMinutes == minutes {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(formatMinutes(app.ratioLearningMinutes))
                    .font(.system(size: 12, weight: .semibold))
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

    private func inlineRewardTimePicker(app: LinkedLearningApp, logicalID: String) -> some View {
        Menu {
            ForEach(ratioPresets, id: \.self) { minutes in
                Button(action: {
                    updateRewardMinutes(for: logicalID, minutes: minutes)
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
            HStack(spacing: 2) {
                Text(formatMinutes(app.rewardMinutesEarned))
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(AppTheme.playfulCoral)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.playfulCoral.opacity(0.15))
            )
        }
    }

    // MARK: - Unlock Mode Section

    private var unlockModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UNLOCK MODE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

            HStack(spacing: 8) {
                modeButton(.all)
                modeButton(.any)
            }

            Text(unlockMode.description)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
        }
        .padding(12)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
    }

    private func modeButton(_ mode: UnlockMode) -> some View {
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
                            .stroke(isSelected ? AppTheme.vibrantTeal.opacity(0.5) : AppTheme.border(for: colorScheme), lineWidth: 1)
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

                Text("This reward app will be blocked until at least one learning app is linked.")
                    .font(.caption)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var emptyLearningAppsView: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 2) {
                Text("No learning apps available")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("Learning apps must be configured on the child's device first.")
                    .font(.caption)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    // MARK: - Actions

    private func toggleApp(app: FullAppConfigDTO) {
        if let index = linkedApps.firstIndex(where: { $0.logicalID == app.logicalID }) {
            linkedApps.remove(at: index)
            expandedAppIDs.remove(app.logicalID)
        } else {
            var newLinkedApp = LinkedLearningApp.defaultRequirement(logicalID: app.logicalID)
            newLinkedApp.displayName = app.displayName
            linkedApps.append(newLinkedApp)
        }
    }

    private func toggleExpanded(for logicalID: String) {
        if expandedAppIDs.contains(logicalID) {
            expandedAppIDs.remove(logicalID)
        } else {
            expandedAppIDs.insert(logicalID)
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

    private func updateRatioLearning(for logicalID: String, minutes: Int) {
        if let index = linkedApps.firstIndex(where: { $0.logicalID == logicalID }) {
            linkedApps[index].ratioLearningMinutes = minutes
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
struct ParentLinkedAppsPicker_Previews: PreviewProvider {
    static var previews: some View {
        ParentLinkedAppsPicker(
            linkedApps: .constant([]),
            unlockMode: .constant(.all),
            availableLearningApps: [],
            rewardAppIconURL: nil,
            rewardAppLogicalID: "test"
        )
        .padding()
    }
}
#endif
