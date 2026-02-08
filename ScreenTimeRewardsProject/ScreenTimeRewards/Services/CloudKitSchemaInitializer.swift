//
//  CloudKitSchemaInitializer.swift
//  ScreenTimeRewards
//
//  Force CloudKit schema initialization
//

import Foundation
import CoreData
import CloudKit
import Combine

#if DEBUG
@MainActor
class CloudKitSchemaInitializer: ObservableObject {
    @Published var status: String = "Not initialized"
    @Published var isInitializing: Bool = false
    @Published var error: String?

    private let container = PersistenceController.shared.container

    /// Initialize CloudKit schema by exporting Core Data model
    func initializeSchema() async {
        status = "Starting schema initialization..."
        isInitializing = true
        error = nil

        print("[Schema] ===== CloudKit Schema Initialization =====")

        do {
            // Method 1: Use initializeCloudKitSchema (iOS 14+)
            status = "Exporting schema to CloudKit..."
            print("[Schema] Calling initializeCloudKitSchema()...")

            try await container.initializeCloudKitSchema()

            status = "✅ Schema exported successfully!"
            print("[Schema] ✅ Schema initialization complete")
            print("[Schema] CloudKit should now have queryable indexes")
            print("[Schema] Wait 30-60 seconds, then check CloudKit Dashboard")

        } catch let error as NSError {
            self.error = error.localizedDescription
            status = "❌ Schema initialization failed"
            print("[Schema] ❌ Error: \(error)")
            print("[Schema] Error code: \(error.code)")
            print("[Schema] Error domain: \(error.domain)")
            print("[Schema] User info: \(error.userInfo)")
        }

        isInitializing = false
    }

    /// Alternative: Create dummy records to force schema creation
    func createDummyRecords() {
        status = "Creating dummy records..."
        print("[Schema] Creating dummy records to trigger schema export...")

        let context = container.viewContext

        // Create dummy RegisteredDevice
        let device = RegisteredDevice(context: context)
        device.deviceID = "schema-init-dummy-\(UUID().uuidString)"
        device.deviceName = "Schema Initializer"
        device.deviceType = "dummy"
        device.registrationDate = Date()
        device.isActive = false

        // Create dummy AppConfiguration
        let config = AppConfiguration(context: context)
        config.logicalID = "schema-init-dummy-\(UUID().uuidString)"
        config.displayName = "Schema Initializer"
        config.category = "Dummy"
        config.pointsPerMinute = 0
        config.isEnabled = false

        // Create dummy UsageRecord
        let usage = UsageRecord(context: context)
        usage.recordID = "schema-init-dummy-\(UUID().uuidString)"
        usage.displayName = "Schema Initializer"
        usage.sessionStart = Date()
        usage.totalSeconds = 0

        // Create dummy DailySummary
        let summary = DailySummary(context: context)
        summary.summaryID = "schema-init-dummy-\(UUID().uuidString)"
        summary.date = Date()
        summary.totalLearningSeconds = 0

        do {
            try context.save()
            status = "✅ Dummy records created and saved"
            print("[Schema] ✅ Dummy records saved to Core Data")
            print("[Schema] CloudKit sync should export schema automatically")
            print("[Schema] Wait 30-60 seconds for sync to complete")
        } catch {
            self.error = error.localizedDescription
            status = "❌ Failed to create dummy records"
            print("[Schema] ❌ Error saving dummy records: \(error)")
        }
    }

    /// Clean up dummy records
    func cleanupDummyRecords() {
        status = "Cleaning up dummy records..."
        print("[Schema] Removing dummy records...")

        let context = container.viewContext

        // Fetch and delete all dummy records
        let deviceRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        deviceRequest.predicate = NSPredicate(format: "deviceType == %@", "dummy")

        let configRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        configRequest.predicate = NSPredicate(format: "category == %@", "Dummy")

        do {
            let devices = try context.fetch(deviceRequest)
            let configs = try context.fetch(configRequest)

            for device in devices {
                context.delete(device)
            }
            for config in configs {
                context.delete(config)
            }

            try context.save()
            status = "✅ Dummy records cleaned up"
            print("[Schema] ✅ Dummy records deleted")
        } catch {
            self.error = error.localizedDescription
            status = "❌ Failed to cleanup dummy records"
            print("[Schema] ❌ Error cleaning up: \(error)")
        }
    }
}
#endif
