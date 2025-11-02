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
    
    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel = AppUsageViewModel()
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var modeManager = DeviceModeManager.shared

    // Check if user has completed one-time setup
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(viewModel)
                .environmentObject(sessionManager)
        }
    }
}

struct RootView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some View {
        Group {
            if modeManager.needsDeviceSelection {
                DeviceSelectionView()
            } else if modeManager.isParentDevice {
                ParentRemoteDashboardView()  // NEW - Will be implemented in Phase 3
            } else if modeManager.isChildDevice {
                // Existing flow
                if !hasCompletedSetup {
                    SetupFlowView()
                } else {
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
                }
            }
        }
    }
}