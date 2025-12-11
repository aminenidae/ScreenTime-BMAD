import SwiftUI

/// Main entry point for Child Mode
/// Now uses gamified tab-based navigation with avatar, collections, and challenges
struct ChildModeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ChildModeTabView()
            .environmentObject(viewModel)
            .environmentObject(sessionManager)
            .onAppear {
                // Start monitoring when entering Child Mode
                print("[ChildModeView] Child Mode appeared - starting monitoring")
                viewModel.startMonitoring(force: false)
            }
    }
}

struct ChildModeView_Previews: PreviewProvider {
    static var previews: some View {
        ChildModeView()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
