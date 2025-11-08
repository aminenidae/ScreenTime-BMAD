import SwiftUI

struct ParentModeContainer: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    
    var body: some View {
        #if DEBUG
        let _ = print("[ParentModeContainer] Rendering with sessionManager: \(sessionManager)")
        #endif

        // Main content - Exit button now only in Settings tab
        MainTabView(isParentMode: true)
    }
}

struct ParentModeContainer_Previews: PreviewProvider {
    static var previews: some View {
        ParentModeContainer()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
