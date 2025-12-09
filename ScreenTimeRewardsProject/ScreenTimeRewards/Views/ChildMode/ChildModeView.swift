import SwiftUI

/// Main entry point for Child Mode
/// Shows the Time Bank dashboard directly (no challenge routing)
struct ChildModeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ChildDashboardView()
                .environmentObject(viewModel)
                .environmentObject(sessionManager)
        }
        .navigationViewStyle(.stack)
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
