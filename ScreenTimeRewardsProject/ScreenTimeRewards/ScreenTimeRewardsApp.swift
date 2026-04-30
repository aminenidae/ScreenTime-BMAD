//
//  ScreenTimeRewardsApp.swift
//  ScreenTimeRewards
//
//  Option D: Updated app entry point
//  Routes to setup flow or main app based on completion status
//

import SwiftUI
import CoreData

@main
struct ScreenTimeRewardsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel = AppUsageViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var modeManager = DeviceModeManager.shared

    init() {
        // Handle reinstall - clear PIN if app was reinstalled
        // Must happen before any PIN checks
        ParentPINService.shared.handleReinstallIfNeeded()

        // Perform streak migration if needed
        Task { @MainActor in
            await StreakMigrationService.shared.performMigrationIfNeeded()
        }

        // DEBUG: Check pairing context on startup
        #if DEBUG
        print("🔍 [STARTUP] Pairing Context Check:")
        print("   - Parent Zone ID: \(UserDefaults.standard.string(forKey: "parentSharedZoneID") ?? "❌ NOT SET")")
        print("   - Parent Zone Owner: \(UserDefaults.standard.string(forKey: "parentSharedZoneOwner") ?? "❌ NOT SET")")
        print("   - Parent Root Record: \(UserDefaults.standard.string(forKey: "parentSharedRootRecordName") ?? "❌ NOT SET")")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LaunchScreenView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(viewModel)
                .environmentObject(sessionManager)
                .environmentObject(subscriptionManager)
                .environmentObject(modeManager)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // Refresh usage data from extension when app becomes active
                print("[ScreenTimeRewardsApp] 🔄 App became active - refreshing extension data")

                // Refresh battery snapshot in App Group so the extension's next log
                // line correlates threshold-events with current charge state.
                AppDelegate.persistBatterySnapshot()

                // MONITORING RECOVERY: If monitoring should be active but isn't registered
                // with iOS, restart it. Smart threshold filtering in scheduleActivity()
                // prevents catch-up floods, making this safe to call on every foreground.
                ScreenTimeService.shared.checkMonitoringHealth()

                // HEARTBEAT GAP DETECTION: If monitoring should be active but extension
                // hasn't fired in >5 minutes, log the gap for diagnostics
                if let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared"),
                   defaults.bool(forKey: "wasMonitoringActive") {
                    let lastHeartbeat = defaults.double(forKey: "extension_heartbeat")
                    if lastHeartbeat > 0 {
                        let gapSeconds = Date().timeIntervalSince1970 - lastHeartbeat
                        if gapSeconds > 300 { // 5 minutes
                            let gapMinutes = Int(gapSeconds / 60)
                            let hbDate = Date(timeIntervalSince1970: lastHeartbeat)
                            let formatter = DateFormatter()
                            formatter.dateFormat = "HH:mm:ss"
                            let hbString = formatter.string(from: hbDate)

                            let lcFormatter = DateFormatter()
                            lcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            let timestamp = lcFormatter.string(from: Date())
                            let entry = "[\(timestamp)] EXTENSION_GAP — no heartbeat for \(gapMinutes)m (last: \(hbString))\n"

                            var log = defaults.string(forKey: "monitoring_lifecycle_log") ?? ""
                            log.append(entry)
                            if log.utf8.count > 100_000 {
                                let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
                                let kept = lines.suffix(400)
                                log = kept.joined(separator: "\n") + "\n"
                            }
                            defaults.set(log, forKey: "monitoring_lifecycle_log")
                        }
                    }
                }

                Task { @MainActor in
                    ScreenTimeService.shared.refreshFromExtension()
                }

                // Analytics — once-per-day heartbeat. Idempotent, keyed off
                // calendar date in UserDefaults. Refreshes user-properties first
                // so tier / paired_status are current on the event.
                Task { @MainActor in
                    AppAnalytics.shared.refreshDeviceModeUserProperty()
                    AppAnalytics.shared.refreshSubscriptionUserProperties()
                    AppAnalytics.shared.refreshPairedStatusUserProperty()

                    let learningCount = viewModel.appUsages.filter { $0.category == .learning }.count
                    let rewardCount = viewModel.appUsages.filter { $0.category == .reward }.count
                    AppAnalytics.shared.refreshAppCountUserProperties(
                        learning: learningCount,
                        reward: rewardCount
                    )

                    AppAnalytics.shared.trackDailyActiveIfNeeded(
                        learningMinutesToday: 0,
                        rewardMinutesToday: 0,
                        learningAppsCount: learningCount,
                        rewardAppsCount: rewardCount
                    )
                }

                // Ensure extension has latest goal configs (critical for shield unlock to work)
                Task { @MainActor in
                    ScreenTimeService.shared.syncGoalConfigsToExtension()
                    print("[ScreenTimeRewardsApp] 📋 Synced goal configs to extension")
                }

                // Check if extension unlocked any apps while main app was closed
                Task { @MainActor in
                    BlockingCoordinator.shared.checkExtensionUnlockState()
                    print("[ScreenTimeRewardsApp] 🔓 Checked extension unlock state")
                }

                // Start background sync as safety net for missed Darwin notifications
                ScreenTimeService.shared.startBackgroundSync()
                print("[ScreenTimeRewardsApp] 🔄 Started background sync timer (5min polling)")

                // Initialize StreakService to ensure midnight timer is running
                let _ = StreakService.shared
                print("[ScreenTimeRewardsApp] 🔥 StreakService initialized")

                // Start periodic refresh for blocking states (downtime, daily limits, etc.)
                BlockingCoordinator.shared.startPeriodicRefresh()
                print("[ScreenTimeRewardsApp] ⏱️ Started BlockingCoordinator periodic refresh")

                // Initialize real-time sync coordinator (listens for shield changes, throttles syncs)
                let _ = RealTimeSyncCoordinator.shared
                print("[ScreenTimeRewardsApp] 📡 RealTimeSyncCoordinator initialized")

                // Set up CloudKit database subscriptions for real-time push notifications
                Task {
                    await CloudKitSyncService.shared.setupDatabaseSubscriptions()
                    print("[ScreenTimeRewardsApp] 📡 CloudKit database subscriptions configured")
                }

                // Sync parent zone info to App Group for extension CloudKit access
                // This ensures the extension can sync directly to parent's zone
                if modeManager.isChildDevice {
                    // First, migrate any existing pairing (for devices paired before this feature)
                    DevicePairingService.shared.migrateExistingPairingToAppGroup()

                    // Then sync current zone info (refreshes in case parent changed)
                    DevicePairingService.shared.syncParentZoneInfoToAppGroup()
                    print("[ScreenTimeRewardsApp] 📡 Synced parent zone info to App Group for extension")

                    // Refresh parent subscription status (detect tier changes/expiration)
                    Task {
                        await SubscriptionManager.shared.refreshParentSubscriptionIfNeeded()
                        print("[ScreenTimeRewardsApp] 🔄 Refreshed parent subscription status")
                    }

                    // Refresh hasFullAccess so the LimitedModeBanner reflects the current
                    // paired+subscribed state on foreground, not just after a 24h BGTask.
                    Task {
                        await ChildBackgroundSyncService.shared.verifyParentSubscription()
                        print("[ScreenTimeRewardsApp] 🔄 Refreshed hasFullAccess (banner state)")
                    }

                    // Detect orphaned parent zone (e.g., parent switched iCloud post-pair).
                    // Sets needsReconnect so the banner routes Connect → fresh scan flow.
                    Task {
                        await ChildBackgroundSyncService.shared.verifyPairedZoneReachable()
                    }

                    // Process any pending CloudKit syncs that failed in the extension
                    // Extension may timeout on sync; main app retries as backup
                    Task {
                        await CloudKitSyncService.shared.processExtensionRetryQueue()
                        print("[ScreenTimeRewardsApp] 📡 Processed extension CloudKit retry queue")
                    }
                }

                // Sync app configurations to CloudKit for paired child devices
                // This ensures existing apps sync to parent dashboard on app open
                if modeManager.isChildDevice,
                   !DevicePairingService.shared.getPairedParents().isEmpty {
                    Task {
                        // FIRST: Process any pending configuration commands from parent
                        // Must happen BEFORE uploading configs, otherwise we overwrite parent's changes!
                        do {
                            let commandCount = try await ChildConfigCommandProcessor.shared.processPendingCommands()
                            if commandCount > 0 {
                                print("[ScreenTimeRewardsApp] ✅ Processed \(commandCount) config command(s) from parent")
                            }
                        } catch {
                            print("[ScreenTimeRewardsApp] ⚠️ Failed to process config commands: \(error.localizedDescription)")
                        }

                        // THEN: Backfill AppConfiguration entities from existing persisted apps
                        // This handles apps configured before this sync feature was added
                        await ScreenTimeService.shared.backfillAppConfigurationsForCloudKit()

                        // Upload app configurations to CloudKit (now includes any parent changes)
                        do {
                            try await CloudKitSyncService.shared.uploadAppConfigurationsToParent()
                            print("[ScreenTimeRewardsApp] ✅ Synced app configurations to parent")
                        } catch {
                            print("[ScreenTimeRewardsApp] ⚠️ Failed to sync app configs: \(error.localizedDescription)")
                        }

                        // Also upload shield states (blocked/unlocked status)
                        do {
                            try await CloudKitSyncService.shared.uploadShieldStatesToParent()
                            print("[ScreenTimeRewardsApp] ✅ Synced shield states to parent")
                        } catch {
                            print("[ScreenTimeRewardsApp] ⚠️ Failed to sync shield states: \(error.localizedDescription)")
                        }

                        // Upload daily usage history (last 30 days)
                        do {
                            try await CloudKitSyncService.shared.uploadDailyUsageHistoryToParent()
                            print("[ScreenTimeRewardsApp] ✅ Synced daily usage history to parent")
                        } catch {
                            print("[ScreenTimeRewardsApp] ⚠️ Failed to sync usage history: \(error.localizedDescription)")
                        }
                    }
                }

            case .background, .inactive:
                // Lock parent session when app goes to background on child device
                // This forces PIN re-entry when parent mode is accessed again
                if modeManager.isChildDevice && sessionManager.currentMode == .parent {
                    sessionManager.exitToSelection()
                    #if DEBUG
                    print("[ScreenTimeRewardsApp] 🔒 Locked parent session - returning to mode selection")
                    #endif
                }

                // Lock parent device dashboard when app goes to background
                // This forces PIN re-entry when the app is re-opened
                if modeManager.isParentDevice && sessionManager.isParentDeviceAuthenticated {
                    sessionManager.lockParentDevice()
                    #if DEBUG
                    print("[ScreenTimeRewardsApp] 🔒 Locked parent device dashboard - PIN required on next access")
                    #endif
                }

                // Stop periodic refresh when app goes to background
                BlockingCoordinator.shared.stopPeriodicRefresh()
                print("[ScreenTimeRewardsApp] ⏸️ Stopped BlockingCoordinator periodic refresh")

                // Stop background sync to save resources
                ScreenTimeService.shared.stopBackgroundSync()
                print("[ScreenTimeRewardsApp] ⏸️ Stopped background sync timer")

            @unknown default:
                break
            }
        }
    }
}

struct RootView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    /// Observe paired-parent verification state so the launch gate re-renders when
    /// hasFullAccess flips after CloudKit/Firebase confirms the parent's subscription.
    /// Without this, effectiveHasAccess wouldn't trigger a SwiftUI update when only
    /// the syncService side of the OR changes.
    @ObservedObject private var syncService = ChildBackgroundSyncService.shared
    @AppStorage("hasCompletedParentOnboarding") private var parentComplete = false
    @AppStorage("hasCompletedChildOnboarding") private var childComplete = false

    private var hasCompletedOnboarding: Bool {
        parentComplete || childComplete
    }

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingFlowView()
            } else if modeManager.needsDeviceSelection {
                DeviceSelectionView()
            } else if modeManager.isChildDevice && !subscriptionManager.effectiveHasAccess {
                // effectiveHasAccess includes ChildBackgroundSyncService.hasFullAccess,
                // which is restored from cache on launch. Prevents the "Subscription
                // Required" flash a child device used to show in the gap between
                // RevenueCat reporting no entitlement and the paired-parent CloudKit
                // verification resolving.
                SubscriptionLockoutView()
            } else if modeManager.isParentDevice {
                ParentDeviceAuthView()  // Requires PIN authentication before showing dashboard
            } else if modeManager.isChildDevice {
                Group {
                    switch sessionManager.currentMode {
                    case .none:
                        ModeSelectionView()
                    case .parent:
                        ParentModeContainer()
                    case .child:
                        ChildModeView()
                    }
                }
            } else {
                ModeSelectionView()
            }
        }
    }
}
