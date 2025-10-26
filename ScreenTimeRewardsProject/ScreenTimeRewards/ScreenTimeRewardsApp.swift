import SwiftUI
import CoreData

@main
struct ScreenTimeRewardsApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel = AppUsageViewModel()
    @StateObject private var sessionManager = SessionManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                switch sessionManager.currentMode {
                case .none:
                    ModeSelectionView()
                case .parent:
                    MainTabView()
                case .child:
                    // We'll implement ChildModeView in Phase 3
                    MainTabView() // Temporary - will be replaced with ChildModeView
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .environmentObject(viewModel)
            .environmentObject(sessionManager)
        }
    }
}