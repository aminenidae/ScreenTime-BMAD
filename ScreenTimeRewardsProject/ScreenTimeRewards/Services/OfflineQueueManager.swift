import CloudKit
import CoreData
import Combine

@MainActor
class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()

    @Published var queuedOperationsCount: Int = 0

    private let persistenceController = PersistenceController.shared
    private let maxRetries = 3

    func enqueueOperation(
        operation: String,
        payload: [String: Any]
    ) throws {
        let context = persistenceController.container.viewContext

        let item = SyncQueueItem(context: context)
        item.queueID = UUID().uuidString
        item.operation = operation
        item.payloadJSON = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        item.createdAt = Date()
        item.retryCount = 0
        item.status = "queued"

        try context.save()

        updateQueueCount()

        print("[Queue] Enqueued: \(operation)")
    }

    func processQueue() async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<SyncQueueItem> = SyncQueueItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "status == %@", "queued")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        guard let items = try? context.fetch(fetchRequest), !items.isEmpty else {
            return
        }

        print("[Queue] Processing \(items.count) items")

        for item in items {
            item.status = "processing"
            item.lastAttempt = Date()

            do {
                try await processItem(item)
                context.delete(item)  // Success - remove from queue
            } catch {
                item.retryCount += 1
                item.status = item.retryCount >= maxRetries ? "failed" : "queued"
                print("[Queue] Item failed: \(error.localizedDescription)")
            }

            try? context.save()
        }

        updateQueueCount()
    }

    private func processItem(_ item: SyncQueueItem) async throws {
        guard let payloadJSON = item.payloadJSON,
              let payloadData = Data(base64Encoded: payloadJSON),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw NSError(domain: "Queue", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid payload"])
        }

        switch item.operation {
        case "upload_usage":
            // Process usage upload
            print("[Queue] Processing usage upload")
            // In a real implementation, we would trigger a sync of usage records
            break
        case "download_config":
            // Process config download
            print("[Queue] Processing config download")
            // Download and apply parent configurations
            let configurations = try await CloudKitSyncService.shared.downloadParentConfiguration()
            print("[Queue] Downloaded \(configurations.count) configurations")
            break
        case "send_command":
            // Process command
            print("[Queue] Processing send command")
            // In a real implementation, we would send a command to another device
            break
        default:
            throw NSError(domain: "Queue", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown operation"])
        }
    }

    private func updateQueueCount() {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<SyncQueueItem> = SyncQueueItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "status == %@", "queued")

        queuedOperationsCount = (try? context.count(for: fetchRequest)) ?? 0
    }
}