import SwiftUI
import FamilyControls
import ManagedSettings

/// Sheet for configuring per-app schedule and time limits
struct AppConfigurationSheet: View {
    let token: ApplicationToken
    let appName: String
    let appType: AppType
    let learningSnapshots: [LearningAppSnapshot]  // For reward apps: available learning apps to link

    @Binding var configuration: AppScheduleConfiguration
    let onSave: (AppScheduleConfiguration) -> Void
    let onCancel: () -> Void

    @State private var localConfig: AppScheduleConfiguration
    @State private var isFullDayAccess: Bool

    init(
        token: ApplicationToken,
        appName: String,
        appType: AppType,
        learningSnapshots: [LearningAppSnapshot] = [],  // Default to empty for learning apps
        configuration: Binding<AppScheduleConfiguration>,
        onSave: @escaping (AppScheduleConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.token = token
        self.appName = appName
        self.appType = appType
        self.learningSnapshots = learningSnapshots
        self._configuration = configuration
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize local state
        _localConfig = State(initialValue: configuration.wrappedValue)
        _isFullDayAccess = State(initialValue: configuration.wrappedValue.allowedTimeWindow.isFullDay)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App header
                    appHeader

                    Divider()
                        .background(ChallengeBuilderTheme.border)

                    // Time Window Section
                    TimeWindowPicker(
                        timeWindow: $localConfig.allowedTimeWindow,
                        isFullDay: $isFullDayAccess
                    )
                    .onChange(of: isFullDayAccess) { newValue in
                        if newValue {
                            localConfig.allowedTimeWindow = .fullDay
                        }
                    }

                    Divider()
                        .background(ChallengeBuilderTheme.border)

                    // Daily Limits Section
                    DailyLimitsPicker(
                        dailyLimits: $localConfig.dailyLimits,
                        useAdvancedConfig: $localConfig.useAdvancedDayConfig
                    )

                    // Unlock Requirements Section (reward apps only)
                    if appType == .reward {
                        Divider()
                            .background(ChallengeBuilderTheme.border)

                        LinkedLearningAppsPicker(
                            linkedApps: $localConfig.linkedLearningApps,
                            unlockMode: $localConfig.unlockMode,
                            learningSnapshots: learningSnapshots
                        )
                    }

                    Divider()
                        .background(ChallengeBuilderTheme.border)

                    // Enable/Disable toggle
                    enableToggle

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(ChallengeBuilderTheme.background.ignoresSafeArea())
            .navigationTitle("Configure App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(AppTheme.playfulCoral)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(localConfig)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: 16) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.5)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ChallengeBuilderTheme.surface)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(ChallengeBuilderTheme.surface)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                // App name
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                } else {
                    Text(appName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                        .lineLimit(1)
                }

                // Category badge
                HStack(spacing: 6) {
                    Image(systemName: appType == .learning ? "book.fill" : "gift.fill")
                        .font(.system(size: 11))

                    Text(appType == .learning ? "Learning" : "Reward")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(appType == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((appType == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral).opacity(0.15))
                )
            }

            Spacer()
        }
    }

    // MARK: - Enable Toggle

    private var enableToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Limits")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ChallengeBuilderTheme.text)

                Text(localConfig.isEnabled ? "Limits are active" : "Limits are disabled")
                    .font(.system(size: 13))
                    .foregroundColor(ChallengeBuilderTheme.mutedText)
            }

            Spacer()

            Toggle("", isOn: $localConfig.isEnabled)
                .labelsHidden()
                .tint(AppTheme.vibrantTeal)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(localConfig.isEnabled ? AppTheme.vibrantTeal.opacity(0.1) : ChallengeBuilderTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(localConfig.isEnabled ? AppTheme.vibrantTeal.opacity(0.3) : ChallengeBuilderTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct AppConfigurationSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available - requires ApplicationToken")
    }
}
#endif
