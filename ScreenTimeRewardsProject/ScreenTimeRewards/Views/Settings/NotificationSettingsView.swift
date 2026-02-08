import SwiftUI

/// View for managing notification settings
struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = NotificationSettingsManager.shared

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Daily Limit Alerts", isOn: $settings.dailyLimitNotificationsEnabled)
                    Toggle("Learning Goal Completed", isOn: $settings.learningGoalNotificationsEnabled)
                    Toggle("Streak Milestones", isOn: $settings.streakNotificationsEnabled)
                } header: {
                    Text("Achievement Notifications")
                }

                Section {
                    Toggle("Reward Time Warnings", isOn: $settings.rewardTimeNotificationsEnabled)
                    Toggle("Downtime Reminders", isOn: $settings.downtimeNotificationsEnabled)
                } header: {
                    Text("Time Notifications")
                }

                if DeviceModeManager.shared.isParentDevice {
                    Section {
                        Toggle("Child Activity Alerts", isOn: $settings.parentAlertsEnabled)
                    } header: {
                        Text("Parent Notifications")
                    } footer: {
                        Text("Receive notifications when your child completes goals or reaches limits")
                    }
                }

                Section {
                    Toggle("Sound", isOn: $settings.soundEnabled)
                    Toggle("Badge", isOn: $settings.badgeEnabled)
                } header: {
                    Text("Notification Style")
                }

                Section {
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
