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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(viewModel)
                .environmentObject(sessionManager)
                .environmentObject(subscriptionManager)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // Refresh usage data from extension when app becomes active
                print("[ScreenTimeRewardsApp] 🔄 App became active - refreshing extension data")
                Task { @MainActor in
                    ScreenTimeService.shared.refreshFromExtension()

                    // Restart polling timer when app comes to foreground (if monitoring is active)
                    if ScreenTimeService.shared.isMonitoring {
                        ScreenTimeService.shared.startUsagePolling()
                    }
                }
            } else if newPhase == .background {
                // Stop polling when app goes to background to save battery
                print("[ScreenTimeRewardsApp] 🌙 App went to background - stopping polling timer")
                Task { @MainActor in
                    ScreenTimeService.shared.stopUsagePolling()
                }
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
