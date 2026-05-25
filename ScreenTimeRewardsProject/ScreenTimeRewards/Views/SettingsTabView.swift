import SwiftUI
import UIKit
import FamilyControls
import CoreData

extension Notification.Name {
    static let healSwitchToDashboard = Notification.Name("healSwitchToDashboard")
    static let healOverlayShow = Notification.Name("healOverlayShow")
    static let healOverlayUpdate = Notification.Name("healOverlayUpdate")
    static let healOverlayDismiss = Notification.Name("healOverlayDismiss")
}

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @State private var showingPairingView = false
    @State private var showingSubscriptionManagement = false
    @State private var showingPairingConfig = false
    @State private var showingWebsiteBlockingView = false

    @State private var showResetConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteAccountFinalConfirmation = false
    @State private var isDeletingAccount = false
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
    @State private var showingTrialResetConfirmation = false
    @State private var showingDiagnosticReport = false
    @State private var diagnosticReportText = ""
    @State private var showingLogExport = false

    // Silent diagnostic report upload state machine.
    @State private var diagnosticUploadState: DiagnosticUploadState = .idle
    @State private var diagnosticUploadAlertMessage: String = ""
    @State private var showingDiagnosticUploadAlert = false

    enum DiagnosticUploadState: Equatable {
        case idle
        case uploading
        case success(reportId: String)
        case failure(message: String)
    }

    @State private var firebaseFamilyResult: String = ""
    @State private var isCreatingFirebaseFamily = false

    @State private var isRefreshingTracking = false
    @State private var trackingRefreshFeedback: String?

    @State private var isHealingUsage = false
    @State private var showHealConfirm = false
    @State private var healResultMessage: String?
    @State private var healPhaseMessage = "Resetting usage data..."

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
                                deleteAccountRow
                            }

                            Text("Reset clears device settings. Delete removes all data permanently.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                                .padding(.horizontal, 4)
                        }

                        // Diagnostics Section — Debug-only. The silent diagnostic
                        // report upload sends extension logs to Firebase, which
                        // requires a privacy-policy update before it can ship in
                        // Release. Hide the entire section in Release builds.
                        #if DEBUG
                        settingsSection(title: "DIAGNOSTICS") {
                            refreshTrackingRow
                            healUsageRow
                            sendDiagnosticReportRow
                            extensionLogExportRow
                            diagnosticMappingRow
                            cleanupMappingsRow
                            extensionLogsRow
                            monitoringLogRow
                            midnightDiagnosticLogRow
                            bgtaskLogRow
                            firebaseFamilySetupRow
                        }
                        #endif

                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }

        .sheet(isPresented: $showingSubscriptionManagement) {
            SubscriptionManagementView()
                .environmentObject(subscriptionManager)
                .environmentObject(modeManager)
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

        .sheet(isPresented: $showingLogExport) {
            DiagnosticsLogExportView()
        }

        .alert("Diagnostic Report", isPresented: $showingDiagnosticUploadAlert) {
            Button("OK", role: .cancel) {
                // Reset to idle once the user dismisses success/failure UI so
                // subsequent taps fire a fresh upload (not stuck on success).
                if case .success = diagnosticUploadState {
                    diagnosticUploadState = .idle
                } else if case .failure = diagnosticUploadState {
                    diagnosticUploadState = .idle
                }
            }
        } message: {
            Text(diagnosticUploadAlertMessage)
        }

        .alert("Heal Usage Data?", isPresented: $showHealConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Heal", role: .destructive) {
                Task { await runHealUsage() }
            }
        } message: {
            Text("Clears today's recorded usage and asks iOS for the correct values. Totals will rebuild from iOS's authoritative count in a few seconds. The hourly chart will flatten to the current hour.")
        }

        .alert("Heal Complete", isPresented: Binding(
            get: { healResultMessage != nil },
            set: { if !$0 { healResultMessage = nil } }
        )) {
            Button("OK") { healResultMessage = nil }
        } message: {
            Text(healResultMessage ?? "")
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

    var deleteAccountRow: some View {
        Button(action: {
            showDeleteAccountConfirmation = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.errorRed.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if isDeletingAccount {
                        ProgressView()
                            .tint(AppTheme.errorRed)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.errorRed)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete Account & Data")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.errorRed)

                    Text("Permanently remove all data")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
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
                            .stroke(AppTheme.errorRed.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDeletingAccount)
        .alert("Delete Account & Data?", isPresented: $showDeleteAccountConfirmation) {
            Button("Continue", role: .destructive) {
                showDeleteAccountFinalConfirmation = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all your data including screen time history, challenges, streaks, pairing data, and app configurations.\n\nThis does not cancel your subscription. Manage your subscription in Settings > Apple ID > Subscriptions.")
        }
        .alert("Are you sure? This cannot be undone.", isPresented: $showDeleteAccountFinalConfirmation) {
            Button("Delete Everything", role: .destructive) {
                performAccountDeletion()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All data will be permanently removed from this device and iCloud. You can revoke Screen Time access manually in iOS Settings if desired.")
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        let isChild = modeManager.currentMode == .childDevice

        Task {
            try? await AccountDeletionService.shared.deleteAllData(isChildDevice: isChild)
            isDeletingAccount = false
            sessionManager.exitToSelection()
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

                    if subscriptionManager.isParentPairedSubscription {
                        // Child device paired with parent
                        Text("Managed by Parent")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    } else {
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

    var refreshTrackingRow: some View {
        Button(action: {
            guard !isRefreshingTracking else { return }
            isRefreshingTracking = true
            trackingRefreshFeedback = "Refreshing…"
            Task {
                await ScreenTimeService.shared.restartMonitoring(
                    reason: "settings_refresh_tracking_button",
                    force: true
                )
                await MainActor.run {
                    isRefreshingTracking = false
                    trackingRefreshFeedback = "Refreshed just now"
                }
            }
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isRefreshingTracking ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Refresh Tracking")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    if let feedback = trackingRefreshFeedback {
                        Text(feedback)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
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
                            .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var healUsageRow: some View {
        Button(action: {
            guard !isHealingUsage else { return }
            showHealConfirm = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if isHealingUsage {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.purple)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundColor(.purple)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isHealingUsage ? "Healing…" : "Heal Usage Data")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Clear today's totals and rebuild from iOS")
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
        .disabled(isHealingUsage)
    }

    private func runHealUsage() async {
        // Start heal BEFORE any UI transitions to avoid racing with
        // fullScreenCover presentation and DeviceActivityCenter calls.
        let result = await ScreenTimeService.shared.healUsageData(reason: "settings_heal_button")

        // Switch to dashboard and show spinner (lives on MainTabView).
        NotificationCenter.default.post(name: .healSwitchToDashboard, object: nil)
        NotificationCenter.default.post(name: .healOverlayShow, object: "Updating learning app usage...")

        // Track batch progress with dynamic messages.
        if let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") {
            var lastBatch = 0
            while defaults.bool(forKey: "heal_batch_active") {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let current = defaults.integer(forKey: "heal_batch_current")
                if current != lastBatch {
                    lastBatch = current
                    let total = defaults.integer(forKey: "heal_batch_total")
                    if current >= total - 1 {
                        NotificationCenter.default.post(name: .healOverlayUpdate, object: "Finishing up...")
                    } else {
                        NotificationCenter.default.post(name: .healOverlayUpdate, object: "Updating reward app usage\n(\(current) of \(total - 1))...")
                    }
                }
            }
        }

        NotificationCenter.default.post(name: .healOverlayDismiss, object: nil)
        await MainActor.run {
            healResultMessage = result
        }
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
        Link(destination: URL(string: "https://i6dev.ca/ticlock/support.html")!) {
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
                        #if DEBUG
                        .onTapGesture(count: 5) {
                            showingTrialResetConfirmation = true
                        }
                        #endif
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
        #if DEBUG
        .alert("Reset Trial?", isPresented: $showingTrialResetConfirmation) {
            Button("Reset Trial", role: .destructive) {
                subscriptionManager.resetTrialForTesting()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset your trial to 14 days. Force quit and relaunch the app after resetting.")
        }
        #endif
    }

    /// One-tap silent upload of extension logs to Firebase. No share sheet,
    /// no Files-app, no email composer — log content never surfaces to the
    /// user. On success the user gets a short reference ID (RPT-XXXXXX) to
    /// quote in support email.
    var sendDiagnosticReportRow: some View {
        Button(action: {
            startDiagnosticReportUpload()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if case .uploading = diagnosticUploadState {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppTheme.vibrantTeal)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Diagnostic Report")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(sendDiagnosticReportSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }

                Spacer()

                if case .uploading = diagnosticUploadState {
                    EmptyView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
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
        .buttonStyle(PlainButtonStyle())
        .disabled({ if case .uploading = diagnosticUploadState { return true } else { return false } }())
    }

    private var sendDiagnosticReportSubtitle: String {
        switch diagnosticUploadState {
        case .idle: return "Tap to send logs to support"
        case .uploading: return "Sending…"
        case .success(let id): return "Sent ✓  Reference: \(id)"
        case .failure: return "Tap to retry"
        }
    }

    private func startDiagnosticReportUpload() {
        guard diagnosticUploadState != .uploading else { return }
        diagnosticUploadState = .uploading

        Task {
            do {
                let reportId = try await DiagnosticReportUploader.shared.upload()
                await MainActor.run {
                    diagnosticUploadState = .success(reportId: reportId)
                    diagnosticUploadAlertMessage = "Report sent successfully.\n\nReference: \(reportId)\n\nQuote this ID when contacting support."
                    showingDiagnosticUploadAlert = true
                }
            } catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    diagnosticUploadState = .failure(message: message)
                    diagnosticUploadAlertMessage = "Couldn't send report.\n\n\(message)\n\nPlease check your connection and try again."
                    showingDiagnosticUploadAlert = true
                }
            }
        }
    }

    var extensionLogExportRow: some View {
        Button(action: {
            showingLogExport = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Extension Logs")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Full daily logs (battery + thresholds)")
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

    var diagnosticMappingRow: some View {
        Button(action: {
            // Run diagnostic and get report
            diagnosticReportText = screenTimeService.diagnosticValidateMappings()
            // Copy to clipboard for easy sharing
            UIPasteboard.general.string = diagnosticReportText
            showingDiagnosticReport = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "stethoscope")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Mapping Diagnostic")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Check for data corruption")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }

                Spacer()

                Image(systemName: "doc.on.clipboard")
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
        .alert("Diagnostic Report", isPresented: $showingDiagnosticReport) {
            Button("OK") { }
        } message: {
            Text("Report copied to clipboard!\n\nPaste it in Notes or share it for analysis.")
        }
    }

    var cleanupMappingsRow: some View {
        Button(action: {
            // Clean up stale mappings
            screenTimeService.cleanupStaleMappings()
            // Re-run diagnostic to show cleaned state
            diagnosticReportText = screenTimeService.diagnosticValidateMappings()
            UIPasteboard.general.string = diagnosticReportText
            showingDiagnosticReport = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "trash.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean Up Stale Mappings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Remove orphaned event data")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }

                Spacer()

                Image(systemName: "arrow.clockwise")
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

    var extensionLogsRow: some View {
        NavigationLink(destination: ExtensionLogViewerView()) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("View Extension Logs")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Debug DeviceActivity events")
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

    var monitoringLogRow: some View {
        NavigationLink(destination: MonitoringLifecycleLogView()) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "power.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitoring Log")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Start/stop/kill lifecycle events")
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

    var midnightDiagnosticLogRow: some View {
        NavigationLink(destination: MidnightDiagnosticLogView()) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "moon.stars")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Midnight Diagnostic")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Cross-midnight catch-up events")
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

    var bgtaskLogRow: some View {
        NavigationLink(destination: BackgroundTaskLogView()) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BGTask Log")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text("Background task scheduling & execution")
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

    #if DEBUG
    var firebaseFamilySetupRow: some View {
        Button(action: {
            guard !isCreatingFirebaseFamily else { return }
            isCreatingFirebaseFamily = true
            firebaseFamilyResult = "Creating…"
            Task {
                SubscriptionManager.shared.activateDevSubscription(tier: .family)
                // Bypass createFirebaseFamilyIfNeeded() guards (parentDevice mode) so this
                // works on any device during testing. Step 3 writes firebase_family_id.
                let result: String
                do {
                    if let existing = FirebaseValidationService.shared.currentFamilyId {
                        result = "familyId: \(existing) (existing)"
                    } else {
                        let id = try await FirebaseValidationService.shared.createFamily(subscriptionTier: .family)
                        result = "familyId: \(id)"
                    }
                } catch {
                    result = "Failed: \(error.localizedDescription)"
                }
                await MainActor.run {
                    firebaseFamilyResult = result
                    isCreatingFirebaseFamily = false
                }
            }
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Activate Test Family (Firebase)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(firebaseFamilyResult.isEmpty
                         ? "DEBUG: create Firebase family without RC purchase"
                         : firebaseFamilyResult)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                if isCreatingFirebaseFamily {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
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
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if firebaseFamilyResult.hasPrefix("familyId: ") {
                Button("Copy familyId") {
                    let id = String(firebaseFamilyResult.dropFirst("familyId: ".count))
                    UIPasteboard.general.string = id
                }
            }
        }
    }
    #endif

}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
            .environmentObject(SubscriptionManager.shared)
    }
}
