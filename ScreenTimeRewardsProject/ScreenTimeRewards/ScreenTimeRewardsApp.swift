//
//  ScreenTimeRewardsApp.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-10-14.
//

import SwiftUI
import CoreData

@main
struct ScreenTimeRewardsApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}