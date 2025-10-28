import SwiftUI

struct ChildModeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    
    var body: some View {
        NavigationView {
            ChildDashboardView()
                .environmentObject(viewModel)
                .navigationTitle("Child Dashboard")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Exit") {
                            sessionManager.exitToSelection()
                        }
                        .foregroundColor(.blue)
                    }
                }
        }
        .navigationViewStyle(.stack)  // Add this to fix iPad layout issue
    }
}

struct ChildModeView_Previews: PreviewProvider {
    static var previews: some View {
        ChildModeView()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}