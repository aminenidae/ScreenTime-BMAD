import SwiftUI

/// Sheet for parent to edit a child's app configuration remotely.
/// This allows modifying schedules, limits, and settings for apps
/// that are already configured on the child's device.
struct ParentAppEditSheet: View {
    @Binding var config: MutableAppConfigDTO?
    let childLearningApps: [FullAppConfigDTO]  // Available learning apps on child
    let onSave: (MutableAppConfigDTO) -> Void
    let onCancel: () -> Void

    @State private var localConfig: MutableAppConfigDTO
    @State private var isFullDayAccess: Bool
    @State private var showingCategoryChangeAlert = false

    @Environment(\.colorScheme) var colorScheme

    init(
        config: Binding<MutableAppConfigDTO?>,
        childLearningApps: [FullAppConfigDTO] = [],
        onSave: @escaping (MutableAppConfigDTO) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._config = config
        self.childLearningApps = childLearningApps
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize local state from the config
        // Note: config.wrappedValue should never be nil in practice
        if let existingConfig = config.wrappedValue {
            _localConfig = State(initialValue: existingConfig)
            _isFullDayAccess = State(initialValue: existingConfig.scheduleConfig?.allowedTimeWindow.isFullDay ?? true)
        } else {
            // Fallback empty config - should never be reached
            _localConfig = State(initialValue: MutableAppConfigDTO.empty)
            _isFullDayAccess = State(initialValue: true)
        }
    }

    private var accentColor: Color {
        localConfig.isLearningApp ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    private var hasChanges: Bool {
        localConfig.hasChanges
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    // App Header (read-only)
                    appHeader

                    // Basic Settings Section
                    basicSettingsSection

                    divider

                    // Time Window Section (only show when tracking is enabled)
                    if localConfig.isEnabled, let scheduleConfig = localConfig.scheduleConfig {
                        TimeWindowPicker(
                            timeWindow: Binding(
                                get: { scheduleConfig.allowedTimeWindow },
                                set: { newValue in
                                    localConfig.scheduleConfig?.allowedTimeWindow = newValue
                                }
                            ),
                            dailyTimeWindows: Binding(
                                get: { scheduleConfig.dailyTimeWindows },
                                set: { newValue in
                                    localConfig.scheduleConfig?.dailyTimeWindows = newValue
                                }
                            ),
                            useAdvancedConfig: Binding(
                                get: { scheduleConfig.useAdvancedTimeWindowConfig },
                                set: { newValue in
                                    localConfig.scheduleConfig?.useAdvancedTimeWindowConfig = newValue
                                }
                            ),
                            isFullDay: $isFullDayAccess
                        )
                        .onChange(of: isFullDayAccess) { newValue in
                            if newValue {
                                localConfig.scheduleConfig?.allowedTimeWindow = .fullDay
                                localConfig.scheduleConfig?.dailyTimeWindows = .allFullDay
                                localConfig.scheduleConfig?.useAdvancedTimeWindowConfig = false
                            }
                        }

                        divider

                        // Daily Limits Section
                        DailyLimitsPicker(
                            dailyLimits: Binding(
                                get: { scheduleConfig.dailyLimits },
                                set: { newValue in
                                    localConfig.scheduleConfig?.dailyLimits = newValue
                                }
                            ),
                            useAdvancedConfig: Binding(
                                get: { scheduleConfig.useAdvancedDayConfig },
                                set: { newValue in
                                    localConfig.scheduleConfig?.useAdvancedDayConfig = newValue
                                }
                            ),
                            maxAllowedMinutes: scheduleConfig.allowedTimeWindow.durationInMinutes,
                            dailyTimeWindows: scheduleConfig.dailyTimeWindows,
                            useAdvancedTimeWindows: scheduleConfig.useAdvancedTimeWindowConfig
                        )
                    }

                    // Reward-specific sections (only show when tracking is enabled)
                    if localConfig.isEnabled && localConfig.isRewardApp {
                        divider
                        linkedAppsSection
                        divider
                        streakSettingsSection
                    }

                    // Note about limitations
                    limitationsNote

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("Edit \(localConfig.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(localConfig)
                    }
                    .disabled(!hasChanges)
                    .foregroundColor(hasChanges ? accentColor : .gray)
                }
            }
        }
        .alert("Change Category?", isPresented: $showingCategoryChangeAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Change") {
                if localConfig.isLearningApp {
                    localConfig.switchToReward()
                } else {
                    localConfig.switchToLearning()
                }
            }
        } message: {
            Text("Changing the category will reset some settings. Are you sure?")
        }
        .onAppear {
            // Sync localConfig from binding after view appears
            // This fixes the timing issue where @State init captures stale/nil values
            if let existingConfig = config {
                localConfig = existingConfig
                isFullDayAccess = existingConfig.scheduleConfig?.allowedTimeWindow.isFullDay ?? true
            }
        }
        .onChange(of: localConfig.isEnabled) { newValue in
            // Create default schedule config when enabling tracking
            if newValue && localConfig.scheduleConfig == nil {
                localConfig.scheduleConfig = localConfig.isRewardApp
                    ? .defaultReward(logicalID: localConfig.logicalID)
                    : .defaultLearning(logicalID: localConfig.logicalID)
            }
        }
    }

    // MARK: - View Components

    private var appHeader: some View {
        VStack(spacing: 12) {
            // App icon placeholder (we don't have the actual icon)
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: localConfig.isLearningApp ? "book.fill" : "gamecontroller.fill")
                    .font(.system(size: 32))
                    .foregroundColor(accentColor)
            }

            Text(localConfig.displayName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            // Category badge
            Text(localConfig.category)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(accentColor)
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    private var basicSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BASIC SETTINGS")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            // Enabled toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Tracking")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Text("Track usage and apply limits")
                        .font(.caption)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                }
                Spacer()
                Toggle("", isOn: $localConfig.isEnabled)
                    .labelsHidden()
                    .tint(accentColor)
            }
            .padding()
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)

            // Points per minute (for learning apps)
            if localConfig.isLearningApp {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Points per Minute")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        Text("Reward points earned for each minute of learning")
                            .font(.caption)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                    Spacer()
                    Stepper(
                        "\(localConfig.pointsPerMinute)",
                        value: $localConfig.pointsPerMinute,
                        in: 1...10
                    )
                    .labelsHidden()
                }
                .padding()
                .background(AppTheme.card(for: colorScheme))
                .cornerRadius(12)
            }

            // Blocking toggle (for reward apps)
            if localConfig.isRewardApp {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Block Until Goals Met")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        Text("Require learning goals before unlocking")
                            .font(.caption)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                    Spacer()
                    Toggle("", isOn: $localConfig.blockingEnabled)
                        .labelsHidden()
                        .tint(accentColor)
                }
                .padding()
                .background(AppTheme.card(for: colorScheme))
                .cornerRadius(12)
            }
        }
    }

    private var linkedAppsSection: some View {
        ParentLinkedAppsPicker(
            linkedApps: $localConfig.linkedLearningApps,
            unlockMode: $localConfig.unlockMode,
            availableLearningApps: childLearningApps.filter { $0.category == "Learning" }
        )
    }

    private var streakSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STREAK BONUS")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            // Enable toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Streak Bonus")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Text("Reward consistency with bonus time")
                        .font(.caption)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { localConfig.streakSettings?.isEnabled ?? false },
                    set: { newValue in
                        if localConfig.streakSettings == nil {
                            localConfig.streakSettings = .defaultSettings
                        }
                        localConfig.streakSettings?.isEnabled = newValue
                    }
                ))
                .labelsHidden()
                .tint(accentColor)
            }
            .padding()
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)

            // Bonus settings (if enabled)
            if localConfig.streakSettings?.isEnabled == true {
                VStack(spacing: 12) {
                    // Bonus value
                    HStack {
                        Text("Bonus Amount")
                            .font(.subheadline)
                        Spacer()
                        Text("\(localConfig.streakSettings?.bonusValue ?? 10)%")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(accentColor)
                            .frame(minWidth: 50)
                        Stepper(
                            "",
                            value: Binding(
                                get: { localConfig.streakSettings?.bonusValue ?? 10 },
                                set: { localConfig.streakSettings?.bonusValue = $0 }
                            ),
                            in: 5...50,
                            step: 5
                        )
                        .labelsHidden()
                    }

                    // Streak cycle
                    HStack {
                        Text("Streak Cycle")
                            .font(.subheadline)
                        Spacer()
                        Text("\(localConfig.streakSettings?.streakCycleDays ?? 7) days")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(accentColor)
                            .frame(minWidth: 60)
                        Stepper(
                            "",
                            value: Binding(
                                get: { localConfig.streakSettings?.streakCycleDays ?? 7 },
                                set: { localConfig.streakSettings?.streakCycleDays = $0 }
                            ),
                            in: 3...14
                        )
                        .labelsHidden()
                    }
                }
                .padding()
                .background(AppTheme.card(for: colorScheme))
                .cornerRadius(12)
            }
        }
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Remote Configuration Note")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text("Changes will apply when the child's device syncs. New apps can only be added from the child's device due to Apple privacy requirements.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
            .frame(height: 1)
    }
}

