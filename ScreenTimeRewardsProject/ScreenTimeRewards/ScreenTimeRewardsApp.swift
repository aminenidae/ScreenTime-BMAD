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
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // Refresh usage data from extension when app becomes active
                print("[ScreenTimeRewardsApp] 🔄 App became active - refreshing extension data")
                Task { @MainActor in
                    ScreenTimeService.shared.refreshFromExtension()
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

            case .background, .inactive:
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
            } else if modeManager.isChildDevice && !subscriptionManager.hasAccess {
                SubscriptionLockoutView()
            } else if modeManager.isParentDevice {
                ParentRemoteDashboardView()  // NEW - Will be implemented in Phase 3
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
