import SwiftUI

struct SyncStatusIndicatorView: View {
    @ObservedObject var syncService: CloudKitSyncService
    
    var body: some View {
        HStack {
            Circle()
                .fill(syncStatusColor)
                .frame(width: 10, height: 10)
            
            Text(syncStatusText)
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status: \(syncStatusText)")
    }
    
    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .idle:
            return .gray
        case .syncing:
            return .yellow
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private var syncStatusText: String {
        switch syncService.syncStatus {
        case .idle:
            return "Sync idle"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Synced"
        case .error:
            return "Sync error"
        }
    }
}

struct SyncStatusIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        let syncService = CloudKitSyncService.shared
        
        return Group {
            SyncStatusIndicatorView(syncService: syncService)
                .previewLayout(.sizeThatFits)
                .padding()
                .previewDisplayName("Default")
            
            SyncStatusIndicatorView(syncService: syncService)
                .environment(\.colorScheme, .dark)
                .previewLayout(.sizeThatFits)
                .padding()
                .previewDisplayName("Dark Mode")
        }
    }
}