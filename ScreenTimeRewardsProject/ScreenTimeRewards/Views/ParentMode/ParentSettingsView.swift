//
//  ParentSettingsView.swift
//  ScreenTimeRewards
//
//  Settings view for parent device mode.
//

import SwiftUI

/// Settings view for parent device mode (used in ParentTabView)
struct ParentSettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    // Same `ParentRemoteViewModel` instance the dashboard uses (forwarded from
    // ParentTabView via `.environmentObject(viewModel)`). We re-forward it
    // into the LinkedDevicesView sheet so an unpair from there mutates the
    // shared list, not a private copy. SwiftUI sheets do not inherit env
    // objects automatically.
    @EnvironmentObject var viewModel: ParentRemoteViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var showingSubscriptionManagement = false
    @State private var showingLinkedDevices = false
    @State private var showingWebRestrictions = false
    @State private var showingNotificationSettings = false
    @State private var showingAbout = false
    @State private var showingChangePIN = false
    #if DEBUG
    @State private var showingTrialResetConfirmation = false
    #endif

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Subscription Section
                    subscriptionSection

                    // Device Management Section
                    deviceManagementSection

                    // App Controls Section
                    appControlsSection

                    // Notifications Section
                    notificationsSection

                    // About Section
                    aboutSection

                    #if DEBUG
                    // Testing-only: restore a fresh 14-day trial (clears the Keychain
                    // trial-start that otherwise persists across reinstalls).
                    Button(role: .destructive) {
                        showingTrialResetConfirmation = true
                    } label: {
                        Text("Reset Trial (Testing)")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.playfulCoral.opacity(0.15))
                            .foregroundColor(AppTheme.playfulCoral)
                            .cornerRadius(AppTheme.CornerRadius.medium)
                    }
                    #endif
                }
                .padding()
            }
            .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingSubscriptionManagement) {
            SubscriptionManagementView()
        }
        .sheet(isPresented: $showingLinkedDevices) {
            // Forward the shared ParentRemoteViewModel so unpair/state changes
            // stay consistent with the dashboard. The sheet doesn't inherit
            // env objects automatically.
            LinkedDevicesView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingWebRestrictions) {
            WebsiteBlockingView()
        }
        .sheet(isPresented: $showingNotificationSettings) {
            ParentNotificationSettingsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .fullScreenCover(isPresented: $showingChangePIN) {
            ChangePINView(onSuccess: {
                showingChangePIN = false
            })
        }
        #if DEBUG
        .alert("Reset Trial?", isPresented: $showingTrialResetConfirmation) {
            Button("Reset Trial", role: .destructive) {
                subscriptionManager.resetTrialForTesting()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Testing only: restores a fresh 14-day trial on this device.")
        }
        #endif
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Subscription")

            settingsButton(
                icon: "crown.fill",
                title: String(localized: "Manage Subscription"),
                subtitle: subscriptionStatusText,
                iconColor: .yellow
            ) {
                showingSubscriptionManagement = true
            }
        }
    }

    private var subscriptionStatusText: String {
        switch subscriptionManager.currentStatus {
        case .active:
            return String(localized: "Premium Active")
        case .trial:
            return String(localized: "Trial Period")
        case .grace:
            return String(localized: "Grace Period")
        case .expired:
            return String(localized: "Expired")
        case .cancelled:
            return String(localized: "Cancelled")
        }
    }

    // MARK: - Device Management Section

    private var deviceManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Device Management")

            settingsButton(
                icon: "link",
                title: String(localized: "Linked Devices"),
                subtitle: String(localized: "Manage paired child devices"),
                iconColor: .blue
            ) {
                showingLinkedDevices = true
            }

            settingsButton(
                icon: "lock.fill",
                title: String(localized: "Change PIN"),
                subtitle: String(localized: "Update your parent PIN"),
                iconColor: .purple
            ) {
                showingChangePIN = true
            }
        }
    }

    // MARK: - App Controls Section

    private var appControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("App Controls")

            settingsButton(
                icon: "globe",
                title: String(localized: "Website Blocking"),
                subtitle: String(localized: "Manage blocked websites and browsers"),
                iconColor: .red
            ) {
                showingWebRestrictions = true
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Notifications")

            settingsButton(
                icon: "bell.fill",
                title: String(localized: "Notification Settings"),
                subtitle: String(localized: "Configure alerts and reminders"),
                iconColor: .orange
            ) {
                showingNotificationSettings = true
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("About")

            settingsButton(
                icon: "info.circle.fill",
                title: String(localized: "About"),
                subtitle: String(localized: "Version, privacy, and support"),
                iconColor: .gray
            ) {
                showingAbout = true
            }
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            .textCase(.uppercase)
    }

    private func settingsButton(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))
            }
            .padding(16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Parent Settings View") {
    ParentSettingsView()
        .environmentObject(SubscriptionManager.shared)
}
