import SwiftUI
import CoreData

@main
struct ScreenTimeRewardsApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel = AppUsageViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(viewModel)  // Task 0: Inject shared view model
        }
    }
}