import SwiftUI
import UIKit
import FamilyControls
import CoreData

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @State private var showingPairingView = false
    @State private var showingSubscriptionManagement = false
    @State private var showingPairingConfig = false
    @State private var showingWebsiteBlockingView = false

    @State private var showResetConfirmation = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared
    private let screenTimeService = ScreenTimeService.shared
    @State private var areBrowsersBlocked = false
    @Environment(\.colorScheme) var colorScheme

    // New settings state
    @State private var showingEditChildName = false
    @State private var showingChangePIN = false
    @State private var showingNotificationSettings = false
    @State private var showingAbout = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            sessionManager.exitToSelection()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                                )
                        }
                        .accessibilityLabel("Go back")

                        Spacer()

                        Text("SETTINGS")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(2)
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))

                        Spacer()

                        // Invisible spacer for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(AppTheme.brandedText(for: colorScheme).opacity(0.15))
                        .frame(height: 1)
                }
                .background(AppTheme.background(for: colorScheme))

                ScrollView {
                    VStack(spacing: 24) {


                        // Account Section
                        settingsSection(title: "ACCOUNT") {
                            exitParentModeRow
                        }

                        // Subscription Section
                        settingsSection(title: "SUBSCRIPTION") {
                            subscriptionRow
                        }

                        // Web Restrictions Section
                        settingsSection(title: "WEB RESTRICTIONS") {
                            blockedWebsitesRow
                            blockBrowsersRow
                            adultContentStatusRow
                        }

                        // Devices Section
                        settingsSection(title: "DEVICES") {
                            pairingStatusRow

                            if pairingService.isPaired() {
                                pairingConfigRow
                            }
                        }

                        // Child Section - for editing this device's name
                        settingsSection(title: "CHILD") {
                            editChildNameRow
                        }

                        // Security Section
                        settingsSection(title: "SECURITY") {
                            changePINRow
                        }

                        // General Section
                        settingsSection(title: "GENERAL") {
                            notificationSettingsRow
                            helpSupportRow
                            aboutRow
                        }

                        // Danger Zone Section
                        VStack(alignment: .leading, spacing: 8) {
                            settingsSection(title: "DANGER ZONE") {
                                resetDeviceRow
                            }

                            Text("This will erase all app settings and data on this device.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                                .padding(.horizontal, 4)
                        }

                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Hidden report view to ensure extension is triggered from this screen
            HiddenUsageReportView()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }

        .sheet(isPresented: $showingSubscriptionManagement) {
            SubscriptionManagementView()
        }

        .sheet(isPresented: $showingPairingConfig) {
            PairingConfigView()
        }

        .sheet(isPresented: $showingWebsiteBlockingView) {
            WebsiteBlockingView()
        }

        .sheet(isPresented: $showingEditChildName) {
            EditChildNameSheet(
                currentName: modeManager.deviceName,
                onSave: { newName in
                    updateDeviceName(newName)
                }
            )
        }

        .fullScreenCover(isPresented: $showingChangePIN) {
            ChangePINView(onSuccess: {
                showingChangePIN = false
            })
        }

        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }

        .sheet(isPresented: $showingAbout) {
            AboutView()
        }

        .onAppear {
            // Sync browser blocking state
            areBrowsersBlocked = screenTimeService.areBrowsersBlocked
        }
    }
}

// MARK: - Helper Functions

private extension SettingsTabView {
    func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                .padding(.horizontal, 4)

            content()
        }
    }

    func updateDeviceName(_ newName: String) {
        modeManager.setDeviceName(newName)

        #if DEBUG
        print("[SettingsTabView] Device name updated to: \(newName)")
        #endif
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Row Views

private extension SettingsTabView {


    var exitParentModeRow: some View {
        Button(action: {
            sessionManager.exitToSelection()
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.playfulCoral.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.playfulCoral)
                }

                // Label
                Text("Exit Parent Mode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var pairingStatusRow: some View {
        Button(action: {
            showingPairingView = true
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.brandedText(for: colorScheme).opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "ipad.and.iphone")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }

                // Status content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing Status")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    if pairingService.isPaired() {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))

                            Text("Paired with Child's iPad")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                        }
                    } else {
                        Text("Not paired")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var resetDeviceRow: some View {
        Button(action: {
            showResetConfirmation = true
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.errorRed.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.errorRed)
                }

                // Label
                Text("Reset This Device")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.errorRed)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.errorRed.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Reset Device Mode?",
                          isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                modeManager.resetDeviceMode()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset your device mode selection. App configurations will be preserved.")
        }
    }

    var subscriptionRow: some View {
        Button(action: {
            showingSubscriptionManagement = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.sunnyYellow.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.sunnyYellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Subscription")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(subscriptionManager.currentTierName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)

                    if subscriptionManager.isInTrial, let days = subscriptionManager.trialDaysRemaining {
                        Text("\(days) days left in trial")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                    } else if subscriptionManager.isInGracePeriod {
                        Text("Grace Period")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.playfulCoral)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.sunnyYellow.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var pairingConfigRow: some View {
        Button(action: {
            showingPairingConfig = true
        }) {
            HStack(spacing: 16) {
                // Icon container with badge overlay
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.vibrantTeal.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }

                    // Add badge if unnamed apps exist
                    if viewModel.hasUnnamedApps {
                        NotificationBadge()
                            .offset(x: 4, y: -4)
                    }
                }

                // Label
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing Configuration")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Name apps for monitoring")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Web Restrictions Rows

    var blockedWebsitesRow: some View {
        Button(action: {
            showingWebsiteBlockingView = true
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.playfulCoral.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "globe.badge.chevron.backward")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.playfulCoral)
                }

                // Label with count
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blocked Websites")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    let count = screenTimeService.currentlyBlockedWebDomains.count
                    Text(count == 0 ? "No websites blocked" : "\(count) site\(count == 1 ? "" : "s") blocked")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var blockBrowsersRow: some View {
        HStack(spacing: 16) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.errorRed.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "safari")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.errorRed)
            }

            // Label
            VStack(alignment: .leading, spacing: 2) {
                Text("Block All Browsers")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("Safari, Chrome, Firefox, etc.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $areBrowsersBlocked)
                .labelsHidden()
                .tint(AppTheme.errorRed)
                .onChange(of: areBrowsersBlocked) { newValue in
                    if newValue {
                        screenTimeService.blockAllBrowsers()
                    } else {
                        screenTimeService.unblockAllBrowsers()
                    }
                    // Sync to paired child devices
                    Task {
                        await screenTimeService.syncWebRestrictionsToChildren()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                )
        )
    }

    var adultContentStatusRow: some View {
        HStack(spacing: 16) {
            // Icon container with shield
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }

            // Label
            VStack(alignment: .leading, spacing: 2) {
                Text("Adult Content Blocked")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("Always protected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }

            Spacer()

            // Status checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - New Settings Rows

    var editChildNameRow: some View {
        Button(action: {
            showingEditChildName = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Child's Name")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(modeManager.deviceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var changePINRow: some View {
        Button(action: {
            showingChangePIN = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.sunnyYellow.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "lock.rotation")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.sunnyYellow)
                }

                Text("Change PIN")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var notificationSettingsRow: some View {
        Button(action: {
            showingNotificationSettings = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.playfulCoral.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "bell.badge")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.playfulCoral)
                }

                Text("Notifications")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var helpSupportRow: some View {
        Link(destination: URL(string: "https://screentimerewards.app/support")!) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }

                Text("Help & Support")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    var aboutRow: some View {
        Button(action: {
            showingAbout = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.brandedText(for: colorScheme).opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("About")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Version \(appVersion)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
            .environmentObject(SubscriptionManager.shared)
    }
}
