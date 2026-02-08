import SwiftUI

/// Notification settings view specifically for parent device
/// Allows parents to configure which alerts they receive about their children's activity
struct ParentNotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = NotificationSettingsManager.shared

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Learning Goal Completed", isOn: $settings.learningGoalNotificationsEnabled)
                    Toggle("Daily Limit Reached", isOn: $settings.dailyLimitNotificationsEnabled)
                    Toggle("Streak Milestones", isOn: $settings.streakNotificationsEnabled)
                } header: {
                    Text("Child Achievement Alerts")
                } footer: {
                    Text("Receive notifications when your child reaches milestones")
                }

                Section {
                    Toggle("Reward Time Expired", isOn: $settings.rewardTimeNotificationsEnabled)
                    Toggle("Downtime Started", isOn: $settings.downtimeNotificationsEnabled)
                } header: {
                    Text("Time Alerts")
                } footer: {
                    Text("Get notified about time-based events")
                }

                Section {
                    Toggle("Sound", isOn: $settings.soundEnabled)
                    Toggle("Badge", isOn: $settings.badgeEnabled)
                } header: {
                    Text("Notification Style")
                }

                Section {
                    NavigationLink(destination: notificationScheduleView) {
                        HStack {
                            Text("Quiet Hours")
                            Spacer()
                            Text("Off")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Schedule")
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

    private var notificationScheduleView: some View {
        List {
            Section {
                Text("Quiet hours settings coming soon")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Configure times when you don't want to receive notifications")
            }
        }
        .navigationTitle("Quiet Hours")
    }
}
