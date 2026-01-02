import SwiftUI

/// A picker for parents to link/unlink learning apps to a reward app remotely.
/// Uses FullAppConfigDTO since parent doesn't have access to ApplicationTokens.
struct ParentLinkedAppsPicker: View {
    @Binding var linkedApps: [LinkedLearningApp]
    @Binding var unlockMode: UnlockMode
    let availableLearningApps: [FullAppConfigDTO]

    @Environment(\.colorScheme) var colorScheme

    // Minutes presets
    private let minutePresets = [5, 10, 15, 20, 30, 45, 60]
    private let rewardMinutePresets = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("UNLOCK REQUIREMENTS")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("Link learning apps that must be used to unlock this reward app")
                    .font(.caption)
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

        return VStack(alignment: .leading, spacing: 8) {
            // Main row with checkbox
            HStack(spacing: 12) {
                // Generic app icon (parent doesn't have access to actual app icons)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: "book.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                // App name
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .lineLimit(1)

                    if isSelected, let linked = linkedApp {
                        Text(linked.displayString)
                            .font(.caption)
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }

                Spacer()

                // Checkbox
                Button(action: {
                    toggleApp(app: app)
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? AppTheme.vibrantTeal : .gray)
                }
                .buttonStyle(.plain)
            }

            // Per-app configuration (only when selected)
            if isSelected, let linked = linkedApp {
                perAppConfig(linkedApp: linked, appLogicalID: app.logicalID)
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

    // MARK: - Per-App Configuration

    private func perAppConfig(linkedApp: LinkedLearningApp, appLogicalID: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Learn time row
            HStack(spacing: 8) {
                Text("Learn:")
                    .font(.caption)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

                // Minutes picker
                Menu {
                    ForEach(minutePresets, id: \.self) { minutes in
                        Button(action: {
                            updateMinutes(for: appLogicalID, minutes: minutes)
                        }) {
                            HStack {
                                Text(formatMinutes(minutes))
                                if linkedApp.minutesRequired == minutes {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formatMinutes(linkedApp.minutesRequired))
                            .font(.caption)
                            .fontWeight(.medium)
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
                            updatePeriod(for: appLogicalID, period: period)
                        }) {
                            HStack {
                                Text(period.displayName)
                                if linkedApp.goalPeriod == period {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(linkedApp.goalPeriod.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
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

            // Reward earned row
            HStack(spacing: 8) {
                Text("Earn:")
                    .font(.caption)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

                // Reward minutes picker
                Menu {
                    ForEach(rewardMinutePresets, id: \.self) { minutes in
                        Button(action: {
                            updateRewardMinutes(for: appLogicalID, minutes: minutes)
                        }) {
                            HStack {
                                Text(formatMinutes(minutes))
                                if linkedApp.rewardMinutesEarned == minutes {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formatMinutes(linkedApp.rewardMinutesEarned))
                            .font(.caption)
                            .fontWeight(.medium)
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

                Text("reward time")
                    .font(.caption)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))

                Spacer()
            }
        }
        .padding(.leading, 48) // Align with app name
    }

    // MARK: - Unlock Mode Section

    private var unlockModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlock Mode")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            // Mode selection
            Picker("Unlock Mode", selection: $unlockMode) {
                Text("Complete ALL apps").tag(UnlockMode.all)
                Text("Complete ANY app").tag(UnlockMode.any)
            }
            .pickerStyle(.segmented)

            Text(unlockMode.description)
                .font(.caption)
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
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
        } else {
            var newLinkedApp = LinkedLearningApp.defaultRequirement(logicalID: app.logicalID)
            newLinkedApp.displayName = app.displayName
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
            availableLearningApps: []
        )
        .padding()
    }
}
#endif
