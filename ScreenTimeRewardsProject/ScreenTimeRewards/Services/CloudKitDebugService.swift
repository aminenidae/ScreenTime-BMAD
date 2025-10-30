#if DEBUG
import CloudKit
import SwiftUI
import Combine
import CoreData

@MainActor
class CloudKitDebugService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String?
    @Published var localDeviceCount: Int = 0
    @Published var localDevices: [String] = []

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let persistenceController = PersistenceController.shared

    func checkStatus() async {
        do {
            accountStatus = try await container.accountStatus()
            isAvailable = (accountStatus == .available)

            #if DEBUG
            print("[CloudKit] Account status: \(statusString)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            print("[CloudKit] Error: \(error)")
        }
    }

    func checkLocalDevices() {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()

        do {
            let devices = try context.fetch(fetchRequest)
            localDeviceCount = devices.count
            localDevices = devices.map { device in
                let id = device.deviceID ?? "nil"
                let name = device.deviceName ?? "nil"
                let type = device.deviceType ?? "nil"
                let parentID = device.parentDeviceID ?? "nil"
                return "ID: \(id), Name: \(name), Type: \(type), ParentID: \(parentID)"
            }

            #if DEBUG
            print("[CloudKit Debug] Found \(localDeviceCount) devices in Core Data")
            for deviceInfo in localDevices {
                print("[CloudKit Debug]   - \(deviceInfo)")
            }

            // Check for child devices specifically
            let childCount = devices.filter { $0.deviceType == "child" }.count
            let parentCount = devices.filter { $0.deviceType == "parent" }.count
            print("[CloudKit Debug] Summary: \(parentCount) parent(s), \(childCount) child(ren)")
            #endif
        } catch {
            errorMessage = "Failed to fetch local devices: \(error.localizedDescription)"
            print("[CloudKit Debug] Error: \(error)")
        }
    }

    func queryCloudKitDirectly() async {
        #if DEBUG
        print("[CloudKit Debug] ===== Querying CloudKit Directly =====")
        #endif

        do {
            let database = container.privateCloudDatabase

            // Use a predicate on a custom field instead of recordName
            // Query for any deviceType (which is queryable)
            let predicate = NSPredicate(format: "CD_deviceType != %@", "")
            let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)

            // Don't sort by anything to avoid using system fields
            query.sortDescriptors = nil

            #if DEBUG
            print("[CloudKit Debug] Executing query for CD_RegisteredDevice...")
            print("[CloudKit Debug] Using predicate: CD_deviceType != ''")
            #endif

            let results = try await database.records(matching: query)

            #if DEBUG
            print("[CloudKit Debug] Query returned \(results.matchResults.count) records")
            for (recordID, result) in results.matchResults {
                switch result {
                case .success(let record):
                    let deviceID = record["CD_deviceID"] as? String ?? "nil"
                    let deviceType = record["CD_deviceType"] as? String ?? "nil"
                    let parentID = record["CD_parentDeviceID"] as? String ?? "nil"
                    print("[CloudKit Debug]   - \(recordID.recordName): type=\(deviceType), deviceID=\(deviceID), parentID=\(parentID)")
                case .failure(let error):
                    print("[CloudKit Debug]   - Error fetching \(recordID): \(error)")
                }
            }
            #endif

            errorMessage = "✅ Found \(results.matchResults.count) records in CloudKit"
        } catch {
            errorMessage = "❌ CloudKit query failed: \(error.localizedDescription)"
            #if DEBUG
            print("[CloudKit Debug] Query error: \(error)")
            if let ckError = error as? CKError {
                print("[CloudKit Debug] CKError code: \(ckError.code.rawValue)")
                print("[CloudKit Debug] CKError domain: \(ckError.errorCode)")
            }
            #endif
        }
    }

    func cleanupDuplicateDevices() {
        #if DEBUG
        print("[CloudKit Debug] ===== Cleaning Up Duplicate Devices =====")
        #endif

        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()

        do {
            let devices = try context.fetch(fetchRequest)
            var seenIDs = Set<String>()
            var toDelete: [RegisteredDevice] = []

            for device in devices {
                if let deviceID = device.deviceID {
                    if seenIDs.contains(deviceID) {
                        // Duplicate found
                        toDelete.append(device)
                        #if DEBUG
                        print("[CloudKit Debug] Marking duplicate for deletion: \(deviceID)")
                        #endif
                    } else {
                        seenIDs.insert(deviceID)
                    }
                }
            }

            for device in toDelete {
                context.delete(device)
            }

            if !toDelete.isEmpty {
                try context.save()
                #if DEBUG
                print("[CloudKit Debug] ✅ Deleted \(toDelete.count) duplicate device(s)")
                #endif
                errorMessage = "✅ Deleted \(toDelete.count) duplicate device(s)"
            } else {
                #if DEBUG
                print("[CloudKit Debug] No duplicates found")
                #endif
                errorMessage = "No duplicates found"
            }

            // Refresh the list
            checkLocalDevices()
        } catch {
            errorMessage = "❌ Failed to cleanup: \(error.localizedDescription)"
            #if DEBUG
            print("[CloudKit Debug] Cleanup error: \(error)")
            #endif
        }
    }

    var statusString: String {
        switch accountStatus {
        case .couldNotDetermine: return "Could Not Determine"
        case .available: return "Available"
        case .restricted: return "Restricted"
        case .noAccount: return "No iCloud Account"
        case .temporarilyUnavailable: return "Temporarily Unavailable"
        @unknown default: return "Unknown"
        }
    }
}

struct CloudKitDebugView: View {
    @StateObject private var debug = CloudKitDebugService()
    @StateObject private var schemaInit = CloudKitSchemaInitializer()

    var body: some View {
        List {
            Section("CloudKit Status") {
                HStack {
                    Text("Account Status")
                    Spacer()
                    Text(debug.statusString)
                        .foregroundColor(debug.isAvailable ? .green : .red)
                }

                if let error = debug.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("Local Core Data") {
                HStack {
                    Text("Registered Devices")
                    Spacer()
                    Text("\(debug.localDeviceCount)")
                        .foregroundColor(.blue)
                }

                ForEach(debug.localDevices, id: \.self) { deviceInfo in
                    Text(deviceInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Schema Initialization") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(schemaInit.status)
                        .font(.caption)
                        .foregroundColor(schemaInit.status.contains("✅") ? .green : .primary)

                    if let error = schemaInit.error {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Button("Initialize CloudKit Schema") {
                    Task {
                        await schemaInit.initializeSchema()
                    }
                }
                .disabled(schemaInit.isInitializing)

                Button("Create Dummy Records (Alternative)") {
                    schemaInit.createDummyRecords()
                }
                .disabled(schemaInit.isInitializing)

                Button("Cleanup Dummy Records") {
                    schemaInit.cleanupDummyRecords()
                }
                .disabled(schemaInit.isInitializing)
            }

            Section("Actions") {
                Button("Check CloudKit Status") {
                    Task {
                        await debug.checkStatus()
                    }
                }

                Button("Check Local Devices") {
                    debug.checkLocalDevices()
                }

                Button("Query CloudKit Directly") {
                    Task {
                        await debug.queryCloudKitDirectly()
                    }
                }

                Button("Cleanup Duplicate Devices") {
                    debug.cleanupDuplicateDevices()
                }
            }

            Section("Instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Initialize CloudKit Schema")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text("   Click 'Initialize CloudKit Schema' button above")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("2. Wait for completion")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 4)
                    Text("   Wait 30-60 seconds for schema to sync to CloudKit")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("3. Check CloudKit Dashboard")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 4)
                    Text("   Queries should now work in CloudKit Dashboard")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("CloudKit Debug")
        .onAppear {
            Task {
                await debug.checkStatus()
                debug.checkLocalDevices()
            }
        }
    }
}
#endif