//
//  Persistence.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-10-14.
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // No preview data needed for CloudKit entities
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            assertionFailure("Preview save failed: \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ScreenTimeRewards")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure CloudKit
            guard let description = container.persistentStoreDescriptions.first else {
                preconditionFailure("No persistent store description - Core Data model misconfigured")
            }
            
            // Enable CloudKit sync
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.screentimerewards"
            )
            
            // Enable history tracking for sync
            description.setOption(true as NSNumber,
                                 forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber,
                                 forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Log error but don't crash - Core Data may recover or work in degraded mode
                // Common causes: locked device, out of space, migration failure
                print("❌ [PersistenceController] Failed to load persistent store: \(error), \(error.userInfo)")
                #if DEBUG
                assertionFailure("Core Data store load failed: \(error)")
                #endif
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}