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
    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel = AppUsageViewModel()
    @StateObject private var sessionManager = SessionManager.shared

    // Check if user has completed one-time setup
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedSetup {
                    // Setup completed - show normal app flow
                    mainAppView
                } else {
                    // First launch - show setup flow
                    setupFlowView
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .environmentObject(viewModel)
            .environmentObject(sessionManager)
        }
    }

    // MARK: - Setup Flow View

    private var setupFlowView: some View {
        SetupFlowView()
    }

    // MARK: - Main App View

    private var mainAppView: some View {
        Group {
            switch sessionManager.currentMode {
            case .none:
                ModeSelectionView()
            case .parent:
                MainTabView()
            case .child:
                ChildModeView()
            }
        }
    }
}
