#if DEBUG
import CloudKit
import SwiftUI
import Combine

class CloudKitDebugService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String?

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")

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

            Section {
                Button("Check Status") {
                    Task {
                        await debug.checkStatus()
                    }
                }
            }
        }
        .navigationTitle("CloudKit Debug")
        .onAppear {
            Task {
                await debug.checkStatus()
            }
        }
    }
}
#endif